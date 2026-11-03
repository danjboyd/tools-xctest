#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

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

echo "Running Swift overlay checks with $swiftc..."

# Bridge.swift without its import of the real (Clang) XCTest module, whose
# declarations Stub.swift provides.
grep -v '^@_exported import XCTest$' "$source_root/XCTest/Swift/Bridge.swift" > "$work_dir/Bridge.swift"
cmp -s "$source_root/XCTest/Swift/Bridge.swift" "$work_dir/Bridge.swift" \
  && fail "expected Bridge.swift to import the XCTest Clang module"

set +e
output=$("$swiftc" -swift-version 5 -warnings-as-errors -module-name XCTest \
  "$source_root/Tests/SwiftOverlay/Stub.swift" "$work_dir/Bridge.swift" \
  "$source_root/XCTest/Swift/Assertions.swift" "$source_root/XCTest/Swift/Errors.swift" \
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

echo "Swift overlay checks passed."
