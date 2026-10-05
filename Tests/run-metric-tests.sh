#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

build_fixture MetricFixture

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

# Values of a measurement, e.g. values testClock "Clock Monotonic Time, s".
values() {
  printf '%s\n' "$output" | grep -o "$1 measured \[$2\] average: .*values: \[[^]]*\]" | sed 's/.*values: \[//; s/\]//'
}

echo "Running XCTMetric regressions..."
run_fixture MetricFixture -only-testing:MetricFixture/MetricPassingTests
assert_status 0
assert_contains "MetricPassingTests: 5 tests PASSED"

# The clock metric: 5 iterations by default, each about 10ms.
clock=$(values testClock "Clock Monotonic Time, s")
[ "$(echo "$clock" | tr ',' '\n' | wc -l)" -eq 5 ] || fail "expected 5 clock values: $clock"
for v in $(echo "$clock" | tr ',' ' '); do
  awk -v v="$v" 'BEGIN { exit !(v >= 0.009 && v < 0.5) }' || fail "unexpected clock value $v"
done

# CPU time follows the 20ms spin; logical writes are the 100 kB written;
# the memory peak covers the 8 MB touched.
for v in $(values testAllMetrics "CPU Time, s" | tr ',' ' '); do
  awk -v v="$v" 'BEGIN { exit !(v >= 0.01 && v < 0.5) }' || fail "unexpected CPU time $v"
done
[ "$(values testAllMetrics "Disk Logical Writes, kB")" = "100.000000, 100.000000, 100.000000" ] \
  || fail "unexpected logical writes: $(values testAllMetrics "Disk Logical Writes, kB")"
for v in $(values testAllMetrics "Memory Peak Physical, kB" | tr ',' ' '); do
  awk -v v="$v" 'BEGIN { exit !(v >= 8192) }' || fail "unexpected memory peak $v"
done
assert_contains "testAllMetrics measured [Memory Physical, kB] average: "

# A custom metric gets its hooks around each run, after the block's own
# start with ManuallyStart; its measurements are reported by identifier.
hooks=$(printf '%s\n' "$output" | grep -o 'widget: .*' | paste -sd '|' -)
expected="widget: willBegin|widget: block before start|widget: didStart|widget: block measuring|widget: didStop"
[ "$hooks" = "$expected|$expected" ] || fail "unexpected metric hooks: $hooks"
[ "$(values testManualStartAndCustomMetric "Widgets, w")" = "1.000000, 2.000000" ] || fail "expected the custom metric's values"
assert_not_contains "timestamps out of order"

# ManuallyStop: the block stops measuring itself.
[ "$(printf '%s\n' "$output" | grep -c 'metric: after stop')" -eq 2 ] || fail "expected 2 manually stopped runs"
assert_contains "testManualStop measured [Clock Monotonic Time, s]"

# Misuse fails the test.
run_fixture MetricFixture -only-testing:MetricFixture/MetricFailingTests
assert_status 1
assert_contains "testNeverStarts: Must call -startMeasuring and -stopMeasuring once in each run of the measured block."
assert_not_contains "testNeverStarts: Cannot call -stopMeasuring before -startMeasuring."
assert_contains "testMeasuresTwice: API violation - measure methods can only be called once per test."
assert_contains "testMetricError: Failed to measure WidgetMetric: widget counter broke"
assert_contains "testZeroIterations: The iteration count must be at least 1."

# Baselines are kept per measurement, under the test's "metrics"; polarity
# says which way is worse.
cat > "$work_dir/baselines.json" <<'JSON'
{
  "MetricFailingTests/testWidgetsRegress": {"metrics": {"com.example.widgets": {"average": 100, "maxPercentRegression": 10}}},
  "MetricPassingTests/testClock": {"metrics": {"com.apple.dt.XCTMetric_Clock.time.monotonic": {"average": 10}}}
}
JSON
run_fixture MetricFixture -performance-baselines "$work_dir/baselines.json" \
  -only-testing:MetricFixture/MetricFailingTests/testWidgetsRegress -only-testing:MetricFixture/MetricPassingTests/testClock
assert_status 1
assert_contains "testWidgetsRegress: [Widgets, w] average: 3.000000, 97.0% worse than baseline 100.000000 (max allowed regression 10.0%)"
assert_contains "testClock measured [Clock Monotonic Time, s] average: "
assert_contains "MetricPassingTests: 1 tests PASSED"

# Recording baselines nests new metrics under "metrics".
run_fixture MetricFixture -performance-baselines "$work_dir/new.json" -update-performance-baselines \
  -only-testing:MetricFixture/MetricPassingTests/testAllMetrics
assert_status 0
recorded=$(cat "$work_dir/new.json")
[[ "$recorded" == *'"metrics"'* && "$recorded" == *'"com.apple.dt.XCTMetric_CPU.time"'* \
   && "$recorded" == *'"com.apple.dt.XCTMetric_Disk.logical_writes"'* ]] || fail "unexpected recorded baselines: $recorded"

# Apple-format output names each metric, its identifier and polarity.
run_fixture MetricFixture -output-format apple -only-testing:MetricFixture/MetricPassingTests/testManualStartAndCustomMetric
assert_status 0
assert_contains "Test Case '-[MetricPassingTests testManualStartAndCustomMetric]' measured [Widgets, w] average: 1.500"
assert_contains "performanceMetricID:com.example.widgets"
assert_contains "polarity: prefers larger"

echo "XCTMetric tests passed."
