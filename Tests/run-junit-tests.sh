#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

build_fixture LifecycleFixture
build_fixture AsyncFixture

report_dir=$(mktemp -d)
trap 'rm -rf "$report_dir"' EXIT
report="$report_dir/report.xml"

check_well_formed() {
  if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$1" || fail "JUnit report is not well-formed XML"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys, xml.dom.minidom; xml.dom.minidom.parse(sys.argv[1])' "$1" \
      || fail "JUnit report is not well-formed XML"
  fi
}

echo "Running JUnit report regressions..."
run_fixture LifecycleFixture -junit-report "$report" \
  -only-testing:LifecycleFixture/TestThrowsTests \
  -only-testing:LifecycleFixture/TearDownFailsTests \
  -only-testing:LifecycleFixture/SkipConditionTests \
  -only-testing:LifecycleFixture/ClassSetUpThrowsTests \
  -only-testing:LifecycleFixture/ClassTearDownThrowsTests \
  -only-testing:LifecycleFixture/OrderTests
assert_status 1
[ -f "$report" ] || fail "expected a JUnit report at $report"
check_well_formed "$report"
output=$(cat "$report")

assert_contains '<testsuites name="LifecycleFixture.bundle" tests="12" failures="1" errors="3" skipped="2" time="'
assert_contains '<testsuite name="OrderTests" tests="3" failures="0" errors="0" skipped="0" time="'
assert_contains '<testcase classname="OrderTests" name="testA" time="'
# Assertion failures are <failure>s with their location.
assert_contains '<failure message="failed: fixture tearDown failure" type="XCTestFailure">LifecycleFixture.m:118: failed: fixture tearDown failure</failure>'
# Uncaught exceptions are <error>s.
assert_contains '<error message="threw exception: &quot;NSInternalInconsistencyException&quot;, &quot;fixture exception&quot;" type="UncaughtException">'
# Tests in a class whose +setUp failed carry the cause.
assert_contains '+setUp failed: threw exception: &quot;NSInternalInconsistencyException&quot;, &quot;fixture +setUp exception&quot;'
# Skips.
assert_contains '<skipped message="LifecycleFixture.m:216: (1 + 1 == 2) is true: fixture skipIf"/>'
# A failed +tearDown becomes an extra case; text is escaped.
assert_contains '<testsuite name="ClassTearDownThrowsTests" tests="2" failures="0" errors="1" skipped="0"'
assert_contains '<testcase classname="ClassTearDownThrowsTests" name="+tearDown" time="0.000">'
assert_contains 'fixture +tearDown &lt;exception&gt; &amp; &quot;quotes&quot;'

# A passing run writes a report with no failures and exits 0.
rm -f "$report"
run_fixture AsyncFixture -junit-report "$report" -only-testing:AsyncFixture/AsyncPassingTests
assert_status 0
check_well_formed "$report"
output=$(cat "$report")
assert_contains '<testsuites name="AsyncFixture.bundle" tests="12" failures="0" errors="0" skipped="0"'

# Not being able to write the report fails the run.
run_fixture AsyncFixture -junit-report "$report_dir/missing/report.xml" -only-testing:AsyncFixture/AsyncPassingTests
assert_status 1
assert_contains "Could not write JUnit report"

run_fixture AsyncFixture -junit-report
assert_status 1
assert_contains "missing path for -junit-report"

echo "JUnit report tests passed."
