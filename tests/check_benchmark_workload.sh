#!/usr/bin/env bash
set -euo pipefail
export OMP_DYNAMIC=FALSE

# Read the benchmark settings so validation uses the same workload.
read -r n steps delta_t threads <<< "$(python3 -B -c '
import json, sys
sys.path.insert(0, "tools")
from benchmark import validate_config
config = json.load(open("bench/config.json"))
validate_config(config)
print(config["n"], config["n_steps"], config["delta_t"], *config["threads"])
')"
output="build/validation/benchmark-workload-n$n-steps$steps-dt$delta_t"
mkdir -p "$output"
echo "Workload: n=$n steps=$steps delta_t=$delta_t teams=$threads"

# Compare the initial and final states without printing every timestep.
timeout 120s ./build/reference-precise "$n" "$steps" "$delta_t" "$steps" g \
    > "$output/reference.csv"
passed=0
for variant in basic reduced-default reduced-forces-cyclic reduced-all-cyclic; do
    for team in $threads; do
        name="$variant-t$team"
        timeout 120s "./build/part2b-$variant-validate" "$team" "$n" "$steps" "$delta_t" "$steps" g \
            > "$output/$name.csv" 2> "$output/$name-team.txt"
        grep -qx "requested_team=$team" "$output/$name-team.txt"
        grep -qx "observed_team=$team" "$output/$name-team.txt"
        echo "$name: observed_team=$team"
        python3 tools/compare.py "$output/reference.csv" "$output/$name.csv" --atol 1e-6 --rtol 1e-10
        passed=$((passed + 1))
    done
done
echo "Benchmark workload validation passed: $passed comparisons; finite states and team sizes checked"
