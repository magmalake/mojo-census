# Changelog fragments

Each PR adds its changelog entry here as one file instead of editing
CHANGELOG.md, so open PRs don't conflict there (the same scheme as
morca's):

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

A change that needs something done around its deploy (a backfill after it,
a check before it) adds its steps beside the fragment, as
`changes/<pr>-<slug>.after.toml`; steps that belong to the release rather than
to one PR go in `changes/release.after.toml`:

```toml
[[step]]
id = "1.3.0-retool-subjects"     # unique and stable: a release's steps are shown once
when = "after"                   # before (checked before the new image starts) or after
run = "morca backfill --rerun mojo_retool @all"   # a morca command, run in the scheduler
# or: manual = "What to do or check, for a person."
```

One `key = "value"` per line. The release writes them into `upgrade.toml`
(shipped in the image for deploy.sh, morca#323) and into the version's
changelog section, under "Before deploying" and "After deploying".

The census isn't a tin, so `shelf release` doesn't release it. A release is a
PR that runs

```sh
sh scripts/changelog.sh 0.2.0   # the fragments, under "## 0.2.0 - <today>" in CHANGELOG.md
```

and, once it's merged, the tag `v0.2.0` on its merge commit. The tag's CI
pushes `ghcr.io/morca-dev/census:0.2.0` and makes the GitHub release, its notes
the version's section of CHANGELOG.md. This README stays.
