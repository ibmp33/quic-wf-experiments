<site>-net<profile>-run<index>

例如：
youtube-net-rtt40l1e-3    # 第3次访问 youtube，RTT40ms，loss=1e-3
wiki-net-rtt80l0-1        # 第1次访问 wikipedia，RTT80ms，无丢包

├── samples/               # 每次访问对应一个 sample 目录
│   └── <sample-id>/       # e.g., site-yt-net-rtt40-loss0.01-run01
│        ├── raw/
│        │   ├── capture.pcap
│        │   ├── netlog.json
│        │   ├── devtools-performance.json
│        │   ├── sslkeys.log
│        │   ├── ebpf.log              # 可选：rtt/retrans/softirq
│        │   ├── sysinfo.json          # OS/CPU/内核信息快照
│        │   └── notes.txt             # 手写备注（可选）
│        ├── metadata.json             # 该 sample 的标签/环境
│        ├── features.json             # 该 sample 提取后的特征
│        └── timeline.csv              # 跨层时间线（可选）


从工程角度：
	1.	config/sites.txt + net_profiles.json → generate_plan.py → experiment_plan.csv
	2.	run_sample.sh + start_capture.sh → 生成 samples/<sid>/raw/* + metadata.json
	3.	extract_features.py → samples/<sid>/features.json
	4.	build_dataset.py → dataset.csv
	5.	analysis/*.py → 各种图表 & WF 实验结果

从研究角度：
	•	pcap + NetLog + DevTools = ground truth for QUIC behavior & page load
	•	eBPF = OS/CPU/softirq side-channel，帮你判断 trace 差异是不是 OS 搞的
	•	metadata = 环境标签（RTT/loss/bandwidth/CPU 状态）
	•	features = WF 特征（老的 + 机制驱动的新特征）
	•	dataset = 做分类 & 鲁棒性分析的输入