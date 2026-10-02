#!/usr/bin/env bash
set -euo pipefail
export OMP_DYNAMIC=FALSE
mkdir -p build/validation

for threads in 1 2 4; do
    for spec in "1 0 g" "7 10 g" "4 3 i"; do
        read -r n steps mode <<< "$spec"
        input=/dev/null

        if [[ $mode == i ]]; then input=tests/inputs/noncollinear-4.txt; fi
        timeout 30s ./build/shared-precise 1 "$n" "$steps" 0.01 1 "$mode" \
            < "$input" > build/validation/expected.csv
        timeout 30s ./build/locks-validate "$threads" "$n" "$steps" 0.01 1 "$mode" \
            < "$input" > build/validation/locks.csv 2> build/validation/locks-team.txt
        grep -qx "observed_team=$threads" build/validation/locks-team.txt
        echo "Locks setup: threads=$threads n=$n steps=$steps mode=$mode"
        python3 tools/compare.py build/validation/expected.csv build/validation/locks.csv
    done
done

timeout 30s ./build/locks 2 4 2 0.01 1 g > build/validation/locks-ordinary.txt
timeout 30s ./build/locks-no-output 2 4 2 0.01 1 g > build/validation/locks-timing.txt
test "$(wc -l < build/validation/locks-timing.txt)" -eq 1
grep -q '^Elapsed time = ' build/validation/locks-timing.txt
echo "Locks setup checks passed: 9 comparisons, team sizes and output modes"
