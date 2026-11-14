"""The library's view of the step: the methods of `morca.Ctx` that
`morca.tables` uses, each a call through the host block (lake_abi)."""

from lake_abi import (
    CheckDeclaredFn,
    CommittedFn,
    FenceFn,
    LogFn,
    MadeFn,
    NameFn,
    PinFn,
    SameRunFn,
    SummaryFn,
    TextFn,
    H_CHECK_DECLARED,
    H_COMMITS,
    H_COMMITTED,
    H_DECLARES_WRITE,
    H_ERROR,
    H_FENCE,
    H_LOG,
    H_MADE,
    H_PIN,
    H_REPLACES,
    H_SAME_RUN,
    H_STATE,
    H_SUMMARY,
    decode_map,
    encode_map,
    Slot,
    get_int,
    text_of,
)


def _fn[FT: TrivialRegisterPassable](block: Int, at: Int) -> FT:
    var addr = get_int(block, at)
    return Pointer(to=addr).unsafe_bitcast[FT]()[]


@fieldwise_init
struct HostCommit(Copyable, Movable):
    var table: String
    var snapshot_id: Int64


struct Host(Copyable, Movable):
    """The host block at `block`; copies are views of the same block."""

    var block: Int

    def __init__(out self, block: Int):
        self.block = block

    def _state(self) -> Int:
        return get_int(self.block, H_STATE)

    def _error(self) -> Error:
        var n = Slot()
        var p = _fn[TextFn](self.block, H_ERROR)(self._state(), n.addr)
        return Error(text_of(p, n.get()))

    def check_declared(self, dataset: String, write: Bool) raises:
        var f = _fn[CheckDeclaredFn](self.block, H_CHECK_DECLARED)
        if f(self._state(), Int(dataset.unsafe_ptr()), dataset.byte_length(), 1 if write else 0) != 0:
            raise self._error()

    def declares_write(self, dataset: String) -> Bool:
        var f = _fn[NameFn](self.block, H_DECLARES_WRITE)
        return f(self._state(), Int(dataset.unsafe_ptr()), dataset.byte_length()) != 0

    def replaces(self, dataset: String) -> Bool:
        var f = _fn[NameFn](self.block, H_REPLACES)
        return f(self._state(), Int(dataset.unsafe_ptr()), dataset.byte_length()) != 0

    def pin(self, table: String, current: Int64, dataset: String = "") raises -> Int64:
        var out = Slot()
        var f = _fn[PinFn](self.block, H_PIN)
        if f(
            self._state(), Int(table.unsafe_ptr()), table.byte_length(), current,
            Int(dataset.unsafe_ptr()), dataset.byte_length(), out.addr,
        ) != 0:
            raise self._error()
        return Int64(out.get())

    def fence(self) raises:
        if _fn[FenceFn](self.block, H_FENCE)(self._state()) != 0:
            raise self._error()

    def committed(self, table: String, snapshot_id: Int64, dataset: String = "") raises:
        var f = _fn[CommittedFn](self.block, H_COMMITTED)
        if f(
            self._state(), Int(table.unsafe_ptr()), table.byte_length(), snapshot_id,
            Int(dataset.unsafe_ptr()), dataset.byte_length(),
        ) != 0:
            raise self._error()

    def summary(self, table: String) -> Dict[String, String]:
        var n = Slot()
        var f = _fn[SummaryFn](self.block, H_SUMMARY)
        var p = f(self._state(), Int(table.unsafe_ptr()), table.byte_length(), n.addr)
        return decode_map(text_of(p, n.get()))

    def same_run(self, summary: Dict[String, String]) -> Bool:
        var s = encode_map(summary)
        var f = _fn[SameRunFn](self.block, H_SAME_RUN)
        var r = f(self._state(), Int(s.unsafe_ptr()), s.byte_length())
        _ = s^
        return r != 0

    def made(self, table: String, summary: Dict[String, String]) -> Bool:
        var s = encode_map(summary)
        var f = _fn[MadeFn](self.block, H_MADE)
        var r = f(
            self._state(), Int(table.unsafe_ptr()), table.byte_length(),
            Int(s.unsafe_ptr()), s.byte_length(),
        )
        _ = s^
        return r != 0

    def log(self, msg: String):
        _fn[LogFn](self.block, H_LOG)(self._state(), Int(msg.unsafe_ptr()), msg.byte_length())

    def commits(self) -> List[HostCommit]:
        var n = Slot()
        var p = _fn[TextFn](self.block, H_COMMITS)(self._state(), n.addr)
        var out = List[HostCommit]()
        for rec in text_of(p, n.get()).split("\x1e"):
            if not rec:
                continue
            var kv = rec.split("\x1f")
            try:
                out.append(HostCommit(String(kv[0]), Int64(Int(kv[1]))))
            except:
                pass
        return out^
