"""Contributors from `git log`: hashed emails, bots, co-authors, per month.

    pixi run test
"""

from std.os import getenv
from std.testing import TestSuite, assert_equal, assert_false, assert_true

from command import command
from contributors import (
    AuthorMonth,
    ID_HEX,
    author_id,
    contributor_counts,
    counts_by_repo,
    is_bot,
    month_start,
    normalize_email,
    parse_author_log,
    parse_coauthor,
    read_authors,
)
from days import days_of


def _rec(at: Int, name: String, email: String, coauthors: List[String] = List[String]()) -> String:
    """One commit as `AUTHOR_FORMAT` prints it."""
    var out = String("\x1e", at, "\x1f", name, "\x1f", email, "\x1f")
    for i in range(len(coauthors)):
        if i > 0:
            out += "\x1d"
        out += coauthors[i]
    out += "\n"
    return out^


def test_author_id_is_a_hash() raises:
    var id = author_id("Ann", "ann@example.com")
    assert_equal(id.byte_length(), ID_HEX)
    assert_false("ann" in id)
    # sha256("email:ann@example.com"), cut.
    assert_equal(id, "35f3b3170d36d0a1")
    # Case, spaces and the name don't matter; the email does.
    assert_equal(author_id("A. N. Other", "  Ann@Example.COM "), id)
    assert_true(author_id("Ann", "bob@example.com") != id)
    # No email: by name.
    assert_equal(author_id("Ann", ""), author_id(" ann ", ""))
    assert_true(author_id("Ann", "") != id)


def test_noreply_emails() raises:
    assert_equal(normalize_email("12345+ann@users.noreply.github.com"), "ann@users.noreply.github.com")
    assert_equal(normalize_email("ann@users.noreply.github.com"), "ann@users.noreply.github.com")
    assert_equal(normalize_email("a+b@example.com"), "a+b@example.com")
    assert_equal(
        author_id("x", "12345+Ann@users.noreply.github.com"),
        author_id("y", "ann@users.noreply.github.com"),
    )


def test_bots() raises:
    assert_true(is_bot("dependabot[bot]", "49699333+dependabot[bot]@users.noreply.github.com"))
    assert_true(is_bot("github-actions[bot]", "41898282+github-actions[bot]@users.noreply.github.com"))
    assert_true(is_bot("renovate[bot]", "x@example.com"))
    assert_true(is_bot("Dependabot", "support@github.com"))
    assert_true(is_bot("github-actions", "actions@github.com"))
    assert_true(is_bot("Someone", "123+some[bot]@users.noreply.github.com"))
    assert_false(is_bot("Ann", "ann@example.com"))
    assert_false(is_bot("Robot Builder", "robot@example.com"))
    assert_false(is_bot("bot-fan", "bot@example.com"))


def test_parse_coauthor() raises:
    var a = parse_coauthor("  Ann Lee <ann@example.com> ")
    assert_equal(a[0], "Ann Lee")
    assert_equal(a[1], "ann@example.com")
    var b = parse_coauthor("Just A Name")
    assert_equal(b[0], "Just A Name")
    assert_equal(b[1], "")
    var c = parse_coauthor("<only@example.com>")
    assert_equal(c[0], "")
    assert_equal(c[1], "only@example.com")


def test_month_start() raises:
    # 2023-11-14T22:13:20Z
    assert_equal(month_start(1700000000), days_of("2023-11-01"))
    assert_equal(month_start(days_of("2024-02-29") * 86_400 + 86_399), days_of("2024-02-01"))
    assert_equal(month_start(days_of("2024-03-01") * 86_400), days_of("2024-03-01"))


