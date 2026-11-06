#!/bin/bash
#
# Per-rank CPU pinning for dual-rail clients, used by run-io500.sh when
# RAIL_SPLIT is set:
#
#   rail-bind.sh A:B|auto|node <command...>
#
# Of the ranks on this node, A/(A+B) go to socket 0 and the rest to socket 1.
# "auto" takes A and B from the link speeds of this node's DAOS fabric
# interfaces (daos_agent.yml) on NUMA node 0 and 1, so each socket gets ranks
# in proportion to its NIC bandwidth. "node" is "auto" with a Broadcom
# (bnxt_en) interface counted at half its link speed. At PPN 144 this gives
# 72:72 on nodes with CX-7 400G + 2x CX-6 200G and 96:48 on the others.
# Each rank gets one hwthread, physical cores first, then their hyperthread
# siblings. The DAOS
# agent picks the NIC from the NUMA node the rank runs on (fabric_ifaces in
# daos_agent.yml), so pinning the CPU is what picks the rail.
#
# Broadcom bnxt_re reports max_qp_wr 2039. With FI_OFI_RXM_USE_SRX=1 (from
# the server's client_env_vars) ofi_rxm asks the verbs MSG endpoint for 4096
# receive entries, libfabric then drops the bnxt_re domain and DAOS init fails
# with DER_HG. On nodes with that NIC every rank caps it at 2039; a client
# environment variable takes precedence over the server-supplied ones.
if [ -e /sys/class/infiniband/bnxt_re0 ]
then
  export FI_OFI_RXM_MSG_RX_SIZE=2039
fi

# libfabric's MR cache does not take effect with its default memory monitor
# here, so every I/O would register and deregister its buffer; with
# userfaultfd the cache works.
export FI_MR_CACHE_MONITOR=userfaultfd

# MPI runs on UCX and would otherwise use every active mlx5 port; limit it to
# the mlx5 ports behind the DAOS fabric interfaces in daos_agent.yml.
ucx_devs=""
for ifc in $(sed -n 's/^ *iface: *//p' /etc/daos/daos_agent.yml)
do
  for ib in /sys/class/net/"$ifc"/device/infiniband/mlx5_*
  do
    [ -e "$ib" ] && ucx_devs="${ucx_devs:+$ucx_devs,}$(basename "$ib"):1"
  done
done
if [ -n "$ucx_devs" ]
then
  export UCX_NET_DEVICES="$ucx_devs"
fi

split="$1"
shift

local_rank="${OMPI_COMM_WORLD_LOCAL_RANK:?not launched by Open MPI}"
local_size="${OMPI_COMM_WORLD_LOCAL_SIZE:?not launched by Open MPI}"

# "0-47,96-143" -> one cpu per line, in list order
expand_cpus()
{
  local range

  for range in ${1//,/ }
  do
    seq "${range%-*}" "${range#*-}"
  done
}

last_cpu=$(($(nproc --all) - 1))
s0_cpus=($(expand_cpus "$(cat /sys/devices/system/cpu/cpu0/topology/package_cpus_list)"))
s1_cpus=($(expand_cpus "$(cat /sys/devices/system/cpu/cpu$last_cpu/topology/package_cpus_list)"))

# Sum of link speeds (Mb/s) of the agent's fabric interfaces on a NUMA node;
# with a second argument "half-bnxt", bnxt_en interfaces count half
numa_bw()
{
  local ifc total=0 speed drv

  for ifc in $(awk -v want="$1" '
      /numa_node:/ { numa = $2 }
      /iface:/ && numa == want { print $2 }' /etc/daos/daos_agent.yml)
  do
    speed=$(cat /sys/class/net/"$ifc"/speed 2> /dev/null) || speed=0
    [ "${speed:-0}" -gt 0 ] || continue
    drv=$(basename "$(readlink -f /sys/class/net/"$ifc"/device/driver)")
    [ "${2:-}" = half-bnxt ] && [ "$drv" = bnxt_en ] && speed=$((speed / 2))
    total=$((total + speed))
  done
  echo "$total"
}

if [ "$split" = auto ] || [ "$split" = node ]
then
  mode=""
  [ "$split" = node ] && mode=half-bnxt
  bw0=$(numa_bw 0 $mode)
  bw1=$(numa_bw 1 $mode)
  if [ "$bw0" -le 0 ] || [ "$bw1" -le 0 ]
  then
    echo "rail-bind: auto split needs a linked fabric NIC on both NUMA nodes ($bw0:$bw1)" >&2
    exit 1
  fi
  split="$((bw0 / 1000)):$((bw1 / 1000))"
fi

weight0="${split%:*}"
weight1="${split#*:}"
n0=$(((local_size * weight0 + (weight0 + weight1) / 2) / (weight0 + weight1)))

if [ "$n0" -gt "${#s0_cpus[@]}" ] || [ $((local_size - n0)) -gt "${#s1_cpus[@]}" ]
then
  echo "rail-bind: $local_size ranks with split $split do not fit the sockets" >&2
  exit 1
fi

if [ "$local_rank" -lt "$n0" ]
then
  cpu="${s0_cpus[$local_rank]}"
else
  cpu="${s1_cpus[$((local_rank - n0))]}"
fi

exec taskset -c "$cpu" "$@"
