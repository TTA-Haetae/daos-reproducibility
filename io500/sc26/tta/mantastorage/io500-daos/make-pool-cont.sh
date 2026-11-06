#!/bin/bash
#
# Pool and POSIX container for the two IO500 tracks, in two steps because dmg
# only works on the servers and daos only where daos_agent runs:
#
#   make-pool-cont.sh pool                       # on a server (root), e.g. MantaStorage-01
#   PROFILE=prod make-pool-cont.sh cont          # on a client, as the io500 user
#   PROFILE=research make-pool-cont.sh cont
#
# Profiles (container properties, checked after creation with lib.sh):
#   prod      io500-prod, rd_fac:1, rd_lvl:2 (node): survives the loss of
#             one server (2 engines), as the Production list requires
#   research  io500-research, rd_fac:0: Research list only
#
# 'pool' only creates a missing pool and never destroys one; recreating a
# pool is a manual step between runs. It creates the pool with a fixed
# data_thresh (DATA_THRESH bytes, default 2048: 3901-byte mdtest-hard files
# go to the data tier instead of metadata), and for an existing pool it
# checks that data_thresh is that value, since it is a pool property that
# changes placement for every container and can be changed at any time.
# 'cont' destroys and recreates only the track's own container.
#
#   POOL_SIZE=100% POOL_OWNER=gluesys ./make-pool-cont.sh pool
#   POOL_ARGS="--mem-ratio=50%" ./make-pool-cont.sh pool   (technology preview in 2.8)

set -euo pipefail
. "$(dirname "$0")/lib.sh"

PROFILE="${PROFILE:-}"
DAOS_POOL="${DAOS_POOL:-io500}"
POOL_SIZE="${POOL_SIZE:-100%}"
POOL_ARGS="${POOL_ARGS:-}"
POOL_OWNER="${POOL_OWNER:-gluesys}"
DATA_THRESH="${DATA_THRESH:-2048}"

safe_pool "$DAOS_POOL"

case "${1:-}" in
pool)
  safe_size "$POOL_SIZE"
  safe_word "$POOL_OWNER" "$DATA_THRESH"
  [[ "$DATA_THRESH" =~ ^[0-9]+$ ]] || { echo "DATA_THRESH must be bytes" >&2; exit 1; }
  pools="$(dmg pool list -j | pool_labels)"
  if grep -q -x -F "$DAOS_POOL" <<< "$pools"
  then
    echo "pool $DAOS_POOL exists, kept"
  else
    dmg pool create --size="$POOL_SIZE" $POOL_ARGS --properties="data_thresh:$DATA_THRESH" \
      --user="$POOL_OWNER@" --group="$POOL_OWNER@" "$DAOS_POOL"
  fi
  props="$(dmg pool get-prop -j "$DAOS_POOL" | pool_props)"
  grep -q -x "data_thresh=$DATA_THRESH" <<< "$props" ||
    { echo "pool $DAOS_POOL: $(grep data_thresh <<< "$props"), want $DATA_THRESH" >&2; exit 1; }
  dmg pool query -j "$DAOS_POOL" | pool_health
  dmg pool query -j "$DAOS_POOL" | pool_space
  ;;
cont)
  case "$PROFILE" in
  prod) CONT_PROPS="rd_fac:1,rd_lvl:2" ;;
  research) CONT_PROPS="rd_fac:0" ;;
  *) echo "PROFILE must be prod or research" >&2; exit 1 ;;
  esac
  DAOS_CONT="${DAOS_CONT:-io500-$PROFILE}"
  [[ "$DAOS_CONT" =~ $OWN_CONT_RE ]] || { echo "refusing container $DAOS_CONT" >&2; exit 1; }

  conts="$(daos container list -j "$DAOS_POOL" | cont_labels)"
  if grep -q -x -F "$DAOS_CONT" <<< "$conts"
  then
    daos container destroy --force "$DAOS_POOL" "$DAOS_CONT"
  fi
  daos container create --type=POSIX \
    --properties="$CONT_PROPS,compression:off,dedup:off" \
    "$DAOS_POOL" "$DAOS_CONT"

  props="$(daos container get-prop -j "$DAOS_POOL" "$DAOS_CONT" | check_cont_props "$PROFILE")"
  echo "container-ok $DAOS_CONT profile=$PROFILE $props"
  ;;
*)
  echo "usage: $0 pool                         (on a server, as root)" >&2
  echo "       PROFILE=prod|research $0 cont   (on a client)" >&2
  exit 1
  ;;
esac
