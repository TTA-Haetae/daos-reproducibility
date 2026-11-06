#!/bin/bash

D_POOL="$1"
D_CONT="$2"
D_RF="$3"

echo "daos container create --type=POSIX $D_POOL --properties=rd_fac:${D_RF},compression:off,dedup:off $D_CONT"
daos container destroy "$D_POOL" "$D_CONT" --force

for i in $(seq 1 4);
do
    NODE_NAME="$(printf "MantaStorage-%02d" "${i}")"

    ssh "$NODE_NAME" "systemctl stop daos_agent";
    ssh "$NODE_NAME" "systemctl start daos_agent";
done

echo "daos container create --type=POSIX $D_POOL --properties=rd_fac:${D_RF},compression:off,dedup:off $D_CONT"
daos container create --type=POSIX "$D_POOL" --properties="rd_fac:${D_RF},compression:off,dedup:off" "$D_CONT"
