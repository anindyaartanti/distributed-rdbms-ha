$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

Copy-Item -LiteralPath (Join-Path $root "configs\haproxy.cfg.template") `
          -Destination (Join-Path $root "configs\runtime\haproxy.cfg") -Force

Write-Host "Reset runtime/haproxy.cfg from template."

try {
    $result = curl.exe -s -X POST "http://127.0.0.1:8080/reload"
    Write-Host "Reload result: $result"
} catch {
    Write-Host "Reloader not reachable (haproxy will pick up the config on next start)."
}
