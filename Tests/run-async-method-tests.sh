#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

build_fixture AsyncMethodFixture

report_dir=$(mktemp -d)
trap 'rm -rf "$report_dir"' EXIT
report="$report_dir/report.xml"

echo "Running async test method regressions..."

# Async tests (testFooWithCompletionHandler:) are found, and listed under
# the names they were written with.
run_fixture AsyncMethodFixture -list-tests
assert_status 0
[ "$output" = $'AsyncMethodFixture/AsyncHangTests/testNeverCompletes
AsyncMethodFixture/AsyncTests/testAssertionFails
AsyncMethodFixture/AsyncTests/testCompletesLater
AsyncMethodFixture/AsyncTests/testCompletesNow
AsyncMethodFixture/AsyncTests/testCompletesOnAnotherThread
AsyncMethodFixture/AsyncTests/testNoArgumentSignature
AsyncMethodFixture/AsyncTests/testPassesWithErrorBlock
AsyncMethodFixture/AsyncTests/testSkips
AsyncMethodFixture/AsyncTests/testThrows' ] \
  || fail "expected the async tests to be listed without WithCompletionHandler:"

run_fixture AsyncMethodFixture -skip-testing:AsyncMethodFixture/AsyncHangTests -junit-report "$report"
assert_status 1
assert_not_contains "WithCompletionHandler"

# Each runs until its completion is called: now, later on the run loop, or
# from another thread.
assert_contains "fixture: AsyncTests.testCompletesNow"
assert_contains "fixture: AsyncTests.testCompletesLater finished"
assert_contains "fixture: AsyncTests.testCompletesOnAnotherThread finished on main thread: 0"
for passing in testCompletesNow testCompletesLater testCompletesOnAnotherThread \
               testNoArgumentSignature testPassesWithErrorBlock; do
  assert_not_contains "$passing FAILED"
done

# A failure inside an async test is that test's, at its line.
assert_contains "AsyncTests.testAssertionFails: AsyncMethodFixture.m:51: failed: async assertion"

# A completion error (async throws) fails the test with its description,
# and a control-flow error skips it, at its location.
assert_contains "AsyncTests.testThrows: failed - async error"
assert_contains "testSkips SKIPPED at /src/AsyncTests.swift:7, Test skipped - async skip"
assert_contains "AsyncTests: 2/8 tests FAILED, 1 skipped"

output=$(cat "$report")
assert_contains '<testcase classname="AsyncTests" name="testCompletesLater"'
assert_contains '<testcase classname="AsyncTests" name="testThrows"'
assert_not_contains "WithCompletionHandler"

# Selected by those names.
run_fixture AsyncMethodFixture -only-testing:AsyncMethodFixture/AsyncTests/testCompletesLater
assert_status 0
assert_contains "fixture: AsyncTests.testCompletesLater finished"
assert_not_contains "fixture: AsyncTests.testCompletesNow"

# An async test that never completes is stopped by its execution time
# allowance.
run_fixture AsyncMethodFixture -default-test-execution-time-allowance 1 \
  -only-testing:AsyncMethodFixture/AsyncHangTests
assert_status 1
assert_contains "fixture: AsyncHangTests.testNeverCompletes"
assert_contains "testNeverCompletes: Test exceeded execution time allowance of 1 second"

echo "Async test method regressions passed."
