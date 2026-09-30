param(
    [ValidateSet("A", "B")]
    [string]$Shard = "A",
    [string]$OrchestratorUrl = "http://127.0.0.1:3000",
    [int]$TimeoutSeconds = 150
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$router = Join-Path $root "router\router.py"
$cfgPath = Join-Path $root "configs\runtime\haproxy.cfg"

if ($Shard -eq "A") {
    $master = "shard-a-master"
    $cluster = "shard-a-master:3306"
    $writePort = 13306
    $backendMaster = "master_a"
} else {
    $master = "shard-b-master"
    $cluster = "shard-b-master:3306"
    $writePort = 13316
    $backendMaster = "master_b"
}

$base = Get-Random -Minimum 1000 -Maximum 8000
$markerId = if ($Shard -eq "A") { $base - ($base % 2) } else { $base - ($base % 2) + 1 }
$markerName = "marker-$markerId"

Write-Host "== Shard $Shard failover test =="
Write-Host "master=$master cluster=$cluster writePort=$writePort markerId=$markerId"
Write-Host ""

Write-Host "[1] writing marker before failover..."
python $router put $markerId $markerName "$markerName@example.com"
if ($LASTEXITCODE -ne 0) { throw "pre-failover write failed" }

Write-Host ""
Write-Host "[2] stopping master container $master ..."
docker stop $master | Out-Null
$stopTime = Get-Date

Write-Host "[3] waiting for Orchestrator to promote a replica (timeout ${TimeoutSeconds}s)..."
$promoted = $null
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 3
    $cfg = Get-Content -LiteralPath $cfgPath -Raw
    $m = [regex]::Match($cfg, "backend\s+$backendMaster\b[\s\S]*?server\s+\S+\s+([^:\s]+):3306")
    if ($m.Success) {
        $candidate = $m.Groups[1].Value
        if ($candidate -ne $master) { $promoted = $candidate; break }
    }
}
if (-not $promoted) { throw "no promotion detected within ${TimeoutSeconds}s" }
$elapsed = [math]::Round(((Get-Date) - $stopTime).TotalSeconds, 1)
Write-Host "    promoted new master: $promoted (HAProxy repointed after ${elapsed}s)"

Write-Host ""
Write-Host "[4] HAProxy backend $backendMaster now points to:"
(Get-Content -LiteralPath $cfgPath | Select-String -Pattern "server\s+\S+\s+$promoted" | Select-Object -First 1).Line.Trim()

Write-Host ""
Write-Host "[5] writing a NEW marker through write port $writePort after failover..."
$markerId2 = $markerId + 2
python $router put $markerId2 "$markerName-after" "$markerName-after@example.com" 2>&1
if ($LASTEXITCODE -ne 0) { throw "post-failover write failed" }

Write-Host ""
Write-Host "[6] markers on promoted master $promoted :"
docker exec $promoted mysql -uroot -prootpass -N -e "SELECT customer_id, name FROM shop.customers WHERE customer_id IN ($markerId, $markerId2) ORDER BY customer_id" 2>$null

Write-Host ""
Write-Host "RESULT: $master failed -> $promoted promoted in ${elapsed}s (Orchestrator + HAProxy hook)"
