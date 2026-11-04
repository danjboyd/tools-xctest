#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

# Swift support stays separate from the rest of tools-xctest: what Swift needs
# from the headers lives in XCTest/GSXCTestSwift.h (macros that are empty, or
# give the plain Objective-C form, unless Swift imports the headers) and
# XCTest/GSXCTestSwiftOverlay.h (methods only the Swift overlay calls). The
# other headers name no Swift-only attribute, and read as plain Objective-C
# to a compiler that isn't importing them for Swift.

echo "Running Swift separation regressions..."
output=

swift_only='swift_name|enum_extensibility|_Nullable|_Nonnull|NS_ASSUME_NONNULL|assume_nonnull|nullability|__swift__|_gsWaitInBackground|_gsAddAsyncTeardownBlock'

for header in "$source_root"/XCTest/*.h; do
  case "$(basename "$header")" in
    GSXCTestSwift.h|GSXCTestSwiftOverlay.h) continue ;;
  esac
  output=$(grep -nE "$swift_only" "$header" || true)
  [ -z "$output" ] || fail "expected no Swift-only declarations in $(basename "$header"):"
done

# What a compiler not importing for Swift sees, through the umbrella header.
cc=${CC:-$(gnustep-config --variable=CC 2>/dev/null || echo cc)}
objc_flags=$(gnustep-config --objc-flags 2>/dev/null || true)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
printf '#import <XCTest/XCTest.h>\n' > "$work_dir/umbrella.m"
# shellcheck disable=SC2086
"$cc" -E -P -I"$source_root" $objc_flags "$work_dir/umbrella.m" > "$work_dir/umbrella.i" 2>"$work_dir/cc.log" \
  || { output=$(cat "$work_dir/cc.log"); fail "expected the umbrella header to preprocess"; }
output=$(grep -nE 'swift_name|enum_extensibility|_gsWaitInBackground|_gsAddAsyncTeardownBlock' "$work_dir/umbrella.i" || true)
[ -z "$output" ] || fail "expected no Swift-only declarations when not importing for Swift:"

# The library is compiled without __swift__, and the overlay calls it with
# __swift__ defined: the enums must be the same size both ways.
case "$("$cc" --version 2>&1)" in
  *clang*)
    cat > "$work_dir/sizes.m" <<'SIZES'
#import <XCTest/XCTest.h>
_Static_assert(sizeof(XCTWaiterResult) == sizeof(unsigned int), "XCTWaiterResult");
_Static_assert(sizeof(XCTAttachmentLifetime) == sizeof(unsigned int), "XCTAttachmentLifetime");
SIZES
    for swift in "" "-D__swift__=50000"; do
      # shellcheck disable=SC2086
      output=$("$cc" -fsyntax-only $swift -I"$source_root" $objc_flags "$work_dir/sizes.m" 2>&1) \
        || fail "expected the enums' sizes not to depend on Swift (${swift:-without __swift__}):"
    done
    ;;
esac

echo "Swift separation tests passed."
