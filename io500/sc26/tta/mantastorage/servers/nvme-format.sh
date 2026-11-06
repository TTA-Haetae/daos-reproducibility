#!/bin/bash
# Run as root on one DAOS server with daos_server stopped:
#   nvme-format.sh <outdir> <pci>=<serial> [<pci>=<serial> ...]
# For each drive, in order:
#   0 refuse unless the PCI address is in a bdev_list of daos_server.yml
#     (never the OS disk)
#   1 move it from vfio-pci to the kernel nvme driver
#   2 refuse (and skip the rest) unless the model is one of the four DAOS data
#     models and the serial matches the expected one, and no block device of
#     the controller is mounted, swapped on or held (holders/)
#   2b save capacity (tnvmcap, unvmcap, nn; nsze, ncap, nvmcap, lbaf) to
#     capacity.txt for the over-provisioning check
#   3 save smart-log, error-log, id-ctrl, id-ns; refuse to format if
#     critical_warning != 0, media_errors > 0 or percentage_used >= 90
#   4 nvme format --ses=1 keeping the LBA format in use (LBAF_SAMSUNG=<n> in the
#     environment forces that format for the Samsung model, e.g. 1 = 4 KiB)
#   5 save smart-log again, hand the drive back (driver_override cleared,
#     unbound from nvme; daos_server rebinds it to vfio-pci at start)
# Prints one result line per drive: OK, SKIP <reason> or FAIL <reason>.
set -u
out="$1"; shift
mkdir -p "$out" || exit 1

if pgrep -x daos_engine > /dev/null || systemctl is-active -q daos_server
then
  echo "daos_server/daos_engine still running; stop them first" >&2
  exit 1
fi

MODELS="XP7680SE70006|SAMSUNG MZQL23T8HCLS-00A07|PASCARI XX208H023T84P324T0910|DAPUSTOR DPRD3108T0T507T6000"
BDEVS=$(tr -d ' "' < /etc/daos/daos_server.yml | grep -oE '[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-9a-f]' | sort -u)

give_back() {
  local b="$1"
  echo > "/sys/bus/pci/devices/$b/driver_override"
  [ -e "/sys/bus/pci/drivers/nvme/$b" ] && echo "$b" > /sys/bus/pci/drivers/nvme/unbind
}

