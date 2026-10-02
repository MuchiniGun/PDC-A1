#!/usr/bin/env bash
set -euo pipefail
export OMP_DYNAMIC=FALSE
output=build/validation/locks
mkdir -p "$output"
passed=0
for spec in "7 20 g" "64 100 g" "4 3 i"; do
    read -r n steps mode <<< "$spec"
    input=/dev/null
    if [[ $mode == i ]]; then input=tests/inputs/noncollinear-4.txt; fi
    name="n$n-steps$steps-$mode"
    timeout 120s ./build/shared-precise 1 "$n" "$steps" 0.01 1 "$mode" \
        < "$input" > "$output/$name-reference.csv"
    for threads in 1 4 16 32; do
        for repeat in 1 2 3; do
            run="$name-t$threads-r$repeat"
            timeout 120s ./build/locks-validate "$threads" "$n" "$steps" 0.01 1 "$mode" \
                < "$input" > "$output/$run.csv" 2> "$output/$run-team.txt"
            grep -qx "observed_team=$threads" "$output/$run-team.txt"
            echo "$run: observed_team=$threads"
            python3 tools/compare.py "$output/$name-reference.csv" "$output/$run.csv"
            passed=$((passed + 1))
        done
    done
done
echo "Particle-lock checks passed: $passed repeated comparisons and team sizes"
