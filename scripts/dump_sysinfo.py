#!/usr/bin/env python3
"""
dump_sysinfo.py — 流量分析专用系统信息收集

记录与网络性能 / QUIC / TCP / WF 实验相关的关键 OS 状态。
"""

import argparse
import json
import os
import platform
import subprocess
from pathlib import Path


def run(cmd):
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.DEVNULL)
        return out.decode("utf-8", errors="replace").strip()
    except Exception:
        return ""


def read(path):
    try:
        return Path(path).read_text(errors="replace")
    except Exception:
        return ""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output", help="sysinfo.json 输出路径")
    args = parser.parse_args()

    info = {}

    # -----------------------------------------------------
    # 1) 基本平台信息
    # -----------------------------------------------------
    info["platform"] = {
        "system": platform.system(),
        "release": platform.release(),
        "version": platform.version(),
        "machine": platform.machine(),
        "python": platform.python_version(),
        "uname": list(platform.uname()),
    }

    # -----------------------------------------------------
    # 2) CPU / scheduler 状态（影响 pacing、flows）
    # -----------------------------------------------------
    info["cpu"] = {
        "lscpu": run(["lscpu"]),
        "cpuinfo": read("/proc/cpuinfo"),
        "scaling_governor": read("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"),
        "scaling_driver": read("/sys/devices/system/cpu/cpu0/cpufreq/scaling_driver"),
    }

    # -----------------------------------------------------
    # 3) 网络 sysctl（我们关心 net.*）
    # -----------------------------------------------------
    info["sysctl_net"] = run(["sysctl", "-a"])

    # -----------------------------------------------------
    # 4) /proc/net (conntrack, tcp, udp)
    # -----------------------------------------------------
    info["proc_net"] = {
        "tcp": read("/proc/net/tcp"),
        "udp": read("/proc/net/udp"),
        "snmp": read("/proc/net/snmp"),
        "netstat": read("/proc/net/netstat"),
    }

    # -----------------------------------------------------
    # 5) 网卡配置 / 统计（ethtool -k / -S）
    # -----------------------------------------------------
    info["nic"] = {
        "ip_addr": run(["ip", "addr"]),
        "ip_link": run(["ip", "link"]),
        "ip_route": run(["ip", "route"]),
        "ethtool_k": run(["ethtool", "-k", "eth0"]),
        "ethtool_S": run(["ethtool", "-S", "eth0"]),
    }

    # -----------------------------------------------------
    # 6) 中断 / softirq（网络延迟抖动的关键信号）
    # -----------------------------------------------------
    info["interrupts"] = read("/proc/interrupts")
    info["softirqs"] = read("/proc/softirqs")

    # -----------------------------------------------------
    # 7) 内核命令行（影响 BBR / pacing / timer frequency）
    # -----------------------------------------------------
    info["cmdline"] = read("/proc/cmdline")

    # -----------------------------------------------------
    # 8) 内存状态（影响 page cache 和 chrome 行为）
    # -----------------------------------------------------
    info["meminfo"] = read("/proc/meminfo")

    # -----------------------------------------------------
    # 写文件
    # -----------------------------------------------------
    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(info, indent=2), encoding="utf-8")

    print(f"[dump_sysinfo] wrote {args.output}")


if __name__ == "__main__":
    main()