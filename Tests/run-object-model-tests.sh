#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

build_fixture ObjectModelFixture

echo "Running object model regressions..."
run_fixture ObjectModelFixture
assert_status 1

# The principal class is created first and registers an observer.
assert_contains "fixture: principal class created"
assert_contains "observer: bundle will start ObjectModelFixture.bundle"
assert_contains "observer: bundle did finish ObjectModelFixture.bundle"

# Observer events for one class, in order.
observed=$(printf '%s\n' "$output" | grep -o 'observer: .*Observed.*' | paste -sd '|' -)
expected="observer: suite will start ObservedTests (4 tests)"
expected+="|observer: case will start -[ObservedTests testFails]"
expected+="|observer: case failed -[ObservedTests testFails]: failed: observed failure"
expected+="|observer: case did finish -[ObservedTests testFails] succeeded=0 skipped=0"
expected+="|observer: case will start -[ObservedTests testPasses]"
expected+="|observer: case did finish -[ObservedTests testPasses] succeeded=1 skipped=0"
expected+="|observer: case will start -[ObservedTests testSkips]"
expected+="|observer: case did finish -[ObservedTests testSkips] succeeded=1 skipped=1"
expected+="|observer: case will start -[ObservedTests testThrows]"
expected+='|observer: case failed -[ObservedTests testThrows]: threw exception: "NSInternalInconsistencyException", "observed exception"'
expected+="|observer: case did finish -[ObservedTests testThrows] succeeded=0 skipped=0"
expected+="|observer: suite did finish ObservedTests executed=4 failures=1 unexpected=1 skipped=1 succeeded=0"
[ "$observed" = "$expected" ] || fail "unexpected observer events: $observed"

# +defaultTestSuite overrides: an abstract base runs nothing itself.
assert_contains "fixture: ConcreteTests testShared"
assert_not_contains "fixture: AbstractBaseTests testShared"
assert_contains "XCTest:   AbstractBaseTests SKIPPED"
assert_contains "XCTest:   ConcreteTests: 1 tests PASSED"

# +testInvocations overrides.
assert_contains "fixture: CustomInvocationTests testEnabled ran"
assert_contains "fixture: CustomInvocationTests verifyExtra ran"
assert_not_contains "fixture: CustomInvocationTests testDisabled ran"
assert_contains "XCTest:   CustomInvocationTests: 2 tests PASSED"

# -recordFailureWithDescription:... sees assertion failures and can drop them.
assert_contains "fixture: recordFailure saw 'failed: ignorable' expected=1"
assert_contains "fixture: recordFailure saw 'failed: real failure' expected=1"
assert_contains "XCTest:   RecordFailureOverrideTests: 1/2 tests FAILED"

# The XCTest/XCTestSuite/XCTestRun API used from a test.
assert_contains "fixture: InnerTests testInnerPasses ran"
assert_contains "XCTest:   ProgrammaticTests: 3 tests PASSED"
assert_contains "XCTest:   InnerTests SKIPPED"

# Listing uses the same suites.
run_fixture ObjectModelFixture -list-tests -only-testing:ObjectModelFixture/CustomInvocationTests
[ "$output" = $'ObjectModelFixture/CustomInvocationTests/testEnabled\nObjectModelFixture/CustomInvocationTests/verifyExtra' ] \
  || fail "expected -list-tests to follow +testInvocations"

# Getters and other non-void methods named test... aren't tests.
run_fixture ObjectModelFixture -list-tests -only-testing:ObjectModelFixture/GetterTests
[ "$output" = $'ObjectModelFixture/GetterTests/testOnewayVoid\nObjectModelFixture/GetterTests/testReal' ] \
  || fail "expected only void test methods to be listed, got: $output"

# Suites containing suites: skip counts, and failing +setUp.
run_fixture ObjectModelFixture -only-testing:ObjectModelFixture/NestedSuiteRunTests -only-testing:ObjectModelFixture/NestedSuiteTests
assert_status 0
assert_contains "NestedSuiteRunTests: 2 tests PASSED"
assert_contains "NestedSuiteTests: 1 tests PASSED"
# The suite run inside a test isn't reported as a class of its own.
assert_not_contains "NestedSuiteTests +setUp FAILED"
assert_not_contains "+tearDown FAILED"

echo "Object model tests passed."
