#!/usr/bin/env bash
set -euo pipefail
export OMP_DYNAMIC=FALSE
variant=${1:-basic}
case "$variant" in
    basic|reduced-default) ;;
    *) echo "Unknown Part 2B variant: $variant" >&2; exit 1 ;;
esac
output="build/validation/$variant"
mkdir -p "$output"

for spec in "1 10 g" "4 3 g" "7 20 g" "4 3 i"; do
    read -r n steps mode <<< "$spec"
    name="n$n-steps$steps-$mode"
    input=/dev/null
    if [[ $mode == i ]]; then input=tests/inputs/noncollinear-4.txt; fi
    timeout 30s ./build/shared-precise 1 "$n" "$steps" 0.01 1 "$mode" \
        < "$input" > "$output/$name-reference.csv"
    for threads in 1 4; do
        timeout 30s "./build/part2b-$variant-validate" "$threads" "$n" "$steps" 0.01 1 "$mode" \
            < "$input" > "$output/$name-t$threads.csv" 2> "$output/$name-t$threads-team.txt"
        grep -qx "observed_team=$threads" "$output/$name-t$threads-team.txt"
        echo "$variant $name: observed_team=$threads"
        python3 tools/compare.py "$output/$name-reference.csv" "$output/$name-t$threads.csv"
    done
done

timeout 30s "./build/part2b-$variant" 4 4 3 0.01 1 g > "$output/ordinary.txt"
timeout 30s ./build/reference-observation 4 3 0.01 1 g > "$output/reference-ordinary.txt"
diff -u <(sed '/^Elapsed time =/d' "$output/ordinary.txt") \
    <(sed '/^Elapsed time =/d' "$output/reference-ordinary.txt")
timeout 30s "./build/part2b-$variant-no-output" 4 4 3 0.01 1 g > "$output/timing.txt"
test "$(wc -l < "$output/timing.txt")" -eq 1
grep -q '^Elapsed time = ' "$output/timing.txt"
echo "$variant checks passed: 8 comparisons, team sizes and output modes"
