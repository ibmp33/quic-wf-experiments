# 汇总所有 samples → ML 数据表

import os, json, csv

ROOT = os.path.dirname(os.path.dirname(__file__))
samples_root = os.path.join(ROOT, "samples")

rows = []
for sid in os.listdir(samples_root):
    sdir = os.path.join(samples_root, sid)
    meta_file = os.path.join(sdir, "metadata.json")
    feat_file = os.path.join(sdir, "features.json")
    if not (os.path.exists(meta_file) and os.path.exists(feat_file)):
        continue
    meta = json.load(open(meta_file))
    feats = json.load(open(feat_file))
    row = {"sample_id": sid, "site": meta["site"], "profile": meta["profile"]}
    row.update(feats)
    rows.append(row)

# 写成 CSV，便于用 sklearn/pandas
fieldnames = sorted({k for r in rows for k in r.keys()})
with open(os.path.join(ROOT, "dataset.csv"), "w", newline='') as f:
    w = csv.DictWriter(f, fieldnames=fieldnames)
    w.writeheader()
    for r in rows:
        w.writerow(r)