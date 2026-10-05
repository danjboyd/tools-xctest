#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/test-helpers.sh"
parse_test_args "$@"

build_fixture OrderFixture

report_dir=$(mktemp -d)
trap 'rm -rf "$report_dir"' EXIT

# The tests as they ran, as "Class.test" (and "Class +setUp") separated by |.
ran() {
  printf '%s\n' "$output" | grep -o 'order: .*' | sed 's/^order: //' | paste -sd '|' -
}

echo "Running execution order regressions..."

# Alphabetical by default.
run_fixture OrderFixture
assert_status 0
assert_not_contains "random order"
alphabetical=$(ran)
expected="Alpha +setUp|Alpha.testOne|Alpha.testThree|Alpha.testTwo|Alpha +tearDown"
expected+="|Beta +setUp|Beta.testOne|Beta.testThree|Beta.testTwo|Beta +tearDown"
expected+="|Gamma +setUp|Gamma.testOne|Gamma.testThree|Gamma.testTwo|Gamma +tearDown"
[ "$alphabetical" = "$expected" ] || fail "unexpected default order: $alphabetical"

# A seed gives the same shuffled order every time, with each class's
# tests still together between its +setUp and +tearDown.
run_fixture OrderFixture -test-execution-order-seed 42 -junit-report "$report_dir/order.xml"
assert_status 0
assert_contains "XCTest: Running tests in random order (seed 42; repeat with -test-execution-order-seed 42)"
seeded=$(ran)
expected="Gamma +setUp|Gamma.testTwo|Gamma.testOne|Gamma.testThree|Gamma +tearDown"
expected+="|Alpha +setUp|Alpha.testOne|Alpha.testTwo|Alpha.testThree|Alpha +tearDown"
expected+="|Beta +setUp|Beta.testThree|Beta.testTwo|Beta.testOne|Beta +tearDown"
[ "$seeded" = "$expected" ] || fail "unexpected order for seed 42: $seeded"
grep -q '<property name="executionOrderSeed" value="42"/>' "$report_dir/order.xml" \
  || fail "expected the seed in the JUnit report"

# Listing follows the same order.
run_fixture OrderFixture -list-tests -test-execution-order-seed 42
listed=$(printf '%s\n' "$output" | grep '^OrderFixture/' | sed 's|^OrderFixture/||; s|Tests/|.|' | paste -sd '|' -)
[ "$listed" = "Gamma.testTwo|Gamma.testOne|Gamma.testThree|Alpha.testOne|Alpha.testTwo|Alpha.testThree|Beta.testThree|Beta.testTwo|Beta.testOne" ] \
  || fail "expected -list-tests to follow the seeded order: $listed"

# Without a seed one is picked and logged, and it repeats the run.
run_fixture OrderFixture -test-execution-order random
assert_status 0
seed=$(printf '%s\n' "$output" | sed -n 's/.*random order (seed \([0-9]*\);.*/\1/p')
[ -n "$seed" ] || fail "expected the chosen seed to be logged"
first=$(ran)
run_fixture OrderFixture -test-execution-order-seed "$seed"
[ "$(ran)" = "$first" ] || fail "expected seed $seed to repeat the order"

# Filters and random order combine.
run_fixture OrderFixture -test-execution-order-seed 42 -only-testing:OrderFixture/BetaTests
[ "$(ran)" = "Beta +setUp|Beta.testThree|Beta.testTwo|Beta.testOne|Beta +tearDown" ] \
  || fail "unexpected filtered order: $(ran)"

run_fixture OrderFixture -test-execution-order sideways
assert_status 1
assert_contains "-test-execution-order must be 'alphabetical' or 'random'"
run_fixture OrderFixture -test-execution-order-seed 0
assert_status 1
assert_contains "-test-execution-order-seed needs a whole number greater than 0"

echo "Execution order tests passed."
