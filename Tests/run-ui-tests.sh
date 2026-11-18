#!/usr/bin/env bash
#
# UI testing for hosted tests (XCTest/XCUI.h, libXCTestUI): queries,
# attributes, clicking, typing, menus and waiting, from the main thread and
# from the UI test thread, against Tests/UIHostApp. The design is in
# Docs/ui-testing-design.md (issue #26).

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

if [ ! -e "$xctest_lib_dir/libXCTestUI.so" ]; then
  echo "Skipping UI tests: libXCTestUI wasn't built (no gnustep-gui)."
  exit 0
fi

# A private Xvfb when available, so no windows appear on the desktop. Its
# X authority file is ours, so xvfb-run makes no directory of its own (see
# run-ui-thread-tests.sh).
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
if command -v xvfb-run >/dev/null 2>&1; then
  : > "$work/Xauthority"
  display_wrapper=(xvfb-run -a -f "$work/Xauthority")
elif [ -n "${DISPLAY:-}" ]; then
  display_wrapper=()
else
  echo "Skipping UI tests: no X display and no xvfb-run."
  exit 0
fi

echo "Building UIHostApp..."
make -C "$source_root/Tests/UIHostApp" clean all
build_fixture UIFixture

host_app="$source_root/Tests/UIHostApp/UIHostApp.app"

# A scratch home and defaults, so the app doesn't read or write the user's.
mkdir -p "$work/home" "$work/tmp"

run_ui() {
  set +e
  output=$(env HOME="$work/home" TMPDIR="$work/tmp" \
    LD_LIBRARY_PATH="$xctest_lib_dir${runtime_lib_dirs:+:$runtime_lib_dirs}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    timeout -k 5 120 "${display_wrapper[@]}" "$xctest_bin" -host "$host_app" \
    "$source_root/Tests/UIFixture/UIFixture.bundle" "$@" 2>&1)
  status=$?
  set -e
}

echo "Running UI test regressions..."

# Queries, attributes and actions from the main thread, and an alert
# driven from the UI test thread.
run_ui -skip-testing:UIFixture/UIFailureTests -attachments-path "$work/attachments"
assert_status 0
assert_contains "uihostapp: launched"
assert_contains "UIElementTests: 6 tests PASSED"
assert_contains "UIActionTests: 5 tests PASSED"
assert_contains "UIAlertTests: 3 tests PASSED"
assert_contains "UIScreenshotTests: 4 tests PASSED"
assert_contains "UISheetTests: 2 tests PASSED"
# A screenshot attachment is saved as PNG.
[ "$(head -c 8 "$work/attachments/UIScreenshotTests/testAnElementsScreenshotIsItsSize/increment.png" | od -An -tx1 | tr -d ' \n')" = "89504e470d0a1a0a" ] \
  || fail "expected the screenshot attachment to be saved as PNG"

# Actions a user couldn't perform, and queries that don't find exactly one
# element, fail the test with a message saying why.
run_ui -only-testing:UIFixture/UIFailureTests
assert_status 1
assert_contains "UIFailureTests: 6/6 tests FAILED"
assert_contains "couldn't click buttons \"Disabled\": it isn't hittable (it's disabled)"
assert_contains "couldn't click buttons \"Hidden\": it isn't hittable (it's hidden, off screen or outside its window)"
assert_contains "no matches found for buttons \"Nope\""
assert_contains "couldn't click menu items \"Unavailable\": it isn't hittable (it's disabled)"
assert_not_contains "the disabled menu item's action ran"
assert_contains "couldn't take a screenshot of menu items \"Reset\": it isn't drawn in a window"
assert_contains "couldn't click buttons \"Twin\": 2 matches found for buttons \"Twin\": button \"Twin\", button \"Twin\""

make -C "$source_root/Tests/UIHostApp" clean > /dev/null
make -C "$source_root/Tests/UIFixture" clean > /dev/null
echo "UI test regressions passed."
