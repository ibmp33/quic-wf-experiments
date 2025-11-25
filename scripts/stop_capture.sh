#!/usr/bin/env bash
set -euo pipefail

# 用法：
#   ./scripts/stop_capture.sh <CAPTURE_ROOT>
#
# 其中 CAPTURE_ROOT 一般是：samples/<sid>/raw

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <CAPTURE_ROOT>" >&2
  exit 1
fi

CAPTURE_ROOT="$1"
PIDS_FILE="${CAPTURE_ROOT}/pids.txt"

if [[ ! -f "${PIDS_FILE}" ]]; then
  echo "[stop_capture] No pids.txt found in ${CAPTURE_ROOT}, nothing to stop."
  exit 0
fi

echo "[stop_capture] Stopping processes listed in ${PIDS_FILE} ..."

# 小工具：判断某个 PID 是否还活着
is_alive() {
  local pid="$1"
  if [[ -z "${pid}" ]]; then
    return 1
  fi
  kill -0 "${pid}" 2>/dev/null
}

# 逐行读取：<name> <pid>
while read -r name pid _; do
  # 跳过空行
  [[ -z "${name}" ]] && continue
  [[ -z "${pid}" ]] && continue

  echo "[stop_capture] Handling ${name} (${pid})"

  if ! is_alive "${pid}"; then
    echo "[stop_capture]  - ${name} (${pid}) already exited."
    continue
  fi

  # 先尝试优雅地 TERM
  echo "[stop_capture]  - sending SIGTERM to ${name} (${pid})"
  kill "${pid}" 2>/dev/null || true

  # 等一会儿看它是否退出
  for _ in 1 2 3; do
    sleep 1
    if ! is_alive "${pid}"; then
      echo "[stop_capture]  - ${name} (${pid}) exited after SIGTERM."
      break
    fi
  done

  # 还活着的话，强行 KILL
  if is_alive "${pid}"; then
    echo "[stop_capture]  - ${name} (${pid}) still alive, sending SIGKILL."
    kill -9 "${pid}" 2>/dev/null || true
  fi

  # 最后再检查一下
  if is_alive "${pid}"; then
    echo "[stop_capture]  - WARNING: ${name} (${pid}) still seems alive."
  else
    echo "[stop_capture]  - ${name} (${pid}) stopped."
  fi
done < "${PIDS_FILE}"

echo "[stop_capture] Done."