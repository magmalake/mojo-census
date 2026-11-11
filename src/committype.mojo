"""Commit types from commit subjects, by rules (#121): what a commit did,
for the repo page's commits and the Migrations page.

`commit_type` reads the subject the way a person skims it:

1. `Merge pull request ...` / `Merge branch ...` is `merge`.
2. A conventional-commit prefix (`fix:`, `feat(api):`, `docs!:`) names the
   type (`CONVENTIONAL`).
3. A commit that changed the Mojo version (it has a `mojo_version` row in
   mojo.migrations), or whose subject says it moved to a Mojo version
   (`update to Mojo 24.3`, `bump nightly to dev2026080206`), is `version`.
4. A subject about migrating (`migrate`, `deprecated`, `port to Mojo`) is
   `migration`: work that follows a version change.
5. Otherwise the first word (`Fix`, `Added`, `Refactor`, `Update README`),
   else `other`.

About a third of subjects carry a conventional prefix and the first word
labels another quarter; on 2,992 subjects of 80 sampled census repos, 39%
stay `other`. Those are for a nearest-neighbour labeller over subject
embeddings, as the categories (#113) do it, once 100 hand-labelled commits
can check it.
"""

from model import Migration, Point


comptime COMMIT_TYPES_VERSION = 1
"""Bumped when the rules change, so the console can say which it used."""


def commit_type_keys() -> List[String]:
    """Every type, in the order the console lists them."""
    return [
        "feature", "fix", "version", "migration", "refactor", "perf", "docs",
        "test", "chore", "merge", "other",
    ]


def commit_type_title(t: String) -> String:
    if t == "feature":
        return "Feature"
    if t == "fix":
        return "Fix"
    if t == "version":
        return "Mojo version"
    if t == "migration":
        return "Migration"
    if t == "refactor":
        return "Refactor"
    if t == "perf":
        return "Performance"
    if t == "docs":
        return "Docs"
    if t == "test":
        return "Tests"
    if t == "chore":
        return "Build and chores"
    if t == "merge":
        return "Merge"
    return "Other"


def _conventional(t: String) -> String:
    """The type a conventional-commit prefix names; empty for one it doesn't
    know."""
    if t == "feat" or t == "feature" or t == "add":
        return "feature"
    if t == "fix" or t == "bugfix" or t == "hotfix":
        return "fix"
    if t == "docs" or t == "doc":
        return "docs"
    if t == "test" or t == "tests":
        return "test"
    if t == "refactor" or t == "style":
        return "refactor"
    if t == "perf" or t == "bench":
        return "perf"
    if (
        t == "chore" or t == "build" or t == "ci" or t == "release"
        or t == "deps" or t == "revert"
    ):
        return "chore"
    return String()


def _first_word(w: String) -> String:
    """The type a subject's first word names; empty for none."""
    if (
        w == "fix" or w == "fixed" or w == "fixes" or w == "fixing" or w == "bugfix"
        or w == "hotfix" or w == "typo" or w == "correct" or w == "corrected"
        or w == "resolve"
    ):
        return "fix"
    if (
        w == "add" or w == "added" or w == "adds" or w == "adding" or w == "implement"
        or w == "implemented" or w == "create" or w == "created" or w == "introduce"
        or w == "support" or w == "enable" or w == "new"
    ):
        return "feature"
    if (
        w == "refactor" or w == "refactored" or w == "cleanup" or w == "clean"
        or w == "rename" or w == "renamed" or w == "simplify" or w == "move"
        or w == "moved" or w == "restructure" or w == "reorganize" or w == "format"
        or w == "remove" or w == "removed" or w == "delete" or w == "deleted"
    ):
        return "refactor"
    if w == "optimize" or w == "optimized" or w == "speed" or w == "speedup":
        return "perf"
    if w == "docs" or w == "doc" or w == "readme" or w == "document" or w == "documentation":
        return "docs"
    if w == "test" or w == "tests":
        return "test"
    if w == "revert" or w == "release":
        return "chore"
    return String()


def _is_letter(c: UInt8) -> Bool:
    return (c >= UInt8(ord("a")) and c <= UInt8(ord("z")))


def _is_word_byte(c: UInt8) -> Bool:
    """Letters, digits, `.` and `-`: `1.2.0.dev2026`, `mojo-compiler` stay
    one word each."""
    return (
        _is_letter(c) or (c >= UInt8(ord("0")) and c <= UInt8(ord("9")))
        or c == UInt8(ord(".")) or c == UInt8(ord("-")) or c == UInt8(ord("_"))
    )


def words(lower: String) -> List[String]:
    """The words of a lowercased subject, without a trailing `.`."""
    var out = List[String]()
    var b = lower.as_bytes()
    var i = 0
    while i < len(b):
        while i < len(b) and not _is_word_byte(b[i]):
            i += 1
        var start = i
        while i < len(b) and _is_word_byte(b[i]):
            i += 1
        var end = i
        while end > start and (b[end - 1] == UInt8(ord(".")) or b[end - 1] == UInt8(ord("-"))):
            end -= 1
        if end > start:
            out.append(String(lower[byte=start:end]))
    return out^


