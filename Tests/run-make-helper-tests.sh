#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

fixture="$source_root/Tests/MakeHelperFixture"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
export LD_LIBRARY_PATH="$xctest_lib_dir${runtime_lib_dirs:+:$runtime_lib_dirs}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# make_fixture [make args...] sets $output and $status, building with this
# tree's xctest.make, library and xctest.
make_fixture() {
  set +e
  output=$(make -C "$fixture" XCTEST_MAKE="$source_root/xctest.make" \
    XCTEST_LIBRARY_DIR="$xctest_lib_dir" XCTEST_INCLUDE_DIR="$source_root" \
    XCTEST="$xctest_bin" "$@" 2>&1)
  status=$?
  set -e
}

echo "Running build-system helper regressions..."

# Builds each XCTEST_BUNDLE_NAME as a .xctest bundle linked with XCTest.
make_fixture clean all
assert_status 0
for bundle in HelperTests OtherTests; do
  [ -f "$(bundle_binary "$fixture/$bundle.xctest" "$bundle")" ] || fail "expected $bundle.xctest to be built"
done

# make check runs every bundle.
make_fixture check
assert_status 0
assert_contains "Running HelperTests.xctest..."
assert_contains "helper: HelperTests testPasses ran"
assert_contains "Running OtherTests.xctest..."
assert_contains "XCTest:   OtherTests: 1 tests PASSED"

# A failing bundle fails make check, after the others have still run.
HELPER_FIXTURE_FAIL=1 make_fixture check
[ "$status" -ne 0 ] || fail "expected make check to fail"
assert_contains "asked to fail"
assert_contains "XCTest:   OtherTests: 1 tests PASSED"

# XCTEST_FLAGS reach every run, <Bundle>_XCTEST_FLAGS only that bundle's.
make_fixture check XCTEST_FLAGS="-output-format apple" \
  HelperTests_XCTEST_FLAGS="-only-testing:HelperTests/HelperTests/testPasses"
assert_status 0
assert_contains "Test Case '-[OtherTests testOther]' passed"
assert_contains "Test Case '-[HelperTests testPasses]' passed"
assert_not_contains "testFailsWhenAsked"

# XCTEST_HOST and XCTEST_LAUNCHER go on the xctest command line.
make_fixture check XCTEST_HOST=/opt/Example.app XCTEST_LAUNCHER=echo
assert_status 0
assert_contains "$xctest_bin ./HelperTests.xctest -host /opt/Example.app"

# Test bundles are never installed.
make_fixture install DESTDIR="$work_dir/destdir"
assert_status 0
[ -z "$(find "$work_dir/destdir" -name '*.xctest' 2>/dev/null)" ] || fail "expected test bundles not to be installed"
assert_contains "Skipping standard installation of HelperTests"

# Without XCTEST_BUNDLE_NAME, the makefile says what's missing.
set +e
output=$(make -C "$fixture" XCTEST_MAKE="$source_root/xctest.make" XCTEST_BUNDLE_NAME= 2>&1)
status=$?
set -e
[ "$status" -ne 0 ] || fail "expected an empty XCTEST_BUNDLE_NAME to fail"
assert_contains "set XCTEST_BUNDLE_NAME to the test bundles to build"

# xctest-bundle wraps a shared library as a bundle xctest can load.
"$source_root/xctest-bundle" "$work_dir/Wrapped.xctest" "$(bundle_binary "$fixture/OtherTests.xctest" OtherTests)"
grep -q 'NSExecutable = "Wrapped";' "$work_dir/Wrapped.xctest/Resources/Info-gnustep.plist" \
  || fail "expected the wrapped bundle's plist to name its executable"
set +e
output=$("$xctest_bin" "$work_dir/Wrapped.xctest" 2>&1)
status=$?
set -e
assert_status 0
assert_contains "XCTest:   OtherTests: 1 tests PASSED"
set +e
output=$("$source_root/xctest-bundle" "$work_dir/Missing.xctest" "$work_dir/nope.so" 2>&1)
status=$?
set -e
assert_status 1
assert_contains "no such library"

# make coverage builds the bundles instrumented on the side, runs them with
# coverage, and writes a summary, lcov and HTML for each. It needs clang's
# llvm-profdata and llvm-cov.
have_llvm_tool() {
  command -v "$1" > /dev/null 2>&1 \
    || [ -n "$(IFS=:; for d in $PATH; do ls "$d/$1"-[0-9]* 2>/dev/null || true; done)" ]
}
if have_llvm_tool llvm-profdata && have_llvm_tool llvm-cov; then
  make_fixture all
  ordinary=$(bundle_binary "$fixture/HelperTests.xctest" HelperTests)
  touch -d '2000-01-01' "$ordinary"
  coverage_dir="$work_dir/coverage"
  make_fixture coverage XCTEST_COVERAGE_DIR="$coverage_dir"
  assert_status 0
  assert_contains "Running HelperTests.xctest for coverage..."
  assert_contains "Running OtherTests.xctest for coverage..."
  for bundle in HelperTests OtherTests; do
    for report in "$bundle.profdata" "$bundle.txt" "$bundle.lcov" "$bundle-html/index.html"; do
      [ -f "$coverage_dir/$report" ] || fail "expected make coverage to write $report"
    done
  done
  grep -q 'HelperTests\.m' "$coverage_dir/HelperTests.txt" || fail "expected the summary to cover HelperTests.m"
  grep -q '^SF:.*HelperTests\.m$' "$coverage_dir/HelperTests.lcov" || fail "expected the lcov to cover HelperTests.m"
  ! grep -q 'Headers/Foundation' "$coverage_dir/HelperTests.txt" \
    || fail "expected GNUstep's headers to be left out of the summary"
  [ "$(find "$ordinary" -newermt '2000-01-02' 2>/dev/null)" = "" ] \
    || fail "expected make coverage to leave the ordinary build alone"

  # A failing test fails make coverage, after the reports are written.
  rm -f "$coverage_dir/HelperTests.txt"
  HELPER_FIXTURE_FAIL=1 make_fixture coverage XCTEST_COVERAGE_DIR="$coverage_dir"
  [ "$status" -ne 0 ] || fail "expected make coverage to fail when a test fails"
  assert_contains "asked to fail"
  [ -f "$coverage_dir/HelperTests.txt" ] || fail "expected a report from a failing run"
else
  echo "Skipping make coverage: no llvm-profdata and llvm-cov."
fi

make_fixture clean
[ ! -e "$fixture/obj/xctest-coverage" ] || fail "expected make clean to remove the coverage build"
echo "Build-system helper tests passed."
