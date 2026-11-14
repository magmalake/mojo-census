"""census issues.issues_of with GitHub reached through libhttp (spike,
morca #445)."""

from std.time import sleep

from http_client import github
from issues import Fetched, IssueRow, PER_PAGE, parse_issues
from jscan import micros_to_iso
from morca.civil import now
from stats import limited, state_of, wait_seconds


def issues_of_lib(repo: String, since: Int64, max_wait_s: Int, max_pages: Int) raises -> Fetched:
    """Every issue and pull request of `repo` updated at `since` or later
    (microseconds; 0 for all), oldest update first, in at most `max_pages`
    pages. Waits out rate limits for at most `max_wait_s` seconds in all
    and raises when that isn't enough."""
    var rows = List[IssueRow]()
    var calls = 0
    var waited = 0
    var remaining = -1
    var page = 1
    var attempt = 0
    var q = String("?state=all&sort=updated&direction=asc&per_page=", PER_PAGE)
    if since > 0:
        q += String("&since=", micros_to_iso(since))
    while page <= max_pages:
        var r = github(String("/repos/", repo, "/issues", q, "&page=", page))
        calls += 1
        remaining = r.remaining
        if limited(r):
            var w = wait_seconds(r, Int(now()), attempt)
            if waited + w > max_wait_s:
                raise Error(
                    repo, ": GitHub's rate limit (HTTP ", r.status,
                    ") would take ", w, " s more after ", waited, " s",
                )
            sleep(Float64(w))
            waited += w
            attempt += 1
            continue
        if r.status >= 500 and attempt < 3:
            sleep(Float64(5 * (attempt + 1)))
            waited += 5 * (attempt + 1)
            attempt += 1
            continue
        if r.status != 200:
            # Issues turned off is a 410; a repo that is gone a 404.
            return Fetched(rows^, state_of(r.status), calls, waited, remaining)
        attempt = 0
        var got = parse_issues(repo, r.body, now() * 1_000_000)
        var n = len(got)
        for ref x in got:
            rows.append(x.copy())
        if n < PER_PAGE:
            break
        page += 1
    return Fetched(rows^, String("ok"), calls, waited, remaining)
