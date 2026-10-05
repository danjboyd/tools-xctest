#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

build_fixture AttachmentFixture

report_dir=$(mktemp -d)
trap 'rm -rf "$report_dir"' EXIT

echo "Running attachment regressions..."

# Without -attachments-path or -junit-report nothing is saved.
run_fixture AttachmentFixture
assert_status 1
assert_not_contains " saved to "
assert_contains "XCTest: Attachment 'class-level' added outside of a running test; ignored."
assert_contains "XCTest:   AttachmentTests: 3/5 tests FAILED"

# With a JUnit report, attachments go next to it.
run_fixture AttachmentFixture -junit-report "$report_dir/results.xml"
assert_status 1
dir="$report_dir/results-attachments/AttachmentTests"

# A passing test keeps only KeepAlways attachments.
[ "$(cat "$dir/testPassingKeepsOnlyKeepAlways/notes.txt")" = "kept text" ] || fail "expected the kept attachment"
[ ! -e "$dir/testPassingKeepsOnlyKeepAlways/dropped.txt" ] || fail "expected the default lifetime to drop a passing test's attachment"
[ ! -e "$dir/testAttachmentProperties" ] || fail "expected no folder for a test without kept attachments"

# A failing test keeps everything, named by name and type.
kept=$(cd "$dir/testFailingKeepsAll" && ls | LC_ALL=C sort | paste -sd ' ' -)
[ "$kept" = "Attachment.txt a_b.txt archive.plist attachment-fixture.log blob.bin dup-2.txt dup.txt settings.plist" ] \
  || fail "unexpected saved attachments: $kept"
[ "$(cat "$dir/testFailingKeepsAll/attachment-fixture.log")" = "log line" ] || fail "expected the file's contents"
[ "$(cat "$dir/testFailingKeepsAll/dup-2.txt")" = "second" ] || fail "expected the second duplicate"
grep -q "<key>key</key>" "$dir/testFailingKeepsAll/settings.plist" || fail "expected an XML property list"

# Attachments from activities and issues.
[ "$(cat "$dir/testActivityAttachment/inside.txt")" = "from activity" ] || fail "expected the activity's attachment"
assert_contains "Attachment 'inside' (in Capture) saved to $dir/testActivityAttachment/inside.txt"
[ "$(cat "$dir/testIssueAttachment/evidence.txt")" = "issue data" ] || fail "expected the issue's attachment"

# The JUnit report links them.
grep -q "\[\[ATTACHMENT|$dir/testFailingKeepsAll/blob.bin\]\]" "$report_dir/results.xml" \
  || fail "expected attachment links in the JUnit report"
grep -q "\[\[ATTACHMENT|$dir/testPassingKeepsOnlyKeepAlways/notes.txt\]\]" "$report_dir/results.xml" \
  || fail "expected a passing test's kept attachment in the JUnit report"

# -attachments-path chooses the directory; a rerun replaces a test's files.
mkdir -p "$report_dir/custom/AttachmentTests/testFailingKeepsAll"
touch "$report_dir/custom/AttachmentTests/testFailingKeepsAll/stale.txt"
(cd "$report_dir" && run_fixture AttachmentFixture -attachments-path custom -only-testing:AttachmentFixture/AttachmentTests/testFailingKeepsAll)
assert_status 1
[ -e "$report_dir/custom/AttachmentTests/testFailingKeepsAll/blob.bin" ] || fail "expected a relative -attachments-path to work"
[ ! -e "$report_dir/custom/AttachmentTests/testFailingKeepsAll/stale.txt" ] || fail "expected old files to be replaced"
[ ! -e "$report_dir/custom/AttachmentTests/testFailingKeepsAll/dup-3.txt" ] || fail "expected names to restart"

run_fixture AttachmentFixture -attachments-path
assert_status 1
assert_contains "missing directory for -attachments-path"

echo "Attachment tests passed."
