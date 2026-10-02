#!/bin/bash
# Run the BehaviorSpace experiments headlessly with NetLogo 7.0.4.
# Usage: ./run-experiments.sh [experiment ...]   (default: all experiments)
# Results are written to Results/<experiment>.csv
# Full design (4 experiments, 60 reps, 1,000,000 moves per run) takes several hours.

NETLOGO="${NETLOGO:-/Applications/NetLogo 7.0.4}"
THREADS="${THREADS:-$(sysctl -n hw.ncpu 2>/dev/null || nproc)}"
export JAVA_HOME="${JAVA_HOME:-$NETLOGO/runtime/Contents/Home}"

cd "$(dirname "$0")"
mkdir -p Results

EXPERIMENTS=("$@")
if [ ${#EXPERIMENTS[@]} -eq 0 ]; then
  EXPERIMENTS=(random-sampling extensive-only extensive-intensive local-density local-density-r2.25
               random-sampling-no-spacing extensive-only-no-spacing extensive-intensive-no-spacing local-density-no-spacing)
fi

for exp in "${EXPERIMENTS[@]}"; do
  echo "$(date '+%H:%M:%S') running $exp"
  "$NETLOGO/netlogo-headless.sh" \
    --model plaice-search-model.nlogox \
    --experiment "$exp" \
    --table "Results/$exp.csv" \
    --threads "$THREADS" || exit 1
done
echo "$(date '+%H:%M:%S') done"
