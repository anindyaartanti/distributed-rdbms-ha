$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
$router = Join-Path $root "router\router.py"

Write-Host "=================================================="
Write-Host " VERIFIKASI SISTEM DISTRIBUTED RDBMS HA"
Write-Host "=================================================="

Write-Host ""
Write-Host "[1] Replikasi & semi-sync"
& (Join-Path $PSScriptRoot "show-replication.ps1")

Write-Host ""
Write-Host "[2] HAProxy backend status (mysql-check)"
$csv = (Invoke-WebRequest -Uri "http://127.0.0.1:8404/stats;csv" -UseBasicParsing).Content
($csv -split "`n" | Where-Object { $_ -match '^(master_a|replicas_a|master_b|replicas_b),' }) | ForEach-Object {
    $f = $_ -split ','
    Write-Host ("    {0,-12} {1,-16} {2}" -f $f[0], $f[1], $f[17])
}

Write-Host ""
Write-Host "[3] Sharding: data per shard (via read frontend)"
python $router list

Write-Host ""
Write-Host "[4] Partition pruning pada tabel orders (Shard A master)"
docker exec shard-a-master mysql -uroot -prootpass -e "EXPLAIN SELECT * FROM shop.orders WHERE order_date >= '2026-01-01'\G" 2>$null |
    Select-String -Pattern "partitions"

Write-Host ""
Write-Host "[5] Read/write routing demo (Shard A)"
python $router put 7000 "Verify User" "verify@example.com"
python $router get 7000
