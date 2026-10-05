#!/usr/bin/env bash
set -euo pipefail
export OMP_DYNAMIC=FALSE
output=build/validation/build-modes
mkdir -p "$output"
for variant in basic reduced-default reduced-forces-cyclic reduced-all-cyclic; do
    bash tests/check_part2b.sh "$variant"
    # Check the timing binary itself, not just its validation counterpart.
    timeout 30s "./build/part2b-$variant-no-output" 4 4 3 0.01 1 g \
        > "$output/$variant-time.txt" 2> "$output/$variant-team.txt"
    grep -qx 'requested_team=4' "$output/$variant-team.txt"
    grep -qx 'observed_team=4' "$output/$variant-team.txt"
    test "$(wc -l < "$output/$variant-team.txt")" -eq 2
    test "$(wc -l < "$output/$variant-time.txt")" -eq 1
    grep -Eq '^Elapsed time = [0-9.eE+-]+ seconds$' "$output/$variant-time.txt"
    ldd "./build/part2b-$variant-no-output" > "$output/$variant-libraries.txt"
    grep -q 'libgomp' "$output/$variant-libraries.txt"
    echo "$variant: timing output, requested/observed teams and libgomp checked"
done
echo "Build-mode checks passed: 4 variants, 32 comparisons and benchmark metadata"
