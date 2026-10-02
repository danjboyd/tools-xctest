#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

build_fixture LifecycleFixture
build_fixture AsyncFixture

# Like run_fixture, but keeps only stdout, where Apple-format output goes.
run_fixture_stdout() {
  local name=$1
  shift
  set +e
  output=$(LD_LIBRARY_PATH="$xctest_lib_dir${runtime_lib_dirs:+:$runtime_lib_dirs}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    "$xctest_bin" "$source_root/Tests/$name/$name.bundle" "$@" 2>/dev/null)
  status=$?
  set -e
}

assert_matches() {
  printf '%s\n' "$output" | grep -Eq -- "$1" || fail "expected output to match: $1"
}

echo "Running Apple output format regressions..."
run_fixture_stdout LifecycleFixture -output-format apple \
  -only-testing:LifecycleFixture/TestThrowsTests \
  -only-testing:LifecycleFixture/SkipConditionTests \
  -only-testing:LifecycleFixture/ClassSetUpThrowsTests \
  -only-testing:LifecycleFixture/StopAfterFailureTests
assert_status 1
assert_not_contains "XCTest:"
assert_matches "^Test Suite 'Selected tests' started at [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8}\.[0-9]{3}\.$"
assert_contains "Test Suite 'LifecycleFixture.bundle' started at "
assert_contains "Test Suite 'TestThrowsTests' started at "
assert_contains "Test Case '-[TestThrowsTests testThrows]' started."
assert_contains '<unknown>:0: error: -[TestThrowsTests testThrows] : threw exception: "NSInternalInconsistencyException", "fixture exception"'
assert_matches "^Test Case '-\[TestThrowsTests testThrows\]' failed \([0-9]+\.[0-9]{3} seconds\)\.$"
assert_contains "LifecycleFixture.m:146: error: -[StopAfterFailureTests testStops] : ((NO) is true) failed: fixture stop"
assert_contains '<unknown>:0: error: +[ClassSetUpThrowsTests setUp] : threw exception: "NSInternalInconsistencyException", "fixture +setUp exception"'
assert_contains "-[SkipConditionTests testSkipIfTrue] : Test skipped - (1 + 1 == 2) is true: fixture skipIf"
assert_matches "^Test Case '-\[SkipConditionTests testSkipIfTrue\]' skipped \("
assert_matches "^Test Case '-\[SkipConditionTests testSkipIfFalse\]' passed \("
assert_matches "^Test Suite 'SkipConditionTests' passed at "
assert_matches "^Test Suite 'TestThrowsTests' failed at "
assert_matches "^	 Executed 4 tests, with 2 tests skipped and 0 failures \(0 unexpected\) in [0-9.]+ \([0-9.]+\) seconds$"
assert_matches "^	 Executed 1 test, with 2 failures \(2 unexpected\) in "
assert_matches "^Test Suite 'Selected tests' failed at "
assert_matches "^	 Executed 7 tests, with 2 tests skipped and 4 failures \(3 unexpected\) in "

# Per-test durations are measured.
run_fixture_stdout AsyncFixture -output-format apple -only-testing:AsyncFixture/AsyncPassingTests/testInvertedWaitsFullTimeout
assert_status 0
assert_matches "^Test Case '-\[AsyncPassingTests testInvertedWaitsFullTimeout\]' passed \(0\.[2-9][0-9]{2} seconds\)\.$"
assert_matches "^Test Suite 'Selected tests' passed at "
assert_matches "^	 Executed 1 test, with 0 failures \(0 unexpected\) in "

# Without filters the top-level suite is "All tests".
run_fixture_stdout AsyncFixture -output-format apple -skip-testing:AsyncFixture/AsyncFailureTests
assert_contains "Test Suite 'Selected tests'"
run_fixture_stdout LifecycleFixture -output-format apple
assert_contains "Test Suite 'All tests' started at "

run_fixture LifecycleFixture -output-format bogus
assert_status 1
assert_contains "-output-format must be 'classic' or 'apple'"

echo "Output format tests passed."
