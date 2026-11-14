"""The lake lib-tin: morca's Iceberg tables (morca.tables over iceberg,
parquet, objectstore) as a shared library with a C ABI.

    mojo build --emit shared-lib -I . lakelib.mojo -o liblake.dylib

Tables are handles (the address of a heap `Table`, freed with
`lake_free_table`). Rows cross as Arrow C Data Interface structs: a scan
returns an `ArrowArrayStream` the caller consumes and releases; batches
given to `lake_append` / `lake_commit_files` are borrowed for the call.
See lake_abi.mojo for text, maps, the host block and errors.
"""

from std.memory.alloc import unsafe_alloc

from iceberg.catalog.filesystem import Table
from iceberg.commit import FileChanges
from iceberg.schema import Schema
from parquet import RecordBatch
from arrow_mlake import AT_STRUCT, ArrayArena, ArrayData, ArrowType
from arrow_mlake.carrow import ExportedArray, export_c
from arrow_mlake.carrow_import import import_batch_c
from arrow_mlake.carrow_stream import export_stream_of

from lake_abi import ABI_VERSION, alloc_text, free_text, put_int, text_of
from lake_host import Host
import tables_impl as tables


# ── handles and errors ──────────────────────────────────────────────────────


def _new_table(var t: Table) -> Int:
    var p = unsafe_alloc[Table](1)
    p.unsafe_write(t^)
    return Int(p)


def _table(h: Int) -> Pointer[Table, MutAnyOrigin]:
    return Pointer[Table, MutAnyOrigin](unsafe_from_address=h)


def _fail(err: Int, e: Error):
    if err != 0:
        var msg = String(e)
        put_int(err, 0, alloc_text(msg))
        put_int(err, 8, msg.byte_length())


def _batches(n: Int, arrays: Int, schemas: Int, schema: Schema) raises -> List[RecordBatch]:
    """The `n` borrowed C batches, imported (copied), their columns given
    the table's field ids by name: the C Data Interface carries names, and
    a writer matches columns by id."""
    var out = List[RecordBatch]()
    for i in range(n):
        var a = Pointer[Int, MutUntrackedOrigin](unsafe_from_address=arrays + 8 * i)[]
        var s = Pointer[Int, MutUntrackedOrigin](unsafe_from_address=schemas + 8 * i)[]
        var b = import_batch_c(a, s)
        for r in b.roots.copy():
            var name = b.arena.nodes[r].name.copy()
            _assign_ids(b.arena, r, name, schema)
        out.append(b^)
    return out^


def _assign_ids(mut arena: ArrayArena, node: Int, full: String, schema: Schema):
    for k in range(len(schema.flat)):
        if schema.flat[k].name == full:
            arena.nodes[node].field_id = Int32(schema.flat[k].id)
            break
    var kids = arena.nodes[node].children.copy()
    for c in kids:
        _assign_ids(arena, c, String(full, ".", arena.nodes[c].name), schema)


def _export_batch(b: RecordBatch) raises -> ExportedArray:
    """A batch as one struct array, as a stream carries it."""
    var arena = b.arena.copy()
    var st = ArrayData(ArrowType(AT_STRUCT), String())
    st.nullable = False
    st.length = b.num_rows
    st.children = b.roots.copy()
    var root = arena.add(st^)
    return export_c(arena, root)


# ── exports ─────────────────────────────────────────────────────────────────


@export("lake_abi_version")
def lake_abi_version() abi("C") -> UInt32:
    return ABI_VERSION


@export("lake_free_text")
def lake_free_text(p: Int) abi("C"):
    free_text(p)


@export("lake_table")
def lake_table(host: Int, ds: Int, ds_n: Int, err: Int) abi("C") -> Int:
    """The table of a dataset the step declared; 0 on error."""
    try:
        var ctx = Host(host)
        return _new_table(tables.table(ctx, text_of(ds, ds_n)))
    except e:
        _fail(err, e)
        return 0


