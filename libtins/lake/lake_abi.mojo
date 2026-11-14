"""The lake lib-tin's C ABI, as both sides see it: the version, the layout
of the host block, and how text and string maps cross.

Everything that crosses is an integer, a float, or a pointer to bytes plus
a length. Text is UTF-8, not NUL-terminated. A string map is
`key \\x1f value \\x1e` repeated. Memory is freed by the side that
allocated it: text the library returns is freed with `lake_free_text`, text
a host callback returns stays the host's and is valid until its next call.

**The host block** is what the caller passes to every call that needs the
step: `HOST_SIZE` bytes, one 8-byte slot each, the first the host's own
state address, the rest `abi("C")` function pointers. The library calls
them on the caller's thread, inside the call.

**Errors.** Every fallible export takes `err`, the address of two slots;
on failure it writes a text pointer and length there (free with
`lake_free_text`) and returns its failure value.
"""

from std.memory.alloc import unsafe_alloc

comptime ABI_VERSION: UInt32 = 1

# Host block slots (byte offsets).
comptime H_STATE = 0
comptime H_CHECK_DECLARED = 8
comptime H_PIN = 16
comptime H_FENCE = 24
comptime H_COMMITTED = 32
comptime H_SUMMARY = 40
comptime H_SAME_RUN = 48
comptime H_MADE = 56
comptime H_REPLACES = 64
comptime H_DECLARES_WRITE = 72
comptime H_LOG = 80
comptime H_COMMITS = 88
comptime H_ERROR = 96
comptime HOST_SIZE = 104

# Callback types: (state, ...) with text as (ptr, len).
comptime CheckDeclaredFn = def(Int, Int, Int, Int) thin abi("C") -> Int32
comptime PinFn = def(Int, Int, Int, Int64, Int, Int, Int) thin abi("C") -> Int32
comptime FenceFn = def(Int) thin abi("C") -> Int32
comptime CommittedFn = def(Int, Int, Int, Int64, Int, Int) thin abi("C") -> Int32
comptime SummaryFn = def(Int, Int, Int, Int) thin abi("C") -> Int
comptime SameRunFn = def(Int, Int, Int) thin abi("C") -> Int32
comptime MadeFn = def(Int, Int, Int, Int, Int) thin abi("C") -> Int32
comptime NameFn = def(Int, Int, Int) thin abi("C") -> Int32
comptime LogFn = def(Int, Int, Int) thin abi("C") -> None
comptime TextFn = def(Int, Int) thin abi("C") -> Int


def get_int(block: Int, at: Int) -> Int:
    return Pointer[Int, MutUntrackedOrigin](unsafe_from_address=block + at)[]


def put_int(block: Int, at: Int, v: Int):
    Pointer[Int, MutUntrackedOrigin](unsafe_from_address=block + at)[] = v


def text_of(addr: Int, n: Int) -> String:
    """A copy of `n` bytes at `addr` as a String."""
    if n <= 0 or addr == 0:
        return String()
    var buf = List[UInt8](capacity=n)
    var p = Pointer[UInt8, ImmUntrackedOrigin](unsafe_from_address=addr)
    for i in range(n):
        buf.append(p[unsafe_offset=i])
    return String(unsafe_from_utf8=Span(buf))


def alloc_text(s: String) -> Int:
    """`s` copied into memory of this side's allocator; freed by
    `free_text` on the same side."""
    var n = s.byte_length()
    var p = unsafe_alloc[UInt8](n + 1)
    var src = s.unsafe_ptr()
    for i in range(n):
        p[unsafe_offset=i] = src[unsafe_offset=i]
    p[unsafe_offset=n] = 0
    return Int(p)


def free_text(addr: Int):
    if addr != 0:
        Pointer[UInt8, MutUntrackedOrigin](unsafe_from_address=addr).unsafe_free()


def encode_map(d: Dict[String, String]) -> String:
    var out = String()
    for e in d.items():
        out.write(e.key, "\x1f", e.value, "\x1e")
    return out^


def decode_map(s: String) -> Dict[String, String]:
    var d = Dict[String, String]()
    for rec in s.split("\x1e"):
        if not rec:
            continue
        var kv = rec.split("\x1f")
        if len(kv) == 2:
            d[String(kv[0])] = String(kv[1])
    return d^


struct Slot(Movable):
    """One 8-byte out-parameter on the heap. A stack variable whose address
    is passed as an integer isn't known to be written by the call, and the
    optimiser may read the old value after it: out-parameters go here."""

    var addr: Int

    def __init__(out self):
        var p = unsafe_alloc[Int](1)
        p[] = 0
        self.addr = Int(p)

    def get(self) -> Int:
        return get_int(self.addr, 0)

    def __del__(deinit self):
        Pointer[Int, MutUntrackedOrigin](unsafe_from_address=self.addr).unsafe_free()
