#!/usr/bin/env bash
set -euo pipefail

sql() {
  docker exec "$1" mysql -uroot -prootpass -e "$2"
}

setup_shard() {
  local master="$1"; shift
  local replicas=("$@")

  echo "[master] ${master}: enabling semi-sync"
  sql "$master" "SET GLOBAL rpl_semi_sync_master_enabled=ON;"

  for replica in "${replicas[@]}"; do
    echo "[replica] ${replica} -> ${master}"
    sql "$replica" "RESET SLAVE ALL; \
RESET MASTER; \
CHANGE MASTER TO MASTER_HOST='${master}', \
MASTER_USER='repl', MASTER_PASSWORD='replpass', \
MASTER_AUTO_POSITION=1; \
START SLAVE;"
  done
}

setup_shard shard-a-master shard-a-rep1 shard-a-rep2
setup_shard shard-b-master shard-b-rep1 shard-b-rep2

echo "Replication configured. Run scripts/show-replication.sh to verify."
