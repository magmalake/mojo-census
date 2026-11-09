"""The console's Repos page (`/repos`, sorted and filtered by its query) and
Search page (`/search?q=`), which share the repos table."""

from flare.http import Request, Response, html_escape, internal_error
from listing import (
    ListQuery,
    list_url,
    new_bit,
    parse_list_query,
    select_repos,
    sorted_by,
    with_active,
    with_estimate,
    with_new,
    with_version,
)
from model import Library, day
from search import search_score, url_decode

from console_cache import Cache
from console_layout import _age, _chips, _empty, _help, _n, _now_days, _or_dash, _page


def _th(label: String, key: String, q: ListQuery, sortable: Bool, num: Bool = True) -> String:
    """A column header; a sortable one links to the table sorted by it (the
    same column again flips the direction) and shows the current order."""
    var cls = String(" class=num") if num else String()
    if not sortable:
        return String("<th", cls, ">", label, "</th>")
    var cur = q.sort == key
    var aria = String()
    var arrow = String()
    if cur:
        aria = String(" aria-sort=ascending") if q.asc else String(" aria-sort=descending")
        arrow = String(" &#9650;") if q.asc else String(" &#9660;")
    return String(
        "<th", cls, aria, "><a href='", html_escape(list_url(sorted_by(q, key))), "'>", label, arrow, "</a></th>"
    )


def _libs_table(
    libs: List[Library], idx: List[Int], today: Int, q: ListQuery, sortable: Bool,
    c30: List[Int64] = List[Int64](),
) -> String:
    """The Repos table: the repos `idx` of `libs`, in that order. The Repos
    page sorts it by its column headers; search results are in rank order."""
    var h = String(
        "<div class=tbl><table><thead><tr><th>Repository</th>",
        _th("Lines of Mojo", "lines", q, sortable), _th("Files", "files", q, sortable),
        "<th class=num>Commits</th>", _th("Commits, 30 days", "commits30", q, sortable) if len(c30) > 0 else String(),
        "<th>Age</th><th>Created</th>",
        "<th>Mojo version</th><th>Tooling</th>", _th("Stars", "stars", q, sortable),
        _th("Forks", "forks", q, sortable), _th("Used by", "used_by", q, sortable),
        "</tr></thead><tbody>",
    )
    for i in idx:
        ref l = libs[i]
        var lines = _n(l.mojo_lines) if l.commits > 0 else String("<span class=mute>not read</span>")
        h.write(
            "<tr><td><a class=repo href='/repos/", html_escape(l.repo), "'>", html_escape(l.repo),
            "</a>", _chips(l.topics), "</td><td class=num>", lines, "</td><td class=num>",
            _n(l.mojo_files), "</td><td class=num>", l.commits, "</td>",
            String("<td class=num>", c30[i], "</td>") if len(c30) > 0 else String(), "<td>",
            _age(l.created_at, today), "</td><td>", day(l.created_at),
            "</td><td class='mono soft'>", _version_cell(l), "</td><td>",
            _or_dash(l.tooling), "</td><td class=num>", _n(l.stars), "</td><td class=num>",
            _n(l.forks), "</td><td class=num>", _n(Int64(len(l.used_by))), "</td></tr>",
        )
    h.write("</tbody></table></div>")
    return h^


def _version_cell(l: Library) -> String:
    """The detected version, or, muted, the estimate by date with a `~`."""
    if l.mojo_version.byte_length() > 0:
        return html_escape(l.mojo_version)
    if l.version_estimate.byte_length() > 0:
        return String(
            "<span class=mute title='estimated by date: the Mojo release current at its last Mojo commit'>~",
            html_escape(l.version_estimate), "</span>",
        )
    return _or_dash(String())


def _list_query(req: Request) -> ListQuery:
    return parse_list_query(
        req.query_param("sort"), req.query_param("dir"),
        url_decode(req.query_param("version")), req.query_param("active"),
        req.query_param("new"), req.query_param("estimate"),
    )


def _raw_query(req: Request) -> String:
    """The part of the URL after `?`, before any `#`; empty for none."""
    var q = req.url.find("?")
    if q < 0:
        return String()
    var s = String(req.url[byte = q + 1 :])
    var hash = s.find("#")
    if hash >= 0:
        var cut = String(s[byte=:hash])
        s = cut^
    return s^


def _filter_options(q: ListQuery, c: Cache) -> String:
    """The version families and the activity filter as links, with how many
    repos each has under the other filter; the ones in use are marked."""
    var per = Dict[String, Int]()
    var total = 0
    for i in range(len(c.libs)):
        if q.active and not c.active[i]:
            continue
        if q.new.byte_length() > 0 and c.news[i] & new_bit(q.new) == 0:
            continue
        var bucket = c.est_buckets[i] if q.estimate else c.buckets[i]
        per[bucket] = per.get(bucket, 0) + 1
        total += 1
    var h = String("<div class=filters><span class=label>Mojo version</span>")
    h.write(
        "<a class='chip", " on" if q.version.byte_length() == 0 else "", "' href='",
        html_escape(list_url(with_version(q, String()))), "'>any (", total, ")</a>",
    )
    for ref f in (c.ov.est_buckets if q.estimate else c.ov.buckets):
        var n = per.get(f, 0)
        if n == 0 and q.version != f:
            continue
        h.write(
            "<a class='chip", " on" if q.version == f else "", "' href='",
            html_escape(list_url(with_version(q, f))), "'>", html_escape(f), " (", n, ")</a>",
        )
    h.write(
        "<span class=label>Versions</span>",
        "<a class='chip", " on" if not q.estimate else "", "' href='",
        html_escape(list_url(with_estimate(q, False))), "'>detected</a>",
        "<a class='chip", " on" if q.estimate else "", "' href='",
        html_escape(list_url(with_estimate(q, True))),
        "' title='A repo with no detected version counts under the Mojo release current at its last Mojo commit'>",
        "detected + estimated by date</a>",
    )
    h.write("<span class=label>Activity</span>")
    h.write(
        "<a class='chip", " on" if not q.active else "", "' href='",
        html_escape(list_url(with_active(q, False))), "'>any</a>",
        "<a class='chip", " on" if q.active else "", "' href='",
        html_escape(list_url(with_active(q, True))), "'>active in the last year</a>",
    )
    h.write("<span class=label>First commit</span>")
    var news: List[String] = ["", "month", "last-month", "30d"]
    var titles: List[String] = ["any", "this month", "last month", "last 30 days"]
    for k in range(4):
        h.write(
            "<a class='chip", " on" if q.new == news[k] else "", "' href='",
            html_escape(list_url(with_new(q, news[k]))), "'>", titles[k], "</a>",
        )
    h.write("</div>")
    return h^


