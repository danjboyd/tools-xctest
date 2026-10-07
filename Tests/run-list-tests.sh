#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

build_fixture FilterFixture
build_fixture LifecycleFixture

echo "Running test listing regressions..."
run_fixture FilterFixture -list-tests
assert_status 0
expected=$'FilterFixture/AlphaTests/testOne\nFilterFixture/AlphaTests/testTwo\nFilterFixture/BetaTests/testThree'
[ "$output" = "$expected" ] || fail "unexpected -list-tests output"

# Listing doesn't run anything.
assert_not_contains "fixture:"
assert_not_contains "XCTest:"

# Filters apply.
run_fixture FilterFixture -list-tests -only-testing:FilterFixture/AlphaTests -skip-testing:FilterFixture/AlphaTests/testOne
assert_status 0
[ "$output" = "FilterFixture/AlphaTests/testTwo" ] || fail "expected filters to apply to -list-tests"

run_fixture FilterFixture -list-tests -only-testing:FilterFixture/MissingTests
assert_status 1
assert_contains "No tests matched 'FilterFixture/MissingTests'."
assert_not_contains "FilterFixture/AlphaTests"

run_fixture FilterFixture -list-tests -only-testing:FilterFixture/AlphaTests/testOne/extra
assert_status 1
assert_contains "Invalid test identifier"

# Inherited tests are listed for each subclass.
run_fixture LifecycleFixture -list-tests -only-testing:LifecycleFixture/InheritedDerivedTests
[ "$output" = $'LifecycleFixture/InheritedDerivedTests/testInherited\nLifecycleFixture/InheritedDerivedTests/testOwn' ] \
  || fail "expected inherited tests to be listed"

run_fixture FilterFixture -list-tests-json -only-testing:FilterFixture/BetaTests
assert_status 0
if command -v python3 >/dev/null 2>&1; then
  printf '%s' "$output" | python3 -c '
import json, sys
listing = json.load(sys.stdin)
assert listing["bundle"] == "FilterFixture.bundle", listing
assert listing["target"] == "FilterFixture", listing
assert listing["tests"] == [{"identifier": "FilterFixture/BetaTests/testThree",
                             "class": "BetaTests", "method": "testThree"}], listing
' || fail "unexpected -list-tests-json output"
else
  assert_contains '"identifier": "FilterFixture/BetaTests/testThree"'
fi

# A bundle whose name has no basename still gets a complete JSON listing.
odd_dir=$(mktemp -d)
cp -r "$source_root/Tests/FilterFixture/FilterFixture.bundle" "$odd_dir/.bundle"
set +e
output=$(LD_LIBRARY_PATH="$xctest_lib_dir${runtime_lib_dirs:+:$runtime_lib_dirs}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  "$xctest_bin" -list-tests-json "$odd_dir/.bundle" 2>&1)
status=$?
set -e
rm -rf "$odd_dir"
assert_status 0
assert_contains '"tests"'
assert_contains '"target"'
assert_contains '"identifier"'

echo "Test listing tests passed."
