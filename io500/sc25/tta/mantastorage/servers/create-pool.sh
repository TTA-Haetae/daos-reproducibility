#!/bin/bash

D_POOL="$1"
D_SIZE="$2"
D_RATIO="$3"

for i in $(seq 1 4);
do
    NODE_NAME="$(printf "MantaStorage-%02d" "${i}")"

    ssh "$NODE_NAME" "systemctl stop daos_server";
    ssh "$NODE_NAME" "rm -rf /var/daos/control_meta/daos_control";
    ssh "$NODE_NAME" "rm -rf /mnt/daos/*/*";
    ssh "$NODE_NAME" "umount /mnt/daos/*";
    ssh "$NODE_NAME" "systemctl start daos_server";
done

dmg storage format

sleep 60;

echo "dmg pool create --size=$D_SIZE --mem-ratio=$D_RATIO $D_POOL"
dmg pool create --size="$D_SIZE" --mem-ratio="$D_RATIO" "$D_POOL"
