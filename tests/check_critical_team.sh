#!/usr/bin/env bash
set -euo pipefail
export OMP_DYNAMIC=FALSE
mkdir -p build/validation

for threads in 1 2 4; do
    for repeat in 1 2 3; do
        for n in 1 7; do
            timeout 30s ./build/shared-precise 1 "$n" 10 0.01 1 g > build/validation/expected.csv
            timeout 30s ./build/critical-validate "$threads" "$n" 10 0.01 1 g \
                > build/validation/critical.csv 2> build/validation/team.txt
            grep -qx "observed_team=$threads" build/validation/team.txt
            echo "Team=$threads repeat=$repeat n=$n"
            python3 tools/compare.py build/validation/expected.csv build/validation/critical.csv
        done
    done
    timeout 30s ./build/shared-precise 1 4 3 0.01 1 i \
        < tests/inputs/noncollinear-4.txt > build/validation/expected.csv
    timeout 30s ./build/critical-validate "$threads" 4 3 0.01 1 i \
        < tests/inputs/noncollinear-4.txt > build/validation/critical.csv 2> build/validation/team.txt
    grep -qx "observed_team=$threads" build/validation/team.txt
    echo "Team=$threads non-collinear input"
    python3 tools/compare.py build/validation/expected.csv build/validation/critical.csv

    # Normal output must occur once, independently of the number of threads.
    timeout 30s ./build/critical 1 4 3 0.01 1 g > build/validation/normal-one.txt
    timeout 30s ./build/critical "$threads" 4 3 0.01 1 g > build/validation/normal-team.txt
    diff -u <(sed '/^Elapsed time =/d' build/validation/normal-one.txt) \
        <(sed '/^Elapsed time =/d' build/validation/normal-team.txt)
    timeout 30s ./build/critical-no-output "$threads" 4 3 0.01 1 g > build/validation/timing.txt
    test "$(wc -l < build/validation/timing.txt)" -eq 1
    grep -q '^Elapsed time = ' build/validation/timing.txt
done
echo "Persistent-team checks passed: requested teams observed, reference agreement, no duplicated output"
