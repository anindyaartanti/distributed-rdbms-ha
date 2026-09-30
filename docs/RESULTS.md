# Hasil Implementasi & Pengujian

Dokumen ini mencatat **hasil nyata** implementasi sistem (bukan rencana).
Semua perintah dijalankan pada satu host Windows + Docker Desktop.

## 1. Lingkungan Uji

| Komponen        | Versi / Keterangan                       |
|-----------------|------------------------------------------|
| Host OS         | Windows (PowerShell 5.1)                 |
| Docker Engine   | 29.2.1 (Docker Desktop, WSL2)            |
| MySQL           | 8.0.46 (`mysql:8.0`)                     |
| HAProxy         | 2.9.15 (`haproxy:2.9`)                   |
| Orchestrator    | 3.2.4 (`openarkcode/orchestrator`)       |
| Python (router) | 3.14 (host)                              |
| Tanggal uji     | 2026-09-30                               |

## 2. Cara Menjalankan

```powershell
# dari root repo
powershell -ExecutionPolicy Bypass -File scripts\setup-all.ps1
```

Skrip tersebut menjalankan: build image → reset config HAProxy → `compose up` →
tunggu healthy → `init-replication` → `register-orchestrator`.

Verifikasi cepat:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-all.ps1
```

## 3. Topologi Berjalan

```
10 container: 6 MySQL (2 shard x master+2 replica), haproxy, haproxy-reloader,
              orchestrator, orchestrator-db
```

| Service          | Peran                | Port host     |
|------------------|----------------------|---------------|
| haproxy          | routing baca/tulis   | 13306/13307/13316/13317, 8404 |
| orchestrator     | failover (UI/API)    | 3000          |
| orchestrator-db  | backend metadata     | 3310          |
| haproxy-reloader | reload HAProxy       | 8080          |
| shard-a-master   | master Shard A       | 3406          |
| shard-a-rep1/2   | replica Shard A      | 3407/3408     |
| shard-b-master   | master Shard B       | 3416          |
| shard-b-rep1/2   | replica Shard B      | 3417/3418     |

> Port `3306` host dipakai MySQL bawaan OS, sehingga HAProxy dipetakan ke `13306+`.

## 4. Hasil Pengujian

### 4.1 Replikasi & Semi-Sync

```
=== Replication status ===
shard-a-rep1   parent=shard-a-master   IO/SQL/data = ON ON 3
shard-a-rep2   parent=shard-a-master   IO/SQL/data = ON ON 3
shard-b-rep1   parent=shard-b-master   IO/SQL/data = ON ON 3
shard-b-rep2   parent=shard-b-master   IO/SQL/data = ON ON 3

=== Semi-sync masters ===
shard-a-master   Rpl_semi_sync_master_clients 2   Rpl_semi_sync_master_status ON
shard-b-master   Rpl_semi_sync_master_clients 2   Rpl_semi_sync_master_status ON
```

**Kesimpulan:** replikasi GTID berjalan di kedua shard (IO & SQL thread ON,
lag 0), semi-sync aktif dengan 2 replica per master.

### 4.2 Routing Baca/Tulis HAProxy

```
[2] HAProxy backend status (mysql-check)
    master_a     shard-a-master   UP
    replicas_a   shard-a-rep1     UP
    replicas_a   shard-a-rep2     UP
    master_b     shard-b-master   UP
    replicas_b   shard-b-rep1     UP
    replicas_b   shard-b-rep2     UP
```

Uji node down: `docker stop shard-a-rep1` → status menjadi `DOWN`, trafik baca
tetap dilayani `shard-a-rep2`; setelah `docker start`, status kembali `UP`
otomatis. Write (`13306`) selalu diarahkan ke master, read (`13307`) ke replica.

### 4.3 Sharding (routing `customer_id % 2`)

```
--- Shard A (read port 13307) ---     --- Shard B (read port 13317) ---
102  Andi Genap                       101  Cici Ganjil
104  Budi Genap                       103  Dewi Ganjil
106  Eka Genap                        105  Fajar Ganjil
```

Write/read melalui router:

```
customer 7000 -> Shard A (write port 13306)
7000  Verify User  verify@example.com
(read from Shard A, port 13307)
```

**Kesimpulan:** data terpecah disjoint antar shard; router mengarahkan operasi
ke shard yang benar (genap → A, ganjil → B).

### 4.4 Partitioning (`orders PARTITION BY RANGE(YEAR(order_date))`)

```
EXPLAIN SELECT * FROM orders WHERE order_date >= '2026-01-01';
   partitions: p2026,pmax
