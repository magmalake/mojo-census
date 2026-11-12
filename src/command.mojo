"""Running git (or any program) without a shell, and removing what it made.

`command` forks and executes `argv` directly (looked up on `PATH`), its
standard output going to a file of its own that is read back once it ends,
any bytes that aren't UTF-8 dropped: an old commit's subject, path or tag
can be Latin-1. Its standard error is kept (shared with this process),
merged into the output or dropped. With a timeout it is killed past it,
with everything it started, as it leads a process group of its own. No
`sh` and no `iconv` are needed, so the census runs on a runtime image
without either (#53). `remove_tree` is `rm -rf` and `make_dirs` is
`mkdir -p`.

Everything the child needs is prepared before `fork`, so the child calls
only `setpgid`, `fopen`, `fileno`, `dup2`, `execvp` and `_exit`.
"""

from std.ffi import c_int, external_call
from std.memory import stack_allocation
from std.os import getenv, listdir, makedirs, remove, rmdir, setenv
from std.os.path import exists, isdir, islink
from std.time import perf_counter_ns, sleep


comptime TIMED_OUT = 124
"""`command`'s status for a command killed at its timeout (as `timeout(1)`)."""
comptime STDERR_KEEP = 0
"""Its standard error goes where this process's goes."""
comptime STDERR_MERGE = 1
"""Its standard error goes into the output, as `2>&1`."""
comptime STDERR_DROP = 2
"""Its standard error goes to `/dev/null`."""


def _cstr(s: String) -> List[UInt8]:
    var b = List[UInt8](capacity=s.byte_length() + 1)
    for c in s.as_bytes():
        b.append(c)
    b.append(0)
    return b^


def _code(s: Int) -> Int:
    """An exit code from a `waitpid` status: 128 + the signal if killed."""
    return (s >> 8) & 0xFF if s & 0x7F == 0 else 128 + (s & 0x7F)


def utf8_only(bytes: Span[UInt8, _]) -> String:
    """`bytes` as text, without the bytes that aren't UTF-8 (as
    `iconv -c -f UTF-8 -t UTF-8`)."""
    var out = List[UInt8](capacity=len(bytes))
    var i = 0
    var n = len(bytes)
    while i < n:
        var b = Int(bytes[i])
        var need: Int
        var low = 0x80
        var high = 0xBF
        if b < 0x80:
            out.append(bytes[i])
            i += 1
            continue
        elif b >= 0xC2 and b <= 0xDF:
            need = 1
        elif b >= 0xE0 and b <= 0xEF:
            need = 2
            if b == 0xE0:
                low = 0xA0
            elif b == 0xED:
                high = 0x9F
        elif b >= 0xF0 and b <= 0xF4:
            need = 3
            if b == 0xF0:
                low = 0x90
            elif b == 0xF4:
                high = 0x8F
        else:
            i += 1  # not a lead byte: dropped
            continue
        var ok = i + need < n
        if ok:
            for k in range(1, need + 1):
                var c = Int(bytes[i + k])
                var lo = low if k == 1 else 0x80
                var hi = high if k == 1 else 0xBF
                if c < lo or c > hi:
                    ok = False
                    break
        if not ok:
            i += 1  # a broken sequence: its lead byte dropped, the rest looked at again
            continue
        for k in range(need + 1):
            out.append(bytes[i + k])
        i += need + 1
    return String(unsafe_from_utf8=out)


