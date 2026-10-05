//
//  GSXCTestRunner.h
//  Eggplant
//
//  Created by Adam Fox on 9/17/18.
//  Copyright © 2018 TestPlant, Inc. All rights reserved.
//
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

typedef enum {
    /*! "XCTest: ..." log lines (the default). */
    GSXCTestOutputFormatClassic,
    /*! The format of Apple's xctest, with per-test timings, on stdout. */
    GSXCTestOutputFormatApple,
} GSXCTestOutputFormat;

typedef enum {
    /*! Each test runs once. */
    GSXCTestRepetitionNone,
    /*! Each test runs testIterations times. */
    GSXCTestRepetitionFixed,
    /*! Each test repeats until it fails, at most testIterations times. */
    GSXCTestRepetitionUntilFailure,
    /*! A failing test is retried until it passes, at most testIterations
     * times; failed attempts before a pass don't count. */
    GSXCTestRepetitionRetryOnFailure,
} GSXCTestRepetitionMode;

@interface GSXCTestRunner : NSObject {
    NSLock *runLock;
    NSBundle *testBundle;
    id principalObject;
    NSString *performanceBaselinesPath;
    BOOL updatePerformanceBaselines;
    NSMutableDictionary *performanceBaselines;
    GSXCTestRepetitionMode repetitionMode;
    NSUInteger testIterations;
    GSXCTestOutputFormat outputFormat;
    NSString *bundleName;
    NSString *junitReportPath;
    BOOL testTimeoutsEnabled;
    NSTimeInterval defaultExecutionTimeAllowance;
    NSTimeInterval maximumExecutionTimeAllowance;
    void (^terminationHandler)(int exitCode);
    NSString *attachmentsPath;
    BOOL randomizeExecutionOrder;
    unsigned long long executionOrderSeed;
    NSString *workerResultsPath;
}

@property GSXCTestOutputFormat outputFormat;

/*! The test bundle's file name, used to name its suite in reports. */
@property (copy) NSString *bundleName;

/*! If set, a JUnit XML report is written here after each run. A run that
 * cannot write its report counts as failed. */
@property (copy) NSString *junitReportPath;

/*!
 * The loaded test bundle. If set, observers get testBundleWillStart: and
 * testBundleDidFinish:, and the bundle's NSPrincipalClass (if any) is
 * instantiated before the first run so it can register observers.
 */
@property (retain) NSBundle *testBundle;

/*!
 * A JSON file of performance baselines: {"TestClass/testMethod":
 * {"average": seconds, "maxPercentRegression": percent}}. A measured test
 * fails if its average is worse than its baseline by more than
 * maxPercentRegression (default 10).
 */
@property (copy) NSString *performanceBaselinesPath;

/*! If YES, measured averages are written back to performanceBaselinesPath
 * after the run (keeping each entry's maxPercentRegression). */
@property BOOL updatePerformanceBaselines;

/*! How tests are repeated; see GSXCTestRepetitionMode. */
@property GSXCTestRepetitionMode repetitionMode;
/*! The number of runs (or maximum attempts) per test when repeating. */
@property NSUInteger testIterations;

/*!
 * If YES, test classes run in a random order, as do the tests within each
 * class (a class's tests still run together, between its +setUp and
 * +tearDown). The order comes from executionOrderSeed, so a run can be
 * repeated exactly; listing tests uses the same order.
 */
@property BOOL randomizeExecutionOrder;
/*! The seed for a random order; 0 (the default) picks one, which is
 * logged and then kept here. */
@property unsigned long long executionOrderSeed;

/*!
 * Where to save XCTAttachments, in <Class>/<test>/ folders. If not set
 * but junitReportPath is, next to the report: "results.xml" saves them in
 * "results-attachments". Attachments are kept for failed tests, and for
 * any test if their lifetime is XCTAttachmentLifetimeKeepAlways.
 */
@property (copy) NSString *attachmentsPath;

/*!
 * If YES, each test may run for at most its executionTimeAllowance
 * (including set up and teardown). A test that runs out of time fails;
 * the run's reports are finished and the process ends (see
 * terminationHandler) without running the remaining tests.
 */
@property BOOL testTimeoutsEnabled;
/*! The default executionTimeAllowance of each test, in seconds; 0 for the
 * default of 600. */
@property NSTimeInterval defaultExecutionTimeAllowance;
/*! A cap on executionTimeAllowance, in seconds; 0 for none. */
@property NSTimeInterval maximumExecutionTimeAllowance;

/*!
 * Called, on another thread, instead of exiting when a run has to end the
 * process early (a test ran out of time), after the reports are written.
 * It should not return; if it does, the process exits with exitCode.
 */
@property (copy) void (^terminationHandler)(int exitCode);

- (BOOL)runAll;
- (BOOL)runTestsNamed:(NSArray *)testNames; // nil for all tests
- (BOOL)runTestsForTargetName:(NSString *)targetName
          onlyTestIdentifiers:(NSArray *)onlyTestIdentifiers
          skipTestIdentifiers:(NSArray *)skipTestIdentifiers;

/*!
 * The tests that -runTestsForTargetName:... would run, as
 * TestTarget/TestClass/testMethod identifiers in run order, without running
 * them. Returns nil if a filter identifier is invalid.
 */
- (NSArray *)testIdentifiersForTargetName:(NSString *)targetName
                      onlyTestIdentifiers:(NSArray *)onlyTestIdentifiers
                      skipTestIdentifiers:(NSArray *)skipTestIdentifiers;

/*!
 * Set in a parallel run's worker processes: the console output leaves out
 * the run's opening and closing lines, no JUnit report is written, and the
 * results go to this file (JSON) for the coordinator.
 */
@property (copy) NSString *workerResultsPath;

- (void)waitForCompletion;

+ (GSXCTestRunner *)sharedRunner;

@end

@interface GSXCTestRunner (GSParallel)

/*!
 * Runs the selected tests in up to \a workerCount processes at once (0 for
 * one per CPU), one test class per process, by starting this program as a
 * worker for each class. Each class's output is printed as a block when it
 * finishes, then the merged results are reported (console summary, JUnit
 * report). A crashed worker fails its class's tests; the other classes
 * still run. The test bundle must be set; host applications aren't
 * supported, nor is updatePerformanceBaselines.
 */
- (BOOL)runTestsInParallelForTargetName:(NSString *)targetName
                    onlyTestIdentifiers:(NSArray *)onlyTestIdentifiers
                    skipTestIdentifiers:(NSArray *)skipTestIdentifiers
                            workerCount:(NSUInteger)workerCount;

@end
