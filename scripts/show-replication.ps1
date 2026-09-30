$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot

$replicas = @{
    "shard-a-rep1" = "shard-a-master"
    "shard-a-rep2" = "shard-a-master"
    "shard-b-rep1" = "shard-b-master"
    "shard-b-rep2" = "shard-b-master"
}

Write-Host "=== Replication status ==="
foreach ($replica in $replicas.Keys) {
    $sql = "SELECT SERVICE_STATE FROM performance_schema.replication_connection_status; " +
           "SELECT SERVICE_STATE FROM performance_schema.replication_applier_status; " +
           "SELECT COUNT(*) FROM shop.customers;"
    $out = docker exec $replica mysql -uroot -prootpass -N -e $sql 2>$null
    Write-Host ("{0,-14} parent={1,-16} IO/SQL/data = {2}" -f $replica, $replicas[$replica], ($out -join " "))
}

Write-Host ""
Write-Host "=== Semi-sync masters ==="
foreach ($master in @("shard-a-master", "shard-b-master")) {
    $out = docker exec $master mysql -uroot -prootpass -N -e "SHOW STATUS LIKE 'Rpl_semi_sync_master_clients'; SHOW STATUS LIKE 'Rpl_semi_sync_master_status';" 2>$null
    Write-Host ("{0,-16} {1}" -f $master, ($out -join "  "))
}
