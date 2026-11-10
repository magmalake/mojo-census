"""The sentence-embedding model mojo_embed embeds with and the console
embeds search queries with: where it is downloaded from, its files, and the
hash of its weights that names its revision (`model_rev`)."""

from std.os import getenv, makedirs, remove
from std.os.path import exists
from std.time import perf_counter_ns

from embedtext import fnv64, hex64
from fetch import get_bytes


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
comptime QUERY_PREFIX = "Represent this sentence for searching relevant passages: "
"""What bge models want before a short search query (not before the texts
searched)."""


def ensure_model(dir: String) raises -> List[String]:
    """Downloads the files of the model missing from `dir`, and checks that
    downloaded weights hash to the expected revision. A directory that has
    them all is used as it is. Returns a line to log per download."""
    var files: List[String] = [
        "config.json", "vocab.txt", "1_Pooling/config.json", "model.safetensors",
    ]
    var log = List[String]()
    var missing = List[String]()
    for ref f in files:
        if not exists(dir + "/" + f):
            missing.append(f)
    if len(missing) == 0:
        return log^
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
        log.append(String(
            "downloaded ", f, " (", len(body), " bytes) in ",
            Float64(perf_counter_ns() - t0) / 1e9, " s",
        ))
    if "model.safetensors" in missing:
        var want = getenv("MOJO_EMBED_MODEL_REV", DEFAULT_REV)
        var got = model_rev(dir)
        if got != want:
            remove(dir + "/model.safetensors")
            raise Error(
                url, "/model.safetensors hashes to ", got, ", expected ", want,
                " (MOJO_EMBED_MODEL_REV); removed",
            )
    return log^


def model_rev(dir: String) raises -> String:
    """A hash of the model's weights, which names the model's version."""
    var b: List[UInt8]
    with open(dir + "/model.safetensors", "r") as f:
        b = f.read_bytes()
    return hex64(fnv64(Span(b)))
