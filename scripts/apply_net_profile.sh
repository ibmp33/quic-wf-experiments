#!/usr/bin/env bash
set -euo pipefail
	# •	输入一个 profile 名（例如 rtt40l1e-3）
	# •	根据预定义的规则解析出：
	# •	RTT（ms）
	# •	丢包率（loss）
	# •	带宽（可选）
	# •	然后对 指定网卡（默认 eth0） 施加 tc netem + tbf 等规则
        # rtt40l1e-3    RTT 40ms, loss = 1e-3
        # rtt80l0       RTT 80ms, no loss
        # rtt20l5e-4    RTT 20ms, loss 5e-4
# 用法：
#   sudo ./scripts/apply_net_profile.sh <PROFILE> [NS_NAME]
#
# 示例：
#   sudo ./scripts/apply_net_profile.sh rtt40l1e-3 netlab

PROFILE="$1"
NS_NAME="${2:-netlab}"
VETH_HOST="veth-${NS_NAME}"

echo "[apply_net_profile] Profile='${PROFILE}' on ${VETH_HOST} (ns=${NS_NAME})"

# 检查 veth 是否存在
if ! ip link show "${VETH_HOST}" >/dev/null 2>&1; then
  echo "[apply_net_profile] ERROR: ${VETH_HOST} not found. Did you run create_ns.sh ${NS_NAME} ?"
  exit 1
fi

# ----------------------------
# 解析 RTT
# ----------------------------
if [[ "$PROFILE" =~ rtt([0-9]+) ]]; then
    RTT_MS="${BASH_REMATCH[1]}"
else
    echo "[apply_net_profile] WARN: cannot parse RTT, default RTT=0ms"
    RTT_MS=0
fi

# ----------------------------
# 解析 loss
#   l1e-3   -> 1e-3
#   l0      -> 0
#   l5e-4   -> 5e-4
#   l1      -> 1%
# ----------------------------
LOSS="0"
if [[ "$PROFILE" =~ l([0-9]+(e-?[0-9]+)?) ]]; then
    LOSS_RAW="${BASH_REMATCH[1]}"
    if [[ "$LOSS_RAW" == *e* ]]; then
        LOSS="${LOSS_RAW}"
    else
        LOSS="${LOSS_RAW}%"
    fi
fi

echo "[apply_net_profile] Parsed:"
echo "  RTT  = ${RTT_MS} ms"
echo "  loss = ${LOSS}"

# ----------------------------
# 清理旧 qdisc
# ----------------------------
echo "[apply_net_profile] Clearing existing qdisc on ${VETH_HOST} ..."
tc qdisc del dev "${VETH_HOST}" root 2>/dev/null || true

# ----------------------------
# 应用 netem
# ----------------------------
NETEM_CMD=(tc qdisc add dev "${VETH_HOST}" root netem delay "${RTT_MS}ms" loss "${LOSS}")
echo "[apply_net_profile] Running: ${NETEM_CMD[*]}"
"${NETEM_CMD[@]}"

echo "[apply_net_profile] Done."