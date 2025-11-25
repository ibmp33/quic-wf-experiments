# scripts/generate_plan.py
import json, itertools, csv

sites = [line.strip() for line in open('config/sites.txt') if line.strip()]
profiles = json.load(open('config/net_profiles.json'))
runs_per_case = 5   # 每个 (site, profile) 跑多少次

with open('config/experiment_plan.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['sample_id', 'site', 'profile', 'run'])
    for site, prof in itertools.product(sites, profiles):
        for run in range(1, runs_per_case+1):
            sid = f"{site.split('.')[0]}-net-{prof['name']}-run{run:02d}"
            w.writerow([sid, site, prof['name'], run])