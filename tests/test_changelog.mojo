"""CHANGELOG.md as the How it works page's Changelog tab renders it.

    pixi run test
"""

from std.testing import TestSuite, assert_equal, assert_true, assert_false

from changelog import changelog_html

comptime PULLS = "https://github.com/morca-dev/census/pull"


def test_sections_and_bullets() raises:
    var md = String(
        "# Changelog\n\nThe fragments are written here.\n\n"
        "## 1.1.0 - 2026-11-10\n\n"
        "- **New**: a `pipe` line\n  that wraps. (#100, #103)\n\n"
        "- **Two**: second. (#104)\n\n"
        "## 1.0.0 - 2026-11-10\n\nThe first.\n\n- **Old**: x.\n"
    )
    var h = changelog_html(md, PULLS)
    assert_false("Changelog" in h)
    assert_false("fragments" in h)
    assert_equal(
        h,
        String(
            "<h2 id='v1.1.0'>1.1.0 - 2026-11-10</h2><ul>",
            "<li><strong>New</strong>: a <code>pipe</code> line that wraps. (",
            "<a href='", PULLS, "/100' rel=noopener>#100</a>, ",
            "<a href='", PULLS, "/103' rel=noopener>#103</a>)</li>",
            "<li><strong>Two</strong>: second. (<a href='", PULLS,
            "/104' rel=noopener>#104</a>)</li></ul>",
            "<h2 id='v1.0.0'>1.0.0 - 2026-11-10</h2><p>The first.</p>",
            "<ul><li><strong>Old</strong>: x.</li></ul>",
        ),
    )


def test_escapes_links_and_code() raises:
    var h = changelog_html(
        "## 2\n- a <b> & [the docs](https://x.dev/a?b=1&c=2) `<x> #5` #PR caf\u00e9\n", PULLS
    )
    assert_equal(
        h,
        String(
            "<h2 id='v2'>2</h2><ul><li>a &lt;b&gt; &amp; <a href='https://x.dev/a?b=1&amp;c=2'",
            " rel=noopener>the docs</a> <code>&lt;x&gt; #5</code> #PR caf\u00e9</li></ul>",
        ),
    )


def test_unclosed_markup() raises:
    var h = changelog_html("## 1\n\nan **open `tick [link\n", PULLS)
    assert_equal(h, "<h2 id='v1'>1</h2><p>an <strong>open `tick [link</strong></p>")
    assert_true(changelog_html("", PULLS) == "")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
