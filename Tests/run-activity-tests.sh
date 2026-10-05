#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

build_fixture ActivityFixture

report_dir=$(mktemp -d)
trap 'rm -rf "$report_dir"' EXIT

echo "Running activity regressions..."
run_fixture ActivityFixture -junit-report "$report_dir/activities.xml"
assert_status 1

# Activities are logged as they start; failures inside them carry their
# path, outermost first.
assert_contains "XCTest:     Activity: Log in"
assert_contains "XCTest:     Activity: Log in > Enter password"
assert_contains "Assertion FAILED at ActivityFixture.m:21, Log in > Enter password: failed: wrong password"
assert_contains "ActivityTests.testNestedActivityFailure: ActivityFixture.m:21: Log in > Enter password: failed: wrong password"
# Once an activity has finished (or thrown), failures aren't in it.
assert_contains "Assertion FAILED at ActivityFixture.m:30, failed: outside any activity"
assert_contains "fixture: caught 'from activity'"
assert_contains "Assertion FAILED at ActivityFixture.m:51, failed: after the exception"
# Each thread has its own activities.
assert_contains "Assertion FAILED at ActivityFixture.m:60, Background: failed: on another thread"
# Expected failures show their activity too.
assert_contains "Expected failure (known issue) at ActivityFixture.m:71, Flaky step: failed: expected inside activity"
# Outside a test, the block still runs.
assert_contains "fixture: class activity ran"
assert_contains "XCTest:   ActivityTests: 4/6 tests FAILED"

grep -q '<failure message="Log in &gt; Enter password: failed: wrong password"' "$report_dir/activities.xml" \
  || fail "expected the activity path in the JUnit report"

# Apple-format output has Apple's "t = " activity lines, indented by nesting.
run_fixture ActivityFixture -output-format apple -only-testing:ActivityFixture/ActivityTests/testNestedActivityFailure
assert_status 1
[[ "$output" =~ "    t =     0.0"[0-9]"s Log in" ]] || fail "expected a t = line for the activity"
[[ "$output" =~ "    t =     0.0"[0-9]"s     Enter password" ]] || fail "expected an indented t = line for the nested activity"
assert_contains "ActivityFixture.m:21: error: -[ActivityTests testNestedActivityFailure] : Log in > Enter password: failed: wrong password"

echo "Activity tests passed."
