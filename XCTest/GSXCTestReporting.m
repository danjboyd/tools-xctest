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
#import <XCTest/XCTestPrivate.h>

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
@synthesize expectedFailures = _expectedFailures;
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
        _expectedFailures = [[NSMutableArray alloc] init];
    }

    return self;
}

- (void) dealloc
{
    [_className release];
    [_methodName release];
    [_failures release];
    [_expectedFailures release];
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

// One line per failed test (and failed class +tearDown), with its first
// failure, in run order. Empty if nothing failed.
static NSArray *GSFailedTestLines(GSXCTestRunResult *run, NSString *(^testName)(NSString *className, NSString *name))
{
    NSMutableArray *lines = [NSMutableArray array];

    for (GSXCTestSuiteResult *suite in [run suiteResults]) {
        for (GSXCTestCaseResult *test in [suite testResults]) {
            if ([test status] == GSXCTestStatusFailed) {
                GSXCTestIssue *first = [[test failures] objectAtIndex:0];
                NSString *location = [first filePath]
                    ? [NSString stringWithFormat:@"%@:%lu: ", [first filePath], (unsigned long)[first lineNumber]]
                    : @"";
                [lines addObject:[NSString stringWithFormat:@"%@: %@%@",
                    testName([test className], [test methodName]), location, [first message]]];
            }
        }
        for (GSXCTestIssue *failure in [suite classFailures]) {
            if ([[failure context] isEqualToString:@"+tearDown"]) {
                [lines addObject:[NSString stringWithFormat:@"%@: %@",
                    testName([suite name], @"+tearDown"), [failure message]]];
                break;
            }
        }
    }

    return lines;
}

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

- (void) test: (GSXCTestCaseResult *)test didRecordExpectedFailure: (GSXCTestIssue *)failure
{
    if ([failure filePath] != nil) {
        NSLog(@"XCTest:     Expected failure (%@) at %@:%lu, %@", [failure context],
            [failure filePath], (unsigned long)[failure lineNumber], [failure message]);
    } else {
        NSLog(@"XCTest:     Expected failure (%@): %@", [failure context], [failure message]);
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

    NSArray *failedLines = GSFailedTestLines(run, ^NSString *(NSString *className, NSString *name) {
        return [NSString stringWithFormat:@"%@.%@", className, name];
    });
    if ([failedLines count] > 0) {
        NSLog(@"XCTest: Failed tests:");
        for (NSString *line in failedLines) {
            NSLog(@"XCTest:   %@", line);
        }
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

- (void) test: (GSXCTestCaseResult *)test didRecordExpectedFailure: (GSXCTestIssue *)failure
{
    GSPrintLine([NSString stringWithFormat:@"%@: %@ : Expected failure: %@: %@",
        GSAppleLocation(failure), GSAppleTestName(test), [failure context], [failure message]]);
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

    // Like xcodebuild's closing "Failing tests:" list.
    NSArray *failedLines = GSFailedTestLines(run, ^NSString *(NSString *className, NSString *name) {
        return [name hasPrefix:@"+"]
            ? [NSString stringWithFormat:@"+[%@ %@]", className, [name substringFromIndex:1]]
            : [NSString stringWithFormat:@"-[%@ %@]", className, name];
    });
    if ([failedLines count] > 0) {
        GSPrintLine(@"");
        GSPrintLine(@"Failing tests:");
        for (NSString *line in failedLines) {
            GSPrintLine([@"\t" stringByAppendingString:line]);
        }
    }
}

@end

#pragma mark - JUnit reporter

// Escapes text for XML attributes and content, dropping characters XML 1.0
// does not allow.
static NSString *GSXMLEscape(NSString *string)
{
    NSMutableString *escaped = [NSMutableString stringWithCapacity:[string length]];
    NSUInteger length = [string length];

    for (NSUInteger i = 0; i < length; i++) {
        unichar c = [string characterAtIndex:i];

        switch (c) {
            case '&': [escaped appendString:@"&amp;"]; break;
            case '<': [escaped appendString:@"&lt;"]; break;
            case '>': [escaped appendString:@"&gt;"]; break;
            case '"': [escaped appendString:@"&quot;"]; break;
            case '\'': [escaped appendString:@"&apos;"]; break;
            default:
                if (c >= 0x20 || c == '\t' || c == '\n' || c == '\r') {
                    [escaped appendFormat:@"%C", c];
                }
                break;
        }
    }

    return escaped;
}

static NSString *GSJUnitIssueLine(GSXCTestIssue *issue)
{
    if ([issue filePath] == nil) {
        return [issue message];
    }

    return [NSString stringWithFormat:@"%@:%lu: %@",
        [issue filePath], (unsigned long)[issue lineNumber], [issue message]];
}

static NSString *GSJUnitTimestamp(NSDate *date)
{
    NSCalendarDate *calendarDate = [NSCalendarDate dateWithTimeIntervalSinceReferenceDate:
        [date timeIntervalSinceReferenceDate]];

    return [calendarDate descriptionWithCalendarFormat:@"%Y-%m-%dT%H:%M:%S"];
}

// Appends a <failure> or <error> element for a list of failures.
static void GSAppendJUnitFailures(NSMutableString *xml, NSArray *failures)
{
    GSXCTestIssue *first = [failures objectAtIndex:0];
    BOOL unexpected = NO;
    NSMutableArray *lines = [NSMutableArray array];

    for (GSXCTestIssue *failure in failures) {
        if ([failure unexpected] && !unexpected) {
            unexpected = YES;
            first = failure;
        }
        [lines addObject:GSJUnitIssueLine(failure)];
    }

    [xml appendFormat:@"      <%@ message=\"%@\" type=\"%@\">%@</%@>\n",
        unexpected ? @"error" : @"failure",
        GSXMLEscape([first message]),
        unexpected ? @"UncaughtException" : @"XCTestFailure",
        GSXMLEscape([lines componentsJoinedByString:@"\n"]),
        unexpected ? @"error" : @"failure"];
}

static BOOL GSIssuesIncludeUnexpected(NSArray *issues)
{
    for (GSXCTestIssue *issue in issues) {
        if ([issue unexpected]) {
            return YES;
        }
    }

    return NO;
}

@implementation GSXCTestJUnitReporter

@synthesize wroteReport = _wroteReport;

- (id) initWithPath: (NSString *)path
{
    self = [super init];
    if (self) {
        _path = [path copy];
    }

    return self;
}

- (void) dealloc
{
    [_path release];
    [super dealloc];
}

- (void) runDidStart: (GSXCTestRunResult *)run {}
- (void) suiteHasNoSelectedTests: (GSXCTestSuiteResult *)suite {}
- (void) suiteDidStart: (GSXCTestSuiteResult *)suite {}
- (void) testDidStart: (GSXCTestCaseResult *)test {}
- (void) test: (GSXCTestCaseResult *)test didRecordFailure: (GSXCTestIssue *)failure {}
- (void) test: (GSXCTestCaseResult *)test didRecordExpectedFailure: (GSXCTestIssue *)failure {}
- (void) suite: (GSXCTestSuiteResult *)suite didRecordClassFailure: (GSXCTestIssue *)failure {}
- (void) testDidFinish: (GSXCTestCaseResult *)test {}
- (void) suiteDidFinish: (GSXCTestSuiteResult *)suite {}

- (void) runDidFinish: (GSXCTestRunResult *)run
{
    NSMutableString *suitesXML = [NSMutableString string];
    NSMutableString *xml = [NSMutableString string];
    NSUInteger totalTests = 0, totalFailures = 0, totalErrors = 0, totalSkipped = 0;
    NSError *error = nil;

    for (GSXCTestSuiteResult *suite in [run suiteResults]) {
        NSMutableString *casesXML = [NSMutableString string];
        NSMutableArray *tearDownFailures = [NSMutableArray array];
        NSUInteger tests = 0, failures = 0, errors = 0, skipped = 0;

        for (GSXCTestCaseResult *test in [suite testResults]) {
            tests++;
            [casesXML appendFormat:@"    <testcase classname=\"%@\" name=\"%@\" time=\"%.3f\"",
                GSXMLEscape([test className]), GSXMLEscape([test methodName]), [test duration]];

            if ([test status] == GSXCTestStatusFailed) {
                if (GSIssuesIncludeUnexpected([test failures])) {
                    errors++;
                } else {
                    failures++;
                }
                [casesXML appendString:@">\n"];
                GSAppendJUnitFailures(casesXML, [test failures]);
                [casesXML appendString:@"    </testcase>\n"];
            } else if ([test status] == GSXCTestStatusSkipped) {
                skipped++;
                [casesXML appendFormat:@">\n      <skipped message=\"%@\"/>\n    </testcase>\n",
                    GSXMLEscape(GSJUnitIssueLine([test skip]))];
            } else if ([[test expectedFailures] count] > 0) {
                [casesXML appendString:@">\n"];
            } else {
                [casesXML appendString:@"/>\n"];
            }

            // Expected failures don't fail the test; list them as output.
            if ([[test expectedFailures] count] > 0) {
                NSMutableArray *lines = [NSMutableArray array];
                for (GSXCTestIssue *expected in [test expectedFailures]) {
                    [lines addObject:[NSString stringWithFormat:@"Expected failure (%@): %@",
                        [expected context], GSJUnitIssueLine(expected)]];
                }
                if ([test status] == GSXCTestStatusPassed) {
                    [casesXML appendFormat:@"      <system-out>%@</system-out>\n    </testcase>\n",
                        GSXMLEscape([lines componentsJoinedByString:@"\n"])];
                } else {
                    // Insert before the closing tag written above.
                    NSRange close = [casesXML rangeOfString:@"    </testcase>\n" options:NSBackwardsSearch];
                    [casesXML insertString:[NSString stringWithFormat:@"      <system-out>%@</system-out>\n",
                                               GSXMLEscape([lines componentsJoinedByString:@"\n"])]
                                   atIndex:close.location];
                }
            }
        }

        for (GSXCTestIssue *failure in [suite classFailures]) {
            if ([[failure context] isEqualToString:@"+tearDown"]) {
                [tearDownFailures addObject:failure];
            }
        }
        if ([tearDownFailures count] > 0) {
            tests++;
            if (GSIssuesIncludeUnexpected(tearDownFailures)) {
                errors++;
            } else {
                failures++;
            }
            [casesXML appendFormat:@"    <testcase classname=\"%@\" name=\"+tearDown\" time=\"0.000\">\n",
                GSXMLEscape([suite name])];
            GSAppendJUnitFailures(casesXML, tearDownFailures);
            [casesXML appendString:@"    </testcase>\n"];
        }

        [suitesXML appendFormat:@"  <testsuite name=\"%@\" tests=\"%lu\" failures=\"%lu\" errors=\"%lu\" skipped=\"%lu\" time=\"%.3f\" timestamp=\"%@\">\n%@  </testsuite>\n",
            GSXMLEscape([suite name]), (unsigned long)tests, (unsigned long)failures,
            (unsigned long)errors, (unsigned long)skipped, [suite duration],
            GSJUnitTimestamp([suite startDate]), casesXML];

        totalTests += tests;
        totalFailures += failures;
        totalErrors += errors;
        totalSkipped += skipped;
    }

    [xml appendString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"];
    [xml appendFormat:@"<testsuites name=\"%@\" tests=\"%lu\" failures=\"%lu\" errors=\"%lu\" skipped=\"%lu\" time=\"%.3f\">\n%@</testsuites>\n",
        GSXMLEscape([run bundleName]), (unsigned long)totalTests, (unsigned long)totalFailures,
        (unsigned long)totalErrors, (unsigned long)totalSkipped, [run duration], suitesXML];

    _wroteReport = [xml writeToFile:_path atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (!_wroteReport) {
        NSLog(@"XCTest: Could not write JUnit report to '%@': %@", _path,
            error ? [error localizedDescription] : @"unknown error");
    }
}

@end

#pragma mark - Observation bridge

// Sends a reporter message to every reporter.
#define GS_REPORT(call) \
    for (id<GSXCTestReporter> reporter in _reporters) { [reporter call]; }

@interface GSXCTestReportingObserver () <XCTestObservation, GSXCTestObservationPrivate>
@end

@implementation GSXCTestReportingObserver

- (id) initWithReporters: (NSArray *)reporters
                     run: (GSXCTestRunResult *)run
                topSuite: (XCTestSuite *)topSuite
{
    self = [super init];
    if (self) {
        _reporters = [reporters copy];
        _run = [run retain];
        _topSuite = [topSuite retain];
    }

    return self;
}

- (void) dealloc
{
    [_reporters release];
    [_run release];
    [_topSuite release];
    [_currentSuite release];
    [_currentTest release];
    [super dealloc];
}

- (void) testSuiteWillStart: (XCTestSuite *)testSuite
{
    GSXCTestSuiteResult *suite = nil;

    if (testSuite == _topSuite) {
        [_run setStartDate:[[testSuite testRun] startDate]];
        GS_REPORT(runDidStart:_run)
        return;
    }

    if (![testSuite isKindOfClass:[GSXCTestCaseSuite class]]) {
        return;
    }

    suite = [[[GSXCTestSuiteResult alloc] initWithName:[testSuite name]] autorelease];
    if ([testSuite testCaseCount] == 0) {
        GS_REPORT(suiteHasNoSelectedTests:suite)
        return;
    }

    [suite setStartDate:[[testSuite testRun] startDate]];
    [[_run suiteResults] addObject:suite];
    [_currentSuite release];
    _currentSuite = [suite retain];
    GS_REPORT(suiteDidStart:suite)
}

- (void) testSuiteDidFinish: (XCTestSuite *)testSuite
{
    if (testSuite == _topSuite) {
        [_run setDuration:[[testSuite testRun] totalDuration]];
        GS_REPORT(runDidFinish:_run)
        return;
    }

    if (_currentSuite != nil && [testSuite isKindOfClass:[GSXCTestCaseSuite class]]
        && [[testSuite name] isEqualToString:[_currentSuite name]]) {
        [_currentSuite setDuration:[[testSuite testRun] totalDuration]];
        GS_REPORT(suiteDidFinish:_currentSuite)
        [_currentSuite release];
        _currentSuite = nil;
    }
}

- (void) testCaseWillStart: (XCTestCase *)testCase
{
    if (_currentTestCase != nil) {
        return;
    }

    GSXCTestCaseResult *test = [[[GSXCTestCaseResult alloc]
        initWithClassName:NSStringFromClass([testCase class])
               methodName:[testCase _gsMethodName]] autorelease];

    [test setStartDate:[[testCase testRun] startDate]];
    [[_currentSuite testResults] addObject:test];
    _currentTestCase = testCase;
    _currentTest = [test retain];
    GS_REPORT(testDidStart:test)
}

- (void) _gsTestCase: (XCTestCase *)testCase didRecordIssue: (GSXCTestIssue *)issue
{
    // Ignores tests run by the running test, and failures from other
    // threads that arrive after their test has finished.
    if (testCase != _currentTestCase || _currentTest == nil) {
        return;
    }

    [[_currentTest failures] addObject:issue];
    GS_REPORT(test:_currentTest didRecordFailure:issue)
}

- (void) _gsTestCase: (XCTestCase *)testCase didRecordExpectedFailure: (GSXCTestIssue *)issue
{
    if (testCase != _currentTestCase || _currentTest == nil) {
        return;
    }

    [[_currentTest expectedFailures] addObject:issue];
    GS_REPORT(test:_currentTest didRecordExpectedFailure:issue)
}

- (void) _gsTestSuite: (XCTestSuite *)testSuite didRecordIssue: (GSXCTestIssue *)issue
{
    if (_currentSuite == nil || ![[testSuite name] isEqualToString:[_currentSuite name]]) {
        return;
    }

    [[_currentSuite classFailures] addObject:issue];
    GS_REPORT(suite:_currentSuite didRecordClassFailure:issue)
}

- (void) _gsTestCase: (XCTestCase *)testCase didSkipWithIssue: (GSXCTestIssue *)issue
{
    if (testCase == _currentTestCase && _currentTest != nil && [_currentTest skip] == nil) {
        [_currentTest setSkip:issue];
    }
}

- (void) testCaseDidFinish: (XCTestCase *)testCase
{
    XCTestRun *run = [testCase testRun];
    GSXCTestCaseResult *test = nil;

    if (testCase != _currentTestCase || _currentTest == nil) {
        return;
    }
    test = [_currentTest autorelease];
    _currentTestCase = nil;
    _currentTest = nil;

    // A failure outranks a skip, as in Apple's XCTest.
    if ([run totalFailureCount] > 0) {
        [test setStatus:GSXCTestStatusFailed];
    } else if ([run hasBeenSkipped]) {
        [test setStatus:GSXCTestStatusSkipped];
    } else {
        [test setStatus:GSXCTestStatusPassed];
    }
    [test setDuration:[run testDuration]];

    GS_REPORT(testDidFinish:test)
}

@end
