#!/usr/bin/env bash
#
# SPIKE (#26), not production code and not part of make check. Runs
# Tests/UIThreadSpikeFixture in Tests/HostApp with the loader's spike test
# thread (XCTEST_SPIKE_UI_TEST_THREAD). Isolated: a private Xvfb
# (xvfb-run -a), a scratch HOME and GNUstep user configuration, a hard
# outer timeout, and cleanup of only the processes it started.
#
# usage: Tests/run-ui-thread-spike.sh <base GNUstep.conf>

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
base_conf=${1:?usage: $0 <base GNUstep.conf>}
limit=${SPIKE_TIME_LIMIT:-90}

work=$(mktemp -d "${TMPDIR:-/tmp}/xctest-ui-spike.XXXXXX")
cleanup() {
  # Only processes whose command line or environment names this run's
  # scratch directory are ours.
  for pid in $(pgrep -f "$work" 2>/dev/null || true); do
    kill -TERM "$pid" 2>/dev/null || true
  done
  rm -r "$work"
}
trap cleanup EXIT

# The scratch GNUstep configuration: the base one without its user keys,
# with every user directory under $work.
sed -E '/^GNUSTEP_USER_(CONFIG_FILE|DEFAULTS_DIR|DIR[A-Z_]*)=/d' "$base_conf" > "$work/GNUstep.conf"
cat >> "$work/GNUstep.conf" <<EOF
GNUSTEP_USER_CONFIG_FILE=$work/no-user.conf
GNUSTEP_USER_DIR=$work/home/GNUstep
GNUSTEP_USER_DEFAULTS_DIR=$work/defaults
GNUSTEP_USER_DIR_LIBRARY=$work/home/GNUstep/Library
GNUSTEP_USER_DIR_APPS=$work/home/GNUstep/Applications
GNUSTEP_USER_DIR_TOOLS=$work/home/GNUstep/Tools
EOF
chmod 600 "$work/GNUstep.conf"
mkdir -p "$work/home" "$work/defaults" "$work/run" "$work/tmp"
chmod 700 "$work/run"
export GNUSTEP_CONFIG_FILE="$work/GNUstep.conf" GNUSTEP_USER_CONFIG_FILE="$work/no-user.conf"
export HOME="$work/home" TMPDIR="$work/tmp" XDG_RUNTIME_DIR="$work/run"
export XDG_CONFIG_HOME="$work/config" XDG_DATA_HOME="$work/data" XDG_CACHE_HOME="$work/cache"
unset DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS

set +eu
. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -eu

make -s -C "$root" > "$work/build.log" 2>&1 || { tail -20 "$work/build.log"; exit 2; }
make -s -C "$root/Tests/HostApp" > "$work/hostapp.log" 2>&1 || { tail -20 "$work/hostapp.log"; exit 2; }
make -s -C "$root/Tests/UIThreadSpikeFixture" > "$work/fixture.log" 2>&1 || { tail -20 "$work/fixture.log"; exit 2; }

export LD_LIBRARY_PATH="$root/XCTest/obj${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export XCTEST_SPIKE_UI_TEST_THREAD=1

set +e
timeout -k 5 "$limit" xvfb-run -a -s "-nolisten tcp" \
  "$root/obj/xctest" -host "$root/Tests/HostApp/HostApp.app" \
  "$root/Tests/UIThreadSpikeFixture/UIThreadSpikeFixture.bundle" \
  -default-test-execution-time-allowance 30 > "$work/run.log" 2>&1
status=$?
set -e

cat "$work/run.log"
echo "spike: exit status $status (124 means the ${limit} s limit was hit)"
leftover=$(pgrep -f "$work" 2>/dev/null || true)
[ -z "$leftover" ] || echo "spike: processes left over (cleaned up): $leftover"
exit "$status"
