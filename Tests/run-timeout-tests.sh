#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

build_fixture TimeoutFixture

report_dir=$(mktemp -d)
trap 'rm -rf "$report_dir"' EXIT

echo "Running execution time allowance regressions..."

# Without time limits the default allowance is 600 seconds and nothing
# is timed.
run_fixture TimeoutFixture -only-testing:TimeoutFixture/AQuickTests
assert_status 0
assert_contains "fixture: default allowance 600"

# A test that hangs past its allowance fails; the run's reports are
# finished, observers hear the end, and the remaining tests don't run.
start=$(date +%s)
run_fixture TimeoutFixture -default-test-execution-time-allowance 1 -junit-report "$report_dir/timeout.xml"
elapsed=$(( $(date +%s) - start ))
assert_status 1
[ "$elapsed" -lt 15 ] || fail "expected the hung test to be stopped promptly (took ${elapsed}s)"
assert_contains "fixture: default allowance 1"
assert_contains "fixture: hanging"
assert_not_contains "fixture: hang ended"
assert_contains "XCTest:     testHangs: Test exceeded execution time allowance of 1 second"
assert_contains "XCTest:   HangTests: 1/1 tests FAILED"
assert_contains "XCTest:   HangTests.testHangs: Test exceeded execution time allowance of 1 second"
assert_contains "xctest: -[HangTests testHangs] exceeded its execution time allowance of 1 second; stopping the run (the remaining tests were not run)"
assert_contains "observer: HangTests finished executed=1 failures=1"
assert_contains "observer: bundle did finish"
assert_not_contains "fixture: ran after the hang"
grep -q '<testsuites name="TimeoutFixture.bundle" tests="2" failures="1"' "$report_dir/timeout.xml" \
  || fail "expected a JUnit report covering the tests that ran"
grep -q '<failure message="Test exceeded execution time allowance of 1 second"' "$report_dir/timeout.xml" \
  || fail "expected the timeout in the JUnit report"

# Apple-format output is finished too.
run_fixture TimeoutFixture -output-format apple -default-test-execution-time-allowance 1 -skip-testing:TimeoutFixture/OwnAllowanceTests
assert_status 1
assert_contains "error: -[HangTests testHangs] : Test exceeded execution time allowance of 1 second"
assert_contains "Test Case '-[HangTests testHangs]' failed ("
assert_contains "Test Suite 'Selected tests' failed at "
assert_contains "Test Suite 'TimeoutFixture.bundle' failed at "

# A test can give itself a longer allowance...
run_fixture TimeoutFixture -default-test-execution-time-allowance 1 -only-testing:TimeoutFixture/OwnAllowanceTests
assert_status 0
assert_contains "fixture: own allowance 5"
assert_contains "OwnAllowanceTests: 1 tests PASSED"

# ...but not beyond the maximum.
run_fixture TimeoutFixture -maximum-test-execution-time-allowance 1 -only-testing:TimeoutFixture/OwnAllowanceTests
assert_status 1
assert_contains "testTakesTwoSeconds: Test exceeded execution time allowance of 1 second"

# Turning time limits off explicitly wins over the allowance options.
run_fixture TimeoutFixture -test-timeouts-enabled NO -maximum-test-execution-time-allowance 1 -only-testing:TimeoutFixture/OwnAllowanceTests
assert_status 0

# Bad values.
run_fixture TimeoutFixture -default-test-execution-time-allowance 0
assert_status 1
assert_contains "-default-test-execution-time-allowance needs a number of seconds greater than 0"
run_fixture TimeoutFixture -test-timeouts-enabled maybe
assert_status 1
assert_contains "-test-timeouts-enabled must be YES or NO"

echo "Timeout tests passed."
