#!/bin/bash

# IO500 launcher for DAOS (DFS API), derived from io500.sh of io500-sc26.
# Only the part above the "SHOULD NOT EDIT" line differs from upstream.
#
# Runs from anywhere; it cd's to the io500 build dir (default ../io500):
#   STONEWALL=300 PPN=64 ./run-io500.sh [config-tmpl.ini]
#
# Environment knobs:
#   DAOS_POOL, DAOS_CONT  pool / POSIX container labels (default: io500)
#   HOSTFILE              one client hostname per line (default: clients/hosts)
#   PPN                   MPI ranks per client node (default: 64)
#   BIND                  core (default) or hwthread for PPN > physical cores
#   MAP                   Open MPI --map-by (default ppr:$PPN:node); ppr:N:socket
#                         keeps each socket's ranks on its own NIC (dual rail)
#   RAIL_SPLIT            A:B pins A/(A+B) of each node's ranks to socket 0
#                         (CX-7) and the rest to socket 1 (CX-6), e.g. 2:1;
#                         rail-bind.sh re-pins each rank after MPI's binding
#   STONEWALL            stonewall seconds; < 300 is a smoke test, INVALID run
#   MPI_PML               ucx (default, MPI over RDMA) or ob1 (TCP btl)
#   ENV_SET               "K=V ..." added to, or replacing, io500_env
#   ENV_UNSET             "K ..." dropped from io500_env
#
# Per-run diagnostics (env, mpirun line, node state, fabric NIC counter
# deltas) go to $KIT_DIR/runs/<timestamp>, not into the result tarball.

KIT_DIR="$(cd "$(dirname "$0")" && pwd)"

# create_tarball copies $0 after the cd below, so it must be absolute
if [ "${0:0:1}" != "/" ]
then
  exec "$KIT_DIR/$(basename "$0")" "$@"
fi

# Runnable as plain ./run-io500.sh: default ini, io500 build dir, Open MPI PATH
io500_tmpl="$(realpath "${1:-$KIT_DIR/config-production-tmpl.ini}")"
HOSTFILE="$(realpath "${HOSTFILE:-$KIT_DIR/clients/hosts}")"
cd "${IO500_DIR:-$KIT_DIR/../io500}"

if ! command -v mpirun > /dev/null && [ -x /usr/lib64/openmpi/bin/mpirun ]
then
  export PATH=/usr/lib64/openmpi/bin:$PATH
fi

DAOS_POOL="${DAOS_POOL:-io500}"
DAOS_CONT="${DAOS_CONT:-io500}"
PPN="${PPN:-64}"
# core: up to 96 ranks per client; hwthread: up to 192 (uses hyperthreads)
BIND="${BIND:-core}"
MAP="${MAP:-ppr:$PPN:node}"

io500_launch=""
if [ -n "${RAIL_SPLIT:-}" ]
then
  io500_launch="$KIT_DIR/rail-bind.sh $RAIL_SPLIT"
fi
STONEWALL="${STONEWALL:-300}"

NNODES="$(grep -cv '^\s*\(#\|$\)' "$HOSTFILE")"
NPROC="$((NNODES * PPN))"

# 4/9 of the ranks run find, with a queue of 45 entries per find rank
FIND_NPROC="${FIND_NPROC:-$((NPROC * 4 / 9))}"
FIND_QLEN="${FIND_QLEN:-$((FIND_NPROC * 45))}"

# Render the template into the current directory; the rendered file is what
# io500 reads and what create_tarball() puts into the result tarball.
io500_ini="$PWD/$(basename "${io500_tmpl/-tmpl.ini/.ini}")"
sed -e "s/@DAOS_POOL@/$DAOS_POOL/g" \
    -e "s/@DAOS_CONT@/$DAOS_CONT/g" \
    -e "s/@FIND_NPROC@/$FIND_NPROC/g" \
    -e "s/@FIND_QLEN@/$FIND_QLEN/g" \
    -e "s/@STONEWALL@/$STONEWALL/g" \
    "$io500_tmpl" > "$io500_ini"

io500_env=(
  # pfind reads the pool/container from these two variables, not from the ini
  "DAOS_POOL=$DAOS_POOL"
  "DAOS_CONT=$DAOS_CONT"

  "CRT_CREDIT_EP_CTX=0"
  "CRT_MRC_ENABLE=1"
  "CRT_TIMEOUT=600"

  # Only used by the ofi+verbs provider; ignored under ucx+*
  "FI_OFI_RXM_USE_SRX=1"
  "FI_UNIVERSE_SIZE=16384"
  "FI_VERBS_INLINE_SIZE=128"
  "FI_VERBS_PREFER_XRC=1"
)

env_drop=" $ENV_UNSET "
for kv in $ENV_SET
do
  env_drop+="${kv%%=*} "
done
env_keep=()
for kv in "${io500_env[@]}"
do
  [[ "$env_drop" == *" ${kv%%=*} "* ]] || env_keep+=("$kv")
done
io500_env=("${env_keep[@]}" $ENV_SET)

io500_mpirun="mpirun"

