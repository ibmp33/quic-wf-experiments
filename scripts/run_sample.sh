#!/usr/bin/env bash
set -euo pipefail

# 用法：
#   ./scripts/run_sample.sh <SITE> <PROFILE> <RUN_ID> <URL> [NS_NAME]
#
# 示例：
#   ./scripts/run_sample.sh youtube rtt40l1e-3 1 "https://www.youtube.com" netlab
#
# 假设：
#   - 已经运行过 sudo ./scripts/create_ns.sh netlab
#   - apply_net_profile.sh / run_in_ns.sh / start_capture.sh / stop_capture.sh /
#     dump_sysinfo.py / capture_netlog.py 都已经在 scripts/ 目录下

if [[ $# -lt 4 ]]; then
  echo "Usage: $0 <SITE> <PROFILE> <RUN_ID> <URL> [NS_NAME]" >&2
  exit 1
fi

SITE="$1"
PROFILE="$2"
RUN_ID="$3"
URL="$4"
NS_NAME="${5:-netlab}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SAMPLE_ID="${SITE}-net-${PROFILE}-run${RUN_ID}"
SAMPLES_DIR="${ROOT}/samples"
SAMPLE_DIR="${SAMPLES_DIR}/${SAMPLE_ID}"
CAPTURE_ROOT="${SAMPLE_DIR}/raw"

mkdir -p "${CAPTURE_ROOT}"

echo "[run_sample] SAMPLE_ID=${SAMPLE_ID}"
echo "[run_sample] SITE=${SITE}"
echo "[run_sample] PROFILE=${PROFILE}"
echo "[run_sample] RUN_ID=${RUN_ID}"
echo "[run_sample] URL=${URL}"
echo "[run_sample] NS_NAME=${NS_NAME}"
echo "[run_sample] SAMPLE_DIR=${SAMPLE_DIR}"

# ----------------------------------------------------------------------
# 1) 应用网络 profile（只影响 veth-NS_NAME，不动宿主 eth0）
# ----------------------------------------------------------------------
echo "[run_sample] Applying net profile..."
sudo "${ROOT}/scripts/apply_net_profile.sh" "${PROFILE}" "${NS_NAME}"

# ----------------------------------------------------------------------
# 2) 启动底层抓包（针对 veth-NS_NAME）
# ----------------------------------------------------------------------
VETH_IFACE="veth-${NS_NAME}"
echo "[run_sample] Starting capture on ${VETH_IFACE} ..."
"${ROOT}/scripts/start_capture.sh" "${CAPTURE_ROOT}" "${VETH_IFACE}"

# ----------------------------------------------------------------------
# 3) 写 sysinfo.json（host 视角）
# ----------------------------------------------------------------------
if [[ -f "${ROOT}/scripts/dump_sysinfo.py" ]]; then
  echo "[run_sample] Dumping sysinfo..."
  python3 "${ROOT}/scripts/dump_sysinfo.py" "${CAPTURE_ROOT}/sysinfo.json"
else
  echo "[run_sample] WARN: dump_sysinfo.py not found, skip sysinfo."
fi

# ----------------------------------------------------------------------
# 4) 在 ns 里访问 URL，采集 NetLog / DevTools / sslkeys
# ----------------------------------------------------------------------
NETLOG_PATH="${CAPTURE_ROOT}/netlog.json"
DEVTOOLS_PATH="${CAPTURE_ROOT}/devtools-performance.json"
SSLKEYLOG="${CAPTURE_ROOT}/sslkeys.log"

echo "[run_sample] Running capture_netlog.py inside ns=${NS_NAME} ..."

if [[ ! -f "${ROOT}/scripts/capture_netlog.py" ]]; then
  echo "[run_sample] ERROR: capture_netlog.py not found in scripts/"
  exit 1
fi

"${ROOT}/scripts/run_in_ns.sh" "${NS_NAME}" \
  python3 "${ROOT}/scripts/capture_netlog.py" \
    --url "${URL}" \
    --site "${SITE}" \
    --profile "${PROFILE}" \
    --output-netlog "${NETLOG_PATH}" \
    --output-devtools "${DEVTOOLS_PATH}" \
    --ssl-key-log "${SSLKEYLOG}" \
    --headless

# ----------------------------------------------------------------------
# 5) 停止底层抓包（tcpdump / eBPF）
# ----------------------------------------------------------------------
echo "[run_sample] Stopping capture..."
"${ROOT}/scripts/stop_capture.sh" "${CAPTURE_ROOT}"

# ----------------------------------------------------------------------
# 6) 写 metadata.json
# ----------------------------------------------------------------------
echo "[run_sample] Writing metadata.json..."

python3 - <<EOF
import json, time, os, pathlib
sample_dir = ${SAMPLE_DIR!r}
pathlib.Path(sample_dir).mkdir(parents=True, exist_ok=True)
meta = {
    "sample_id": ${SAMPLE_ID!r},
    "site": ${SITE!r},
    "profile": ${PROFILE!r},
    "run_id": ${RUN_ID!r},
    "url": ${URL!r},
    "ns_name": ${NS_NAME!r},
    "timestamp": time.time(),
}
out_path = os.path.join(sample_dir, "metadata.json")
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(meta, f, indent=2, ensure_ascii=False)
EOF

# 7) notes 占位
touch "${CAPTURE_ROOT}/notes.txt"

echo "[run_sample] Sample ${SAMPLE_ID} finished."