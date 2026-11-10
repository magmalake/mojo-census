# Changelog

The fragments in [changes/](changes/README.md) are written here at each
release.

## 1.0.0 - 2026-11-10

The census as it ran at mojourney.dev before embeddings, with orca-mojo
0.21.0, tagged after the fact at the merge of #99.

- **GH Archive**: each day from 2023-01-01 into `gharchive.events`, with its candidate, hourly and release tables (`gharchive`, `gharchive_index`).
- **Mojo repositories**: found from the candidates (`mojo_repos`), with their histories, migrations, tags and Mojo versions (`mojo_history`, `mojo_versions`, `mojo_retool`), activity by month (`mojo_activity`) and GitHub stats (`mojo_stats`).
- **The console**: a flare app at mojourney.dev over those tables.
- **The dev stack**: images from the `dev` branch, `orca.dev.toml` and the dev-only `ballast` pipeline (#87, #97, #99).
