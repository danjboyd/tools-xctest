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

# Every run gets this scratch TMPDIR, so the processes it starts can be
# found and ended afterwards, whatever happened to the run: xvfb-run's own
# cleanup stops its Xvfb only if it gets that far (it exits early, leaving
# Xvfb running, when it can't remove its temporary directory, and not at
# all when it's killed). Xvfb names a file under the TMPDIR on its command
# line; the app and xctest inherit TMPDIR.
owned_tmp=$(mktemp -d "${TMPDIR:-/tmp}/xctest-ui-thread.XXXXXX")
owned_tmp=$(cd "$owned_tmp" && pwd -P)

# A process's start time (clock ticks since boot), to tell it apart from a
# later process that reuses its pid.
proc_start() {
  local stat fields
  stat=$(cat "/proc/$1/stat" 2>/dev/null) || return 1
  fields=${stat##*) }
  set -- $fields
  echo "${20}"
}

# "pid:start" for each process this script's runs started: an argument
# that is $owned_tmp or under it, or TMPDIR=$owned_tmp in its environment.
# Never the harness itself or its parent. The number of processes whose
# environment couldn't be read (other users') goes to $owned_tmp/unreadable,
# to be reported, not assumed absent. (It's run in $(...), so it can't set
# a variable.)
owned_pids() {
  local dir pid start unreadable=0
  for dir in /proc/[0-9]*; do
    pid=${dir#/proc/}
    case "$pid" in "$$"|"$BASHPID"|"$PPID") continue ;; esac
    if { tr '\0' '\n' < "$dir/cmdline"; } 2>/dev/null \
         | awk -v d="$owned_tmp" '$0 == d || index($0, d "/") == 1 { found = 1 } END { exit !found }' \
       || { tr '\0' '\n' < "$dir/environ"; } 2>/dev/null | grep -qxF -- "TMPDIR=$owned_tmp"; then
      start=$(proc_start "$pid") && echo "$pid:$start"
    elif [ -e "$dir" ] && ! [ -r "$dir/environ" ]; then
      unreadable=$((unreadable + 1))
    fi
  done
  echo "$unreadable" > "$owned_tmp/unreadable"
}

# Sends \a signal to each listed "pid:start" still alive with that same
# start time.
signal_owned() {
  local signal=$1 entry
  shift
  for entry in "$@"; do
    [ "$(proc_start "${entry%%:*}")" = "${entry#*:}" ] && kill "-$signal" "${entry%%:*}" 2>/dev/null || true
  done
}

# Ends any owned process still running: TERM, then KILL after 5 s, then
# rescans for up to 5 s more. Sets $leftover to the "pid:start" entries it
# found (printing each one's command line first, as a receipt) and
# $residual to any still running at the end; returns 1 if there are any.
end_owned_processes() {
  local entries entry
  residual=
  leftover=$(owned_pids | tr '\n' ' ')
  [ -n "${leftover// }" ] || return 0
  for entry in $leftover; do
    echo "owned process ${entry%%:*} (start ${entry#*:}): $({ tr '\0' ' ' < "/proc/${entry%%:*}/cmdline"; } 2>/dev/null | cut -c1-160)"
  done
  signal_owned TERM $leftover
  for _ in 1 2 3 4 5; do
    entries=$(owned_pids | tr '\n' ' ')
    [ -n "${entries// }" ] || return 0
    sleep 1
  done
  signal_owned KILL $entries
  for _ in 1 2 3 4 5; do
    entries=$(owned_pids | tr '\n' ' ')
    [ -n "${entries// }" ] || return 0
    sleep 1
  done
  residual=$entries
  echo "owned processes still running after KILL (pid:start): $residual"
  return 1
}

# On every exit: end what's left. Only when nothing owned is still running
# is the scratch directory (and its private GNUstep configuration) removed;
# otherwise it's kept for inspection, and the script fails.
cleanup_owned() {
  local status=$?
  if end_owned_processes; then
    rm -r "$owned_tmp" 2>/dev/null || true
  else
    echo "Cleanup incomplete; kept $owned_tmp" >&2
    status=1
  fi
  exit "$status"
}
trap cleanup_owned EXIT

# A private GNUstep configuration: the one in use, with the user's
# directories and defaults database under $owned_tmp. GNUstep ignores a
# configuration file that group or others can write, so it's 0600.
base_conf=${GNUSTEP_CONFIG_FILE:-$(sed -n 's/^ *GNUSTEP_CONFIG_FILE=//p' "$GNUSTEP_MAKEFILES/GNUstep.sh" 2>/dev/null | head -n 1)}
private_conf="$owned_tmp/GNUstep.conf"
mkdir -p "$owned_tmp/home/GNUstep/Library" "$owned_tmp/defaults"
{
  [ ! -r "$base_conf" ] || sed -E '/^GNUSTEP_USER_[A-Z_]*=/d' "$base_conf"
  echo "GNUSTEP_USER_CONFIG_FILE=$owned_tmp/no-user.conf"
  echo "GNUSTEP_USER_DIR=$owned_tmp/home/GNUstep"
  echo "GNUSTEP_USER_DEFAULTS_DIR=$owned_tmp/defaults"
  echo "GNUSTEP_USER_DIR_LIBRARY=$owned_tmp/home/GNUstep/Library"
} > "$private_conf"
chmod 600 "$private_conf"

# The environment of every run below.
run_env=(env TMPDIR="$owned_tmp" HOME="$owned_tmp/home"
  GNUSTEP_CONFIG_FILE="$private_conf" UITHREAD_DEFAULTS_ROOT="$owned_tmp/defaults"
  LD_LIBRARY_PATH="$xctest_lib_dir${runtime_lib_dirs:+:$runtime_lib_dirs}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}")

# Before anything can write defaults: check, in this runtime, that the
# defaults database resolves under $owned_tmp. Stop otherwise.
set +e
output=$("${run_env[@]}" "$xctest_bin" "$source_root/Tests/UIThreadFixture/UIThreadFixture.bundle" \
  -only-testing:UIThreadFixture/UIThreadDefaultsRootTests 2>&1)
status=$?
set -e
assert_status 0
assert_contains "uithread: defaults root $owned_tmp/defaults"

# run_ui [xctest args...] sets $output, $status and $elapsed (seconds).
# UI_RUN_LIMIT (default 120 s) and UI_RUN_SIGNAL bound the run; normally
# timeout signals the run's whole process group. UI_RUN_FOREGROUND=yes
# signals only xvfb-run, as when it dies on its own.
run_ui() {
  local start
  start=$(date +%s)
  set +e
  output=$("${run_env[@]}" \
    timeout ${UI_RUN_FOREGROUND:+--foreground} -s "${UI_RUN_SIGNAL:-TERM}" -k 5 "${UI_RUN_LIMIT:-120}" \
    "${display_wrapper[@]}" \
    "$xctest_bin" -host "$host_app" \
    "$source_root/Tests/UIThreadFixture/UIThreadFixture.bundle" "$@" 2>&1)
  status=$?
  set -e
  elapsed=$(( $(date +%s) - start ))
  # Nothing a finished run started may outlive it.
  end_owned_processes || fail "processes the run started are still running after KILL: $residual"
  [ -z "${leftover// }" ] || echo "run_ui: ended processes the run left behind (pid:start): $leftover"
  echo "run_ui: $(cat "$owned_tmp/unreadable") other users' processes couldn't be checked for ownership"
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
# The timed-out query is counted as still running, not just its modal.
[ "$(printf '%s\n' "$output" | grep -c 'testCQueryEntersAModal: the test ended with 1 action(s) still running and a modal session open')" -ge 1 ] \
  || fail "expected teardown to count the timed-out query as still running"
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
set +e
output=$("${run_env[@]}" "$xctest_bin" "$source_root/Tests/UIThreadFixture/UIThreadFixture.bundle" \
  -only-testing:UIThreadFixture/UIThreadInactiveTests 2>&1)
status=$?
set -e
assert_status 0
assert_contains "uithread: inactive mode runs inline"

# The harness's own cleanup: xvfb-run killed outright (SIGKILL, so it
# can't stop its Xvfb) while the app hangs. xctest gives up on the app
# after 5 s; the orphaned Xvfb is found and ended. Nothing owned may
# remain afterwards.
if [ ${#display_wrapper[@]} -gt 0 ]; then
  HOSTAPP_HANG=1 UI_RUN_LIMIT=2 UI_RUN_SIGNAL=KILL UI_RUN_FOREGROUND=yes run_ui -host-launch-timeout 5 \
    -only-testing:UIThreadFixture/UIThreadAOrdinaryTests
  [ "$status" -eq 137 ] || fail "expected the run to be killed at its limit (status $status)"
  [ -n "${leftover// }" ] || fail "expected the killed run to leave processes for the harness to end"
  [ -z "$(owned_pids)" ] || fail "expected no owned processes after cleanup: $(owned_pids)"
fi

# A process that ignores TERM (the shell and its sleep both inherit the
# ignored signal) is ended with KILL, identified by its exact pid and start
# time, and nothing owned remains.
env TMPDIR="$owned_tmp" setsid sh -c 'trap "" TERM; sleep 60' < /dev/null > /dev/null 2>&1 &
stubborn=$!
sleep 0.5
stubborn_id="$stubborn:$(proc_start "$stubborn")"
end_owned_processes || fail "expected the TERM-ignoring process to be ended: $residual"
case " $leftover " in
  *" $stubborn_id "*) ;;
  *) fail "expected the cleanup to name the TERM-ignoring process $stubborn_id, got: $leftover" ;;
esac
[ -z "$(owned_pids)" ] || fail "expected no owned processes after KILL: $(owned_pids)"

make -C "$source_root/Tests/UIThreadFixture" clean > /dev/null
echo "UI test thread regressions passed."
