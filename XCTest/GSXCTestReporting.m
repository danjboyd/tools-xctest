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

#import <XCTest/GSXCTestReporting.h>

#include <stdio.h>

@implementation GSXCTestIssue

@synthesize message = _message;
@synthesize filePath = _filePath;
@synthesize lineNumber = _lineNumber;
@synthesize unexpected = _unexpected;
@synthesize context = _context;

+ (GSXCTestIssue *) issueWithMessage: (NSString *)message
                            filePath: (NSString *)filePath
                          lineNumber: (NSUInteger)lineNumber
                          unexpected: (BOOL)unexpected
{
    GSXCTestIssue *issue = [[[self alloc] init] autorelease];

    [issue setMessage:message];
    [issue setFilePath:filePath];
    [issue setLineNumber:lineNumber];
    [issue setUnexpected:unexpected];
    return issue;
}

- (void) dealloc
{
    [_message release];
    [_filePath release];
    [_context release];
    [super dealloc];
}

@end

@implementation GSXCTestCaseResult

@synthesize className = _className;
@synthesize methodName = _methodName;
@synthesize status = _status;
@synthesize failures = _failures;
@synthesize skip = _skip;
@synthesize startDate = _startDate;
@synthesize duration = _duration;

- (id) initWithClassName: (NSString *)className methodName: (NSString *)methodName
{
    self = [super init];
    if (self) {
        _className = [className copy];
        _methodName = [methodName copy];
        _failures = [[NSMutableArray alloc] init];
    }

    return self;
}

- (void) dealloc
{
    [_className release];
    [_methodName release];
    [_failures release];
    [_skip release];
    [_startDate release];
    [super dealloc];
}

@end

@implementation GSXCTestSuiteResult

@synthesize name = _name;
@synthesize testResults = _testResults;
@synthesize classFailures = _classFailures;
@synthesize startDate = _startDate;
@synthesize duration = _duration;

- (id) initWithName: (NSString *)name
{
    self = [super init];
    if (self) {
        _name = [name copy];
        _testResults = [[NSMutableArray alloc] init];
        _classFailures = [[NSMutableArray alloc] init];
    }

    return self;
}

- (void) dealloc
{
    [_name release];
    [_testResults release];
    [_classFailures release];
    [_startDate release];
    [super dealloc];
}

- (NSUInteger) countOfTestsWithStatus: (GSXCTestStatus)status
{
    NSUInteger count = 0;

    for (GSXCTestCaseResult *test in _testResults) {
        if ([test status] == status) {
            count++;
        }
    }

    return count;
}

- (NSUInteger) failureCount
{
    NSUInteger count = [_classFailures count];

    for (GSXCTestCaseResult *test in _testResults) {
        count += [[test failures] count];
    }

    return count;
}

- (NSUInteger) unexpectedFailureCount
{
    NSUInteger count = 0;

    for (GSXCTestIssue *failure in _classFailures) {
        count += [failure unexpected] ? 1 : 0;
    }
    for (GSXCTestCaseResult *test in _testResults) {
        for (GSXCTestIssue *failure in [test failures]) {
            count += [failure unexpected] ? 1 : 0;
        }
    }

    return count;
}

- (NSTimeInterval) testDuration
{
    NSTimeInterval duration = 0;

    for (GSXCTestCaseResult *test in _testResults) {
        duration += [test duration];
    }

    return duration;
}

- (BOOL) hasFailed
{
    return [_classFailures count] > 0 || [self countOfTestsWithStatus:GSXCTestStatusFailed] > 0;
}

@end

@implementation GSXCTestRunResult

@synthesize name = _name;
@synthesize bundleName = _bundleName;
@synthesize filtersActive = _filtersActive;
@synthesize suiteResults = _suiteResults;
@synthesize startDate = _startDate;
@synthesize duration = _duration;

- (id) initWithName: (NSString *)name bundleName: (NSString *)bundleName
{
    self = [super init];
    if (self) {
        _name = [name copy];
        _bundleName = [bundleName copy];
        _suiteResults = [[NSMutableArray alloc] init];
    }

    return self;
}