@export("lake_ensure_table")
def lake_ensure_table(host: Int, ds: Int, ds_n: Int, schema: Int, schema_n: Int, err: Int) abi("C") -> Int:
    """`ensure_table` with an Iceberg schema as JSON; unpartitioned, no
    properties of its own. 0 on error."""
    try:
        var ctx = Host(host)
        var s = Schema.parse(text_of(schema, schema_n))
        return _new_table(tables.ensure_table(ctx, text_of(ds, ds_n), s))
    except e:
        _fail(err, e)
        return 0


@export("lake_free_table")
def lake_free_table(h: Int) abi("C"):
    if h != 0:
        var p = _table(h)
        p.unsafe_deinit_pointee()
        p.unsafe_free()


@export("lake_has_snapshot")
def lake_has_snapshot(h: Int) abi("C") -> Int:
    return 1 if _table(h)[].metadata.has_current_snapshot else 0


@export("lake_scan")
def lake_scan(host: Int, h: Int, cols: Int, cols_n: Int, out_stream: Int, err: Int) abi("C") -> Int32:
    """Scans the table at the step's pinned snapshot, the columns named in
    `cols` (comma-separated; empty = all), into an ArrowArrayStream whose
    address goes to `out_stream` (0 when no rows). 0 ok, 1 error."""
    try:
        var ctx = Host(host)
        var sc = tables.scan(ctx, _table(h)[])
        var names = text_of(cols, cols_n)
        if names:
            var sel = List[String]()
            for c in names.split(","):
                sel.append(String(c))
            sc = sc.select(sel^)
        var exported = List[ExportedArray]()
        for b in sc.to_batches():
            exported.append(_export_batch(b))
        put_int(out_stream, 0, export_stream_of(exported^) if len(exported) > 0 else 0)
        return 0
    except e:
        _fail(err, e)
        return 1


@export("lake_plan_files")
def lake_plan_files(host: Int, h: Int, out_n: Int, err: Int) abi("C") -> Int:
    """The data files of the step's pinned snapshot, `path \\x1f records
    \\x1e` each, as text to free with lake_free_text; 0 on error."""
    try:
        var ctx = Host(host)
        var out = String()
        for task in tables.scan(ctx, _table(h)[]).plan_files():
            out.write(task.data_file.file_path, "\x1f", task.data_file.record_count, "\x1e")
        put_int(out_n, 0, out.byte_length())
        return alloc_text(out)
    except e:
        _fail(err, e)
        return 0


@export("lake_find_commit")
def lake_find_commit(host: Int, h: Int) abi("C") -> Int64:
    return tables.find_commit(Host(host), _table(h)[])


@export("lake_append")
def lake_append(host: Int, h: Int, n: Int, arrays: Int, schemas: Int, err: Int) abi("C") -> Int64:
    """`morca.tables.append` of `n` borrowed C batches; -2 on error."""
    try:
        var ctx = Host(host)
        ref t = _table(h)[]
        var bs = _batches(n, arrays, schemas, t.metadata.schema())
        return tables.append(ctx, t, bs)
    except e:
        _fail(err, e)
        return -2


@export("lake_commit_files")
def lake_commit_files(
    host: Int, h: Int, op: Int, op_n: Int, removed: Int, removed_n: Int,
    n: Int, arrays: Int, schemas: Int, err: Int,
) abi("C") -> Int64:
    """Writes `n` borrowed C batches into data files and commits them with
    the files `removed` names (`path \\x1e` each) gone, as one snapshot of
    `op`: `write_files` then `commit`. -2 on error."""
    try:
        var ctx = Host(host)
        ref t = _table(h)[]
        var files = FileChanges()
        if n > 0:
            var bs = _batches(n, arrays, schemas, t.metadata.schema())
            files.added_data = tables.write_files(t, bs).files.copy()
        for p in text_of(removed, removed_n).split("\x1e"):
            if p:
                files.removed.append(String(p))
        return tables.commit(ctx, t, text_of(op, op_n), files^)
    except e:
        _fail(err, e)
        return -2
