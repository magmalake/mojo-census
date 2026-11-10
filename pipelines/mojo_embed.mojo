"""Embeds every Mojo repository's name, description and topics into
mojo.repo_embeddings, for similar repositories, semantic search and
categories on the console.

Daily partitions from 2026-11-10, each filled at 07:00 UTC, after
mojo_stats has refreshed the descriptions (06:00). A run reads every
repository's text (`mojo.repos`, overridden by its latest `ok` row of
`mojo.repo_stats`), and embeds only the repositories whose text or model
changed since their row was written: each row keeps `input_hash`, a hash of
the text and of the model's weights. The others keep their rows, and a run
with nothing new commits nothing. A repository gone from `mojo.repos` loses
its row.

The model is a sentence-transformers directory (magmalake/encoder.mojo):
MOJO_EMBED_MODEL, default build/models/bge-small-en-v1.5, recorded as
MOJO_EMBED_MODEL_NAME (default bge-small-en-v1.5). It is not in the
image: a run downloads the files the directory lacks (133 MB, a few
seconds) from MOJO_EMBED_MODEL_URL, BAAI/bge-small-en-v1.5 on Hugging Face
pinned to a revision, and checks the weights' hash. That hash is the rows'
`model_rev`, so new weights embed everything again on the next run (or at
once: `orca backfill --rerun mojo_embed <day>`).

The table is unpartitioned and rewritten whole by each commit, one
`overwrite` (`replace.replace_files`), as mojo_versions does.

    MOJO_EMBED_MODEL=build/models/bge-small-en-v1.5 \\
        ./build/mojo_embed run --partitions 2026-11-10
"""

from std.os import getenv, makedirs, remove, setenv
from std.os.path import exists
from std.time import perf_counter_ns

from encoder import Encoder
from orca import Cron, Ctx, Current, Daily, Day, Mapped, Pipeline, Step, orca_main
from orca.civil import now
from orca.tables import ensure_table, scan, table

from cols import col, has_col, i32_at, str_at, strs_at
from fetch import get_bytes
from embedtext import (
    EmbedRow,
    embed_batch,
    embed_rows,
    fnv64,
    hex64,
    input_hash,
    repo_input,
    vector_bytes,
)
from lake import REPOS, REPO_EMBEDDINGS, REPO_STATS, repo_embeddings_schema
from replace import replace_files

comptime DEFAULT_MODEL = "build/models/bge-small-en-v1.5"
comptime DEFAULT_URL = (
    "https://huggingface.co/BAAI/bge-small-en-v1.5/resolve/"
    "5c38ec7c405ec4b44b94cc5a9bb96e735b38267a"
)
"""Where a missing model is downloaded from: Hugging Face, pinned to a
revision (MOJO_EMBED_MODEL_URL to change it)."""
comptime DEFAULT_REV = "bbddccb7d85cc5e6"
"""`model_rev` of DEFAULT_URL's weights; a download must hash to
MOJO_EMBED_MODEL_REV (this by default)."""
comptime MODEL_FILES: List[StaticString] = [
    "config.json", "vocab.txt", "1_Pooling/config.json", "model.safetensors",
]
comptime BATCH = 32


def _ensure_model(mut ctx: Ctx, dir: String) raises:
    """Downloads the files of the model missing from `dir`, and checks that
    downloaded weights hash to the expected revision. A directory that has
    them all is used as it is."""
    var missing = List[String]()
    comptime for i in range(len(MODEL_FILES)):
        comptime f = MODEL_FILES[i]
        if not exists(dir + "/" + f):
            missing.append(f)
    if len(missing) == 0:
        return
    var url = getenv("MOJO_EMBED_MODEL_URL", DEFAULT_URL)
    for ref f in missing:
        var path = dir + "/" + f
        var parent = String(path[byte = : path.rfind("/")])
        makedirs(parent, exist_ok=True)
        var t0 = perf_counter_ns()
        # The whole body arrives before the file is opened, so a failed
        # download leaves no file behind; the weights are checked below.
        var body = get_bytes(url + "/" + f)
        with open(path, "w") as out:
            out.write_bytes(Span(body))
        ctx.log(String(
            "downloaded ", f, " (", len(body), " bytes) in ",
            Float64(perf_counter_ns() - t0) / 1e9, " s",
        ))
    if "model.safetensors" in missing:
        var want = getenv("MOJO_EMBED_MODEL_REV", DEFAULT_REV)
        var got = _model_rev(dir)
        if got != want:
            remove(dir + "/model.safetensors")
            raise Error(
                url, "/model.safetensors hashes to ", got, ", expected ", want,
                " (MOJO_EMBED_MODEL_REV); removed",
            )


