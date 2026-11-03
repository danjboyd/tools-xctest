#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

build_fixture ThrowingFixture

report_dir=$(mktemp -d)
trap 'rm -rf "$report_dir"' EXIT
report="$report_dir/report.xml"

echo "Running throwing-test regressions..."

# Throwing tests are found, and listed under the names they were written with.
run_fixture ThrowingFixture -list-tests
assert_status 0
[ "$output" = $'ThrowingFixture/ThrowingTests/testPlain\nThrowingFixture/ThrowingTests/testSucceeds\nThrowingFixture/ThrowingTests/testThrows' ] \
  || fail "expected the throwing tests to be listed without AndReturnError:"

# An error returned by a test fails it with the error's description.
run_fixture ThrowingFixture -junit-report "$report"
assert_status 1
assert_contains "fixture: ThrowingTests.testSucceeds"
assert_contains "fixture: ThrowingTests.testThrows"
assert_contains "ThrowingTests.testThrows"
assert_contains "fixture error"
assert_not_contains "AndReturnError"
output=$(cat "$report")
assert_contains '<testcase classname="ThrowingTests" name="testThrows" time="'
assert_contains 'fixture error'
assert_not_contains "AndReturnError"

# They are selected by those names too.
run_fixture ThrowingFixture -only-testing:ThrowingFixture/ThrowingTests/testSucceeds
assert_status 0
assert_contains "fixture: ThrowingTests.testSucceeds"
assert_not_contains "fixture: ThrowingTests.testThrows"
run_fixture ThrowingFixture -skip-testing:ThrowingFixture/ThrowingTests/testThrows
assert_status 0
assert_not_contains "fixture: ThrowingTests.testThrows"

echo "Throwing-test regressions passed."
