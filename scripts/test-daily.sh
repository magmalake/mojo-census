#!/bin/sh
# gharchive commits its three index tables once a day. This checks, on three
# real hours of GH Archive (about 300 MB of downloads), that
#   - the index rows are the rows the hourly commits of origin/main wrote,
#   - a step that fails after k hours is retried (orca's SQLite store gives
#     the run a number) and ends with exactly the same rows and one commit
#     of each index table, rebuilding the skipped hours from the events,
#   - a failure after the index commits is retried without committing again,
#   - a rerun of the day replaces all four tables' rows,
#   - with GHARCHIVE_EVENTS=off the index rows are the same, nothing is
#     written to gharchive.events, and a retry (after 2 hours, or after the
#     index commits) and a rerun leave one copy of the rows.
#
#   scripts/test-daily.sh build/gharchive-main build/gharchive
#
# The first is gharchive built from origin/main, the second from this tree
# (`pixi run build-gharchive`). Run inside `pixi shell` or `pixi run`.
set -eu
OLD=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
NEW=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
W=${TMPDIR:-/tmp}/census-test-daily
DAY=2024-06-12
export GHARCHIVE_HOURS=15,16,17
rm -rf "$W"
mkdir -p "$W"

mojo build -I src tools/dump_index.mojo -o "$W/dump_index"
digest() { # warehouse table
  out=$(ORCA_WAREHOUSE="$1" "$W/dump_index" "$2") || exit 1
  [ -n "$out" ] || { echo "FAIL: no digest of $2 in $1" >&2; exit 1; }
  echo "$out"
}
rows() { # a table's line without its marker count and snapshot count
  digest "$1" "$2" | sed 's/ markers.*//'
}
snaps() { digest "$1" "$2" | sed 's/.*snapshots //'; }
fail() { echo "FAIL: $*" >&2; exit 1; }
same() { # warehouse-a warehouse-b
  for t in gharchive.candidates gharchive.repo_hour gharchive.releases; do
    a=$(rows "$1" $t); b=$(rows "$2" $t)
    [ "$a" = "$b" ] || fail "$t differs: $a / $b"
    echo "ok: $a"
  done
}
echo "== origin/main, an hour a commit"
ORCA_WAREHOUSE=$W/old $OLD run --partitions $DAY > "$W/old.log"

echo "== a day a commit"
ORCA_WAREHOUSE=$W/new $NEW run --partitions $DAY > "$W/new.log"
same "$W/old" "$W/new"
for t in gharchive.candidates gharchive.repo_hour gharchive.releases; do
  [ "$(snaps "$W/new" $t)" = 1 ] || fail "$t: not one snapshot"
  [ "$(snaps "$W/old" $t)" = 3 ] || fail "old $t: not three snapshots"
done

echo "== fails after 2 hours, retried"
ORCA_DATABASE_URL=sqlite:///$W/resume.db ORCA_WAREHOUSE=$W/resume \
  GHARCHIVE_FAIL_AFTER=2 $NEW run --partitions $DAY > "$W/resume.log"
grep -q "2 hours already committed" "$W/resume.log" || fail "no resume"
grep -q "rebuilding the index of the 2 committed hours" "$W/resume.log" \
  || fail "no rebuild"
same "$W/new" "$W/resume"
[ "$(snaps "$W/resume" gharchive.candidates)" = 1 ] || fail "resume: two commits"

echo "== fails after the index commits, retried"
ORCA_DATABASE_URL=sqlite:///$W/end.db ORCA_WAREHOUSE=$W/end \
  GHARCHIVE_FAIL_AFTER=end $NEW run --partitions $DAY > "$W/end.log"
grep -q "3 hours already committed" "$W/end.log" || fail "no resume (end)"
if grep -q "rebuilding" "$W/end.log"; then fail "rebuilt a committed index"; fi
same "$W/new" "$W/end"
for t in gharchive.candidates gharchive.repo_hour gharchive.releases; do
  [ "$(snaps "$W/end" $t)" = 1 ] || fail "end: $t committed twice"
done

echo "== the day again replaces its rows"
ORCA_DATABASE_URL=sqlite:///$W/new.db ORCA_WAREHOUSE=$W/new \
  $NEW run --partitions $DAY > "$W/again.log"
grep -q "replacing the" "$W/again.log" || fail "no replace"
same "$W/old" "$W/new"
for t in gharchive.candidates gharchive.repo_hour gharchive.releases; do
  [ "$(snaps "$W/new" $t)" = 2 ] || fail "again: $t not two snapshots"
done
echo "== GHARCHIVE_EVENTS=off: the same index, no events"
GHARCHIVE_EVENTS=off ORCA_WAREHOUSE=$W/off $NEW run --partitions $DAY > "$W/off.log"
same "$W/old" "$W/off"
[ -e "$W/off/gharchive/events" ] && fail "off: wrote gharchive.events"
for t in gharchive.candidates gharchive.repo_hour gharchive.releases; do
  [ "$(snaps "$W/off" $t)" = 1 ] || fail "off: $t not one snapshot"
done

echo "== GHARCHIVE_EVENTS=off, fails after 2 hours, retried"
GHARCHIVE_EVENTS=off ORCA_DATABASE_URL=sqlite:///$W/off-resume.db \
  ORCA_WAREHOUSE=$W/off-resume GHARCHIVE_FAIL_AFTER=2 \
  $NEW run --partitions $DAY > "$W/off-resume.log"
grep -q "GHARCHIVE_FAIL_AFTER=2" "$W/off-resume.log" || fail "off: no failure"
same "$W/old" "$W/off-resume"
for t in gharchive.candidates gharchive.repo_hour gharchive.releases; do
  [ "$(snaps "$W/off-resume" $t)" = 1 ] || fail "off resume: $t committed twice"
done

echo "== GHARCHIVE_EVENTS=off, fails after the index commits, retried"
GHARCHIVE_EVENTS=off ORCA_DATABASE_URL=sqlite:///$W/off-end.db \
  ORCA_WAREHOUSE=$W/off-end GHARCHIVE_FAIL_AFTER=end \
  $NEW run --partitions $DAY > "$W/off-end.log"
grep -q "the index is committed already" "$W/off-end.log" \
  || fail "off: no resume (end)"
same "$W/old" "$W/off-end"
for t in gharchive.candidates gharchive.repo_hour gharchive.releases; do
  [ "$(snaps "$W/off-end" $t)" = 1 ] || fail "off end: $t committed twice"
done

echo "== GHARCHIVE_EVENTS=off, the day again over a day loaded with them"
ev=$(digest "$W/new" gharchive.events)
GHARCHIVE_EVENTS=off ORCA_DATABASE_URL=sqlite:///$W/new.db \
  ORCA_WAREHOUSE=$W/new $NEW run --partitions $DAY > "$W/off-again.log"
same "$W/old" "$W/new"
for t in gharchive.candidates gharchive.repo_hour gharchive.releases; do
  [ "$(snaps "$W/new" $t)" = 3 ] || fail "off again: $t not three snapshots"
done
[ "$(digest "$W/new" gharchive.events)" = "$ev" ] || fail "off again: events changed"
echo "all ok"
