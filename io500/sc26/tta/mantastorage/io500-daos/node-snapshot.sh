#!/bin/bash
#
# Record what every client looked like around an IO500 run.
#
#   node-snapshot.sh state  HOSTFILE > state.txt      # packages, sysctl, agent
#   node-snapshot.sh nic    HOSTFILE > nic.txt        # fabric NIC counters
#   node-snapshot.sh delta  before.txt after.txt      # counters that moved
#
# The fabric NIC is the one in include_fabric_ifaces of daos_agent.yml.
# ethtool -S works without root; output lines are "host iface counter value".

mode="$1"

hosts() {
  grep -v '^\s*\(#\|$\)' "$1"
}

remote_state='
echo "## $(hostname)"
uname -r
rpm -q daos-client libfabric mercury libibverbs rdma-core ucx 2>&1 | tr "\n" " "; echo
echo "agent $(md5sum < /etc/daos/daos_agent.yml | cut -c1-8)" \
     "io500 $(md5sum < ~/io500/io500 | cut -c1-8)"
echo "numa_balancing $(cat /proc/sys/kernel/numa_balancing)" \
     "thp $(cat /sys/kernel/mm/transparent_hugepage/enabled)" \
     "governor $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)"
for i in $(sed -n "s/^include_fabric_ifaces: *\[\(.*\)\]/\1/p" /etc/daos/daos_agent.yml | tr ",\"" "  "); do
  echo "$i speed $(cat /sys/class/net/$i/speed) mtu $(cat /sys/class/net/$i/mtu)" \
       "numa $(cat /sys/class/net/$i/device/numa_node)"
done
'

remote_nic='
h=$(hostname)
for i in $(sed -n "s/^include_fabric_ifaces: *\[\(.*\)\]/\1/p" /etc/daos/daos_agent.yml | tr ",\"" "  "); do
  /usr/sbin/ethtool -S $i |
    awk -v h=$h -v i=$i -F": *" "/discard|pause_ctrl|out_of_buffer|_bytes_phy|rx_crc_errors_phy/ {gsub(/ /,\"\",\$1); print h, i, \$1, \$2}"
done
'

case "$mode" in
state|nic)
  [ "$mode" = state ] && cmd="$remote_state" || cmd="$remote_nic"
  for h in $(hosts "$2")
  do
    # A host that could not be read must not look like a host with no drops
    { ssh -o BatchMode=yes -o ConnectTimeout=5 "$h" "$cmd" ||
        echo "$h SNAPSHOT_FAILED rc=$?"; } > "/tmp/snap.$$.$h" 2>&1 &
  done
  wait
  for h in $(hosts "$2")
  do
    cat "/tmp/snap.$$.$h"
    rm -f "/tmp/snap.$$.$h"
  done
  ;;
delta)
  # host iface counter before after diff: nonzero diffs, plus counters
  # present on only one side ("-"), so a failed snapshot shows up here
  awk 'NR == FNR { v[$1" "$2" "$3] = $4; next }
       { k = $1" "$2" "$3; seen[k] = 1 }
       !(k in v) { print k, "-", $4, "-"; next }
       $4 != v[k] { print k, v[k], $4, $4 - v[k] }
       END { for (k in v) if (!(k in seen)) print k, v[k], "-", "-" }' "$2" "$3" | column -t
  ;;
*)
  echo "usage: $0 state|nic HOSTFILE  |  $0 delta BEFORE AFTER" >&2
  exit 1
  ;;
esac
