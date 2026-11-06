#!/bin/bash
#
# Build io500 (tag io500-sc26_v4) against DAOS, with the DFS-native pfind.
#
#   MY_DAOS_INSTALL_PATH=/usr ./build.sh        # DAOS from RPMs (default)
#   MY_DAOS_INSTALL_PATH=$HOME/install/daos ./build.sh
#
# MY_DAOS_INSTALL_PATH is the name pfind's compile.sh reads. Do not use
# DAOS_PREFIX for this: pfind treats DAOS_PREFIX as a DFS path prefix.

set -euo pipefail

KIT_DIR="$(cd "$(dirname "$0")" && pwd)"
IO500_DIR="${IO500_DIR:-$KIT_DIR/../io500}"
IO500_TAG="io500-sc26_v4"

# mchaarawi/pfind branch dfs_find, pinned (the branch can move)
PFIND_URL="https://github.com/mchaarawi/pfind.git"
PFIND_HASH="b86a4a010559"

export MY_DAOS_INSTALL_PATH="${MY_DAOS_INSTALL_PATH:-/usr}"

if [ ! -f "$MY_DAOS_INSTALL_PATH/include/daos.h" ]
then
  echo "error: $MY_DAOS_INSTALL_PATH/include/daos.h not found (install daos-devel?)"
  exit 1
fi

if ! command -v mpicc > /dev/null
then
  echo "error: mpicc not in PATH (module load mpi/mpich-x86_64 ?)"
  exit 1
fi

cd "$IO500_DIR"
git checkout --quiet -- prepare.sh
git fetch --quiet origin tag "$IO500_TAG"
git checkout --quiet "$IO500_TAG"

# A build/pfind left by a plain ./prepare.sh is the VI4IO clone; prepare.sh
# would reuse it and fail to check out the dfs_find commit.
if [ -d build/pfind ] && ! git -C build/pfind remote get-url origin | grep -q mchaarawi
then
  rm -rf build/pfind
fi

# pfind's own prepare.sh clones lz4 HEAD, and lz4 >= 1.10 no longer leaves
# lib/*.o where pfind's compile.sh links them from. Pre-fetch pfind and pin
# lz4 to v1.9.4; io500's prepare.sh then reuses both.
if [ ! -d build/pfind ]
then
  mkdir -p build
  git clone --quiet "$PFIND_URL" build/pfind
  git -C build/pfind checkout --quiet "$PFIND_HASH"
fi

if [ ! -f build/pfind/lz4/lib/lz4.o ]
then
  rm -rf build/pfind/lz4
  git clone --quiet --depth 1 --branch v1.9.4 https://github.com/lz4/lz4.git build/pfind/lz4
  make -C build/pfind/lz4/lib -j > /dev/null
fi

# The only change to upstream prepare.sh: swap in the DFS pfind.
# Same edit as the DAOS community IO500 instructions; must be documented
# in the submission (IO500 rule: non-default find needs its source included).
sed -i -e "s|^PFIND_HASH=.*|PFIND_HASH=$PFIND_HASH|" \
       -e "s|https://github.com/VI4IO/pfind.git|$PFIND_URL|" \
       prepare.sh

IOR_EXTRA_CONFIGURE_FLAGS="--with-daos=$MY_DAOS_INSTALL_PATH" \
IO500_EXTRA_CFLAGS="-I$MY_DAOS_INSTALL_PATH/include" \
IO500_EXTRA_LDFLAGS="-L$MY_DAOS_INSTALL_PATH/lib64 -ldaos -ldaos_common -ldfs -lgurt -luuid" \
./prepare.sh

# ior must actually have the DFS backend, or every phase fails at runtime
if ! ldd ./bin/ior | grep -q libdfs
then
  echo "error: ior built without DFS"
  exit 1
fi

git -C build/pfind log -1 --format='pfind: %h %s'
echo "OK: $IO500_DIR/io500"
