#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

build_fixture ModuleFixture

echo "Running module-qualified class name regressions..."

# Swift registers a test class as <Module>.<Class>. Identifiers leave the
# module out, as Apple's do.
run_fixture ModuleFixture -list-tests
assert_status 0
[ "$output" = $'ModuleFixture/SwiftStyleTests/testOne\nModuleFixture/SwiftStyleTests/testTwo\nModuleFixture/PlainTests/testPlain' ] \
  || fail "expected the Swift-style class to be listed without its module"

# Selected by the class name alone...
run_fixture ModuleFixture -only-testing:ModuleFixture/SwiftStyleTests
assert_status 0
assert_contains "fixture: SwiftStyleTests.testOne"
assert_contains "fixture: SwiftStyleTests.testTwo"
assert_not_contains "fixture: PlainTests.testPlain"

run_fixture ModuleFixture -only-testing:ModuleFixture/SwiftStyleTests/testTwo
assert_status 0
assert_contains "fixture: SwiftStyleTests.testTwo"
assert_not_contains "fixture: SwiftStyleTests.testOne"

run_fixture ModuleFixture -skip-testing:ModuleFixture/SwiftStyleTests/testTwo
assert_status 0
assert_contains "fixture: SwiftStyleTests.testOne"
assert_not_contains "fixture: SwiftStyleTests.testTwo"
assert_contains "fixture: PlainTests.testPlain"

run_fixture ModuleFixture -XCTest SwiftStyleTests/testOne
assert_status 0
assert_contains "fixture: SwiftStyleTests.testOne"
assert_not_contains "fixture: SwiftStyleTests.testTwo"

# ...and by its full runtime name.
run_fixture ModuleFixture -only-testing:ModuleFixture/ModuleFixture.SwiftStyleTests/testOne
assert_status 0
assert_contains "fixture: SwiftStyleTests.testOne"
assert_not_contains "fixture: SwiftStyleTests.testTwo"

run_fixture ModuleFixture -XCTest ModuleFixture.SwiftStyleTests/testTwo
assert_status 0
assert_contains "fixture: SwiftStyleTests.testTwo"
assert_not_contains "fixture: SwiftStyleTests.testOne"

# The dot form: Module.Class.method. (Module.Class alone reads as
# Class.method, as it always has; select a whole class by its name.)
run_fixture ModuleFixture -XCTest ModuleFixture.SwiftStyleTests.testTwo
assert_status 0
assert_contains "fixture: SwiftStyleTests.testTwo"
assert_not_contains "fixture: SwiftStyleTests.testOne"

run_fixture ModuleFixture -XCTest SwiftStyleTests.testOne
assert_status 0
assert_contains "fixture: SwiftStyleTests.testOne"
assert_not_contains "fixture: SwiftStyleTests.testTwo"

# Another module's name doesn't match.
run_fixture ModuleFixture -only-testing:ModuleFixture/Other.SwiftStyleTests
assert_status 1
assert_contains "No tests matched 'ModuleFixture/Other.SwiftStyleTests'"

# Output names the class as it is registered, as Apple's does.
run_fixture ModuleFixture -only-testing:ModuleFixture/SwiftStyleTests/testOne
assert_contains "ModuleFixture.SwiftStyleTests"

# Parallel workers are given the listed identifiers; each test runs once.
run_fixture ModuleFixture -parallel-testing-enabled YES -parallel-testing-worker-count 2
assert_status 0
[ "$(printf '%s\n' "$output" | grep -c 'fixture: SwiftStyleTests.testOne')" -eq 1 ] \
  || fail "expected testOne to run once in a parallel run"
[ "$(printf '%s\n' "$output" | grep -c 'fixture: SwiftStyleTests.testTwo')" -eq 1 ] \
  || fail "expected testTwo to run once in a parallel run"

echo "Module-qualified class name regressions passed."
