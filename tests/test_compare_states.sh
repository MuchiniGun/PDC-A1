#!/usr/bin/env bash
set -euo pipefail

comparator=(python3 tools/compare.py)
reference=tests/expected/reference-n4-steps2.csv

expect_status() {
    local expected_status=$1
    local fixture=$2
    local actual_status

    set +e
    "${comparator[@]}" "$reference" "$fixture"
    actual_status=$?
    set -e

    if [[ $actual_status -ne $expected_status ]]; then
        echo "unexpected status for $fixture: got $actual_status, expected $expected_status" >&2
        exit 1
    fi
    echo "expected rejection confirmed: $fixture (status $actual_status)"
}

"${comparator[@]}" "$reference" "$reference"
expect_status 1 tests/fixtures/reference-n4-corrupt.csv
expect_status 2 tests/fixtures/reference-n4-missing.csv
expect_status 2 tests/fixtures/reference-n4-nonfinite.csv
expect_status 2 tests/fixtures/reference-n4-malformed.csv
echo "Comparator checks passed"
