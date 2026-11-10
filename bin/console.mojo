"""The console: a flare app over mojo.repos, mojo.commits, mojo.migrations,
mojo.repo_stats, mojo.activity, mojo.releases, mojo.tags, mojo.repo_versions
and mojo.repo_deps.

    PORT=8080 pixi run ./build/console

Pages: `/` the overview (cards, repos per Mojo version, growth curves),
`/repos` the repos by size and age (`?sort=lines|files|stars|forks|used_by&dir=asc|desc`,
`?version=1.x`, `?active=1y`), `/search?q=` finds repos by name, GitHub topic
or description, `/migrations` the migrations to each Mojo version over time,
`/how`, `/how/optimizations` and `/how/changelog` how the census is built,
`/repos/<owner>/<name>` one repo. The data pages have JSON at `/api/...`.

The repos and the overview are computed and kept (`Cache`), and a background
thread keeps them fresh: every `CONSOLE_REFRESH_SECONDS` (default 1800) it
looks at the tables' current snapshots and, only when one moved or the UTC day
changed, builds a new `Cache` beside the old one and swaps it in. Requests
always read the current one and never wait for a build; until the first build
finishes they get a "warming up" page (503). A new build goes in only when its
data checks pass (`checks`); else the previous one stays, the failing checks
are logged and the footer says so. `/checks` shows the last run.
The per-repo data (commits, migrations, releases, activity) and the
Migrations page are read and rendered at the same time.

The look follows mlake.dev: its warm-ash neutrals, ember accent and lake
links, on the system font stack (no external fonts or scripts).
"""

from std.memory.alloc import unsafe_alloc
from std.os import getenv
from std.memory import ArcPointer
from std.time import sleep

from flare.http import (
    Handler,
    HttpServer,
    Request,
    Response,
    Router,
    ServerConfig,
    html_escape,
    redirect,
)
from flare.net import SocketAddr
from orca.civil import now
from threads import OpaquePtr, ThreadHandle

from checks import CheckRun, RepoFacts, Tops, notice, page_facts, publish, run_checks, when
from days import day_text
from model import Point, read_days, read_sources
from swap import Swap, check_due, needs_build

from console_api import index_json, overview_json, repo_json, search_json, versions_json
from console_cache import RETRY_SECS, Cache, refresh_secs
from console_how import changelog, how, optimizations
from console_layout import EDGE_CACHE, _empty, _page
from console_list import repos_page, search
from console_migrations import migrations_page
from console_overview import overview
from console_repo import repo_page


def _check(c: Cache, t: Int64) raises -> CheckRun:
    """The data checks on a new build, from what it read: each repo's numbers
    in the tables beside the ones its page shows."""
    var cut30 = Int64(c.built_day - 30) * 86_400_000_000
    var none = List[Point]()
    var repos = List[RepoFacts]()
    for i in range(len(c.libs)):
        ref l = c.libs[i]
        var page = page_facts(none, cut30)
        if l.repo in c.details:
            page = page_facts(c.details[l.repo].pts, cut30)
        repos.append(
            RepoFacts(
                l.repo, l.commits, c.commits30[i], c.history[i], l.mojo_lines, l.stars,
                Int64(len(l.used_by)), page^,
            )
        )
    var tops = Tops()
    tops.active = c.active_repos.copy()
    tops.active_commits = c.active_commits.copy()
    tops.active_lines = c.active_lines.copy()
    tops.rising = c.rising.copy()
    tops.rising_gain = c.rising_gain.copy()
    tops.rising_forks = c.rising_forks.copy()
    tops.rising_used_by = c.rising_used_by.copy()
    tops.rising_score = c.rising_score.copy()
    tops.rising_stars = c.rising_stars.copy()
    # An owner/* row is checked by its repos.
    for ref d in c.depended:
        for m in d.members:
            tops.depended.append(c.libs[m].repo)
            tops.depended_used_by.append(Int64(len(c.libs[m].used_by)))
    return CheckRun(t, c.built_at, run_checks(c.repo_rows, repos, tops))


