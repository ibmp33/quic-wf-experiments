# 用 subprocess 调 tshark
# tshark -r capture.pcap -T fields \
#   -e frame.time_epoch -e ip.src -e ip.dst -e udp.srcport -e udp.dstport -e frame.len \
#   -Y "udp && (udp.port == 443 || udp.port == 80)" \
#   > packets.tsv
# [
#   { "t": 0.000, "dir": "out", "size": 1250 },
#   { "t": 0.012, "dir": "in",  "size": 1375 },
#   ...
# ]

# scripts/extract_features.py
# 计算你关心的 WF 特征（第 3-4 层）
# 比如：
# 	•	IAT stats：mean/var/max
# 	•	IAT histogram（分桶）
# 	•	burst stats（连续同向包的长度总和/包数）
# 	•	sliding windows（每 50ms / 100ms 内 bytes count）
# 	•	前 K 个包的 size 序列
# 	•	上/下行总字节数、比率
# 	•	request-response phase pattern（简单做：找第一个大下行 burst）

import json, os
from your_lib import parse_packets, compute_features

ROOT = os.path.dirname(os.path.dirname(__file__))
samples_root = os.path.join(ROOT, "samples")

for sid in os.listdir(samples_root):
    sdir = os.path.join(samples_root, sid)
    raw_pcap = os.path.join(sdir, "raw", "capture.pcap")
    if not os.path.exists(raw_pcap):
        continue
    print("[*] extracting features for", sid)
    packets = parse_packets(raw_pcap)   # 内部用 tshark 输出再读
    feats = compute_features(packets)
    with open(os.path.join(sdir, "features.json"), "w") as f:
        json.dump(feats, f, indent=2)