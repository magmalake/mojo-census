from std.testing import TestSuite, assert_equal

from committype import commit_type, words


def _is(subject: String, want: String, version_change: Bool = False) raises:
    assert_equal(commit_type(subject, version_change), want, subject)


def test_conventional() raises:
    _is("feat(api): add a thing", "feature")
    _is("fix: handle empty input", "fix")
    _is("docs!: rewrite the guide", "docs")
    _is("perf: faster tokenizer", "perf")
    _is("chore: tidy", "chore")
    _is("ci: run on arm", "chore")
    _is("refactor: migrate _ffi.mojo to Pointer (Mojo 1.0.0)", "migration")
    _is("fix: bump to latest Mojo nightly, fix mechanical breaks (#766)", "version")


def test_version() raises:
    _is("Upgrade to Mojo 24.2", "version")
    _is("update mojo", "version")
    _is("update to 26.2", "version")
    _is("deps: bump Mojo nightly to 1.0.0b3.dev2026062206", "version")
    _is("Bump Mojo nightly to dev2026080206", "version")
    _is("tweak the manifest", "version", version_change=True)
    # A library's version, not Mojo's.
    _is("Pin bench-mojo 0.2.0 (p50/p90 in the benchmark tables)", "other")
    _is("Relax the package run-dependency to mojo-compiler >=1.0,<2", "other")


def test_migration() raises:
    _is("Replace deprecated ptr.offset() with pointer arithmetic", "migration")
    _is("port to Mojo 1.2", "migration")
    _is("fix(web): set Vite dev server port to 3000", "fix")


def test_first_word() raises:
    _is("Fix auth for Prefix upload (#151)", "fix")
    _is("Added append function to array types", "feature")
    _is("Update README.md", "docs")
    _is("Simplify imports (#7)", "refactor")
    _is("Merge pull request #12 from a/b", "merge")
    _is("update", "other")
    _is("", "other")
    _is("Création du module", "other")


def test_words() raises:
    var w = words("bump mojo to 1.2.0.dev2026. done-")
    assert_equal(len(w), 5)
    assert_equal(w[3], "1.2.0.dev2026")
    assert_equal(w[4], "done")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
