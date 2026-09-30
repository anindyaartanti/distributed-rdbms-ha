$ErrorActionPreference = "Stop"

function Invoke-Sql {
    param([string]$Container, [string]$Sql)
    docker exec $Container mysql -uroot -prootpass -e $Sql
}

$shards = @(
    @{ Master = "shard-a-master"; Replicas = @("shard-a-rep1", "shard-a-rep2") },
    @{ Master = "shard-b-master"; Replicas = @("shard-b-rep1", "shard-b-rep2") }
)

foreach ($shard in $shards) {
    Write-Host "[master] $($shard.Master): enabling semi-sync"
    Invoke-Sql $shard.Master "SET GLOBAL rpl_semi_sync_master_enabled=ON;"

    foreach ($replica in $shard.Replicas) {
        Write-Host "[replica] $replica -> $($shard.Master)"
        $sql = "RESET SLAVE ALL; " +
               "RESET MASTER; " +
               "CHANGE MASTER TO MASTER_HOST='$($shard.Master)', " +
               "MASTER_USER='repl', MASTER_PASSWORD='replpass', " +
               "MASTER_AUTO_POSITION=1; " +
               "START SLAVE;"
        Invoke-Sql $replica $sql
    }
}

Write-Host "Replication configured. Run scripts/show-replication.ps1 to verify."
