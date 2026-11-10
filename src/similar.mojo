"""Similar repos from mojo.repo_embeddings (mojo_embed): each repo's
nearest others by the cosine of their embeddings, worked out by brute force
when the console's cache is built (a few thousand repos of 384 floats).

Only one model's vectors are compared: the model and revision of the newest
row. While mojo_embed is re-embedding with new weights, the repos not done
yet are left out rather than ranked against vectors of another model.
"""

from embedtext import EmbedRow, embed_rows, vector_of
from lake import try_load


comptime SIMILAR_SHOWN = 5
"""How many similar repos a repo's page and JSON list."""


@fieldwise_init
struct Neighbor(Copyable, Movable):
    var repo: String
    var score: Float32
    """The cosine of the two embeddings (they are L2-normalized)."""


struct Embeddings(Movable):
    """One vector per repo, all of one model and revision."""

    var repos: List[String]
    var vecs: List[Float32]
    """`dim` values per repo, in `repos`' order."""
    var inputs: List[String]
    """The text each was embedded from."""
    var dim: Int
    var model: String
    var model_rev: String
    var snapshot: Int64
    """The mojo.repo_embeddings snapshot read, -1 for none."""
    var embedded_at: Int64
    """The newest row's `embedded_at`, in microseconds."""

    def __init__(out self):
        self.repos = List[String]()
        self.vecs = List[Float32]()
        self.inputs = List[String]()
        self.dim = 0
        self.model = String()
        self.model_rev = String()
        self.snapshot = -1
        self.embedded_at = 0


def latest_of(rows: List[EmbedRow], snapshot: Int64 = -1) -> Embeddings:
    """Each repo's newest row of the newest row's model and revision; rows
    whose vector isn't `dim` float32 values are skipped."""
    var out = Embeddings()
    out.snapshot = snapshot
    var newest = -1
    for i in range(len(rows)):
        if newest < 0 or rows[i].embedded_at > rows[newest].embedded_at:
            newest = i
    if newest < 0:
        return out^
    out.model = rows[newest].model
    out.model_rev = rows[newest].model_rev
    out.dim = rows[newest].dim
    out.embedded_at = rows[newest].embedded_at
    var pick = Dict[String, Int]()
    for i in range(len(rows)):
        ref r = rows[i]
        if r.model != out.model or r.model_rev != out.model_rev or r.dim != out.dim:
            continue
        if len(r.vector) != 4 * r.dim:
            continue
        var at = pick.get(r.repo, -1)
        if at < 0 or r.embedded_at > rows[at].embedded_at:
            pick[r.repo] = i
    var names = List[String]()
    for e in pick.items():
        names.append(e.key)
    sort(names)
    var order = List[Int]()
    for ref n in names:
        order.append(pick.get(n, 0))
    for i in range(len(names)):
        out.repos.append(names[i])
        out.inputs.append(rows[order[i]].input)
        var v = vector_of(rows[order[i]].vector)
        for x in v:
            out.vecs.append(x)
    return out^


def read_embeddings() raises -> Embeddings:
    """`latest_of` mojo.repo_embeddings' current snapshot; empty when the
    table doesn't exist or has no snapshot."""
    var t = try_load("mojo", "repo_embeddings")
    if not t or not t.value().metadata.has_current_snapshot:
        return Embeddings()
    var rows = List[EmbedRow]()
    for b in t.value().scan().to_batches():
        for r in embed_rows(b):
            rows.append(r.copy())
    return latest_of(rows, t.value().metadata.current_snapshot_id)


def _insert(mut top: List[Neighbor], var n: Neighbor, k: Int):
    """Adds `n` to `top` (highest score first, then by name) if it makes the
    first `k`."""
    var i = len(top)
    while i > 0 and (
        top[i - 1].score < n.score
        or (top[i - 1].score == n.score and top[i - 1].repo > n.repo)
    ):
        i -= 1
    if i >= k:
        return
    top.insert(i, n^)
    if len(top) > k:
        _ = top.pop()


def nearest(
    e: Embeddings, keep: Dict[String, Bool], k: Int = SIMILAR_SHOWN
) -> Dict[String, List[Neighbor]]:
    """Each repo of `e` in `keep`: the `k` others in `keep` with the highest
    cosine, highest first. Each pair's dot product is computed once."""
    var idx = List[Int]()
    for i in range(len(e.repos)):
        if e.repos[i] in keep:
            idx.append(i)
    var tops = List[List[Neighbor]]()
    for _ in range(len(idx)):
        tops.append(List[Neighbor]())
    var d = e.dim
    for a in range(len(idx)):
        var oa = idx[a] * d
        for b in range(a + 1, len(idx)):
            var ob = idx[b] * d
            var s = Float32(0)
            for j in range(d):
                s += e.vecs[oa + j] * e.vecs[ob + j]
            _insert(tops[a], Neighbor(e.repos[idx[b]], s), k)
            _insert(tops[b], Neighbor(e.repos[idx[a]], s), k)
    var out = Dict[String, List[Neighbor]]()
    for a in range(len(idx)):
        out[e.repos[idx[a]]] = tops[a].copy()
    return out^
