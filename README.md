# tools-xctest

`tools-xctest` is a testing framework for Objective-C, providing functionalities identical to Apple's XCTest. It is designed for use with the GNUstep development environment. This framework allows developers to write and run unit tests for their Objective-C code in a way that is familiar to those accustomed to XCTest in Apple's ecosystem.

## Requirements
- GNUstep Base
- GNUstep Make

## Installation

### Dependencies
- GNUstep Base
- GNUstep Make

### Using Meson
1. Run `meson setup build`
2. Build XCTest with `ninja -C build`
3. Install XCTest with `ninja -C build install`

### Using GNUstep Make
1. Run `make` to build the project.
2. Run `make install` to install `tools-xctest` on your system.

## Usage
To use `tools-xctest`, include the header files in your test classes and link against the `tools-xctest` library. The usage is similar to Apple's XCTest:

```objc
#import <XCTest/XCTest.h>

@interface MyTestCase : XCTestCase
@end

@implementation MyTestCase

- (void)testExample {
    XCTAssertEqual(1 + 1, 2, @"Basic arithmetic doesn't seem to work!");
}

@end
```

Test classes support the same lifecycle as Apple's XCTest:

- `+setUp` and `+tearDown` run once per class, around all of its tests.
- Each test gets a fresh instance and runs `-setUpWithError:`, `-setUp`, the test method, any blocks registered with `-addTeardownBlock:` (last added first), `-tearDown`, then `-tearDownWithError:`.
- Teardown always runs, even when set up or the test fails or throws.
- Set `continueAfterFailure = NO` to stop a test at its first failed assertion.
- Test methods inherited from a superclass are run for each subclass, and tests run in alphabetical order.
- Call `XCTExpectFailure(@"reason")` (or `XCTExpectFailureInBlock`) to mark known failures: they are reported as expected and don't fail the test, and a strict expectation fails the test if nothing failed. `XCTExpectedFailureOptions` makes it non-strict, disables it, or matches only some issues.
- Call `XCTSkip(...)`, `XCTSkipIf(condition, ...)` or `XCTSkipUnless(condition, ...)` to skip the rest of a test, for example when it needs a display or a platform feature that isn't available. Skipped tests are reported separately and don't fail the run; teardown still runs.

### Activities

