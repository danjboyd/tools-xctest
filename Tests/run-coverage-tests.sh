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
  profdata=$(IFS=:; for d in $PATH; do ls "$d"/llvm-profdata-[0-9]* 2>/dev/null; done \
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

# The number of times the profile says CoverageFixtureCovered ran.
covered_count() {
  "$profdata" show --all-functions --counts "$1" \
    | awk '/^  CoverageFixtureCovered:/ { found = 1 } found && /Function count:/ { print $3; exit }'
}

echo "Running code coverage regressions..."

run_fixture CoverageFixture -coverage-output "$work/single"
assert_status 0
assert_contains "code coverage written to '$work/single/CoverageFixture.profdata'"
[ -f "$work/single/CoverageFixture.profdata" ] || fail "expected the merged profile"
[ ! -e "$work/single/profraw" ] || fail "expected the raw profiles to be removed after merging"
[ "$(covered_count "$work/single/CoverageFixture.profdata")" = 2 ] \
  || fail "expected CoverageFixtureCovered to be counted twice: $("$profdata" show --all-functions --counts "$work/single/CoverageFixture.profdata")"

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