def _is_mojo(w: String) -> Bool:
    return (
        w == "mojo" or w == "max" or w == "magic" or w == "nightly" or w == "modular"
        or w == "mojo-compiler"
    )


def _is_version_number(w: String) -> Bool:
    """`24.3`, `1.2.0.dev2026101905`, `v25.1`, `dev2026080206`."""
    var b = w.as_bytes()
    if len(b) == 0:
        return False
    var at = 1 if b[0] == UInt8(ord("v")) else 0
    if w.startswith("dev20"):
        return True
    if at >= len(b) or b[at] < UInt8(ord("0")) or b[at] > UInt8(ord("9")):
        return False
    return "." in w


def _is_bump(w: String) -> Bool:
    return (
        w == "bump" or w == "bumped" or w == "upgrade" or w == "upgraded"
        or w == "update" or w == "updated" or w == "pin" or w == "pinned"
        or w == "switch"
    )


def _says_version(ws: List[String]) -> Bool:
    """A bump word and a Mojo version: `update to 26.2`, `upgrade Mojo to
    version 24.1.0`, `update mojo`, `bump nightly to dev2026080206`."""
    var bump = False
    for ref w in ws:
        if _is_bump(w):
            bump = True
    for i in range(len(ws) if bump else 0):
        if _is_mojo(ws[i]):
            # `update mojo`, `upgrade mojo and torch`: right after the bump word.
            if i > 0 and _is_bump(ws[i - 1]):
                return True
            # `bump to latest Mojo nightly`, `upgrade to the new mojo`.
            if i > 0 and (ws[i - 1] == "latest" or ws[i - 1] == "new" or ws[i - 1] == "newest"):
                return True
            for j in range(i + 1, min(i + 4, len(ws))):
                if _is_version_number(ws[j]) or ws[j] == "version" or ws[j] == "latest":
                    return True
    # `update to 26.2`: a Modular release number on its own.
    for i in range(1, len(ws)):
        if ws[i - 1] == "to" and _is_version_number(ws[i]):
            var w = ws[i]
            if w.startswith("24.") or w.startswith("25.") or w.startswith("26.") or w.startswith("dev20"):
                return True
    return False


def _says_migration(ws: List[String]) -> Bool:
    for i in range(len(ws)):
        ref w = ws[i]
        if w.startswith("migrat") or w.startswith("deprecat"):
            return True
        if (w == "port" or w == "ported") and i + 2 < len(ws) and ws[i + 1] == "to":
            if _is_mojo(ws[i + 2]) or _is_version_number(ws[i + 2]):
                return True
    return False


def commit_type(subject: String, version_change: Bool) -> String:
    """The type of a commit with this subject; `version_change` when
    mojo.migrations has a Mojo version change at it."""
    var s = subject.lower()
    if s.startswith("merge pull request") or s.startswith("merge branch") or s.startswith("merge remote"):
        return "merge"
    var b = s.as_bytes()
    # A conventional prefix: letters, an optional `(scope)` and `!`, a `:`.
    var i = 0
    while i < len(b) and _is_letter(b[i]):
        i += 1
    var base = String()
    var rest_at = 0
    if i > 0:
        var j = i
        if j < len(b) and b[j] == UInt8(ord("(")):
            while j < len(b) and b[j] != UInt8(ord(")")):
                j += 1
            j += 1
        if j < len(b) and b[j] == UInt8(ord("!")):
            j += 1
        if j < len(b) and b[j] == UInt8(ord(":")):
            base = _conventional(String(s[byte=:i]))
            rest_at = j + 1
    var ws = words(String(s[byte=rest_at:]))
    var migration = _says_migration(ws)
    if version_change:
        return "migration" if migration else "version"
    if base.byte_length() > 0 and base != "chore" and base != "fix" and base != "refactor":
        return base
    if base.byte_length() > 0 and migration:
        return "migration"
    if _says_version(ws):
        return "version"
    if migration:
        return "migration"
    if base.byte_length() > 0:
        return base
    if len(ws) == 0:
        return "other"
    if (ws[0] == "update" or ws[0] == "updated" or ws[0] == "updates") and len(ws) > 1:
        if ws[1] == "readme" or ws[1] == "readme.md" or ws[1] == "docs" or ws[1] == "documentation":
            return "docs"
    var t = _first_word(ws[0])
    return t if t.byte_length() > 0 else String("other")


def has_subjects(pts: List[Point]) -> Bool:
    """Whether any commit has its subject (read since #102)."""
    for ref p in pts:
        if p.subject.byte_length() > 0:
            return True
    return False


def commit_types(pts: List[Point], ms: List[Migration]) -> List[String]:
    """`committype.commit_type` of each commit of `pts`, a commit with a
    Mojo version change in `ms` counting as one."""
    var changed = Dict[String, Bool]()
    for ref m in ms:
        if m.kind == "mojo_version":
            changed[m.sha] = True
    var out = List[String]()
    for ref p in pts:
        out.append(
            commit_type(p.subject, p.sha in changed) if p.subject.byte_length() > 0
            else String()
        )
    return out^