```

**Kesimpulan:** partition pruning bekerja — hanya partisi relevan yang dipindai.

### 4.5 Auto Failover (Orchestrator + hook HAProxy)

Perintah: `powershell -File scripts\test-failover.ps1 -Shard A`

```
[1] writing marker before failover...
customer 5360 -> Shard A (write port 13306)
[2] stopping master container shard-a-master ...
[3] waiting for Orchestrator to promote a replica...
    promoted new master: shard-a-rep1 (HAProxy repointed after 6.2s)
[4] HAProxy backend master_a now points to:
server shard-a-rep1 shard-a-rep1:3306 check
[5] writing a NEW marker through write port 13306 after failover...
customer 5362 -> Shard A (write port 13306)
[6] markers on promoted master shard-a-rep1 :
5360  marker-5360
5362  marker-5360-after
```

**Kesimpulan:**
- Orchestrator mendeteksi master mati, mempromosikan `shard-a-rep1`
  (read_only=0, `RESET SLAVE ALL`).
- Hook `PostMasterFailoverProcesses` memanggil `on-failover.sh` →
  `haproxy-reloader` menulis ulang backend `master_a` dan reload HAProxy
  (`Success=1`), sehingga **write otomatis dialihkan** ke master baru.
- **Deteksi + repoint ≈ 6 detik**; tidak ada data hilang (marker sebelum
  failover tetap ada karena semi-sync).

### 4.6 Reintegrasi Master Lama

Setelah `docker start shard-a-master`, node lama kembali sebagai *detached master*.
Dijalankan `scripts\reintegrate.ps1 -Demoted shard-a-master -NewMaster shard-a-rep1`:

```
shard-a-master  read_only=1  IO=ON  SQL=ON
shard-a-master is now replicating from shard-a-rep1
marker 5362 tersinkron: 5360 marker-5360 ; 5362 marker-5360-after
```

**Kesimpulan:** master lama didemote menjadi replica dan mengejar ketertinggalan
(marker pasca-failover ikut tersinkron).

### 4.7 Kualitas Topologi Orchestrator

```
cluster shard-a-master:3306 : master=shard-a-master problems=[]
cluster shard-b-master:3306 : master=shard-b-master problems=[]
```

Tidak ada `errant_gtid` / problem lain (lihat catatan §6).

## 5. Ringkasan Kebutuhan vs Hasil

| # | Kebutuhan Tugas                          | Status | Bukti            |
|---|------------------------------------------|--------|------------------|
| 1 | RDBMS terdistribusi master-slave         | ✅     | §4.1             |
| 2 | Partitioning/sharding + replikasi        | ✅     | §4.1, §4.3, §4.4 |
| 3 | Auto failover                            | ✅     | §4.5, §4.6       |
| 4 | Routing read/write (HAProxy)             | ✅     | §4.2, §4.3       |

## 6. Catatan Teknis / Gotcha

1. **Config file world-writable di Windows.** Bind-mount `.cnf` dari Windows
   membuat MySQL mengabaikan file (mode 0777). Solusi: `COPY --chmod=0644` ke
   image (`Dockerfile.master` / `Dockerfile.slave`).
2. **Variabel plugin saat `--initialize`.** `rpl_semi_sync_master_timeout` tidak
   dikenal saat inisialisasi datadir. Solusi: prefix `loose_`.
3. **Errant GTID.** Replica yang menjalankan SQL lokal (mis. init script) punya
   GTID sendiri → Orchestrator menolak promosi (`errant_gtid`). Solusi: replica
   di-**kosongkan tanpa init**, menerima skema/user lewat replikasi, dan
   `RESET MASTER` sebelum `CHANGE MASTER`.
4. **Reload HAProxy lintas container.** Orchestrator harus memicu reload di
   container HAProxy. Solusi: master socket HAProxy (`-S`) ditaruh di volume
   bersama dan di-reload oleh service `haproxy-reloader` (Python + Unix socket).
5. **Port 3306 host terpakai OS** → HAProxy dipetakan ke `13306` dst.
