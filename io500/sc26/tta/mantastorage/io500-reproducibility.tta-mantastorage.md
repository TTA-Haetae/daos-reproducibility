# IO500 Reproducibility - SC26 - TTA - MantaStorage

> The goal of these questions are to demonstrate that your IO500 benchmark execution is valid, can be
> reproduced, and provide additional details of your submitted storage system. Along with the other
> submitted items, the answers to these questions are used to calculate your reproducibility score and
> whether the submission is eligible for the Production or Research list.

## System Purpose

> Please describe the purpose and general usage of the submitted system. This would include the
> types of typical applications it supports (e.g., defense applications, molecular dynamics,
> benchmarking, system test, systems research), the general use and purpose of the data generated
> by the applications running on it.

MantaStorage is the DAOS storage system of Haetae, an AI research supercomputer owned and operated by TTA (Telecommunications Technology Association) in Bundang-gu, Seongnam-si, Republic of Korea. Haetae was originally built for a national R&D project. TTA has since extended its use to the AI research of other research institutions, universities and companies, which run their AI workloads on it:

* ETRI: training and inference of large AI models, e.g. vision-language models (LLaVA-Video), vision transformers and graph neural networks.
* KETI: data collection and pre-processing for large-model training, training of multimodal generative models, and container orchestration of AI training jobs.
* KISTI: training of deep-learning models.
* SKKU: AI model training with large training datasets.
* POSTECH: training and inference of multimodal models.
* Seoul National University: large-language-model inference serving.
* Sogang University: GPU-accelerated AI applications (training and inference).
* Mobigen (company): AI-based extraction of metadata from multimodal data (text, images, video and speech) and vector-indexed search for its multimodal data platform, which supplies datasets to AI training and inference.

TTA operates the system and allocates its resources to these institutions.

The compute nodes of Haetae are fitted with GPUs (NVIDIA H100) as the jobs require, and the GPUs are moved between nodes. No GPUs were installed in the compute nodes during the IO500 runs.

The data of these jobs are model weights and datasets (e.g. Qwen3, Qwen3-VL, Llama 2, DeepSeek-V4 and agentic inference traces), KV-cache and pre-processed data, container images, and training and inference results. Gluesys configures and maintains the storage for TTA.

## Availability

> Please provide the deployment timeframe of the submitted system, or for on-demand cloud
> systems, the general period over which it is deployed and destroyed.
>
> Please describe the availability of the system to users and who are its set of most regular users.

The system was first deployed in autumn 2025 and was listed at SC25 (storage system "MantaStorage", client system "ESC8000-E11"). Around the turn of the year 2025/2026, TTA extended its use beyond the original project to the AI research of other research institutions, universities and companies.

In October and November 2026 the system was expanded from 4 to 6 DAOS servers and from 7 to 10 compute nodes, moved from InfiniBand HDR to 400 GbE RoCE v2, and upgraded to DAOS 2.8.1 on Rocky Linux 10. The storage was emptied for this planned upgrade, and the submitted runs were made directly after it. Regular operation resumes in December 2026, when the institutions' datasets and models are loaded back onto MantaStorage. As this is after the submission deadline, TTA will provide evidence of the production use of the system within three months of the published list, as the Production list rules require for systems not yet in production at the deadline.

Its most regular users are the researchers of these institutions. They receive accounts (one to three per institution) and resource allocations from TTA on request of their institution. The system is planned to stay in operation at least until December 2028, and TTA plans to expand it gradually (further compute nodes and storage servers) as the institutions' needs grow. The 10 compute nodes of this submission are its current size, not a fixed limit.

## Storage System Software

> How is this software available? (e.g., commercially, open-source, not publicly available) Note that if
> the storage software is not open-source or commercially available, then a general description
> would be requested, but this would limit the submission's reproducibility score.
>
> Can anyone download/purchase this software?
>
> List either product webpage or open-source repo of the exact software used in IO500.

The storage software is the Distributed Asynchronous Object Store (DAOS), release 2.8.1, with unmodified server and client code. DAOS is completely open-source:

