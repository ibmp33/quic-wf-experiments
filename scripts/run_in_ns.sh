#!/usr/bin/env bash
set -euo pipefail

# 用法：
#   ./scripts/run_in_ns.sh <NS_NAME> <command...>
#
# 示例：
#   ./scripts/run_in_ns.sh netlab bash
#   ./scripts/run_in_ns.sh netlab python3 scripts/capture_netlog.py ...

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <NS_NAME> <command...>" >&2
  exit 1
fi

NS_NAME="$1"
shift

echo "[run_in_ns] ns=${NS_NAME} cmd=$*"
exec ip netns exec "${NS_NAME}" "$@"