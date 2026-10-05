#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

build_fixture ParallelFixture

report_dir=$(mktemp -d)
trap 'rm -rf "$report_dir"' EXIT

echo "Running parallel execution regressions..."

# Four one-second classes with four workers take about a second, each in
# its own process, and the results are merged.
start=$(date +%s%N)
run_fixture ParallelFixture -parallel-testing-worker-count 4 -junit-report "$report_dir/parallel.xml"
elapsed_ms=$(( ($(date +%s%N) - start) / 1000000 ))
assert_status 1
[ "$elapsed_ms" -lt 3500 ] || fail "expected the slow classes to run in parallel (took ${elapsed_ms}ms)"
assert_contains "XCTest: Running 6 test classes in parallel, 4 at a time"
pids=$(printf '%s\n' "$output" | sed -n 's/.*parallel: Slow[A-D] first in pid \([0-9]*\).*/\1/p' | sort -u | wc -l)
[ "$pids" -eq 4 ] || fail "expected each class in its own process, got $pids"
# Each class's output is one block.
blocks=$(printf '%s\n' "$output" | grep -oE 'Running Slow[A-D]Tests|Slow[A-D]Tests: 2 tests PASSED|parallel: Slow[A-D] (first|second)' | sed 's/.*Slow\([A-D]\).*/\1/' | uniq | wc -l)
[ "$blocks" -eq 4 ] || fail "expected each class's output to stay together"
assert_contains "XCTest:   FailingTests: 1/4 tests FAILED, 1 skipped"
assert_contains "XCTest:   FailingTests.testFails: ParallelFixture.m:45: failed: fails in a worker"
assert_contains "XCTest: 1/6 test cases FAILED (1 test skipped)"
[ "$(printf '%s\n' "$output" | grep -c 'XCTest: Running Unit Tests')" -eq 1 ] || fail "expected one run header"
grep -q '<testsuites name="ParallelFixture.bundle" tests="14" failures="1" errors="0" skipped="1"' "$report_dir/parallel.xml" \
  || fail "expected a merged JUnit report"
grep -q 'measured \[Time, seconds\]' "$report_dir/parallel.xml" || fail "expected measurements in the JUnit report"

# A crashing worker fails its own class's unreported tests; others run.
PARALLEL_FIXTURE_CRASH=1 run_fixture ParallelFixture -parallel-testing-enabled YES \
  -only-testing:ParallelFixture/TroubleTests -only-testing:ParallelFixture/FailingTests
assert_status 1
assert_contains "xctest: the process running TroubleTests exited (signal 6) without reporting its results"
assert_contains "TroubleTests.testCrashes: The test process exited (signal 6) before reporting this test's result"
assert_contains "XCTest:   FailingTests: 1/4 tests FAILED, 1 skipped"

# With time limits, a hung test stops only its own worker.
start=$(date +%s)
PARALLEL_FIXTURE_HANG=1 run_fixture ParallelFixture -parallel-testing-enabled YES -default-test-execution-time-allowance 1 \
  -only-testing:ParallelFixture/TroubleTests -only-testing:ParallelFixture/SlowATests
assert_status 1
[ $(( $(date +%s) - start )) -lt 15 ] || fail "expected the hung worker to be stopped promptly"
assert_contains "testHangs: Test exceeded execution time allowance of 1 second"
assert_contains "XCTest:   SlowATests: 2 tests PASSED"

# Apple-format output keeps one run header and footer.
run_fixture ParallelFixture -parallel-testing-enabled YES -output-format apple \
  -only-testing:ParallelFixture/FailingTests -only-testing:ParallelFixture/SlowATests
assert_status 1
[ "$(printf '%s\n' "$output" | grep -c "Test Suite 'Selected tests' started")" -eq 1 ] || fail "expected one run header"
assert_contains "Test Suite 'SlowATests' passed at "
assert_contains "Executed 6 tests, with 1 test skipped and 1 failure (0 unexpected)"
assert_contains $'Failing tests:\n\t-[FailingTests testFails]'

# Random order: the coordinator logs the seed once and workers use it.
run_fixture ParallelFixture -parallel-testing-enabled YES -test-execution-order-seed 7 -only-testing:ParallelFixture/FailingTests
[ "$(printf '%s\n' "$output" | grep -c 'random order (seed 7')" -eq 1 ] || fail "expected the seed to be logged once"

# Workers save attachments where a single run would.
build_fixture AttachmentFixture
run_fixture AttachmentFixture -parallel-testing-enabled YES -junit-report "$report_dir/attachments.xml"
assert_status 1
[ -e "$report_dir/attachments-attachments/AttachmentTests/testFailingKeepsAll/blob.bin" ] \
  || fail "expected workers to save attachments next to the report"
grep -q "\[\[ATTACHMENT|$report_dir/attachments-attachments/AttachmentTests/testIssueAttachment/evidence.txt\]\]" "$report_dir/attachments.xml" \
  || fail "expected attachments in the merged JUnit report"

# Combinations that aren't supported.
run_fixture ParallelFixture -parallel-testing-enabled YES -host /nonexistent.app
assert_status 1
assert_contains "-parallel-testing-enabled can't be used with -host"
run_fixture ParallelFixture -parallel-testing-enabled YES -performance-baselines "$report_dir/b.json" -update-performance-baselines
assert_status 1
assert_contains "-update-performance-baselines can't be used with -parallel-testing-enabled"
run_fixture ParallelFixture -parallel-testing-worker-count 0
assert_status 1
assert_contains "-parallel-testing-worker-count needs a number of at least 1"

echo "Parallel tests passed."
