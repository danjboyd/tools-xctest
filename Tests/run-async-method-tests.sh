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
[ "$output" = $'AsyncMethodFixture/AsyncFulfillmentTests/testAFulfilledFromTheRunLoop
AsyncMethodFixture/AsyncFulfillmentTests/testBNoLimitByDefault
AsyncMethodFixture/AsyncFulfillmentTests/testCTimesOut
AsyncMethodFixture/AsyncFulfillmentTests/testDChecksOrder
AsyncMethodFixture/AsyncFulfillmentTests/testEWaiterGivesItsResult
AsyncMethodFixture/AsyncFulfillmentTests/testFWaitedOnExpectationCounts
AsyncMethodFixture/AsyncHangTests/testNeverCompletes
AsyncMethodFixture/AsyncLifecycleTests/testBody
AsyncMethodFixture/AsyncSetUpFailsTests/testBody
AsyncMethodFixture/AsyncSetUpSkipsTests/testBody
AsyncMethodFixture/AsyncStopTests/testAStopsDuringTheCall
AsyncMethodFixture/AsyncStopTests/testBContinuesOnTheRunLoop
AsyncMethodFixture/AsyncStopTests/testCRunsNext
AsyncMethodFixture/AsyncStopTests/testDPlainTestStops
AsyncMethodFixture/AsyncTearDownFailsTests/testBody
AsyncMethodFixture/AsyncTeardownBlockTests/testAOrder
AsyncMethodFixture/AsyncTeardownBlockTests/testBAsyncBlockError
AsyncMethodFixture/AsyncTests/testAssertionFails
AsyncMethodFixture/AsyncTests/testCompletesLater
AsyncMethodFixture/AsyncTests/testCompletesNow
AsyncMethodFixture/AsyncTests/testCompletesOnAnotherThread
AsyncMethodFixture/AsyncTests/testNoArgumentSignature
AsyncMethodFixture/AsyncTests/testPassesWithErrorBlock
AsyncMethodFixture/AsyncTests/testSkips
AsyncMethodFixture/AsyncTests/testThrows' ] \
  || fail "expected the async tests to be listed without WithCompletionHandler:"

run_fixture AsyncMethodFixture -skip-testing:AsyncMethodFixture/AsyncHangTests \
  -skip-testing:AsyncMethodFixture/AsyncStopTests -skip-testing:AsyncMethodFixture/AsyncFulfillmentTests \
  -skip-testing:AsyncMethodFixture/AsyncLifecycleTests -skip-testing:AsyncMethodFixture/AsyncSetUpFailsTests \
  -skip-testing:AsyncMethodFixture/AsyncSetUpSkipsTests -skip-testing:AsyncMethodFixture/AsyncTearDownFailsTests \
  -skip-testing:AsyncMethodFixture/AsyncTeardownBlockTests \
  -junit-report "$report"
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
assert_contains "AsyncTests.testAssertionFails: AsyncMethodFixture.m:53: failed: async assertion"

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

# continueAfterFailure = NO stops an async test during the call, but not
# from the run loop: that would unwind through whatever is running the body.
# Here, that's a timer, which swallows the exception, so the test never
# completes; the allowance turns that hang into a failure. A @MainActor Swift
# test unwinding through libdispatch's main queue hangs later @MainActor tests.
# The failures are recorded either way.
run_fixture AsyncMethodFixture -default-test-execution-time-allowance 20 \
  -only-testing:AsyncMethodFixture/AsyncStopTests
assert_status 1
assert_contains "failed: during the call"
assert_not_contains "testAStopsDuringTheCall continued"
assert_contains "failed: on the run loop"
assert_contains "fixture: AsyncStopTests.testBContinuesOnTheRunLoop continued"
assert_contains "fixture: AsyncStopTests.testCRunsNext"
assert_contains "failed: in a plain test"
assert_not_contains "testDPlainTestStops continued"
assert_contains "AsyncStopTests: 3/4 tests FAILED"

# The wait behind Swift's await fulfillment(of:) leaves the run loop free,
# reports failed waits as a test's other waits do, and completes either way.
run_fixture AsyncMethodFixture -default-test-execution-time-allowance 20 \
  -only-testing:AsyncMethodFixture/AsyncFulfillmentTests
assert_status 1
assert_contains "fixture: AsyncFulfillmentTests.testA returned to the run loop"
assert_contains "fixture: AsyncFulfillmentTests.testA waited, on main thread: 0"
assert_contains 'Asynchronous wait failed: Exceeded timeout of 0.05 seconds, with unfulfilled expectations: "never".'
assert_contains "fixture: AsyncFulfillmentTests.testC completed after the timeout"
assert_contains "Failed due to expectation fulfilled in incorrect order: requires 'first', actually fulfilled 'second'."
assert_contains "fixture: AsyncFulfillmentTests.testE result 1"
assert_not_contains "unwaited"
assert_contains "AsyncFulfillmentTests: 2/6 tests FAILED"

# Asynchronous set up comes first and tear down last, each waited for.
run_fixture AsyncMethodFixture -only-testing:AsyncMethodFixture/AsyncLifecycleTests
assert_status 0
lifecycle=$(printf '%s\n' "$output" | grep -o 'fixture: lifecycle .*' | sed 's/fixture: lifecycle //' | tr '\n' ',')
[ "$lifecycle" = "setUpWithCompletionHandler:,async step finished on the run loop,setUpWithError:,setUp,test,tearDown,tearDownWithError:,tearDownWithCompletionHandler:," ] \
  || fail "unexpected lifecycle order: $lifecycle"

# An error from async set up fails the test without running it; tear down still runs.
run_fixture AsyncMethodFixture -only-testing:AsyncMethodFixture/AsyncSetUpFailsTests
assert_status 1
assert_contains "async set up error"
assert_not_contains "fixture: AsyncSetUpFailsTests test ran"
assert_contains "fixture: AsyncSetUpFailsTests tearDown ran"

run_fixture AsyncMethodFixture -only-testing:AsyncMethodFixture/AsyncSetUpSkipsTests
assert_status 0
assert_contains "testBody SKIPPED at /src/AsyncSetUp.swift:9, Test skipped - async set up skip"
assert_not_contains "fixture: AsyncSetUpSkipsTests test ran"

run_fixture AsyncMethodFixture -only-testing:AsyncMethodFixture/AsyncTearDownFailsTests
assert_status 1
assert_contains "fixture: AsyncTearDownFailsTests test ran"
assert_contains "async tear down error"

# Teardown blocks that finish later wait their turn in the same queue.
run_fixture AsyncMethodFixture -only-testing:AsyncMethodFixture/AsyncTeardownBlockTests/testAOrder
assert_status 0
teardown=$(printf '%s\n' "$output" | grep -o 'fixture: teardown .*' | sed 's/fixture: teardown //' | tr '\n' ',')
[ "$teardown" = "test body,last added,async block started,async block finished on the run loop,first added,tearDown," ] \
  || fail "unexpected teardown order: $teardown"

# An error from one fails the test; the rest of tear down still runs.
run_fixture AsyncMethodFixture -only-testing:AsyncMethodFixture/AsyncTeardownBlockTests/testBAsyncBlockError
assert_status 1
assert_contains "async teardown block error"
assert_contains "fixture: teardown ran after the error"
assert_contains "fixture: teardown tearDown"

echo "Async test method regressions passed."
