"""The thin Mojo side of the http lib-tin (spike, morca #445): one HTTP
request through libhttp's C ABI (libtins/http/httplib.mojo), so the
program compiles none of flare. `HTTP_LIB` names the library file."""

from std.ffi import OwnedDLHandle, RTLD
from std.memory.alloc import unsafe_alloc
from std.os import getenv
from std.sys import CompilationTarget

from fetch import Reply, USER_AGENT

comptime _SendFn = def(
    Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int
) thin abi("C") -> Int32
comptime _FreeFn = def(Int) thin abi("C") -> None


def _get(block: Int, at: Int) -> Int:
    return Pointer[Int, MutUntrackedOrigin](unsafe_from_address=block + at)[]


def _text(addr: Int, n: Int) -> String:
    if n <= 0 or addr == 0:
        return String()
    var buf = List[UInt8](capacity=n)
    var p = Pointer[UInt8, ImmUntrackedOrigin](unsafe_from_address=addr)
    for i in range(n):
        buf.append(p[unsafe_offset=i])
    return String(unsafe_from_utf8=Span(buf))


def _sym[FT: TrivialRegisterPassable](lib: OwnedDLHandle, name: String) raises -> FT:
    var opt = lib.get_symbol[FT](name)
    if not opt:
        raise Error("http: libhttp has no symbol ", name)
    var addr: Int = Int(opt.value())
    return Pointer(to=addr).unsafe_bitcast[FT]()[]


@fieldwise_init
struct HttpReply(Movable):
    var status: Int
    var headers: Dict[String, String]
    var body: String


def send(
    method: String, url: String, headers: Dict[String, String], body: String,
    want: List[String], timeout_ms: Int = 30_000, idle_ms: Int = 60_000,
) raises -> HttpReply:
    var file = getenv("HTTP_LIB")
    if not file:
        comptime if CompilationTarget.is_macos():
            file = "libhttp.dylib"
        else:
            file = "libhttp.so"
    var lib = OwnedDLHandle(file, RTLD.NOW | RTLD.LOCAL | RTLD.NODELETE)
    var f = _sym[_SendFn](lib, "http_send")
    var free = _sym[_FreeFn](lib, "http_free")
    var h = String()
    for e in headers.items():
        h.write(e.key, "\x1f", e.value, "\x1e")
    var w = String()
    for n in want:
        w.write(n, "\x1e")
    var res = Int(unsafe_alloc[Int](5))
    var err = Int(unsafe_alloc[Int](2))
    var rc = f(
        Int(method.unsafe_ptr()), method.byte_length(), Int(url.unsafe_ptr()), url.byte_length(),
        Int(h.unsafe_ptr()), h.byte_length(), Int(body.unsafe_ptr()), body.byte_length(),
        Int(w.unsafe_ptr()), w.byte_length(), timeout_ms, idle_ms, res, err,
    )
    _ = h^
    _ = w^
    if rc != 0:
        var msg = _text(_get(err, 0), _get(err, 8))
        free(_get(err, 0))
        raise Error(msg^)
    var got = Dict[String, String]()
    for rec in _text(_get(res, 8), _get(res, 16)).split("\x1e"):
        var kv = rec.split("\x1f")
        if len(kv) == 2:
            got[String(kv[0])] = String(kv[1])
    var out = HttpReply(_get(res, 0), got^, _text(_get(res, 24), _get(res, 32)))
    free(_get(res, 8))
    free(_get(res, 24))
    Pointer[Int, MutUntrackedOrigin](unsafe_from_address=res).unsafe_free()
    Pointer[Int, MutUntrackedOrigin](unsafe_from_address=err).unsafe_free()
    return out^


def _int(d: Dict[String, String], k: String) -> Int:
    try:
        return Int(d.get(k, "-1"))
    except:
        return -1


def github(path: String) raises -> Reply:
    """census fetch.github over libhttp."""
    var hs = Dict[String, String]()
    hs["User-Agent"] = USER_AGENT
    hs["Accept"] = "application/vnd.github+json"
    hs["X-GitHub-Api-Version"] = "2022-11-28"
    var token = getenv("GITHUB_TOKEN")
    if token:
        hs["Authorization"] = String("Bearer ", token)
    var r = send("GET", String("https://api.github.com", path), hs, String(),
        ["x-ratelimit-remaining", "retry-after", "x-ratelimit-reset"])
    return Reply(
        r.status, r.body.copy(), _int(r.headers, "x-ratelimit-remaining"),
        _int(r.headers, "retry-after"), _int(r.headers, "x-ratelimit-reset"),
    )
