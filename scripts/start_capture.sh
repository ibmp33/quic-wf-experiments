#!/usr/bin/env bash
set -euo pipefail

# 用法：
#   ./scripts/start_capture.sh <CAPTURE_ROOT> [IFACE]
#
# 参数：
#   CAPTURE_ROOT  - 输出目录，一般是 samples/<sid>/raw
#   IFACE         - 要抓包的网卡，默认 veth-netlab（namespace 方案）

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <CAPTURE_ROOT> [IFACE]" >&2
  exit 1
fi

CAPTURE_ROOT="$1"
IFACE="${2:-veth-netlab}"

mkdir -p "${CAPTURE_ROOT}"

PCAP_FILE="${CAPTURE_ROOT}/capture.pcap"
EBPF_LOG="${CAPTURE_ROOT}/ebpf.log"
TCPDUMP_ERR="${CAPTURE_ROOT}/tcpdump.stderr"
PIDS_FILE="${CAPTURE_ROOT}/pids.txt"

# 清空 pids.txt
: > "${PIDS_FILE}"

echo "[start_capture] CAPTURE_ROOT=${CAPTURE_ROOT}"
echo "[start_capture] IFACE=${IFACE}"

# ----------------------------------------------------------------------
# 1) 启动 tcpdump（抓 veth 接口，只录实验流量）
# ----------------------------------------------------------------------
echo "[start_capture] Starting tcpdump -> ${PCAP_FILE}"

tcpdump -i "${IFACE}" -n \
  --snapshot-length 0 \
  --buffer-size 4096 \
  -w "${PCAP_FILE}" \
  "tcp or udp" \
  2>"${TCPDUMP_ERR}" &

TCPDUMP_PID=$!
echo "tcpdump ${TCPDUMP_PID}" >> "${PIDS_FILE}"

# ----------------------------------------------------------------------
# 2) 启动 eBPF 收集 (可选)
# ----------------------------------------------------------------------
if command -v bpftrace >/dev/null 2>&1; then
  echo "[start_capture] Starting eBPF tracing -> ${EBPF_LOG}"

  bpftrace -e '
tracepoint:tcp:tcp_retransmit_skb { printf("retrans %d -> %d\n", args->sport, args->dport); }
' > "${EBPF_LOG}" 2>&1 &

  EBPF_PID=$!
  echo "ebpf ${EBPF_PID}" >> "${PIDS_FILE}"
else
  echo "[start_capture] bpftrace not found, skip eBPF" | tee "${EBPF_LOG}"
fi

echo "[start_capture] Low-level capture processes started."