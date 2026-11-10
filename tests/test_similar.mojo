# Similar repos from embedding rows: which rows are compared, and the
# nearest others by cosine. Small hand-made vectors, no model needed.

from std.math import sqrt
from std.testing import assert_almost_equal, assert_equal, assert_true, TestSuite

from embedtext import EmbedRow, vector_bytes
from similar import latest_of, nearest


def _row(repo: String, v: List[Float32], at: Int64, rev: String = "r1") -> EmbedRow:
    var n = Float32(0)
    for x in v:
        n += x * x
    var u = List[Float32]()
    for x in v:
        u.append(x / sqrt(n))
    return EmbedRow(repo, "m", rev, "h", "text", len(u), vector_bytes(u, 0, len(u)), at)


def _keep(names: List[String]) -> Dict[String, Bool]:
    var out = Dict[String, Bool]()
    for n in names:
        out[n] = True
    return out^


def test_nearest_by_cosine() raises:
    var rows: List[EmbedRow] = [
        _row("a/x", [1, 0, 0], 1),
        _row("a/y", [0.9, 0.1, 0], 1),
        _row("a/z", [0, 1, 0], 1),
        _row("b/w", [0.5, 0.5, 0], 1),
    ]
    var e = latest_of(rows, 7)
    assert_equal(e.snapshot, 7)
    assert_equal(len(e.repos), 4)
    var near = nearest(e, _keep(["a/x", "a/y", "a/z", "b/w"]), 2)
    ref x = near["a/x"]
    assert_equal(len(x), 2)
    assert_equal(x[0].repo, "a/y")
    assert_equal(x[1].repo, "b/w")
    assert_true(x[0].score > x[1].score)
    assert_almost_equal(near["a/z"][0].score, Float32(0.70710677), atol=1e-5)
    assert_equal(near["a/z"][0].repo, "b/w")
    # Never the repo itself.
    for ref n in near["b/w"]:
        assert_true(n.repo != "b/w")


def test_only_repos_kept() raises:
    var rows: List[EmbedRow] = [
        _row("a/x", [1, 0], 1), _row("a/y", [1, 0.1], 1), _row("gone/r", [1, 0], 1),
    ]
    var near = nearest(latest_of(rows), _keep(["a/x", "a/y"]), 5)
    assert_equal(len(near), 2)
    assert_equal(len(near["a/x"]), 1)
    assert_equal(near["a/x"][0].repo, "a/y")


def test_newest_row_and_one_model() raises:
    var rows: List[EmbedRow] = [
        _row("a/x", [1, 0], 1),
        _row("a/x", [0, 1], 5),  # newer: replaces the first
        _row("a/y", [0, 1], 2),
        _row("a/z", [0, 1], 9, "r2"),  # newest row: its rev wins
        _row("a/w", [0, 1], 9, "r2"),
    ]
    var e = latest_of(rows)
    assert_equal(e.model_rev, "r2")
    assert_equal(len(e.repos), 2)
    var e1 = latest_of([_row("a/x", [1, 0], 1), _row("a/x", [0, 1], 5), _row("a/y", [0, 1], 2)])
    assert_equal(len(e1.repos), 2)
    var near = nearest(e1, _keep(["a/x", "a/y"]))
    assert_almost_equal(near["a/x"][0].score, Float32(1), atol=1e-6)


def test_ties_by_name_and_empty() raises:
    var rows: List[EmbedRow] = [
        _row("q/q", [1, 0], 1), _row("c/c", [0, 1], 1), _row("b/b", [0, 1], 1),
    ]
    var near = nearest(latest_of(rows), _keep(["q/q", "c/c", "b/b"]), 1)
    assert_equal(near["q/q"][0].repo, "b/b")
    assert_equal(len(nearest(latest_of(List[EmbedRow]()), _keep(["a/a"]))), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
