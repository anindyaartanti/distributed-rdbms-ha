# Desain Sistem: Distributed RDBMS with High Availability

**Mata Kuliah / Proyek:** DABD — Distributed Database Design
**Versi:** 1.0 — **terimplementasi & teruji** (hasil nyata: lihat [RESULTS.md](RESULTS.md))
**Stack:** MySQL 8.0 · GTID Replication · Docker Compose · Orchestrator · HAProxy

---

## Daftar Isi

1. [Pendahuluan](#bab-1--pendahuluan)
2. [Landasan Teori](#bab-2--landasan-teori)
3. [Desain Arsitektur](#bab-3--desain-arsitektur)
4. [Desain Replikasi & Partitioning/Sharding](#bab-4--desain-replikasi--partitioningsharding)
5. [Desain Auto Failover](#bab-5--desain-auto-failover)
6. [Desain Read/Write Routing (HAProxy)](#bab-6--desain-readwrite-routing-haproxy)
7. [Skenario Pengujian](#bab-7--skenario-pengujian)
8. [Kesimpulan](#bab-8--kesimpulan)
- [Lampiran A — Matriks Parameter Konfigurasi](#lampiran-a--matriks-parameter-konfigurasi)

---

## BAB 1 — Pendahuluan

### 1.1 Latar Belakang

Aplikasi modern menuntut basis data yang tidak hanya menyimpan data, tetapi juga:
**tersedia tinggi (high availability)**, **mampu menangani beban baca besar**, dan
**dapat diskalakan secara horizontal**. Satu instance RDBMS tunggal menjadi
*Single Point of Failure* (SPOF) dan *bottleneck* saat trafik bertambah.

Untuk mengatasinya, dibangun sistem **RDBMS terdistribusi** dengan arsitektur
**master-slave**, dilengkapi replikasi, pemecahan data (partitioning/sharding),
failover otomatis, dan pemisahan trafik baca/tulis.

### 1.2 Rumusan Masalah

1. Bagaimana membangun RDBMS dan menjadikannya terdistribusi dengan arsitektur master-slave?
2. Bagaimana mengimplementasikan partitioning/sharding dan replikasi?
3. Bagaimana mengimplementasikan auto failover?
4. Bagaimana mengimplementasikan routing read/write (misalnya dengan HAProxy)?

### 1.3 Tujuan

Menyusun **desain** sistem RDBMS terdistribusi yang memenuhi keempat kebutuhan di
atas, lengkap dengan topologi, konfigurasi, alur proses, dan rencana pengujian.

### 1.4 Batasan & Asumsi

- **Scope dokumen:** desain dan contoh konfigurasi, **belum** implementasi/uji live.
- Jumlah node target: **2 shard**, tiap shard = **1 master + 2 replica** (total 6 node DB).
- Replikasi menggunakan **MySQL GTID** (logis, mudah dikelola saat failover).
- Routing memakai **HAProxy `mode tcp`** di depan cluster.
- Failover memakai **Orchestrator** dengan hook ke HAProxy.
- Deployment direpresentasikan lewat **Docker Compose** (satu host, network internal).

---

## BAB 2 — Landasan Teori

### 2.1 RDBMS Terdistribusi

RDBMS terdistribusi menyebar data dan beban ke beberapa node yang saling
terhubung jaringan, namun tetap tampak sebagai satu sistem basis data.

### 2.2 CAP Theorem

Dalam sistem terdistribusi, tidak mungkin memenuhi ketiganya sekaligus:

```
        Consistency
           /\
          /  \
         /    \
        /      \
   Availability — Partition Tolerance
```

- Sistem master-slave asinkron memilih **AP** (Availability + Partition Tolerance),
  mengorbankan *strong consistency* menjadi *eventual consistency*.
- Replikasi semi-sinkron memilih **CP** (Consistency + Partition Tolerance),
  mengorbankan sebagian availability saat replika lambat.

**Keputusan desain:** memakai **semi-synchronous replication** untuk keseimbangan —
write dianggap sukses setelah minimal **1 replica** mengakui (ACK), sehingga risiko
kehilangan data saat failover kecil.

### 2.3 Replikasi

```
   Master                         Replica
   +--------+   binlog events   +--------+
   | binlog | ----------------> | relay  |
   +--------+                   | log    |
       |                        +--------+
   proses write                    |
       |                           v
       v                      SQL thread
   data dir  ===== data copy ===> data dir
```

- **Master** mencatat semua perubahan ke **binary log (binlog)**.
- **Replica** menarik binlog master ke **relay log**, lalu menerapkan (replay) ke datanya.
- **GTID** (*Global Transaction Identifier*) memberi identitas unik tiap transaksi,
  sehingga posisi replikasi tidak perlu dihitung manual (menggantikan `binlog file + pos`).

### 2.4 Partitioning vs Sharding

| Aspek        | Partitioning                            | Sharding                                    |
|--------------|-----------------------------------------|---------------------------------------------|
| Lokasi data  | 1 server, banyak bagian logis           | Banyak server (node) berbeda                |
| Tujuan       | Kelola tabel besar, pruning query       | Skala horizontal, sebar beban & kapasitas   |
| Teknik       | `PARTITION BY RANGE/HASH/LIST`          | Routing key `hash(key) % N` ke server       |
| Transparansi | Transparan bagi aplikasi (1 koneksi)    | Perlu lapisan routing (aplikasi/middleware) |

**Keputusan desain:** menggunakan **keduanya** — partitioning untuk tabel besar
(`orders`) dan sharding untuk tabel yang tumbuh cepat (`customers`).

### 2.5 High Availability & Failover

- **HA (High Availability):** sistem tetap melayani walau ada komponen gagal.
- **Failover:** proses memindahkan peran master ke node lain saat master gagal.
  - *Manual failover:* operator memutuskan & menjalankan promosi.
  - *Auto failover:* alat (Orchestrator) mendeteksi kegagalan dan mempromosikan
    replica secara otomatis, lalu mengarahkan ulang trafik.

### 2.6 Read/Write Splitting

Beban akses umumnya didominasi **baca (read)**. Dengan memisahkan trafik:
- **Write** selalu ke master (karena hanya master yang boleh menerima perubahan).
- **Read** didistribusikan ke replica (load balancing), sehingga master lega.

---

## BAB 3 — Desain Arsitektur

### 3.1 Diagram Topologi

```
                        +-------------------------------------------------------+
                        |                     APLIKASI                          |
                        +---------------------------+---------------------------+
                                                    |
                              write:3306            |            read:3307
                        +---------------------------v---------------------------+
                        |                       HAProxy                         |
                        |   frontend write  :3306  ->  backend master_pool      |
                        |   frontend read   :3307  ->  backend replica_pool     |
                        |   (mode tcp + option mysql-check health)              |
                        +---------------------------+---------------------------+
                                                    |
              +-------------------------------------+-------------------------------------+
              |                                                                           |
   ========================== SHARD-A ==========================        ========================== SHARD-B ==========================
   |                                                            |    |                                                            |
   |   +----------------+        binlog        +-------------+   |    |   +----------------+        binlog        +-------------+   |
   |   |  A-Master :3306|<-------------------->|  A-Replica1 |   |    |   |  B-Master :3306|<-------------------->|  B-Replica1 |   |
   |   +-------+--------+                      +-------------+   |    |   +-------+--------+                      +-------------+   |
   |           |                               +-------------+   |    |           |                               +-------------+   |
   |           +------------------------------>|  A-Replica2 |   |    |           +------------------------------>|  B-Replica2 |   |
   |                                           +-------------+   |    |                                           +-------------+   |
   ================================================================    ================================================================
                        ^                                                                    ^
                        |                     monitor + promote                            |
                        +--------------------+   ORCHESTRATOR   +----------------------------+
                                             |  (heartbeat tiap  |   on-failover hook
                                             |   detik)          |--> update haproxy.cfg
                                             +-------------------+
```

### 3.2 Spesifikasi Node

| Node               | Peran               | Port Host              | Keterangan                          |
|--------------------|---------------------|------------------------|-------------------------------------|
| `haproxy`          | Router              | 13306/13307, 13316/13317 | Write/Read Shard A & B; stats 8404 |
| `haproxy-reloader` | Reload HAProxy      | 8080                   | Menerima hook failover              |
| `orchestrator`     | Monitor + Failover  | 3000                   | Web UI + API                        |
| `orchestrator-db`  | Backend metadata    | 3310                   | DB milik Orchestrator               |
| `shard-a-master`   | Master Shard-A      | 3406                   | R/W + binlog                        |
| `shard-a-rep1`     | Replica Shard-A     | 3407                   | Read-only, relay log                |
| `shard-a-rep2`     | Replica Shard-A     | 3408                   | Read-only, relay log                |
| `shard-b-master`   | Master Shard-B      | 3416                   | R/W + binlog                        |
| `shard-b-rep1`     | Replica Shard-B     | 3417                   | Read-only, relay log                |
| `shard-b-rep2`     | Replica Shard-B     | 3418                   | Read-only, relay log                |

> Port `3306` host dipakai MySQL bawaan OS, sehingga frontend HAProxy dipetakan ke
> `13306`–`13317`. Di dalam network Docker, semua MySQL memakai port 3306.

### 3.3 Justifikasi Teknologi

| Pilihan                  | Alasan                                                                 |
|--------------------------|------------------------------------------------------------------------|
| MySQL 8.0                | Mature, mendukung GTID, partitioning native, ekosistem failover luas.  |
| GTID replication         | Failover sederhana: replica baru cukup tahu GTID, tanpa hitung posisi. |
| Semi-sync                | Mengurangi risiko kehilangan data tanpa mengorbankan terlalu banyak availability. |
| Docker Compose           | Reproducible, mudah dibongkar-pasang saat pengujian.                    |
| HAProxy                  | Read/write splitting + health check handal, konfigurasi ringkas.       |
| Orchestrator             | Deteksi topologi + auto promosi + hook (integrasi HAProxy).            |

### 3.4 Alur Read/Write

```
 WRITE (INSERT/UPDATE/DELETE)
   App --> HAProxy:3306 --> backend master_pool --> A-Master --> binlog --> A-Replica1/2

 READ (SELECT)
   App --> HAProxy:3307 --> backend replica_pool --roundrobin--> A-Replica1 / A-Replica2
```

---

## BAB 4 — Desain Replikasi & Partitioning/Sharding

### 4.1 Konfigurasi Replikasi GTID

**Master (`master.cnf`)** — inti:

```
[mysqld]
log-bin                  = mysql-bin
binlog_format            = ROW
gtid_mode                = ON
enforce_gtid_consistency = ON
log_slave_updates        = ON
plugin-load-add          = rpl_semi_sync_master=semisync_master.so;rpl_semi_sync_slave=semisync_slave.so
loose_rpl_semi_sync_master_timeout = 1000
```

**Replica (`slave.cnf`)** — inti:

```
[mysqld]
log-bin                  = mysql-bin
relay-log                = relay-bin
gtid_mode                = ON
enforce_gtid_consistency = ON
read_only                = ON
log_slave_updates        = ON
plugin-load-add          = rpl_semi_sync_master=semisync_master.so;rpl_semi_sync_slave=semisync_slave.so
loose_rpl_semi_sync_slave_enabled = ON
```

> Catatan implementasi: (1) file `.cnf` di-`COPY --chmod=0644` ke image karena
> bind-mount Windows membuat file world-writable (diabaikan MySQL); (2) variabel
> plugin memakai prefix `loose_` agar tidak error saat `--initialize`.
> `server-id` unik diberikan lewat argumen `command` per container.

**Inisialisasi replikasi (dijalankan sekali):**

```sql
RESET SLAVE ALL;
RESET MASTER;                 -- replica dimulai bersih: tanpa GTID lokal (hindari errant GTID)
CHANGE MASTER TO
  MASTER_HOST     = 'shard-a-master',
  MASTER_USER     = 'repl',
  MASTER_PASSWORD = 'replpass',
  MASTER_AUTO_POSITION = 1;   -- memakai GTID
START SLAVE;
```

> Replica sengaja **dikosongkan tanpa init script**; skema, user, dan data diterima
> lewat replikasi. Ini mencegah `errant_gtid` yang membuat Orchestrator menolak
> promosi. Semi-sync di master diaktifkan runtime: `SET GLOBAL rpl_semi_sync_master_enabled=ON`.

**Verifikasi:** `SHOW SLAVE STATUS\G` → `Slave_IO_Running=Yes`, `Slave_SQL_Running=Yes`,
`Seconds_Behind_Master` mendekati 0.

### 4.2 Strategi Sharding

Tabel `customers` dipecah horizontal ke 2 shard berdasarkan **routing key**:

```
   shard_index = hash(customer_id) % 2

   customer_id = 101  -> hash(101) % 2 = 1  -> SHARD-B
   customer_id = 102  -> hash(102) % 2 = 0  -> SHARD-A
```

```
                 customers (logis)
   +-----------------+-----------------+
   |   Shard-A       |   Shard-B       |
   |  id % 2 == 0    |  id % 2 == 1    |
   |  A-Master + 2r  |  B-Master + 2r  |
   +-----------------+-----------------+
```

**Routing di level aplikasi:** aplikasi memiliki *shard map* (`shard_key -> host/port`)
dan mengarahkan query ke shard yang tepat sebelum masuk HAProxy.

> **Catatan skala:** `hash % N` sederhana namun rawan *reshuffle* saat N berubah.
> Untuk produksi dapat ditingkatkan ke **consistent hashing** atau *directory-based
> sharding* (`shard_directory` table). Ini dicatat sebagai rekomendasi lanjutan.

### 4.3 Strategi Partitioning

Tabel `orders` di setiap shard dipartisi berdasarkan **tahun**:

```sql
CREATE TABLE orders (
  order_id    BIGINT NOT NULL,
  customer_id BIGINT NOT NULL,
  order_date  DATE   NOT NULL,
  amount      DECIMAL(12,2) NOT NULL,
  PRIMARY KEY (order_id, order_date)
)
PARTITION BY RANGE (YEAR(order_date)) (
  PARTITION p2024 VALUES LESS THAN (2025),
  PARTITION p2025 VALUES LESS THAN (2026),
  PARTITION p2026 VALUES LESS THAN (2027),
  PARTITION pmax  VALUES LESS THAN MAXVALUE
);
```

**Manfaat:**
- **Partition pruning:** `WHERE order_date >= '2026-01-01'` hanya membaca partisi `p2026`.
- **Maintenance:** partisi lama bisa di-*archive*/*drop* tanpa mengganggu data lain.

### 4.4 Skema Sharding (ringkas)

```
   Aplikasi
      |
      | shard = hash(customer_id) % 2
      v
   +-----------+          +-----------+
   | Shard-A   |          | Shard-B   |
   | customers |          | customers |
   | orders    | (part.)  | orders    | (part.)
   +-----------+          +-----------+
```

---

## BAB 5 — Desain Auto Failover

### 5.1 Peran Orchestrator

Orchestrator memantau seluruh topologi replikasi dan menyimpan state-nya:

```
   Orchestrator
     |- poll heartbeat setiap N detik ke setiap node
     |- memetakan topologi (siapa master, siapa replica)
     |- mendeteksi kegagalan (master tidak merespons)
     +- memilih replica terbaik (relay log paling lengkap) -> promosi
```

### 5.2 Alur Auto Failover

```
  1. Master A-Master berhenti merespons.
  2. Orchestrator mendeteksi (heartbeat gagal / koneksi timeout).
  3. Orchestrator memilih kandidat replica terbaik (mis. A-Replica1).
  4. Kandidat dipromosikan -> menjadi master baru.
  5. Replica lain di-repoint untuk mereplikasi dari master baru.
  6. Hook on-failover dipanggil -> memperbarui backend HAProxy (master_pool).
  7. Trafik tulis dialihkan ke master baru secara otomatis.
  8. Setelah A-Master lama hidup kembali, ia didemote menjadi replica.
```

Diagram keadaan:

```
   NORMAL                FAILOVER DETECTED            SETELAH FAILOVER
   -------               -----------------            ----------------
   A-Master (RW)         A-Master (X mati)            A-Replica1 (RW)  <- master baru
     |                     |                               |
     +-- A-Rep1 (RO)       +-- A-Rep1                    A-Master (RO, demoted)
     +-- A-Rep2 (RO)       +-- A-Rep2 (kandidat)         A-Rep2   (RO)
```

### 5.3 Hook Integrasi ke HAProxy

Orchestrator berjalan di container sendiri dan tidak punya akses langsung ke
container HAProxy. Solusinya: **volume `runtime/` dibagi** antara HAProxy dan
service kecil `haproxy-reloader`, dan socket master HAProxy (`-S`) ditaruh di
volume tersebut.

```
Orchestrator (PostMasterFailoverProcesses)
    |
    +-- hooks/on-failover.sh  (env: ORC_FAILED_HOST, ORC_SUCCESSOR_HOST)
            |
            +-- curl POST http://haproxy-reloader:8080/failover {failed, successor}
                    |
                    +-- reloader: tulis ulang backend master_x di runtime/haproxy.cfg
                    +-- reloader: kirim perintah "reload" ke Unix socket HAProxy
                                  (Success=1) -> trafik tulis dialihkan tanpa restart
```

> HAProxy dijalankan `haproxy -W -db -S /shared/haproxy.sock -f /shared/haproxy.cfg`
> (master-worker + master CLI). Reload bersifat *seamless* (worker baru di-fork,
> koneksi lama tetap dilayani hingga selesai).

### 5.4 Kriteria Keberhasilan Failover

| Kriteria                       | Target                                     |
|--------------------------------|--------------------------------------------|
| Deteksi kegagalan              | < 10 detik                                 |
| Downtime tulis (write outage)  | < 30 detik                                 |
| Kehilangan data (data loss)    | 0 baris (dengan semi-sync)                 |
| Konsistensi arah trafik        | Write selalu ke master baru                |

---

## BAB 6 — Desain Read/Write Routing (HAProxy)

### 6.1 Konfigurasi Inti

**Frontend & backend (ringkas):**

```
frontend write_frontend
    bind *:3306
    default_backend master_pool

frontend read_frontend
    bind *:3307
    default_backend replica_pool

backend master_pool
    mode tcp
    option mysql-check user haproxy_check
    server shard-a-master shard-a-master:3306 check

backend replica_pool
    mode tcp
    balance roundrobin
    option mysql-check user haproxy_check
    server shard-a-rep1 shard-a-rep1:3306 check
    server shard-a-rep2 shard-a-rep2:3306 check
```

> Implementasi aktual memakai penamaan per shard: `master_a`/`replicas_a` dan
> `master_b`/`replicas_b`, dengan frontend `write_a/read_a` (bind 3306/3307) dan
> `write_b/read_b` (bind 3316/3317). Pemetaan ke host: 13306/13307/13316/13317.

### 6.2 Alur Routing

```
                   +-------------------------------+
   write :3306 --> |  frontend write  -> master_pool| --> A-Master  (RW)
                   +-------------------------------+

                   +-------------------------------+     +--> A-Replica1 (RO)
   read  :3307 --> |  frontend read   -> replica_pool| ---|
                   +-------------------------------+     +--> A-Replica2 (RO)
                                                        (balance roundrobin)
```

### 6.3 Health Check & Penanganan Node Down

- `option mysql-check` mengirim handshake MySQL tiap interval ke setiap server.
- Server yang gagal check ditandai **DOWN** dan dikeluarkan dari pool.
- Saat pulih, server otomatis masuk kembali (**UP**) setelah beberapa check sukses.
- Jika **semua** replica down, `replica_pool` kosong → trafik baca gagal (bisa
  diarahkan fallback ke master; lihat rekomendasi).

### 6.4 Pertimbangan Staleness (Replication Lag)

Replica bisa tertinggal (`Seconds_Behind_Master > 0`). Implikasi:
- Data "read-your-writes" bisa belum terlihat di replica.
- **Mitigasi desain:** query yang butuh data *fresh* diarahkan ke port write (master),
  atau gunakan sesi *sticky* ke master untuk sementara setelah write.

---

## BAB 7 — Skenario Pengujian

> Rencana uji ini akan dieksekusi pada **Fase Implementasi** (belum dijalankan).

| # | Skenario                                  | Langkah Inti                                              | Kriteria Lulus                                   |
|---|-------------------------------------------|-----------------------------------------------------------|--------------------------------------------------|
| 1 | Replikasi berjalan                        | Insert di master, cek di replica                          | Data muncul di kedua replica, lag ~0             |
| 2 | Read/write routing                        | Write via :3306, read via :3307                           | Write ke master; read tersebar ke replica        |
| 3 | Partition pruning                         | `EXPLAIN` query dengan filter tanggal                     | Hanya partisi relevan yang dipindai (`partitions`)|
| 4 | Sharding routing                          | Insert `customer_id` genap & ganjil                       | Data masuk ke shard yang benar                   |
| 5 | Node replica down                         | Matikan 1 replica                                         | HAProxy keluarkan dari pool, layanan tetap normal |
| 6 | **Auto failover**                         | Matikan master                                            | Orchestrator promosikan replica < 30s, write lanjut |
| 7 | Reintegrasi node lama                      | Hidupkan kembali master lama                              | Node didemote jadi replica, sinkron kembali      |
| 8 | Rollback/trafik setelah failover          | Jalankan write & read pasca failover                      | Semua trafik mengarah ke master baru             |

**Alat bantu uji:** `mysql` client, `docker stop/start`, log Orchestrator,
statistik HAProxy (`:8404/stats`), dan skrip shell otomatis.

---

## BAB 8 — Kesimpulan

### 8.1 Ringkasan Desain

Sistem yang dirancang menggabungkan:
- **Master-slave** dengan **GTID + semi-sync replication** untuk HA dan integritas data.
- **Partitioning** (native `PARTITION BY RANGE`) untuk efisiensi tabel besar.
- **Sharding horizontal** (`hash(customer_id) % 2`) untuk skala dan sebar beban.
- **Auto failover** berbasis **Orchestrator** + hook HAProxy.
- **Read/write routing** dengan **HAProxy** (write:3306, read:3307).

### 8.2 Rekomendasi Lanjutan

1. Ganti `hash % N` dengan **consistent hashing** atau *directory-based sharding*.
2. Tambahkan **fallback read ke master** saat seluruh replica down.
3. Tambahkan **monitoring** (Prometheus + Grafana) untuk lag, koneksi, QPS.
4. Pertimbangkan **MySQL Group Replication / InnoDB Cluster** untuk konsistensi lebih kuat.
5. Uji **chaos** (matikan node acak) untuk validasi ketahanan sistem.

---

## Lampiran A — Matriks Parameter Konfigurasi

| File                    | Parameter Kunci                                                                 |
|-------------------------|---------------------------------------------------------------------------------|
| `master.cnf`            | GTID + `plugin-load-add` semi-sync + `loose_rpl_semi_sync_master_timeout`       |
| `slave.cnf`             | GTID + `read_only` + semi-sync + relay log                                      |
| `Dockerfile.master/slave`| `COPY --chmod=0644` file cnf ke image (menghindari isu world-writable Windows) |
| `haproxy.cfg.template`  | frontend `write_a/read_a/write_b/read_b`, backend per shard, `mysql-check`       |
| `reloader.py`           | rewrite backend master + reload lewat Unix socket HAProxy                        |
| `orchestrator.conf.json`| `MySQLOrchestrator*`, `RecoverMasterClusterFilters`, `PostMasterFailoverProcesses` |
| `hooks/on-failover.sh`  | kirim `{failed, successor}` ke `haproxy-reloader`                                |
| `docker-compose.yml`    | 10 service, `runtime` volume bersama, healthcheck                                |
| `init-common.sql`       | skema, `PARTITION BY RANGE`, user (masters)                                      |
| `init-shard-a/b.sql`    | data per shard                                                                   |

> Kode lengkap ada di direktori [`configs/`](../configs), [`router/`](../router),
> dan [`scripts/`](../scripts). Hasil uji nyata di [RESULTS.md](RESULTS.md).

> Semua contoh konfigurasi tersedia di direktori [`configs/`](../configs/).
