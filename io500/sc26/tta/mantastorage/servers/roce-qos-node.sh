#!/bin/bash
#
# roce-qos-node.sh <status|apply|revert|install|uninstall>: run as root on each DAOS server and
# compute node. Puts every RDMA port of
# the node into the switch's RoCE lossless class (Cumulus "qos roce"
# defaults): RoCE DSCP 26 -> priority 3 with PFC, CNP DSCP 48 ->
# priority 6, ECN on, 802.3x pause off.
#   mlx5_*   mlnx_qos --trust dscp --pfc 0,0,0,1,0,0,0,0, ethtool -A off,
#            rdma_cm default_roce_tos 106 (DSCP 26, ECT). CNP is already
#            DSCP 48 / prio 6 (mlx5 default).
#   bnxt_re* Broadcom bnxt_setupcc.sh (the copy next to the installed
#            239.1.170.0 driver) -m 3 -r 3 -s 26 -c 6 -p 48 -u 4 (dcb):
#            pause off, ETS, PFC prio 3, dcb app 4791/26 -> 3, 48 -> 6,
#            bnxt_re configfs cc (roce/cnp prio and dscp, ECN), rdma_cm tos.
# apply saves the state before the first change in $STATE/<netdev>.* and
# keeps that copy when run again; revert restores it and deletes it. The
# settings themselves are not persistent; "install" (below) re-applies them
# at every boot. New RDMA connections only pick up the
# ToS, so DAOS engines, agents and clients must restart afterwards.
set -uo pipefail
MODE="${1:?status|apply|revert|install|uninstall}"
STATE=/var/lib/roce-qos
SETUPCC=/home/gluesys/bnxt/netxtreme-bnxt_en-1.10.3-239.1.170.0/bnxt_re-239.1.170.0/bnxt_setupcc.sh
TOS=106
H=$(hostname)
rc=0

say() { echo "$H $*"; }
fail() { echo "$H ERROR $*"; rc=1; }

