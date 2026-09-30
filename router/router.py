#!/usr/bin/env python3

import argparse
import subprocess
import sys
import shutil

HOST = "127.0.0.1"
USER = "app"
PASSWORD = "apppass"

SHARDS = {
    "A": {"write": 13306, "read": 13307},
    "B": {"write": 13316, "read": 13317},
}


def mysql_binary():
    path = shutil.which("mysql")
    if not path:
        sys.exit("mysql client not found in PATH")
    return path


def escape(value):
    return str(value).replace("\\", "\\\\").replace("'", "\\'")


def run_sql(port, sql):
    cmd = [
        mysql_binary(),
        f"-h{HOST}",
        f"-P{port}",
        f"-u{USER}",
        f"-p{PASSWORD}",
        "-N",
        "-B",
        "-e",
        sql,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"query failed on port {port}:\n{result.stderr.strip()}")
    return result.stdout.strip()


def shard_for(customer_id):
    return "A" if int(customer_id) % 2 == 0 else "B"


def cmd_put(args):
    shard = shard_for(args.customer_id)
    port = SHARDS[shard]["write"]
    sql = (
        "INSERT INTO shop.customers (customer_id, name, email) VALUES ("
        f"{int(args.customer_id)}, '{escape(args.name)}', '{escape(args.email)}')"
    )
    run_sql(port, sql)
    print(f"customer {args.customer_id} -> Shard {shard} (write port {port})")


def cmd_get(args):
    shard = shard_for(args.customer_id)
    port = SHARDS[shard]["read"]
    sql = (
        "SELECT customer_id, name, email FROM shop.customers "
        f"WHERE customer_id = {int(args.customer_id)}"
    )
    out = run_sql(port, sql)
    print(out if out else f"customer {args.customer_id} not found in Shard {shard}")
    print(f"(read from Shard {shard}, port {port})")


def cmd_list(_args):
    for shard, ports in SHARDS.items():
        out = run_sql(ports["read"], "SELECT customer_id, name FROM shop.customers ORDER BY customer_id")
        print(f"--- Shard {shard} (read port {ports['read']}) ---")
        print(out if out else "(empty)")


def main():
    parser = argparse.ArgumentParser(description="Shard router (customer_id % 2)")
    sub = parser.add_subparsers(dest="command", required=True)

    p_put = sub.add_parser("put", help="insert a customer into its shard")
    p_put.add_argument("customer_id", type=int)
    p_put.add_argument("name")
    p_put.add_argument("email")
    p_put.set_defaults(func=cmd_put)

    p_get = sub.add_parser("get", help="read a customer from its shard replica")
    p_get.add_argument("customer_id", type=int)
    p_get.set_defaults(func=cmd_get)

    p_list = sub.add_parser("list", help="list customers per shard")
    p_list.set_defaults(func=cmd_list)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
