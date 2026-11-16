#!/usr/bin/env bash
# gnustep-packager's build step: build tools-xctest, build the app, and run
# the app's tests. A failing test fails this step, so no package is made.
#
# Run from the example's root (the manifest's workingDirectory), in the
# toolchain's shell: on Windows, gnustep-packager's msys2-bash shell, the
# CLANG64 shell of the gnustep-cli-new toolchain.
#
# tools-xctest isn't part of that toolchain yet, so it's built here from its
# release archive and used uninstalled, from build/. Nothing is installed:
# not into the toolchain, which later steps still use, and not into the
# stage, which only gets the app (packaging/stage.sh).
set -euo pipefail

XCTEST_VERSION=0.8.0
XCTEST_SHA256=7623055145e4fd7067db5f3b690b7a5ca561fcb56baf8772302ca71dd6d1f27d
XCTEST_URL=https://github.com/danjboyd/tools-xctest/releases/download/v$XCTEST_VERSION/tools-xctest-$XCTEST_VERSION.tar.gz

root=$(pwd)
work=$root/build
src=$work/tools-xctest-$XCTEST_VERSION

windows=no
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) windows=yes ;;
esac

# The toolchain's gnustep-make environment.
if [ -z "${GNUSTEP_MAKEFILES:-}" ]; then
  GNUSTEP_MAKEFILES=$(gnustep-config --variable=GNUSTEP_MAKEFILES)
fi
if [ "$windows" = yes ]; then
  GNUSTEP_MAKEFILES=$(cygpath -u "$GNUSTEP_MAKEFILES")
fi
set +u
. "$GNUSTEP_MAKEFILES/GNUstep.sh"
set -u

if [ "$windows" = yes ]; then
  # MSYS2's libdispatch headers define mode_t unless HAVE_MODE_T is set.
  export ADDITIONAL_CPPFLAGS="${ADDITIONAL_CPPFLAGS:-} -DHAVE_MODE_T"

  # gnustep-base 1.31.1's NSBackgroundActivityScheduler.h puts __block on an
  # instance variable, which clang 23 rejects (gnustep/libs-base#809). If the
  # toolchain has that header, compile against a fixed copy instead of
  # editing the toolchain.
  headers=$(cygpath -u "$(gnustep-config --variable=GNUSTEP_SYSTEM_HEADERS)")
  header=$headers/Foundation/NSBackgroundActivityScheduler.h
  if grep -q 'BLOCK_SCOPE GSScheduledBlock _block;' "$header" 2>/dev/null; then
    mkdir -p "$work/include/Foundation"
    sed 's/BLOCK_SCOPE GSScheduledBlock _block;/GSScheduledBlock _block;/' \
      "$header" > "$work/include/Foundation/NSBackgroundActivityScheduler.h"
    export ADDITIONAL_INCLUDE_DIRS="-I$work/include ${ADDITIONAL_INCLUDE_DIRS:-}"
    echo "Using a fixed copy of $header (gnustep/libs-base#809)."
  fi
fi

echo "== tools-xctest $XCTEST_VERSION"
mkdir -p "$work"
archive=$work/tools-xctest-$XCTEST_VERSION.tar.gz
if [ ! -f "$archive" ]; then
  curl -fsSL --retry 3 -o "$archive.part" "$XCTEST_URL"
  mv "$archive.part" "$archive"
fi
echo "$XCTEST_SHA256  $archive" | sha256sum -c -
rm -rf "$src"
tar -xzf "$archive" -C "$work"
make -C "$src"

echo "== Greeter.app"
make -C "$root"

echo "== GreeterTests"
# The uninstalled tools-xctest: its xctest.make, headers, library and runner.
# Windows finds the XCTest DLL on PATH.
PATH=$src/XCTest/obj:$PATH make -C "$root/Tests" check \
  XCTEST_MAKE="$src/xctest.make" \
  XCTEST_INCLUDE_DIR="$src" \
  XCTEST_LIBRARY_DIR="$src/XCTest/obj" \
  XCTEST="$src/obj/xctest" \
  XCTEST_FLAGS="-junit-report $work/GreeterTests.junit.xml"
