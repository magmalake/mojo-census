"""Holds a set amount of memory and keeps a set number of cores busy, so a
run's peaks are known in advance: what morca's learned requests (morca #269,
`memory_gb = "auto"`) are checked against on the dev stack (#97). Only
morca.dev.toml registers it; it reads and writes no table.

Daily partitions from 2011-01-01, one run a day, run by hand (no schedule).
Each day's amounts come from `PLAN`, a list of segments in order; a day past
the last segment fails. `BALLAST_HOLD_S` (default 20) is how long a run
holds its memory and cores.

    ./build/ballast run --partitions 2011-01-01
    docker exec scheduler morca backfill ballast 2011-01-01..2011-01-22
"""

from std.os import getenv, setenv
from std.time import perf_counter_ns

from morca import Ctx, Daily, Day, Mapped, Pipeline, Step, morca_main
from threads import OpaquePtr, opaque_ptr, parallel_for

from days import days_of


@fieldwise_init
struct Segment(Copyable, Movable):
    """`days` runs in a row, each holding `mb` MB (times `growth` per run
    after the first) and keeping `cores` cores busy (or alternating 1 and 2
    when 0). `what` names the scenario of #97 it is for."""

    var days: Int
    var mb: Int
    var growth: Float64
    var cores: Int
    var what: StaticString


def plan() -> List[Segment]:
    """The scenarios of #97, in the order they run (100 days), sized for the
    dev stack's CAX11 (2 cores, 4 GB): the largest run holds 1.5 GB."""
    return [
        Segment(22, 300, 1.0, 1, "A1-A2 cold start, then steady"),
        Segment(1, 1500, 1.0, 1, "A3 one outlier"),
        Segment(19, 300, 1.0, 1, "A3 the outlier in the window"),
        Segment(20, 60, 1.0, 1, "A6 shrink"),
        Segment(20, 300, 1.08, 1, "A4 ramp"),
        Segment(10, 200, 1.0, 0, "A7 cores 1, 2"),
        Segment(3, 1200, 1.0, 1, "A5 over an auto..1 cap"),
        Segment(5, 300, 1.0, 1, "A8 learn = false"),
    ]


@fieldwise_init
struct Amounts(Copyable, Movable, Writable):
    var mb: Int
    var cores: Int
    var what: String


def amounts(day: String) raises -> Amounts:
    """What `day` holds, from its place in `plan()`."""
    var i = Int(days_of(day) - days_of("2011-01-01"))
    if i < 0:
        raise Error("ballast: ", day, " is before 2011-01-01")
    for s in plan():
        if i < s.days:
            var mb = Float64(s.mb)
            for _ in range(i):
                mb *= s.growth
            var cores = s.cores if s.cores > 0 else i % 2 + 1
            return Amounts(Int(mb), cores, String(s.what))
        i -= s.days
    raise Error("ballast: ", day, " is past the plan's last day")


def _spin(i: Int, ctx: OpaquePtr) -> None:
    """Keeps a core busy until the deadline `ctx` carries (perf_counter_ns)."""
    var until = Int(ctx)
    while perf_counter_ns() < until:
        pass


def hold(mut ctx: Ctx, d: Day) raises -> Int:
    """Touches every page of the day's memory, then keeps its cores busy for
    `BALLAST_HOLD_S` seconds with the memory still held."""
    var day = String(d)
    var a = amounts(day)
    var seconds = Int(getenv("BALLAST_HOLD_S", "20"))
    ctx.log(String(day, ": ", a.mb, " MB, ", a.cores, " cores for ", seconds, " s (", a.what, ")"))
    var block = List[UInt8](length=a.mb * 1024 * 1024, fill=1)
    var until = perf_counter_ns() + seconds * 1_000_000_000
    parallel_for[_spin](n_tasks=a.cores, ctx=opaque_ptr(Int(until)), num_workers=a.cores)
    # Read the block after the spin, so it's held until here.
    var sum = 0
    for i in range(0, len(block), 4096):
        sum += Int(block[i])
    return sum


comptime Hold = Step["hold", Day, Int, hold, Mapped]
comptime Ballast = Pipeline["ballast", Hold, partitions=Daily["2011-01-01"]]


def main() raises:
    if not getenv("MORCA_WAREHOUSE"):
        _ = setenv("MORCA_WAREHOUSE", "build/warehouse")
    morca_main[Ballast]()
