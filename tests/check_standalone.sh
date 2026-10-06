#!/usr/bin/env bash
set -euo pipefail
export OMP_DYNAMIC=FALSE
repo=$PWD
build_dir=$(mktemp -d)
trap 'rm -f "$build_dir/program.c" "$build_dir/program" "$build_dir/output.csv" "$build_dir/team.txt"; rmdir "$build_dir"' EXIT

# Compile a copy in an empty directory to check it needs no project headers.
for variant in critical locks; do
    cp "part2a_$variant.c" "$build_dir/program.c"
    (
        cd "$build_dir"
        gcc -O2 -g -Wall -Wextra -fopenmp -DVALIDATE program.c -lm -o program
        timeout 120s ./program 4 4 2 0.01 1 g > output.csv 2> team.txt
        grep -qx 'observed_team=4' team.txt
    )
    python3 tools/compare.py "$repo/tests/expected/reference-n4-steps2.csv" "$build_dir/output.csv"
    echo "$variant standalone build and comparison passed"
done
echo "Part 2A standalone checks passed: 2 comparisons"
