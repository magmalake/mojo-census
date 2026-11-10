# Repo categories: the rules on the embedded text, the vote of the nearest
# labelled repos (small hand-made vectors), and the /repos filter's query.

from std.testing import assert_equal, assert_false, assert_true, TestSuite

from categories import by_rule, categorize, category_keys, category_title, examples, is_category
from listing import list_url, parse_list_query, select_repos, with_category
from similar import Embeddings


def test_rules() raises:
    assert_equal(by_rule("mojo thing"), "other")  # no description
    assert_equal(by_rule("mojo zlib: Bindings for zlib in Mojo, follows the Python api."), "ffi")
    assert_equal(by_rule("x: Mojo bindings to libfoo."), "ffi")
    assert_equal(by_rule("x: A wrapper around libcurl."), "ffi")
    assert_equal(by_rule("x: TCP sockets via C FFI."), "ffi")
    assert_equal(by_rule("raylib mojo: Mojo bindings for raylib."), "games")
    assert_equal(by_rule("x: Bindings for SDL3 in Mojo."), "games")
    assert_equal(by_rule("mojo pytz: Mojo port of pytz - timezone offsets."), "tooling")
    assert_equal(by_rule("x: Port of numpy."), "tooling")
    # Not "port of": the vote decides.
    assert_equal(by_rule("x: Support of many formats."), "")
    assert_equal(by_rule("x: A GPT in Mojo."), "")
    assert_equal(by_rule("x Topics: gpu"), "")


def _emb(names: List[String], inputs: List[String], vecs: List[List[Float32]]) -> Embeddings:
    var e = Embeddings()
    e.dim = len(vecs[0])
    for i in range(len(names)):
        e.repos.append(names[i])
        e.inputs.append(inputs[i])
        for x in vecs[i]:
            e.vecs.append(x)
    e.snapshot = 1
    return e^


def test_vote_of_the_nearest_examples() raises:
    # Two real example names, an ml one and a web one, and repos near each.
    var names: List[String] = [
        "basalt-org/basalt", "atsentia/mojo-redis", "a/near-ml", "a/near-web", "a/bare",
        "a/port",
    ]
    var inputs: List[String] = [
        "basalt: ML framework.", "mojo redis: Redis client.", "near ml: tensors.",
        "near web: sockets.", "bare", "p: Mojo port of attrs.",
    ]
    var vecs: List[List[Float32]] = [
        [1, 0, 0], [0, 1, 0], [0.9, 0.1, 0], [0.1, 0.9, 0], [1, 0, 0], [0, 1, 0],
    ]
    var cats = categorize(_emb(names, inputs, vecs))
    assert_equal(cats["a/near-ml"], "ml")
    assert_equal(cats["a/near-web"], "web")
    assert_equal(cats["a/bare"], "other")
    assert_equal(cats["a/port"], "tooling")
    # An example doesn't vote for itself: the only other example decides.
    assert_equal(cats["basalt-org/basalt"], "web")
    assert_equal(len(categorize(Embeddings())), 0)


def test_examples_and_keys() raises:
    var seen = Dict[String, Bool]()
    for ref line in examples():
        var parts = line.split(" ")
        assert_equal(len(parts), 2)
        assert_true(is_category(String(parts[0])))
        assert_true(String(parts[0]) != "other")
        assert_false(String(parts[1]) in seen)
        seen[String(parts[1])] = True
    assert_equal(len(seen), 72)
    for ref k in category_keys():
        assert_true(category_title(k) != k)
    assert_false(is_category("bogus"))


def test_listing_filter() raises:
    var q = parse_list_query("", "", "", "", "", "", "ffi")
    assert_equal(q.category, "ffi")
    assert_true(q.has_filter())
    assert_equal(list_url(q), "/repos?category=ffi")
    assert_equal(parse_list_query("", "", "", "", "", "", "bogus").category, "")
    assert_equal(list_url(with_category(q, String())), "/repos")
    var lines: List[Int64] = [30, 20, 10]
    var fam: List[String] = ["1.2", "1.2", "1.2"]
    var active: List[Bool] = [True, True, True]
    var cats: List[String] = ["ffi", "ml", "ffi"]
    var idx = select_repos(
        q, lines, lines, lines, fam, active, List[String](), List[Int](), List[Int64](),
        List[Int64](), List[Int64](), cats,
    )
    assert_equal(len(idx), 2)
    assert_equal(idx[0], 0)
    assert_equal(idx[1], 2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
