param(
    [int]$WaitSeconds = 70
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$compose = Join-Path $root "configs\docker-compose.yml"

Write-Host "== 1/6 build MySQL images =="
& (Join-Path $PSScriptRoot "build-images.ps1")

Write-Host "== 2/6 reset HAProxy runtime config =="
Copy-Item -LiteralPath (Join-Path $root "configs\haproxy.cfg.template") `
          -Destination (Join-Path $root "configs\runtime\haproxy.cfg") -Force

Write-Host "== 3/6 start cluster =="
docker compose -f $compose up -d

Write-Host "== 4/6 wait for MySQL to become healthy (${WaitSeconds}s) =="
Start-Sleep -Seconds $WaitSeconds

Write-Host "== 5/6 configure replication =="
& (Join-Path $PSScriptRoot "init-replication.ps1")
Start-Sleep -Seconds 8

Write-Host "== 6/6 register topology with Orchestrator =="
& (Join-Path $PSScriptRoot "register-orchestrator.ps1")

Write-Host ""
Write-Host "Done. Run scripts/verify-all.ps1 to check the cluster."
