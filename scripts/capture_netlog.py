#!/usr/bin/env python3
"""
capture_netlog.py

启动 Chrome，并通过 DevTools Protocol (CDP) 采集：
- NetLog (chrome 启动参数 --log-net-log)
- DevTools Performance trace (CDP Tracing domain)
- SSL key log (--ssl-key-log-file)
运行时间 ≈ Chrome 启动 + DevTools 就绪（最多 20s） + trace_duration + 2s + 关浏览器

依赖：
    pip install websocket-client
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
import socket
from contextlib import closing
from urllib.request import urlopen
from urllib.error import URLError

import websocket  # type: ignore


def find_free_port() -> int:
    """找一个本地可用的 TCP 端口，用作 Chrome remote-debugging-port。"""
    with closing(socket.socket(socket.AF_INET, socket.SOCK_STREAM)) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def wait_for_devtools(port: int, timeout: float = 15.0) -> str:
    """
    等待 Chrome DevTools HTTP 接口就绪，并返回第一个 page 的 WebSocket URL。
    """
    deadline = time.time() + timeout
    version_url = f"http://127.0.0.1:{port}/json/version"
    list_url = f"http://127.0.0.1:{port}/json"

    while time.time() < deadline:
        try:
            # 先试 /json/version 看服务是否 up
            with urlopen(version_url, timeout=1) as resp:
                _ = resp.read()
        except URLError:
            time.sleep(0.3)
            continue
        except Exception:
            time.sleep(0.3)
            continue

        # 再拿 /json 列表
        try:
            with urlopen(list_url, timeout=2) as resp:
                data = resp.read().decode("utf-8", errors="replace")
                targets = json.loads(data)
        except Exception:
            time.sleep(0.3)
            continue

        # 找第一个 type == "page" 的 target
        for t in targets:
            if t.get("type") == "page" and "webSocketDebuggerUrl" in t:
                return t["webSocketDebuggerUrl"]

        time.sleep(0.3)

    raise RuntimeError(f"DevTools endpoint not ready on port {port}")


def cdp_send(ws: websocket.WebSocket, msg_id: int, method: str, params=None):
    """发送一个 CDP 命令。"""
    payload = {"id": msg_id, "method": method}
    if params is not None:
        payload["params"] = params
    ws.send(json.dumps(payload))
    return msg_id


def run_tracing(ws: websocket.WebSocket, duration: float = 10.0):
    """
    使用 CDP Tracing 收集一段时间的性能 trace。

    策略：
      - Tracing.start(transferMode="ReportEvents")
      - 等 duration 秒
      - Tracing.end
      - 收集所有 Tracing.dataCollected 的内容
    """
    msg_id = 1
    events = []

    # 启动 tracing
    cdp_send(
        ws,
        msg_id,
        "Tracing.start",
        params={
            "categories": "devtools.timeline,disabled-by-default-devtools.timeline,"
                          "toplevel,blink.user_timing,loading,netlog",
            "options": "record-as-much-as-possible",
            "bufferUsageReportingInterval": 1000,
            "transferMode": "ReportEvents",
        },
    )
    msg_id += 1

    tracing_started = False
    tracing_ended = False
    end_sent = False
    start_time = time.time()

    ws.settimeout(1.0)

    while True:
        # 超时保护
        now = time.time()
        if now - start_time > duration and not end_sent:
            # 发送 Tracing.end
            cdp_send(ws, msg_id, "Tracing.end")
            msg_id += 1
            end_sent = True

        if tracing_ended:
            break

        try:
            raw = ws.recv()
        except websocket.WebSocketTimeoutException:
            continue
        except Exception:
            # 连接断了就退出
            break

        try:
            msg = json.loads(raw)
        except Exception:
            continue

        # 处理事件
        method = msg.get("method")
        if method == "Tracing.tracingStartedInBrowser":
            tracing_started = True

        if method == "Tracing.dataCollected":
            # dataCollected 的 params.value 里是一组 event
            chunk = msg.get("params", {}).get("value", [])
            if isinstance(chunk, list):
                events.extend(chunk)

        if method == "Tracing.tracingComplete":
            tracing_ended = True

    return events


def launch_chrome(
    chrome_binary: str,
    url: str,
    netlog_path: str,
    ssl_key_log: str,
    remote_debug_port: int,
    user_data_dir: str,
    headless: bool = False,
):
    """启动 Chrome 进程，返回 Popen 对象。"""
    args = [
        chrome_binary,
        f"--user-data-dir={user_data_dir}",
        f"--remote-debugging-port={remote_debug_port}",
        "--no-first-run",
        "--disable-popup-blocking",
        "--disable-background-networking",
        "--disable-background-timer-throttling",
        "--disable-default-apps",
        "--disable-extensions",
        "--disable-sync",
        "--disable-translate",
        "--metrics-recording-only",
        "--safebrowsing-disable-auto-update",
        "--disable-features=Translate,BackForwardCache",
        f"--log-net-log={netlog_path}",
        "--log-net-log-capture-mode=Everything",
        f"--ssl-key-log-file={ssl_key_log}",
    ]

    if headless:
        args.append("--headless=new")

    args.append(url)

    proc = subprocess.Popen(
        args,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return proc


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True, help="要访问的 URL")
    parser.add_argument("--site", required=False, help="站点逻辑名（可选）")
    parser.add_argument("--profile", required=False, help="网络 profile 名（可选）")
    parser.add_argument("--output-netlog", required=True, help="netlog.json 输出路径")
    parser.add_argument(
        "--output-devtools", required=True, help="DevTools performance trace 输出路径"
    )
    parser.add_argument(
        "--ssl-key-log", required=True, help="SSL key log 输出路径 (sslkeys.log)"
    )
    parser.add_argument(
        "--chrome-binary",
        default="google-chrome",
        help="Chrome 可执行文件路径（默认 google-chrome）",
    )
    parser.add_argument(
        "--headless",
        action="store_true",
        help="是否使用 headless 模式跑 Chrome",
    )
    parser.add_argument(
        "--trace-duration",
        type=float,
        default=15.0,
        help="Tracing 持续时间（秒），默认 15s",
    )
    args = parser.parse_args()

    # 确保输出目录存在
    os.makedirs(os.path.dirname(args.output_netlog), exist_ok=True)
    os.makedirs(os.path.dirname(args.output_devtools), exist_ok=True)
    os.makedirs(os.path.dirname(args.ssl_key_log), exist_ok=True)

    # 选择 remote debugging 端口
    port = find_free_port()

    # 为这次实验创建专属的 user-data-dir
    with tempfile.TemporaryDirectory(prefix="chrome-profile-") as tmp_profile:
        print(f"[*] Launching Chrome on port {port} ...", file=sys.stderr)
        chrome_proc = launch_chrome(
            chrome_binary=args.chrome_binary,
            url=args.url,
            netlog_path=args.output_netlog,
            ssl_key_log=args.ssl_key_log,
            remote_debug_port=port,
            user_data_dir=tmp_profile,
            headless=args.headless,
        )

        try:
            # 等 DevTools endpoint
            ws_url = wait_for_devtools(port, timeout=20.0)
            print(f"[*] DevTools WS endpoint: {ws_url}", file=sys.stderr)

            # 连接 WebSocket
            ws = websocket.create_connection(ws_url, timeout=5)
        except Exception as e:
            print(f"[!] Failed to connect DevTools: {e}", file=sys.stderr)
            chrome_proc.terminate()
            chrome_proc.wait(timeout=10)
            sys.exit(1)

        # 启用 Page/Network（可选）
        msg_id = 1
        cdp_send(ws, msg_id, "Page.enable")
        msg_id += 1
        cdp_send(ws, msg_id, "Network.enable")
        msg_id += 1

        # 开始 tracing
        print(
            f"[*] Starting DevTools tracing for {args.trace_duration:.1f}s ...",
            file=sys.stderr,
        )
        events = []
        try:
            events = run_tracing(ws, duration=args.trace_duration)
        finally:
            try:
                ws.close()
            except Exception:
                pass

        print(
            f"[*] Collected {len(events)} tracing events, writing to {args.output_devtools}",
            file=sys.stderr,
        )

        # 写 devtools-performance.json
        with open(args.output_devtools, "w", encoding="utf-8") as f:
            json.dump(
                {
                    "url": args.url,
                    "site": args.site,
                    "profile": args.profile,
                    "traceEvents": events,
                },
                f,
                indent=2,
                ensure_ascii=False,
            )

        # 给 Chrome 一点时间把 netlog / sslkeys 刷盘
        time.sleep(2.0)
        print("[*] Stopping Chrome...", file=sys.stderr)
        chrome_proc.terminate()
        try:
            chrome_proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            chrome_proc.kill()

        print("[*] capture_netlog.py done.", file=sys.stderr)


if __name__ == "__main__":
    main()