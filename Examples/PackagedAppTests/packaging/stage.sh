#!/usr/bin/env bash
# gnustep-packager's stage step on Windows: Greeter.app and the GNUstep
# runtime it needs, from the gnustep-cli-new toolchain's CLANG64 tree. Not
# the tests, and not tools-xctest: the app doesn't link XCTest.
#
#   packaging/stage.sh [stage-root]   (default dist/stage)
set -euo pipefail

stage=${1:-dist/stage}
clang64=/clang64
runtime=$stage/runtime

rm -rf "$stage"
mkdir -p "$stage/app" "$runtime/bin" "$runtime/System/Library" \
  "$runtime/System/Tools" "$stage/metadata/licenses" "$stage/metadata/icons"

cp -R Greeter.app "$stage/app/"

# The bundles GNUstep loads at run time and gnustep-gui's shared resources.
for name in Bundles Images KeyBindings Fonts ColorPickers PostScript DTDs \
            Services Sounds; do
  if [ -d "$clang64/lib/GNUstep/$name" ]; then
    cp -R "$clang64/lib/GNUstep/$name" "$runtime/System/Library/"
  fi
done
if [ -d "$clang64/etc/fonts" ]; then
  mkdir -p "$runtime/etc"
  cp -R "$clang64/etc/fonts" "$runtime/etc/"
fi

# gdnc and make_services start with the app; gpbs with the first pasteboard
# use. The packager runs the staged defaults tool for packaged defaults.
for tool in gdnc.exe gpbs.exe make_services.exe; do
  cp "$clang64/bin/$tool" "$runtime/System/Tools/"
done
cp "$clang64/bin/defaults.exe" "$runtime/bin/"

# The DLLs everything staged so far imports, and the DLLs those import. A
# name that isn't in CLANG64 is taken as Windows' own; gnustep-packager's
# runtime closure check fails the package on anything missed.
queue=()
while IFS= read -r -d '' file; do
  queue+=("$file")
done < <(find "$stage" -type f \( -iname '*.exe' -o -iname '*.dll' \) -print0)
declare -A seen=()
i=0
while [ "$i" -lt "${#queue[@]}" ]; do
  file=${queue[$i]}
  i=$((i + 1))
  [ -n "${seen[$file]:-}" ] && continue
  seen[$file]=1
  while IFS= read -r dll; do
    dll=${dll%$'\r'}
    if [ -f "$clang64/bin/$dll" ] && [ ! -f "$runtime/bin/$dll" ]; then
      cp "$clang64/bin/$dll" "$runtime/bin/"
      queue+=("$runtime/bin/$dll")
    fi
  done < <(llvm-objdump -p "$file" | sed -n 's/^ *DLL Name: *//p')
done

# Point every GNUstep domain into the package.
cat > "$runtime/bin/GNUstep.conf" <<'CONF'
GNUSTEP_USER_CONFIG_FILE=
GNUSTEP_SYSTEM_ROOT=../System
GNUSTEP_LOCAL_ROOT=../System
GNUSTEP_NETWORK_ROOT=../System
GNUSTEP_SYSTEM_LIBRARY=../System/Library
GNUSTEP_SYSTEM_TOOLS=../System/Tools
GNUSTEP_NETWORK_LIBRARY=../System/Library
GNUSTEP_NETWORK_TOOLS=../System/Tools
GNUSTEP_LOCAL_LIBRARY=../lib/GNUstep
GNUSTEP_LOCAL_TOOLS=../System/Tools
CONF

cat > "$stage/metadata/licenses/gnustep-runtime.txt" <<'TXT'
This package includes the GNUstep Base and GUI libraries, under the GNU Lesser
General Public License, version 2.1 or later:
https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html
TXT
