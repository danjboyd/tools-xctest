#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

build_fixture AssertionFixture

echo "Running assertion message regressions..."
run_fixture AssertionFixture
assert_status 1

assert_contains 'failed: fixture message'
assert_contains '((1 + 1) equal to (3)) failed: ("2") is not equal to ("3")'
assert_contains '((YES) equal to (NO)) failed: ("1") is not equal to ("0")'
assert_contains '(([self boom]) equal to (1)) failed: throwing "boom"'
assert_contains '((2) not equal to (2)) failed: ("2") is equal to ("2")'
assert_contains '((0.1 + 0.2) equal to (0.4) +/- (0.001)) failed: ("0.30000000000000004") is not equal to ("0.4") +/- ("0.001")'
assert_contains '((1.0) not equal to (1.05) +/- (0.1)) failed: ("1") is equal to ("1.05") +/- ("0.1")'
assert_contains '((@"a") equal to (@"b")) failed: ("a") is not equal to ("b")'
assert_contains '((@"a") not equal to (@"a")) failed: ("a") is equal to ("a")'
assert_contains '((@"x") == nil) failed: "x"'
assert_contains '((nil) != nil) failed'
assert_contains '((1) greater than (2)) failed: ("1") is less than or equal to ("2")'
assert_contains '((1) greater than or equal to (2)) failed: ("1") is less than ("2")'
assert_contains '((2) less than (1)) failed: ("2") is greater than or equal to ("1")'
assert_contains '((2) less than or equal to (1)) failed: ("2") is greater than ("1")'
assert_contains '((1 > 2) is true) failed'
assert_contains '((2 > 1) is false) failed'
assert_contains '((1) throws) failed: no exception thrown'
assert_contains '(([self boom]) throws <FixtureException>) failed: threw <NSException> "boom"'
assert_contains '(([self boom]) throws <NSException, "OtherName">) failed: threw <NSException, "NSInternalInconsistencyException"> "boom"'
assert_contains '(([self boom]) does not throw) failed: threw "boom"'
assert_contains '(([self boom]) does not throw <NSException>) failed: threw <NSException> "boom"'
assert_contains '(([self boom]) does not throw <NSException, "NSInternalInconsistencyException">) failed: threw <NSException, "NSInternalInconsistencyException"> "boom"'
assert_not_contains 'assertion failed'
assert_contains '"a") is not identical to ("a")'
assert_contains '((object) not identical to (object)) failed: ("<NSObject: '
assert_contains 'AssertionMessageTests: 25/25 tests FAILED'
assert_contains 'PassingIdentityTests: 1 tests PASSED'

echo "Assertion message tests passed."
