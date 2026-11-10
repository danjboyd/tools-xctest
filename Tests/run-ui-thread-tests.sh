#!/usr/bin/env bash
#
# The UI test thread for hosted tests: classes that opt in run on a test
# thread and reach the app through GSXCTestMainThread; the others still run
# on the main thread. The design is in issue #26.

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

# Like the hosted tests, these need an X server: a private Xvfb when
# available, so no windows appear on the desktop.
if command -v xvfb-run >/dev/null 2>&1; then
  display_wrapper=(xvfb-run -a)
elif [ -n "${DISPLAY:-}" ]; then
  display_wrapper=()
else
  echo "Skipping UI test thread tests: no X display and no xvfb-run."
  exit 0
fi

echo "Building HostApp..."
make -C "$source_root/Tests/HostApp" clean all
build_fixture UIThreadFixture

host_app="$source_root/Tests/HostApp/HostApp.app"

# run_ui [xctest args...] sets $output, $status and $elapsed (seconds).
run_ui() {
  local start
  start=$(date +%s)
  set +e
  output=$(LD_LIBRARY_PATH="$xctest_lib_dir${runtime_lib_dirs:+:$runtime_lib_dirs}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    timeout -k 5 120 "${display_wrapper[@]}" "$xctest_bin" -host "$host_app" \
    "$source_root/Tests/UIThreadFixture/UIThreadFixture.bundle" "$@" 2>&1)
  status=$?
  set -e
  elapsed=$(( $(date +%s) - start ))
}

echo "Running UI test thread regressions..."

# The opted-in class drives a modal alert from the test thread; the
# ordinary classes before and after it run on the main thread, in order.
run_ui -skip-testing:UIThreadFixture/UIThreadTeardownTests -skip-testing:UIThreadFixture/UIThreadWedgedTests \
  -skip-testing:UIThreadFixture/UIThreadYBlocksBetweenClassesTests -skip-testing:UIThreadFixture/UIThreadInactiveTests
assert_status 0
assert_contains "UIThreadAOrdinaryTests: 1 tests PASSED"
assert_contains "UIThreadDispatchTests: 4 tests PASSED"
assert_contains "UIThreadZOrdinaryTests: 1 tests PASSED"
assert_contains "uithread: ordinary class before ran on the main thread"
assert_contains "uithread: alert opened and dismissed"
assert_contains "uithread: blocked main thread reported"
assert_contains "uithread: ordinary class after ran on the main thread"
order=$(printf '%s\n' "$output" | grep -o 'uithread: [a-z]* class [a-z]*' | tr '\n' '|')
[ "$order" = "uithread: ordinary class before|uithread: ordinary class after|" ] \
  || fail "expected the classes to run in their usual order, got: $order"

# Without an opted-in class in the run, nothing changes: every test runs
# on the main thread (as the hosted tests check in detail).
run_ui -only-testing:UIThreadFixture/UIThreadAOrdinaryTests
assert_status 0
assert_contains "UIThreadAOrdinaryTests: 1 tests PASSED"

# A test that leaves an alert open fails, and teardown ends the alert so
# the next test starts clean; the same for a query that entered a modal
# loop and timed out.
run_ui -only-testing:UIThreadFixture/UIThreadTeardownTests
assert_status 1
assert_contains "the test ended with 1 action(s) still running and a modal session open; they were ended"
assert_contains "testALeavesAnAlertOpen FAILED"
assert_contains "uithread: next test started clean"
assert_not_contains "testBStartsClean FAILED"
assert_contains "testCQueryEntersAModal FAILED"
assert_contains "uithread: started clean again"
assert_not_contains "testDStartsCleanAgain FAILED"

# An application whose main thread stops responding: the test fails, the
# rest fail without running, and the run ends without waiting for it.
run_ui -only-testing:UIThreadFixture/UIThreadWedgedTests -only-testing:UIThreadFixture/UIThreadZOrdinaryTests
assert_status 1
assert_contains "the application stopped responding after the test"
assert_contains "not run: the application stopped responding in an earlier test"
assert_contains "testBNeverRuns FAILED"
assert_contains "testRunsOnTheMainThreadAfterTheUIClass FAILED"
assert_not_contains "uithread: a test ran after the application stopped responding"
[ "$elapsed" -lt 25 ] || fail "expected the run to end without waiting for the main thread (took ${elapsed}s)"

# The main thread stops answering between classes: the next class's
# hand-off to the main thread is bounded, so it fails without running and
# the run ends without waiting.
run_ui -only-testing:UIThreadFixture/UIThreadYBlocksBetweenClassesTests -only-testing:UIThreadFixture/UIThreadZOrdinaryTests
assert_status 1
assert_contains "uithread: class before the blocked hand-off ran"
assert_contains "UIThreadYBlocksBetweenClassesTests: 1 tests PASSED"
assert_contains "not run: the application stopped responding in an earlier test"
assert_contains "testRunsOnTheMainThreadAfterTheUIClass FAILED"
assert_not_contains "uithread: ordinary class after ran on the main thread"
[ "$elapsed" -lt 25 ] || fail "expected the run to end without waiting for the main thread (took ${elapsed}s)"

# Without -host, the opt-in has no effect and everything runs inline.
run_fixture UIThreadFixture -only-testing:UIThreadFixture/UIThreadInactiveTests
assert_status 0
assert_contains "uithread: inactive mode runs inline"

make -C "$source_root/Tests/UIThreadFixture" clean > /dev/null
echo "UI test thread regressions passed."
