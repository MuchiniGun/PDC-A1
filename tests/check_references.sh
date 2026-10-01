#!/usr/bin/env bash
# Runs in the course container from the repository root.
set -euo pipefail
mkdir -p build/validation

# Test cases covering: no pairs, one pair, small traces, and uneven sizes.
for n in 1 2 4 7 17; do
    timeout 30s ./build/reference-precise "$n" 10 0.01 1 g > build/validation/reduced.csv
    timeout 30s ./build/shared-precise 1 "$n" 10 0.01 1 g > build/validation/shared.csv
    echo "Generated case: n=$n, steps=10"
    python3 tools/compare.py build/validation/reduced.csv build/validation/shared.csv
done

timeout 30s ./build/reference-precise 4 3 0.01 1 i \
    < tests/inputs/noncollinear-4.txt > build/validation/reduced.csv
timeout 30s ./build/shared-precise 1 4 3 0.01 1 i \
    < tests/inputs/noncollinear-4.txt > build/validation/shared.csv
echo "Non-collinear case: n=4, steps=3"
python3 tools/compare.py build/validation/reduced.csv build/validation/shared.csv

timeout 30s ./build/reference-precise 4 2 0.01 1 g > build/validation/current.csv
python3 tools/compare.py tests/expected/reference-n4-steps2.csv build/validation/current.csv
echo "Reference checks passed"
