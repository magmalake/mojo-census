"""The thin Mojo side of the lake lib-tin (spike, morca #445): morca's
Iceberg tables through liblake's C ABI instead of compiled into the
program. Nothing here imports iceberg or reaches parquet's code; rows are
`arrow_mlake` batches, crossing as Arrow C Data Interface structs.

    var lake = Lake(ctx)                 # loads liblake (late: fork safety)
    var t = lake.table("mojo.repos")
    for b in lake.scan(t, ["repo"]): ...
    var n = lake.append(t, batches)

`LAKE_LIB` names the library file (default `liblake.dylib` / `.so` beside
the binary's search path). See libtins/lake/lake_abi.mojo for the ABI.
"""

from std.ffi import OwnedDLHandle, RTLD
from std.memory.alloc import unsafe_alloc
from std.os import getenv
from std.sys import CompilationTarget

from arrow_mlake import (
    AT_INT64,
    AT_LIST,
    AT_STRUCT,
    AT_UTF8,
    TU_MICRO,
    ArrayArena,
    ArrayData,
    ArrowType,
    at_timestamp,
    bit_set,
    store_u64,
)
from arrow_mlake.batch import RecordBatch
from arrow_mlake.carrow import ExportedArray, export_c
from arrow_mlake.carrow_import import ImportedStream

from morca import Ctx

comptime ABI_VERSION: UInt32 = 1
comptime HOST_SIZE = 104

comptime _VersionFn = def() thin abi("C") -> UInt32
comptime _FreeFn = def(Int) thin abi("C") -> None
comptime _TableFn = def(Int, Int, Int, Int) thin abi("C") -> Int
comptime _EnsureFn = def(Int, Int, Int, Int, Int, Int) thin abi("C") -> Int
comptime _HasFn = def(Int) thin abi("C") -> Int
comptime _ScanFn = def(Int, Int, Int, Int, Int, Int) thin abi("C") -> Int32
comptime _PlanFn = def(Int, Int, Int, Int) thin abi("C") -> Int
comptime _FindFn = def(Int, Int) thin abi("C") -> Int64
comptime _AppendFn = def(Int, Int, Int, Int, Int, Int) thin abi("C") -> Int64
comptime _CommitFn = def(
    Int, Int, Int, Int, Int, Int, Int, Int, Int, Int
) thin abi("C") -> Int64

comptime _CheckDeclaredFn = def(Int, Int, Int, Int) thin abi("C") -> Int32
comptime _PinFn = def(Int, Int, Int, Int64, Int, Int, Int) thin abi("C") -> Int32
comptime _FenceFn = def(Int) thin abi("C") -> Int32
comptime _CommittedFn = def(Int, Int, Int, Int64, Int, Int) thin abi("C") -> Int32
comptime _SummaryFn = def(Int, Int, Int, Int) thin abi("C") -> Int
comptime _SameRunFn = def(Int, Int, Int) thin abi("C") -> Int32
comptime _MadeFn = def(Int, Int, Int, Int, Int) thin abi("C") -> Int32
comptime _NameFn = def(Int, Int, Int) thin abi("C") -> Int32
comptime _LogFn = def(Int, Int, Int) thin abi("C") -> None
comptime _TextFn = def(Int, Int) thin abi("C") -> Int


# ── bytes ───────────────────────────────────────────────────────────────────


def _get(block: Int, at: Int) -> Int:
    return Pointer[Int, MutUntrackedOrigin](unsafe_from_address=block + at)[]


def _put(block: Int, at: Int, v: Int):
    Pointer[Int, MutUntrackedOrigin](unsafe_from_address=block + at)[] = v


def _text(addr: Int, n: Int) -> String:
    if n <= 0 or addr == 0:
        return String()
    var buf = List[UInt8](capacity=n)
    var p = Pointer[UInt8, ImmUntrackedOrigin](unsafe_from_address=addr)
    for i in range(n):
        buf.append(p[unsafe_offset=i])
    return String(unsafe_from_utf8=Span(buf))


def _encode_map(d: Dict[String, String]) -> String:
    var out = String()
    for e in d.items():
        out.write(e.key, "\x1f", e.value, "\x1e")
    return out^


