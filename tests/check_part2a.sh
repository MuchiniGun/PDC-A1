#!/usr/bin/env bash
set -euo pipefail
export OMP_DYNAMIC=FALSE
variant=${1:-critical}
case "$variant" in
    critical|locks) ;;
    *) echo "Expected critical or locks" >&2; exit 1 ;;
esac
output="build/validation/$variant-full"
mkdir -p "$output"
passed=0

# Keep each result so a failed case can be inspected without rerunning it.
for case_spec in "1 10 g" "2 1 g" "2 10 g" "4 3 g" "7 20 g" \
                 "17 20 g" "64 100 g" "4 3 i" "4 0 g"; do
    read -r n steps mode <<< "$case_spec"
    name="n$n-steps$steps-$mode"
    input=/dev/null
    if [[ $mode == i ]]; then input=tests/inputs/noncollinear-4.txt; fi
    timeout 120s ./build/shared-precise 1 "$n" "$steps" 0.01 1 "$mode" \
        < "$input" > "$output/$name-reference.csv"
    repeats=1
    if [[ $n -eq 64 ]]; then repeats=5; fi

    for threads in 1 2 4 8 16 32; do
        for ((repeat=1; repeat<=repeats; repeat++)); do
            run="$name-t$threads-r$repeat"
            timeout 120s "./build/$variant-validate" "$threads" "$n" "$steps" 0.01 1 "$mode" \
                < "$input" > "$output/$run.csv" 2> "$output/$run-team.txt"
            grep -qx "observed_team=$threads" "$output/$run-team.txt"
            echo "$run: observed_team=$threads"
            python3 tools/compare.py "$output/$name-reference.csv" "$output/$run.csv"
            passed=$((passed + 1))
        done
    done
done

# Normal output should print every state once, and timing-only output one line.
timeout 120s ./build/reference-observation 4 3 0.01 1 g > "$output/ordinary-reference.txt"
for threads in 1 2 4 8 16 32; do
    timeout 120s "./build/$variant" "$threads" 4 3 0.01 1 g > "$output/ordinary-t$threads.txt"
    diff -u <(sed '/^Elapsed time =/d' "$output/ordinary-reference.txt") \
        <(sed '/^Elapsed time =/d' "$output/ordinary-t$threads.txt")
    timeout 120s "./build/$variant-no-output" "$threads" 4 3 0.01 1 g > "$output/timing-t$threads.txt"
    test "$(wc -l < "$output/timing-t$threads.txt")" -eq 1
    grep -q '^Elapsed time = ' "$output/timing-t$threads.txt"
done
echo "$variant validation passed: $passed comparisons; team sizes and output modes passed"
