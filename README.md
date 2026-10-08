# tools-xctest

An Objective-C XCTest compatibility library and command-line test runner for
GNUstep. Build with `make` in a configured GNUstep development environment.
The library requires Objective-C exceptions and blocks support.

Link test bundles or standalone test programs against `libXCTest` and import
`<XCTest/XCTest.h>`. For an uninstalled build, add this repository to the header
search path and `XCTest/obj` to the library search path. On Linux, put
`XCTest/obj` in `LD_LIBRARY_PATH` when running against the local library.

```sh
xctest path/to/Tests.bundle
xctest -XCTest ExampleTests path/to/Tests.bundle
xctest -XCTest ExampleTests.testAddition,OtherTests.testParsing path/to/Tests.bundle
```

`-XCTest All` runs all discovered tests. Apple's `Class/method` form works as
well as `Class.method`. Exit status is zero only when at least one test executes
and every selected test succeeds. Invalid bundles, unknown options, unmatched
filters (each selection is checked), empty runs, assertion failures, and
uncaught exceptions return nonzero.

## Building with Meson

As an alternative to GNUstep Make, use Meson with Clang and a configured
GNUstep environment:

```sh
OBJC=clang meson setup build
meson compile -C build
meson install -C build
```

The runner is part of `libXCTest`; its public header is
`<XCTest/GSXCTestRunner.h>`.

It also builds and runs on Windows with MSYS2 (clang64) and GNUstep Make,
except for hosted tests (`-host`), which need `LD_PRELOAD`. There, test bundles'
executables are `<Name>.dll`.

## Supported behavior

- Discovery of `void` instance methods whose names start with `test` and which
  take no arguments, including inherited methods and subclass overrides.
  Classes and methods run in alphabetical order, with a fresh instance per test.
- Class `+setUp` / `+tearDown` and instance `-setUp` / `-tearDown`, plus
  `-setUpWithError:`, `-tearDownWithError:` and `-addTeardownBlock:`. Instance
  teardown runs even when setup or the test throws; class teardown runs after
  class setup failures. Uncaught exceptions are recorded as failures.
- Selector- and invocation-based test construction, `name`, `invocation`,
  `invokeTest`, `continueAfterFailure` (default `YES`), and overridable
  `recordFailureWithDescription:inFile:atLine:expected:` and `recordIssue:`.
  The GNUstep extension `failureCount` reports failures for the latest run.
  Standalone cases work without linking the runner.
- Boolean, nil, object/scalar equality, identity, ordering, accuracy, and
  exception assertions. Diagnostics include expressions, values, file/line, and
  optional formatted messages. Expressions are evaluated once; an exception
  thrown while evaluating them is an unexpected failure.
  Accuracy comparisons support integers and floating-point values without
  integer subtraction overflow. NaN operands or a negative/NaN accuracy never
  yield equality, and ordering assertions fail for NaN operands.
- `XCTSkip`, `XCTSkipIf` and `XCTSkipUnless`, in a test or in `+setUp` (which
  skips the whole class), and `XCTExpectFailure` for known failures.
- `XCTestExpectation`, fulfillment counts, inverted expectations, and
  over-fulfillment checks (`assertForOverFulfill`, on by default for
  expectations a test case creates). `fulfill` is thread-safe.
  `waitForExpectationsWithTimeout:handler:` and
  `waitForExpectations:timeout:` (and `enforceOrder:`) pump the calling thread's
  default run loop. Timeouts and expectation violations record failures;
  completion handlers receive an `NSError` on failure. Case-created expectations
  must be waited on. Notification, KVO and predicate expectations, and
  `XCTWaiter` for waiting without failing the test.
- Apple's object model: `XCTestSuite`, `XCTestRun` (`XCTestCaseRun`,
  `XCTestSuiteRun`), `XCTestObservation` and `XCTestObservationCenter`, and
  `XCTIssue` for every failure.
- `XCTContext` activities, `XCTAttachment`, and performance tests
  (`measureBlock:` and the `XCTMetric` API).
- In the runner: Apple-style `-only-testing` / `-skip-testing` filters,
  Apple-format output, JUnit reports, test listing, repetition, random order,
  per-test time limits, parallel runs, and running tests inside an application.
  `xctest.make` and `xctest-bundle` build test bundles.

Create and wait on expectations on the test thread; callbacks on other threads
may fulfill them. Inverted expectations require waiting for the entire timeout.
Empty expectation lists are rejected. A wait may be started from a run loop
callback during another wait. Fulfilling an expectation again after its wait
has completed is reported when `assertForOverFulfill` is set.

