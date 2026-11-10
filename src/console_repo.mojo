"""The console's page of one repo (`/repos/<owner>/<name>`): its title block,
lines of Mojo over time, dependencies, similar repos, stars per month,
releases and tags, migrations and latest commits."""

from flare.http import Request, Response, html_escape, internal_error, not_found
from days import day_text
from model import Library, MonthActivity, Point, day
from similar import Neighbor
from overview import tool_code, unversioned
from versions import source_label, usable

from console_cache import Cache
from console_how import ORCA_UI
from console_layout import _age, _chips, _empty, _n, _now_days, _or_dash, _page, _this_month
from console_migrations import _line_chart


comptime COMMITS_SHOWN = 50
"""How many of a repository's commits the page lists; the JSON has all."""


def _chart(points: List[Point]) -> String:
    """Lines of Mojo over time, as an SVG polyline with the area under it."""
    if len(points) < 2:
        return String(
            "<div class=card><p class=mute>Too few commits read to draw a line.</p></div>"
        )
    var w = 900
    var h = 180
    var t0 = points[0].at
    var t1 = points[len(points) - 1].at
    var top = Int64(1)
    for ref p in points:
        if p.lines > top:
            top = p.lines
    var span = max(t1 - t0, Int64(1))
    var pts = String()
    for ref p in points:
        var x = Int((p.at - t0) * Int64(w) // span)
        var y = h - Int(max(p.lines, Int64(0)) * Int64(h - 10) // top)
        pts.write(x, ",", y, " ")
    return String(
        "<div class=card><svg viewBox='-4 -4 ", w + 8, " ", h + 8,
        "' role=img aria-label='lines of Mojo over time'>",
        "<polygon fill='var(--ember)' fill-opacity='.12' points='0,", h, " ", pts, w, ",", h, "'/>",
        "<polyline fill=none stroke='var(--ember)' stroke-width=2 stroke-linejoin=round points='", pts, "'/></svg>",
        "<p class=mute>", day(t0), " to ", day(t1), "; peak ", _n(top), " lines</p></div>",
    )


comptime RELEASES_SHOWN = 30


def _stars_chart(repo_months: List[MonthActivity], all_loaded: List[String]) raises -> String:
    """Stars and forks per month from GH Archive, over the months loaded but
    the one in progress (unless it's the only one)."""
    var loaded = all_loaded.copy()
    if len(loaded) > 1 and loaded[len(loaded) - 1] == _this_month():
        _ = loaded.pop()
    var counts = Dict[String, Int]()
    var top = 1
    var total = Int64(0)
    for ref a in repo_months:
        counts[String("stars|", a.month)] = Int(a.stars)
        counts[String("forks|", a.month)] = Int(a.forks)
        top = max(top, Int(a.stars), Int(a.forks))
        total += a.stars
    var names: List[String] = ["stars", "forks"]
    return _line_chart(
        loaded, names, counts, top,
        String("Line chart: stars and forks per month"),
        String("Stars (WatchEvents) and forks per month in GH Archive, ", loaded[0], " to ", loaded[len(loaded) - 1]),
        String(
            _n(total), " stars over the months of GH Archive loaded so far (",
            len(all_loaded), "; months in between aren't loaded yet), counted from its events.",
        ),
    )


def _stat(label: String, value: String, note: String = "") -> String:
    """One tile of the title block; `value` and `note` are already escaped."""
    return String(
        "<div class=stat><b>", label, "</b><span>", value, "</span>",
        String("<small>", note, "</small>") if note.byte_length() > 0 else String(),
        "</div>",
    )


def _deps_stat(l: Library) -> String:
    """The "Depends on" tile: the Mojo libraries of the census among its
    dependencies, of how many it declares."""
    if l.declared_deps < 0:
        return _stat("Depends on", _or_dash(String()), "dependencies not read yet")
    return _stat(
        "Depends on", _n(Int64(len(l.depends_on))),
        String("Mojo libraries, of ", l.declared_deps, " declared"),
    )


def _repo_links(repos: List[String]) -> String:
    """Repos as links to their pages, comma-separated."""
    var h = String()
    for i in range(len(repos)):
        if i > 0:
            h += ", "
        h.write("<a class=repo href='/repos/", html_escape(repos[i]), "'>", html_escape(repos[i]), "</a>")
    return h^


def _deps_section(l: Library) -> String:
    """What it depends on and what depends on it, when there is any."""
    if len(l.declared) == 0 and len(l.used_by) == 0:
        return String()
    var h = String("<h2>Dependencies</h2><div class=prose>")
    if len(l.depends_on) > 0:
        h.write("<p>Depends on ", _repo_links(l.depends_on), ".</p>")
    if len(l.used_by) > 0:
        h.write("<p>Used by ", _repo_links(l.used_by), ".</p>")
    if len(l.declared) > 0:
        h.write("<p class=mute>Declared in its manifests at HEAD (toolchain left out): ")
        for i in range(len(l.declared)):
            if i > 0:
                h += ", "
            h.write("<code>", html_escape(l.declared[i]), "</code>")
        h.write(".</p>")
    h.write("</div>")
    return h^


def _short_rev(rev: String) -> String:
    return String(rev[byte=:8]) if rev.byte_length() > 8 else rev


def _similar_section(repo: String, c: Cache) -> String:
    """The repos nearest it by embedding (`similar.nearest`), with the model
    and snapshot they're from; nothing before mojo_embed has run."""
    if c.embed_snapshot < 0:
        return String()
    var h = String("<h2>Similar repos</h2>")
    var near = c.similar.get(repo, List[Neighbor]())
    if len(near) == 0:
        h.write(_empty("Not embedded yet", "mojo_embed hasn't embedded this repository's description yet."))
        return h^
    h.write(
        "<div class=tbl><table><thead><tr><th>Repo</th><th>Description</th>",
        "<th class=num>Similarity</th></tr></thead><tbody>",
    )
    for ref n in near:
        var desc = String()
        var other = c.find(n.repo)
        if other:
            desc = other.value().description
        h.write(
            "<tr><td><a class=repo href='/repos/", html_escape(n.repo), "'>", html_escape(n.repo),
            "</a></td><td class=soft>", _or_dash(desc), "</td><td class=num>",
            Int(n.score * 100 + 0.5), "%</td></tr>",
        )
    h.write(
        "</tbody></table></div><p class=mute>By the cosine of the embeddings of each repo's name, ",
        "description and topics: <code>", html_escape(c.embed_model), "</code> at <code>",
        html_escape(_short_rev(c.embed_rev)), "</code>, from snapshot ", c.embed_snapshot,
        " of mojo.repo_embeddings, which <a href='", ORCA_UI,
        "/pipelines/mojo_embed' rel=noopener>mojo_embed</a> writes.</p>",
    )
    return h^


def _version_stat(l: Library) -> String:
    """The Mojo version tile: the detected version and where it was read
    (`24.4`, from CI), else why there is none, and the estimate by date, kept
    apart from it."""
    var est = String()
    if l.version_estimate.byte_length() > 0:
        est = String("~", html_escape(l.version_estimate), " by date")
    if usable(l.mojo_version):
        var note = String("from ", html_escape(source_label(l.version_source)))
        if l.version_file.byte_length() > 0:
            note += String(": ", html_escape(l.version_file))
        return _stat("Mojo version", html_escape(l.mojo_version), note)
    var why = unversioned(l.commits, tool_code(l.tooling))
    var note = String("no manifest or lock file; nothing states a version") if why == "no-manifest" else String(
        "unknown: its manifest names no Mojo version" if l.commits > 0 else "unknown: history not read yet"
    )
    if est.byte_length() > 0:
        return _stat(
            "Mojo version",
            String("<span class=mute>", html_escape(why.replace("-", " ")), "</span>"),
            String(note, "; <span title='the Mojo release current at the last Mojo commit; a guess'>", est, "</span>"),
        )
    return _stat("Mojo version", _or_dash(String()), note)


def repo_page(req: Request, c: Cache) raises -> Response:
    try:
        var repo = String(req.param("owner"), "/", req.param("name"))
        var found = c.find(repo)
        if not found:
            return not_found(req.url)
        var l = found.value().copy()
        var data = c.data(repo)
        ref pts = data.pts
        ref ms = data.ms
        var today = _now_days()
        var gh = String("https://github.com/", html_escape(repo))
        var h = String(
            "<div class=head><h1><span class=owner>", html_escape(req.param("owner")),
            " /</span> ", html_escape(req.param("name")), "</h1>",
            "<p class=desc>", html_escape(l.description), "</p>",
            _chips(l.topics, 100),
            "<p class=meta><a href='", gh, "' rel=noopener>GitHub &#8599;</a> &middot; first seen in GH Archive ",
            day(l.first_seen), " (", html_escape(l.found_by), ")",
            " &middot; ", _n(l.mojo_lines), " lines of Mojo in ", _n(l.mojo_files), " files at the last of ",
            l.commits, " commits (", day(l.first_commit), " to ", day(l.last_commit), ")",
            String(" &middot; <strong>archived</strong>") if l.archived else String(),
            String(" &middot; now <a href='https://github.com/", html_escape(l.renamed_to), "' rel=noopener>",
                html_escape(l.renamed_to), "</a>") if l.renamed_to.byte_length() > 0 else String(),
            String(" &middot; GitHub says <strong>", html_escape(l.state), "</strong>")
                if l.state.byte_length() > 0 and l.state != "ok" and l.state != "renamed" else String(),
            "</p><div class=stats>",
            _stat("Stars", _n(l.stars), String("as of ", day_text(l.stats_as_of)) if l.stats_as_of > 0 else String("when found")),
            _stat("Forks", _n(l.forks), String("as of ", day_text(l.stats_as_of)) if l.stats_as_of > 0 else String("when found")),
            _deps_stat(l),
            _stat("Used by", _n(Int64(len(l.used_by))), "census repos that depend on it"),
            _stat("Open issues", _n(l.open_issues)) if l.stats_as_of > 0 else String(),
            _stat("Watchers", _n(l.watchers)) if l.stats_as_of > 0 else String(),
            _stat("Created", day(l.created_at), String(_age(l.created_at, today), " ago") if l.created_at else String()),
            _stat("Lines of Mojo", _n(l.mojo_lines), String(_n(l.mojo_files), " files")),
            _stat("Commits", _n(Int64(l.commits)), String(day(l.first_commit), " to ", day(l.last_commit)) if l.commits > 0 else String()),
            _version_stat(l),
            _stat("Tooling", _or_dash(l.tooling)),
            _stat("License", _or_dash(l.license)),
            "</div></div>",
            "<h2>Lines of Mojo</h2>", _chart(pts),
            _deps_section(l),
            _similar_section(repo, c),
            "<h2>Stars per month</h2>",
        )
        ref loaded = c.loaded
        if len(loaded) == 0:
            h.write(_empty("No activity yet", "The activity pipeline hasn't counted this repository's GH Archive events yet."))
        else:
            h.write(_stars_chart(data.acts, loaded))
        h.write("<h2>Releases and tags</h2>")
        ref rels = data.rels
        if len(rels) == 0:
            h.write(_empty("No releases or tags", "No published release in the GH Archive days loaded, and no git tag in the clone."))
        else:
            h.write(
                "<div class=tbl><table><thead><tr><th>Date</th><th>Tag</th><th>Name</th>",
                "<th>From</th><th>Mojo version</th><th>Commit</th></tr></thead><tbody>",
            )
            for i in range(min(len(rels), RELEASES_SHOWN)):
                ref x = rels[i]
                var commit = String("<span class=mute>&ndash;</span>")
                if x.commit.byte_length() > 0:
                    commit = String(
                        "<a class=mono href='", gh, "/commit/", html_escape(x.commit), "' rel=noopener>",
                        html_escape(String(x.commit[byte=:10])), "</a>",
                    )
                h.write(
                    "<tr><td>", day(x.at), "</td><td class='mono soft'><a href='", gh, "/releases/tag/",
                    html_escape(x.tag), "' rel=noopener>", html_escape(x.tag), "</a>",
                    " <span class=chip>pre-release</span>" if x.prerelease else "",
                    "</td><td class=soft>", _or_dash(x.name), "</td><td>",
                    "GitHub release" if x.source == "release" else "git tag",
                    "</td><td class=mono>", _or_dash(x.mojo_version), "</td><td>", commit, "</td></tr>",
                )
            h.write("</tbody></table></div>")
            if len(rels) > RELEASES_SHOWN:
                h.write(
                    "<p class=mute>The latest ", RELEASES_SHOWN, " of ", len(rels),
                    "; all of them are in <a href='/api/repos/", html_escape(repo), "'>the JSON</a>.</p>",
                )
        h.write("<h2>Migrations</h2>")
        if len(ms) == 0:
            h.write(_empty("No migrations recorded", "No change of Mojo version or tooling between the commits read so far."))
        else:
            h.write(
                "<div class=tbl><table><thead><tr><th>Date</th><th>What</th><th>From</th><th>To</th>",
                "<th>Commit</th></tr></thead><tbody>",
            )
            for ref m in ms:
                h.write(
                    "<tr><td>", day(m.at), "</td><td>", html_escape(m.kind), "</td><td class=mono>",
                    _or_dash(m.from_value), "</td><td class=mono>", _or_dash(m.to_value),
                    "</td><td><a class=mono href='", gh, "/commit/", html_escape(m.sha), "' rel=noopener>",
                    html_escape(String(m.sha[byte=:10])), "</a></td></tr>",
                )
            h.write("</tbody></table></div>")
        h.write("<h2>Commits</h2>")
        if len(pts) == 0:
            h.write(_empty("No commits read yet", "The history pipeline hasn't reached this repository."))
        else:
            h.write(
                "<div class=tbl><table><thead><tr><th>Date</th><th>Commit</th>",
                "<th class=num>Lines of Mojo</th><th>Tooling</th><th>Mojo version</th></tr></thead><tbody>",
            )
            var i = len(pts)
            var stop = max(i - COMMITS_SHOWN, 0)
            while i > stop:
                i -= 1
                ref p = pts[i]
                h.write(
                    "<tr><td>", day(p.at), "</td><td><a class=mono href='", gh, "/commit/",
                    html_escape(p.sha), "' rel=noopener>", html_escape(String(p.sha[byte=:10])),
                    "</a></td><td class=num>", _n(p.lines), "</td><td>", _or_dash(p.tooling),
                    "</td><td class=mono>", _or_dash(p.version), "</td></tr>",
                )
            h.write("</tbody></table></div>")
            if len(pts) > COMMITS_SHOWN:
                h.write(
                    "<p class=mute>The latest ", COMMITS_SHOWN, " of ", len(pts),
                    " commits; all of them are in <a href='/api/repos/", html_escape(repo), "'>the JSON</a>.</p>",
                )
        return _page(repo, h^, "repos")
    except e:
        return internal_error(String(e))
