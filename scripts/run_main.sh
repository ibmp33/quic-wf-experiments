#!/usr/bin/env bash
set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

while IFS=, read -r sample_id site profile run; do
  [ "$sample_id" = "sample_id" ] && continue
  "$ROOT/scripts/run_sample.sh" "$sample_id" "$site" "$profile"
done < "$ROOT/config/experiment_plan.csv"