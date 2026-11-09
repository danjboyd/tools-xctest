#!/usr/bin/env bash
#
# The xctest(1) man page describes exactly the options `xctest -h` lists.

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

page=$source_root/xctest.1

echo "Running man page regressions..."
set +e
output=$(LD_LIBRARY_PATH="$xctest_lib_dir${runtime_lib_dirs:+:$runtime_lib_dirs}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  "$xctest_bin" -h 2>&1)
status=$?
set -e
assert_status 0

# Options in the help: the first word of each line indented by two spaces,
# with "-h, --help" as two, and "-only-testing:<identifier>" as "-only-testing:".
help_options=$(printf '%s\n' "$output" | sed -n 's/^  \(-[^ ]*\).*/\1/p' \
  | sed 's/,$//; s/<.*//' | tr -d '\r')
help_options=$(printf '%s\n%s\n' "$help_options" \
  "$(printf '%s\n' "$output" | sed -n 's/^  -h, \(--help\).*/\1/p' | tr -d '\r')" | sort -u)

# Options the page describes: the first word of the line after each .TP in
# OPTIONS, with "\-" as "-" and ".BR -h , --help" as two.
page_options=$(awk '
  /^\.SH / { in_options = ($2 == "OPTIONS") }
  in_options && after_tp {
    line = $0
    gsub(/\\-/, "-", line)
    sub(/^\.[A-Z]+ /, "", line)
    n = split(line, words, /[ ,"]+/)
    for (i = 1; i <= n; i++) {
      if (words[i] ~ /^-/) {
        print words[i]
        if (words[i] != "-h") break
      }
    }
    after_tp = 0
  }
  /^\.TP/ { after_tp = 1 }
' "$page" | sort -u)

[ -n "$help_options" ] || fail "found no options in xctest -h"

missing=$(comm -23 <(echo "$help_options") <(echo "$page_options"))
extra=$(comm -13 <(echo "$help_options") <(echo "$page_options"))
[ -z "$missing" ] || fail "options in xctest -h that xctest.1 doesn't describe: $(echo $missing)"
[ -z "$extra" ] || fail "options in xctest.1 that xctest -h doesn't list: $(echo $extra)"

echo "Man page regressions passed ($(echo "$help_options" | wc -l) options)."
