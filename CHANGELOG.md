# Changelog

Releases of this fork (danjboyd/tools-xctest). Versions are tagged
`vX.Y.Z`; 0.1.x are upstream's (gnustep/tools-xctest).

## Unreleased

- Upstream's CRLF line endings are restored in `XCTestAssertions.h`,
  `XCTestAssertionsImpl.h` and `GSXCTestRunner.h`.
- Restored three upstream fixes the merge had lost: `+[GSXCTestRunner
  sharedRunner]` is synchronized, `expectedFulfillmentCount` rejects 0,
  and test-class discovery retries if classes are added while it runs.

## 0.5.0

This release is built on upstream's rewrite of tools-xctest
(gnustep/tools-xctest 5c84fc3), merged into the fork.

Runs that used to pass can now fail: a run in which no test executes,
and a `-XCTest` or `-only-testing` selection that matches no test, both
exit nonzero. `+tearDown` now also runs after a failed `+setUp`.

- CI: GitHub Actions builds and tests on Linux (clang, libobjc2; make
  check and meson test) and Windows (MSYS2 clang64; make check).
- Builds and runs on Windows (MSYS2 clang64): the CPU, memory and
  storage metrics use the Windows process APIs, parallel workers find
  `xctest` without `/proc`, and a crashed worker's status is shown in
  hex (`status 0xC0000409`). `xctest` writes `\n` line endings there
  too. `-host` and `libXCTestHost` are left out, since they need
  `LD_PRELOAD`. `xctest-bundle` names a DLL's copy `<Name>.dll`.
- The time-limit watchdog creates its lock in `+initialize` instead of
  with `pthread_once`.
- Merged upstream's rewrite (gnustep/tools-xctest 5c84fc3): its
  `AGENTS.md`, `Tests/Regression.m` and `Tests/run.sh` (now part of
  `make check` and `meson test`), and these behaviours:
  - A run in which no test executes fails, as does each `-XCTest` or
    `-only-testing` selection that matches no test ("No tests matched
    '<selection>'."), also with `-list-tests`.
  - `-XCTest` accepts `Class.method` as well as `Class/method`.
  - `+tearDown` runs even if `+setUp` failed or skipped the class.
  - `-[XCTestCase failureCount]` (GNUstep extension); `-invokeTest`
    called directly runs the test in a run of its own.
  - `-initWithSelector:` rejects selectors that aren't test methods, and
    a test case without an invocation fails.
  - Accuracy assertions take integers as well as floating-point values,
    compared without overflow; a negative or NaN accuracy never matches.
  - Assertion messages may use a non-literal format string.
  - The wait handler's timeout error names the unfulfilled expectations.
- Fixes: an exception thrown while evaluating an assertion's arguments
  is an unexpected failure, not an expected one (gnustep/tools-xctest#10);
  `XCTAssertGreaterThan`, `...LessThan` and the `OrEqual` forms fail for
  NaN operands. The fork already behaved as gnustep/tools-xctest#9 and
  #11 ask; `Tests/Regression.m` now checks those too.
- `XCTMetric`'s memory and storage errors use `XCTestErrorDomain`.
- Line endings are LF, except in upstream's CRLF files. (As released,
  0.5.0 also converted three of upstream's CRLF files to LF; the next
  release restores them.)

## 0.4.0

- Randomized execution order: `-test-execution-order random`, with the
  seed logged and recorded in JUnit reports, and
  `-test-execution-order-seed <n>` to repeat an order.
- The `XCTMetric` performance API: `measureWithMetrics:options:block:`,
  `XCTMeasureOptions`, and the clock, CPU, memory and storage metrics;
  baselines per metric.
- Parallel execution: `-parallel-testing-enabled YES` and
  `-parallel-testing-worker-count <n>` run each test class in a worker
  process; a crashed or hung worker only affects its own class.
- Apple's `-XCTest <tests>` selection syntax; `.xctest` bundles.
- Build-system helpers: `xctest.make` for gnustep-make projects
  (`include $(GNUSTEP_MAKEFILES)/Auxiliary/xctest.make`, `make check`)
  and the `xctest-bundle` script for Meson and other build systems.

## 0.3.0

- Every failure is an `XCTIssue` recorded with `-[XCTestCase recordIssue:]`,
  with a type, source location (`XCTSourceCodeContext`), associated error
  and attachments; `XCTMutableIssue`. Overrides of
  `-recordFailureWithDescription:...` keep working. Observers get
  `testCase:didRecordIssue:` and `testSuite:didRecordIssue:`.
- Per-test time limits: `executionTimeAllowance`, and
  `-test-timeouts-enabled`, `-default-test-execution-time-allowance` and
  `-maximum-test-execution-time-allowance`. A test that runs out of time
  fails, the reports are finished, and xctest exits.
- `XCTContext` activities (`runActivityNamed:block:`); failures inside
  one are reported with its path, and `-output-format apple` prints
  Apple's `t =` lines.
- `XCTAttachment`, from tests, activities and issues; saved under
  `-attachments-path` (or next to the `-junit-report`) and linked from the
  JUnit report.

## 0.2.1

- Fix a leak: test cases and their runs retained each other.
- Report failures that arrive outside their test's lifetime.
- Only void, argument-less methods are tests; assertion macro locals no
  longer collide with the caller's variables.
- Fix the XCTSkipIf/XCTSkipUnless message mangled by the macro rename.
- Fix suites that contain suites.

## 0.2.0

- Apple-style `-only-testing` / `-skip-testing` filters.
- Full test lifecycle: class and instance set up and tear down, teardown
  blocks, `continueAfterFailure`.
- `XCTSkip`, descriptive assertion messages, `XCTExpectFailure`.
- Asynchronous testing with `XCTestExpectation` and `XCTWaiter`.
- Apple's `XCTestSuite` / `XCTestRun` / `XCTestObservation` object model.
- Performance tests (`measureBlock:`) with JSON baselines.
- `-output-format apple`, JUnit reports, `-list-tests`, a failed-test
  summary, and test repetition (`-test-iterations`,
  `-run-tests-until-failure`, `-retry-tests-on-failure`).
- Hosted tests: `xctest -host App.app`, via libXCTestHost.
