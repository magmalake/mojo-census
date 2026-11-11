"""Reading `git log --numstat --summary` into commits and migrations.

    pixi run test
"""

from std.testing import TestSuite, assert_equal, assert_false, assert_true

from std.os import getenv

from history import LOG_FORMAT, SUBJECT_MAX, History, _parse_log, _read_tags, _sh, is_bazel_file, is_mojo_file, safe_repo
from history import CommitRow, MigrationRow, TagRow, join_tags, parse_tags


def _log() -> String:
    # Three first-parent commits: two Mojo files, then one grows and a
    # .🔥 file appears, then one is deleted. No manifest is touched, so
    # nothing reads the (absent) clone.
    return String(
        "@@aaa 1700000000\n\n",
        "10\t0\tsrc/a.mojo\n5\t0\tb.mojo\n3\t0\tREADME.md\n",
        " create mode 100644 src/a.mojo\n create mode 100644 b.mojo\n",
        " create mode 100644 README.md\n",
        "@@bbb 1700000100\n\n",
        "4\t1\tsrc/a.mojo\n7\t0\tc.🔥\n-\t-\tlogo.png\n",
        " create mode 100644 c.🔥\n create mode 100644 logo.png\n",
        "@@ccc 1700000200\n\n",
        "0\t5\tb.mojo\n delete mode 100644 b.mojo\n",
    )


def test_lines_and_files() raises:
    var h = History.empty("o/r")
    _parse_log("o/r", "/nonexistent", _log(), h)
    assert_equal(len(h.commits), 3)
    assert_equal(h.commits.items[0].mojo_lines, 15)
    assert_equal(h.commits.items[0].mojo_files, 2)
    assert_equal(h.commits.items[1].mojo_lines, 25)
    assert_equal(h.commits.items[1].mojo_files, 3)
    assert_equal(h.commits.items[2].mojo_lines, 20)
    assert_equal(h.commits.items[2].mojo_files, 2)
    assert_equal(h.commits.items[2].seq, 2)
    assert_equal(h.commits.items[1].committed_at, 1700000100 * 1_000_000)
    assert_equal(h.commits.items[0].tooling, "none")
    assert_equal(len(h.migrations), 0)


def test_bazel_outranks_pixi() raises:
    # pixi.toml first, then a root MODULE.bazel (bazel, though pixi is still
    # there), a nested WORKSPACE that doesn't count, then Bazel's files go.
    var log = String(
        "@@aaa 1700000000\n\n",
        " create mode 100644 pixi.toml\n create mode 100644 a.mojo\n",
        "@@bbb 1700000100\n\n",
        " create mode 100644 MODULE.bazel\n",
        "@@ccc 1700000200\n\n",
        " create mode 100644 sub/WORKSPACE\n",
        "@@ddd 1700000300\n\n",
        " delete mode 100644 MODULE.bazel\n",
        "@@eee 1700000400\n\n",
        " create mode 100644 BUILD.bazel\n",
    )
    var h = History.empty("o/r")
    _parse_log("o/r", "/nonexistent", log, h)
    assert_equal(len(h.commits), 5)
    assert_equal(h.commits.items[0].tooling, "pixi")
    assert_equal(h.commits.items[1].tooling, "bazel")
    assert_equal(h.commits.items[2].tooling, "bazel")
    assert_equal(h.commits.items[3].tooling, "pixi")
    assert_equal(h.commits.items[4].tooling, "bazel")
    var kinds = List[String]()
    for ref m in h.migrations.items:
        if m.kind == "tooling":
            kinds.append(String(m.from_value, ">", m.to_value))
    assert_equal(len(kinds), 4)
    assert_equal(kinds[0], "none>pixi")
    assert_equal(kinds[1], "pixi>bazel")
    assert_equal(kinds[2], "bazel>pixi")
    assert_equal(kinds[3], "pixi>bazel")
    assert_true(is_bazel_file("WORKSPACE.bazel"))
    assert_false(is_bazel_file("sub/BUILD.bazel"))
    assert_false(is_bazel_file("BUILD"))


def test_mojo_files() raises:
    assert_true(is_mojo_file("a/b.mojo"))
    assert_true(is_mojo_file("x.🔥"))
    assert_false(is_mojo_file("a.mojom"))


def test_output_not_utf8() raises:
    # An old commit's Latin-1 author or path: the bytes that aren't UTF-8
    # are dropped instead of failing the whole run.
    var r = _sh("printf 'caf\\351 ok\\n'; (exit 3)")
    assert_equal(r[0], 3)
    assert_equal(r[1], "caf ok\n")


