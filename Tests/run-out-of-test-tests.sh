#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

build_fixture OutOfTestFixture

report_dir=$(mktemp -d)
trap 'rm -rf "$report_dir"' EXIT

echo "Running out-of-test failure regressions..."

# Failures recorded after their test finished are reported against that
# test, so the exit status, console and JUnit agree.
run_fixture OutOfTestFixture -junit-report "$report_dir/late.xml" -only-testing:OutOfTestFixture/LateFailureTests
assert_status 1
assert_contains "LateFailureTests.testA_SchedulesMainThreadFailure FAILED after it finished: OutOfTestFixture.m:"
assert_contains "late failure on the main thread"
assert_contains "LateFailureTests.testB_SchedulesBackgroundFailure FAILED after it finished: OutOfTestFixture.m:"
assert_contains "late failure on a background thread"
# The test running when they arrive is neither blamed nor stopped.
assert_contains "fixture: testC_RunsWhileTheyArrive finished"
assert_not_contains "testC_RunsWhileTheyArrive FAILED"
assert_contains "XCTest: Failed tests:"
assert_contains "XCTest:   LateFailureTests.testA_SchedulesMainThreadFailure: OutOfTestFixture.m:"
grep -q '<testsuites name="OutOfTestFixture.bundle" tests="3" failures="2" errors="0"' "$report_dir/late.xml" \
  || fail "expected the JUnit report to show both late failures"

# Over-fulfilling an expectation late fails the test that created it.
run_fixture OutOfTestFixture -only-testing:OutOfTestFixture/OverFulfillTests
assert_status 1
assert_contains "OverFulfillTests.testA_FulfillsAgainLater FAILED after it finished: API violation - multiple calls made to -[XCTestExpectation fulfill] for fulfilled twice."
assert_not_contains "testB_RunsWhileItArrives FAILED"

# A failure recorded by an observer that runs before xctest's reporting
# is reported, rather than crashing the end-of-run summary.
run_fixture OutOfTestFixture -junit-report "$report_dir/early.xml" -only-testing:OutOfTestFixture/EarlyObserverTests
assert_status 1
assert_contains "testFailedByObserver: failure from an observer"
assert_contains "XCTest:   EarlyObserverTests.testFailedByObserver: failure from an observer"
assert_contains "XCTest: 1/1 test cases FAILED"
[ -f "$report_dir/early.xml" ] || fail "expected a JUnit report"

echo "Out-of-test failure tests passed."
