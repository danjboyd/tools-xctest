#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

# Without @nonobjc, these replace the Objective-C methods they call, on the
# interop toolchain; see Expectations.swift. A stock swiftc can't show that.
output=$(awk '/^[[:space:]]+public (class )?func / && !nonobjc { print FILENAME ":" FNR ": " $0 }
              { if ($0 ~ /@nonobjc/) nonobjc = 1; else if ($0 !~ /^[[:space:]]+@/) nonobjc = 0 }' \
  "$source_root/XCTest/Swift/Expectations.swift" "$source_root/XCTest/Swift/Helpers.swift")
[ -z "$output" ] || fail "expected @nonobjc on:"

# Builds the Swift overlay (XCTest/Swift) with a stock Swift toolchain and a
# stub of the Objective-C side, and checks what each assertion records. A
# GNUstep-interop toolchain isn't needed. Skipped when there's no swiftc
# (set SWIFTC to choose one).
swiftc=${SWIFTC:-$(command -v swiftc || true)}
if [ -z "$swiftc" ]; then
  echo "Skipping Swift overlay checks: no swiftc (set SWIFTC)."
  exit 0
fi

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

echo "Running Swift overlay checks with $swiftc ($("$swiftc" --version 2>&1 | head -n 1))..."

# Bridge.swift without its import of the real (Clang) XCTest module, whose
# declarations Stub.swift provides.
grep -v '^@_exported import XCTest$' "$source_root/XCTest/Swift/Bridge.swift" > "$work_dir/Bridge.swift"
cmp -s "$source_root/XCTest/Swift/Bridge.swift" "$work_dir/Bridge.swift" \
  && fail "expected Bridge.swift to import the XCTest Clang module"

set +e
output=$("$swiftc" -swift-version 5 -warnings-as-errors -module-name XCTest \
  "$source_root/Tests/SwiftOverlay/Stub.swift" "$work_dir/Bridge.swift" \
  "$source_root/XCTest/Swift/Assertions.swift" "$source_root/XCTest/Swift/Errors.swift" \
  "$source_root/XCTest/Swift/Expectations.swift" \
  "$source_root/XCTest/Swift/Helpers.swift" \
  "$source_root/Tests/SwiftOverlay/main.swift" -o "$work_dir/overlay-check" 2>&1)
status=$?
set -e
assert_status 0

set +e
output=$("$work_dir/overlay-check" 2>&1)
status=$?
set -e
printf '%s\n' "$output" | grep -v '^PASS' || true
assert_status 0
assert_contains "All overlay checks passed."

# The stub above is written by hand, so check what these actually import as, from
# the real headers. Stock Swift's bridged types differ from the interop
# toolchain's, so this only looks at names and non-optional results.
if objc_flags=$(gnustep-config --objc-flags 2>/dev/null); then
  clang_args=(-Xcc "-I$source_root")
  for flag in $objc_flags; do
    case "$flag" in -D*|-I*|-fobjc*|-fblocks|-fconstant*) clang_args+=(-Xcc "$flag") ;; esac
  done
  set +e
  output=$("$swiftc" -frontend -typecheck -enable-objc-interop -disable-objc-attr-requires-foundation-module \
    -module-name XCTest -import-underlying-module -module-cache-path "$work_dir/modules" \
    -I "$source_root" "${clang_args[@]}" -Xcc -fmodules \
    -Xcc "-fmodule-map-file=$source_root/XCTest/module.modulemap" \
    "$source_root/Tests/SwiftOverlay/ImportedNames.swift" 2>&1)
  status=$?
  set -e
  # A crash is the compiler's own, on GNUstep's headers, and says nothing here.
  if [ "$status" -ge 128 ]; then
    echo "Skipping the check of imported names: $swiftc crashed on the headers."
  else
    assert_status 0
    echo "Imported names checked against the headers."
  fi
fi

echo "Swift overlay checks passed."
