# Distributed RDBMS with High Availability

Implementasi **RDBMS terdistribusi** dengan arsitektur **master-slave**,
**replikasi GTID + semi-sync**, **partitioning & sharding**, **auto failover
(Orchestrator)**, dan **read/write routing (HAProxy)**.

> Status: **berjalan & teruji** (lihat [docs/RESULTS.md](docs/RESULTS.md)).

## Kebutuhan Tugas

1. Membangun RDBMS dan menjadikannya terdistribusi (master-slave).
2. Mengimplementasikan partitioning/sharding dan replikasi.
3. Mengimplementasikan auto failover.
4. Mengimplementasikan routing read/write (HAProxy).

## Stack Teknologi

| Komponen           | Teknologi                                  |
|--------------------|--------------------------------------------|
| RDBMS              | MySQL 8.0                                  |
| Replikasi          | GTID + semi-synchronous                    |
| Partitioning       | Native `PARTITION BY RANGE` (tabel `orders`) |
| Sharding           | Horizontal `customer_id % 2` (router aplikasi) |
| Read/Write Routing | HAProxy 2.9 (`mode tcp`)                   |
| Auto Failover      | Orchestrator 3.2 + hook reload HAProxy     |
| Deploy             | Docker Compose                             |

## Topologi

```
                       +----------------------------+
   Aplikasi/router ---> |          HAProxy           |
                       |  write_a 13306   read_a 13307 |--> Shard A (master + 2 replica)
                       |  write_b 13316   read_b 13317 |--> Shard B (master + 2 replica)
                       +----------------------------+
                              ^ reload (master socket)
                       +----------------------------+
                       |      haproxy-reloader      |
                       +----------------------------+
                              ^ HTTP hook
                       +----------------------------+
                       |        Orchestrator        |  (deteksi + promosi)
                       +----------------------------+
```

## Struktur Repositori

```
.
├── README.md
├── docs/
│   ├── DESIGN.md            # dokumen desain lengkap (8 BAB)
│   └── RESULTS.md           # hasil implementasi & pengujian
├── configs/
│   ├── docker-compose.yml   # 10 service: 6 MySQL + haproxy + reloader + orchestrator(+db)
│   ├── Dockerfile.master    # image MySQL master (COPY --chmod cnf)
│   ├── Dockerfile.slave     # image MySQL replica
│   ├── master.cnf           # GTID + semi-sync (master)
│   ├── slave.cnf            # GTID + read_only + semi-sync (replica)
│   ├── init-common.sql      # skema, partisi, user (masters)
│   ├── init-shard-a.sql     # data Shard A (genap)
│   ├── init-shard-b.sql     # data Shard B (ganjil)
│   ├── haproxy.cfg.template # template konfigurasi HAProxy
│   ├── runtime/haproxy.cfg  # konfigurasi hidup (diupdate saat failover)
│   ├── reloader.py          # service reload HAProxy (Unix socket)
│   ├── orchestrator.conf.json
│   └── hooks/on-failover.sh # hook PostMasterFailoverProcesses
├── router/
│   └── router.py            # router sharding (customer_id % 2)
└── scripts/
    ├── build-images.ps1
    ├── setup-all.ps1        # satu perintah: build + up + replikasi + register
    ├── init-replication.ps1
    ├── register-orchestrator.ps1
    ├── init-haproxy.ps1
    ├── show-replication.ps1
    ├── verify-all.ps1
    ├── test-failover.ps1
    └── reintegrate.ps1
```

## Cara Menjalankan

Prasyarat: Docker Desktop (WSL2), PowerShell, `mysql` client, Python 3.

```powershell
# 1) jalankan seluruh cluster + replikasi + registrasi failover
powershell -ExecutionPolicy Bypass -File scripts\setup-all.ps1

# 2) verifikasi
powershell -ExecutionPolicy Bypass -File scripts\verify-all.ps1
```

Uji failover & reintegrasi:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\test-failover.ps1 -Shard A
powershell -ExecutionPolicy Bypass -File scripts\reintegrate.ps1 -Demoted shard-a-master -NewMaster shard-a-rep1
```

## Port Host

| Endpoint                     | Port              |
|------------------------------|-------------------|
| HAProxy write Shard A / B    | 13306 / 13316     |
| HAProxy read Shard A / B     | 13307 / 13317     |
| HAProxy stats                | 8404 (`/stats`)   |
| Orchestrator UI/API          | 3000              |
| haproxy-reloader             | 8080              |
| Node MySQL (debug)           | 3406–3408, 3416–3418 |

> Port `3306` host dipakai MySQL bawaan OS, sehingga HAProxy dipetakan ke `13306+`.

## Dokumen

- [docs/DESIGN.md](docs/DESIGN.md) — desain arsitektur, replikasi, sharding, failover, routing.
- [docs/RESULTS.md](docs/RESULTS.md) — hasil pengujian nyata + catatan teknis.
