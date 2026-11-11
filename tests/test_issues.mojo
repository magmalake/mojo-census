# mojo.issues rows: a page of GitHub's issues list parsed (issues and pull
# requests), merged into what is stored, read back as written, and the
# counts and lists a repo page shows. No network.

from std.testing import assert_equal, assert_true, TestSuite

from issues import (
    ISSUES_SHOWN,
    IssueRow,
    issue_rows,
    issues_batch,
    merge_issues,
    parse_issues,
    summarize,
)

comptime PAGE = """[
 {"number": 12, "title": "Parser is slow", "state": "open", "user": {"login": "ann"},
  "labels": [{"name": "bug"}, {"name": "perf"}], "comments": 3,
  "created_at": "2026-01-02T03:04:05Z", "updated_at": "2026-02-01T00:00:00Z",
  "closed_at": null},
 {"number": 13, "title": "Fix the parser", "state": "closed", "user": {"login": "bo"},
  "labels": [], "comments": 0, "created_at": "2026-02-03T00:00:00Z",
  "updated_at": "2026-02-04T00:00:00Z", "closed_at": "2026-02-04T00:00:00Z",
  "pull_request": {"url": "x", "merged_at": "2026-02-04T00:00:00Z"}},
 {"number": 14, "title": "Not merged", "state": "closed", "user": null,
  "labels": [], "comments": 1, "created_at": "2026-02-05T00:00:00Z",
  "updated_at": "2026-02-06T00:00:00Z", "closed_at": "2026-02-06T00:00:00Z",
  "pull_request": {"url": "y", "merged_at": null}}
]"""


def test_parse_page() raises:
    var rows = parse_issues("a/b", PAGE, 99)
    assert_equal(len(rows), 3)
    assert_equal(rows[0].kind, "issue")
    assert_equal(rows[0].number, 12)
    assert_equal(rows[0].title, "Parser is slow")
    assert_equal(rows[0].author, "ann")
    assert_equal(len(rows[0].labels), 2)
    assert_equal(rows[0].labels[1], "perf")
    assert_equal(rows[0].comments, 3)
    assert_equal(rows[0].closed_at, 0)
    assert_true(rows[0].updated_at > rows[0].created_at)
    assert_equal(rows[1].kind, "pr")
    assert_true(rows[1].merged_at > 0)
    assert_equal(rows[2].kind, "pr")
    assert_equal(rows[2].merged_at, 0)
    assert_equal(rows[2].author, "")
    assert_equal(rows[2].fetched_at, 99)
    assert_equal(len(parse_issues("a/b", "[]", 0)), 0)


def test_merge_and_roundtrip() raises:
    var old = parse_issues("a/b", PAGE, 1)
    var newer = parse_issues("a/b", PAGE, 2)
    newer[0].state = String("closed")
    var merged = merge_issues(old^, [newer[0].copy()])
    assert_equal(len(merged), 3)
    var b = issues_batch(merged)
    var back = issue_rows(b)
    assert_equal(len(back), 3)
    for ref r in back:
        if r.number == 12:
            assert_equal(r.state, "closed")
            assert_equal(r.fetched_at, 2)
            assert_equal(len(r.labels), 2)
        if r.number == 14:
            assert_equal(r.merged_at, 0)
            assert_equal(r.closed_at > 0, True)


def test_summary() raises:
    var rows = parse_issues("a/b", PAGE, 1)
    for i in range(ISSUES_SHOWN + 5):
        var r = rows[0].copy()
        r.number = Int64(100 + i)
        r.updated_at = Int64(i)
        rows.append(r^)
    var s = summarize(rows)
    ref x = s["a/b"]
    assert_equal(x.open_issues, ISSUES_SHOWN + 6)
    assert_equal(x.merged_prs, 1)
    assert_equal(x.closed_prs, 1)
    assert_equal(len(x.issues), ISSUES_SHOWN)
    assert_equal(x.issues[0].number, 12)  # updated last of all
    assert_equal(x.prs[0].number, 14)  # opened last
    assert_equal(x.total(), ISSUES_SHOWN + 8)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
