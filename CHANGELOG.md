# Changelog

The fragments in [changes/](changes/README.md) are written here at each
release.

## 1.3.0 - 2026-11-11

- **Commit subjects**: `mojo.commits` keeps each commit's subject line. (#102, #131)

- **Commit types**: each commit is labelled feature, fix, Mojo version, migration and so on from its subject, on the repo page and in the JSON. (#121, #132)

- **Live page**: `mojo_live` polls every census repo every 3 minutes; `/live` shows the new commits and how fresh they are. (#123, #134)

- **Version in the footer**: the console shows the release it runs. (#136)

- **Release steps**: a release's before- and after-deploy steps ship in the image as `upgrade.toml`, for deploy.sh to show and run. (#137, #138)

- **Build on Debian**: the image's build stages start from pixi's bookworm image, like its runtime stages. (#141)

**Before deploying:**

- Deploy with orca's deploy package 0.23.0 (`orca-hetzner-0.23.0`) or later: its deploy.sh reads `upgrade.toml` and runs the step below. An older one doesn't, so run it by hand.

**After deploying** (deploy.sh shows these and runs the commands):

- Run `orca backfill --rerun mojo_retool @all`.

## 1.2.0 - 2026-11-11

- **Python build tools and packaging**: tooling knows uv, poetry, pdm and pip; a new `packaging` column (rattler, conda-build). Run `mojo_retool` after deploying. (#118)

- **Issues and pull requests**: a daily pipeline, `mojo_issues` (08:00 UTC), keeps every census repo's issues and pull requests in `mojo.issues` from the GitHub API; each repo page lists its open issues and newest pull requests. Needs the GitHub token secret, as mojo_stats does. (#120, #127)

- **Embedding model from the bucket**: mojo_embed and the console fetch the model from the stack's bucket, copied there from Hugging Face once. (#128)

## 1.1.0 - 2026-11-10

- **`mojo_embed`, repository embeddings**: a daily pipeline (07:00 UTC) writes `mojo.repo_embeddings`, a bge-small-en-v1.5 vector per repository from its description and topics, with encoder-mojo 0.1.0 on the CPU; it re-embeds only repositories whose text changed and downloads the model (133 MB) to `MOJO_EMBED_MODEL` on its first run. (#100, #103)

- **orca 0.21.1**: runs held at their memory limit are killed and retried bigger, out-of-memory raises expire after 20 good runs, and learned CPUs fit the host. (#104)

- **A changelog and GitHub releases**: each PR adds a fragment to `changes/`, `scripts/changelog.sh` writes them here at a release, and a tag's CI makes its GitHub release from its section. (#105)

- **A Changelog tab**: How it works has a third tab, `/how/changelog`, with CHANGELOG.md, each entry linking its pull request; the image carries the file at `/opt/orca/CHANGELOG.md` (`CENSUS_CHANGELOG`). (#107)

- **A lab stack**: `orca.lab.toml` and `lab` images, for testing orca. (#108)

- **amd64 images**: each image is built for arm64 and amd64. (#109)

- **Reruns without `--allow-append`**: four pipelines that rewrite their rows declare `replaces=`, on orca 0.22.0. (#111)
- **Search model uses less memory**: encoder.mojo with the sized safetensors read (encoder #6). (#111)

- **Similar repos**: each repo page and its JSON list the 5 repos nearest it by embedding, with the model and snapshot they come from. (#101, #112)

- **Repo categories**: each repo gets an approximate category (ML, bindings, libraries, learning, games, web, other) from its description and embedding, as a filter on /repos, a tile on its page and a table on the overview. (#101, #113)

- **Search by meaning**: /search and /api/search list repos related to the query by embedding after the text matches; the console downloads the model (133 MB) on its first start and needs about 270 MB more memory; `CONSOLE_SEMANTIC=0` turns it off. (#101, #114)

## 1.0.0 - 2026-11-10

The census as it ran at mojourney.dev before embeddings, with orca-mojo
0.21.0, tagged after the fact at the merge of #99.

- **GH Archive**: each day from 2023-01-01 into `gharchive.events`, with its candidate, hourly and release tables (`gharchive`, `gharchive_index`).
- **Mojo repositories**: found from the candidates (`mojo_repos`), with their histories, migrations, tags and Mojo versions (`mojo_history`, `mojo_versions`, `mojo_retool`), activity by month (`mojo_activity`) and GitHub stats (`mojo_stats`).
- **The console**: a flare app at mojourney.dev over those tables.
- **The dev stack**: images from the `dev` branch, `orca.dev.toml` and the dev-only `ballast` pipeline (#87, #97, #99).
