# Pembagian Laporan — Distributed RDBMS with High Availability

Dokumen ini memetakan komponen laporan ke 5 anggota. Setiap komponen wajib
diuraikan dalam tiga bagian: **Pengertian**, **Implementasi**, dan **Bukti/Demo
(sudah diterapkan)**.

## Ringkasan Pembagian

| Anggota | Bagian bersama | Komponen yang dikerjakan |
|---|---|---|
| Anggota 1 | **Pendahuluan** | Fondasi RDBMS, arsitektur master-slave, skema data, hak akses |
| Anggota 2 | — | Replikasi & konsistensi |
| Anggota 3 | — | Partitioning & sharding |
| Anggota 4 | **Kesimpulan** | High availability & auto failover |
| Anggota 5 | **Diagram arsitektur menyeluruh** | Routing HAProxy, integrasi failover, deployment, observability |

---

## Anggota 1 — Fondasi RDBMS, Arsitektur Master-Slave, Skema & Hak Akses
**Tambahan bagian bersama: Pendahuluan** (latar belakang, rumusan masalah 4 poin,
tujuan, batasan/asumsi).

**1. RDBMS (MySQL 8.0)**
- Pengertian: DBMS relasional, ACID, storage engine InnoDB.
- Implementasi: `configs/Dockerfile.master`, `configs/Dockerfile.slave`, `configs/master.cnf`, `configs/slave.cnf`.
- Bukti/Demo: `docker compose ps` (semua node healthy); `SELECT VERSION()`.

**2. Arsitektur terdistribusi master-slave (2 shard)**
- Pengertian: master (baca-tulis) vs replica (baca-saja), tujuan skalabilitas & redundansi.
- Implementasi: `configs/docker-compose.yml` (2 shard × master + 2 replica, network `dbnet`).
- Bukti/Demo: daftar 6 node MySQL + status healthy.

**3. Skema database & seed data**
- Pengertian: perancangan tabel relasional dan data awal.
- Implementasi: `configs/init-common.sql`, `configs/init-shard-a.sql`, `configs/init-shard-b.sql`.
- Bukti/Demo: `SHOW CREATE TABLE shop.customers;`, `SELECT * FROM shop.customers;`.

**4. Manajemen user & hak akses**
- Pengertian: user peran (replikasi, health-check, orchestrator, aplikasi), prinsip least privilege.
- Implementasi: user `repl`, `haproxy_check`, `orchestrator`, `app` pada `init-common.sql`.
- Bukti/Demo: `SELECT user, host FROM mysql.user;`, `SHOW GRANTS FOR 'app'@'%';`.

---

## Anggota 2 — Replikasi & Konsistensi

**1. Replikasi (binary log → relay log)**
- Pengertian: alur replikasi master→replica, peran IO thread & SQL thread.
- Implementasi: `log-bin`, `relay-log`, `log_slave_updates`; `scripts/init-replication.ps1`.
- Bukti/Demo: `scripts/show-replication.ps1` (IO=ON, SQL=ON, lag 0).

**2. GTID (Global Transaction Identifier)**
- Pengertian: identitas transaksi global, `MASTER_AUTO_POSITION=1`.
- Implementasi: `gtid_mode=ON`, `enforce_gtid_consistency=ON`, `CHANGE MASTER ... AUTO_POSITION=1`.
- Bukti/Demo: `SELECT @@gtid_mode;`, `SELECT @@GLOBAL.gtid_executed;`, konsistensi data master↔replica.

**3. Semi-synchronous replication & durability**
- Pengertian: semi-sync (commit tunggu ACK minimal 1 replica), trade-off CAP.
- Implementasi: plugin `rpl_semi_sync_master/slave`, prefix `loose_`, `sync_binlog`, `innodb_flush_log_at_trx_commit`.
- Bukti/Demo: `SHOW STATUS LIKE 'Rpl_semi_sync_master_status';` (ON) dan `..._clients` (2).

**4. Tantangan replikasi: errant GTID**
- Pengertian: GTID lokal pada replica menyebabkan Orchestrator menolak promosi.
- Implementasi: replica dikosongkan tanpa init + `RESET MASTER` sebelum `CHANGE MASTER`.
- Bukti/Demo: `problems=[]` pada Orchestrator (sebelumnya `errant_gtid`).

---

## Anggota 3 — Partitioning & Sharding

**1. Partitioning tabel**
- Pengertian: memecah tabel menjadi partisi logis; partisi pruning.
- Implementasi: `orders PARTITION BY RANGE (YEAR(order_date))` di `configs/init-common.sql`.
- Bukti/Demo: `EXPLAIN SELECT ... WHERE order_date >= '2026-01-01'` → `partitions: p2026,pmax`.

