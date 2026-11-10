# Changelog fragments

Each PR adds its changelog entry here as one file instead of editing
CHANGELOG.md, so open PRs don't conflict there (the same scheme as
orca.mojo's):

```sh
shelf changes new <pr>-<slug> --bump minor   # writes changes/<pr>-<slug>.minor.md
```

The file holds the entry as it will read in the changelog: one bullet, a bold
title and at most one plain sentence on what changed for someone running the
census (say so if deploying needs an action), then the PR number, `(#123)`, in
one or two lines. Details belong in the PR. A PR with several changes may add
a bullet for each. The level comes from the file name (`.patch.md`,
`.minor.md`, `.breaking.md`; none is a patch). CI runs `shelf changes check`:
a PR that changes code needs a fragment, unless it's labelled `no-changelog`.

The census isn't a tin, so `shelf release` doesn't release it. A release is a
PR that runs

```sh
sh scripts/changelog.sh 0.2.0   # the fragments, under "## 0.2.0 - <today>" in CHANGELOG.md
```

and, once it's merged, the tag `v0.2.0` on its merge commit. The tag's CI
pushes `ghcr.io/magmalake/orca:0.2.0` and makes the GitHub release, its notes
the version's section of CHANGELOG.md. This README stays.