cm_dir() { echo "/sys/kernel/config/rdma_cm/$1/ports/1"; }
cm_tos() {
  local made=0 v
  [ -d "/sys/kernel/config/rdma_cm/$1" ] || { mkdir "/sys/kernel/config/rdma_cm/$1" || return 1; made=1; }
  if [ $# -eq 2 ]; then echo -n "$2" > "$(cm_dir "$1")/default_roce_tos" || v=ERR; fi
  v=${v:-$(cat "$(cm_dir "$1")/default_roce_tos")}
  [ $made = 1 ] && rmdir "/sys/kernel/config/rdma_cm/$1"
  echo "$v"
}
# bnxt_re configfs cc: read (no value) or write name=value pairs, then apply
BNXT_CC="roce_prio roce_dscp cnp_prio cnp_dscp ecn_enable ecn_marking cc_mode disable_prio_vlan_tx"
bnxt_cc() {
  local dev=$1 d=/sys/kernel/config/bnxt_re/$1 made=0 kv out=""
  shift
  [ -d "$d" ] || { mkdir "$d" || return 1; made=1; }
  if [ $# -gt 0 ]; then
    for kv in "$@"; do [ -w "$d/ports/1/cc/${kv%%=*}" ] && echo -n "${kv#*=}" > "$d/ports/1/cc/${kv%%=*}"; done
    echo -n 0x1 > "$d/ports/1/cc/apply"
  fi
  for k in $BNXT_CC; do [ -r "$d/ports/1/cc/$k" ] && out+=" $k=$(tr -d '\n' < "$d/ports/1/cc/$k")"; done
  [ $made = 1 ] && rmdir "$d"
  echo "${out# }"
}
pause() { ethtool -a "$1" | awk '/^RX:/{r=$2} /^TX:/{t=$2} END{print r, t}'; }

port_status() {
  local dev=$1 nd=$2 drv=$3 pfc pa tos c
  pfc=$(dcb pfc show dev "$nd" prio-pfc | sed 's/^prio-pfc //')
  pa=$(pause "$nd")
  tos=$(cm_tos "$dev")
  if [ "$drv" = mlx5 ]; then
    tr=$(mlnx_qos -i "$nd" | awk -F': ' '/trust/{print $2}')
    c=$(ethtool -S "$nd" | awk '$1 ~ /^(rx|tx)_prio3_(bytes|pause):$/ || $1 == "rx_discards_phy:" {sub(":", "", $1); printf " %s=%s", $1, $2}')
    say "$dev $nd trust=$tr pfc[$pfc] pause=${pa// /\/} tos=$tos$c"
  else
    app=$(dcb app show dev "$nd" | tr '\n' ' ')
    c=$(ethtool -S "$nd" | awk 'tolower($1) ~ /pri3|pfc.*3|cos3/ && $2 != 0 {sub(":", "", $1); printf " %s=%s", $1, $2}')
    say "$dev $nd pfc[$pfc] pause=${pa// /\/} tos=$tos app[${app% }] cc[$(bnxt_cc "$dev")]$c"
  fi
}

save_port() {
  local dev=$1 nd=$2 drv=$3 f=$STATE/$nd
  [ -s "$f.pause" ] && { say "$nd: saved state kept from $(date -r "$f.pause" +%F_%T)"; return 0; }
  mkdir -p "$STATE"
  cm_tos "$dev" > "$f.tos" || return 1
  dcb -j pfc show dev "$nd" > "$f.pfc" || return 1
  if [ "$drv" = mlx5 ]; then
    mlnx_qos -i "$nd" > "$f.mlnx_qos" || return 1
  else
    dcb -j ets show dev "$nd" > "$f.ets" || return 1
    dcb app show dev "$nd" > "$f.app" || return 1
    bnxt_cc "$dev" > "$f.cc" || return 1
    systemctl is-active lldpad > "$f.lldpad" 2>/dev/null || true
  fi
  pause "$nd" > "$f.pause"   # written last: marks a complete save
}

apply_port() {
  local dev=$1 nd=$2 drv=$3
  save_port "$dev" "$nd" "$drv" || { fail "$nd: could not save state, not changed"; return; }
  if [ "$drv" = mlx5 ]; then
    ethtool -A "$nd" rx off tx off 2>/dev/null || [ "$(pause "$nd")" = "off off" ] || fail "$nd: pause off"
    mlnx_qos -i "$nd" --trust dscp --pfc 0,0,0,1,0,0,0,0 > /dev/null || fail "$nd: mlnx_qos"
    [ "$(cm_tos "$dev" $TOS)" = $TOS ] || fail "$nd: rdma_cm tos"
  else
    [ -x "$SETUPCC" ] || { fail "$nd: $SETUPCC missing"; return; }
    bash "$SETUPCC" -d "$dev" -i "$nd" -m 3 -r 3 -s 26 -c 6 -p 48 -u 4 > "$STATE/$nd.setupcc.log" 2>&1 ||
      fail "$nd: bnxt_setupcc.sh rc=$? (see $STATE/$nd.setupcc.log)"
    # setupcc.sh writes DSCP<<2 (104) without ECT; use the same ToS as mlx5
    [ "$(cm_tos "$dev" $TOS)" = $TOS ] || fail "$nd: rdma_cm tos"
  fi
}

revert_port() {
  local dev=$1 nd=$2 drv=$3 f=$STATE/$nd p
  [ -s "$f.pause" ] || { say "$nd: no saved state, nothing to revert"; return; }
  if [ "$drv" = mlx5 ]; then
    tr=$(awk -F': ' '/trust/{print $2}' "$f.mlnx_qos")
    p=$(awk '/^[[:space:]]*enabled/{for (i = 2; i <= 9; i++) printf "%s%s", $i, (i < 9 ? "," : "")}' "$f.mlnx_qos")
    [[ "$tr" =~ ^(pcp|dscp)$ && "$p" =~ ^[01](,[01]){7}$ ]] || { fail "$nd: bad saved mlnx_qos"; return; }
    mlnx_qos -i "$nd" --trust "$tr" --pfc "$p" > /dev/null || fail "$nd: mlnx_qos restore"
  else
    while read -r sel rest; do
      for e in $rest; do dcb app del dev "$nd" "$sel" "$e" 2> /dev/null; done
    done < <(dcb app show dev "$nd")
    while read -r sel rest; do
      [ -n "$rest" ] && dcb app add dev "$nd" "$sel" $rest
    done < "$f.app"
    python3 -I - "$f.ets" "$nd" <<'EOF' || fail "$nd: ets restore"
import json, subprocess, sys
e = json.load(open(sys.argv[1]))
# the device takes only ets_cap traffic classes (bnxt: 3)
cap = int(e.get('ets_cap') or 8)
cmd = ['dcb', 'ets', 'set', 'dev', sys.argv[2]]
for key, arg, n in (('tc_tsa', 'tc-tsa', cap), ('tc_bw', 'tc-bw', cap), ('prio_tc', 'prio-tc', 8)):
    v = e.get(key)
    if isinstance(v, list) and v:
        cmd += [arg] + ['%d:%s' % (i, x) for i, x in enumerate(v[:n])]
sys.exit(subprocess.call(cmd) if len(cmd) > 5 else 0)
EOF
    bnxt_cc "$dev" $(cat "$f.cc") > /dev/null || fail "$nd: bnxt_re cc restore"
    [ "$(cat "$f.lldpad" 2>/dev/null)" = active ] && systemctl start lldpad
  fi
  p=$(python3 -I -c 'import json, sys; e = json.load(open(sys.argv[1])); v = e.get("prio_pfc", {}); print(" ".join("%s:%s" % (k, "on" if x else "off") for k, x in (v.items() if isinstance(v, dict) else enumerate(v))))' "$f.pfc")
  [ -n "$p" ] && { dcb pfc set dev "$nd" prio-pfc $p || fail "$nd: pfc restore"; }
  read -r prx ptx < "$f.pause"
  ethtool -A "$nd" rx "$prx" tx "$ptx" 2>/dev/null || [ "$(pause "$nd")" = "$prx $ptx" ] || fail "$nd: pause restore"
  [ "$(cm_tos "$dev" "$(cat "$f.tos")")" = "$(cat "$f.tos")" ] || fail "$nd: rdma_cm tos restore"
  [ $rc = 0 ] && rm -f "$f".*
}

# install: make apply persistent. Copies this script to $BIN, adds the
# roce-qos.service oneshot (after network-online, before daos_server and
# daos_agent) and enables it, and turns off ethtool.pause-rx/tx in the
# NetworkManager profile of every RDMA port that sets them (old values in
# $STATE/<netdev>.nm; the live link is not re-applied). uninstall undoes it.
BIN=/usr/local/sbin/roce-qos-node.sh
UNIT=/etc/systemd/system/roce-qos.service
if [ "$MODE" = install ] || [ "$MODE" = uninstall ]
then
  for d in /sys/class/infiniband/*
  do
    nd=$(ls "$d/device/net" | head -1)
    c=$(nmcli -g GENERAL.CONNECTION device show "$nd" 2> /dev/null)
    [ -n "$c" ] || continue
    if [ "$MODE" = install ]; then
      cur=$(nmcli -g ethtool.pause-rx,ethtool.pause-tx connection show "$c" | paste -sd' ')
      if [[ "$cur" == *on* ]]; then
        mkdir -p "$STATE"
        [ -s "$STATE/$nd.nm" ] || echo "$c|$cur" > "$STATE/$nd.nm"
        nmcli connection modify "$c" ethtool.pause-rx off ethtool.pause-tx off || fail "$nd: nmcli modify"
      fi
    elif [ -s "$STATE/$nd.nm" ]; then
      IFS='|' read -r c cur < "$STATE/$nd.nm"
      read -r rx tx <<< "$cur"
      nmcli connection modify "$c" ethtool.pause-rx "${rx:-}" ethtool.pause-tx "${tx:-}" && rm -f "$STATE/$nd.nm" ||
        fail "$nd: nmcli restore"
    fi
    say "$nd nm[$c] pause=$(nmcli -g ethtool.pause-rx,ethtool.pause-tx connection show "$c" | paste -sd/)"
  done
  if [ "$MODE" = install ]; then
    install -m 0755 "$0" "$BIN" || fail "copy to $BIN"
    cat > "$UNIT" << EOF
[Unit]
Description=RoCE lossless class (DSCP 26 / PFC prio 3) to match the switch
Wants=network-online.target
After=network-online.target NetworkManager-wait-online.service
Before=daos_server.service daos_agent.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$BIN apply

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable roce-qos.service 2>&1 | grep -v "^Created" || true
  else
    systemctl disable roce-qos.service 2> /dev/null
    rm -f "$UNIT" "$BIN"
    systemctl daemon-reload
  fi
  say "roce-qos.service $(systemctl is-enabled roce-qos.service 2> /dev/null || echo absent)"
  exit $rc
fi

for d in /sys/class/infiniband/*
do
  dev=$(basename "$d")
  nd=$(ls "$d/device/net" | head -1)
  case "$dev" in mlx5_*) drv=mlx5 ;; bnxt_re*) drv=bnxt ;; *) say "$dev: unknown driver, skipped"; continue ;; esac
  case "$MODE" in
    status) ;;
    apply) apply_port "$dev" "$nd" "$drv" ;;
    revert) revert_port "$dev" "$nd" "$drv" ;;
    *) echo "usage: $0 status|apply|revert" >&2; exit 2 ;;
  esac
  port_status "$dev" "$nd" "$drv"
done
exit $rc
