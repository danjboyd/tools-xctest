#!/usr/bin/env bash
#
# -enable-code-coverage and -coverage-output: the run's profiles, from one
# process or from parallel workers, are merged into <dir>/<target>.profdata.

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

# The same search as xctest's, to know whether this can run here.
profdata=${XCTEST_LLVM_PROFDATA:-}
if [ -z "$profdata" ]; then
  profdata=$(command -v llvm-profdata 2>/dev/null || true)
fi
if [ -z "$profdata" ]; then
  profdata=$(IFS=:; for d in $PATH; do ls "$d"/llvm-profdata-[0-9]* 2>/dev/null || true; done \
    | sed 's/.*-\([0-9]*\)\(\.exe\)\{0,1\}$/\1 &/' | sort -n | tail -n 1 | cut -d' ' -f2-)
fi
if [ -z "$profdata" ]; then
  echo "Skipping code coverage regressions: no llvm-profdata on PATH."
  exit 0
fi

build_fixture CoverageFixture
build_fixture FilterFixture

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Without coverage on, the instrumented fixture still writes a profile when
# it's loaded; keep that out of the current directory. With coverage on,
# xctest's own LLVM_PROFILE_FILE replaces this.
export LLVM_PROFILE_FILE="$work/uncollected-%p.profraw"

# The number of times the profile says CoverageFixtureCovered ran.
covered_count() {
  "$profdata" show --all-functions --counts "$1" \
    | awk '/^  CoverageFixtureCovered:/ { found = 1 } found && /Function count:/ { print $3; exit }'
}

# xctest's per-run raw profile directories under $1, and the profiles in them.
raw_directories() {
  find "$1" -mindepth 1 -maxdepth 1 -type d -name 'profraw-*'
}
raw_profiles() {
  find "$1" -mindepth 2 -maxdepth 2 -path '*/profraw-*/*.profraw'
}

echo "Running code coverage regressions..."

run_fixture CoverageFixture -coverage-output "$work/single"
assert_status 0
# (On Windows the path is printed in its native form.)
assert_contains "code coverage written to '"
assert_contains "/single/CoverageFixture.profdata'"
[ -f "$work/single/CoverageFixture.profdata" ] || fail "expected the merged profile"
[ -z "$(raw_directories "$work/single")" ] || fail "expected the raw profiles to be removed after merging"
[ "$(covered_count "$work/single/CoverageFixture.profdata")" = 2 ] \
  || fail "expected CoverageFixtureCovered to be counted twice: $("$profdata" show --all-functions --counts "$work/single/CoverageFixture.profdata")"

# Running again into the same directory replaces the profile: nothing
# from the first run is counted again. Files that were already there,
# including a directory of the caller's named profraw, are left alone.
mkdir -p "$work/single/profraw"
echo keep > "$work/single/profraw/keep.profraw"
echo keep > "$work/single/notes.txt"
run_fixture CoverageFixture -coverage-output "$work/single"
assert_status 0
[ "$(covered_count "$work/single/CoverageFixture.profdata")" = 2 ] \
  || fail "expected a second run not to add to the first run's counts"
[ -f "$work/single/profraw/keep.profraw" ] && [ -f "$work/single/notes.txt" ] \
  || fail "expected files already in the coverage directory to be kept"
[ -z "$(raw_directories "$work/single")" ] || fail "expected only this run's raw profiles to be removed"

# Two runs at once into the same directory don't take each other's
# profiles: each writes a whole profile, so the last one stands.
coverage_env() {
  env LD_LIBRARY_PATH="$xctest_lib_dir${runtime_lib_dirs:+:$runtime_lib_dirs}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" "$@"
}
coverage_env "$xctest_bin" "$source_root/Tests/CoverageFixture/CoverageFixture.bundle" \
  -coverage-output "$work/concurrent" > "$work/first.log" 2>&1 &
first=$!
coverage_env "$xctest_bin" "$source_root/Tests/CoverageFixture/CoverageFixture.bundle" \
  -coverage-output "$work/concurrent" > "$work/second.log" 2>&1 &