def _decode_map(s: String) -> Dict[String, String]:
    var d = Dict[String, String]()
    for rec in s.split("\x1e"):
        if not rec:
            continue
        var kv = rec.split("\x1f")
        if len(kv) == 2:
            d[String(kv[0])] = String(kv[1])
    return d^


def _sym[FT: TrivialRegisterPassable](lib: OwnedDLHandle, name: String) raises -> FT:
    var opt = lib.get_symbol[FT](name)
    if not opt:
        raise Error("lake: liblake has no symbol ", name)
    var addr: Int = Int(opt.value())
    return Pointer(to=addr).unsafe_bitcast[FT]()[]


# ── the host: callbacks into the step's Ctx ─────────────────────────────────


struct _HostState(Movable):
    var ctx: Int
    var scratch: String
    var err: String

    def __init__(out self, ctx: Int):
        self.ctx = ctx
        self.scratch = String()
        self.err = String()


def _st(state: Int) -> Pointer[_HostState, MutAnyOrigin]:
    return Pointer[_HostState, MutAnyOrigin](unsafe_from_address=state)


def _ctx(state: Int) -> Pointer[Ctx, MutAnyOrigin]:
    return Pointer[Ctx, MutAnyOrigin](unsafe_from_address=_st(state)[].ctx)


def _on_check_declared(state: Int, ds: Int, n: Int, write: Int) abi("C") -> Int32:
    try:
        _ctx(state)[].check_declared(_text(ds, n), write=write != 0)
        return 0
    except e:
        _st(state)[].err = String(e)
        return 1


def _on_pin(
    state: Int, loc: Int, n: Int, current: Int64, ds: Int, dn: Int, out_id: Int
) abi("C") -> Int32:
    try:
        var id = _ctx(state)[].pin(_text(loc, n), current, _text(ds, dn))
        Pointer[Int64, MutUntrackedOrigin](unsafe_from_address=out_id)[] = id
        return 0
    except e:
        _st(state)[].err = String(e)
        return 1


def _on_fence(state: Int) abi("C") -> Int32:
    try:
        _ctx(state)[].fence()
        return 0
    except e:
        _st(state)[].err = String(e)
        return 1


def _on_committed(
    state: Int, loc: Int, n: Int, id: Int64, ds: Int, dn: Int
) abi("C") -> Int32:
    try:
        _ctx(state)[].committed(_text(loc, n), id, _text(ds, dn))
        return 0
    except e:
        _st(state)[].err = String(e)
        return 1


def _on_summary(state: Int, loc: Int, n: Int, out_n: Int) abi("C") -> Int:
    ref s = _st(state)[]
    s.scratch = _encode_map(_ctx(state)[].summary(_text(loc, n)))
    _put(out_n, 0, s.scratch.byte_length())
    return Int(s.scratch.unsafe_ptr())


def _on_same_run(state: Int, t: Int, n: Int) abi("C") -> Int32:
    return 1 if _ctx(state)[].same_run(_decode_map(_text(t, n))) else 0


def _on_made(state: Int, loc: Int, n: Int, t: Int, tn: Int) abi("C") -> Int32:
    return 1 if _ctx(state)[].made(_text(loc, n), _decode_map(_text(t, tn))) else 0


def _on_replaces(state: Int, ds: Int, n: Int) abi("C") -> Int32:
    return 1 if _ctx(state)[].replaces(_text(ds, n)) else 0


def _on_declares_write(state: Int, ds: Int, n: Int) abi("C") -> Int32:
    return 1 if _text(ds, n) in _ctx(state)[].declared_writes else 0


def _on_log(state: Int, msg: Int, n: Int) abi("C") -> None:
    _ctx(state)[].log(_text(msg, n))


def _on_commits(state: Int, out_n: Int) abi("C") -> Int:
    ref s = _st(state)[]
    var t = String()
    for c in _ctx(state)[].commits:
        t.write(c.table, "\x1f", c.snapshot_id, "\x1e")
    s.scratch = t^
    _put(out_n, 0, s.scratch.byte_length())
    return Int(s.scratch.unsafe_ptr())


def _on_error(state: Int, out_n: Int) abi("C") -> Int:
    ref s = _st(state)[]
    _put(out_n, 0, s.err.byte_length())
    return Int(s.err.unsafe_ptr())


# ── tables and the library ──────────────────────────────────────────────────