def _filter_chips(q: ListQuery) -> String:
    """The filters in use, each a chip that removes it."""
    if not q.has_filter():
        return String()
    var h = String("<div class=filters><span class=label>Filters</span>")
    if q.version.byte_length() > 0:
        h.write(
            "<a class='chip on' href='", html_escape(list_url(with_version(q, String()))),
            "' aria-label='Remove the version filter'>version ",
            html_escape(q.version), " (estimated by date too)" if q.estimate else "", " &times;</a>",
        )
    if q.active:
        h.write(
            "<a class='chip on' href='", html_escape(list_url(with_active(q, False))),
            "' aria-label='Remove the activity filter'>active in the last year &times;</a>",
        )
    if q.new.byte_length() > 0:
        var what = String("new this month")
        if q.new == "last-month":
            what = String("new last month")
        elif q.new == "30d":
            what = String("new in the last 30 days")
        h.write(
            "<a class='chip on' href='", html_escape(list_url(with_new(q, String()))),
            "' aria-label='Remove the new repos filter'>", what, " &times;</a>",
        )
    h.write("</div>")
    return h^


def repos_page(req: Request, c: Cache) raises -> Response:
    try:
        var q = _list_query(req)
        var idx = select_repos(
            q, c.lines, c.files, c.stars,
            c.est_buckets if q.estimate else c.buckets, c.active,
            c.est_families if q.estimate else c.families, c.news, c.commits30,
            c.forks, c.used_by,
        )
        var h = String(
            "<h1>Mojo repos</h1><p class=sub>Mojo repos, versions and growth, counted",
            " from GH Archive by magmalake. Not affiliated with Modular.</p>",
        )
        if len(c.libs) == 0:
            h.write(
                _empty(
                    "No repos yet",
                    "The lake is still filling. The pipelines read GH Archive an hour at a"
                    " time and write a row here for each repository they find Mojo in,"
                    " so this page fills in as they catch up.",
                )
            )
            return _page("Repos", h^, "repos")
        h.write(
            "<p class=lead><strong>", len(idx), " repo" if len(idx) == 1 else " repos",
            "</strong>", " of " if q.has_filter() else "", String(len(c.libs)) if q.has_filter() else "",
            " found in GH Archive.",
            _help(
                "h-repos", "the Repos table",
                "Size is lines of Mojo at the last commit read; age is since GitHub created the"
                " repository. Click a column to sort.",
            ),
            "</p>",
            _filter_chips(q), _filter_options(q, c),
        )
        if len(idx) == 0:
            h.write(_empty("No repos match", "No repo has all of these filters. Remove one with the chips above."))
        else:
            h.write(_libs_table(c.libs, idx, _now_days(), q, True, c.commits30))
        return _page("Repos", h^, "repos")
    except e:
        return internal_error(String(e))


def _matches(query: String, c: Cache) raises -> List[Int]:
    """The indices into `c.libs` of the repos matching `query`, best match
    first; equal matches keep the Repos order (biggest first)."""
    var hits = List[Int]()
    var scores = List[Int]()
    for i in range(len(c.libs)):
        ref l = c.libs[i]
        var sc = search_score(l.repo, l.description, query, l.topics)
        if sc > 0:
            hits.append(i)
            scores.append(sc)
    for i in range(1, len(hits)):
        var j = i
        while j > 0 and scores[j - 1] < scores[j]:
            scores.swap_elements(j - 1, j)
            hits.swap_elements(j - 1, j)
            j -= 1
    return hits^


def search(req: Request, c: Cache) raises -> Response:
    try:
        var q = String(url_decode(req.query_param("q")).strip())
        var h = String("<h1>Search</h1>")
        if q.byte_length() == 0:
            h.write(
                _empty(
                    "Search the repos",
                    "Type part of a repository name, topic or description in the box above,"
                    " for example flare or http. Names that match best come first.",
                )
            )
            return _page("Search", h^, "search")
        var hits = _matches(q, c)
        h.write(
            "<p class=lead>", len(hits), " ", "repo" if len(hits) == 1 else "repos",
            " matching &ldquo;", html_escape(q), "&rdquo; in the repository name, GitHub topics or description.</p>",
        )
        if len(hits) == 0:
            h.write(_empty("No repos match", "Try a shorter word, or part of the owner or the name."))
        else:
            h.write(_libs_table(c.libs, hits, _now_days(), _list_query(req), False))
        return _page(String("Search: ", q), h^, "search", q)
    except e:
        return internal_error(String(e))