**2. Sharding horizontal**
- Pengertian: memecah data ke beberapa server (shard) berdasarkan routing key.
- Implementasi: aturan `customer_id % 2` (genap→Shard A, ganjil→Shard B); seed terpisah per shard.
- Bukti/Demo: `python router/router.py list` (data disjoint antar shard).

**3. Router aplikasi (sharding)**
- Pengertian: lapisan penentu shard sebelum query dijalankan.
- Implementasi: `router/router.py` (perintah `put`/`get`/`list`, pemilihan shard + port).
- Bukti/Demo: `python router/router.py put 7000 ...` lalu `get 7000` (diarahkan ke shard benar).

**4. Perbandingan partitioning vs sharding**
- Pengertian: perbedaan tujuan, lokasi data, dan transparansi bagi aplikasi.
- Implementasi: keduanya diterapkan pada sistem ini.
- Bukti/Demo: tabel perbandingan + rujukan hasil komponen 1 & 2 anggota ini.

---

## Anggota 4 — High Availability & Auto Failover
**Tambahan bagian bersama: Kesimpulan** (ringkasan hasil per kebutuhan tugas).

**1. Konsep High Availability & SPOF**
- Pengertian: ketersediaan tinggi, single point of failure, RTO/RPO.
- Implementasi: master + 2 replica per shard; Orchestrator sebagai pengawas.
- Bukti/Demo: sistem tetap melayani saat satu replica dimatikan.

**2. Auto failover dengan Orchestrator**
- Pengertian: deteksi kegagalan → analisis → pemilihan kandidat → promosi.
- Implementasi: `configs/orchestrator.conf.json`, `scripts/register-orchestrator.ps1`.
- Bukti/Demo: `scripts/test-failover.ps1 -Shard A` (promosi + waktu ≈ 6 detik).

**3. Reintegrasi master lama**
- Pengertian: node yang pulih dipulihkan sebagai replica kembali.
- Implementasi: `scripts/reintegrate.ps1`.
- Bukti/Demo: master lama `read_only=1` dan menyinkronkan marker pasca-failover.

**4. Deteksi kegagalan & anti-flapping**
- Pengertian: interval polling, periode blokir recovery, status downtime.
- Implementasi: `InstancePollSeconds`, `RecoveryPeriodBlockSeconds` pada `orchestrator.conf.json`.
- Bukti/Demo: log Orchestrator (`DeadMaster`, `MasterRecovery`) dan UI `http://127.0.0.1:3000`.

---

## Anggota 5 — Routing HAProxy, Integrasi Failover, Deployment & Observability
**Tambahan bagian bersama: Diagram arsitektur menyeluruh** (gambar end-to-end:
aplikasi/router → HAProxy → 2 shard, Orchestrator + reloader, port dan alur).

**1. Read/write splitting dengan HAProxy**
- Pengertian: pemisahan trafik baca/tulis dan load balancing replica.
- Implementasi: `configs/haproxy.cfg.template` (frontend `write_a/read_a/write_b/read_b`, backend per shard).
- Bukti/Demo: write ke `13306` → master; read ke `13307` → replica (roundrobin).

**2. Health check & penanganan node down**
- Pengertian: deteksi node mati dan pengeluaran/restorasi otomatis dari pool.
- Implementasi: `option mysql-check user haproxy_check`.
- Bukti/Demo: `docker stop` replica → status `DOWN`, layanan tetap jalan; pulih → `UP` (stats `:8404/stats`).

**3. Integrasi failover → update HAProxy**
- Pengertian: mengarahkan ulang trafik tulis ke master baru tanpa restart.
- Implementasi: `configs/hooks/on-failover.sh` → `configs/reloader.py` (Unix socket, master `-S`), seamless reload.
- Bukti/Demo: backend `master_a → shard-a-rep1`, reload `Success=1` (hasil `scripts/test-failover.ps1` langkah 4).

**4. Deployment & orkestrasi (Docker Compose)**
- Pengertian: containerization, reproduksibilitas, network/volume.
- Implementasi: `configs/docker-compose.yml`, Dockerfile `COPY --chmod=0644`, volume `runtime/`.
- Bukti/Demo: `docker compose up -d` → seluruh service healthy; `scripts/setup-all.ps1`.

**5. Observability**
- Pengertian: pemantauan status cluster.
- Implementasi: HAProxy stats page, Orchestrator Web UI, `scripts/verify-all.ps1`.
- Bukti/Demo: tabel status dari `:8404` dan `:3000`.

---

## Alur Pengerjaan Laporan (urutan bab)

1. Pendahuluan (Anggota 1).
2. Fondasi & skema (Anggota 1).
3. Replikasi & konsistensi (Anggota 2).
4. Partitioning & sharding (Anggota 3).
5. Diagram arsitektur menyeluruh (Anggota 5).
6. Routing HAProxy & integrasi failover (Anggota 5).
7. High availability & auto failover (Anggota 4).
8. Deployment & observability (Anggota 5).
9. Kesimpulan (Anggota 4).