def _look(mut sw: Swap[Cache], mut runs: Swap[CheckRun], cur: Cache, t: Int64) raises:
    """Look at the tables' snapshots and, if one moved or the day changed,
    build a new `Cache`, check it and swap it in. Raises with the old one
    still in place; a build that fails its checks is dropped (unless there is
    no other)."""
    var src = read_sources()
    var today = Int(t // 86400)
    if not needs_build(cur.ready, cur.built_day, today, src.same_as(cur.sources)):
        return
    read_days(src, day_text(Int64(today - 1)))
    var next = Cache()
    next._build(today, src^)
    next.built_at = t
    var run = _check(next, t)
    var bad = run.failed()
    if not publish(sw, next^, runs, run^, cur.built_at if cur.ready else 0):
        print(String("console: data checks failed; still serving the build from ", when(cur.built_at), "\n", bad), end="")
    elif bad.byte_length() > 0:
        print(String("console: data checks failed on the first build; serving it anyway\n", bad), end="")


@fieldwise_init
struct Shared(ImplicitlyCopyable):
    """The addresses of what the refresher and the handlers share, which live
    as long as the process."""

    var cache: Int
    """The `Swap[Cache]`."""
    var checks: Int
    """The `Swap[CheckRun]`: the last data checks."""


def _refresher(arg: OpaquePtr) -> OpaquePtr:
    """The refresher thread: the only one that reads the lake or builds a
    `Cache`, one build at a time. It uses nothing a request handler holds: each
    read opens its own catalog and S3 client, and the only thing shared with
    the handlers is the `Swap`."""
    var sh = Pointer[Shared, MutUntrackedOrigin](unsafe_from_address=Int(arg))[]
    ref sw = Pointer[Swap[Cache], MutUntrackedOrigin](unsafe_from_address=sh.cache)[]
    ref runs = Pointer[Swap[CheckRun], MutUntrackedOrigin](unsafe_from_address=sh.checks)[]
    var interval = refresh_secs()
    var checked = Int64(0)
    while True:
        try:
            var t = now()
            var cur = sw.get()
            if check_due(cur[].ready, t, checked, cur[].built_day, Int(t // 86400), interval):
                checked = t
                var started = t
                try:
                    _look(sw, runs, cur[], t)
                    if not cur[].ready:
                        print("console: first build in", now() - started, "s")
                    else:
                        print("console: looked at the tables;", now() - started, "s")
                except e:
                    # Keep serving what there is; look again soon.
                    print("console: refresh failed:", e)
                    checked = t - Int64(interval) + Int64(min(interval, RETRY_SECS))
        except e:
            print("console: refresher:", e)
        sleep(1.0)


def _warming_up() raises -> Response:
    var resp = _page(
        "Warming up",
        _empty("Warming up", "The census is reading the lake for the first time; this page reloads itself."),
        "",
    )
    resp.status = 503
    resp.reason = "Service Unavailable"
    resp.headers.set("Retry-After", "5")
    resp.headers.set("Refresh", "5")
    resp.headers.set("Cache-Control", "no-store")
    return resp^


@fieldwise_init
struct Site(Handler, Copyable):
    """One route of the console, with the shared `Swap` of `Cache`s."""

    var page: Int
    var cache: Int
    """The address of the `Swap[Cache]`, which lives as long as the process."""
    var checks: Int
    """The address of the `Swap[CheckRun]`."""

    def serve(self, req: Request) raises -> Response:
        ref sw = Pointer[Swap[Cache], MutUntrackedOrigin](unsafe_from_address=self.cache)[]
        ref runs = Pointer[Swap[CheckRun], MutUntrackedOrigin](unsafe_from_address=self.checks)[]
        if self.page == 10:
            return _checks_page(runs.get()[])
        # One reference for the whole request: a rebuild that finishes meanwhile
        # doesn't change what this page reads.
        var held = sw.get()
        ref c = held[]
        if not c.ready:
            return _warming_up()
        var resp = self._route(req, c)
        var note = notice(runs.get()[])
        if note.byte_length() > 0:
            resp = _with_notice(resp^, note)
        # A missing repo or a bad query isn't kept at the edge: Cloudflare would
        # otherwise hold it for its default TTL.
        resp.headers.set("Cache-Control", EDGE_CACHE if resp.status == 200 else "no-store")
        return resp^

    def _route(self, req: Request, c: Cache) raises -> Response:
        if self.page == 0:
            return overview(req, c)
        if self.page == 1:
            return repos_page(req, c)
        if self.page == 2:
            return search(req, c)
        if self.page == 3:
            return repo_page(req, c)
        if self.page == 4:
            return overview_json(req, c)
        if self.page == 5:
            return index_json(req, c)
        if self.page == 6:
            return search_json(req, c)
        if self.page == 8:
            return migrations_page(req, c)
        if self.page == 9:
            return versions_json(req, c)
        return repo_json(req, c)


def _checks_page(run: CheckRun) raises -> Response:
    """`/checks`: the last data checks, as text."""
    var resp = Response(status=200, reason="OK", body=List[UInt8](run.text().as_bytes()))
    resp.headers.set("Content-Type", "text/plain; charset=utf-8")
    # Never cached: it's where a failing check shows first.
    resp.headers.set("Cache-Control", "no-store")
    return resp^


def _with_notice(var resp: Response, note: String) -> Response:
    """`resp` with `note` atop its footer, when it is one of `_page`'s."""
    comptime FOOTER = "<footer><div class=wrap>"
    var html = String(StringSlice(unsafe_from_utf8=Span(resp.body)))
    var k = html.find(FOOTER)
    if k < 0:
        return resp^
    k += FOOTER.byte_length()
    var out = String(
        html[byte=:k], "<p class=notice role=status>", html_escape(note), " <a href='/checks'>Details</a></p>",
        html[byte=k:],
    )
    resp.body = List[UInt8](out.as_bytes())
    return resp^


def _moved_to_migrations(req: Request) raises -> Response:
    return redirect("/migrations", 301)


def main() raises:
    var p = unsafe_alloc[Swap[Cache]](1)
    p.unsafe_write(Swap[Cache](Cache()))
    var cache = Int(p)
    var pc = unsafe_alloc[Swap[CheckRun]](1)
    pc.unsafe_write(Swap[CheckRun](CheckRun()))
    var checks = Int(pc)
    var sh = unsafe_alloc[Shared](1)
    sh.unsafe_write(Shared(cache, checks))
    var refresher = ThreadHandle.spawn[_refresher](OpaquePtr(unsafe_from_address=Int(sh)))
    refresher.detach()
    var r = Router()
    r.get("/", Site(0, cache, checks))
    r.get("/repos", Site(1, cache, checks))
    r.get("/migrations", Site(8, cache, checks))
    r.get("/versions", _moved_to_migrations)
    r.get("/how", how)
    r.get("/how/optimizations", optimizations)
    r.get("/how/changelog", changelog)
    r.get("/search", Site(2, cache, checks))
    r.get("/repos/:owner/:name", Site(3, cache, checks))
    r.get("/api/overview", Site(4, cache, checks))
    r.get("/api/repos", Site(5, cache, checks))
    r.get("/api/versions", Site(9, cache, checks))
    r.get("/api/search", Site(6, cache, checks))
    r.get("/api/repos/:owner/:name", Site(7, cache, checks))
    r.get("/checks", Site(10, cache, checks))
    var addr = String("0.0.0.0:", getenv("PORT", "8080"))
    var server = HttpServer.bind(SocketAddr.parse(addr), ServerConfig())
    print("console on http://", addr, sep="")
    server.serve(r^)
