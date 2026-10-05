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

// Test results and the reporters that print them. Internal to the XCTest
// library; not installed.

#import <Foundation/Foundation.h>

typedef enum {
    GSXCTestStatusPassed,
    GSXCTestStatusFailed,
    GSXCTestStatusSkipped,
} GSXCTestStatus;

@class XCTIssue;

/*! A recorded failure, or the location and reason of a skip. */
@interface GSXCTestIssue : NSObject {
    NSString *_message;
    NSString *_filePath;
    NSUInteger _lineNumber;
    BOOL _unexpected;
    NSString *_context;
    XCTIssue *_xctIssue;
    NSArray *_activityPath;
}
+ (GSXCTestIssue *) issueWithMessage: (NSString *)message
                            filePath: (NSString *)filePath
                          lineNumber: (NSUInteger)lineNumber
                          unexpected: (BOOL)unexpected;
/*! A failure recorded as \a issue. */
+ (GSXCTestIssue *) issueWithXCTIssue: (XCTIssue *)issue;
/*! The XCTIssue the failure was recorded as; for failures that weren't
 * (e.g. in +setUp), one made from the other properties. */
@property (retain) XCTIssue *xctIssue;
@property (copy) NSString *message;
/*! nil when the issue has no source location. */
@property (copy) NSString *filePath;
@property NSUInteger lineNumber;
/*! YES for uncaught exceptions rather than failed assertions. */
@property BOOL unexpected;
/*! For class-level issues, "+setUp" or "+tearDown". */
@property (copy) NSString *context;
/*! The XCTContext activities the issue was recorded in, outermost first
 * (those running on the recording thread when it was created); or nil. */
@property (copy) NSArray *activityPath;
/*! The message, after the activity path if there is one:
 * "Log in > Enter password: message". */
- (NSString *) displayMessage;
@end

/*! One performance measurement: the values of each run of the block. */
@interface GSXCTMeasurement : NSObject {
    NSString *_metricIdentifier;
    NSString *_displayName;
    NSString *_unitSymbol;
    int _polarity;
    NSArray *_values;
    NSNumber *_baselineAverage;
    double _maxPercentRegression;
}
@property (copy) NSString *metricIdentifier;
/*! "Time", "Clock Monotonic Time", ... */
@property (copy) NSString *displayName;
/*! "seconds", "s", "kB", ... */
@property (copy) NSString *unitSymbol;
/*! An XCTPerformanceMeasurementPolarity. */
@property int polarity;
@property (copy) NSArray *values;
/*! nil when the test has no baseline. */
@property (retain) NSNumber *baselineAverage;
@property double maxPercentRegression;
- (double) average;
/*! Sample standard deviation as a percentage of the average. */
- (double) relativeStandardDeviation;
/*! "[0.001000, 0.001100, ...]" */
- (NSString *) valuesDescription;
/*! "[Time, seconds]" */
- (NSString *) metricDescription;
/*! "prefers smaller", as Apple prints it. */
- (NSString *) polarityDescription;
@end

@class XCTAttachment;

/*! An attachment added to a test, and where it was saved. */
@interface GSXCTAttachmentRecord : NSObject {
    XCTAttachment *_attachment;
    NSArray *_activityPath;
    NSString *_savedPath;
}
- (id) initWithAttachment: (XCTAttachment *)attachment activityPath: (NSArray *)activityPath;
@property (readonly) XCTAttachment *attachment;
/*! The XCTContext activity it was added in, outermost first; or nil. */
@property (readonly) NSArray *activityPath;
/*! The absolute path of the saved file; nil if it wasn't saved. */
@property (copy) NSString *savedPath;
/*! The attachment's name, or a default. */
- (NSString *) displayName;
@end

@interface GSXCTestCaseResult : NSObject {
    NSString *_className;
    NSString *_methodName;
    GSXCTestStatus _status;
    NSMutableArray *_failures;
    NSMutableArray *_expectedFailures;
    NSMutableArray *_measurements;
    NSMutableArray *_attachments;
    GSXCTestIssue *_skip;
    NSDate *_startDate;
    NSTimeInterval _duration;
    NSUInteger _iteration;
    NSUInteger _iterationCount;
}
- (id) initWithClassName: (NSString *)className methodName: (NSString *)methodName;
/*! When tests repeat: this run's iteration (from 1) and the maximum; else 0. */
@property NSUInteger iteration;
@property NSUInteger iterationCount;
/*! The method name, plus " (iteration N)" when tests repeat. */
- (NSString *) displayName;
@property (readonly, copy) NSString *className;
@property (readonly, copy) NSString *methodName;
@property GSXCTestStatus status;
@property (readonly) NSMutableArray *failures;
/*! Failures absorbed by XCTExpectFailure; each issue's context is the reason. */
@property (readonly) NSMutableArray *expectedFailures;
@property (readonly) NSMutableArray *measurements;
/*! GSXCTAttachmentRecords, in the order they were added. */
@property (readonly) NSMutableArray *attachments;
@property (retain) GSXCTestIssue *skip;
@property (retain) NSDate *startDate;
@property NSTimeInterval duration;
@end

@interface GSXCTestSuiteResult : NSObject {
    NSString *_name;
    NSMutableArray *_testResults;
    NSMutableArray *_classFailures;
    NSDate *_startDate;
    NSTimeInterval _duration;
}
- (id) initWithName: (NSString *)name;
@property (readonly, copy) NSString *name;
@property (readonly) NSMutableArray *testResults;
/*! Failures in +setUp or +tearDown. */
@property (readonly) NSMutableArray *classFailures;
@property (retain) NSDate *startDate;
@property NSTimeInterval duration;
- (NSUInteger) countOfTestsWithStatus: (GSXCTestStatus)status;
/*! All failures, including class-level ones. */
- (NSUInteger) failureCount;
- (NSUInteger) unexpectedFailureCount;
/*! Sum of the test durations. */
- (NSTimeInterval) testDuration;
- (BOOL) hasFailed;
@end

