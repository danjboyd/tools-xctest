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

// Internal interfaces shared between the XCTest library's source files.
// Not installed.

#import <XCTest/XCAbstractTest.h>
#import <XCTest/XCTestCase.h>
#import <XCTest/XCTestSuite.h>
#import <XCTest/XCTestRun.h>
#import <XCTest/XCTestObservationCenter.h>
#import <XCTest/XCTestExpectation.h>
#import <XCTest/XCTWaiter.h>
#import <XCTest/GSXCTestReporting.h>
#import <XCTest/GSXCTestRunner.h>
#import <XCTest/XCTIssue.h>
#import <XCTest/XCTActivity.h>

@class XCTIssue;
@class XCTSourceCodeLocation;

// An issue at \a filePath:\a lineNumber (no location if filePath is nil).
XCTIssue *_GSXCTMakeIssue(XCTIssueType type, NSString *description,
                          NSString *filePath, NSUInteger lineNumber, NSError *error);
// An issue's file path as recorded (e.g. __FILE__, not made absolute), or nil.
NSString *_GSXCTIssueFilePath(XCTIssue *issue);
NSUInteger _GSXCTIssueLineNumber(XCTIssue *issue);
// YES for issues counted as unexpected (uncaught exceptions), as Apple's
// XCTestRun counts them.
BOOL _GSXCTIssueIsUnexpected(XCTIssue *issue);

@interface XCTSourceCodeLocation (GSPrivate)
- (NSString *) _gsFilePath;
@end

// Records a failure that has no source location (e.g. a failed wait)
// against a test, or the running test if \a test is nil.
void _XCTRecordFailure(XCTestCase *test, NSString *description);

// Stops the test when continueAfterFailure is NO. Only on the main thread,
// where tests run; a failure on another thread is just recorded.
void _XCTInterruptIfNeeded(XCTestCase *test);

// Per-test time limits (GSXCTestWatchdog.m). An allowance of 0 uses the
// default (600 seconds) or, for the maximum, means none.
void _GSXCTSetTimeouts(BOOL enabled, NSTimeInterval defaultAllowance, NSTimeInterval maximumAllowance);
NSTimeInterval _GSXCTDefaultExecutionTimeAllowance(void);
// Called around each test and suite as it runs, on the thread running it.
void _GSXCTWatchdogTestWillStart(XCTestCase *test);
void _GSXCTWatchdogTestDidFinish(XCTestCase *test);
void _GSXCTWatchdogAllowanceDidChange(void);
void _GSXCTWatchdogSuiteWillStart(XCTestSuite *suite);
void _GSXCTWatchdogSuiteDidFinish(XCTestSuite *suite);

// A running XCTContext activity.
@interface GSXCTActivity : NSObject <XCTActivity> {
    NSString *_name;
    NSArray *_path;
    NSDate *_startDate;
    XCTestCase *_testCase;
}
- (id) initWithName: (NSString *)name parent: (GSXCTActivity *)parent testCase: (XCTestCase *)testCase;
// Its name, after those of the activities around it.
- (NSArray *) path;
- (NSDate *) startDate;
// The test it ran in (not retained), or nil.
- (XCTestCase *) testCase;
@end

// The path of the innermost activity running on this thread, or nil.
NSArray *_GSXCTCurrentActivityPath(void);

// Every XCTestCase subclass, sorted by name.
NSArray *_GSXCTestCaseSubclasses(void);

@class _XCTSkipFailureException;
// The location and description carried by a skip.
GSXCTestIssue *_GSXCTIssueForSkip(_XCTSkipFailureException *skip);

// "Name", "reason" -- the way Apple's XCTest describes a caught exception.
NSString *_GSXCTDescribeException(NSException *exception);

@interface XCTest (GSPrivate)
- (void) _gsSetTestRun: (XCTestRun *)run;
@end

@interface XCTestSuite (GSPrivate)
// Records every test case in the suite (recursively) as failed with
// \a cause, or as skipped, without running them.
- (void) _gsFailWithoutRunning: (GSXCTestIssue *)cause;
- (void) _gsSkipWithoutRunning: (GSXCTestIssue *)skip;
@end

@interface XCTestRun (GSPrivate)
// Counts the issue and tells observers about it.
- (void) _gsRecordIssue: (GSXCTestIssue *)issue;
@end

@interface XCTestCaseRun (GSPrivate)
// Marks the test skipped (once) and tells observers.
- (void) _gsRecordSkip: (GSXCTestIssue *)skip;
@end

@interface XCTestSuiteRun (GSPrivate)
// Failures recorded on the suite itself, e.g. in a class's +setUp.
- (NSArray *) _gsOwnIssues;
@end

/*!
 * The suite of one test class's tests. Running it calls the class's
 * +setUp and +tearDown around the tests; if +setUp fails, each test is
 * recorded as failed without running.
 */
@interface GSXCTestCaseSuite : XCTestSuite {
    Class _testCaseClass;
    NSString *_classContext;
}
+ (GSXCTestCaseSuite *) suiteForTestCaseClass: (Class)testCaseClass;
@property (readonly) Class testCaseClass;
// The class suite whose tests are running, or nil.
+ (GSXCTestCaseSuite *) _gsCurrentClassSuite;
// How every class suite repeats its tests.
+ (void) _gsSetRepetitionMode: (GSXCTestRepetitionMode)mode iterations: (NSUInteger)iterations;
// Records a failure from +setUp/+tearDown.
- (void) _gsRecordClassFailure: (NSString *)description
                        inFile: (NSString *)filePath
                        atLine: (NSUInteger)lineNumber
                      expected: (BOOL)expected;
