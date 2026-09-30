param(
    [Parameter(Mandatory = $true)][string]$Demoted,
    [Parameter(Mandatory = $true)][string]$NewMaster,
    [string]$OrchestratorUrl = "http://127.0.0.1:3000"
)

$ErrorActionPreference = "Continue"

function Invoke-Sql {
    param([string]$Container, [string]$Sql)
    docker exec $Container mysql -uroot -prootpass -e $Sql 2>$null
}

Write-Host "Reintegrating $Demoted as a replica of $NewMaster ..."

Invoke-Sql $Demoted "STOP SLAVE; SET GLOBAL super_read_only=0; SET GLOBAL read_only=1; RESET SLAVE ALL;"

$sql = "CHANGE MASTER TO MASTER_HOST='$NewMaster', MASTER_USER='repl', " +
       "MASTER_PASSWORD='replpass', MASTER_AUTO_POSITION=1; START SLAVE;"
Invoke-Sql $Demoted $sql

Start-Sleep -Seconds 5

$status = docker exec $Demoted mysql -uroot -prootpass -N -e "SELECT @@read_only; SELECT SERVICE_STATE FROM performance_schema.replication_connection_status; SELECT SERVICE_STATE FROM performance_schema.replication_applier_status;" 2>$null
Write-Host "$Demoted => read_only / IO / SQL : $($status -join ' / ')"

$masterHost = docker exec $Demoted mysql -uroot -prootpass -N -e "SELECT MASTER_HOST FROM performance_schema.replication_connection_status;" 2>$null
Write-Host "$Demoted is now replicating from $masterHost"
