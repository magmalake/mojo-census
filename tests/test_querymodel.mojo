# Search by meaning without a model: the nearest repos to a query vector, and
# a QueryModel that isn't loaded.

from std.testing import assert_equal, assert_false, assert_true, TestSuite

from querymodel import MEANING_FLOOR, MEANING_SHOWN, QueryModel, related
from similar import Embeddings


def _emb(n: Int) -> Embeddings:
    # Repo i at angle i degrees from the query's axis, in 2 dimensions.
    var e = Embeddings()
    e.dim = 2
    from std.math import cos, sin
    for i in range(n):
        e.repos.append(String("r/", i))
        e.inputs.append(String("r", i, ": text"))
        var a = Float32(i) * 3.14159265 / 180
        e.vecs.append(cos(a))
        e.vecs.append(sin(a))
    return e^


def test_related() raises:
    var e = _emb(90)
    var q: List[Float32] = [1, 0]
    var skip = Dict[String, Bool]()
    skip["r/0"] = True
    var r = related(e, q, skip)
    assert_equal(len(r), MEANING_SHOWN)
    assert_equal(e.repos[r[0].index], "r/1")  # r/0 is a text match already
    for k in range(1, len(r)):
        assert_true(r[k - 1].score >= r[k].score)
    # Only those at least MEANING_FLOOR: cos(53 degrees) is just above 0.6.
    var few = related(_emb(60), q, Dict[String, Bool]())
    for ref x in few:
        assert_true(x.score >= MEANING_FLOOR)
    # A vector of another dimension, or none, finds nothing.
    assert_equal(len(related(e, [1, 0, 0], skip)), 0)
    assert_equal(len(related(e, List[Float32](), skip)), 0)


def test_not_loaded() raises:
    var m = QueryModel()
    assert_false(m.ready())
    assert_equal(m.rev(), "")
    assert_equal(len(m.embed("audio")), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
