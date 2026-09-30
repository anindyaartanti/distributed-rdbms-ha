$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

docker build -f (Join-Path $root "configs\Dockerfile.master") -t rdbms-master:latest (Join-Path $root "configs")
docker build -f (Join-Path $root "configs\Dockerfile.slave")  -t rdbms-slave:latest  (Join-Path $root "configs")

Write-Host "Images rdbms-master:latest and rdbms-slave:latest built."
