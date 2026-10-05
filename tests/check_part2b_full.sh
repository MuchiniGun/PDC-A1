#!/usr/bin/env bash
set -euo pipefail
export OMP_DYNAMIC=FALSE
output=build/validation/part2b-full
mkdir -p "$output"
passed=0

echo "Tolerances: atol=1e-6 rtol=1e-10; mass must match exactly"
echo "Requested teams: 1 2 4 8 16 32; OMP_DYNAMIC=$OMP_DYNAMIC"

# Include uneven work, more threads than particles, and supplied particle data.
for case_spec in "1 10 g" "2 1 g" "2 10 g" "4 3 g" "7 20 g" \
                 "17 20 g" "64 100 g" "4 3 i" "4 0 g"; do
    read -r n steps mode <<< "$case_spec"
    name="n$n-steps$steps-$mode"
    input=/dev/null
    if [[ $mode == i ]]; then input=tests/inputs/noncollinear-4.txt; fi
    timeout 120s ./build/reference-precise "$n" "$steps" 0.01 1 "$mode" \
        < "$input" > "$output/$name-reference.csv"
    repeats=1
    if [[ $n -eq 64 ]]; then repeats=5; fi

    for variant in basic reduced-default reduced-forces-cyclic reduced-all-cyclic; do
        for threads in 1 2 4 8 16 32; do
            for ((repeat=1; repeat<=repeats; repeat++)); do
                run="$variant-$name-t$threads-r$repeat"
                timeout 120s "./build/part2b-$variant-validate" "$threads" "$n" "$steps" 0.01 1 "$mode" \
                    < "$input" > "$output/$run.csv" 2> "$output/$run-team.txt"
                grep -qx "requested_team=$threads" "$output/$run-team.txt"
                grep -qx "observed_team=$threads" "$output/$run-team.txt"
                echo "$run: observed_team=$threads"
                python3 tools/compare.py "$output/$name-reference.csv" "$output/$run.csv" \
                    --atol 1e-6 --rtol 1e-10
                passed=$((passed + 1))
            done
        done
    done
done

# Check that normal output is not duplicated and timing builds omit states.
timeout 120s ./build/reference-observation 4 3 0.01 1 g > "$output/ordinary-reference.txt"
for variant in basic reduced-default reduced-forces-cyclic reduced-all-cyclic; do
    for threads in 1 2 4 8 16 32; do
        run="$variant-t$threads"
        timeout 120s "./build/part2b-$variant" "$threads" 4 3 0.01 1 g \
            > "$output/$run-ordinary.txt" 2> "$output/$run-ordinary-team.txt"
        diff -u <(sed '/^Elapsed time =/d' "$output/ordinary-reference.txt") \
            <(sed '/^Elapsed time =/d' "$output/$run-ordinary.txt")
        timeout 120s "./build/part2b-$variant-no-output" "$threads" 4 3 0.01 1 g \
            > "$output/$run-timing.txt" 2> "$output/$run-timing-team.txt"
        test "$(wc -l < "$output/$run-timing.txt")" -eq 1
        grep -Eq '^Elapsed time = [0-9.eE+-]+ seconds$' "$output/$run-timing.txt"
        for mode in ordinary timing; do
            grep -qx "requested_team=$threads" "$output/$run-$mode-team.txt"
            grep -qx "observed_team=$threads" "$output/$run-$mode-team.txt"
        done
    done
    timeout 120s "./build/part2b-$variant-no-output" 4 4 3 0.01 1 i \
        < tests/inputs/noncollinear-4.txt > "$output/$variant-input-timing.txt" \
        2> "$output/$variant-input-team.txt"
    test "$(wc -l < "$output/$variant-input-timing.txt")" -eq 1
    grep -Eq '^Elapsed time = [0-9.eE+-]+ seconds$' "$output/$variant-input-timing.txt"
    grep -qx 'requested_team=4' "$output/$variant-input-team.txt"
    grep -qx 'observed_team=4' "$output/$variant-input-team.txt"
    echo "$variant: 78 comparisons, team sizes and output modes passed"
done
echo "Part 2B validation passed: $passed comparisons across 4 variants; team sizes and output modes passed"
