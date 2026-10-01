#!/usr/bin/env bash
set -euo pipefail
mkdir -p build/validation

for n in 1 2 4 7 17; do
    timeout 30s ./build/shared-precise 1 "$n" 10 0.01 1 g > build/validation/expected.csv
    timeout 30s ./build/critical-validate 1 "$n" 10 0.01 1 g > build/validation/critical.csv
    echo "Critical reference comparison: n=$n"
    python3 tools/compare.py build/validation/expected.csv build/validation/critical.csv
done

timeout 30s ./build/shared-precise 1 4 3 0.01 1 i \
    < tests/inputs/noncollinear-4.txt > build/validation/expected.csv
timeout 30s ./build/critical-validate 1 4 3 0.01 1 i \
    < tests/inputs/noncollinear-4.txt > build/validation/critical.csv
echo "Non-collinear critical baseline"
python3 tools/compare.py build/validation/expected.csv build/validation/critical.csv

# Verify normal output and NO_OUTPUT binaries also run.
timeout 30s ./build/critical 1 4 2 0.01 1 g > build/validation/ordinary.txt
timeout 30s ./build/critical-no-output 1 4 2 0.01 1 g > build/validation/timing.txt
test "$(wc -l < build/validation/timing.txt)" -eq 1
grep -q '^Elapsed time = ' build/validation/timing.txt

reject() {
    local status=0
    timeout 5s ./build/critical "$@" > build/validation/rejected.txt 2>&1 || status=$?
    if [[ $status -ne 1 ]]; then
        echo "Expected input rejection (status 1), got $status: $*" >&2
        exit 1
    fi
}
reject 0 4 2 0.01 1 g
reject 1 4 2 0.01 0 g
reject 1 4 2 nan 1 g
reject 1 4oops 2 0.01 1 g
reject 1 4 2 0.01 1 i < /dev/null
echo "Input rejection and output-mode checks passed"
echo "Critical reference and input checks passed"
