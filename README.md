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
- Call `XCTSkip(...)`, `XCTSkipIf(condition, ...)` or `XCTSkipUnless(condition, ...)` to skip the rest of a test, for example when it needs a display or a platform feature that isn't available. Skipped tests are reported separately and don't fail the run; teardown still runs.

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

Automated CLI regression tests can be run with `make check` or `meson test -C build`.

## License
`tools-xctest` is licensed under LGPL-2.1. Please refer to the COPYING.LIB file for detailed information. For files not explicitly licensed, they fall under the same LGPL.

## Contributions
Contributions to `tools-xctest` are welcome. Please submit pull requests or issues through the GitHub repository.
