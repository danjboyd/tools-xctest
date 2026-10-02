#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
  echo "usage: $0 <xctest-bin> <xctest-lib-dir> <source-root> [runtime-lib-dirs]" >&2
  exit 2
fi

xctest_bin=$1
xctest_lib_dir=$2
source_root=$3
runtime_lib_dirs=${4:-}
fixture_dir="$source_root/Tests/LifecycleFixture"
fixture_bundle="$fixture_dir/LifecycleFixture.bundle"

if [ -z "$runtime_lib_dirs" ] && [ -n "${GNUSTEP_MAKEFILES:-}" ]; then
  runtime_lib_dirs="$(dirname "$GNUSTEP_MAKEFILES")/Libraries"
fi

fail() {
  echo "$1" >&2
  echo "$output" >&2
  exit 1
}

assert_contains() {
  [[ "$output" == *"$1"* ]] || fail "expected output to contain: $1"
}

assert_not_contains() {
  [[ "$output" != *"$1"* ]] || fail "expected output to omit: $1"
}

# Prints the "fixture: <prefix>..." lines in order, one per line, with the
# NSLog prefix stripped.
fixture_lines() {
  printf '%s\n' "$output" | grep -o "fixture: $1.*" | sed 's/^fixture: //'
}

assert_sequence() {
  local prefix=$1
  local expected=$2
  local actual
  actual=$(fixture_lines "$prefix" | paste -sd ',' -)
  [ "$actual" = "$expected" ] || fail "expected '$prefix' sequence '$expected', got '$actual'"
}

echo "Building LifecycleFixture bundle..."
make -C "$fixture_dir" clean all \
  XCTEST_SOURCE_ROOT="$source_root" \
  XCTEST_LIBRARY_DIR="$xctest_lib_dir"

