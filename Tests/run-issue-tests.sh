#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

build_fixture IssueFixture

echo "Running issue regressions..."
run_fixture IssueFixture
assert_status 1

# -recordIssue: sees assertion failures and uncaught exceptions, with types
# and locations, and can drop or rewrite them.
assert_contains "fixture: recordIssue -[RecordIssueOverrideTests testAssertionFails] type=0 at IssueFixture.m:72 '((1) equal to (2)) failed"
assert_contains "fixture: recordIssue -[RecordIssueOverrideTests testThrows] type=2 at - 'threw exception: \"NSInternalInconsistencyException\", \"fixture exception\"'"
assert_contains "fixture: recordIssue -[RecordIssueOverrideTests testIgnoredFailure] type=0 at IssueFixture.m:74 'failed: ignorable'"
assert_not_contains "testIgnoredFailure FAILED"
assert_contains "Assertion FAILED at IssueFixture.m:75, rewritten by recordIssue:"
# An issue recorded directly keeps its type and location.
assert_contains "fixture: recordIssue -[RecordIssueOverrideTests testRecordsIssueDirectly] type=4 at Custom.m:7 'recorded directly'"
assert_contains "Assertion FAILED at Custom.m:7, recorded directly"
assert_contains "XCTest:   RecordIssueOverrideTests: 4/5 tests FAILED"

# A failing -setUpWithError: is a thrown error that carries the error.
assert_contains "fixture: setUpWithError issue type=1 error=FixtureDomain/42"
assert_not_contains "SetUpErrorTests body ran"

# With both methods overridden, each sees an issue exactly once, whichever
# is called first, and the legacy override's changes are kept.
both=$(printf '%s\n' "$output" | grep -o "fixture: both .*" | paste -sd '|' -)
expected="fixture: both recordIssue 'failed: from assertion'"
expected+="|fixture: both recordFailure 'failed: from assertion'"
expected+="|fixture: both recordFailure 'from legacy call'"
expected+="|fixture: both recordIssue 'from legacy call (legacy edit)'"
[ "$both" = "$expected" ] || fail "unexpected override calls: $both"
assert_contains "Assertion FAILED at IssueFixture.m:135, failed: from assertion (legacy edit)"
assert_contains "Assertion FAILED at Legacy.m:3, from legacy call (legacy edit)"

# XCTExpectFailure matchers see the issue's type and location; an
# unmatched expectation is its own issue type.
assert_contains "fixture: matcher type=0 at IssueFixture.m:158"
assert_contains "Expected failure (known bug) at IssueFixture.m:158, failed: expected one"
assert_contains "fixture: matcher-test recordIssue type=5 'Failed due to unmatched expected failure: never fails'"

# Observers get testCase:didRecordIssue: for failures, but not for
# expected ones or dropped ones.
assert_contains "observer: -[RecordIssueOverrideTests testThrows] issue type=2 'threw exception"
assert_contains "observer: -[RecordIssueOverrideTests testRewrittenFailure] issue type=0 'rewritten by recordIssue:'"
assert_contains "observer: -[SetUpErrorTests testNeverRuns] issue type=1 'failed in setUpWithError: - set up broke'"
assert_not_contains "observer: -[IssueMatcherTests testMatcherSeesTypeAndLocation]"
assert_not_contains "issue type=0 'failed: ignorable'"

assert_contains "XCTest:   IssueCopyingTests: 1 tests PASSED"

echo "Issue tests passed."
