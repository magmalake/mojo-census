"""The http lib-tin (spike, morca #445): flare's blocking HTTP client as a
shared library with a C ABI. One call, one request:

    int32 http_send(method, m_n, url, u_n, headers, h_n, body, b_n,
                    want, w_n, timeout_ms, idle_ms, out, err)

Text is (pointer, length). `headers` is a map (`k \\x1f v \\x1e` ...);
`want` the response headers to return (`name \\x1e` ...). `out` is five
slots: status, the wanted headers as a map (pointer, length), the body
(pointer, length); both are this library's, freed with `http_free`. On
failure (1) `err` gets a message to free the same way.

    mojo build --emit shared-lib -I ../lake httplib.mojo -o libhttp.dylib
"""

from std.os import getenv
from std.os.path import exists

from flare.http import HttpClient, Request
from flare.tls import TlsConfig

from lake_abi import alloc_text, decode_map, encode_map, free_text, put_int, text_of

comptime ABI_VERSION: UInt32 = 1


def _ca_bundle() -> String:
    """As census fetch._ca_bundle."""
    var env = getenv("SSL_CERT_FILE")
    if env:
        return env
    var prefix = getenv("CONDA_PREFIX")
    var conda = String(prefix, "/ssl/cacert.pem")
    if prefix and exists(conda):
        return conda
    var debian = String("/etc/ssl/certs/ca-certificates.crt")
    if exists(debian):
        return debian
    return String()


def _client(timeout_ms: Int, idle_ms: Int) raises -> HttpClient:
    var ca = _ca_bundle()
    var c = HttpClient(TlsConfig(ca_bundle=ca), timeout_ms=timeout_ms) if ca else HttpClient(timeout_ms=timeout_ms)
    if idle_ms > 0:
        return c^.with_read_timeout(idle_ms)
    return c^


@export("http_abi_version")
def http_abi_version() abi("C") -> UInt32:
    return ABI_VERSION


@export("http_free")
def http_free(p: Int) abi("C"):
    free_text(p)


@export("http_send")
def http_send(
    method: Int, m_n: Int, url: Int, u_n: Int, headers: Int, h_n: Int,
    body: Int, b_n: Int, want: Int, w_n: Int, timeout_ms: Int, idle_ms: Int,
    res: Int, err: Int,
) abi("C") -> Int32:
    try:
        var c = _client(timeout_ms, idle_ms)
        var b = text_of(body, b_n)
        var req: Request
        if b_n > 0:
            var bytes = List[UInt8](b.as_bytes())
            req = Request(method=text_of(method, m_n), url=text_of(url, u_n), body=bytes^)
        else:
            req = Request(method=text_of(method, m_n), url=text_of(url, u_n))
        for e in decode_map(text_of(headers, h_n)).items():
            req.headers.set(e.key, e.value)
        var resp = c.send(req)
        var got = Dict[String, String]()
        for name in text_of(want, w_n).split("\x1e"):
            if name:
                var v = resp.headers.get(String(name))
                if v:
                    got[String(name)] = String(v)
        var h = encode_map(got)
        var t = resp.text()
        put_int(res, 0, resp.status)
        put_int(res, 8, alloc_text(h))
        put_int(res, 16, h.byte_length())
        put_int(res, 24, alloc_text(t))
        put_int(res, 32, t.byte_length())
        return 0
    except e:
        var msg = String(e)
        put_int(err, 0, alloc_text(msg))
        put_int(err, 8, msg.byte_length())
        return 1
