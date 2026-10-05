# Changelog

Releases of this fork (danjboyd/tools-xctest). Versions are tagged
`vX.Y.Z`; 0.1.x are upstream's (gnustep/tools-xctest).

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
