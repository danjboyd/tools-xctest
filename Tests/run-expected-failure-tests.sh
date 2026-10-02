#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

build_fixture ExpectedFailureFixture

echo "Running XCTExpectFailure regressions..."
run_fixture ExpectedFailureFixture -only-testing:ExpectedFailureFixture/ExpectedPassingTests
assert_status 0
assert_contains "ExpectedPassingTests: 7 tests PASSED"
assert_contains "Expected failure (known bug 1) at ExpectedFailureFixture.m:"
assert_contains ", ((NO) is true) failed: broken"
assert_contains "fixture: testExpectedAssertion continued"
assert_contains "Expected failure (block reason) at ExpectedFailureFixture.m:"
assert_contains 'Expected failure (throws): threw exception: "NSInternalInconsistencyException", "expected boom"'
assert_contains "Expected failure (matched) at "
assert_contains "fixture: testExpectedFailureDoesNotStopTest continued"
assert_contains "Expected failure (inner) at "
assert_contains "failed: nested"
assert_contains "Expected failure (outer) at "
assert_contains "failed: after block"

run_fixture ExpectedFailureFixture -only-testing:ExpectedFailureFixture/ExpectedFailingTests
assert_status 1
assert_contains "ExpectedFailingTests: 5/5 tests FAILED"
assert_contains "testStrictUnmatched: Failed due to unmatched expected failure: never happens"
assert_contains "testBlockStrictUnmatched: Failed due to unmatched expected failure: block never"
assert_contains "failed: outside the block"
assert_contains "failed: not matched"
assert_contains "testMatcherRejects: Failed due to unmatched expected failure: picky"
assert_contains "failed: counts anyway"
assert_not_contains "unmatched expected failure: disabled"

# Apple format and JUnit report them too.
report_dir=$(mktemp -d)
trap 'rm -rf "$report_dir"' EXIT
run_fixture ExpectedFailureFixture -output-format apple -junit-report "$report_dir/report.xml" \
  -only-testing:ExpectedFailureFixture/ExpectedPassingTests/testExpectedAssertion
assert_status 0
assert_contains "-[ExpectedPassingTests testExpectedAssertion] : Expected failure: known bug 1: ((NO) is true) failed: broken"
assert_contains "Test Case '-[ExpectedPassingTests testExpectedAssertion]' passed ("
grep -q '<system-out>Expected failure (known bug 1): ExpectedFailureFixture.m:' "$report_dir/report.xml" \
  || fail "expected the JUnit report to list the expected failure"
grep -q 'failures="0" errors="0"' "$report_dir/report.xml" \
  || fail "expected failures should not count in the JUnit report"

echo "XCTExpectFailure tests passed."