- (void) dealloc
{
    [_name release];
    [_bundleName release];
    [_suiteResults release];
    [_startDate release];
    [super dealloc];
}

- (NSUInteger) countOfTestsWithStatus: (GSXCTestStatus)status
{
    NSUInteger count = 0;

    for (GSXCTestSuiteResult *suite in _suiteResults) {
        count += [suite countOfTestsWithStatus:status];
    }

    return count;
}

- (NSUInteger) failureCount
{
    NSUInteger count = 0;

    for (GSXCTestSuiteResult *suite in _suiteResults) {
        count += [suite failureCount];
    }

    return count;
}

- (NSUInteger) unexpectedFailureCount
{
    NSUInteger count = 0;

    for (GSXCTestSuiteResult *suite in _suiteResults) {
        count += [suite unexpectedFailureCount];
    }

    return count;
}

- (NSTimeInterval) testDuration
{
    NSTimeInterval duration = 0;

    for (GSXCTestSuiteResult *suite in _suiteResults) {
        duration += [suite testDuration];
    }

    return duration;
}

- (BOOL) hasFailed
{
    for (GSXCTestSuiteResult *suite in _suiteResults) {
        if ([suite hasFailed]) {
            return YES;
        }
    }

    return NO;
}

@end

#pragma mark - Classic reporter

static NSString *GSSkippedSummary(NSUInteger skipCount)
{
    if (skipCount == 0) {
        return @"";
    }

    return [NSString stringWithFormat:@" (%lu %@ skipped)",
        (unsigned long)skipCount, skipCount == 1 ? @"test" : @"tests"];
}

@implementation GSXCTestClassicReporter

- (void) runDidStart: (GSXCTestRunResult *)run
{
    NSLog(@"XCTest: Running Unit Tests");
}

- (void) suiteHasNoSelectedTests: (GSXCTestSuiteResult *)suite
{
    NSLog(@"XCTest:   %@ SKIPPED", [suite name]);
}

- (void) suiteDidStart: (GSXCTestSuiteResult *)suite
{
    NSLog(@"XCTest:   Running %@", [suite name]);
}

- (void) testDidStart: (GSXCTestCaseResult *)test
{
    NSLog(@"XCTest:     %@...", [test methodName]);
}

- (void) test: (GSXCTestCaseResult *)test didRecordFailure: (GSXCTestIssue *)failure
{
    if ([failure filePath] != nil) {
        NSLog(@"XCTest:     Assertion FAILED at %@:%lu, %@",
            [failure filePath], (unsigned long)[failure lineNumber], [failure message]);
    } else {
        NSLog(@"XCTest:     %@: %@", [test methodName], [failure message]);
    }
}

- (void) suite: (GSXCTestSuiteResult *)suite didRecordClassFailure: (GSXCTestIssue *)failure
{
    if ([failure filePath] != nil) {
        NSLog(@"XCTest:   %@ %@ assertion FAILED at %@:%lu, %@", [suite name], [failure context],
            [failure filePath], (unsigned long)[failure lineNumber], [failure message]);
    } else {
        NSLog(@"XCTest:   %@ %@ FAILED: %@", [suite name], [failure context], [failure message]);
    }
}

- (void) testDidFinish: (GSXCTestCaseResult *)test
{
    GSXCTestIssue *skip = [test skip];

    if ([test status] == GSXCTestStatusFailed) {
        NSLog(@"XCTest:     %@ FAILED", [test methodName]);
    } else if ([test status] == GSXCTestStatusSkipped) {
        NSLog(@"XCTest:     %@ SKIPPED at %@:%lu%@", [test methodName],
            [skip filePath], (unsigned long)[skip lineNumber],
            [[skip message] length] > 0 ? [@", " stringByAppendingString:[skip message]] : @"");
    }
}

