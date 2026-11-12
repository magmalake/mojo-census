# Source this for a local run: the lasting Postgres under build/pg (see
# README), the warehouse and logs under build/, and a small slice of GH
# Archive. `. scripts/env.sh` inside `pixi shell`.
export MORCA_DATABASE_URL="postgresql:///orca?host=$PWD/build&user=postgres"
export MORCA_WAREHOUSE="$PWD/build/warehouse"
export MORCA_LOGS="$PWD/build/logs"
export GHARCHIVE_HOURS="${GHARCHIVE_HOURS:-15,17}"
export MOJO_HISTORY_MAX_KB="${MOJO_HISTORY_MAX_KB:-100000}"
export MOJO_HISTORY_WORKDIR="${MOJO_HISTORY_WORKDIR:-$PWD/build/clones}"
export MORCA_SENSE_SECONDS="${MORCA_SENSE_SECONDS:-10}"