struct _Slot(Movable):
    """A heap out-parameter (see lake_abi.Slot)."""

    var addr: Int

    def __init__(out self):
        var p = unsafe_alloc[Int](1)
        p[] = 0
        self.addr = Int(p)

    def get(self) -> Int:
        return _get(self.addr, 0)

    def __del__(deinit self):
        Pointer[Int, MutUntrackedOrigin](unsafe_from_address=self.addr).unsafe_free()


struct LakeTable(Movable):
    """A table the library holds; freed with it."""

    var handle: Int
    var _free: _FreeFn
    var _has: _HasFn

    def __init__(out self, handle: Int, free: _FreeFn, has: _HasFn):
        self.handle = handle
        self._free = free
        self._has = has

    def has_current_snapshot(self) -> Bool:
        return self._has(self.handle) != 0

    def __del__(deinit self):
        self._free(self.handle)


def _lib_file() -> String:
    var f = getenv("LAKE_LIB")
    if f:
        return f^
    comptime if CompilationTarget.is_macos():
        return "liblake.dylib"
    else:
        return "liblake.so"


def _export_batch(b: RecordBatch) raises -> ExportedArray:
    var arena = b.arena.copy()
    var st = ArrayData(ArrowType(AT_STRUCT), String())
    st.nullable = False
    st.length = b.num_rows
    st.children = b.roots.copy()
    var root = arena.add(st^)
    return export_c(arena, root)