- (void) suiteDidFinish: (GSXCTestSuiteResult *)suite
{
    NSUInteger failed = [suite countOfTestsWithStatus:GSXCTestStatusFailed];
    NSUInteger passed = [suite countOfTestsWithStatus:GSXCTestStatusPassed];
    NSString *skipped = @"";

    if ([suite countOfTestsWithStatus:GSXCTestStatusSkipped] > 0) {
        skipped = [NSString stringWithFormat:@", %lu skipped",
            (unsigned long)[suite countOfTestsWithStatus:GSXCTestStatusSkipped]];
    }

    if (failed > 0) {
        NSLog(@"XCTest:   %@: %lu/%lu tests FAILED%@", [suite name],
            (unsigned long)failed, (unsigned long)[[suite testResults] count], skipped);
    } else if ([suite hasFailed]) {
        NSLog(@"XCTest:   %@: %lu tests passed%@, +tearDown FAILED", [suite name], (unsigned long)passed, skipped);
    } else {
        NSLog(@"XCTest:   %@: %lu tests PASSED%@", [suite name], (unsigned long)passed, skipped);
    }
}

- (void) runDidFinish: (GSXCTestRunResult *)run
{
    NSUInteger failedSuites = 0;
    NSUInteger suiteCount = [[run suiteResults] count];
    NSString *skipped = GSSkippedSummary([run countOfTestsWithStatus:GSXCTestStatusSkipped]);

    for (GSXCTestSuiteResult *suite in [run suiteResults]) {
        failedSuites += [suite hasFailed] ? 1 : 0;
    }

    if (suiteCount == 0) {
        NSLog(@"XCTest: %@", [run filtersActive] ? @"No tests matched the provided filters." : @"No tests found.");
    } else if (failedSuites > 0) {
        NSLog(@"XCTest: %lu/%lu test cases FAILED%@", (unsigned long)failedSuites, (unsigned long)suiteCount, skipped);
    } else {
        NSLog(@"XCTest: %lu tests PASSED%@", (unsigned long)suiteCount, skipped);
    }
}

@end

#pragma mark - Apple-format reporter

static void GSPrintLine(NSString *line)
{
    fprintf(stdout, "%s\n", [line UTF8String]);
    fflush(stdout);
}

static NSString *GSAppleTimestamp(NSDate *date)
{
    NSCalendarDate *calendarDate = [NSCalendarDate dateWithTimeIntervalSinceReferenceDate:
        [date timeIntervalSinceReferenceDate]];

    return [calendarDate descriptionWithCalendarFormat:@"%Y-%m-%d %H:%M:%S.%F"];
}

static NSString *GSPlural(NSUInteger count, NSString *singular, NSString *plural)
{
    return [NSString stringWithFormat:@"%lu %@", (unsigned long)count, count == 1 ? singular : plural];
}

// "Executed 3 tests, with 1 test skipped and 2 failures (1 unexpected) in 0.105 (0.107) seconds"
static NSString *GSExecutedSummary(NSUInteger executed, NSUInteger skipped, NSUInteger failures,
                                   NSUInteger unexpected, NSTimeInterval testTime, NSTimeInterval wallTime)
{
    NSString *skippedPart = skipped > 0
        ? [NSString stringWithFormat:@"%@ skipped and ", GSPlural(skipped, @"test", @"tests")]
        : @"";

    return [NSString stringWithFormat:@"\t Executed %@, with %@%@ (%lu unexpected) in %.3f (%.3f) seconds",
        GSPlural(executed, @"test", @"tests"), skippedPart, GSPlural(failures, @"failure", @"failures"),
        (unsigned long)unexpected, testTime, wallTime];
}

static NSString *GSAppleTestName(GSXCTestCaseResult *test)
{
    return [NSString stringWithFormat:@"-[%@ %@]", [test className], [test methodName]];
}

static NSString *GSAppleLocation(GSXCTestIssue *issue)
{
    if ([issue filePath] == nil) {
        return @"<unknown>:0";
    }

    return [NSString stringWithFormat:@"%@:%lu", [issue filePath], (unsigned long)[issue lineNumber]];
}

@implementation GSXCTestAppleReporter

