/*
 This file is part of the GNUstep XCTEST Library.

 This library is free software; you can redistribute it and/or
 modify it under the terms of the GNU Lesser General Public
 License as published by the Free Software Foundation; either
 version 2 of the License, or (at your option) any later version.

 This library is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.     See the GNU
 Lesser General Public License for more details.

 You should have received a copy of the GNU Lesser General Public
 License along with this library; see the file COPYING.LIB.
 If not, see <http://www.gnu.org/licenses/> or write to the
 Free Software Foundation, 51 Franklin Street, Fifth Floor,
 Boston, MA 02110-1301, USA.
*/

// Per-test time limits. While timeouts are enabled, a background thread
// watches the running test; one that runs past its execution time
// allowance is failed, the run's reports are finished, and the process
// exits. A hung test usually can't be stopped from inside the process, so
// the remaining tests don't run (Apple's XCTest restarts the process
// instead).

#import <XCTest/XCTestPrivate.h>

#include <pthread.h>
#include <stdio.h>
#include <unistd.h>

static BOOL GSTimeoutsEnabled = NO;
static NSTimeInterval GSDefaultAllowance = 600;
static NSTimeInterval GSMaximumAllowance = 0;

// Guards everything below, and is held for the whole of an abort so the
// test can't finish while its run is being stopped.
static NSCondition *GSWatchdogCondition = nil;
static BOOL GSWatchdogStarted = NO;
// The running test (not retained) and when it started; nil between tests.
static XCTestCase *GSWatchedTest = nil;
static NSDate *GSWatchedTestStart = nil;
// The suites running, outermost first (not retained), and how many of
// them enclose the watched test (any after those were started by it).
static NSMutableArray *GSRunningSuites = nil;
static NSUInteger GSEnclosingSuiteCount = 0;

static void GSCreateCondition(void)
{
    GSWatchdogCondition = [[NSCondition alloc] init];
    GSRunningSuites = [[NSMutableArray alloc] init];
}

static NSCondition *GSCondition(void)
{
    static pthread_once_t once = PTHREAD_ONCE_INIT;

    pthread_once(&once, GSCreateCondition);
    return GSWatchdogCondition;
}

// The allowance in effect for a test: its own, capped by the maximum.
static NSTimeInterval GSEffectiveAllowance(XCTestCase *test)
{
    NSTimeInterval allowance = [test executionTimeAllowance];

    if (GSMaximumAllowance > 0 && allowance > GSMaximumAllowance) {
        allowance = GSMaximumAllowance;
    }
    return allowance;
}

// "1 second", "2.5 seconds"
static NSString *GSSeconds(NSTimeInterval seconds)
{
    return [NSString stringWithFormat:@"%g second%@", seconds, seconds == 1 ? @"" : @"s"];
}

// On the watchdog thread, with the condition locked: fails the test, stops
// its run and the suites around it (so reporters finish the run and write
// their reports), then ends the process.
static void GSAbortTimedOutTest(XCTestCase *test, NSTimeInterval allowance)
{
    XCTestRun *testRun = [test testRun];
    XCTestRun *innerRun = testRun;
    NSArray *suites = [GSRunningSuites subarrayWithRange:NSMakeRange(0, GSEnclosingSuiteCount)];
    NSString *name = [test name];

    [testRun recordIssue:_GSXCTMakeIssue(XCTIssueTypeSystem,
        [NSString stringWithFormat:@"Test exceeded execution time allowance of %@", GSSeconds(allowance)],
        nil, 0, nil)];
    [testRun stop];

    for (NSValue *suiteValue in [suites reverseObjectEnumerator]) {
        XCTestSuiteRun *suiteRun = (XCTestSuiteRun *)[(XCTestSuite *)[suiteValue nonretainedObjectValue] testRun];

        [suiteRun addTestRun:innerRun];
        [suiteRun stop];
        innerRun = suiteRun;
    }

    fflush(stdout);
    fprintf(stderr, "xctest: %s exceeded its execution time allowance of %s; "
            "stopping the run (the remaining tests were not run)\n", [name UTF8String], [GSSeconds(allowance) UTF8String]);
    fflush(stderr);
    [[GSXCTestRunner sharedRunner] _gsTerminateWithExitCode:1];
    // Not reached unless a termination handler returns.
    _exit(1);
}

@interface GSXCTestWatchdog : NSObject
@end

@implementation GSXCTestWatchdog

+ (void) watch
{
    NSCondition *condition = GSCondition();

    [condition lock];
    for (;;) {
        @autoreleasepool {
            if (GSWatchedTest == nil) {
                [condition wait];
                continue;
            }

            NSTimeInterval allowance = GSEffectiveAllowance(GSWatchedTest);
            NSDate *deadline = [GSWatchedTestStart dateByAddingTimeInterval:allowance];

            if ([deadline timeIntervalSinceNow] <= 0) {
                GSAbortTimedOutTest(GSWatchedTest, allowance);
            }
            // The allowance can change while the test runs, so look again
            // at least every quarter second.
            [condition waitUntilDate:[deadline earlierDate:[NSDate dateWithTimeIntervalSinceNow:0.25]]];
        }
    }
}

@end

void _GSXCTSetTimeouts(BOOL enabled, NSTimeInterval defaultAllowance, NSTimeInterval maximumAllowance)
{
    GSTimeoutsEnabled = enabled;
    GSDefaultAllowance = defaultAllowance > 0 ? defaultAllowance : 600;
    GSMaximumAllowance = maximumAllowance > 0 ? maximumAllowance : 0;
}

NSTimeInterval _GSXCTDefaultExecutionTimeAllowance(void)
{
    return GSDefaultAllowance;
}

void _GSXCTWatchdogTestWillStart(XCTestCase *test)
{
    NSCondition *condition = GSCondition();

    if (!GSTimeoutsEnabled) {
        return;
    }

    [condition lock];
    // Tests run by the running test are covered by its allowance.
    if (GSWatchedTest == nil) {
        if (!GSWatchdogStarted) {
            GSWatchdogStarted = YES;
            [NSThread detachNewThreadSelector:@selector(watch) toTarget:[GSXCTestWatchdog class] withObject:nil];
        }
        GSWatchedTest = test;
        [GSWatchedTestStart release];
        GSWatchedTestStart = [[NSDate alloc] init];
        GSEnclosingSuiteCount = [GSRunningSuites count];
        [condition signal];
    }
    [condition unlock];
}

void _GSXCTWatchdogTestDidFinish(XCTestCase *test)
{
    NSCondition *condition = GSCondition();

    [condition lock];
    if (GSWatchedTest == test) {
        GSWatchedTest = nil;
        [condition signal];
    }
    [condition unlock];
}

void _GSXCTWatchdogAllowanceDidChange(void)
{
    NSCondition *condition = GSCondition();

    [condition lock];
    [condition signal];
    [condition unlock];
}

void _GSXCTWatchdogSuiteWillStart(XCTestSuite *suite)
{
    NSCondition *condition = GSCondition();

    [condition lock];
    [GSRunningSuites addObject:[NSValue valueWithNonretainedObject:suite]];
    [condition unlock];
}

void _GSXCTWatchdogSuiteDidFinish(XCTestSuite *suite)
{
    NSCondition *condition = GSCondition();

    [condition lock];
    if ([[GSRunningSuites lastObject] nonretainedObjectValue] == suite) {
        [GSRunningSuites removeLastObject];
    }
    [condition unlock];
}
