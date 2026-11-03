#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

# Clang module imports need Clang; GCC has no -fmodules for Objective-C.
cc=${CC:-$(gnustep-config --variable=CC 2>/dev/null || echo clang)}
case "$("$cc" --version 2>&1)" in
  *clang*) ;;
  *)
    echo "Skipping module map regressions: $cc is not Clang."
    exit 0
    ;;
esac

output=
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

echo "Running module map regressions..."

# Stage the headers the way gnustep-make installs them: the header list, and
# nothing else, into <Headers>/XCTest/.
headers=$(printf 'include GNUmakefile\nxctest-print-headers:\n\t@echo $(XCTest_HEADER_FILES)\n' \
  | make -s --no-print-directory -C "$source_root/XCTest" -f - xctest-print-headers 2>/dev/null \
  | tail -n 1)
case " $headers " in
  *" module.modulemap "*) ;;
  *) fail "expected module.modulemap to be installed with the headers" ;;
esac
# Meson installs the same set (meson.build's `headers` list).
meson_headers=$(sed -n '/^headers = \[/,/^\]/p' "$source_root/meson.build" \
  | grep -o "'XCTest/[^']*'" | tr -d "'" | sed 's|^XCTest/||' | sort)
make_headers=$(printf '%s\n' $headers | sort)
[ "$meson_headers" = "$make_headers" ] \
  || fail "expected meson.build and XCTest/GNUmakefile to install the same headers:
$(diff <(printf '%s\n' "$make_headers") <(printf '%s\n' "$meson_headers") || true)"

mkdir -p "$work_dir/Headers/XCTest"
for header in $headers; do
  cp "$source_root/XCTest/$header" "$work_dir/Headers/XCTest/" \
    || fail "expected installed header $header to exist"
done

# A client that imports the module, and its runner submodule, and uses API
# from across the umbrella header, including a throwing test method.
cat > "$work_dir/client.m" <<'EOF'
@import XCTest;
@import XCTest.GSXCTestRunner;

@interface ModuleClientTests : XCTestCase
@end

@implementation ModuleClientTests
- (BOOL) testThrowsAndReturnError: (NSError **)error
{
  XCTestExpectation *e = [self expectationWithDescription: @"module"];
  [e fulfill];
  [self waitForExpectations: @[e] timeout: 1];
  XCTAssertEqual(1, 1);
  XCTAssertThrows([NSException raise: @"x" format: @"y"]);
  [XCTContext runActivityNamed: @"activity" block: ^(id<XCTActivity> a) {
    [a addAttachment: [XCTAttachment attachmentWithString: @"text"]];
  }];
  return YES;
}
@end

int main(void)
{
  return [GSXCTestRunner class] != Nil ? 0 : 1;
}
EOF

# The GNUstep flags, without their dependency-file options.
objc_flags=
for flag in $(gnustep-config --objc-flags 2>/dev/null || true); do
  case "$flag" in
    -MMD|-MD|-MP) ;;
    *) objc_flags="$objc_flags $flag" ;;
  esac
done

# Every XCTest header the umbrella pulls in must come from the staged copy,
# not from an older XCTest installed next to Foundation.
set +e
# shellcheck disable=SC2086
output=$(cd "$work_dir" && "$cc" -I"$work_dir/Headers" $objc_flags -x objective-c \
  -E -M -MF deps "$work_dir/Headers/XCTest/XCTest.h" 2>&1)
status=$?
set -e
assert_status 0
# Clang writes native paths: on Windows, /tmp/x is C:/msys64/tmp/x.
stray=$(tr ' \\' '\n\n' < "$work_dir/deps" | grep '/XCTest/' \
  | grep -v -e "^$work_dir/" -e "^$(native_path "$work_dir")/" || true)
[ -z "$stray" ] || fail "expected every XCTest header to be installed, but these came from elsewhere: $stray"

# Compile in the work directory: the GNUstep flags include -I., and the
# source tree's own XCTest/module.modulemap must not be found.
compile_client() {
  set +e
  # shellcheck disable=SC2086
  output=$(cd "$work_dir" && "$cc" "$@" $objc_flags -fmodules \
    -fmodules-cache-path="$work_dir/cache" -fsyntax-only client.m 2>&1)
  status=$?
  set -e
}

# The module is found from the Headers directory, as `-I<Headers>` gives it.
compile_client -I"$work_dir/Headers"
assert_status 0

# And from the XCTest directory itself, as XCTEST_HEADERS-style setups give it.
compile_client -I"$work_dir/Headers/XCTest"
assert_status 0

# Without the module map, the import fails: the check above used it.
rm "$work_dir/Headers/XCTest/module.modulemap"
rm -rf "$work_dir/cache"
compile_client -I"$work_dir/Headers"
[ "$status" -ne 0 ] || fail "expected @import XCTest to fail without the module map"

echo "Module map regressions passed."
