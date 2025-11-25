# quic-wf-experiments

chmod +x scripts/create_ns.sh
chmod +x scripts/apply_net_profile.sh
chmod +x scripts/run_in_ns.sh
chmod +x scripts/start_capture.sh
chmod +x scripts/stop_capture.sh
chmod +x scripts/run_sample.sh

sudo ./scripts/create_ns.sh netlab
./scripts/run_sample.sh baidu rtt40l1e-3 1 "https://www.baidu.com" netlab

tree samples/
cat samples/baidu-net-rtt40l1e-3-run1/raw/sysinfo.json
tshark -r samples/.../capture.pcap