#!/usr/bin/env bash
# Builds the clang/libobjc2 GNUstep stack that tools-xctest is tested
# against (the versions iep-apt packages) into $PREFIX, in the GNUstep
# filesystem layout. Used by .github/workflows/ci.yml; the workflow caches
# $PREFIX, keyed on this file.

set -euo pipefail

PREFIX=${PREFIX:?set PREFIX to the install directory}
SRC=${SRC:-${RUNNER_TEMP:-/tmp}/gnustep-src}
JOBS=$(nproc)

LIBOBJC2_TAG=v2.3
MAKE_TAG=make-2_9_3
BASE_TAG=base-1_31_1
GUI_TAG=gui-0_32_0
BACK_TAG=back-0_32_0

export CC=clang CXX=clang++
mkdir -p "$SRC"

clone() {
  git clone -q --depth 1 --branch "$2" "https://github.com/gnustep/$1.git" "$SRC/$1"
}

echo "::group::libobjc2 $LIBOBJC2_TAG"
clone libobjc2 "$LIBOBJC2_TAG"
git -C "$SRC/libobjc2" submodule update -q --init --depth 1
cmake -S "$SRC/libobjc2" -B "$SRC/libobjc2/build" -G Ninja \
  -DTESTS=OFF -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DGNUSTEP_INSTALL_TYPE=NONE -DCMAKE_INSTALL_PREFIX="$PREFIX"
cmake --build "$SRC/libobjc2/build"
cmake --install "$SRC/libobjc2/build"
echo "::endgroup::"

export CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib -fuse-ld=lld"
export LD_LIBRARY_PATH="$PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

echo "::group::gnustep-make $MAKE_TAG"
clone tools-make "$MAKE_TAG"
(cd "$SRC/tools-make" &&
  ./configure --prefix="$PREFIX" --with-layout=gnustep \
    --with-library-combo=ng-gnu-gnu --with-runtime-abi=gnustep-2.2 &&
  make install)
echo "::endgroup::"

# GNUstep.sh reads unset variables.
set +u
# shellcheck disable=SC1091
. "$PREFIX/System/Library/Makefiles/GNUstep.sh"
set -u

for lib in "libs-base $BASE_TAG" "libs-gui $GUI_TAG" "libs-back $BACK_TAG"; do
  set -- $lib
  echo "::group::$1 $2"
  clone "$1" "$2"
  (cd "$SRC/$1" && ./configure && make -j"$JOBS" && make install)
  echo "::endgroup::"
done
