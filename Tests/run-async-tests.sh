#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

build_fixture AsyncFixture

echo "Running async regressions..."
run_fixture AsyncFixture -only-testing:AsyncFixture/AsyncPassingTests
assert_status 0
assert_contains "AsyncPassingTests: 12 tests PASSED"

run_fixture AsyncFixture -only-testing:AsyncFixture/AsyncFailureTests
assert_status 1
assert_contains 'Asynchronous wait failed: Exceeded timeout of 0.1 seconds, with unfulfilled expectations: "never fulfilled".'
assert_contains "fixture: timeout handler error com.apple.XCTestErrorDomain 0"
assert_contains 'Asynchronous wait failed: Fulfilled inverted expectation "inverted".'
assert_contains "Failed due to expectation fulfilled in incorrect order: requires 'first', actually fulfilled 'second'."
assert_contains "Failed due to unwaited expectation 'forgotten'."
assert_contains "API violation - multiple calls made to -[XCTestExpectation fulfill] for once only."
assert_contains "API violation - call made to wait without any expectations having been set."
assert_not_contains "fixture: AsyncFailureTests continued after timeout"
assert_contains "AsyncFailureTests: 7/7 tests FAILED"

echo "Async tests passed."
