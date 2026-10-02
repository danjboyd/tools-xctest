#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

build_fixture RepetitionFixture

count_lines() {
  printf '%s\n' "$output" | grep -c -- "$1" || true
}

echo "Running test repetition regressions..."

# Fixed iterations: every run counts; class +setUp runs once.
run_fixture RepetitionFixture -test-iterations 3 -only-testing:RepetitionFixture/CountingTests
assert_status 0
[ "$(count_lines 'fixture: counting run')" -eq 3 ] || fail "expected 3 runs"
[ "$(count_lines 'fixture: CountingTests +setUp')" -eq 1 ] || fail "expected one class +setUp"
assert_contains "testCounts (iteration 2 of 3)..."
assert_contains "CountingTests: 3 tests PASSED"

# Retry on failure: passes on the third attempt, earlier attempts don't count.
report_dir=$(mktemp -d)
trap 'rm -rf "$report_dir"' EXIT
run_fixture RepetitionFixture -retry-tests-on-failure -junit-report "$report_dir/retry.xml" \
  -only-testing:RepetitionFixture/FlakyTests
assert_status 0
[ "$(count_lines 'fixture: flaky run')" -eq 3 ] || fail "expected 3 attempts"
assert_contains "testPassesOnThirdRun failed on iteration 1 of 3; retrying"
assert_contains "testPassesOnThirdRun failed on iteration 2 of 3; retrying"
assert_contains "FlakyTests: 1 tests PASSED"
assert_not_contains "Failed tests:"
grep -q '<testsuite name="FlakyTests" tests="1" failures="0"' "$report_dir/retry.xml" \
  || fail "expected only the passing attempt in the JUnit report"
grep -q 'name="testPassesOnThirdRun (iteration 3)"' "$report_dir/retry.xml" \
  || fail "expected the iteration in the JUnit test name"

# Retry with too few attempts still fails.
run_fixture RepetitionFixture -retry-tests-on-failure -test-iterations 2 -only-testing:RepetitionFixture/FlakyTests
assert_status 1
assert_contains "FlakyTests: 1/1 tests FAILED"
assert_contains "FlakyTests.testPassesOnThirdRun (iteration 2): "

# Until failure: stops at the first failing run.
run_fixture RepetitionFixture -run-tests-until-failure -only-testing:RepetitionFixture/FailsOnThirdTests
assert_status 1
[ "$(count_lines 'fixture: fails-on-third run')" -eq 3 ] || fail "expected to stop after the third run"
assert_contains "FailsOnThirdTests: 1/3 tests FAILED"

run_fixture RepetitionFixture -run-tests-until-failure -test-iterations 2 -only-testing:RepetitionFixture/FailsOnThirdTests
assert_status 0
assert_contains "FailsOnThirdTests: 2 tests PASSED"

# A skipped test isn't repeated.
run_fixture RepetitionFixture -test-iterations 5 -only-testing:RepetitionFixture/RepeatedSkipTests
assert_status 0
[ "$(count_lines 'fixture: skip run')" -eq 1 ] || fail "expected a skipped test to run once"

# Apple-format output keeps its usual lines, once per run.
run_fixture RepetitionFixture -output-format apple -test-iterations 2 -only-testing:RepetitionFixture/CountingTests
assert_status 0
[ "$(count_lines "Test Case '-\[CountingTests testCounts\]' passed (")" -eq 2 ] || fail "expected 2 Apple-format runs"
assert_contains "Executed 2 tests, with 0 failures"

run_fixture RepetitionFixture -run-tests-until-failure -retry-tests-on-failure
assert_status 1
assert_contains "can't be combined"

run_fixture RepetitionFixture -test-iterations 0
assert_status 1
assert_contains "-test-iterations needs a number of at least 1"

echo "Test repetition tests passed."