def test_safe_repo() raises:
    assert_true(safe_repo("modular/modular"))
    assert_true(safe_repo("mzaks/mojo-flx"))
    assert_false(safe_repo("a/b; rm -rf /"))
    assert_false(safe_repo("../etc"))
    assert_false(safe_repo("noslash"))


def test_parse_tags() raises:
    # Annotated (peeled to the commit), lightweight, a name with slashes,
    # dots and non-ASCII, and lines that aren't tags or are cut short.
    var out = String(
        "refs/tags/v1.0\ttag\taaaa\tc0ffee\t1700000000\n",
        "refs/tags/release/2024.1-rc\tcommit\tbbbb\t\t1700000500\n",
        "refs/tags/n\u00e4me-\U0001f525\tcommit\tcccc\t\t1700000900\n",
        "refs/heads/main\tcommit\tdddd\t\t1\n",
        "refs/tags/broken\tcommit\n",
        "refs/tags/nodate\tcommit\teeee\t\t\n",
    )
    var tags = parse_tags("o/r", out)
    assert_equal(len(tags), 4)
    # By bytes: "no" sorts before "n\xc3".
    assert_equal(tags[0].tag, "nodate")
    assert_equal(tags[0].tagged_at, 0)
    assert_equal(tags[1].tag, "n\u00e4me-\U0001f525")
    assert_equal(tags[2].tag, "release/2024.1-rc")
    assert_false(tags[2].annotated)
    assert_equal(tags[2].commit, "bbbb")
    assert_equal(tags[3].tag, "v1.0")
    assert_true(tags[3].annotated)
    assert_equal(tags[3].commit, "c0ffee")
    assert_equal(tags[3].tagged_at, 1700000000 * 1_000_000)
    var by_sha = Dict[String, Tuple[String, String, String]]()
    by_sha["c0ffee"] = (String("pixi"), String("25.4.0"), String("rattler"))
    join_tags(tags, by_sha)
    assert_equal(tags[3].tooling, "pixi")
    assert_equal(tags[3].mojo_version, "25.4.0")
    assert_equal(tags[3].packaging, "rattler")
    assert_equal(tags[2].tooling, "")


def test_tags_of_a_real_clone() raises:
    # A repository with an annotated tag, a lightweight one and one whose
    # name has a byte that isn't UTF-8 (git allows it; it comes back
    # without that byte rather than failing).
    var dir = String(getenv("TMPDIR", "/tmp"), "/mojo-census-test-tags")
    var r = _sh(String(
        "rm -rf '", dir, "' && git init -q '", dir, "' && cd '", dir, "'",
        " && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m one",
        " && GIT_COMMITTER_DATE='1700000000 +0000' git -c user.name=t -c user.email=t@t tag -a v1 -m 'first'",
        " && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m two",
        " && git tag light",
        # macOS won't make a file whose name isn't UTF-8, so the third tag
        # goes straight into packed-refs.
        " && printf '%s refs/tags/caf\\351\\n' \"$(git rev-parse HEAD)\" >> .git/packed-refs",
    ))
    assert_equal(r[0], 0)
    var h = History.empty("o/r")
    _read_tags("o/r", String(dir, "/.git"), h)
    assert_equal(len(h.tags), 3)
    assert_equal(h.tags.items[0].tag, "caf")
    assert_equal(h.tags.items[1].tag, "light")
    assert_false(h.tags.items[1].annotated)
    assert_equal(h.tags.items[2].tag, "v1")
    assert_true(h.tags.items[2].annotated)
    assert_equal(h.tags.items[2].tagged_at, 1700000000 * 1_000_000)
    assert_equal(h.tags.items[2].commit.byte_length(), 40)
    assert_true(h.tags.items[2].commit != h.tags.items[1].commit)
    _ = _sh(String("rm -rf '", dir, "'"))


def _git_history(dir: String, steps: List[String]) raises -> History:
    """A repository made in `dir` by one commit per shell step, read the
    way `_read_history` reads a clone."""
    var cmd = String("rm -rf '", dir, "' && git init -q '", dir, "' && cd '", dir, "'")
    for i in range(len(steps)):
        cmd += String(
            " && ", steps[i], " && git add -A",
            " && GIT_COMMITTER_DATE='", 1700000000 + i * 100, " +0000'",
            " git -c user.name=t -c user.email=t@t commit -q --allow-empty -m s", i,
        )
    var r = _sh(cmd)
    assert_equal(r[0], 0, r[1])
    var log = _sh(String(
        "git -C '", dir, "' -c core.quotepath=off log --first-parent",
        " --reverse --no-renames --diff-merges=first-parent",
        " --format='", LOG_FORMAT, "' --numstat --summary HEAD",
    ))
    assert_equal(log[0], 0)
    var h = History.empty("o/r")
    _parse_log("o/r", dir, log[1], h)
    _ = _sh(String("rm -rf '", dir, "'"))
    return h^