def command(
    argv: List[String],
    timeout_ms: Int = 0,
    stderr: Int = STDERR_KEEP,
    max_bytes: Int = -1,
) raises -> Tuple[Int, String]:
    """Runs `argv` to the end and returns its exit status and its output
    (its first `max_bytes` bytes, if given), any bytes that aren't UTF-8
    dropped. 127 means `argv[0]` couldn't be run. With `timeout_ms`, a
    command still going then is killed with what it started, and the status
    is `TIMED_OUT`, the output saying so."""
    if len(argv) == 0:
        raise Error("command: no program")
    var t0 = Int(perf_counter_ns())
    var path = String(
        getenv("TMPDIR", "/tmp").rstrip("/"),
        "/census-out-",
        external_call["getpid", c_int](),
        "-",
        t0,
    )
    var args = List[List[UInt8]]()
    for a in argv:
        args.append(_cstr(a))
    var ptrs = List[Int]()
    for i in range(len(args)):
        ptrs.append(Int(args[i].unsafe_ptr()))
    ptrs.append(0)
    var path_c = _cstr(path)
    var null_c = _cstr("/dev/null")
    var mode = _cstr("w")
    var pid = external_call["fork", c_int]()
    if pid < 0:
        raise Error("command: fork failed for ", argv[0])
    if pid == 0:
        _ = external_call["setpgid", c_int](c_int(0), c_int(0))
        var f = external_call["fopen", Int](path_c.unsafe_ptr(), mode.unsafe_ptr())
        if f == 0:
            external_call["_exit", NoneType](c_int(126))
        var fd = external_call["fileno", c_int](f)
        _ = external_call["dup2", c_int](fd, c_int(1))
        if stderr == STDERR_MERGE:
            _ = external_call["dup2", c_int](fd, c_int(2))
        elif stderr == STDERR_DROP:
            var nf = external_call["fopen", Int](null_c.unsafe_ptr(), mode.unsafe_ptr())
            if nf != 0:
                _ = external_call["dup2", c_int](
                    external_call["fileno", c_int](nf), c_int(2)
                )
        _ = external_call["execvp", c_int](args[0].unsafe_ptr(), ptrs.unsafe_ptr())
        external_call["_exit", NoneType](c_int(127))
    _ = args^
    _ = ptrs^
    var status = stack_allocation[1, c_int]()
    var code: Int
    while True:
        status[] = 0
        # Without a timeout it waits; with one it looks every 5 ms (WNOHANG).
        var got = external_call["waitpid", c_int](
            pid, status, c_int(1 if timeout_ms > 0 else 0)
        )
        if got == pid:
            code = _code(Int(status[]))
            break
        if got < 0:
            code = 255  # not our child any more
            break
        if timeout_ms > 0 and (Int(perf_counter_ns()) - t0) // 1_000_000 > timeout_ms:
            _ = external_call["kill", c_int](-pid, c_int(9))
            _ = external_call["kill", c_int](pid, c_int(9))
            _ = external_call["waitpid", c_int](pid, status, c_int(0))
            _remove(path)
            return (TIMED_OUT, String("timed out after ", timeout_ms // 1000, " s"))
        sleep(0.005)
    var text = String()
    if exists(path):
        with open(path, "r") as f:
            var bytes = f.read_bytes(max_bytes)
            text = utf8_only(Span(bytes))
        _remove(path)
    return (code, text^)


def _remove(path: String):
    try:
        remove(path)
    except:
        pass


def git(
    args: List[String],
    timeout_ms: Int = 0,
    stderr: Int = STDERR_KEEP,
    max_bytes: Int = -1,
) raises -> Tuple[Int, String]:
    """`command` of `git` with `args`, never asking for credentials
    (`GIT_TERMINAL_PROMPT=0`)."""
    _ = setenv("GIT_TERMINAL_PROMPT", "0")
    var argv: List[String] = ["git"]
    for a in args:
        argv.append(a)
    return command(argv, timeout_ms, stderr, max_bytes)


def remove_tree(path: String) raises:
    """Removes `path` and everything under it, if it is there (`rm -rf`); a
    symbolic link is removed, not followed."""
    if islink(path):
        remove(path)
    elif isdir(path):
        for name in listdir(path):
            remove_tree(String(path, "/", name))
        rmdir(path)
    elif exists(path):
        remove(path)


def make_dirs(path: String) raises:
    """Makes `path` and the directories above it that are missing (`mkdir -p`)."""
    makedirs(path, exist_ok=True)
