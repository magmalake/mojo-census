#!/bin/sh
# Every program, as two multi-call binaries (scripts/multicall.sh) and a
# link per program:
#
#   BIN_DIR/multicall-apps        orca (bin/scheduler.mojo) and console
#   BIN_DIR/multicall-pipelines   every pipeline and every other bin/*.mojo
#
#   scripts/build.sh BIN_DIR PIPELINES_DIR [mojo build flags...]
#
# Two, not one, until flare declares mmap and munmap (Linux) and accept
# (macOS) as memory-region and dista do: two `external_call`s of one C
# function with different signatures don't compile in one program, and only
# the flare servers (orca ui, the console) reach flare's. One binary needs
# magmalake/flare_mlake's mmap-signature branch, released, and orca-mojo and
# k8s-mojo pinning it. Run inside `pixi run`.
set -eu
bin=$1
pipelines=$2
shift 2
apps="bin/scheduler.mojo"
[ -f bin/console.mojo ] && apps="$apps bin/console.mojo"
rest=""
for f in bin/*.mojo pipelines/*.mojo; do
    [ -f "$f" ] || continue
    case " $apps " in *" $f "*) continue ;; esac
    rest="$rest $f"
done
# The two at once, unless MOJO_BUILD_JOBS=1: each mojo build keeps about two
# cores busy and peaks at about 5.6 GB, so together they fit GitHub's arm64
# runner (4 cores, 16 GB). Each one's output is held until it finishes and
# printed in one piece; if either fails, this fails, after both finish, and
# says which.
if [ "${MOJO_BUILD_JOBS:-}" = 1 ]; then
    sh scripts/multicall.sh multicall-apps "$bin" "$pipelines" $apps -- "$@"
    sh scripts/multicall.sh multicall-pipelines "$bin" "$pipelines" $rest -- "$@"
    exit 0
fi
logs=$(mktemp -d "${TMPDIR:-/tmp}/build.XXXXXX")
trap 'rm -rf "$logs"' EXIT
one() { # NAME PROGRAMS... -- FLAGS: its output, then its time or failure, in its log
    name=$1
    shift
    t=$(date +%s)
    if sh scripts/multicall.sh "$name" "$bin" "$pipelines" "$@" > "$logs/$name" 2>&1; then
        echo "build.sh: $name in $(($(date +%s) - t)) s" >> "$logs/$name"
    else
        echo "build.sh: $name FAILED (exit $?)" >> "$logs/$name"
        return 1
    fi
}
one multicall-apps $apps -- "$@" &
apps_pid=$!
one multicall-pipelines $rest -- "$@" &
pipelines_pid=$!
failed=""
wait "$apps_pid" || failed="$failed multicall-apps"
wait "$pipelines_pid" || failed="$failed multicall-pipelines"
cat "$logs/multicall-apps" "$logs/multicall-pipelines"
[ -z "$failed" ] || { echo "build.sh: failed:$failed" >&2; exit 1; }