second=$!
wait "$first" || { output=$(cat "$work/first.log"); fail "expected the first concurrent run to pass"; }
wait "$second" || { output=$(cat "$work/second.log"); fail "expected the second concurrent run to pass"; }
[ "$(covered_count "$work/concurrent/CoverageFixture.profdata")" = 2 ] \
  || fail "expected concurrent runs each to write a whole profile"
[ -z "$(raw_directories "$work/concurrent")" ] || fail "expected both runs' raw profiles to be removed"

# The same with their replacements at the same moment: each waits a
# second right before replacing the profile. Replacing in one step means
# neither finds the other's file in its way (before, Windows removed the
# profile and then moved the new one in, and the second run could fail).
run_concurrent_pair() {
  coverage_env XCTEST_COVERAGE_TEST_REPLACE_DELAY=1 "$xctest_bin" \
    "$source_root/Tests/CoverageFixture/CoverageFixture.bundle" -coverage-output "$1" > "$work/first.log" 2>&1 &
  first=$!
  coverage_env XCTEST_COVERAGE_TEST_REPLACE_DELAY=1 "$xctest_bin" \
    "$source_root/Tests/CoverageFixture/CoverageFixture.bundle" -coverage-output "$1" > "$work/second.log" 2>&1 &
  second=$!
  wait "$first" || { output=$(cat "$work/first.log"); fail "expected the first of two simultaneous replacements to succeed"; }
  wait "$second" || { output=$(cat "$work/second.log"); fail "expected the second of two simultaneous replacements to succeed"; }
}
run_concurrent_pair "$work/simultaneous"
run_concurrent_pair "$work/simultaneous"
[ "$(covered_count "$work/simultaneous/CoverageFixture.profdata")" = 2 ] \
  || fail "expected simultaneous replacements to leave one whole profile"
[ -z "$(raw_directories "$work/simultaneous")" ] || fail "expected the simultaneous runs' raw profiles to be removed"

# A replacement that fails leaves the previous profile as it was, keeps
# the new merged profile, and fails the run.
run_fixture CoverageFixture -coverage-output "$work/replace-fail"
assert_status 0
set +e
output=$(coverage_env XCTEST_COVERAGE_TEST_REPLACE_FAIL=1 "$xctest_bin" \
  "$source_root/Tests/CoverageFixture/CoverageFixture.bundle" -coverage-output "$work/replace-fail" 2>&1)
status=$?
set -e
assert_status 1
assert_contains "/replace-fail/CoverageFixture.profdata'; the merged profile is '"
[ "$(covered_count "$work/replace-fail/CoverageFixture.profdata")" = 2 ] \
  || fail "expected the previous profile to be left whole when the replacement fails"
[ -n "$(find "$work/replace-fail" -path '*/profraw-*/merged.profdata')" ] \
  || fail "expected the new merged profile to be kept when the replacement fails"

# Without a working llvm-profdata the run fails, and keeps its raw
# profiles: a tool that isn't there, and (where a script can be run as
# one) a tool that fails.
set +e
output=$(coverage_env XCTEST_LLVM_PROFDATA="$work/no-such-llvm-profdata" "$xctest_bin" \
  "$source_root/Tests/CoverageFixture/CoverageFixture.bundle" -coverage-output "$work/missing-tool" 2>&1)
status=$?
set -e
assert_status 1
assert_contains "merge' failed; the raw profiles are in '"
[ -n "$(raw_profiles "$work/missing-tool")" ] || fail "expected the raw profiles to be kept when llvm-profdata is missing"
[ ! -e "$work/missing-tool/CoverageFixture.profdata" ] || fail "expected no profile without llvm-profdata"

