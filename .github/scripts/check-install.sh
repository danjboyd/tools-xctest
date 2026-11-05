#!/usr/bin/env bash
# check-install.sh make|meson [swift]
#
# Installs tools-xctest into a scratch DESTDIR, with gnustep-make or Meson,
# and checks the files against Tests/Install/manifest.txt. With "swift", the
# Swift overlay is built by a stand-in swiftc that only writes its outputs,
# so this checks what is installed, not the overlay itself. The build is
# done in a copy of the source tree, which is left untouched.
#
# For gnustep-make, it then checks `make uninstall` removes every file.
# Run with GNUstep's environment set (GNUstep.sh sourced).

set -euo pipefail

mode=${1:?usage: $0 make|meson [swift]}
swift=${2:-}
case "$mode" in make|meson) ;; *) echo "usage: $0 make|meson [swift]" >&2; exit 2 ;; esac
case "$swift" in ""|swift) ;; *) echo "usage: $0 make|meson [swift]" >&2; exit 2 ;; esac

source_root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
destdir=$work/destdir

fail() {
  echo "FAIL ($mode${swift:+, swift}): $1" >&2
  shift
  [ "$#" -eq 0 ] || printf '%s\n' "$@" >&2
  exit 1
}

# Every header in the source is either installed or listed as private.
manifest=$source_root/Tests/Install/manifest.txt
private=$source_root/Tests/Install/private-headers.txt
unlisted=$(for h in "$source_root"/XCTest/*.h; do
  name=$(basename "$h")
  grep -qx "header XCTest/$name.*" "$manifest" || grep -qx "$name" "$private" || echo "$name"
done)
[ -z "$unlisted" ] || fail "headers neither in manifest.txt nor in private-headers.txt:" "$unlisted"

# A stand-in swiftc: writes the files a real one would (-o, -emit-module-path
# and the .swiftdoc beside it).
swiftc_args=()
if [ -n "$swift" ]; then
  cat > "$work/swiftc" <<'STUB'
#!/bin/sh
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) shift; : > "$1" ;;
    -emit-module-path) shift; : > "$1"; : > "${1%.swiftmodule}.swiftdoc" ;;
  esac
  shift
done
STUB
  chmod +x "$work/swiftc"
fi

cp -a "$source_root" "$work/src"
cd "$work/src"
case "$mode" in
  make)
    make clean > /dev/null 2>&1 || true
    make ${swift:+XCTEST_SWIFTC="$work/swiftc"} > "$work/build.log" 2>&1 \
      || { tail -n 30 "$work/build.log" >&2; fail "make failed"; }
    make install DESTDIR="$destdir" ${swift:+XCTEST_SWIFTC="$work/swiftc"} > "$work/install.log" 2>&1 \
      || { tail -n 30 "$work/install.log" >&2; fail "make install failed"; }
    ;;
  meson)
    rm -rf build-install
    meson setup build-install ${swift:+-Dswift=enabled -Dswiftc="$work/swiftc"} > "$work/build.log" 2>&1 \
      && meson compile -C build-install >> "$work/build.log" 2>&1 \
      || { tail -n 30 "$work/build.log" >&2; fail "meson build failed"; }
    meson install -C build-install --destdir "$destdir" > "$work/install.log" 2>&1 \
      || { tail -n 30 "$work/install.log" >&2; fail "meson install failed"; }
    ;;
esac

# Nothing under DESTDIR twice (a rule adding $(DESTDIR) to a GNUstep
# variable that already has it).
doubled=$(cd "$destdir" && find . -path "./${destdir#/}" -prune -print)
[ -z "$doubled" ] || fail "installed under DESTDIR twice:" "$(cd "$destdir" && find "./${destdir#/}" -type f)"

# What was installed, by role (see manifest.txt).
classify() {
  local path=$1 name dir
  name=$(basename "$path")
  dir=$(dirname "$path")
  case "$path" in
    */Makefiles/*) echo "makefile ${path#*/Makefiles/}"; return ;;
  esac
  case "$name" in
    *.pc) echo "pkgconfig $name" ;;
    *.swiftmodule|*.swiftdoc) echo "swiftmodule $name" ;;
    *.h|module.modulemap) echo "header $(basename "$dir")/$name" ;;
    lib*.so|lib*.so.*|lib*.dylib|lib*.a|lib*.dll.a) echo "lib ${name%%.*}" ;;
    *.dll)
      # gnustep-make names it XCTest-0.dll (with libXCTest.dll.a to link).
      name=${name%.dll}
      name=${name%-[0-9]*}
      echo "lib lib${name#lib}" ;;
    *) echo "tool ${name%.exe}" ;;
  esac
}

actual=$(cd "$destdir" && find . \( -type f -o -type l \) | while read -r f; do classify "$f"; done | sort -u)

windows=
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) windows=1 ;; esac
expected=$(grep -v '^#' "$manifest" | while read -r role name tags; do
  [ -n "$role" ] || continue
  case " $tags " in *" swift "*) [ -n "$swift" ] || continue ;; esac
  case " $tags " in *" meson "*) [ "$mode" = meson ] || continue ;; esac
  case " $tags " in *" host "*) [ -z "$windows" ] || continue ;; esac
  echo "$role $name"
done | sort -u)

missing=$(comm -23 <(echo "$expected") <(echo "$actual"))
extra=$(comm -13 <(echo "$expected") <(echo "$actual"))
[ -z "$missing" ] || fail "not installed:" "$missing"
[ -z "$extra" ] || fail "installed but not in manifest.txt:" "$extra" "" "All files:" "$(cd "$destdir" && find . -type f -o -type l | sort)"

# The Swift module goes beside the XCTest header directory, where
# `-I <headers>` finds both; libXCTestSwift beside libXCTest.
if [ -n "$swift" ]; then
  module=$(cd "$destdir" && find . -name XCTest.swiftmodule)
  [ -d "$destdir/$(dirname "$module")/XCTest" ] \
    || fail "XCTest.swiftmodule isn't beside the XCTest headers: $module"
  overlay=$(cd "$destdir" && find . -name 'libXCTestSwift*' | head -n 1)
  ls "$destdir/$(dirname "$overlay")"/libXCTest.* > /dev/null 2>&1 \
    || fail "libXCTestSwift isn't beside libXCTest: $overlay"
fi

if [ "$mode" = make ]; then
  make uninstall DESTDIR="$destdir" ${swift:+XCTEST_SWIFTC="$work/swiftc"} > "$work/uninstall.log" 2>&1 \
    || { tail -n 30 "$work/uninstall.log" >&2; fail "make uninstall failed"; }
  left=$(cd "$destdir" && find . \( -type f -o -type l \) | sort)
  [ -z "$left" ] || fail "left after make uninstall:" "$left"
fi

echo "Install check passed ($mode${swift:+, swift}): $(echo "$actual" | wc -l) files by role."
