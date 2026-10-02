#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

build_fixture PerformanceFixture

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
baselines="$work_dir/baselines.json"
cat > "$baselines" <<'JSON'
{
  "PerfPassingTests/testWithinBaseline": { "average": 1.0 },
  "PerfFailingTests/testRegression": { "average": 0.0001, "maxPercentRegression": 50 }
}
JSON

# Prints the measured average for a test from classic output.
measured_average() {
  printf '%s\n' "$output" | grep -o "$1 measured \[Time, seconds\] average: [0-9.]*" | sed 's/.*average: //'
}

echo "Running performance test regressions..."
run_fixture PerformanceFixture -performance-baselines "$baselines" -only-testing:PerformanceFixture/PerfPassingTests
assert_status 0
assert_contains "PerfPassingTests: 3 tests PASSED"
assert_contains "testMeasureBlock measured [Time, seconds] average: "
assert_contains "relative standard deviation: "
values=$(printf '%s\n' "$output" | grep -o 'testMeasureBlock measured.*values: \[[^]]*\]' | sed 's/.*values: \[//; s/\]//')
[ "$(printf '%s' "$values" | awk -F',' '{ print NF }')" -eq 10 ] || fail "expected 10 measured values, got: $values"
# Each run slept 2ms.
awk -v a="$(measured_average testMeasureBlock)" 'BEGIN { exit !(a >= 0.0019 && a < 0.05) }' \
  || fail "unexpected testMeasureBlock average"
# Only the time between start/stopMeasuring counts (1ms of each 21ms run).
awk -v a="$(measured_average testManualMeasuring)" 'BEGIN { exit !(a >= 0.0009 && a < 0.015) }' \
  || fail "manual measuring should exclude unmeasured time"
assert_contains "testWithinBaseline measured [Time, seconds] average: "
assert_contains ", baseline average: 1.000000 (max regression 10.0%)"

run_fixture PerformanceFixture -performance-baselines "$baselines" -only-testing:PerformanceFixture/PerfFailingTests
assert_status 1
assert_contains "PerfFailingTests: 5/5 tests FAILED"
assert_contains "API violation - measure methods can only be called once per test."
assert_contains "Must call -startMeasuring and -stopMeasuring once in each run of the measured block."
assert_contains "Unsupported performance metric: com.example.Bogus"
assert_contains "Cannot call -startMeasuring outside of a measure block."
assert_contains "worse than baseline 0.000100 (max allowed regression 50.0%)"

# Without baselines nothing can regress.
run_fixture PerformanceFixture -only-testing:PerformanceFixture/PerfFailingTests/testRegression
assert_status 0

# Apple-format measurement line.
run_fixture PerformanceFixture -output-format apple -only-testing:PerformanceFixture/PerfPassingTests/testMeasureBlock
assert_status 0
assert_contains "Test Case '-[PerfPassingTests testMeasureBlock]' measured [Time, seconds] average: 0.00"
assert_contains "performanceMetricID:com.apple.XCTPerformanceMetric_WallClockTime"

# Recording baselines creates or updates the file, keeping settings.
new_baselines="$work_dir/new.json"
run_fixture PerformanceFixture -performance-baselines "$new_baselines" -update-performance-baselines \
  -only-testing:PerformanceFixture/PerfPassingTests/testMeasureBlock
assert_status 0
output=$(cat "$new_baselines")
assert_contains '"PerfPassingTests/testMeasureBlock"'
assert_contains '"average"'

run_fixture PerformanceFixture -performance-baselines "$baselines" -update-performance-baselines \
  -only-testing:PerformanceFixture/PerfFailingTests/testRegression
assert_status 0
output=$(cat "$baselines")
assert_contains '"maxPercentRegression"'
awk -v a="$(printf '%s\n' "$output" | grep -A3 'testRegression' | grep -o '"average": [0-9.e-]*' | sed 's/.*: //')" \
  'BEGIN { exit !(a > 0.004) }' || fail "expected the regression baseline to be updated"

run_fixture PerformanceFixture -performance-baselines "$work_dir/missing.json"
assert_status 1
assert_contains "Could not read performance baselines"

run_fixture PerformanceFixture -update-performance-baselines
assert_status 1
assert_contains "-update-performance-baselines needs -performance-baselines"

echo "Performance tests passed."