echo "Running lifecycle regressions..."
set +e
output=$(LD_LIBRARY_PATH="$xctest_lib_dir${runtime_lib_dirs:+:$runtime_lib_dirs}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  "$xctest_bin" "$fixture_bundle" 2>&1)
status=$?
set -e

# The fixture contains deliberately failing tests.
[ "$status" -ne 0 ] || fail "expected a non-zero exit status"

# Tests run in alphabetical order.
assert_sequence "OrderTests." "OrderTests.testA,OrderTests.testB,OrderTests.testC"

# Full per-test lifecycle; teardown blocks run last-added first.
assert_sequence "phase " "phase +setUp,phase setUpWithError,phase setUp,phase test,phase teardownBlock2,phase teardownBlock1,phase tearDown,phase tearDownWithError,phase +tearDown"

# Class-level setUp/tearDown run once per class, around all of its tests.
assert_sequence "ClassSetUpOnceTests" "ClassSetUpOnceTests +setUp,ClassSetUpOnceTests.testOne,ClassSetUpOnceTests.testTwo,ClassSetUpOnceTests +tearDown"
assert_contains "ClassSetUpOnceTests: 2 tests PASSED"

# tearDown runs when the test throws.
assert_contains "fixture: TestThrowsTests tearDown ran"
assert_contains "testThrows: threw exception: "
assert_contains "TestThrowsTests: 1/1 tests FAILED"

# A throwing setUp skips the test but still runs tearDown.
assert_not_contains "fixture: SetUpThrowsTests test ran"
assert_contains "fixture: SetUpThrowsTests tearDown ran"
assert_contains "SetUpThrowsTests: 1/1 tests FAILED"

# setUpWithError: returning NO skips the test but still runs tearDown.
assert_not_contains "fixture: SetUpErrorTests test ran"
assert_contains "fixture: SetUpErrorTests tearDown ran"
assert_contains "fixture setUpWithError error"
assert_contains "SetUpErrorTests: 1/1 tests FAILED"

# A failure in tearDown fails the test.
assert_contains "fixture tearDown failure"
assert_contains "TearDownFailsTests: 1/1 tests FAILED"

# A throwing +setUp fails every test in the class without running them.
assert_not_contains "fixture: ClassSetUpThrowsTests test ran"
assert_not_contains "fixture: ClassSetUpThrowsTests +tearDown ran"
assert_contains "ClassSetUpThrowsTests: 1/1 tests FAILED"

# A throwing +tearDown fails the class even though its tests passed.
assert_contains "ClassTearDownThrowsTests: 1 tests passed, +tearDown FAILED"

# continueAfterFailure = NO stops the test at the first failure; teardown runs.
assert_not_contains "fixture: StopAfterFailureTests continued"
assert_contains "fixture: StopAfterFailureTests tearDown ran"
assert_contains "StopAfterFailureTests: 1/1 tests FAILED"

# ...including when the failure happens inside another assertion's expression.
assert_not_contains "fixture: StopInsideAssertionTests continued"
assert_contains "StopInsideAssertionTests: 1/1 tests FAILED"

# continueAfterFailure defaults to YES.
assert_contains "fixture: ContinueAfterFailureTests continued"
assert_contains "ContinueAfterFailureTests: 1/1 tests FAILED"

# Subclasses run test methods inherited from their superclass.
assert_contains "fixture: InheritedBaseTests.testInherited"
assert_contains "fixture: InheritedDerivedTests.testInherited"
assert_contains "fixture: InheritedDerivedTests.testOwn"
assert_contains "InheritedDerivedTests: 2 tests PASSED"

# XCTSkip stops the test and reports it as skipped; teardown still runs.
assert_contains "testSkip SKIPPED at "
assert_contains "fixture skip reason 42"
assert_not_contains "fixture: SkipTests continued"
assert_contains "fixture: SkipTests tearDown ran"
assert_contains "SkipTests: 0 tests PASSED, 1 skipped"

# XCTSkipIf / XCTSkipUnless only skip when their condition says so.
assert_contains "fixture: SkipConditionTests.testSkipIfFalse continued"
assert_not_contains "fixture: SkipConditionTests.testSkipIfTrue continued"
assert_contains "(1 + 1 == 2) is true: fixture skipIf"
assert_not_contains "fixture: SkipConditionTests.testSkipUnlessFalse continued"
assert_contains "(1 + 1 == 3) is false"
assert_contains "fixture: SkipConditionTests.testSkipUnlessTrue continued"
assert_contains "SkipConditionTests: 2 tests PASSED, 2 skipped"

# Skipping in setUp skips the test body; teardown still runs.
assert_not_contains "fixture: SkipInSetUpTests test ran"
assert_contains "fixture: SkipInSetUpTests tearDown ran"
assert_contains "SkipInSetUpTests: 0 tests PASSED, 1 skipped"

# A skip raised inside an assertion's expression is a skip, not a failure.
assert_not_contains "fixture: SkipInsideAssertionTests continued"
assert_contains "SkipInsideAssertionTests: 0 tests PASSED, 1 skipped"

# A failure recorded before a skip still fails the test.
assert_contains "FailThenSkipTests: 1/1 tests FAILED"

# An exception while evaluating a skip condition is a failure, not a skip.
assert_contains "([self throwingCondition]) threw exception: fixture condition exception"
assert_contains "fixture: SkipConditionThrowsTests continued"
assert_contains "SkipConditionThrowsTests: 1/1 tests FAILED"

assert_contains "tests skipped)"

# Skipped tests do not make the run fail.
set +e
output=$(LD_LIBRARY_PATH="$xctest_lib_dir${runtime_lib_dirs:+:$runtime_lib_dirs}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  "$xctest_bin" "$fixture_bundle" \
  -only-testing:LifecycleFixture/SkipTests \
  -only-testing:LifecycleFixture/SkipConditionTests 2>&1)
status=$?
set -e
[ "$status" -eq 0 ] || fail "expected a run with only passed and skipped tests to succeed"
assert_contains "2 tests PASSED (3 tests skipped)"

echo "Lifecycle tests passed."