for pair in "$@"
do
  b="${pair%%=*}"; want="${pair#*=}"
  if ! grep -qx "$b" <<< "$BDEVS"
  then
    echo "$b SKIP not in daos_server.yml bdev_list, not touched"; continue
  fi
  drv=none; [ -e "/sys/bus/pci/devices/$b/driver" ] && drv=$(basename "$(readlink -f "/sys/bus/pci/devices/$b/driver")")
  if [ "$drv" = vfio-pci ] || [ "$drv" = none ]
  then
    echo nvme > "/sys/bus/pci/devices/$b/driver_override"
    [ "$drv" = vfio-pci ] && echo "$b" > /sys/bus/pci/drivers/vfio-pci/unbind
    echo "$b" > /sys/bus/pci/drivers_probe
  elif [ "$drv" != nvme ]
  then
    echo "$b FAIL driver is '$drv' (expected vfio-pci or none)"; continue
  fi

  c=""
  for i in $(seq 1 20)
  do
    c=$(ls "/sys/bus/pci/devices/$b/nvme" 2> /dev/null | head -1)
    [ -n "$c" ] && [ -b "/dev/${c}n1" ] && break
    sleep 1
  done
  if [ -z "$c" ] || [ ! -b "/dev/${c}n1" ]
  then
    echo "$b FAIL no nvme controller/namespace after rebinding"; give_back "$b"; continue
  fi

  sn=$(nvme id-ctrl "/dev/$c" | awk -F' : ' '$1 ~ /^sn +$/ {gsub(/ +$/, "", $2); print $2}')
  mn=$(nvme id-ctrl "/dev/$c" | awk -F' : ' '$1 ~ /^mn +$/ {gsub(/ +$/, "", $2); print $2}')
  if ! [[ "$mn" =~ ^($MODELS)$ ]] || [ "$sn" != "$want" ]
  then
    echo "$b SKIP model '$mn' serial '$sn' (expected $want), not formatted"
    give_back "$b"; continue
  fi
  busy=""
  for blk in /sys/bus/pci/devices/$b/nvme/$c/${c}n*
  do
    n=$(basename "$blk")
    findmnt -rno SOURCE | grep -q "^/dev/$n" && busy+=" $n:mounted"
    grep -q "^/dev/$n" /proc/swaps && busy+=" $n:swap"
    [ -n "$(ls "/sys/block/$n/holders" 2> /dev/null)" ] && busy+=" $n:held"
    for part in /sys/block/$n/${n}p*; do [ -e "$part" ] && [ -n "$(ls "$part/holders" 2> /dev/null)" ] && busy+=" $(basename "$part"):held"; done
  done
  if [ -n "$busy" ]
  then
    echo "$b SKIP $sn in use by the OS:$busy, not formatted"; give_back "$b"; continue
  fi
  {
    echo "$b $sn $mn"
    nvme id-ctrl "/dev/$c" | grep -E '^(tnvmcap|unvmcap|nn) '
    nvme id-ns "/dev/${c}n1" | grep -E '^(nsze|ncap|nuse|nvmcap) |in use'
  } >> "$out/capacity.txt"

  nvme smart-log "/dev/$c" > "$out/smart-before-$sn.txt"
  nvme error-log "/dev/$c" -e 64 > "$out/errlog-$sn.txt"
  nvme id-ctrl "/dev/$c" > "$out/id-ctrl-$sn.txt"
  nvme id-ns "/dev/${c}n1" > "$out/id-ns-$sn.txt"

  cw=$(awk -F: '/^critical_warning/ {gsub(/ /, "", $2); print $2}' "$out/smart-before-$sn.txt")
  me=$(awk -F: '/^media_errors/ {gsub(/[ ,]/, "", $2); print $2}' "$out/smart-before-$sn.txt")
  pu=$(awk -F: '/^percentage_used/ {gsub(/[ %]/, "", $2); print $2}' "$out/smart-before-$sn.txt")
  if [ "${cw:-1}" != 0 ] || [ "${me:-1}" != 0 ] || [ "${pu:-100}" -ge 90 ]
  then
    echo "$b SKIP $sn health critical_warning=$cw media_errors=$me percentage_used=$pu, not formatted"
    give_back "$b"; continue
  fi

  lbaf=$(nvme id-ns "/dev/${c}n1" | awk '/in use/ {sub("lbaf", "", $1); print $2 + 0; exit}')
  # LBAF_SAMSUNG=<n> (env) overrides the LBA format for the Samsung model only
  # (used to unify the ten 512 B drives on MantaStorage-01 to 4 KiB = lbaf 1)
  if [ -n "${LBAF_SAMSUNG:-}" ] && [[ "$mn" == SAMSUNG* ]]
  then
    nvme id-ns "/dev/${c}n1" | grep -qE "^lbaf +${LBAF_SAMSUNG} " || { echo "$b SKIP $sn has no lbaf ${LBAF_SAMSUNG}"; give_back "$b"; continue; }
    lbaf=$LBAF_SAMSUNG
  fi
  t0=$(date +%s)
  if ! nvme format "/dev/${c}n1" --ses=1 --lbaf="${lbaf:-0}" --force > "$out/format-$sn.txt" 2>&1
  then
    echo "$b FAIL $sn nvme format failed (see format-$sn.txt)"; give_back "$b"; continue
  fi
  nvme smart-log "/dev/$c" > "$out/smart-after-$sn.txt"
  give_back "$b"
  echo "$b OK $sn lbaf=$lbaf format=$(( $(date +%s) - t0 ))s"
done
