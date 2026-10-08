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
#import <XCTest/XCAbstractTest.h>

@class XCTestSuite;
@class XCTIssue;
@class XCTAttachment;

/*!
 * One test: an instance of a test class bound to one test method (its
 * invocation). xctest builds a test case for each method returned by
 * +testInvocations, groups them with +defaultTestSuite, and runs them.
 */
@interface XCTestCase : XCTest {
    BOOL _continueAfterFailure;
    NSMutableArray *_teardownBlocks;
    NSMutableArray *_expectations;
    NSInvocation *_invocation;
    NSMutableArray *_expectedFailureScopes;
    BOOL _gsRecordingUnmatched;
    id _gsPerformance;
    NSUInteger _gsIteration;
    NSUInteger _gsIterationCount;
    id _gsReportResult;
    NSTimeInterval _executionTimeAllowance;
}

+ (instancetype)testCaseWithInvocation:(NSInvocation *)invocation;
- (instancetype)initWithInvocation:(NSInvocation *)invocation;
+ (instancetype)testCaseWithSelector:(SEL)selector;
- (instancetype)initWithSelector:(SEL)selector;

/*! The test method to run. */
@property (retain) NSInvocation *invocation;

/*!
 * One invocation per test method: instance methods named test..., taking
 * no arguments, including inherited ones, sorted by name. Override to add
 * or remove tests.
 */
+ (NSArray *)testInvocations;

/*!
 * The tests to run for this class: by default a suite with a test case for
 * each of +testInvocations. Override to change it, e.g. return an empty
 * suite from an abstract base class so its tests only run in subclasses.
 */
+ (XCTestSuite *)defaultTestSuite;

/*!
 * Runs set up, the test method and teardown, recording any failures. Can
 * be overridden to wrap the whole test; call super.
 */
- (void)invokeTest;

/*!
 * Records an issue in the test: every failure (assertions, uncaught
 * exceptions, errors from -setUpWithError:, failed waits, performance
 * regressions) goes through here. Override it to observe, change or drop
 * issues; call super to record them. An issue matched by XCTExpectFailure
 * is reported as expected; any other fails the test and, with
 * continueAfterFailure NO, stops it (on the main thread).
 */
- (void)recordIssue:(XCTIssue *)issue;

/*!
 * Superseded by -recordIssue:. Records an assertion failure (\a expected
 * YES) or an uncaught exception as an issue. For compatibility, a subclass
 * that overrides this method still sees every issue here first; calling
 * super goes on to record it.
 */
- (void)recordFailureWithDescription:(NSString *)description
                               inFile:(NSString *)filePath
                               atLine:(NSUInteger)lineNumber
                             expected:(BOOL)expected;


/*!
 * Whether a test keeps running after an assertion fails. Defaults to YES.
 * When NO, the first failure stops the current test; teardown still runs.
 */
@property BOOL continueAfterFailure;

/**
 * GNUstep extension: the number of failures (assertion failures and
 * unexpected exceptions) in the test's latest run.
 */
@property (readonly) NSUInteger failureCount;

/*!
 * How long the test may run, including set up and teardown, when xctest
 * runs with time limits (-test-timeouts-enabled YES, or one of the
 * execution time allowance options). Defaults to
 * -default-test-execution-time-allowance (600 seconds); a test can change
 * it, e.g. in -setUp, and -maximum-test-execution-time-allowance caps it.
 * Unlike Apple's XCTest, it isn't rounded up to whole minutes. A test that
 * runs out of time fails, the run's reports are written, and xctest exits
 * without running the remaining tests.
 */
@property NSTimeInterval executionTimeAllowance;

/*!
 * Called once before the first test of the class runs, and once after the
 * last one finishes.
 */
+ (void)setUp;
+ (void)tearDown;

/*
 * The instance methods -setUpWithError:, -setUp, -tearDown and
 * -tearDownWithError: (declared by XCTest) are called around each test
 * method by -invokeTest, in the order setUpWithError:, setUp, the test,
 * teardown blocks (last added runs first), tearDown, tearDownWithError:.
 * Teardown always runs, even if set up or the test failed.
 */

/*!
 * Registers a block to run after the current test method, before tearDown.
 */
- (void)addTeardownBlock:(void (^)(void))block;

/*!
 * Keeps \a attachment with the test's results (in the innermost
 * XCTContext activity running on this thread, if any). See XCTAttachment.
 */
- (void)addAttachment:(XCTAttachment *)attachment;

@end

typedef NSString *XCTPerformanceMetric;

/*! Wall-clock time, in seconds. The only metric currently supported. */
extern XCTPerformanceMetric const XCTPerformanceMetric_WallClockTime;

@interface XCTestCase (XCTPerformanceMeasurement)

/*! The metrics -measureBlock: records: wall-clock time. */
+ (NSArray *)defaultPerformanceMetrics;

/*!
 * Runs \a block 10 times and reports the average and relative standard
 * deviation of its wall-clock time. Call at most once per test. If a
 * baseline is set for the test (xctest -performance-baselines), an
 * average more than its maxPercentRegression (default 10%) worse fails
 * the test.
 */
- (void)measureBlock:(void (^)(void))block;

/*!
 * As -measureBlock:, but if \a automaticallyStartMeasuring is NO, each
 * run of the block must call -startMeasuring and -stopMeasuring once, and
 * only the time between them counts.
 */
- (void)measureMetrics:(NSArray *)metrics
automaticallyStartMeasuring:(BOOL)automaticallyStartMeasuring
               forBlock:(void (^)(void))block;

- (void)startMeasuring;
- (void)stopMeasuring;

@end
