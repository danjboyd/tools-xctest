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
# As in Apple's XCTest, a first warm-up run isn't counted.
hooks=$(printf '%s\n' "$output" | grep -o 'widget: .*' | paste -sd '|' -)
expected="widget: willBegin|widget: block before start|widget: didStart|widget: block measuring|widget: didStop"
[ "$hooks" = "$expected|$expected|$expected" ] || fail "unexpected metric hooks: $hooks"
[ "$(values testManualStartAndCustomMetric "Widgets, w")" = "2.000000, 3.000000" ] || fail "expected the custom metric's values"
assert_not_contains "timestamps out of order"

# ManuallyStop: the block stops measuring itself.
[ "$(printf '%s\n' "$output" | grep -c 'metric: after stop')" -eq 3 ] || fail "expected 3 manually stopped runs"
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
assert_contains "testWidgetsRegress: [Widgets, w] average: 4.000000, 96.0% worse than baseline 100.000000 (max allowed regression 10.0%)"
assert_contains "testClock measured [Clock Monotonic Time, s] average: "
assert_contains "MetricPassingTests: 1 tests PASSED"

# -performance-warmup-iterations changes the number of warm-up runs.
run_fixture MetricFixture -performance-warmup-iterations 0 \
  -only-testing:MetricFixture/MetricPassingTests/testManualStartAndCustomMetric
assert_status 0
[ "$(values testManualStartAndCustomMetric "Widgets, w")" = "1.000000, 2.000000" ] || fail "expected no warm-up run"
run_fixture MetricFixture -performance-warmup-iterations 3 \
  -only-testing:MetricFixture/MetricPassingTests/testManualStartAndCustomMetric
[ "$(values testManualStartAndCustomMetric "Widgets, w")" = "4.000000, 5.000000" ] || fail "expected 3 warm-up runs"
run_fixture MetricFixture -performance-warmup-iterations -1
assert_status 1
assert_contains "-performance-warmup-iterations needs a number of at least 0"

# With the baseline's stddev and count, a regression must also be
# significant (Welch's t-test); otherwise it's inconclusive, which only
# warns unless -performance-inconclusive-fails YES.
cat > "$work_dir/verdicts.json" <<'JSON'
{
  "version": 2,
  "MetricVerdictTests/testSignificantRegression": {"metrics": {"com.example.series": {"average": 100, "stddev": 1, "count": 5}}},
  "MetricVerdictTests/testNoisyRegression": {"metrics": {"com.example.series": {"average": 100, "stddev": 1, "count": 5}}},
  "MetricVerdictTests/testTooNoisy": {"metrics": {"com.example.series": {"average": 100, "maxPercentRelativeStandardDeviation": 5}}},
  "MetricVerdictTests/testImprovement": {"metrics": {"com.example.series": {"average": 100, "stddev": 1, "count": 5}}}
}
JSON
run_fixture MetricFixture -performance-baselines "$work_dir/verdicts.json" -only-testing:MetricFixture/MetricVerdictTests
assert_status 1
assert_contains "MetricVerdictTests: 1/4 tests FAILED"
assert_contains "testSignificantRegression: [Series, u] average: 111.000000, 11.0% worse than baseline 100.000000 (max allowed regression 10.0%), p = "
assert_contains "baseline average: 100.000000, stddev 1.000000 of 5 values (max regression 10.0%)"
assert_contains "testNoisyRegression: warning: [Series, u] average: 112.000000, 12.0% worse than baseline 100.000000 (max allowed regression 10.0%), but not significantly (p = 0."
assert_contains "testTooNoisy: warning: [Series, u] relative standard deviation 7.9% is above the baseline's maximum of 5.0%; inconclusive"
assert_not_contains "testImprovement: warning"
assert_contains "median: 111.000000, min: 109.000000"

run_fixture MetricFixture -performance-baselines "$work_dir/verdicts.json" -performance-inconclusive-fails YES \
  -only-testing:MetricFixture/MetricVerdictTests
assert_status 1
assert_contains "MetricVerdictTests: 3/4 tests FAILED"
assert_contains "MetricVerdictTests.testNoisyRegression: [Series, u] average: 112.000000, 12.0% worse"
run_fixture MetricFixture -performance-inconclusive-fails maybe
assert_status 1
assert_contains "-performance-inconclusive-fails must be YES or NO"

# Apple-format output and the JUnit report show inconclusive results as warnings.
run_fixture MetricFixture -performance-baselines "$work_dir/verdicts.json" -output-format apple \
  -junit-report "$work_dir/verdicts.xml" -only-testing:MetricFixture/MetricVerdictTests/testTooNoisy
assert_status 0
assert_contains "<unknown>:0: warning: -[MetricVerdictTests testTooNoisy] : [Series, u] relative standard deviation 7.9%"
grep -q "warning: \[Series, u\] relative standard deviation 7.9%" "$work_dir/verdicts.xml" \
  || fail "expected the inconclusive result in the JUnit report"