@interface GSXCTestRunResult : NSObject {
    NSString *_name;
    NSString *_bundleName;
    BOOL _filtersActive;
    unsigned long long _executionOrderSeed;
    NSMutableArray *_suiteResults;
    NSDate *_startDate;
    NSTimeInterval _duration;
}
- (id) initWithName: (NSString *)name bundleName: (NSString *)bundleName;
/*! "All tests", or "Selected tests" when filters are used. */
@property (readonly, copy) NSString *name;
@property (readonly, copy) NSString *bundleName;
@property BOOL filtersActive;
/*! The seed of a random execution order; 0 for alphabetical. */
@property unsigned long long executionOrderSeed;
@property (readonly) NSMutableArray *suiteResults;
@property (retain) NSDate *startDate;
@property NSTimeInterval duration;
- (NSUInteger) countOfTestsWithStatus: (GSXCTestStatus)status;
- (NSUInteger) failureCount;
- (NSUInteger) unexpectedFailureCount;
- (NSTimeInterval) testDuration;
- (BOOL) hasFailed;
@end

/*!
 * Receives test events as they happen. Suites with no selected tests are
 * still reported, through -suiteHasNoSelectedTests:.
 */
@protocol GSXCTestReporter <NSObject>
- (void) runDidStart: (GSXCTestRunResult *)run;
- (void) suiteHasNoSelectedTests: (GSXCTestSuiteResult *)suite;
- (void) suiteDidStart: (GSXCTestSuiteResult *)suite;
- (void) testDidStart: (GSXCTestCaseResult *)test;
- (void) test: (GSXCTestCaseResult *)test didRecordFailure: (GSXCTestIssue *)failure;
/*! A failure recorded after the test finished, e.g. from a callback; the
 * test is now marked failed. May arrive on another thread. */
- (void) test: (GSXCTestCaseResult *)test didRecordFailureAfterFinishing: (GSXCTestIssue *)failure;
- (void) test: (GSXCTestCaseResult *)test didRecordExpectedFailure: (GSXCTestIssue *)failure;
- (void) test: (GSXCTestCaseResult *)test didMeasure: (GSXCTMeasurement *)measurement;
/*! An XCTContext activity started, \a time seconds after the test did.
 * \a activityPath is its name after those of the activities around it. */
- (void) test: (GSXCTestCaseResult *)test didStartActivity: (NSArray *)activityPath atTime: (NSTimeInterval)time;
- (void) suite: (GSXCTestSuiteResult *)suite didRecordClassFailure: (GSXCTestIssue *)failure;
/*! An attachment was saved, as the test finished (before testDidFinish:). */
- (void) test: (GSXCTestCaseResult *)test didSaveAttachment: (GSXCTAttachmentRecord *)attachment;
- (void) testDidFinish: (GSXCTestCaseResult *)test;
/*! A failed attempt that will be retried; it has been removed from its suite. */
- (void) testWillBeRetried: (GSXCTestCaseResult *)test;
- (void) suiteDidFinish: (GSXCTestSuiteResult *)suite;
- (void) runDidFinish: (GSXCTestRunResult *)run;
@end

/*! The original "XCTest: ..." log output. */
@interface GSXCTestClassicReporter : NSObject <GSXCTestReporter>
@end

/*! Output in the format of Apple's xctest, on stdout. */
@interface GSXCTestAppleReporter : NSObject <GSXCTestReporter>
@end

/*!
 * Writes a JUnit XML report when the run finishes. Each test class is a
 * <testsuite>; failures from uncaught exceptions are <error>s, others are
 * <failure>s. A failed +tearDown is reported as an extra "+tearDown" case.
 */
@interface GSXCTestJUnitReporter : NSObject <GSXCTestReporter> {
    NSString *_path;
    BOOL _wroteReport;
}
- (id) initWithPath: (NSString *)path;
/*! NO until the report has been written successfully. */
@property (readonly) BOOL wroteReport;
@end

/*! In a parallel worker: writes the run's results, as JSON, to a file for
 * the coordinator when the run finishes. */
@interface GSXCTestWorkerResultsReporter : NSObject <GSXCTestReporter> {
    NSString *_path;
}
- (id) initWithPath: (NSString *)path;
@end

/*! In a parallel worker: passes everything to a console reporter except
 * the run's opening and closing lines, which the coordinator prints. */
@interface GSXCTestWorkerConsoleReporter : NSObject {
    id<GSXCTestReporter> _reporter;
}
- (id) initWithReporter: (id<GSXCTestReporter>)reporter;
@end

@class XCTestSuite;

/*!
 * An XCTestObservation observer that turns test events into results and
 * reporter calls. topSuite is the suite the run starts with; each
 * GSXCTestCaseSuite inside it is reported as one class. Attachments are
 * saved under attachmentsDirectory as each test finishes, if it's set.
 */
@interface GSXCTestReportingObserver : NSObject {
    NSString *_attachmentsDirectory;
    NSArray *_reporters;
    GSXCTestRunResult *_run;
    XCTestSuite *_topSuite;
    GSXCTestSuiteResult *_currentSuite;
    // The scheduled test that is running (not retained) and its result.
    // Tests that it runs itself are not reported.
    id _currentTestCase;
    GSXCTestCaseResult *_currentTest;
}
- (id) initWithReporters: (NSArray *)reporters
                     run: (GSXCTestRunResult *)run
                topSuite: (XCTestSuite *)topSuite;
/*! An absolute path, or nil not to save attachments. */
@property (copy) NSString *attachmentsDirectory;
@end
