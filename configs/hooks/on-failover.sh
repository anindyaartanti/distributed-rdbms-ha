#!/bin/sh
set -eu

OLD_MASTER="${ORC_FAILED_HOST:-}"
NEW_MASTER="${ORC_SUCCESSOR_HOST:-}"
PORT="${ORC_SUCCESSOR_PORT:-3306}"

if [ -z "$NEW_MASTER" ]; then
  echo "on-failover: no ORC_SUCCESSOR_HOST provided, nothing to do"
  exit 0
fi

echo "on-failover: old=${OLD_MASTER} new=${NEW_MASTER}:${PORT}"

curl -s -X POST "http://haproxy-reloader:8080/failover" \
  -H 'Content-Type: application/json' \
  -d "{\"failed\":\"${OLD_MASTER}\",\"successor\":\"${NEW_MASTER}\",\"port\":${PORT}}"

echo
