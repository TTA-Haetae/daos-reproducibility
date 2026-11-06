# IO500-SC26 - TTA - MantaStorage

Reproducibility information for benchmarks submitted to the IO500-SC26
[10-Node Production](https://io500.org/list/sc26/ten-production) list and
[10-Node Research](https://io500.org/list/sc26/ten) list.

General information on building and running the IO500 benchmarks with DAOS can
be found in the [DAOS Community Wiki](https://daosio.atlassian.net/wiki/spaces/DC/pages/11167301633/IO-500+SC22)
page on IO500.

## IO500.org Reproducibility Questionnaire

Answers to the _IO500.org Reproducibility Questionnaire_ are provided in the
[io500-reproducibility.tta-mantastorage.md](io500-reproducibility.tta-mantastorage.md)
document. Note that this document covers two different _user-selectable_ data
protection schemes to address the different requirements of the _Production_
and _Research_ lists.

## Institution

[TTA](https://tta.or.kr)

MantaStorage is the DAOS storage system of Haetae, an AI research
supercomputer operated by TTA (Telecommunications Technology Association,
Seongnam-si, Republic of Korea). The system was originally built in 2025 for a
national R&D project; TTA has since extended its use to the AI research of
other research institutions, universities and companies (ETRI, KETI, KISTI,
SKKU, POSTECH, Seoul National University, Sogang University and Mobigen). MantaStorage is not a commercial product: it is a DAOS deployment
on off-the-shelf servers that [Gluesys](https://www.gluesys.com) configured
for TTA and maintains. It is the same installation that was
listed at SC25 (see [../../../sc25/tta/mantastorage](../../../sc25/tta/mantastorage))
with the client system named "ESC8000-E11" after its server model: for SC26
the client system is named "Haetae", the storage system keeps the name
"MantaStorage", and the installation was expanded from 4 to 6 DAOS servers and
from 7 to 10 compute nodes, upgraded to DAOS 2.8.1 on Rocky Linux 10, and moved
from InfiniBand HDR to 400GbE RoCE v2. TTA plans to expand the system
gradually as the institutions' needs grow; the 10 compute nodes and 6 storage
servers described here are its size at the time of the SC26 runs.

## Storage System

MantaStorage consists of 6 servers (2x [AIC SB201-SU](https://www.aicipc.com/en/productdetail/51570)
and 4x [Supermicro SYS-222C-TN](https://www.supermicro.com/en/products/system/gpu/2u/sys-222c-tn)),
running DAOS 2.8.1 on Rocky Linux 10.2.

All servers have 2 CPU sockets, 1 TiB of DDR5 memory (16x 64GiB) and two
single-port NVIDIA ConnectX-7 400GbE adapters (MCX75310AAS-NEAT, one per CPU
socket). Each server runs two DAOS engines, one per CPU socket, and each engine
uses the NVMe SSDs and the network adapter attached to its own socket (16
targets and 4 helper threads per engine).

| Server | Model | CPU | RAM | DAOS NVMe (socket 0 / socket 1) |
|---|---|---|---|---|
| MantaStorage-01 | AIC SB201-SU | 2x Intel Xeon 6530P (32C) | 16x 64GiB DDR5-5600 | 8 / 8x Samsung PM9A3 3.84TB U.2 NVMe SSD (PCIe Gen4) |
| MantaStorage-02 | AIC SB201-SU | 2x Intel Xeon 6530P (32C) | 16x 64GiB DDR5-4800 | 8 / 8x Phison Pascari X200P 3.84TB U.2 NVMe SSD (PCIe Gen5) |
| MantaStorage-03 | Supermicro SYS-222C-TN | 2x Intel Xeon 6520P (24C) | 16x 64GiB DDR5-4800 | 4 / 4x Seagate Nytro 5360H (XP7680SE70006) 7.68TB U.2 NVMe SSD (PCIe Gen5) |
| MantaStorage-04 | Supermicro SYS-222C-TN | 2x Intel Xeon 6520P (24C) | 16x 64GiB DDR5-4800 | 4x Seagate Nytro 5360H 7.68TB / 8x DapuStor Roealsen R5100 7.68TB U.2 NVMe SSD (PCIe Gen4) |
| MantaStorage-05 | Supermicro SYS-222C-TN | 2x Intel Xeon 6530P (32C) | 16x 64GiB DDR5-4800 | 4x Seagate Nytro 5360H 7.68TB / 8x Phison Pascari X200P 3.84TB U.2 NVMe SSD |
| MantaStorage-06 | Supermicro SYS-222C-TN | 2x Intel Xeon 6530P (32C) | 16x 64GiB DDR5-4800 | 4 / 4x Seagate Nytro 5360H 7.68TB U.2 NVMe SSD |

All 72 NVMe drives are used by DAOS in MD-on-SSD mode (bdev roles
`data,meta,wal`, 300 GiB tmpfs memory file per engine, `mem-ratio` 100%). The
24 Seagate drives use their full 7.68 TB capacity (4 KiB LBA); the DapuStor
namespaces are 5.63 TB. The
single pool spans all 192 targets and has 363 TB (330 TiB). Each engine
distributes its 16 targets evenly over its 4 or 8 drives. The drives were
formatted (`nvme format --ses=1`) and the pool and container were created
fresh before every submitted run.

DAOS storage software references:

* DAOS [github repository](https://github.com/daos-stack/daos)
  (release [v2.8.1](https://github.com/daos-stack/daos/releases/tag/v2.8.1))
* DAOS [packages repository](https://packages.daos.io)
* DAOS [documentation](https://docs.daos.io/)
* [SC-Asia 2020 paper](https://doi.org/10.1007/978-3-030-48842-0_3)
  _DAOS: A Scale-Out High Performance Storage Stack for Storage Class Memory_
* [SC-Asia 2023 paper](https://doi.org/10.1145/3581576.3581577)
  _Understanding DAOS Storage Performance Scalability_

## Compute Nodes (DAOS clients)

The 10 compute nodes of Haetae access MantaStorage as DAOS clients and run
DAOS 2.8.1 on Rocky Linux 10.2 (same kernel as the servers) with Open MPI
5.0.9 (`openmpi-5.0.9-2.el10_2`). All compute nodes have 2x Intel Xeon Platinum 8558 CPUs (48 cores per socket, hyper-threading
on, 192 hardware threads) and an NVIDIA ConnectX-7 400GbE adapter on socket 0.
The second network rail on socket 1 differs between the nodes:

| Node | Model | RAM | Socket 0 NIC | Socket 1 NIC(s) |
|---|---|---|---|---|
| Haetae-01, Haetae-02 | ASUS ESC8000-E11 | 16x 64GiB DDR5-4800 | ConnectX-7 400GbE (MCX75310AAS-NEAT) | Broadcom BCM57608 400GbE |
| Haetae-03 | ASUS ESC8000-E11 | 16x 64GiB DDR5-4800 | ConnectX-7 400GbE | 2x ConnectX-6 200GbE (MCX653105A-HDAT) |
| Haetae-04 | ASUS ESC8000-E11 | 8x 64GiB DDR5-4800 | ConnectX-7 400GbE | 2x ConnectX-6 200GbE (MCX653105A-HDAT) |
| Haetae-05 to Haetae-08 | ASUS ESC8000-E11 | 8x 64GiB DDR5-4800 | ConnectX-7 400GbE | ConnectX-6 200GbE (MCX653105A-HDAT) |
| Haetae-09, Haetae-10 | KTNF KH590S3 | 8x 32GiB DDR5-5600 | ConnectX-7 400GbE | ConnectX-6 200GbE (MCX653105A-HDAT) |

Sub-NUMA clustering is disabled in the BIOS of all compute nodes, so each node has
two NUMA nodes (one per socket). Each run used 144 MPI ranks per node (1,440
in total), one per hardware thread, pinned by
[io500-daos/rail-bind.sh](io500-daos/rail-bind.sh) so that each NUMA node's
ranks use the NIC on that node (96:48 ranks on nodes with a 400+200GbE pair,
72:72 on Haetae-03 and Haetae-04 whose second rail has 2x 200GbE).

## High-Performance Fabric

The storage fabric is a 400GbE Ethernet network with RoCE v2. Servers and
clients are in one IPv4 subnet (MTU 9000). All servers and clients are
attached to a single NVIDIA Spectrum-3
[SN4700](https://docs.nvidia.com/networking/display/sn4000/introduction)
switch (MSN4700-WS2FC, 32x 400GbE, Cumulus Linux 5.14.0). Each of the 12
server network ports is connected to its own 400GbE switch port, without
breakout cables; the 400GbE client adapters also use one switch port each, and
the 200GbE ConnectX-6 client adapters are attached with breakout cables.

The switch runs the RoCE lossless profile (`nv set qos roce enable on`: PFC on
priority 3, DSCP 26 mapped to priority 3, CNP DSCP 48 to priority 6, ECN on),
and the hosts are configured to match by
[servers/roce-qos-node.sh](servers/roce-qos-node.sh) (installed as the
`roce-qos.service` systemd unit on all 16 nodes): PFC priority 3, DSCP trust,
global pause off, RoCE ToS 106 (DSCP 26).

On the servers, each network port is used by the `daos_engine` running on the
same CPU socket. On the clients, the DAOS agent selects the network interface
from the NUMA node of each MPI rank (`fabric_ifaces` in `daos_agent.yml`).
DAOS uses the `ofi+verbs;ofi_rxm` provider (libfabric 2.6.0) on every rail.
MPI uses UCX (`dc_x`) on the same data network, and a separate 1GbE
management network only for the Open MPI runtime (PRRTE) out-of-band channel.

## Execution Environment

All servers and clients were installed with the following software stack
(the exact package lists are in `servers/MantaStorage-NN/packages.txt` and
`clients/Haetae-NN/packages.txt`):

- Rocky Linux 10.2 (kernel `6.12.0-211.16.1.el10_2.0.1.x86_64`)
- NVIDIA DOCA-OFED 26.04 (`OFED-internal-26.04-0.8.6`; rdma-core 2604.0.7, UCX 1.21.0);
  ConnectX-7 firmware 28.43.3608 on the servers and most compute nodes (the
  per-node versions are in `clients/Haetae-NN/hardware.txt`)
- [DAOS v2.8.1](https://github.com/daos-stack/daos/releases/tag/v2.8.1), unmodified
- libfabric 2.6.0 (unmodified upstream v2.6.0), Mercury 2.4.1
- Open MPI 5.0.9 (Rocky Linux 10 package `openmpi-5.0.9-2.el10_2`) on the clients
- IO500 [io500-sc26_v4](https://github.com/IO500/io500/tree/io500-sc26_v4)
  with the DFS-native `pfind`
  ([mchaarawi/pfind](https://github.com/mchaarawi/pfind) `b86a4a010559`) and
  the two pfind patches in [pfind/](pfind/), built with
  [io500-daos/build.sh](io500-daos/build.sh)
  (resulting [prepare.sh](io500/prepare.sh), [diff](io500/prepare.sh.diff))

System tuning applied on servers and clients by
[servers/sys-tune-node.sh](servers/sys-tune-node.sh) (persisted as
`etc/sysctl.d/90-hpc-tuning.conf` and kernel arguments, see `proc-cmdline.txt`):
`kernel.numa_balancing=0`, `kernel.nmi_watchdog=0`, CPU idle states limited to
C1 (`intel_idle.max_cstate=1 processor.max_cstate=1`), transparent hugepages
`madvise` on clients / `never` on servers, tuned profile
`throughput-performance`, and the ConnectX-7 firmware settings
`ADVANCED_PCI_SETTINGS=1 PCI_WR_ORDERING=force_relax CQE_COMPRESSION=aggressive`
(`servers/MantaStorage-NN/mstconfig.txt`). The common part of
`etc/sysctl.d/99-daos-net.conf` (socket buffers, neighbour table, BBR/fq) is
identical on all 16 nodes; `99-daos-multirail.conf`
(clients) and the per-interface part of `99-daos-net.conf` (servers) set
`arp_ignore/arp_announce/rp_filter/accept_local` for the two rails on one
subnet, and `99-mpi-ports.conf` widens the local port range for Open MPI.
Source-based policy routing keeps the traffic of each rail on its own port:
every RDMA port has its own routing table (100, 101 and, on Haetae-03/04, 102)
and an `ip rule` `from <port address> lookup <table>`, both set in the
NetworkManager profile of the port (`ipv4.routes`, `ipv4.routing-rules`); see
`servers/MantaStorage-NN/routing.txt` and `clients/Haetae-NN/routing.txt`.

### DAOS Server configuration

- `/etc/daos/daos_server.yml`:
  [MantaStorage-01](servers/MantaStorage-01/etc/daos/daos_server.yml),
  [02](servers/MantaStorage-02/etc/daos/daos_server.yml),
  [03](servers/MantaStorage-03/etc/daos/daos_server.yml),
  [04](servers/MantaStorage-04/etc/daos/daos_server.yml),
  [05](servers/MantaStorage-05/etc/daos/daos_server.yml),
  [06](servers/MantaStorage-06/etc/daos/daos_server.yml)
- [/etc/daos/daos_control.yml](servers/MantaStorage-01/etc/daos/daos_control.yml)
- `/etc/sysctl.d/`: [MantaStorage-01](servers/MantaStorage-01/etc/sysctl.d/)
  (the other servers differ only in the interface names)
- engine environment as started (`engine-env.txt`)

Each engine has 16 targets and 4 helper threads, and keeps its metadata in a
300 GiB RAM-backed SCM region with the metadata-on-SSD feature
(`control_metadata`). For the IO500 benchmarks one storage pool `haetae` was
created that spans all 6 servers (12 engines, 192 targets; 100% of the NVMe
capacity, `data_thresh` 2048, `svc_rf` 2), and one DAOS POSIX container per
list was created in that pool, using the
[make-pool-cont.sh](io500-daos/make-pool-cont.sh) script:

```
DAOS_POOL=haetae make-pool-cont.sh pool                                        # on a server: dmg pool create --size=100% --properties=data_thresh:2048
PROFILE=prod     DAOS_POOL=haetae DAOS_CONT=haetae-production make-pool-cont.sh cont   # rd_fac:1, rd_lvl:node, compression and dedup off
PROFILE=research DAOS_POOL=haetae DAOS_CONT=haetae-research   make-pool-cont.sh cont   # rd_fac:0
```

The resulting pool and container properties are recorded in
[servers/pool-cont-production.txt](servers/pool-cont-production.txt) and
[servers/pool-cont-research.txt](servers/pool-cont-research.txt). Before
each submitted run the drives were formatted with
[servers/nvme-format.sh](servers/nvme-format.sh) and the pool was recreated.

### DAOS Client environment

- `/etc/daos/daos_agent.yml`: [Haetae-01](clients/Haetae-01/etc/daos/daos_agent.yml)
  to [Haetae-10](clients/Haetae-10/etc/daos/daos_agent.yml)
  (`fabric_ifaces` lists both rails with their NUMA node)
- `/etc/sysctl.d/`: [Haetae-01](clients/Haetae-01/etc/sysctl.d/) to
  [Haetae-10](clients/Haetae-10/etc/sysctl.d/)

Haetae has no batch scheduler; jobs are started with `mpirun` over a
hostfile, and the IO500 runs were started the same way from Haetae-01 with
[io500-daos/run-io500.sh](io500-daos/run-io500.sh) (the io500.sh of
io500-sc26 with the DAOS-specific part above the "SHOULD NOT EDIT" line) and
the client list in [io500-daos/clients/hosts](io500-daos/clients/hosts):

```
STONEWALL=300 PPN=144 BIND=hwthread RAIL_SPLIT=node DAOS_POOL=haetae DAOS_CONT=haetae-production \
    ./run-io500.sh config-prod-tmpl.ini
STONEWALL=300 PPN=144 BIND=hwthread RAIL_SPLIT=node DAOS_POOL=haetae DAOS_CONT=haetae-research \
    ./run-io500.sh config-research-tmpl.ini
```

The exact `mpirun` command lines and the DAOS/libfabric environment of the
two submitted runs are in [io500-daos/mpirun-production.txt](io500-daos/mpirun-production.txt),
[io500-daos/mpirun-research.txt](io500-daos/mpirun-research.txt),
[io500-daos/env-production.txt](io500-daos/env-production.txt) and
[io500-daos/env-research.txt](io500-daos/env-research.txt). The launcher and
the rendered ini are also included in each IO500 result tarball. Both
submitted runs ended with an MPI abort in the IOR DFS backend's finalize step
after all phases and `result.txt` were written, which ends the launcher
before its `create_tarball` step; each result directory was therefore
packaged with [io500-daos/package-result.sh](io500-daos/package-result.sh),
which checks the launcher log, performs the same steps and adds the launcher
log, its exit status and `packaged-by.txt` to the tarball.

The rules for the IO500 Production lists require that the storage system has
no single point of failure, so the Production run used
[io500/config-prod.ini](io500/config-prod.ini) (rendered from
[config-prod-tmpl.ini](io500-daos/config-prod-tmpl.ini)) in a container with
`rd_fac:1` and `rd_lvl:node`: 2-way replication for metadata and IOR-Hard
(`RP_2GX` / `RP_2G1`) and 4+1P erasure coding for IOR-Easy (`EC_4P1GX`), which
protects against the loss of one server. The Research run used the identical
storage system with [io500/config-research.ini](io500/config-research.ini)
(from [config-research-tmpl.ini](io500-daos/config-research-tmpl.ini)):
sharding/striping without data protection (`SX` / `S1`) to maximize the
achievable performance.

### IO500 build

io500 was built from the official `io500-sc26_v4` tag with
[io500-daos/build.sh](io500-daos/build.sh), [io500/prepare.sh](io500/prepare.sh)
and [io500/Makefile](io500/Makefile) / [io500/local.mk](io500/local.mk) (DAOS
DFS backend). IOR and mdtest are the unmodified upstream commits fetched by
`prepare.sh`; the only change in the io500 tree is that `prepare.sh` fetches
the DFS-aware pfind fork (https://github.com/mchaarawi/pfind, commit b86a4a0)
instead of the VI4IO pfind ([diff](io500/prepare.sh.diff)). The state of the
build tree of each submitted run (git status, diff and binary checksums) is in
[io500/build-tree-production.txt](io500/build-tree-production.txt) and
[io500/build-tree-research.txt](io500/build-tree-research.txt).

The pfind fork was built with the two patches in [pfind/](pfind/) (applied in
order on top of b86a4a0). The pfind build tree used for the submitted runs,
with the patched sources and the build outputs, is
[pfind/pfind-src.tgz](pfind/pfind-src.tgz):

1. [0001-queue-unknown-entries-for-chunked-stealing.patch](pfind/0001-queue-unknown-entries-for-chunked-stealing.patch):
   entries of unknown type are queued as work items so that idle ranks can
   steal them in chunks instead of being stat'ed inline by the few ranks that
   hold the directory splits.
2. [0002-lookup-first-stat-only-name-matches.patch](pfind/0002-lookup-first-stat-only-name-matches.patch):
   an entry is looked up first (one RPC) and only files whose name matches
   `-name` get the full stat, so directories and non-matching files cost one
   RPC instead of two.

The input/output behaviour of pfind is unchanged (same `found`/`total`
counts as the original pfind, verified on a mock tree and by an independent
file count on every run).

## IO500 List Entries

<!-- TODO(SC26): fill in the ranks and submission IDs after submission. -->

- MantaStorage (Haetae): SC26 10-Node Production List, submission TBD
- MantaStorage (Haetae): SC26 10-Node Research List, submission TBD