# Baselines for particular machines, in an entry's "machines", override
# the entry's own, key by key. The machine is named by
# -performance-machine-id or XCTEST_MACHINE_ID, else by its CPU.
cat > "$work_dir/machines.json" <<'JSON'
{
  "MetricVerdictTests/testImprovement": {"metrics": {"com.example.series": {"average": 100, "stddev": 1, "count": 5, "maxPercentRegression": 20}},
                                         "machines": {"slow-box": {"metrics": {"com.example.series": {"average": 70}}},
                                                      "fast-box": {"metrics": {"com.example.series": {"average": 85, "maxPercentRegression": 1}}}}}
}
JSON
series_test=-only-testing:MetricFixture/MetricVerdictTests/testImprovement
run_fixture MetricFixture -performance-baselines "$work_dir/machines.json" "$series_test"
assert_status 0
assert_contains "XCTest: Performance baselines for machine \""
assert_contains " cores, "
assert_contains "baseline average: 100.000000, stddev 1.000000 of 5 values (max regression 20.0%)"
# 90 against 70 is 28.6% worse: past the entry's 20% (inherited), and
# significant with its stddev and count (inherited too).
run_fixture MetricFixture -performance-baselines "$work_dir/machines.json" -performance-machine-id slow-box "$series_test"
assert_status 1
assert_contains "XCTest: Performance baselines for machine \"slow-box\""
assert_contains "testImprovement: [Series, u] average: 90.000000, 28.6% worse than baseline 70.000000 (max allowed regression 20.0%), p = "
XCTEST_MACHINE_ID=fast-box run_fixture MetricFixture -performance-baselines "$work_dir/machines.json" "$series_test"
assert_status 1
assert_contains "5.9% worse than baseline 85.000000 (max allowed regression 1.0%)"
# The option wins over the environment; an unknown machine gets the entry's.
XCTEST_MACHINE_ID=fast-box run_fixture MetricFixture -performance-baselines "$work_dir/machines.json" \
  -performance-machine-id other-box "$series_test"
assert_status 0
assert_contains "baseline average: 100.000000"
run_fixture MetricFixture -performance-machine-id
assert_status 1
assert_contains "missing identifier for -performance-machine-id"

# Recording: for the named machine; for this machine (by its CPU) when the
# entry already has machines; otherwise in the entry, as before.
run_fixture MetricFixture -performance-baselines "$work_dir/machines.json" -update-performance-baselines \
  -performance-machine-id new-box "$series_test"
assert_status 0
recorded=$(cat "$work_dir/machines.json")
printf '%s' "$recorded" | tr -d ' \t\r\n' | grep -q '"new-box":{"metrics":{"com.example.series":{' \
  || fail "expected new-box's baseline to be recorded: $recorded"
printf '%s' "$recorded" | tr -d ' \t\r\n' | grep -q '"slow-box":{"metrics":{"com.example.series":{"average":70}}}' \
  || fail "expected slow-box's baseline to be kept: $recorded"
run_fixture MetricFixture -performance-baselines "$work_dir/machines.json" -update-performance-baselines "$series_test"
assert_status 0
recorded=$(cat "$work_dir/machines.json")
[[ "$recorded" == *' cores, '* ]] || fail "expected this machine's baseline to be recorded: $recorded"
run_fixture MetricFixture -performance-baselines "$work_dir/plain.json" -update-performance-baselines "$series_test"
assert_status 0
recorded=$(cat "$work_dir/plain.json")
[[ "$recorded" != *'machines'* ]] || fail "expected no machines without a machine id: $recorded"

# Recording baselines nests new metrics under "metrics".
run_fixture MetricFixture -performance-baselines "$work_dir/new.json" -update-performance-baselines \
  -only-testing:MetricFixture/MetricPassingTests/testAllMetrics
assert_status 0
recorded=$(cat "$work_dir/new.json")
[[ "$recorded" == *'"metrics"'* && "$recorded" == *'"com.apple.dt.XCTMetric_CPU.time"'* \
   && "$recorded" == *'"com.apple.dt.XCTMetric_Disk.logical_writes"'* ]] || fail "unexpected recorded baselines: $recorded"
# With what the significance test needs, in a version 2 file.
[[ "$recorded" == *'"stddev"'* && "$recorded" == *'"count" : 3'* && "$recorded" == *'"version" : 2'* ]] \
  || [[ "$recorded" == *'"stddev"'* && "$recorded" == *'"count": 3'* && "$recorded" == *'"version": 2'* ]] \
  || fail "expected stddev, count and version in the recorded baselines: $recorded"

# Apple-format output names each metric, its identifier and polarity.
run_fixture MetricFixture -output-format apple -only-testing:MetricFixture/MetricPassingTests/testManualStartAndCustomMetric
assert_status 0
assert_contains "Test Case '-[MetricPassingTests testManualStartAndCustomMetric]' measured [Widgets, w] average: 2.500"
assert_contains "performanceMetricID:com.example.widgets"
assert_contains "polarity: prefers larger"

echo "XCTMetric tests passed."
