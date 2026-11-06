# IO500-SC25 - TTA - MantaStorage

Reproducibility information for benchmarks submitted to the IO500-SC25
[Production](https://io500.org/list/sc25/production) list and
[Research](https://io500.org/list/sc25/io500) list.

General information on building and running the IO500 benchmarks with DAOS can
be found in the [DAOS Community Wiki](https://daosio.atlassian.net/wiki/spaces/DC/pages/11167301633/IO-500+SC22)
page on IO500.

## IO500.org Reproducibility Questionnaire

Answers to the _IO500.org Reproducibility Questionnaire_ are provided in
the
[io500-reproducibility.tta-mantastorage.md](io500-reproducibility.tta-mantastorage.md)
document. Note that this document covers two different _user-selectable_ data protection
schemes to address the different requirements of the _Production_ and _Research_ list.

## Institution

[TTA](https://tta.or.kr)

The TTA operates this supercomputer as part of the Republic of Korea's
national R&D project, "Development of High-Efficiency Parallel Storage
Software Technology Optimized for AI Computational Accelerators."

## Storage System

The DAOS storage cluster in TTA's MantaStorage system consists of 4x
Supermicro SYS-222C-TN servers, currently running DAOS version 2.7(under dev)
on Rocky Linux 9.6. The system was deployed and is commercially supported by
[Gluesys](https://www.gluesys.com):

- Server 1(MantaStorage-01)
    - CPU: 2x Intel(R) Xeon(R) 6530P
    - RAM: 8x 64GiB DDR5 Samsung 4800MT/s
    - NVMe
        - 10x Samsung MZWLR3T8HCLS-00A07 3.84TB
        - 2x Dapustor DPRD3108T0T507T6000 5.63TB
    - NIC
        - 2x Mellanox ConnectX-6 1-port Infiniband HDR adapter
- Server 2(MantaStorage-02)
    - CPU: 2x Intel(R) Xeon(R) 6530P
    - RAM: 8x 64GiB DDR5 Samsung 4800MT/s
    - NVMe
        - 8x Seagate XP7680SE70006 7.68TB
        - 2x Dapustor DPRD3108T0T507T6000 5.63TB
        - 2x Samsung MZWLR3T8HCLS-00A07 3.84TB
    - NIC
        - 2x Mellanox ConnectX-6 1-port Infiniband HDR adapter
- Server 3(MantaStorage-03)
    - CPU: 2x Intel(R) Xeon(R) 6520P
    - RAM: 8x 64GiB DDR5 Samsung 4800MT/s
    - NVMe
        - 8x Samsung MZQL23T8HCLS-00A07 3.84TB
        - 2x Seagate XP7680SE70006 7.68TB
        - 2x Dapustor DPRD3108T0T507T6000 5.63TB
    - NIC
        - 2x Mellanox ConnectX-6 1-port Infiniband HDR adapter
- Server 4(MantaStorage-04)
    - CPU: 2x Intel(R) Xeon(R) 6520P
    - RAM: 8x 64GiB DDR5 Samsung 4800MT/s
    - NVMe
        - 8x Samsung MZQL23T8HCLS-00A07 3.84TB
        - 2x Seagate XP7680SE70006 7.68TB
        - 2x Dapustor DPRD3108T0T507T6000 5.63TB
    - NIC
        - 2x Mellanox ConnectX-6 1-port Infiniband HDR adapter

DAOS storage software references:

* DAOS [github repository](https://github.com/daos-stack/daos)
* DAOS [packages repository](https://packages.daos.io)
* DAOS [documentation](https://docs.daos.io/)
* [SC-Asia 2020 paper](https://doi.org/10.1007/978-3-030-48842-0_3)
  _DAOS: A Scale-Out High Performance Storage Stack for Storage Class Memory_
* [SC-Asia 2023 paper](https://doi.org/10.1145/3581576.3581577)
  _Understanding DAOS Storage Performance Scalability_

## Client Nodes

The clients in TTA's MantaStorage system are ASUSTeK ESC8000-E11 servers,
currently running DAOS version 2.7(under dev) on Rocky Linux 9.6:

- CPU: 2x Intel(R) Xeon(R) Platinum 8558
- RAM: 16x 64GiB DDR5 Samsung 4800MT/s
- NIC: 2x Mellanox ConnectX-5 1-port Infiniband EDR adapter

## High-Performance Fabric

The HPC Fabric is a fully non-blocking HDR InfiniBand network, using
[Mellanox QM8790](https://docs.nvidia.com/networking/display/qm87xx/introduction) switch.

Both servers and clients use two single-port Mellanox ConnectX-6 HDR adapters
(one per CPU socket). On the servers, each port is managed by a dedicated
`daos_engine` running on that CPU socket. On the clients, each MPI task is
communicating through the IB interface on the same NUMA node.

## Execution Environment

All servers and clients were installed with the following software stack:

- Rocky Linux 9.6 (Kernel version 5.14.0-570.52.1.el9_6.x86_64)
- [MLNX_OFED_LINUX-24.10-3.2.5.0](https://docs.nvidia.com/networking/display/mlnxofedv24103250lts/release+notes) on the DAOS servers and clients.
- [DAOS 2.7 (under development)](https://github.com/daos-stack/daos/tree/808afd521bb41f3b0e08b43b2b5bae521ed00bd2)
- [MPICH 4.2.3](https://www.mpich.org/downloads/)

The following DAOS server and client configuration files were used.

### DAOS Server configuration

- [/etc/daos/daos_server.yml](servers/MantaStorage-01/etc/daos/daos_server.yml)
- [/etc/daos/daos_control.yml](servers/MantaStorage-01/etc/daos/daos_control.yml)
- [/etc/daos/daos_agent.yml](servers/MantaStorage-01/etc/daos/daos_agent.yml)
- [/etc/sysctl.d/99-daos-net.conf](servers/MantaStorage-01/etc/sysctl.d/99-daos-net.conf)

For the IO500 benchmarks, one storage pool was created that spans all 4
servers, using the [create-pool.sh](servers/create-pool.sh) script. In that pool, a DAOS POSIX
container was created using the [create-cont.sh](servers/create-cont.sh) script.

### DAOS Client environment

Our IO500-SC25 benchmark runs were performed in the deployment stage, before
user operation started. For this reason the runs have been performed with
interactive `mpirun` invocations, using a hostlist to specify client nodes as
described above.

The IO500 run scripts are included in the IO500 results tarballs.

The rules for the IO500 Production lists require that the storage system has
no single point of failure. So the
[config-all-dfs-rf1-tmpl.ini](config-all-dfs-rf1-tmpl.ini) configuration file
has been used for Production runs. It protects against single faults by using
2-Way replication for metadata and IOR-Hard, and 2+1P Erasure Coding for IOR-Easy.

Submissions to the IO500 Research lists are using an identical storage system
setup, but since the "no single point of failure" requirement does not apply
to the Research list the
[config-all-dfs-rf0-tmpl.ini](config-all-dfs-rf0-tmpl.ini) configuration file
has been used for Research runs. This configuration does not use replication
or Erasure Coding to maximize the achievable performance.

## IO500 List Entries

- MantaStorage: SC25 Research List #85, submission 770
- MantaStorage-EC: SC25 Production List #113, submission 776
