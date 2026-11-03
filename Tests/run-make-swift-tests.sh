#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

# Swift test bundles through xctest.make.
#
# With the gnustep-make under test (no Swift support), a bundle with
# <Bundle>_SWIFT_FILES must fail clearly. With gnustep-swift's tools-make
# (XCTEST_SWIFT_MAKEFILES: the Makefiles directory of an install of
# danjboyd/tools-make's gnustep-swift branch), the bundle is built with a
# stand-in Swift toolchain, linked with swiftrt.o and its objects' autolink
# libraries, and run.

fixture="$source_root/Tests/SwiftMakeFixture"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"; rm -rf "$fixture/obj" "$fixture/SwiftMakeTests.xctest"' EXIT
export LD_LIBRARY_PATH="$xctest_lib_dir${runtime_lib_dirs:+:$runtime_lib_dirs}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# make_fixture <GNUSTEP_MAKEFILES> [make args...] sets $output and $status.
make_fixture() {
  local makefiles=$1
  shift
  set +e
  output=$(make -C "$fixture" GNUSTEP_MAKEFILES="$makefiles" messages=yes \
    XCTEST_MAKE="$source_root/xctest.make" \
    XCTEST_LIBRARY_DIR="$xctest_lib_dir" XCTEST_INCLUDE_DIR="$source_root" \
    XCTEST="$xctest_bin" "$@" 2>&1)
  status=$?
  set -e
}

echo "Running xctest.make Swift regressions..."

# A gnustep-make without Swift support: a clear error, not a bundle without
# its Swift sources.
make_fixture "$GNUSTEP_MAKEFILES" all
[ "$status" -ne 0 ] || fail "expected a Swift test bundle to fail without Swift support"
assert_contains "xctest.make: SwiftMakeTests has Swift sources, but this gnustep-make"
assert_contains "can't build Swift"

if [ -z "${XCTEST_SWIFT_MAKEFILES:-}" ]; then
  echo "Skipping the build with gnustep-swift's tools-make: set XCTEST_SWIFT_MAKEFILES."
  echo "xctest.make Swift regressions passed."
  exit 0
fi

# A stand-in Swift toolchain. swift-frontend compiles each .swift file as
# Objective-C (the fixture's are), passing on the -Xcc flags gnustep-make
# gives it; swift-autolink-extract asks for -lm; swiftrt.o defines a marker.
tools="$work_dir/toolchain"
mkdir -p "$tools/bin" "$tools/resource/linux/$(uname -m)" "$tools/empty"
cat > "$tools/bin/swift-frontend" <<'EOF'
#!/bin/sh
# Records its arguments, then compiles the primary file as Objective-C.
printf '%s\n' "$*" >> "$(dirname "$0")/frontend.log"
primary=; out=; xcc=
while [ $# -gt 0 ]; do
  case "$1" in
    -primary-file) primary=$2; shift ;;
    -o) out=$2; shift ;;
    -Xcc) xcc="$xcc $2"; shift ;;
  esac
  shift
done
# shellcheck disable=SC2086
exec clang -x objective-c $xcc $(gnustep-config --objc-flags | sed 's/-MMD//;s/-MP//') -fPIC -c "$primary" -o "$out"
EOF
cat > "$tools/bin/swift-autolink-extract" <<'EOF'
#!/bin/sh
# swift-autolink-extract <object> -o <file>
printf -- '-lm\n' > "$3"
EOF
cp "$tools/bin/swift-frontend" "$tools/bin/swiftc"
chmod +x "$tools/bin/"*
printf 'int xctest_stand_in_swiftrt_marker = 1;\n' > "$tools/swiftrt.c"
clang -fPIC -c "$tools/swiftrt.c" -o "$tools/resource/linux/$(uname -m)/swiftrt.o"
: > "$tools/empty.modulemap"

swift_make() {
  GNUSTEP_SWIFT_SWIFT_FRONTEND="$tools/bin/swift-frontend" \
  GNUSTEP_SWIFT_REAL_SWIFTC="$tools/bin/swiftc" \
  GNUSTEP_SWIFT_RESOURCE_DIR="$tools/resource" \
  GNUSTEP_SWIFT_GNUSTEP_HEADERS="$tools/empty" \
  GNUSTEP_SWIFT_GNUSTEP_MODULEMAP="$tools/empty.modulemap" \
  GNUSTEP_SWIFT_LIBOBJC2_SRC="$tools/empty" \
  GNUSTEP_SWIFT_LIBOBJC2_CONFIG_INCLUDE="$tools/empty" \
  GNUSTEP_SWIFT_LIBOBJC2_LIBDIR="$tools/empty" \
    make_fixture "$XCTEST_SWIFT_MAKEFILES" \
    ADDITIONAL_LIB_DIRS="$(printf -- '-L%s ' ${runtime_lib_dirs//:/ })" "$@"
}

swift_make clean all
assert_status 0
binary=$(bundle_binary "$fixture/SwiftMakeTests.xctest" SwiftMakeTests)
[ -f "$binary" ] || fail "expected SwiftMakeTests.xctest to be built"

# Each Swift file was compiled with the uninstalled XCTest's headers and its
# module map named explicitly.
log=$(cat "$tools/bin/frontend.log")
[ "$(printf '%s\n' "$log" | grep -c -- '-primary-file')" -eq 2 ] \
  || fail "expected the two Swift files to be compiled" "$log"
[[ "$log" == *"-Xcc -I$source_root "* ]] || { output=$log; fail "expected XCTEST_INCLUDE_DIR on the Swift include path"; }
[[ "$log" == *"-Xcc -fmodule-map-file=$source_root/XCTest/module.modulemap"* ]] \
  || { output=$log; fail "expected the XCTest module map to be named explicitly"; }
[[ "$log" == *"-I $xctest_lib_dir "* ]] || { output=$log; fail "expected XCTEST_LIBRARY_DIR (the Swift overlay) on the Swift include path"; }

# The bundle is linked with swiftrt.o and with each object's autolink file.
link=$(printf '%s\n' "$output" | grep -- "-o .*SwiftMakeTests.xctest" | tail -n 1)
[[ "$link" == *"swiftrt.o"* ]] || { output=$link; fail "expected swiftrt.o on the link line"; }
for file in FirstTests SecondTests; do
  [[ "$link" == *"@"*"/$file.swift.autolink"* ]] || { output=$link; fail "expected $file.swift.autolink on the link line"; }
done
nm "$binary" | grep -q xctest_stand_in_swiftrt_marker || fail "expected swiftrt.o in the bundle"
# Against the uninstalled library, ahead of any installed one.
[[ "$link" == *"-L$xctest_lib_dir "*"-L"*"/Library/Libraries"* ]] \
  || { output=$link; fail "expected XCTEST_LIBRARY_DIR ahead of the installed libraries"; }

# A changed autolink file relinks the bundle.
touch "$fixture/obj/SwiftMakeTests.obj/FirstTests.swift.autolink"
swift_make all
assert_status 0
assert_contains "-o ./SwiftMakeTests.xctest/./SwiftMakeTests"

# It loads into xctest and its tests run.
swift_make check
assert_status 0
assert_contains "swift-make: FirstTests.testFirst ran"
assert_contains "swift-make: SecondTests.testSecond ran"

echo "xctest.make Swift regressions passed."