This is a subset of XCTest, not full Apple XCTest compatibility. UI testing
(`XCUIApplication`) is not implemented, and the CPU metric doesn't report
Apple's cycle and instruction counts.

The sections below describe these in more detail.

### Writing tests

```objc
#import <XCTest/XCTest.h>

@interface MyTestCase : XCTestCase
@end

@implementation MyTestCase
- (void)testExample
{
    XCTAssertEqual(1 + 1, 2, @"Basic arithmetic doesn't seem to work!");
}
@end
```

Each test gets a fresh instance and runs `-setUpWithError:`, `-setUp`, the test
method, any blocks registered with `-addTeardownBlock:` (last added first),
`-tearDown`, then `-tearDownWithError:`. Set `continueAfterFailure = NO` to stop
a test at its first failed assertion.

Call `XCTSkip(...)`, `XCTSkipIf(condition, ...)` or `XCTSkipUnless(condition,
...)` to skip the rest of a test, for example when it needs a display or a
platform feature that isn't available. Skipped tests are reported separately and
don't fail the run; teardown still runs. Call `XCTExpectFailure(@"reason")` (or
`XCTExpectFailureInBlock`) to mark known failures: they are reported as expected
and don't fail the test, and a strict expectation fails the test if nothing
failed. `XCTExpectedFailureOptions` makes it non-strict, disables it, or matches
only some issues.

### Asynchronous tests

Code driven by the run loop (timers, notifications, `NSURLConnection`,
`NSTask`, `performSelector:afterDelay:`) can be tested with expectations.
Waiting runs the current run loop until the expectations are fulfilled or the
timeout passes; a timeout is a test failure.

```objc
- (void)testDownload
{
    XCTestExpectation *done = [self expectationWithDescription:@"download finished"];
    [downloader fetchWithCompletion:^(NSData *data) {
        XCTAssertNotNil(data);
        [done fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
}
```

Also available: `expectationForNotification:object:handler:`,
`keyValueObservingExpectationForObject:keyPath:expectedValue:`,
`expectationForPredicate:evaluatedWithObject:handler:`, and `XCTWaiter`.

### Test suites, runs and observers

Each test is an `XCTestCase` instance bound to one test method, grouped in
`XCTestSuite`s, and its results are kept in an `XCTestRun`. This means you can:

- Override `+defaultTestSuite` or `+testInvocations` to change which tests a
  class has. For example, an abstract base class can return an empty suite so
  its tests only run in subclasses.
- Override `-invokeTest` to wrap each test, or `-recordIssue:` to see, change or
  drop failures. Every failure is an `XCTIssue` with a type (assertion failure,
  thrown error, uncaught exception, performance regression, ...), a source
  location and, for errors from `-setUpWithError:`, the `associatedError`;
  `XCTMutableIssue` lets an override change one. Overrides of
  `-recordFailureWithDescription:inFile:atLine:expected:` still work.
- Build and run suites yourself, and check the run's counts (`failureCount`,
  `skipCount`, `hasSucceeded`, ...). Calling `-invokeTest` directly runs the test
  in a run of its own, and `-[XCTestCase failureCount]` gives its failures.
- Register an `XCTestObservation` observer (it gets `testCase:didRecordIssue:`
  for each failure) with `XCTestObservationCenter` to follow progress. To
  register one before any test runs, do it in the `-init` of the bundle's
  principal class (with gnustep-make, `MyTests_PRINCIPAL_CLASS =
  MyObserverRegistrar`); `xctest` creates it before running tests.

### Activities and attachments

