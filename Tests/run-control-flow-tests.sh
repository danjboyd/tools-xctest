#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

build_fixture ControlFlowFixture

report_dir=$(mktemp -d)
trap 'rm -rf "$report_dir"' EXIT
report="$report_dir/report.xml"

echo "Running control-flow error regressions..."

run_fixture ControlFlowFixture -junit-report "$report"
assert_status 1

# Code 2 (Swift's XCTSkip) from a test skips it, at the error's location.
assert_contains "testSkips SKIPPED at /src/FixtureTests.swift:42, Test skipped - not on this platform"
assert_not_contains "testSkips FAILED"

# Without userInfo, it still skips, with no location and Apple's message.
assert_contains "testSkipsWithoutInfo SKIPPED, Test skipped"
assert_not_contains "(null)"

# Code 2 from -setUpWithError: skips the test; teardown still runs.
assert_contains "testNeverRuns SKIPPED at /src/FixtureTests.swift:42, Test skipped - set up"
assert_not_contains "fixture: SkipInSetUpTests.testNeverRuns"
assert_contains "fixture: SkipInSetUpTests.tearDown"

# Code 1 (XCTUnwrap's error) adds nothing to the failure already recorded.
recorded_line=$(grep -n 'XCTFail(@"recorded once")' "$source_root/Tests/ControlFlowFixture/ControlFlowFixture.m" | cut -d: -f1)
assert_contains "ControlFlowTests.testAlreadyRecorded: ControlFlowFixture.m:$recorded_line: failed: recorded once"
[ "$(printf '%s\n' "$output" | grep -c 'testAlreadyRecorded.*failed')" -eq 1 ] \
  || fail "expected testAlreadyRecorded to record exactly one failure"

# Any other code is an ordinary thrown error.
assert_contains "ControlFlowTests.testOtherCode: failed - unknown control flow"

assert_contains "1/2 test cases FAILED (3 tests skipped)"

output=$(cat "$report")
assert_contains '<testcase classname="ControlFlowTests" name="testSkips"'
assert_contains '<skipped message="/src/FixtureTests.swift:42: Test skipped - not on this platform"/>'
assert_contains '<testcase classname="ControlFlowTests" name="testSkipsWithoutInfo"'
assert_contains '<skipped message="Test skipped"/>'
assert_not_contains "(null)"
[ "$(printf '%s\n' "$output" | grep -c '<failure')" -eq 2 ] \
  || fail "expected exactly two failures in the JUnit report"

echo "Control-flow error regressions passed."
