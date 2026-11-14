"""What a lib-tin boundary costs (spike, morca #445).

    mojo build -I libtins/lake libtins/smoke/boundary_bench.mojo -o build/bb
    LAKE_LIB=libtins/lake/liblake.dylib build/bb

1. A call into liblake through a dlsym'd C function pointer.
2. Rows crossing as Arrow C Data Interface structs, as `lake_append` and
   `lake_scan` move them: export (one copy of every buffer) then import
   (a second copy), for a batch of int64 and utf8 columns.
"""

from std.ffi import OwnedDLHandle, RTLD
from std.os import getenv
from std.time import perf_counter_ns

from arrow_mlake import AT_INT64, AT_STRUCT, AT_UTF8, ArrayArena, ArrayData, ArrowType, bit_set, store_u64
from arrow_mlake.batch import RecordBatch
from arrow_mlake.carrow import export_c
from arrow_mlake.carrow_import import ImportedArray

comptime _VersionFn = def() thin abi("C") -> UInt32
comptime _HasFn = def(Int) thin abi("C") -> Int


def _sym[FT: TrivialRegisterPassable](lib: OwnedDLHandle, name: String) raises -> FT:
    var opt = lib.get_symbol[FT](name)
    var addr: Int = Int(opt.value())
    return Pointer(to=addr).unsafe_bitcast[FT]()[]


@no_inline
def _local_version() -> UInt32:
    return 1


def batch_of(rows: Int) -> RecordBatch:
    var arena = ArrayArena()
    var a = ArrayData(ArrowType(AT_INT64), String("id"))
    var s = ArrayData(ArrowType(AT_UTF8), String("name"))
    s.offsets.append(0)
    for i in range(rows):
        store_u64(a.values, UInt64(i))
        bit_set(a.validity, i, True)
        var t = String("repo-", i, "/some-name")
        s.values.extend(t.as_bytes())
        s.offsets.append(Int32(len(s.values)))
        bit_set(s.validity, i, True)
    a.length = rows
    s.length = rows
    var b = RecordBatch()
    b.roots.append(arena.add(a^))
    b.roots.append(arena.add(s^))
    b.arena = arena^
    b.num_rows = rows
    return b^


def main() raises:
    var lib = OwnedDLHandle(getenv("LAKE_LIB", "liblake.dylib"), RTLD.NOW | RTLD.LOCAL)
    var version = _sym[_VersionFn](lib, "lake_abi_version")
    print("loaded, abi", version())
    # `lib` must outlive every call through its symbols: Mojo destroys it
    # after its last use (here, `_sym`), and dlclose unmaps the code. The
    # wrappers keep it in a struct and open with RTLD_NODELETE.
    comptime N = 20_000_000
    var acc = UInt32(0)
    var t0 = perf_counter_ns()
    for _ in range(N):
        acc += version()
    var t1 = perf_counter_ns()
    for _ in range(N):
        acc += _local_version()
    var t2 = perf_counter_ns()
    print("call through liblake:", Float64(t1 - t0) / N, "ns; local no_inline call:", Float64(t2 - t1) / N, "ns (", acc, ")")

    for rows in [1_000, 100_000, 1_000_000]:
        var b = batch_of(rows)
        var bytes = len(b.arena.nodes[b.roots[0]].values) + len(b.arena.nodes[b.roots[1]].values) + 4 * (rows + 1)
        var reps = max(1, 2_000_000 // rows)
        var e0 = perf_counter_ns()
        var got = 0
        for _ in range(reps):
            var arena = b.arena.copy()
            var st = ArrayData(ArrowType(AT_STRUCT), String())
            st.nullable = False
            st.length = b.num_rows
            st.children = b.roots.copy()
            var root = arena.add(st^)
            var ex = export_c(arena, root)
            var pair = ex.into_raw()
            var imp = ImportedArray(pair[0], pair[1])
            got += imp.into_batch().num_rows
        var e1 = perf_counter_ns()
        var per = Float64(e1 - e0) / Float64(reps)
        print(rows, "rows,", bytes // 1000, "kB: export+import", per / 1000.0, "us per batch,",
            per / Float64(rows), "ns per row,", Float64(bytes) / per, "GB/s (", got, ")")
    _ = lib^