struct Lake(Movable):
    """liblake, open, bound to one step's `Ctx` (whose address it keeps:
    the Ctx must outlive it)."""

    var lib: OwnedDLHandle
    var host: Int
    var state: Pointer[_HostState, MutUntrackedOrigin]
    var err: Int
    var _free_text: _FreeFn
    var _free_table: _FreeFn
    var _has: _HasFn
    var _table: _TableFn
    var _ensure: _EnsureFn
    var _scan: _ScanFn
    var _plan: _PlanFn
    var _find: _FindFn
    var _append: _AppendFn
    var _commit: _CommitFn

    def __init__(out self, mut ctx: Ctx) raises:
        comptime FLAGS = RTLD.NOW | RTLD.LOCAL | RTLD.NODELETE
        var file = _lib_file()
        try:
            self.lib = OwnedDLHandle(file, FLAGS)
        except e:
            raise Error("lake: can't load ", file, ": ", e)
        var v = _sym[_VersionFn](self.lib, "lake_abi_version")()
        if v != ABI_VERSION:
            raise Error("lake: ", file, " has ABI ", v, ", this wrapper speaks ", ABI_VERSION)
        self._free_text = _sym[_FreeFn](self.lib, "lake_free_text")
        self._free_table = _sym[_FreeFn](self.lib, "lake_free_table")
        self._has = _sym[_HasFn](self.lib, "lake_has_snapshot")
        self._table = _sym[_TableFn](self.lib, "lake_table")
        self._ensure = _sym[_EnsureFn](self.lib, "lake_ensure_table")
        self._scan = _sym[_ScanFn](self.lib, "lake_scan")
        self._plan = _sym[_PlanFn](self.lib, "lake_plan_files")
        self._find = _sym[_FindFn](self.lib, "lake_find_commit")
        self._append = _sym[_AppendFn](self.lib, "lake_append")
        self._commit = _sym[_CommitFn](self.lib, "lake_commit_files")
        self.state = unsafe_alloc[_HostState](1)
        self.state.unsafe_write(_HostState(Int(Pointer(to=ctx))))
        self.err = Int(unsafe_alloc[Int](2))
        self.host = Int(unsafe_alloc[Int](HOST_SIZE // 8))
        var h = self.host
        _put(h, 0, Int(self.state))
        Pointer[_CheckDeclaredFn, MutUntrackedOrigin](unsafe_from_address=h + 8)[] = _on_check_declared
        Pointer[_PinFn, MutUntrackedOrigin](unsafe_from_address=h + 16)[] = _on_pin
        Pointer[_FenceFn, MutUntrackedOrigin](unsafe_from_address=h + 24)[] = _on_fence
        Pointer[_CommittedFn, MutUntrackedOrigin](unsafe_from_address=h + 32)[] = _on_committed
        Pointer[_SummaryFn, MutUntrackedOrigin](unsafe_from_address=h + 40)[] = _on_summary
        Pointer[_SameRunFn, MutUntrackedOrigin](unsafe_from_address=h + 48)[] = _on_same_run
        Pointer[_MadeFn, MutUntrackedOrigin](unsafe_from_address=h + 56)[] = _on_made
        Pointer[_NameFn, MutUntrackedOrigin](unsafe_from_address=h + 64)[] = _on_replaces
        Pointer[_NameFn, MutUntrackedOrigin](unsafe_from_address=h + 72)[] = _on_declares_write
        Pointer[_LogFn, MutUntrackedOrigin](unsafe_from_address=h + 80)[] = _on_log
        Pointer[_TextFn, MutUntrackedOrigin](unsafe_from_address=h + 88)[] = _on_commits
        Pointer[_TextFn, MutUntrackedOrigin](unsafe_from_address=h + 96)[] = _on_error

    def __del__(deinit self):
        self.state.unsafe_deinit_pointee()
        self.state.unsafe_free()
        Pointer[Int, MutUntrackedOrigin](unsafe_from_address=self.err).unsafe_free()
        Pointer[Int, MutUntrackedOrigin](unsafe_from_address=self.host).unsafe_free()

    def _raise(self) -> Error:
        var p = _get(self.err, 0)
        var msg = _text(p, _get(self.err, 8))
        self._free_text(p)
        return Error(msg^)

    def _wrap(self, h: Int) raises -> LakeTable:
        if h == 0:
            raise self._raise()
        return LakeTable(h, self._free_table, self._has)

    def table(self, dataset: String) raises -> LakeTable:
        return self._wrap(self._table(self.host, Int(dataset.unsafe_ptr()), dataset.byte_length(), self.err))

    def ensure_table(self, dataset: String, schema_json: String) raises -> LakeTable:
        return self._wrap(self._ensure(
            self.host, Int(dataset.unsafe_ptr()), dataset.byte_length(),
            Int(schema_json.unsafe_ptr()), schema_json.byte_length(), self.err,
        ))

    def scan(self, t: LakeTable, columns: List[String] = List[String]()) raises -> List[RecordBatch]:
        """The table at the step's pinned snapshot, as batches."""
        var cols = String()
        for i in range(len(columns)):
            cols.write("," if i > 0 else "", columns[i])
        var stream = _Slot()
        var rc = self._scan(self.host, t.handle, Int(cols.unsafe_ptr()), cols.byte_length(), stream.addr, self.err)
        _ = cols^  # alive across the call: its address went as an integer
        if rc != 0:
            raise self._raise()
        var out = List[RecordBatch]()
        if stream.get() == 0:
            return out^
        var s = ImportedStream(stream.get())
        while True:
            var b = s.next()
            if not b:
                break
            out.append(b.take())
        return out^

    def plan_files(self, t: LakeTable) raises -> List[Tuple[String, Int64]]:
        var n = _Slot()
        var p = self._plan(self.host, t.handle, n.addr, self.err)
        if p == 0:
            raise self._raise()
        var text = _text(p, n.get())
        self._free_text(p)
        var out = List[Tuple[String, Int64]]()
        for rec in text.split("\x1e"):
            if not rec:
                continue
            var kv = rec.split("\x1f")
            out.append((String(kv[0]), Int64(Int(kv[1]))))
        return out^

    def find_commit(self, t: LakeTable) -> Int64:
        return self._find(self.host, t.handle)

    def append(self, t: LakeTable, batches: List[RecordBatch]) raises -> Int64:
        var ex = List[ExportedArray]()
        for b in batches:
            ex.append(_export_batch(b))
        var arrays = List[Int]()
        var schemas = List[Int]()
        for i in range(len(ex)):
            arrays.append(ex[i].array)
            schemas.append(ex[i].schema)
        var id = self._append(self.host, t.handle, len(ex), Int(arrays.unsafe_ptr()), Int(schemas.unsafe_ptr()), self.err)
        _ = arrays^
        _ = schemas^
        _ = ex^  # released here, after the library has read them
        if id == -2:
            raise self._raise()
        return id

    def commit_files(
        self, t: LakeTable, operation: String, removed: List[String], batches: List[RecordBatch]
    ) raises -> Int64:
        var ex = List[ExportedArray]()
        for b in batches:
            ex.append(_export_batch(b))
        var arrays = List[Int]()
        var schemas = List[Int]()
        for i in range(len(ex)):
            arrays.append(ex[i].array)
            schemas.append(ex[i].schema)
        var rm = String()
        for p in removed:
            rm.write(p, "\x1e")
        var id = self._commit(
            self.host, t.handle, Int(operation.unsafe_ptr()), operation.byte_length(),
            Int(rm.unsafe_ptr()), rm.byte_length(),
            len(ex), Int(arrays.unsafe_ptr()), Int(schemas.unsafe_ptr()), self.err,
        )
        _ = arrays^
        _ = schemas^
        _ = rm^
        _ = ex^
        if id == -2:
            raise self._raise()
        return id


def replace_files(
    lake: Lake, t: LakeTable, removed: List[String], batches: List[RecordBatch]
) raises -> Int64:
    """census `replace.replace_files` over the library."""
    var some = List[RecordBatch]()
    for b in batches:
        if b.num_rows > 0:
            some.append(b.copy())
    if lake.find_commit(t) >= 0:
        return lake.append(t, some)
    if len(removed) == 0 and len(some) == 0:
        return -1
    if len(removed) == 0:
        return lake.append(t, some)
    return lake.commit_files(t, "overwrite", removed, some)


# ── building batches without iceberg ────────────────────────────────────────


struct Cols(Movable):
    """Columns of one batch, built a value at a time, in order."""

    var arena: ArrayArena
    var roots: List[Int]
    var rows: Int

    def __init__(out self):
        self.arena = ArrayArena()
        self.roots = List[Int]()
        self.rows = 0

    def string(mut self, name: String, nullable: Bool) -> Int:
        var a = ArrayData(ArrowType(AT_UTF8), name)
        a.nullable = nullable
        a.offsets.append(0)
        var i = self.arena.add(a^)
        self.roots.append(i)
        return i

    def long(mut self, name: String, nullable: Bool) -> Int:
        var a = ArrayData(ArrowType(AT_INT64), name)
        a.nullable = nullable
        var i = self.arena.add(a^)
        self.roots.append(i)
        return i

    def timestamptz(mut self, name: String, nullable: Bool) -> Int:
        var a = ArrayData(at_timestamp(TU_MICRO, String("UTC")), name)
        a.nullable = nullable
        var i = self.arena.add(a^)
        self.roots.append(i)
        return i

    def string_list(mut self, name: String, nullable: Bool) -> Int:
        var e = ArrayData(ArrowType(AT_UTF8), String("element"))
        e.nullable = False
        e.offsets.append(0)
        var ei = self.arena.add(e^)
        var a = ArrayData(ArrowType(AT_LIST), name)
        a.nullable = nullable
        a.offsets.append(0)
        a.children = [ei]
        var i = self.arena.add(a^)
        self.roots.append(i)
        return i

    def put_str(mut self, c: Int, s: String):
        ref a = self.arena.nodes[c]
        a.values.extend(s.as_bytes())
        a.offsets.append(Int32(len(a.values)))
        bit_set(a.validity, a.length, True)
        a.length += 1

    def put_null(mut self, c: Int):
        ref a = self.arena.nodes[c]
        if a.type.id == AT_UTF8 or a.type.id == AT_LIST:
            a.offsets.append(a.offsets[len(a.offsets) - 1])
        else:
            store_u64(a.values, 0)
        bit_set(a.validity, a.length, False)
        a.null_count += 1
        a.length += 1

    def put_i64(mut self, c: Int, v: Int64):
        ref a = self.arena.nodes[c]
        store_u64(a.values, UInt64(v))
        bit_set(a.validity, a.length, True)
        a.length += 1

    def put_strs(mut self, c: Int, items: List[String]):
        var e = self.arena.nodes[c].children[0]
        for s in items:
            self.put_str(e, s)
        ref a = self.arena.nodes[c]
        a.offsets.append(Int32(self.arena.nodes[e].length))
        bit_set(a.validity, a.length, True)
        a.length += 1

    def batch(deinit self, rows: Int) -> RecordBatch:
        var b = RecordBatch()
        b.arena = self.arena^
        b.roots = self.roots^
        b.num_rows = rows
        return b^