- (void) runDidStart: (GSXCTestRunResult *)run
{
    NSString *timestamp = GSAppleTimestamp([run startDate]);

    GSPrintLine([NSString stringWithFormat:@"Test Suite '%@' started at %@.", [run name], timestamp]);
    GSPrintLine([NSString stringWithFormat:@"Test Suite '%@' started at %@.", [run bundleName], timestamp]);
}

- (void) suiteHasNoSelectedTests: (GSXCTestSuiteResult *)suite
{
}

- (void) suiteDidStart: (GSXCTestSuiteResult *)suite
{
    GSPrintLine([NSString stringWithFormat:@"Test Suite '%@' started at %@.",
        [suite name], GSAppleTimestamp([suite startDate])]);
}

- (void) testDidStart: (GSXCTestCaseResult *)test
{
    GSPrintLine([NSString stringWithFormat:@"Test Case '%@' started.", GSAppleTestName(test)]);
}

- (void) test: (GSXCTestCaseResult *)test didRecordFailure: (GSXCTestIssue *)failure
{
    GSPrintLine([NSString stringWithFormat:@"%@: error: %@ : %@",
        GSAppleLocation(failure), GSAppleTestName(test), [failure message]]);
}

- (void) suite: (GSXCTestSuiteResult *)suite didRecordClassFailure: (GSXCTestIssue *)failure
{
    // "+setUp" -> "+[Class setUp]"
    NSString *context = [failure context];
    NSString *name = [NSString stringWithFormat:@"%@[%@ %@]",
        [context substringToIndex:1], [suite name], [context substringFromIndex:1]];

    GSPrintLine([NSString stringWithFormat:@"%@: error: %@ : %@",
        GSAppleLocation(failure), name, [failure message]]);
}

- (void) testDidFinish: (GSXCTestCaseResult *)test
{
    NSString *status = @"passed";

    if ([test status] == GSXCTestStatusFailed) {
        status = @"failed";
    } else if ([test status] == GSXCTestStatusSkipped) {
        GSXCTestIssue *skip = [test skip];

        status = @"skipped";
        GSPrintLine([NSString stringWithFormat:@"%@: %@ : Test skipped%@",
            GSAppleLocation(skip), GSAppleTestName(test),
            [[skip message] length] > 0 ? [@" - " stringByAppendingString:[skip message]] : @""]);
    }

    GSPrintLine([NSString stringWithFormat:@"Test Case '%@' %@ (%.3f seconds).",
        GSAppleTestName(test), status, [test duration]]);
}

- (void) suiteDidFinish: (GSXCTestSuiteResult *)suite
{
    GSPrintLine([NSString stringWithFormat:@"Test Suite '%@' %@ at %@.", [suite name],
        [suite hasFailed] ? @"failed" : @"passed",
        GSAppleTimestamp([[suite startDate] dateByAddingTimeInterval:[suite duration]])]);
    GSPrintLine(GSExecutedSummary([[suite testResults] count],
                                  [suite countOfTestsWithStatus:GSXCTestStatusSkipped],
                                  [suite failureCount], [suite unexpectedFailureCount],
                                  [suite testDuration], [suite duration]));
}

- (void) runDidFinish: (GSXCTestRunResult *)run
{
    NSUInteger executed = 0;
    NSString *status = [run hasFailed] ? @"failed" : @"passed";
    NSString *timestamp = GSAppleTimestamp([[run startDate] dateByAddingTimeInterval:[run duration]]);
    NSString *summary = nil;

    for (GSXCTestSuiteResult *suite in [run suiteResults]) {
        executed += [[suite testResults] count];
    }

    summary = GSExecutedSummary(executed, [run countOfTestsWithStatus:GSXCTestStatusSkipped],
                                [run failureCount], [run unexpectedFailureCount],
                                [run testDuration], [run duration]);

    GSPrintLine([NSString stringWithFormat:@"Test Suite '%@' %@ at %@.", [run bundleName], status, timestamp]);
    GSPrintLine(summary);
    GSPrintLine([NSString stringWithFormat:@"Test Suite '%@' %@ at %@.", [run name], status, timestamp]);
    GSPrintLine(summary);
}

@end