`[XCTContext runActivityNamed:@"Log in" block:^(id<XCTActivity> activity) {
... }]` runs part of a test as a named step. Activities nest (on each thread),
and failures recorded inside one are reported with its path, e.g. `Log in >
Enter password: ((valid) is true) failed`, in the console, `-output-format
apple` (which also prints Apple's `t = 0.01s Log in` lines) and JUnit reports.

Keep logs, files, images or archived objects with a test's results: `[self
addAttachment:[XCTAttachment attachmentWithString:log]]`, or from an activity
(`[activity addAttachment:...]`) or an issue (`XCTMutableIssue
-addAttachment:`). `XCTAttachment` has Apple's constructors for data, files,
strings, property lists, archivable objects and `NSImage` (saved as PNG, or JPEG
for lower qualities; AppKit must be loaded, as in hosted tests).

`xctest -attachments-path <dir>` saves them as
`<dir>/<TestClass>/<testMethod>/<name>.<ext>`; with `-junit-report results.xml`
and no `-attachments-path` they go in `results-attachments/`, and the report
links each one with a `[[ATTACHMENT|path]]` line in the test's `<system-out>`,
which Jenkins and GitLab pick up. As in Apple's XCTest, an attachment is only
kept if its test fails, unless its `lifetime` is
`XCTAttachmentLifetimeKeepAlways`.

### Performance tests

`measureBlock:` runs a block 10 times and reports the average wall-clock time
and relative standard deviation. `measureMetrics:automaticallyStartMeasuring:NO
forBlock:` with `startMeasuring`/`stopMeasuring` measures only part of each run.

To catch regressions, keep baselines in a JSON file keyed by
`TestClass/testMethod`:

```json
{ "ParserTests/testParseLargeFile": { "average": 0.120, "maxPercentRegression": 10 } }
```

`xctest -performance-baselines baselines.json ...` fails a measured test whose
average is worse than its baseline by more than `maxPercentRegression` (default
10%). Add `-update-performance-baselines` to record the current averages into
the file instead (keeping each entry's settings). Apple keeps baselines in the
Xcode project; this file is the GNUstep equivalent.

`measureWithMetrics:options:block:` (and `measureWithMetrics:block:`,
`measureWithOptions:block:`) runs the block `iterationCount` times (default 5)
with any `XCTMetric`s: `XCTClockMetric` (the default), `XCTCPUMetric` (CPU time,
for the process or the current thread), `XCTMemoryMetric` (resident memory
change and peak, in kB) and `XCTStorageMetric` (logical writes, in kB), read
from `getrusage` and `/proc` (on Windows, from the process and thread APIs,
where the memory peak is the process's peak so far), or your own class
conforming to `XCTMetric`. `XCTMeasureOptions` can leave starting or stopping to
the block (`-startMeasuring`/`-stopMeasuring`). Baselines for these go under the
test's `"metrics"`, by measurement identifier, and a measurement's polarity says
whether larger or smaller is worse:

```json
{ "ParserTests/testParse": { "metrics": { "com.apple.dt.XCTMetric_CPU.time": { "average": 0.05, "maxPercentRegression": 20 } } } }
```

### Hosted tests (running inside your application)

To test code that needs a running `NSApplication` (controllers, windows,
nib/gorm loading, the responder chain), run the bundle inside your app:

```sh
xctest -host MyApp.app MyAppTests.bundle
```

`xctest` launches the app with `libXCTestHost` preloaded. Once the app has
finished launching (after its own `applicationDidFinishLaunching:`), the test
bundle is loaded and its tests run on the main thread inside the app, which then
exits with the result. The app needs no changes. Filters, `-output-format` and
`-junit-report` work as usual. If the app hasn't started the tests within 60
seconds (`-host-launch-timeout <seconds>`; 0 waits forever), `xctest` stops it
and fails; the tests themselves have no time limit. On a headless machine, run
it under `xvfb-run -a`. Tests that also run without a host can skip themselves
with `XCTSkipUnless(NSApp != nil)`.

## Building test bundles

With gnustep-make, include the `xctest.make` that tools-xctest installs:

```make
include $(GNUSTEP_MAKEFILES)/common.make

XCTEST_BUNDLE_NAME = MyTests
MyTests_OBJC_FILES = FooTests.m BarTests.m

include $(GNUSTEP_MAKEFILES)/Auxiliary/xctest.make
```

`make` builds `MyTests.xctest`, linked with XCTest, and `make check` runs it with
`xctest`, failing if any test fails. Test bundles aren't installed.
`XCTEST_BUNDLE_NAME` can list several bundles; the usual bundle variables
(`MyTests_INCLUDE_DIRS`, `MyTests_BUNDLE_LIBS`, ...) still apply. Options for the
run go in `XCTEST_FLAGS` (e.g. `make check XCTEST_FLAGS="-junit-report
results.xml"`) or `MyTests_XCTEST_FLAGS`; `XCTEST_HOST=MyApp.app` runs the tests
inside an application, and `XCTEST_LAUNCHER="xvfb-run -a"` runs `xctest` under
another command. See the comments at the top of `xctest.make` for the rest.

With Meson (or anything that can build a shared library), build the tests as a
shared module and wrap it as a bundle with the installed `xctest-bundle` script:

```meson
xctest = find_program('xctest')
xctest_bundle = find_program('xctest-bundle')

my_tests_lib = shared_module('MyTests', 'FooTests.m', 'BarTests.m',
                             dependencies: [gnustep_dep],
                             link_args: ['-lXCTest'],
                             name_prefix: '')
my_tests = custom_target('MyTests.xctest',
                         input: my_tests_lib,
                         output: 'MyTests.xctest',
                         command: [xctest_bundle, '@OUTPUT@', '@INPUT@'],
                         build_by_default: true)
test('MyTests', xctest, args: [my_tests.full_path()], depends: [my_tests])
```