def test_parse_author_log() raises:
    var jan = Int(days_of("2024-01-10")) * 86_400
    var feb = Int(days_of("2024-02-03")) * 86_400
    var log = String(
        _rec(jan, "Ann", "ann@example.com"),
        _rec(jan + 60, "Ann", "ANN@example.com", ["Bob <bob@example.com>"]),
        # Ann co-authoring her own commit counts once.
        _rec(jan + 120, "Ann", "ann@example.com", ["Ann <ann@example.com>", "dependabot[bot] <x@y>"]),
        _rec(jan + 180, "dependabot[bot]", "49699333+dependabot[bot]@users.noreply.github.com"),
        _rec(feb, "Bob", "bob@example.com", ["Cy <cy@example.com>"]),
        "\x1enot a time\x1fZed\x1fzed@example.com\x1f\n",
    )
    var rows = parse_author_log("o/r", log)
    assert_equal(len(rows), 4)
    var ann = author_id("", "ann@example.com")
    var bob = author_id("", "bob@example.com")
    var cy = author_id("", "cy@example.com")
    var jan1 = days_of("2024-01-01")
    var feb1 = days_of("2024-02-01")
    for ref r in rows:
        assert_equal(r.repo, "o/r")
        if r.month == jan1 and r.author == ann:
            assert_equal(r.commits, 3)
        elif r.month == jan1 and r.author == bob:
            assert_equal(r.commits, 1)
        elif r.month == feb1:
            assert_true(r.author == bob or r.author == cy)
            assert_equal(r.commits, 1)
        else:
            assert_true(False, "unexpected row")
    # Sorted by month, then person.
    assert_equal(rows[0].month, jan1)
    assert_equal(rows[3].month, feb1)


def test_per_month_counts() raises:
    var m1 = days_of("2024-01-01")
    var m2 = days_of("2024-02-01")
    var m3 = days_of("2024-04-01")
    # Out of order on purpose.
    var rows: List[AuthorMonth] = [
        AuthorMonth("o/r", m2, "b", 2),
        AuthorMonth("o/r", m1, "a", 5),
        AuthorMonth("o/r", m3, "c", 1),
        AuthorMonth("o/r", m2, "a", 1),
        AuthorMonth("o/r", m1, "b", 1),
        AuthorMonth("o/r", m3, "a", 1),
    ]
    var c = contributor_counts(rows)
    assert_equal(c.total, 3)
    assert_equal(len(c.months), 3)
    assert_equal(c.months[0].month, "2024-01")
    assert_equal(c.months[0].active, 2)
    assert_equal(c.months[0].new, 2)
    assert_equal(c.months[1].month, "2024-02")
    assert_equal(c.months[1].active, 2)
    assert_equal(c.months[1].new, 0)
    assert_equal(c.months[2].month, "2024-04")
    assert_equal(c.months[2].active, 2)
    assert_equal(c.months[2].new, 1)
    assert_equal(contributor_counts(List[AuthorMonth]()).total, 0)


def test_counts_by_repo() raises:
    var m = days_of("2024-01-01")
    var rows: List[AuthorMonth] = [
        AuthorMonth("o/a", m, "x", 1),
        AuthorMonth("o/b", m, "x", 1),
        AuthorMonth("o/b", m, "y", 1),
    ]
    var by = counts_by_repo(rows)
    assert_equal(by["o/a"].total, 1)
    assert_equal(by["o/b"].total, 2)


def test_authors_of_a_real_clone() raises:
    # Two people and a bot on a side branch merged with a merge commit: the
    # side branch's author counts though it isn't on the first-parent
    # history, and a co-author trailer (any case) counts.
    var dir = String(getenv("TMPDIR", "/tmp"), "/mojo-census-test-authors")
    var r = command(["/bin/sh", "-c", String(
        "rm -rf '", dir, "' && git init -q -b main '", dir, "' && cd '", dir, "'",
        " && GIT_AUTHOR_DATE='1700000000 +0000' git -c user.name=Ann -c user.email=ann@example.com",
        " commit -q --allow-empty -m one",
        " && git checkout -q -b side",
        " && GIT_AUTHOR_DATE='1700000100 +0000' git -c user.name=Bob -c user.email=bob@example.com",
        " commit -q --allow-empty -m 'two' -m 'co-authored-by: Cy <cy@example.com>'",
        " && git checkout -q main",
        " && GIT_AUTHOR_DATE='1700000200 +0000' git -c 'user.name=dependabot[bot]'",
        " -c 'user.email=1+dependabot[bot]@users.noreply.github.com' commit -q --allow-empty -m bump",
        " && GIT_AUTHOR_DATE='1700000300 +0000' git -c user.name=Ann -c user.email=ann@example.com",
        " merge -q --no-ff -m merge side",
    )])
    assert_equal(r[0], 0, r[1])
    var rows = read_authors("o/r", String(dir, "/.git"))
    var c = contributor_counts(rows)
    assert_equal(c.total, 3)
    assert_equal(len(c.months), 1)
    assert_equal(c.months[0].month, "2023-11")
    assert_equal(c.months[0].new, 3)
    for ref a in rows:
        if a.author == author_id("", "ann@example.com"):
            assert_equal(a.commits, 2)
    _ = command(["/bin/sh", "-c", String("rm -rf '", dir, "'")])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