def _model_rev(dir: String) raises -> String:
    """A hash of the model's weights, which names the model's version."""
    var b: List[UInt8]
    with open(dir + "/model.safetensors", "r") as f:
        b = f.read_bytes()
    return hex64(fnv64(Span(b)))


@fieldwise_init
struct _Text(Copyable, Movable):
    var description: String
    var topics: List[String]
    var as_of: Int64  # the repo_stats day it came from; -1 for mojo.repos


def _texts(mut ctx: Ctx) raises -> Dict[String, _Text]:
    """Each repository of `mojo.repos` with its description and topics, the
    latest `ok` row of `mojo.repo_stats` winning over the row of
    mojo.repos, which is as old as the repository's discovery."""
    var out = Dict[String, _Text]()
    var t = table(ctx, REPOS)
    for b in scan(ctx, t).to_batches():
        var c_repo = col(b, "repo")
        var c_desc = col(b, "description")
        var c_topics = col(b, "topics") if has_col(b, "topics") else -1
        for r in range(b.num_rows):
            var topics = strs_at(b, c_topics, r) if c_topics >= 0 else List[String]()
            out[str_at(b.column(c_repo), r)] = _Text(
                str_at(b.column(c_desc), r), topics^, -1
            )
    var stats: Optional[type_of(t)] = None
    try:
        stats = table(ctx, REPO_STATS)
    except e:
        ctx.log(String(REPO_STATS, " not read (", e, "); using ", REPOS, " alone"))
    if stats:
        for b in scan(ctx, stats.value()).to_batches():
            var c_repo = col(b, "repo")
            var c_as_of = col(b, "as_of")
            var c_state = col(b, "state")
            var c_desc = col(b, "description")
            var c_topics = col(b, "topics")
            for r in range(b.num_rows):
                var repo = str_at(b.column(c_repo), r)
                if repo not in out or str_at(b.column(c_state), r) != "ok":
                    continue
                var as_of = i32_at(b.column(c_as_of), r)
                if as_of <= out[repo].as_of:
                    continue
                out[repo] = _Text(
                    str_at(b.column(c_desc), r), strs_at(b, c_topics, r), as_of
                )
    return out^