if mpirun --version 2>&1 | grep -q "Open MPI"
then
  # MPI_NET: subnet for MPI's own TCP traffic (default: management network)
  mpi_net="${MPI_NET:-10.100.230.0/24}"
  io500_mpiargs="-np $NPROC --hostfile $HOSTFILE --map-by $MAP --bind-to $BIND"
  io500_mpiargs+=" --mca oob_tcp_if_include $mpi_net --mca btl_tcp_if_include $mpi_net"

  # Open MPI counts only physical cores as slots; PPN > 96 needs hyperthreads
  if [ "$BIND" != "core" ]
  then
    io500_mpiargs+=" --use-hwthread-cpus"
  fi

  # MPI does not use libfabric. MPI_PML=ucx (default): MPI over UCX/RDMA on
  # the data network; MPI_PML=ob1: TCP.
  if [ "${MPI_PML:-ucx}" = "ucx" ]
  then
    io500_mpiargs+=" --mca pml ucx --mca osc ucx --mca btl ^tcp,ofi --mca mtl ^ofi"
    io500_mpiargs+=" -x UCX_TLS=dc_x,sm,self -x UCX_IB_ROCE_REACHABILITY_MODE=all"
  else
    io500_mpiargs+=" --mca pml ob1 --mca btl self,sm,tcp --mca mtl ^ofi"
  fi

  for kv in "${io500_env[@]}"
  do
    io500_mpiargs+=" -x $kv"
  done
else
  # MPICH (hydra)
  io500_mpiargs="-np $NPROC -ppn $PPN -f $HOSTFILE -bind-to $BIND -map-by $BIND"

  for kv in "${io500_env[@]}"
  do
    io500_mpiargs+=" -genv ${kv%%=*} ${kv#*=}"
  done
fi

function setup(){
  local workdir="$1"
  local resultdir="$2"

  # The datadir lives inside the DAOS container and is created by io500
  # itself through the DFS API, so only the local result dir is made here.
  mkdir -p $resultdir

  local snap="$KIT_DIR/node-snapshot.sh"
  local diagdir="$KIT_DIR/runs/$(basename $resultdir)"
  mkdir -p $diagdir
  printf '%s\n' "${io500_env[@]}" > $diagdir/env.txt
  echo "$io500_mpirun $io500_mpiargs" > $diagdir/mpirun.txt
  cp $io500_ini $HOSTFILE $diagdir/
  $snap state $HOSTFILE > $diagdir/state.txt
  $snap nic $HOSTFILE > $diagdir/nic-before.txt
  # Runs on success and on failure; a failed phase is when drops matter most
  trap "$snap nic $HOSTFILE > $diagdir/nic-after.txt;
        $snap delta $diagdir/nic-before.txt $diagdir/nic-after.txt > $diagdir/nic-delta.txt" EXIT
}

# *****  YOU SHOULD NOT EDIT ANYTHING BELOW THIS LINE  *****
set -eo pipefail  # better error handling

if [[ -z "$io500_ini" ]]; then
  echo "error: ini file must be specified.  usage: $0 <config.ini>"
  exit 1
fi
if [[ ! -s "$io500_ini" ]]; then
  echo "error: ini file '$io500_ini' not found or empty"
  exit 2
fi

function get_ini_section_param() {
  local section="$1"
  local param="$2"
  local inside=false

  while read LINE; do
    LINE=$(sed -e 's/ *#.*//' -e '1s/ *= */=/' <<<$LINE)
    $inside && [[ "$LINE" =~ "[.*]" ]] && inside=false && break
    [[ -n "$section" && "$LINE" =~ "[$section]" ]] && inside=true && continue
    ! $inside && continue
    #echo $LINE | awk -F = "/^$param/ { print \$2 }"
    if [[ $(echo $LINE | grep "^$param *=" ) != "" ]] ; then
      # echo "$section : $param : $inside : $LINE" >> parsed.txt # debugging
      echo $LINE | sed -e "s/[^=]*=[ \t]*\(.*\)/\1/"
      return
    fi
  done < $io500_ini
  echo ""
}

function get_ini_global_param() {
  local param="$1"
  local default="$2"
  local val

  val=$(get_ini_section_param global $param |
  	sed -e 's/[Ff][Aa][Ll][Ss][Ee]/False/' -e 's/[Tt][Rr][Uu][Ee]/True/')

  echo "${val:-$default}"
}

function run_benchmarks {
  $io500_mpirun $io500_mpiargs $io500_launch $PWD/io500 $io500_ini --timestamp $timestamp
}

create_tarball() {
  local sourcedir=$(dirname $io500_resultdir)
  local fname=$(basename ${io500_resultdir})
  local tarball=$sourcedir/io500-$HOSTNAME-$fname.tgz

  cp -v $0 $io500_ini $io500_resultdir
  tar czf $tarball -C $sourcedir $fname
  echo "Created result tarball $tarball"
}

function main {
  # These commands extract the 'datadir' and 'resultdir' from .ini file
  timestamp=$(date +%Y.%m.%d-%H.%M.%S)           # create a uniquifier
  [ $(get_ini_global_param timestamp-datadir True) != "False" ] &&
    ts="$timestamp" || ts="io500"
  # working directory where the test files will be created
  export io500_workdir=$(get_ini_global_param datadir $PWD/datafiles)/$ts
  [ $(get_ini_global_param timestamp-resultdir True) != "False" ] &&
    ts="$timestamp" || ts="io500"
  # the directory where the output results will be kept
  export io500_resultdir=$(get_ini_global_param resultdir $PWD/results)/$ts

  setup $io500_workdir $io500_resultdir
  run_benchmarks
  create_tarball
}

main