if ! is_windows; then
  printf '#!/bin/sh\necho "stand-in llvm-profdata failed" >&2\nexit 3\n' > "$work/failing-llvm-profdata"
  chmod +x "$work/failing-llvm-profdata"
  set +e
  output=$(coverage_env XCTEST_LLVM_PROFDATA="$work/failing-llvm-profdata" "$xctest_bin" \
    "$source_root/Tests/CoverageFixture/CoverageFixture.bundle" -coverage-output "$work/failing-tool" 2>&1)
  status=$?
  set -e
  assert_status 1
  assert_contains "stand-in llvm-profdata failed"
  assert_contains "merge' failed; the raw profiles are in '"
  [ -n "$(raw_profiles "$work/failing-tool")" ] || fail "expected the raw profiles to be kept when the merge fails"
fi

# Parallel workers each write a profile; together they count the same.
run_fixture CoverageFixture -enable-code-coverage YES -coverage-output "$work/parallel" -parallel-testing-worker-count 2
assert_status 0
[ "$(covered_count "$work/parallel/CoverageFixture.profdata")" = 2 ] \
  || fail "expected the workers' profiles to be merged"

# A failing run still writes coverage, and still fails.
set +e
output=$(COVERAGE_FIXTURE_FAIL=1 LD_LIBRARY_PATH="$xctest_lib_dir${runtime_lib_dirs:+:$runtime_lib_dirs}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  "$xctest_bin" "$source_root/Tests/CoverageFixture/CoverageFixture.bundle" -coverage-output "$work/failing" 2>&1)
status=$?
set -e
assert_status 1
[ -f "$work/failing/CoverageFixture.profdata" ] || fail "expected coverage from a failing run"

# The default directory is ./coverage.
(cd "$work" && run_fixture CoverageFixture -enable-code-coverage YES)
[ -f "$work/coverage/CoverageFixture.profdata" ] || fail "expected coverage in ./coverage by default"

# Off, or only listing: nothing is written.
run_fixture CoverageFixture -enable-code-coverage NO -coverage-output "$work/off"
assert_status 0
[ ! -e "$work/off" ] || fail "expected no coverage with -enable-code-coverage NO"
run_fixture CoverageFixture -list-tests -coverage-output "$work/list"
assert_status 0
[ ! -e "$work/list" ] || fail "expected no coverage when listing tests"

# A host application writes its own profile (Linux; it needs a display).
if ! is_windows && { [ -n "${DISPLAY:-}" ] || command -v xvfb-run > /dev/null 2>&1; }; then
  display_wrapper=()
  [ -n "${DISPLAY:-}" ] || display_wrapper=(xvfb-run -a)
  make -C "$source_root/Tests/HostApp" clean all > /dev/null
  make -C "$source_root/Tests/HostedFixture" clean all \
    XCTEST_SOURCE_ROOT="$source_root" XCTEST_LIBRARY_DIR="$xctest_lib_dir" \
    ADDITIONAL_OBJCFLAGS="-fprofile-instr-generate -fcoverage-mapping" \
    ADDITIONAL_LDFLAGS=-fprofile-instr-generate > /dev/null
  set +e
  output=$(LD_LIBRARY_PATH="$xctest_lib_dir${runtime_lib_dirs:+:$runtime_lib_dirs}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    "${display_wrapper[@]}" "$xctest_bin" -host "$source_root/Tests/HostApp/HostApp.app" \
    "$source_root/Tests/HostedFixture/HostedFixture.bundle" -only-testing:HostedFixture/HostedTests \
    -coverage-output "$work/hosted" 2>&1)
  status=$?
  set -e
  make -C "$source_root/Tests/HostedFixture" clean > /dev/null
  assert_status 0
  assert_contains "hostapp: launched"
  [ -f "$work/hosted/HostedFixture.profdata" ] || fail "expected coverage from the host application"
else
  echo "Skipping the hosted coverage check: no display."
fi

# Nothing instrumented: an error, not an empty profile.
run_fixture FilterFixture -coverage-output "$work/none"
assert_status 1
assert_contains "no code coverage was recorded"

run_fixture CoverageFixture -enable-code-coverage maybe
assert_status 1
assert_contains "-enable-code-coverage must be YES or NO"

echo "Code coverage regressions passed."
