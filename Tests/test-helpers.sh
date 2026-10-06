# Shared helpers for the run-*-tests.sh scripts. Source this file, then call
# parse_test_args "$@".

parse_test_args() {
  if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
    echo "usage: $0 <xctest-bin> <xctest-lib-dir> <source-root> [runtime-lib-dirs]" >&2
    exit 2
  fi

  xctest_bin=$1
  xctest_lib_dir=$2
  source_root=$3
  runtime_lib_dirs=${4:-}

  if [ -z "$runtime_lib_dirs" ] && [ -n "${GNUSTEP_MAKEFILES:-}" ]; then
    runtime_lib_dirs="$(dirname "$GNUSTEP_MAKEFILES")/Libraries"
  fi

  # Windows finds DLLs on PATH, not LD_LIBRARY_PATH.
  if is_windows; then
    export PATH="$xctest_lib_dir:$PATH"
  fi
}

# True under MSYS2 or Cygwin on Windows.
is_windows() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
  esac
  return 1
}

# A path as xctest prints it: on Windows, /tmp/x is C:/msys64/tmp/x.
native_path() {
  if is_windows; then
    cygpath -m "$1"
  else
    printf '%s\n' "$1"
  fi
}

# bundle_binary <Name.xctest> <Name>: the bundle's executable, which is
# <Name>.dll on Windows.
bundle_binary() {
  if [ -f "$1/$2.dll" ]; then
    printf '%s\n' "$1/$2.dll"
  else
    printf '%s\n' "$1/$2"
  fi
}

# build_fixture <Name> builds Tests/<Name>/<Name>.bundle.
build_fixture() {
  echo "Building $1 bundle..."
  make -C "$source_root/Tests/$1" clean all \
    XCTEST_SOURCE_ROOT="$source_root" \
    XCTEST_LIBRARY_DIR="$xctest_lib_dir"
}

# run_fixture <Name> [xctest args...] sets $output and $status.
run_fixture() {
  local name=$1
  shift
  set +e
  output=$(LD_LIBRARY_PATH="$xctest_lib_dir${runtime_lib_dirs:+:$runtime_lib_dirs}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    "$xctest_bin" "$source_root/Tests/$name/$name.bundle" "$@" 2>&1)
  status=$?
  set -e
}

fail() {
  echo "$1" >&2
  echo "$output" >&2
  exit 1
}

assert_contains() {
  [[ "$output" == *"$1"* ]] || fail "expected output to contain: $1"
}

assert_not_contains() {
  [[ "$output" != *"$1"* ]] || fail "expected output to omit: $1"
}

assert_status() {
  [ "$status" -eq "$1" ] || fail "expected exit status $1, got $status"
}
