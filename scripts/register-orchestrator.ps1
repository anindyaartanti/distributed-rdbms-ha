param(
    [string]$OrchestratorUrl = "http://127.0.0.1:3000"
)

$ErrorActionPreference = "Stop"

$instances = @(
    "shard-a-master/3306",
    "shard-a-rep1/3306",
    "shard-a-rep2/3306",
    "shard-b-master/3306",
    "shard-b-rep1/3306",
    "shard-b-rep2/3306"
)

foreach ($instance in $instances) {
    $result = curl.exe -s -X GET "$OrchestratorUrl/api/discover/$instance"
    Write-Host "discover $instance -> $result"
}

Start-Sleep -Seconds 5

foreach ($cluster in @("shard-a-master:3306", "shard-b-master:3306")) {
    $instancesJson = curl.exe -s "$OrchestratorUrl/api/cluster/$cluster" | ConvertFrom-Json
    $master = ($instancesJson | Where-Object { $_.ReplicationDepth -eq 0 }).Key.Hostname
    $problems = ($instancesJson | ForEach-Object { $_.Problems } | Where-Object { $_ }) -join ","
    Write-Host "cluster $cluster : master=$master problems=[$problems]"
}
