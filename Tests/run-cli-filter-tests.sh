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
fixture_dir="$source_root/Tests/FilterFixture"
fixture_bundle="$fixture_dir/FilterFixture.bundle"

if [ -z "$runtime_lib_dirs" ] && [ -n "${GNUSTEP_MAKEFILES:-}" ]; then
  runtime_lib_dirs="$(dirname "$GNUSTEP_MAKEFILES")/Libraries"
fi

assert_contains() {
  local haystack=$1
  local needle=$2

  if [[ "$haystack" != *"$needle"* ]]; then
    echo "expected output to contain: $needle" >&2
    echo "$haystack" >&2
    exit 1
  fi
}

assert_not_contains() {
  local haystack=$1
  local needle=$2

  if [[ "$haystack" == *"$needle"* ]]; then
    echo "expected output to omit: $needle" >&2
    echo "$haystack" >&2
    exit 1
  fi
}

run_xctest() {
  local output
  local status

  set +e
  output=$(LD_LIBRARY_PATH="$xctest_lib_dir${runtime_lib_dirs:+:$runtime_lib_dirs}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    "$xctest_bin" "$fixture_bundle" "$@" 2>&1)
  status=$?
  set -e

  printf '%s' "$output"
  return "$status"
}

echo "Building FilterFixture bundle..."
make -C "$fixture_dir" clean all \
  XCTEST_SOURCE_ROOT="$source_root" \
  XCTEST_LIBRARY_DIR="$xctest_lib_dir"

echo "Running CLI filter regressions..."
all_output=$(run_xctest)
assert_contains "$all_output" "fixture: AlphaTests.testOne"
assert_contains "$all_output" "fixture: AlphaTests.testTwo"
assert_contains "$all_output" "fixture: BetaTests.testThree"

only_output=$(run_xctest -only-testing:FilterFixture/AlphaTests/testTwo)
assert_contains "$only_output" "fixture: AlphaTests.testTwo"
assert_not_contains "$only_output" "fixture: AlphaTests.testOne"
assert_not_contains "$only_output" "fixture: BetaTests.testThree"

skip_output=$(run_xctest -skip-testing:FilterFixture/AlphaTests)
assert_contains "$skip_output" "fixture: BetaTests.testThree"
assert_not_contains "$skip_output" "fixture: AlphaTests.testOne"
assert_not_contains "$skip_output" "fixture: AlphaTests.testTwo"

combined_output=$(run_xctest -only-testing:FilterFixture/AlphaTests -skip-testing:FilterFixture/AlphaTests/testOne)
assert_contains "$combined_output" "fixture: AlphaTests.testTwo"
assert_not_contains "$combined_output" "fixture: AlphaTests.testOne"
assert_not_contains "$combined_output" "fixture: BetaTests.testThree"

no_match_output=$(run_xctest -only-testing:FilterFixture/MissingTests)
assert_contains "$no_match_output" "No tests matched the provided filters."

invalid_status=0
set +e
invalid_output=$(run_xctest -only-testing:FilterFixture/AlphaTests/testOne/extra)
invalid_status=$?
set -e
if [ "$invalid_status" -eq 0 ]; then
  echo "expected invalid identifier to fail" >&2
  echo "$invalid_output" >&2
  exit 1
fi
assert_contains "$invalid_output" "Invalid test identifier"

# Bundles named .xctest (as Xcode and buildtool make them) work, with
# Apple's -XCTest selection syntax.
xctest_dir=$(mktemp -d)
cp -r "$source_root/Tests/FilterFixture/FilterFixture.bundle" "$xctest_dir/FilterFixture.xctest"
run_xctest_bundle() {
  set +e
  output=$(LD_LIBRARY_PATH="$xctest_lib_dir${runtime_lib_dirs:+:$runtime_lib_dirs}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    "$xctest_bin" "$@" "$xctest_dir/FilterFixture.xctest" 2>&1)
  status=$?
  set -e
}
run_xctest_bundle -XCTest All -list-tests
[ "$output" = $'FilterFixture/AlphaTests/testOne\nFilterFixture/AlphaTests/testTwo\nFilterFixture/BetaTests/testThree' ] \
  || { echo "expected -XCTest All to list every test of the .xctest bundle: $output" >&2; exit 1; }
run_xctest_bundle -XCTest AlphaTests/testTwo,BetaTests -list-tests
[ "$output" = $'FilterFixture/AlphaTests/testTwo\nFilterFixture/BetaTests/testThree' ] \
  || { echo "expected -XCTest to select Class/method and Class: $output" >&2; exit 1; }
run_xctest_bundle -XCTest AlphaTests/testOne
[ "$status" -eq 0 ] || { echo "expected -XCTest AlphaTests/testOne to pass: $output" >&2; exit 1; }
assert_contains "$output" "AlphaTests: 1 tests PASSED"
run_xctest_bundle -XCTest ""
[ "$status" -eq 1 ] || { echo "expected -XCTest without tests to fail" >&2; exit 1; }
assert_contains "$output" "missing tests for -XCTest"
rm -rf "$xctest_dir"

echo "CLI filter tests passed."