@end

// Extra events, beyond XCTestObservation, for the reporters.
@protocol GSXCTestObservationPrivate <NSObject>
@optional
- (void) _gsTestCase: (XCTestCase *)testCase didRecordIssue: (GSXCTestIssue *)issue;
- (void) _gsTestSuite: (XCTestSuite *)testSuite didRecordIssue: (GSXCTestIssue *)issue;
- (void) _gsTestCase: (XCTestCase *)testCase didSkipWithIssue: (GSXCTestIssue *)issue;
// A failure absorbed by XCTExpectFailure; its context is the reason.
- (void) _gsTestCase: (XCTestCase *)testCase didRecordExpectedFailure: (GSXCTestIssue *)issue;
- (void) _gsTestCase: (XCTestCase *)testCase didMeasure: (GSXCTMeasurement *)measurement;
- (void) _gsTestCase: (XCTestCase *)testCase activityDidStart: (GSXCTActivity *)activity;
// A failure recorded after the test's run stopped (e.g. from a callback).
- (void) _gsTestCase: (XCTestCase *)testCase didRecordIssueAfterFinishing: (GSXCTestIssue *)issue;
// A failed attempt that will be retried, and so no longer counts.
- (void) _gsTestCaseAttemptWasDiscarded: (XCTestCase *)testCase;
@end

@interface GSXCTestRunner (GSTerminationPrivate)
// Ends the process early (a test ran out of time): tells observers the
// bundle finished, then calls the termination handler or exits.
- (void) _gsTerminateWithExitCode: (int)exitCode;
@end

@interface GSXCTestRunner (GSPerformancePrivate)
// The baseline for "Class/testMethod" ({average, maxPercentRegression}), or nil.
- (NSDictionary *) _gsPerformanceBaselineForTest: (NSString *)identifier;
// Remembers a measured average, written out with -update-performance-baselines.
- (void) _gsRecordPerformanceAverage: (double)average forTest: (NSString *)identifier;
@end

@interface XCTestObservationCenter (GSPrivate)
// Adds an observer ahead of all others, so it sees each event first.
- (void) _gsAddTestObserverFirst: (id<XCTestObservation>)testObserver;
// Calls \a block with each observer, in the order they were added.
- (void) _gsNotifyObservers: (void (^)(id observer))block;
@end

@interface XCTestCase (GSXCTestRunnerPrivate)
// The test case currently being run, or nil.
+ (XCTestCase *) _gsCurrentTestCase;
+ (void) _gsSetCurrentTestCase: (XCTestCase *)testCase;
- (void (^)(void)) _gsPopTeardownBlock;
// The test method's name, e.g. "testFoo".
- (NSString *) _gsMethodName;
// When tests repeat: this run's iteration (from 1) and the maximum; 0 otherwise.
- (NSUInteger) _gsIteration;
- (NSUInteger) _gsIterationCount;
- (void) _gsSetIteration: (NSUInteger)iteration of: (NSUInteger)iterationCount;
// The reporters' result for this test, kept so failures recorded after the
// test finished can still be reported against it.
- (GSXCTestCaseResult *) _gsReportResult;
- (void) _gsSetReportResult: (GSXCTestCaseResult *)result;
// Records the test as started and failed with \a cause, without running it.
- (void) _gsFailWithoutRunning: (GSXCTestIssue *)cause;
// Records the test as started and skipped, without running it.
- (void) _gsSkipWithoutRunning: (GSXCTestIssue *)skip;
@end

@interface XCTestCase (GSExpectedFailures)
// Active XCTExpectFailure scopes, innermost last.
- (NSMutableArray *) _gsExpectedFailureScopes;
// If an active scope expects \a failure, reports it as expected (setting
// its context to the reason) and returns YES.
- (BOOL) _gsAbsorbExpectedFailure: (GSXCTestIssue *)failure;
- (void) _gsRecordUnmatchedExpectedFailure: (NSString *)reason;
// At the end of a test: fails for strict scopes that absorbed nothing.
- (void) _gsFinishExpectedFailures;
@end

@interface XCTestCase (GSAsynchronousTestingPrivate)
// Fails the test for each expectation it created but never waited on.
- (void) _gsRecordUnwaitedExpectations;
// Stops observers and releases the test's expectations.
- (void) _gsInvalidateExpectations;
@end

@interface XCTWaiter (GSPrivate)
// The timeout of the most recent wait.
- (NSTimeInterval) _gsTimeout;
@end

@interface XCTestExpectation (GSPrivate)
// The test that created the expectation (retained); over-fulfillment is
// blamed on it rather than on whichever test is running.
- (void) _gsSetOwner: (XCTestCase *)owner;
- (BOOL) _gsIsFulfilled;
// Increases each time any expectation becomes fulfilled; 0 if unfulfilled.
- (NSUInteger) _gsFulfillmentToken;
- (BOOL) _gsHasBeenWaitedOn;
- (void) _gsSetHasBeenWaitedOn: (BOOL)waited;
// Called repeatedly while a waiter waits, e.g. to re-evaluate predicates.
- (void) _gsPoll;
// Stops observing and drops handlers.
- (void) _gsInvalidate;
@end
