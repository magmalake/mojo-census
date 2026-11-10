# Changelog

The fragments in [changes/](changes/README.md) are written here at each
release.

## 0.1.0 - 2026-11-10

The first tagged release: the image `ghcr.io/magmalake/orca:0.1.0`, with
orca-mojo 0.21.1.

- **`mojo_embed`, repository embeddings**: a daily pipeline (07:00 UTC) writes `mojo.repo_embeddings`, a bge-small-en-v1.5 vector per repository from its description and topics, with encoder-mojo 0.1.0 on the CPU; it re-embeds only repositories whose text changed and downloads the model (133 MB) to `MOJO_EMBED_MODEL` on its first run. (#100, #103)

- **orca 0.21.1**: runs held at their memory limit are killed and retried bigger, out-of-memory raises expire after 20 good runs, and learned CPUs fit the host. (#104)

- **The census so far**: GH Archive into `gharchive.events` and its candidate, hourly and release tables (`gharchive`), Mojo repositories found from them (`mojo_repos`), their histories, migrations, tags and Mojo versions (`mojo_history`, `mojo_versions`), activity by month (`mojo_activity`) and GitHub stats (`mojo_stats`), read by the flare console at mojourney.dev.
