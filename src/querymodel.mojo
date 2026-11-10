"""The console's search-query encoder: the model mojo_embed embeds repos
with, loaded once by the refresher thread and shared by the request handlers,
one query at a time."""

from std.memory import ArcPointer
from std.os import getenv

from encoder import Encoder
from threads import Mutex

from embedmodel import QUERY_PREFIX, ensure_model, model_rev
from similar import Embeddings


comptime CONSOLE_MODEL = "/tmp/mojo-census/models/bge-small-en-v1.5"
"""Where the console keeps the model unless MOJO_EMBED_MODEL says otherwise;
downloaded on its first start (133 MB)."""
comptime MEANING_SHOWN = 20
comptime MEANING_FLOOR = Float32(0.6)
"""The least cosine (with `QUERY_PREFIX`) a repo needs to be listed as
related by meaning; below it the matches are mostly noise."""


struct Loaded(Movable):
    var lock: Mutex
    var enc: Encoder
    var rev: String
    """`model_rev` of its weights: only embeddings of the same revision are
    compared with its queries."""

    def __init__(out self, var enc: Encoder, rev: String) raises:
        self.lock = Mutex()
        self.enc = enc^
        self.rev = rev


struct QueryModel(Movable):
    """No model, or one loaded (`load`)."""

    var loaded: Optional[ArcPointer[Loaded]]

    def __init__(out self):
        self.loaded = None

    def __init__(out self, var l: Loaded):
        self.loaded = ArcPointer(l^)

    def ready(self) -> Bool:
        return Bool(self.loaded)

    def rev(self) -> String:
        if not self.loaded:
            return String()
        return self.loaded.value()[].rev

    def embed(self, query: String) raises -> List[Float32]:
        """The query's embedding (normalized), or empty without a model."""
        if not self.loaded:
            return List[Float32]()
        ref l = self.loaded.value()[]
        l.lock.lock()
        try:
            var v = l.enc.encode([String(QUERY_PREFIX, query)], 1)
            l.lock.unlock()
            return v^
        except e:
            l.lock.unlock()
            raise e^


def semantic_on() -> Bool:
    """Off with CONSOLE_SEMANTIC=0."""
    return getenv("CONSOLE_SEMANTIC", "1") != "0"


def load_model() raises -> QueryModel:
    """Downloads the model if it's missing and loads it."""
    var dir = getenv("MOJO_EMBED_MODEL", CONSOLE_MODEL)
    for ref line in ensure_model(dir):
        print("console:", line)
    var rev = model_rev(dir)
    return QueryModel(Loaded(Encoder(dir), rev))


@fieldwise_init
struct Related(Copyable, Movable):
    var index: Int
    """Into `Embeddings.repos`."""
    var score: Float32


def related(e: Embeddings, q: List[Float32], skip: Dict[String, Bool]) -> List[Related]:
    """The repos of `e` nearest the query vector `q` (at least `MEANING_FLOOR`,
    at most `MEANING_SHOWN`), highest first, leaving out those in `skip`."""
    var out = List[Related]()
    if len(q) != e.dim or e.dim == 0:
        return out^
    var d = e.dim
    for i in range(len(e.repos)):
        if e.repos[i] in skip:
            continue
        var s = Float32(0)
        for j in range(d):
            s += q[j] * e.vecs[i * d + j]
        if s < MEANING_FLOOR:
            continue
        var p = len(out)
        while p > 0 and out[p - 1].score < s:
            p -= 1
        if p < MEANING_SHOWN:
            out.insert(p, Related(i, s))
            if len(out) > MEANING_SHOWN:
                _ = out.pop()
    return out^
