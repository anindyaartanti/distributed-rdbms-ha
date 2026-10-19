#!/usr/bin/env bash
set -euo pipefail

declare -A replicas=(
  [shard-a-rep1]=shard-a-master
  [shard-a-rep2]=shard-a-master
  [shard-b-rep1]=shard-b-master
  [shard-b-rep2]=shard-b-master
)

echo "=== Replication status ==="
for replica in "${!replicas[@]}"; do
  sql="SELECT SERVICE_STATE FROM performance_schema.replication_connection_status; \
SELECT SERVICE_STATE FROM performance_schema.replication_applier_status; \
SELECT COUNT(*) FROM shop.customers;"
  out=$(docker exec -e MYSQL_PWD=rootpass "$replica" mysql -uroot -N -e "$sql" 2>/dev/null | tr '\n' ' ')
  printf "%-14s parent=%-16s IO/SQL/data = %s\n" "$replica" "${replicas[$replica]}" "$out"
done

echo
echo "=== Semi-sync masters ==="
for master in shard-a-master shard-b-master; do
  out=$(docker exec -e MYSQL_PWD=rootpass "$master" mysql -uroot -N \
    -e "SHOW STATUS LIKE 'Rpl_semi_sync_master_clients'; SHOW STATUS LIKE 'Rpl_semi_sync_master_status';" 2>/dev/null | tr '\n\t' ' ')
  printf "%-16s %s\n" "$master" "$out"
done
