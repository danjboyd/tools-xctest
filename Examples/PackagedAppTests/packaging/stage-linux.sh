#!/usr/bin/env bash
# gnustep-packager's stage step on Linux: Greeter.app and the GNUstep runtime
# it needs, from the toolchain. Not the tests, and not tools-xctest: the app
# doesn't link XCTest.
#
#   packaging/stage-linux.sh [stage-root]   (default dist/stage)
set -euo pipefail

stage=${1:-dist/stage}
runtime=$stage/runtime

rm -rf "$stage"
mkdir -p "$stage/app" "$runtime/lib" "$runtime/bin" "$runtime/System/Tools" \
  "$stage/metadata/icons" "$stage/metadata/licenses"

cp -a Greeter.app "$stage/app/"

# The system domain's bundles, fonts and resources. gnustep-cli-new keeps
# gnustep-base, -gui and -back in the local domain, so add that too when
# GNUstep itself is there.
system_library=$(gnustep-config --variable=GNUSTEP_SYSTEM_LIBRARY)
local_library=$(gnustep-config --variable=GNUSTEP_LOCAL_LIBRARY)
cp -a "$system_library" "$runtime/System/Library"
if [ "$local_library" != "$system_library" ] &&
   ls "$local_library"/Libraries/libgnustep-base.so* >/dev/null 2>&1; then
  cp -a "$local_library/." "$runtime/System/Library/"
fi
rm -rf "$runtime/System/Library/Makefiles" "$runtime/System/Library/Themes" \
  "$runtime/System/Library/Headers"

# gdnc and make_services start with the app; gpbs with the first pasteboard
# use. The packager runs the staged defaults tool for packaged defaults.
system_tools=$(gnustep-config --variable=GNUSTEP_SYSTEM_TOOLS)
tool_path() {
  if [ -x "$system_tools/$1" ]; then
    printf '%s\n' "$system_tools/$1"
  else
    command -v "$1"
  fi
}
for tool in gdnc gpbs make_services; do
  cp -L "$(tool_path "$tool")" "$runtime/System/Tools/$tool"
done
cp -L "$(tool_path defaults)" "$runtime/bin/defaults"

# Every shared library those need, except the C runtime's.
find "$stage/app" "$runtime/System/Library/Bundles" "$runtime/System/Tools" \
     "$runtime/bin" -type f -exec sh -c \
     'file -b "$1" | grep -q "^ELF" && printf "%s\n" "$1"' _ {} \; |
  while IFS= read -r elf; do
    ldd "$elf" 2>/dev/null | awk '$2 == "=>" && $3 ~ /^\// { print $3 }'
  done | sort -u | while IFS= read -r library; do
    case "$(basename "$library")" in
      libc.so.*|libdl.so.*|libm.so.*|libpthread.so.*|librt.so.*|ld-linux-*) continue ;;
    esac
    cp -L "$library" "$runtime/lib/"
  done

cp packaging/Greeter.png "$stage/metadata/icons/Greeter.png"
cat > "$stage/metadata/licenses/gnustep-runtime.txt" <<'TXT'
This package includes the GNUstep Base and GUI libraries, under the GNU Lesser
General Public License, version 2.1 or later:
https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html
TXT