def embed(mut ctx: Ctx, d: Day) raises -> Int:
    """Embeds the repositories whose text or model changed and rewrites
    mojo.repo_embeddings with them and the unchanged rows.
    Returns the number of repositories embedded."""
    var dir = getenv("MOJO_EMBED_MODEL", DEFAULT_MODEL)
    var model = getenv("MOJO_EMBED_MODEL_NAME", "bge-small-en-v1.5")
    _ensure_model(ctx, dir)
    var rev = _model_rev(dir)
    var t = ensure_table(ctx, REPO_EMBEDDINGS, repo_embeddings_schema())

    var texts = _texts(ctx)
    var repos = List[String]()
    for e in texts.items():
        repos.append(e.key)
    sort(repos)

    # The current rows, and the files they are in: the commit below removes
    # every file, so the rows read must add up to what the files hold.
    var old = Dict[String, EmbedRow]()
    var files = List[String]()
    var file_rows = Int64(0)
    var read_rows = 0
    if t.metadata.has_current_snapshot:
        for task in scan(ctx, t).plan_files():
            files.append(task.data_file.file_path)
            file_rows += task.data_file.record_count
        for b in scan(ctx, t).to_batches():
            for ref r in embed_rows(b):
                old[r.repo] = r.copy()
                read_rows += 1
        if Int64(read_rows) != file_rows:
            raise Error(
                REPO_EMBEDDINGS, ": read ", read_rows, " rows but its files hold ", file_rows,
            )

    var out = List[EmbedRow]()
    var todo = List[String]()
    var inputs = List[String]()
    var hashes = List[String]()
    for ref repo in repos:
        ref tx = texts[repo]
        var input = repo_input(repo, tx.description, tx.topics)
        var h = input_hash(input, rev)
        var prev = old.get(repo)
        if prev and prev.value().input_hash == h:
            out.append(prev.value().copy())
        else:
            todo.append(repo)
            inputs.append(input^)
            hashes.append(h^)
    var dropped = 0
    for e in old.items():
        if e.key not in texts:
            dropped += 1
    if len(todo) == 0 and dropped == 0 and read_rows == len(out):
        ctx.log(String(
            len(repos), " repositories, all embedded already with ", model,
            " ", rev, "; nothing to commit",
        ))
        return 0

    var embedded_at = now() * 1_000_000
    if len(todo) > 0:
        var t0 = perf_counter_ns()
        var enc = Encoder(dir)
        var load_s = Float64(perf_counter_ns() - t0) / 1e9
        t0 = perf_counter_ns()
        var v = enc.encode(inputs, BATCH)
        var s = Float64(perf_counter_ns() - t0) / 1e9
        var dim = enc.dim()
        for i in range(len(todo)):
            out.append(EmbedRow(
                todo[i], model, rev, hashes[i], inputs[i], dim,
                vector_bytes(v, i * dim, dim), embedded_at,
            ))
        ctx.log(String(
            len(todo), " repositories embedded with ", model, " ", rev,
            " (dim ", dim, ") in ", s, " s, ", Float64(len(todo)) / max(s, 1e-9),
            " a second; model loaded in ", load_s, " s",
        ))
    # One `overwrite` snapshot removing `files` and adding `out`; a retry
    # finds the commit its first attempt made. Safe because one run writes
    # the table at a time (max_runs 1).
    var id = replace_files(ctx, t, files, [embed_batch(out)])
    ctx.log(String(
        String(d), ": ", len(repos), " repositories, ", len(todo), " embedded, ",
        len(out) - len(todo), " kept, ", dropped, " dropped; ", REPO_EMBEDDINGS,
        " ", read_rows, " -> ", len(out), " rows; snapshot ", id,
    ))
    return len(todo)


# `Mapped`: once per partition, here a `Day`. No dista task: the encoder
# runs in the step's process, on all its cores.
comptime Embed = Step[
    "embed",
    Day,
    Int,
    embed,
    Mapped,
    retries=1,
    reads=[REPOS, REPO_STATS, REPO_EMBEDDINGS],
    # replaces=: a rerun rewrites these rows (replace.replace_files) rather than
    # adding them again, so `orca backfill --rerun` needs no --allow-append.
    # Under replaces=, an orca.tables `append` to them would replace whole
    # partitions, other keys' rows included: keep writing through replace_files.
    replaces=[REPO_EMBEDDINGS],
]
# Daily at 07:00 UTC, an hour after mojo_stats. A day's run embeds what
# changed since the last, so a missed day needs no catch-up.
comptime MojoEmbed = Pipeline[
    "mojo_embed",
    Embed,
    partitions=Daily["2026-11-10"],
    schedule=Cron["0 7 * * *"],
    fills=Current,
    catchup=False,
]


def main() raises:
    if not getenv("ORCA_WAREHOUSE"):
        _ = setenv("ORCA_WAREHOUSE", "build/warehouse")
    orca_main[MojoEmbed]()