* DAOS [GitHub repository](https://github.com/daos-stack/daos), release [v2.8.1](https://github.com/daos-stack/daos/releases/tag/v2.8.1)
* DAOS [documentation](https://docs.daos.io/)
* [SC-Asia 2020 paper](https://doi.org/10.1007/978-3-030-48842-0_3) _DAOS: A Scale-Out High Performance Storage Stack for Storage Class Memory_
* [SC-Asia 2023 paper](https://doi.org/10.1145/3581576.3581577) _Understanding DAOS Storage Performance Scalability_

MantaStorage is not a commercial product. It is a DAOS deployment on off-the-shelf servers that [Gluesys](https://www.gluesys.com) configured for TTA and maintains. Commercial support for DAOS itself is available from multiple companies.

> Give any and all additional details of this specific storage deployment: (e.g., type of storage server
> product such IBM ESS or DDN SFA400X2, use of Ext4 or some other file system on each storage
> node, dual connected storage media to storage servers).

The MantaStorage DAOS cluster consists of 6 storage servers running DAOS 2.8.1 on Rocky Linux 10.2 (kernel 6.12.0-211.16.1.el10_2.0.1):

- MantaStorage-01, MantaStorage-02: [AIC SB201-SU](https://www.aicipc.com/en/productdetail/51570), 2x Intel Xeon 6530P (32 cores), 1 TiB DDR5, 16x NVMe (MantaStorage-01: Samsung PM9A3 3.84 TB; MantaStorage-02: Phison Pascari X200P 3.84 TB), 2x NVIDIA ConnectX-7 400 GbE
- MantaStorage-03, MantaStorage-06: [Supermicro SYS-222C-TN](https://www.supermicro.com/en/products/system/gpu/2u/sys-222c-tn), 2x Intel Xeon 6520P (24 cores) / 6530P (32 cores), 1 TiB DDR5, 8x Seagate Nytro 5360H (XP7680SE70006) 7.68 TB, 2x NVIDIA ConnectX-7 400 GbE
- MantaStorage-04: Supermicro SYS-222C-TN, 2x Intel Xeon 6520P, 1 TiB DDR5, 4x Seagate Nytro 5360H (XP7680SE70006) 7.68 TB + 8x DapuStor Roealsen R5100 7.68 TB (namespace 5.63 TB), 2x ConnectX-7 400 GbE
- MantaStorage-05: Supermicro SYS-222C-TN, 2x Intel Xeon 6530P, 1 TiB DDR5, 4x Seagate Nytro 5360H (XP7680SE70006) 7.68 TB + 8x Phison Pascari X200P 3.84 TB, 2x ConnectX-7 400 GbE

All servers have 16x 64 GiB DDR5 and two single-port NVIDIA ConnectX-7 400 GbE adapters (MCX75310AAS-NEAT), one per CPU socket and DAOS engine. There are 72 NVMe drives in total.

Haetae has 10 compute nodes that access MantaStorage as DAOS clients: 8x ASUS ESC8000-E11 and 2x KTNF KH590S3. Each has 2x Intel Xeon Platinum 8558 (48 cores), 256 GiB to 1 TiB DDR5, one ConnectX-7 400 GbE adapter on socket 0 and a second rail on socket 1 (Broadcom BCM57608 400 GbE on 2 nodes, ConnectX-6 200 GbE on 8 nodes). The per-node tables and all configuration files are in the [README](README.md) of the reproducibility repository.

DAOS runs in MD-on-SSD mode. Each engine (one per CPU socket, 16 targets) keeps its metadata in a 300 GiB tmpfs memory file, which is persisted through a write-ahead log and periodic checkpoints on NVMe, and keeps all data on NVMe (bdev roles `data,meta,wal`, `mem-ratio` 100%). There is no local file system on the drives; DAOS accesses them through SPDK. The transport is libfabric 2.6.0 `ofi+verbs;ofi_rxm` over RoCE v2 with Mercury 2.4.1. One pool (`haetae`, 363 TB over all 192 targets; `data_thresh` 2048, `svc_rf` 2, WAL checkpointing timed 5 s / 50%, self-heal `exclude;rebuild`) holds the DAOS POSIX containers. The benchmark containers have compression and deduplication off.

## Runtime Environment

> State here that you provided all scripts/documentation that would allow someone else to
> reproduce your environment and attempt to achieve a similar IO500 score as the submitted
> system.

Full reproducibility documentation is provided in the GitHub repository below. It includes the DAOS server and client configuration files, the system tuning and RoCE QoS scripts, the pool and container creation script, the io500 build files, the rendered io500 ini files, the launcher with the exact `mpirun` command lines and the two pfind patches:
[https://github.com/gluesys/daos-reproducibility/tree/master/io500/sc26/tta/mantastorage](https://github.com/gluesys/daos-reproducibility/tree/master/io500/sc26/tta/mantastorage)

Compute nodes (DAOS clients): the 10 physical compute nodes of Haetae (8x ASUS ESC8000-E11, 2x KTNF KH590S3), each with 2x Intel Xeon Platinum 8558 (48 cores, hyper-threading on), 1 TiB, 512 GiB or 256 GiB RAM, one ConnectX-7 400 GbE NIC and a second rail (Broadcom BCM57608 400 GbE on 2 nodes, ConnectX-6 200 GbE on 8 nodes). Each node ran 144 MPI ranks (1,440 in total), bound to hardware threads and split across the two rails by NUMA node.

Network: one NVIDIA Spectrum-3 SN4700 switch (MSN4700-WS2FC, 32x 400 GbE, Cumulus Linux) with the RoCE lossless profile (PFC priority 3, DSCP trust, ECN). The hosts are configured to match (PFC priority 3, pause off, ToS 106, MTU 9000). DAOS uses `ofi+verbs;ofi_rxm` (libfabric 2.6.0) over RoCE v2.

io500 `io500-sc26_v4` was built from the official tag. IOR and mdtest are unmodified (`git diff` empty). The only change in the io500 tree is that `prepare.sh` fetches the DFS-aware pfind fork (https://github.com/mchaarawi/pfind, commit b86a4a0) instead of the VI4IO pfind. The find phase used that fork with two additional patches:

1. Entries of unknown type are queued as work items, so that idle ranks can steal them in chunks instead of the few ranks holding the directory splits stat'ing them inline.
2. An entry is looked up first (one RPC), and only files whose name matches `-name` get the full stat, so directories and non-matching files cost one RPC instead of two.

The patches are in the repository above, together with the pfind build tree used for the runs (patched sources and build outputs) as `pfind/pfind-src.tgz`. The input/output behaviour of pfind is unchanged: it reports the same `found`/`total` counts as the original pfind, which was verified against the original on a mock tree and by an independent file count on every run.

Kernel and system settings used for the runs: `kernel.numa_balancing=0`, `kernel.nmi_watchdog=0`, CPU idle states limited to C1 (`intel_idle.max_cstate=1 processor.max_cstate=1`), transparent hugepages `madvise` on the compute nodes and `never` on the servers, ConnectX-7 firmware `PCI_WR_ORDERING=force_relax` and `CQE_COMPRESSION=aggressive`, and tuned profile `throughput-performance`. The sysctl files for the dual-rail ARP settings and the Open MPI port range are in the repository.

## Fault Tolerance Mechanisms

> Does your system have a single point of failure as defined by `Definition 7` of a Production System?
> Please describe all mechanisms that provide fault tolerance for the submitted storage system. Be
> specific to your submission, not general storage system capabilities (power; networking; inter
> storage data and metadata server; intra storage data and metadata server storage media).

DAOS is a scale-out software-defined storage system. The fault domain of the submitted configuration is the storage server (node).

Hardware: every storage server has two redundant power supplies, ECC memory and two 400 GbE RoCE ports (NVIDIA ConnectX-7 MCX75310AAS-NEAT), one per DAOS engine. Each port is connected by its own cable to its own switch port (no breakout cables). The compute nodes have two network rails each. Each of the 6 storage servers is installed in its own rack, and in each rack the two power supplies of the server are connected to two different PDUs fed from two different power circuits. The loss of a single power supply, PDU or circuit therefore does not bring down a server, and the loss of a whole rack affects only one server, which the Production configuration tolerates. The data network uses one NVIDIA Spectrum-3 SN4700 400 GbE switch (MSN4700-WS2FC, Cumulus Linux) with two redundant power supplies. A failure of this single switch would bring down multiple nodes at once, which this questionnaire explicitly accepts ("any networking failure that brings down multiple nodes is acceptable"). All other redundancy is provided in software.

Software: the DAOS management service is replicated on three servers (`mgmt_svc_replicas`) and the pool service of `haetae` on five (`svc_rf` 2). Client access to both is redirected transparently if a server fails. There are no dedicated metadata servers; data placement is algorithmic and declustered across all 192 storage targets.

Data protection is set per container. For the **Production** submission (container `haetae-production`, `rd_fac:1`, `rd_lvl:node` = node-level fault domains) it was 2-way replication for metadata and IOR-Hard and 4+1P erasure coding for IOR-Easy. By design, this tolerates the loss of any single component on the data path without data loss: a whole server (2 engines, 32 targets), one engine, one NIC or cable, or one NVMe drive. DAOS excludes the failed targets and rebuilds the missing shards or replicas on the remaining servers (self-heal `exclude;rebuild`). When servers were taken down one by one during the preparation of this submission, DAOS excluded their targets and started the rebuild automatically, without operator action. The object class settings in `config-prod.ini` are:

```
    [ior-easy]
    API = DFS --dfs.pool=haetae --dfs.cont=haetae-production --dfs.dir_oclass=RP_2G1 --dfs.oclass=EC_4P1GX
    [ior-hard]
    API = DFS --dfs.pool=haetae --dfs.cont=haetae-production --dfs.dir_oclass=RP_2G1 --dfs.oclass=RP_2GX --dfs.chunk_size=470080
    [mdtest-easy]
    API = DFS --dfs.pool=haetae --dfs.cont=haetae-production --dfs.dir_oclass=RP_2GX --dfs.oclass=RP_2G1
    [mdtest-hard]
    API = DFS --dfs.pool=haetae --dfs.cont=haetae-production --dfs.dir_oclass=RP_2GX --dfs.oclass=RP_2G1
```

The **Research** submission (container `haetae-research`, `rd_fac:0`) used sharding/striping without data protection for all tests, to achieve maximum performance. It does not claim fault tolerance for the benchmark data. Its object class settings in `config-research.ini` are:

```
    [ior-easy]
    API = DFS --dfs.pool=haetae --dfs.cont=haetae-research --dfs.dir_oclass=S1 --dfs.oclass=SX
    [ior-hard]
    API = DFS --dfs.pool=haetae --dfs.cont=haetae-research --dfs.dir_oclass=S1 --dfs.oclass=SX --dfs.chunk_size=470080
    [mdtest-easy]
    API = DFS --dfs.pool=haetae --dfs.cont=haetae-research --dfs.dir_oclass=SX --dfs.oclass=S1
    [mdtest-hard]
    API = DFS --dfs.pool=haetae --dfs.cont=haetae-research --dfs.dir_oclass=SX --dfs.oclass=S1
```

All writes are durable on NVMe (write-ahead log, checkpointed metadata and data) within the measured phase. These choices are user-defined, as part of the API definitions in the io500 ini file, and were executed on the exact same storage system configuration without intervention of a storage administrator. The Production settings are the ones that the users' containers will use when regular operation resumes in December 2026.

## Execution

> Please provide a description of how the IO500 benchmark was executed, e.g., via system scheduler
> (e.g., SLURM) to run a job on the compute cluster, which initially ran a setup process to configure
> the client and file system, and then started the full benchmark.

TTA is the submitting institution and the operator of Haetae. The benchmark was executed by TTA's operations staff with technical support from Gluesys, directly after the planned upgrade described above. It ran on the pool `haetae` with the container settings that the users' Production containers will use when regular operation resumes in December 2026 (`rd_fac:1`, `rd_lvl:node`), i.e. with the same DAOS version, namespace and fault-tolerance settings as in regular operation.

Haetae has no batch scheduler; jobs are started with `mpirun` over a hostfile, and the benchmark was started the same way. A single `mpirun` from Haetae-01 over the hostfile of the 10 compute nodes ran the io500 binary built as described in Runtime Environment, with the ini file included in the result tarball (stonewall 300 s, all phases in one invocation). The launcher `io500-daos/run-io500.sh` and the exact command lines are in the repository. Before each run, the pool was created on freshly formatted NVMe drives (`nvme format --ses=1`) and the benchmark container was created fresh.

At the very end of each run, after all phases had completed and `result.txt` had been written, the IOR DFS backend's finalize step hits an MPI abort. This is an upstream IOR issue: `DFS_Finalize` calls `MPI_Barrier` on a communicator that `test_finalize` has already freed. The abort does not affect any measured phase, but it has two side effects:

1. It ends the launcher before its `create_tarball` step. Each submitted result directory was therefore packaged with `io500-daos/package-result.sh`, which checks the launcher log, performs the same steps as `create_tarball` (copy the launcher and the rendered ini, tar the directory) and adds the launcher log, its exit status and a record of the packaging (`packaged-by.txt`).
2. It can pre-empt rank 0's final `fclose` of the buffered summary. In the Research run, `result_summary.txt` was left empty and was restored from the launcher log included in the tarball, which holds the same `[RESULT]`/`[SCORE]` lines: io500 prints them to stdout through the same call that writes the summary. `result.txt` and its score hash are untouched, and the Production run's summary was written by io500 itself.

In both submitted runs all phases completed and `io500 --verify` returned `[OK]`.

> During the IO500 benchmark execution was the system entirely dedicated to running the
> benchmark or were there other jobs running in the same cluster and storage system?

Compute nodes and storage system were dedicated while running the benchmark; no other jobs were running on the compute nodes or the storage servers.

## Caching

> Please describe all caching mechanisms in client/server that were utilized during the IO500 run.

No client-side caching: the DAOS File System (DFS) API (libdfs) used by IOR, mdtest and pfind performs no data or metadata caching, and dfuse was not used. On the server side, DAOS keeps metadata in the engine memory file (tmpfs), backed by a write-ahead log and periodic checkpoints on NVMe, and data on NVMe. All writes are persistent before the phase ends.

## Data Source

> Where is the source of truth of the data stored and later read back in the IO500 benchmark? This
> question relates to whether the submitted system is a burst buffer layered on primary storage or
> primary storage itself.

DAOS is a standalone storage system, and the DAOS POSIX container used in the IO500 benchmarks is the primary storage. It is not a burst buffer or acceleration layer in front of another file system.

## Trust

> Please describe any steps taken to ensure that the results are trustworthy: did you run the
> benchmark multiple times and get similar scores; did you validate the score is below the physical
> capabilities of the deployed hardware; how did you validate that the storage system follows the
> IO500 rules regarding persistence ("All data must be written to persistent storage within the
> measured time for the individual benchmark")?

The runs were executed by TTA's operations staff with technical support from Gluesys. Fifteen formal full runs (stonewall 300 s) were made on 2026-11-04 and 2026-11-05 (KST), nine with the Production settings and six with the Research settings, all on the same hardware and all valid. The earlier runs were made while the build of the find tool and the drive namespaces were being finalized. The last two runs of each kind used the final configuration and agree within 0.5% (Production 733.75 and 731.58, Research 1,237.26 and 1,242.79). The submitted results are the last run of each kind.

Every submitted run passed `io500 --verify` and an independent completeness check of the find phase: the number of files found equals the number created by the mdtest and ior phases. The measured values are well below the hardware limits of the servers, compute nodes and the 400 GbE network (e.g. ior-easy-write 277 GiB/s on 72 NVMe drives). Persistence was checked in two ways: by the design of the data path, in which every write is acknowledged only after it is in the write-ahead log and data store on NVMe and the memory file is checkpointed every 5 s, and by the read phases, which read the data back after the intervening phases. Server telemetry during the runs (per-engine I/O latencies, scheduler state, space usage) was recorded and is available on request.

## Reproducibility

> Given the 4 possible reproducibility scores listed in the
> [reproducibility description](https://io500.org/the-lists#reproducibility-scores),
> what score do you believe your submission will be assigned?

This submission should be assigned the **Fully Reproducible** score. MantaStorage is not a packaged product but a configuration of open-source software on off-the-shelf hardware that anyone can rebuild:

* the exact software versions are publicly available (DAOS 2.8.1, io500-sc26_v4, the pfind patches in the repository);
* the storage design is published (DAOS documentation and papers);
* the storage servers (Supermicro SYS-222C-TN, AIC SB201-SU), NVMe drives, NVIDIA network adapters and switch are standard products of their vendors, sold in the Americas, EMEA and Asia-Pacific;
* every configuration file and script used for the runs is in the repository.

The Production submission is intended for the Production list.

## Feedback

> Please provide feedback on this questionnaire.

We were able to answer every question and have no additional feedback.
