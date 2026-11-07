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
sh scripts/multicall.sh multicall-apps "$bin" "$pipelines" $apps -- "$@"
sh scripts/multicall.sh multicall-pipelines "$bin" "$pipelines" $rest -- "$@"