`[XCTContext runActivityNamed:@"Log in" block:^(id<XCTActivity> activity) { ... }]` runs part of a test as a named step. Activities nest (on each thread), and failures recorded inside one are reported with its path, e.g. `Log in > Enter password: ((valid) is true) failed`, in the console, `-output-format apple` (which also prints Apple's `t = 0.01s Log in` lines) and JUnit reports.

### Asynchronous tests

Code driven by the run loop (timers, notifications, `NSURLConnection`, `NSTask`, `performSelector:afterDelay:`) can be tested with expectations. Waiting runs the current run loop until the expectations are fulfilled or the timeout passes; a timeout is a test failure.

```objc
- (void)testDownload {
    XCTestExpectation *done = [self expectationWithDescription:@"download finished"];
    [downloader fetchWithCompletion:^(NSData *data) {
        XCTAssertNotNil(data);
        [done fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
}
```

Also available: `waitForExpectations:timeout:enforceOrder:`, inverted expectations and `expectedFulfillmentCount`, `expectationForNotification:object:handler:`, `keyValueObservingExpectationForObject:keyPath:expectedValue:`, `expectationForPredicate:evaluatedWithObject:handler:`, and `XCTWaiter` for waiting without failing the test. `-fulfill` may be called from any thread.

### Test suites, runs and observers

Tests are run through Apple's object model. Each test is an `XCTestCase` instance bound to one test method, grouped in `XCTestSuite`s, and its results are kept in an `XCTestRun` (`XCTestCaseRun`, `XCTestSuiteRun`). This means you can:

- Override `+defaultTestSuite` or `+testInvocations` to change which tests a class has. For example, an abstract base class can return an empty suite so its tests only run in subclasses.
- Override `-invokeTest` to wrap each test, or `-recordIssue:` to see, change or drop failures. Every failure is an `XCTIssue` with a type (assertion failure, thrown error, uncaught exception, performance regression, ...), a source location and, for errors from `-setUpWithError:`, the `associatedError`; `XCTMutableIssue` lets an override change one. Overrides of the older `-recordFailureWithDescription:inFile:atLine:expected:` still work.
- Build and run suites yourself, and check the run's counts (`failureCount`, `skipCount`, `hasSucceeded`, ...).
- Register an `XCTestObservation` observer (it gets `testCase:didRecordIssue:` for each failure) with `XCTestObservationCenter` to follow progress. To register one before any test runs, do it in the `-init` of the bundle's principal class (with gnustep-make, `MyTests_PRINCIPAL_CLASS = MyObserverRegistrar`); `xctest` creates it before running tests.

### Performance tests

`measureBlock:` runs a block 10 times and reports the average wall-clock time and relative standard deviation. `measureMetrics:automaticallyStartMeasuring:NO forBlock:` with `startMeasuring`/`stopMeasuring` measures only part of each run.

To catch regressions, keep baselines in a JSON file keyed by `TestClass/testMethod`:

```json
{ "ParserTests/testParseLargeFile": { "average": 0.120, "maxPercentRegression": 10 } }
```

`xctest -performance-baselines baselines.json ...` fails a measured test whose average is worse than its baseline by more than `maxPercentRegression` (default 10%). Add `-update-performance-baselines` to record the current averages into the file instead (keeping each entry's settings). Apple keeps baselines in the Xcode project; this file is the GNUstep equivalent.

### Hosted tests (running inside your application)

To test code that needs a running `NSApplication` (controllers, windows, nib/gorm loading, the responder chain), run the bundle inside your app:

```bash
xctest -host MyApp.app MyAppTests.bundle
```

`xctest` launches the app with `libXCTestHost` preloaded. Once the app has finished launching (after its own `applicationDidFinishLaunching:`), the test bundle is loaded and its tests run on the main thread inside the app, which then exits with the result. The app needs no changes. Filters, `-output-format` and `-junit-report` work as usual. If the app hasn't started the tests within 60 seconds (`-host-launch-timeout <seconds>`; 0 waits forever), `xctest` stops it and fails; the tests themselves have no time limit. On a headless machine, run it under `xvfb-run -a`. Tests that also run without a host can skip themselves with `XCTSkipUnless(NSApp != nil)`.

You will need to compile the test cases into one or more bundles, as `xctest` expects `.bundle`'s. 

## Running Tests
Tests can be run using the command line tool provided by `tools-xctest`. This can be done by navigating to the directory containing your test cases and executing:

```bash
xctest [path to your test case bundle]
```

The CLI also supports Apple's `xcodebuild` filter syntax for selecting or excluding tests:

```bash
xctest MyTests.bundle -only-testing:MyTests/FooTests/testBar
xctest MyTests.bundle -skip-testing:MyTests/SlowTests
```

Test identifiers use the form `TestTarget[/TestClass[/TestMethod]]`, where `TestTarget` is the bundle name without the `.bundle` extension.

By default results are logged as `XCTest: ...` lines. Pass `-output-format apple` to print them on stdout in the same format as Apple's `xctest`, including per-test timings, so tools that parse Apple's output (xcpretty, xcbeautify, editor integrations) work too:

```
Test Case '-[FooTests testBar]' started.
FooTests.m:12: error: -[FooTests testBar] : ((1 + 1) equal to (3)) failed: ("2") is not equal to ("3")
Test Case '-[FooTests testBar]' failed (0.001 seconds).
```

For CI, `-junit-report <path>` also writes the results as JUnit XML (one `<testsuite>` per test class; assertion failures as `<failure>`, uncaught exceptions as `<error>`, skips as `<skipped>`), which GitHub Actions, GitLab CI and Jenkins can display.

To see which tests a run would select without running them, add `-list-tests` (one `TestTarget/TestClass/testMethod` identifier per line) or `-list-tests-json`. Filters apply, so this is a quick way to check an `-only-testing`/`-skip-testing` combination:

```bash
xctest MyTests.bundle -list-tests -only-testing:MyTests/FooTests
```

To find flaky tests, `-test-iterations <n>` runs each test n times. With `-run-tests-until-failure` a test repeats until it fails (at most 100 times, or n), and with `-retry-tests-on-failure` a failing test is retried until it passes (at most 3 times, or n); failed attempts followed by a pass don't count. Each run uses a fresh test case; class `+setUp`/`+tearDown` still run once.

To keep a hung test from hanging CI, give tests a time limit: with `-test-timeouts-enabled YES`, each test (including its set up and teardown) may run for its `executionTimeAllowance`, 600 seconds unless `-default-test-execution-time-allowance <seconds>` says otherwise. A test can change its own allowance (e.g. `self.executionTimeAllowance = 120` in `-setUp`), and `-maximum-test-execution-time-allowance <seconds>` caps it. Either allowance option turns time limits on. A test that runs out of time fails; the console output, JUnit report and observers are finished for the tests that ran, and `xctest` exits with a failure without running the remaining tests (Apple's XCTest restarts the process instead, and rounds allowances up to whole minutes, which this doesn't). This works with `-host` too.

Automated CLI regression tests can be run with `make check` or `meson test -C build`.

## License
`tools-xctest` is licensed under LGPL-2.1. Please refer to the COPYING.LIB file for detailed information. For files not explicitly licensed, they fall under the same LGPL.

## Contributions
Contributions to `tools-xctest` are welcome. Please submit pull requests or issues through the GitHub repository.
