"""The live poller's GitHub side (#123): which census repos' default branches
moved since the last look, and the commits that moved them.

One GraphQL query asks for the heads of `HEADS_BATCH` repositories at once
(`heads_query`; 1 rate-limit point, a few seconds), so a look at every census
repo is about 13 queries. A repo whose head moved is asked for its latest
`HISTORY_N` commits with their subjects (`history_query`), and the commits
newer than the head seen before are the new ones (`new_since`). A repo seen
for the first time only records its head: its history is mojo_history's.
"""

from jscan import Range, each, field, text, timestamp_micros

comptime HEADS_BATCH = 100
comptime HISTORY_N = 30
"""Commits asked for per moved repo; a push of more is cut to these."""


def _json_string(s: String) -> String:
    """`s` as a JSON string literal."""
    var out = String('"')
    for cp in s.codepoint_slices():
        if cp == '"':
            out += '\\"'
        elif cp == "\\":
            out += "\\\\"
        elif cp == "\n":
            out += "\\n"
        else:
            out += cp
    out += '"'
    return out^


def _owner_name(repo: String) -> Tuple[String, String]:
    var slash = repo.find("/")
    if slash < 0:
        return (repo, String())
    return (String(repo[byte=:slash]), String(repo[byte = slash + 1 :]))


def _gql_string(s: String) -> String:
    """`s` as a GraphQL string literal (repo names are `[A-Za-z0-9._-]`, but
    nothing here relies on it)."""
    return _json_string(s)


def heads_query(repos: List[String]) -> String:
    """The request body asking for the default-branch head of each of `repos`
    (aliases `r0`, `r1`, ...), and the query's cost."""
    var q = String("query{rateLimit{cost remaining}")
    for i in range(len(repos)):
        var on = _owner_name(repos[i])
        q.write(
            "r", i, ":repository(owner:", _gql_string(on[0]), ",name:",
            _gql_string(on[1]), "){defaultBranchRef{target{oid}}}",
        )
    q += "}"
    return String('{"query":', _json_string(q), "}")


def history_query(repo: String, n: Int = HISTORY_N) -> String:
    """The request body asking for the latest `n` commits of `repo`'s default
    branch: sha, subject and committer time."""
    var on = _owner_name(repo)
    var q = String(
        "query{rateLimit{cost remaining}repository(owner:", _gql_string(on[0]),
        ",name:", _gql_string(on[1]), "){defaultBranchRef{target{... on Commit{",
        "history(first:", n, "){nodes{oid messageHeadline committedDate}}}}}}}",
    )
    return String('{"query":', _json_string(q), "}")


@fieldwise_init
struct Heads(Movable):
    var heads: Dict[String, String]
    """repo -> head sha, for the repos that have one (a repo gone or empty
    has none)."""
    var cost: Int
    var remaining: Int


def parse_heads(body: String, repos: List[String]) -> Heads:
    """The heads in a reply to `heads_query(repos)`. A repo GitHub couldn't
    resolve (renamed, gone, private) comes back null and is left out."""
    var out = Dict[String, String]()
    var b = body.as_bytes()
    var all = Range(0, len(b))
    var data = field(b, all, "data")
    var rl = field(b, data, "rateLimit")
    var cost = _int(text(b, field(b, rl, "cost")))
    var remaining = _int(text(b, field(b, rl, "remaining")))
    for i in range(len(repos)):
        var r = field(b, data, String("r", i))
        if not r.found():
            continue
        var oid = text(b, field(b, field(b, field(b, r, "defaultBranchRef"), "target"), "oid"))
        if oid.byte_length() > 0:
            out[repos[i]] = oid^
    return Heads(out^, cost, remaining)


def _int(s: String) -> Int:
    try:
        return Int(s)
    except:
        return -1


@fieldwise_init
struct LiveCommit(Copyable, Movable):
    var repo: String
    var sha: String
    var subject: String
    var committed_at: Int64
    """Microseconds since the epoch, the committer's time."""
    var seen_at: Int64
    """When the poller first saw it."""


def parse_history(repo: String, body: String, seen_at: Int64) -> List[LiveCommit]:
    """The commits in a reply to `history_query(repo)`, newest first."""
    var out = List[LiveCommit]()
    var b = body.as_bytes()
    var all = Range(0, len(b))
    var target = field(b, field(b, field(b, field(b, all, "data"), "repository"), "defaultBranchRef"), "target")
    for c in each(b, field(b, field(b, target, "history"), "nodes")):
        out.append(LiveCommit(
            repo,
            text(b, field(b, c, "oid")),
            text(b, field(b, c, "messageHeadline")),
            timestamp_micros(b, field(b, c, "committedDate")),
            seen_at,
        ))
    return out^


def new_since(history: List[LiveCommit], known: String) -> Tuple[List[LiveCommit], Bool]:
    """The commits of `history` (newest first) newer than `known`, oldest
    first, and whether `known` was among them. When it wasn't (a push of more
    than `HISTORY_N` commits, or a force push), all of `history` is new."""
    var out = List[LiveCommit]()
    var found = False
    for ref c in history:
        if c.sha == known:
            found = True
            break
        out.append(c.copy())
    out.reverse()
    return (out^, found)


@fieldwise_init
struct Freshness(Copyable, Movable):
    """Seconds from a commit to the poller seeing it, over some commits."""

    var n: Int
    var median_s: Int
    var p90_s: Int


def freshness(commits: List[LiveCommit], since: Int64) -> Freshness:
    """Seen-minus-committed over the commits seen at `since` or later. The
    committer's time comes before the push (a commit can be pushed days
    later), so a lag over a day is left out: that commit was old when
    pushed, not slow to arrive."""
    var lags = List[Int]()
    for ref c in commits:
        if c.seen_at < since:
            continue
        var lag = Int((c.seen_at - c.committed_at) // 1_000_000)
        if lag >= 0 and lag <= 86_400:
            lags.append(lag)
    if len(lags) == 0:
        return Freshness(0, 0, 0)
    sort(lags)
    var n = len(lags)
    return Freshness(n, lags[(n - 1) // 2], lags[min(n - 1, (n * 9) // 10)])
