#!/bin/bash
# sys-tune-node.sh <status|runtime|persist|nic|revert>: kernel/system tuning of the
# DAOS servers and compute nodes, run as root on each node.
#   runtime  apply now without reboot: kernel.numa_balancing=0, kernel.nmi_watchdog=0,
#            disable cpuidle states deeper than C1E (exit latency > 10 us),
#            clients only: transparent_hugepage=madvise
#   persist  make the same survive a reboot: /etc/sysctl.d/90-hpc-tuning.conf and kernel
#            args intel_idle.max_cstate=1 processor.max_cstate=1 (clients also
#            transparent_hugepage=madvise) via grubby
#   nic      mlx5 firmware (mstconfig, takes effect after a cold reboot):
#            ADVANCED_PCI_SETTINGS=1 PCI_WR_ORDERING=1 (force relaxed ordering)
#            CQE_COMPRESSION=1 (aggressive). Broadcom ports are left alone.
#   revert   undo runtime+persist+nic (numa_balancing=1, nmi_watchdog=1, cpuidle
#            states enabled, sysctl file removed, kernel args removed, mlx5
#            PCI_WR_ORDERING=0 CQE_COMPRESSION=0 ADVANCED_PCI_SETTINGS=0)
# Nothing here touches DAOS, NVMe or the RoCE QoS.
set -uo pipefail
MODE="${1:?status|runtime|persist|nic|revert}"
H=$(hostname); rc=0
say() { echo "$H $*"; }
fail() { echo "$H ERROR $*"; rc=1; }
is_client() { [[ "$H" == Haetae-* ]]; }
ARGS="intel_idle.max_cstate=1 processor.max_cstate=1"
is_client && ARGS="$ARGS transparent_hugepage=madvise"
SYSCTL=/etc/sysctl.d/90-hpc-tuning.conf

cstates() {   # $1 = 1 to disable deep states, 0 to enable all
  for s in /sys/devices/system/cpu/cpu*/cpuidle/state*; do
    [ "$(cat "$s/latency")" -gt 10 ] && echo "$1" > "$s/disable"
  done
}
mlx_bdfs() { for d in /sys/class/infiniband/mlx5_*; do basename "$(readlink -f "$d/device")"; done; }

case "$MODE" in
  runtime)
    sysctl -q -w kernel.numa_balancing=0 kernel.nmi_watchdog=0 || fail "sysctl"
    cstates 1
    is_client && { echo madvise > /sys/kernel/mm/transparent_hugepage/enabled || fail "thp"; }
    ;;
  persist)
    printf 'kernel.numa_balancing = 0\nkernel.nmi_watchdog = 0\n' > $SYSCTL
    grubby --update-kernel=DEFAULT --args="$ARGS" || fail "grubby"
    ;;
  nic)
    for b in $(mlx_bdfs); do
      mstconfig -y -d "$b" set ADVANCED_PCI_SETTINGS=1 PCI_WR_ORDERING=1 CQE_COMPRESSION=1 > /tmp/mstconfig-$b.log 2>&1 ||
        fail "$b mstconfig (see /tmp/mstconfig-$b.log)"
    done
    ;;
  revert)
    sysctl -q -w kernel.numa_balancing=1 kernel.nmi_watchdog=1; cstates 0
    is_client && echo always > /sys/kernel/mm/transparent_hugepage/enabled
    rm -f $SYSCTL; grubby --update-kernel=DEFAULT --remove-args="$ARGS" || fail "grubby"
    for b in $(mlx_bdfs); do
      mstconfig -y -d "$b" set PCI_WR_ORDERING=0 CQE_COMPRESSION=0 ADVANCED_PCI_SETTINGS=0 > /tmp/mstconfig-$b.log 2>&1 || fail "$b mstconfig revert"
    done
    ;;
  status) ;;
  *) echo "usage: $0 status|runtime|persist|nic|revert" >&2; exit 2 ;;
esac

deep=$(for s in /sys/devices/system/cpu/cpu0/cpuidle/state*; do [ "$(cat $s/latency)" -gt 10 ] && echo -n "$(cat $s/name):$([ "$(cat $s/disable)" = 1 ] && echo off || echo on) "; done)
say "numa_balancing=$(cat /proc/sys/kernel/numa_balancing) nmi_watchdog=$(cat /proc/sys/kernel/nmi_watchdog) thp=$(grep -oE '\[[a-z]+\]' /sys/kernel/mm/transparent_hugepage/enabled) deep_cstates[$deep] sysctl_file=$([ -f $SYSCTL ] && echo yes || echo no) kargs[$(grubby --info=DEFAULT 2>/dev/null | grep -oE 'max_cstate=[0-9]+|transparent_hugepage=[a-z]+' | paste -sd' ')]"
for b in $(mlx_bdfs); do
  say "mlx5 $b $(mstconfig -d "$b" q ADVANCED_PCI_SETTINGS PCI_WR_ORDERING CQE_COMPRESSION 2>/dev/null | grep -E 'ADVANCED|WR_ORD|CQE' | awk '{print $1"="$2}' | paste -sd' ')"
done
exit $rc