def test_subjects() raises:
    var long = String()
    for _ in range(60):
        long += "é_x"  # 4 bytes each: 240 in all
    var log = String(
        "@@aaa 1700000000 fix: a subject with  spaces\n\n",
        "@@bbb 1700000100\n\n",
        "@@ccc 1700000200 ", long, "\n\n",
    )
    var h = History.empty("o/r")
    _parse_log("o/r", "/nonexistent", log, h)
    assert_equal(len(h.commits), 3)
    assert_equal(h.commits.items[0].subject, "fix: a subject with  spaces")
    assert_equal(h.commits.items[0].committed_at, 1700000000 * 1_000_000)
    assert_equal(h.commits.items[1].subject, "")
    var s = h.commits.items[2].subject
    assert_true(s.byte_length() <= SUBJECT_MAX and s.byte_length() > SUBJECT_MAX - 4)
    assert_true(long.startswith(s))


def test_subjects_of_a_real_clone() raises:
    var dir = String(getenv("TMPDIR", "/tmp"), "/mojo-census-test-subjects")
    var h = _git_history(dir, ["true", "true"])
    assert_equal(len(h.commits), 2)
    assert_equal(h.commits.items[0].subject, "s0")
    assert_equal(h.commits.items[1].subject, "s1")


def test_python_tooling_history() raises:
    # mojo-tokenizers' shape, step by step: a pyproject that depends on Mojo
    # (pip, its pin), a uv.lock (uv, the locked version), a rattler recipe
    # (packaging), then the pyproject stops depending on Mojo (none).
    var dir = String(getenv("TMPDIR", "/tmp"), "/mojo-census-test-pytool")
    var pyproject = String(
        "printf '[project]\\nname = \"t\"\\ndependencies = [\\n  \"mojo>=1.2.0,<1.3\",\\n]\\n'",
        " > pyproject.toml && printf 'def main():\\n    pass\\n' > a.mojo",
    )
    var uv_lock = String(
        "printf '[[package]]\\nname = \"mojo\"\\nversion = \"1.2.1\"\\n' > uv.lock",
    )
    var steps: List[String] = [
        pyproject,
        uv_lock,
        String("printf 'package:\\n  name: t\\n' > recipe.yaml"),
        String("printf '[project]\\nname = \"t\"\\ndependencies = [\"numpy\"]\\n' > pyproject.toml"),
    ]
    var h = _git_history(dir, steps)
    assert_equal(len(h.commits), 4)
    assert_equal(h.commits.items[0].tooling, "pip")
    assert_equal(h.commits.items[0].mojo_version, "1.2.0")
    assert_equal(h.commits.items[0].version_source, "pyproject.toml")
    assert_equal(h.commits.items[0].packaging, "none")
    assert_equal(h.commits.items[1].tooling, "uv")
    assert_equal(h.commits.items[1].mojo_version, "1.2.1")
    assert_equal(h.commits.items[1].version_source, "uv.lock")
    assert_equal(h.commits.items[2].tooling, "uv")
    assert_equal(h.commits.items[2].packaging, "rattler")
    assert_equal(h.commits.items[3].tooling, "none")
    assert_equal(h.commits.items[3].packaging, "rattler")
    var kinds = List[String]()
    for ref m in h.migrations.items:
        kinds.append(String(m.kind, ":", m.from_value, ">", m.to_value))
    assert_true("tooling:none>pip" in kinds)
    assert_true("tooling:pip>uv" in kinds)
    assert_true("tooling:uv>none" in kinds)
    assert_true("packaging:none>rattler" in kinds)
    assert_true("mojo_version:1.2.0>1.2.1" in kinds)


def test_pixi_in_pyproject_stays_pixi() raises:
    # pixi reads its manifest from `[tool.pixi.*]`: that is pixi, not pip,
    # with or without a uv.lock beside it.
    var dir = String(getenv("TMPDIR", "/tmp"), "/mojo-census-test-pyproject-pixi")
    var steps: List[String] = [
        String(
            "printf '[project]\\nname = \"t\"\\n[tool.pixi.dependencies]\\nmojo = \">=1.2.0,<2\"\\n'",
            " > pyproject.toml && touch uv.lock",
        ),
    ]
    var h = _git_history(dir, steps)
    assert_equal(len(h.commits), 1)
    assert_equal(h.commits.items[0].tooling, "pixi")
    assert_equal(h.commits.items[0].mojo_version, "1.2.0")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
