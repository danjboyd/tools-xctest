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

#import <Foundation/Foundation.h>

@class XCTest;
@class XCTIssue;

/*!
 * The results of running a test: timing, failures and skips. Starting and
 * stopping a run notifies XCTestObservationCenter's observers.
 */
@interface XCTestRun : NSObject {
    XCTest *_test;
    NSDate *_startDate;
    NSDate *_stopDate;
    NSUInteger _failureCount;
    NSUInteger _unexpectedExceptionCount;
    BOOL _hasBeenSkipped;
}

+ (id) testRunWithTest: (XCTest *)test;
- (id) initWithTest: (XCTest *)test;

/*! The test this run belongs to. Not retained (the test owns its run);
 * nil once the test has been deallocated. */
@property (readonly, assign) XCTest *test;

- (void) start;
- (void) stop;

@property (readonly, copy) NSDate *startDate;
@property (readonly, copy) NSDate *stopDate;

/*! Wall-clock time from start to stop. */
@property (readonly) NSTimeInterval totalDuration;
/*! Time spent in test cases (for a suite, the sum over its tests). */
@property (readonly) NSTimeInterval testDuration;

@property (readonly) NSUInteger testCaseCount;
/*! Test cases that ran (including skipped ones). */
@property (readonly) NSUInteger executionCount;
@property (readonly) NSUInteger skipCount;
/*! Failed assertions and other expected failures. */
@property (readonly) NSUInteger failureCount;
/*! Failures from uncaught exceptions. */
@property (readonly) NSUInteger unexpectedExceptionCount;
@property (readonly) NSUInteger totalFailureCount;

@property (readonly) BOOL hasSucceeded;
@property (readonly) BOOL hasBeenSkipped;

/*! Counts \a issue (as an unexpected exception if it's an uncaught
 * exception, otherwise as a failure) and tells observers about it. */
- (void) recordIssue: (XCTIssue *)issue;

/*! Records an assertion failure (\a expected YES) or an uncaught
 * exception as an issue. Superseded by -recordIssue:. */
- (void) recordFailureWithDescription: (NSString *)description
                               inFile: (NSString *)filePath
                               atLine: (NSUInteger)lineNumber
                             expected: (BOOL)expected;

@end

/*! The run of a single XCTestCase. */
@interface XCTestCaseRun : XCTestRun
@end

/*! The run of an XCTestSuite; its counts include those of its tests. */
@interface XCTestSuiteRun : XCTestRun {
    NSMutableArray *_testRuns;
    NSMutableArray *_ownIssues;
}

@property (readonly, copy) NSArray *testRuns;

- (void) addTestRun: (XCTestRun *)testRun;

@end