To build and run the test targets of an Xcode project, use `buildtool test`
from [libs-xcode](https://github.com/gnustep/libs-xcode); it runs each
`.xctest` bundle with `xctest`, inside the app named by the target's
`TEST_HOST` if it has one.

## Running tests

Besides `-XCTest`, the runner takes Apple's `xcodebuild` filter syntax for
selecting or excluding tests:

```sh
xctest MyTests.bundle -only-testing:MyTests/FooTests/testBar
xctest MyTests.bundle -skip-testing:MyTests/SlowTests
```

Test identifiers use the form `TestTarget[/TestClass[/TestMethod]]`, where
`TestTarget` is the bundle name without its `.bundle` or `.xctest` extension.

By default results are logged as `XCTest: ...` lines. Pass `-output-format
apple` to print them on stdout in the same format as Apple's `xctest`, including
per-test timings, so tools that parse Apple's output (xcpretty, xcbeautify,
editor integrations) work too:

```
Test Case '-[FooTests testBar]' started.
FooTests.m:12: error: -[FooTests testBar] : ((1 + 1) equal to (3)) failed: ("2") is not equal to ("3")
Test Case '-[FooTests testBar]' failed (0.001 seconds).
```

For CI, `-junit-report <path>` also writes the results as JUnit XML (one
`<testsuite>` per test class; assertion failures as `<failure>`, uncaught
exceptions as `<error>`, skips as `<skipped>`), which GitHub Actions, GitLab CI
and Jenkins can display.

To see which tests a run would select without running them, add `-list-tests`
(one `TestTarget/TestClass/testMethod` identifier per line) or
`-list-tests-json`. Filters apply, so this is a quick way to check an
`-only-testing`/`-skip-testing` combination:

```sh
xctest MyTests.bundle -list-tests -only-testing:MyTests/FooTests
```

To find flaky tests, `-test-iterations <n>` runs each test n times. With
`-run-tests-until-failure` a test repeats until it fails (at most 100 times, or
n), and with `-retry-tests-on-failure` a failing test is retried until it passes
(at most 3 times, or n); failed attempts followed by a pass don't count. Each
run uses a fresh test case; class `+setUp`/`+tearDown` still run once.

To catch tests that only pass because of what ran before them,
`-test-execution-order random` shuffles the test classes, and the tests within
each class (a class's tests still run together, between its `+setUp` and
`+tearDown`). The seed is logged and recorded in the JUnit report;
`-test-execution-order-seed <n>` repeats that order exactly, and `-list-tests`
shows it.

To keep a hung test from hanging CI, give tests a time limit: with
`-test-timeouts-enabled YES`, each test (including its set up and teardown) may
run for its `executionTimeAllowance`, 600 seconds unless
`-default-test-execution-time-allowance <seconds>` says otherwise. A test can
change its own allowance (e.g. `self.executionTimeAllowance = 120` in
`-setUp`), and `-maximum-test-execution-time-allowance <seconds>` caps it.
Either allowance option turns time limits on. A test that runs out of time
fails; the console output, JUnit report and observers are finished for the
tests that ran, and `xctest` exits with a failure without running the remaining
tests (Apple's XCTest restarts the process instead, and rounds allowances up to
whole minutes, which this doesn't). This works with `-host` too.

Large suites can run in parallel: `-parallel-testing-enabled YES` runs each test
class in a separate `xctest` worker process, `-parallel-testing-worker-count
<n>` at a time (default: one per CPU; giving a count turns parallel testing on).
Each class's output is printed as one block when it finishes, followed by the
usual summary; the JUnit report and exit status cover everything. Filters,
random order, repetition, time limits and attachments work as in a single run.
A worker that crashes fails only its own class's tests, and with time limits a
hung test stops only its own worker, so the rest of the run carries on. Classes
must not depend on running in the same process; observers registered by the
bundle see each worker's classes separately. It can't be combined with `-host`
or `-update-performance-baselines`.

## Regression tests

```sh
sh Tests/run.sh
```

This builds a standalone regression program and a loadable test bundle, checks
assertions, lifecycle, discovery, filtering, asynchronous waits, and CLI exit
statuses. Some fixtures fail deliberately; the script succeeds only when these
failures are detected correctly.

`make check` (or `meson test -C build`) runs it together with the
`Tests/run-*-tests.sh` scripts, each of which builds a fixture bundle and checks
one area of the runner's behaviour and output.

## License

The license for some files is in their headers. Files without an explicit
license are under the LGPL; see COPYING.LIB.
