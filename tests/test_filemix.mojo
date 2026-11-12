"""What kinds of files a commit changed (`filemix`), and the commit types
the file mix gives (`committype.typed_commits`).

    pixi run test
"""

from std.testing import TestSuite, assert_equal, assert_false, assert_true

from committype import typed_commits
from filemix import (
    KIND_CI, KIND_CONFIG, KIND_DOCS, KIND_LOCK, KIND_MOJO, KIND_MOJO_TEST, KIND_OTHER,
    KIND_PYTHON, FileMix, file_kind,
)
from model import Migration, Point


def test_file_kind() raises:
    assert_equal(file_kind("src/a.mojo"), KIND_MOJO)
    assert_equal(file_kind("x/b.🔥"), KIND_MOJO)
    assert_equal(file_kind("tests/test_a.mojo"), KIND_MOJO_TEST)
    assert_equal(file_kind("python/x/_ffi.py"), KIND_PYTHON)
    assert_equal(file_kind("README.md"), KIND_DOCS)
    assert_equal(file_kind("LICENSE"), KIND_DOCS)
    assert_equal(file_kind("docs/guide/index"), KIND_DOCS)
    assert_equal(file_kind("pixi.toml"), KIND_CONFIG)
    assert_equal(file_kind(".gitignore"), KIND_CONFIG)
    assert_equal(file_kind("pixi.lock"), KIND_LOCK)
    assert_equal(file_kind(".github/workflows/ci.yml"), KIND_CI)
    assert_equal(file_kind("lib/libfoo.so"), KIND_OTHER)


def test_encode_and_decode() raises:
    var m = FileMix()
    m.add("src/a.mojo", 10, 2)
    m.add("tests/test_a.py", 5, 0)
    m.add("README.md", 1, 1)
    m.created()
    var s = m.encode()
    assert_equal(s, "1 12 0 5 2 0 0 0 0 5 3 1 16 3")
    var back = FileMix.decode(s)
    assert_true(Bool(back))
    assert_equal(back.value().encode(), s)
    assert_false(Bool(FileMix.decode("")))
    assert_false(Bool(FileMix.decode("2 1 2 3")))


def _pt(subject: String, changes: String) -> Point:
    return Point(0, 0, String("sha"), String(), String(), subject, changes)


def test_typed_commits() raises:
    var docs = FileMix()
    docs.add("README.md", 40, 3)
    var code_and_tests = FileMix()
    code_and_tests.add("src/a.mojo", 60, 20)
    code_and_tests.add("tests/test_a.mojo", 30, 0)
    var pts: List[Point] = [
        _pt("fix: off by one", code_and_tests.encode()),  # rules, +test
        _pt("19 aug", docs.encode()),  # rules say other; its files say docs
        _pt("19 aug", ""),  # no files known: stays other
        _pt("", ""),  # no subject
    ]
    var t = typed_commits(pts, List[Migration]())
    assert_equal(t[0].main, "fix")
    assert_equal(t[0].by, "rules")
    assert_equal(len(t[0].secondary), 1)
    assert_equal(t[0].secondary[0], "test")
    assert_equal(t[1].main, "docs")
    assert_equal(t[1].by, "files")
    assert_equal(len(t[1].secondary), 0)
    assert_equal(t[2].main, "other")
    assert_equal(t[3].main, "")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
