#!/usr/bin/env bash
set -euo pipefail

# 用法：
#   sudo ./scripts/create_ns.sh [NS_NAME]
#
# 默认 NS_NAME=netlab

# sudo ./scripts/create_ns.sh        # 创建 netlab
# sudo ip netns exec netlab ping -c 3 8.8.8.8

NS_NAME="${1:-netlab}"
VETH_HOST="veth-${NS_NAME}"
VETH_NS="veth-${NS_NAME}-ns"
SUBNET="10.200.1.0/24"
IP_HOST="10.200.1.1/24"
IP_NS="10.200.1.2/24"

echo "[create_ns] Creating netns '${NS_NAME}'"

# 找默认出网接口（例如 eth0 / ens33 / wlan0）
UPLINK_IF=$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')

if [[ -z "${UPLINK_IF}" ]]; then
  echo "[create_ns] ERROR: cannot detect uplink interface via 'ip route get 1.1.1.1'"
  exit 1
fi

echo "[create_ns] UPLINK_IF=${UPLINK_IF}"

# 如果已存在，先删旧 ns / veth，避免脏状态
ip link del "${VETH_HOST}" 2>/dev/null || true
ip netns del "${NS_NAME}" 2>/dev/null || true

# 1) 创建 netns
ip netns add "${NS_NAME}"

# 2) 创建 veth pair
ip link add "${VETH_HOST}" type veth peer name "${VETH_NS}"

# 3) host 这边配置 IP
ip addr add "${IP_HOST}" dev "${VETH_HOST}"
ip link set "${VETH_HOST}" up

# 4) 把另一端塞进 netns 里
ip link set "${VETH_NS}" netns "${NS_NAME}"

# 5) 在 netns 内配置 IP / route
ip netns exec "${NS_NAME}" ip addr add "${IP_NS}" dev "${VETH_NS}"
ip netns exec "${NS_NAME}" ip link set "${VETH_NS}" up
ip netns exec "${NS_NAME}" ip link set lo up
ip netns exec "${NS_NAME}" ip route add default via 10.200.1.1

# 6) host 开 ip_forward + NAT
sysctl -w net.ipv4.ip_forward=1 >/dev/null

# 清理旧 NAT 规则（如果有）
iptables -t nat -D POSTROUTING -s "${SUBNET}" -o "${UPLINK_IF}" -j MASQUERADE 2>/dev/null || true
iptables -t nat -A POSTROUTING -s "${SUBNET}" -o "${UPLINK_IF}" -j MASQUERADE

echo "[create_ns] netns '${NS_NAME}' ready:"
echo "  host side : ${VETH_HOST} (${IP_HOST})"
echo "  ns side   : ${VETH_NS} (${IP_NS})"
echo "  test: sudo ip netns exec ${NS_NAME} ping -c 3 8.8.88"