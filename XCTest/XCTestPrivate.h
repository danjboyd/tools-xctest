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

// Records a failure that has no source location (e.g. a failed wait)
// against a test, or the running test if \a test is nil.
void _XCTRecordFailure(XCTestCase *test, NSString *description);

// Stops the test when continueAfterFailure is NO. Only on the main thread,
// where tests run; a failure on another thread is just recorded.
void _XCTInterruptIfNeeded(XCTestCase *test);

// Every XCTestCase subclass, sorted by name.
NSArray *_GSXCTestCaseSubclasses(void);

// "Name", "reason" -- the way Apple's XCTest describes a caught exception.
NSString *_GSXCTDescribeException(NSException *exception);

@interface XCTest (GSPrivate)
- (void) _gsSetTestRun: (XCTestRun *)run;
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
@end

@interface XCTestObservationCenter (GSPrivate)
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
// Records the test as started and failed with \a cause, without running it.
- (void) _gsFailWithoutRunning: (GSXCTestIssue *)cause;
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
