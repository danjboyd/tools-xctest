#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

# Hosted tests need an X server. Use a private Xvfb when available so no
# windows appear on the desktop; otherwise fall back to $DISPLAY.
if command -v xvfb-run >/dev/null 2>&1; then
  display_wrapper=(xvfb-run -a)
elif [ -n "${DISPLAY:-}" ]; then
  display_wrapper=()
else
  echo "Skipping hosted tests: no X display and no xvfb-run."
  exit 0
fi

echo "Building HostApp..."
make -C "$source_root/Tests/HostApp" clean all
build_fixture HostedFixture

host_app="$source_root/Tests/HostApp/HostApp.app"

run_hosted() {
  set +e
  output=$(LD_LIBRARY_PATH="$xctest_lib_dir${runtime_lib_dirs:+:$runtime_lib_dirs}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    "${display_wrapper[@]}" "$xctest_bin" -host "$host_app" \
    "$source_root/Tests/HostedFixture/HostedFixture.bundle" "$@" 2>&1)
  status=$?
  set -e
}

echo "Running hosted test regressions..."
run_hosted -only-testing:HostedFixture/HostedTests
assert_status 0
assert_contains "hostapp: launched"
assert_contains "HostedTests: 4 tests PASSED"
assert_not_contains " SKIPPED at "
# The app finished launching before the tests started.
launch_line=$(printf '%s\n' "$output" | grep -n 'hostapp: launched' | cut -d: -f1)
start_line=$(printf '%s\n' "$output" | grep -n 'XCTest: Running Unit Tests' | cut -d: -f1)
[ "$launch_line" -lt "$start_line" ] || fail "expected the tests to start after the app launched"

# Failures in the host give a failing exit status.
run_hosted
assert_status 1
assert_contains "HostedFailureTests.testFailsInHost: HostedFixture.m:"

# Output options apply in the host.
report_dir=$(mktemp -d)
trap 'rm -rf "$report_dir"' EXIT
run_hosted -output-format apple -junit-report "$report_dir/hosted.xml" -only-testing:HostedFixture/HostedTests
assert_status 0
assert_contains "Test Case '-[HostedTests testCanSeeTheApplicationsWindows]' passed ("
grep -q '<testsuite name="HostedTests" tests="4" failures="0"' "$report_dir/hosted.xml" \
  || fail "expected a JUnit report from the host"

# An app that quits without launching is an error, not a pass.
HOSTAPP_EXIT_EARLY=1 run_hosted
assert_status 1
assert_contains "host application exited (status 0) before running the tests"

# An app that never finishes launching is stopped after the launch timeout.
start=$(date +%s)
HOSTAPP_HANG=1 run_hosted -host-launch-timeout 2
elapsed=$(( $(date +%s) - start ))
assert_status 1
assert_contains "host application didn't start the tests within 2 seconds"
[ "$elapsed" -lt 15 ] || fail "expected the hung app to be stopped promptly (took ${elapsed}s)"

# The timeout only covers launching, not the tests themselves.
run_hosted -host-launch-timeout 2 -only-testing:HostedFixture/HostedSlowTests
assert_status 0
assert_contains "HostedSlowTests: 1 tests PASSED"

# Attachments are saved from the host; images are encoded as PNG.
run_hosted -attachments-path "$report_dir/hosted-attachments" -only-testing:HostedFixture/HostedAttachmentTests
assert_status 0
[ "$(head -c 8 "$report_dir/hosted-attachments/HostedAttachmentTests/testAttachesImage/swatch.png" | od -An -tx1 | tr -d ' \n')" = "89504e470d0a1a0a" ] \
  || fail "expected a PNG attachment from the host"

# Test time limits apply in the host; running out of time still reports.
run_hosted -default-test-execution-time-allowance 1 -only-testing:HostedFixture/HostedSlowTests
assert_status 1
assert_contains "testSlow: Test exceeded execution time allowance of 1 second"
assert_contains "exceeded its execution time allowance of 1 second; stopping the run"
assert_not_contains "before running the tests"

run_hosted -host-launch-timeout soon
assert_status 1
assert_contains "-host-launch-timeout needs a number of seconds"

# A relative -host path works too.
set +e
output=$(cd "$source_root/Tests" && LD_LIBRARY_PATH="$xctest_lib_dir${runtime_lib_dirs:+:$runtime_lib_dirs}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  "${display_wrapper[@]}" "$xctest_bin" -host HostApp/HostApp.app \
  HostedFixture/HostedFixture.bundle -only-testing:HostedFixture/HostedTests 2>&1)
status=$?
set -e
assert_status 0
assert_not_contains "requires absolute path"
assert_contains "HostedTests: 4 tests PASSED"

run_hosted_missing() {
  set +e
  output=$(LD_LIBRARY_PATH="$xctest_lib_dir${runtime_lib_dirs:+:$runtime_lib_dirs}" \
    "$xctest_bin" -host "$source_root/Tests/HostApp/Missing.app" \
    "$source_root/Tests/HostedFixture/HostedFixture.bundle" 2>&1)
  status=$?
  set -e
}
run_hosted_missing
assert_status 1
assert_contains "could not find host application"

# Without a host the tests skip rather than fail.
run_fixture HostedFixture -only-testing:HostedFixture/HostedTests
assert_status 0
assert_contains "HostedTests: 0 tests PASSED, 4 skipped"

echo "Hosted tests passed."
