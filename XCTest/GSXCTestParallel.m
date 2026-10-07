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

// Parallel runs. The coordinator (xctest -parallel-testing-enabled YES)
// works out which tests run, then hands one test class at a time to a
// pool of worker processes: xctest itself, given exactly that class's
// tests and -gs-parallel-worker-results <file>. A worker prints its class
// as usual (without the run's opening and closing lines) and writes its
// results to the file. The coordinator prints each worker's output as one
// block when the class finishes, then reports the merged results: the
// summary, the failed tests, the JUnit report and the exit status. A
// worker that crashes, or stops after a test runs out of time, only
// affects its own class.

#import <XCTest/XCTestPrivate.h>

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#pragma mark - Results as property lists

static NSDictionary *GSPlistFromIssue(GSXCTestIssue *issue)
{
    NSMutableDictionary *plist = [NSMutableDictionary dictionary];

    [plist setObject:([issue message] ? [issue message] : @"") forKey:@"message"];
    if ([issue filePath] != nil) {
        [plist setObject:[issue filePath] forKey:@"file"];
    }
    [plist setObject:[NSNumber numberWithUnsignedInteger:[issue lineNumber]] forKey:@"line"];
    [plist setObject:[NSNumber numberWithBool:[issue unexpected]] forKey:@"unexpected"];
    if ([issue context] != nil) {
        [plist setObject:[issue context] forKey:@"context"];
    }
    if ([issue activityPath] != nil) {
        [plist setObject:[issue activityPath] forKey:@"activityPath"];
    }
    return plist;
}

static GSXCTestIssue *GSIssueFromPlist(NSDictionary *plist)
{
    GSXCTestIssue *issue = [GSXCTestIssue issueWithMessage:[plist objectForKey:@"message"]
                                                  filePath:[plist objectForKey:@"file"]
                                                lineNumber:[[plist objectForKey:@"line"] unsignedIntegerValue]
                                                unexpected:[[plist objectForKey:@"unexpected"] boolValue]];

    [issue setContext:[plist objectForKey:@"context"]];
    [issue setActivityPath:[plist objectForKey:@"activityPath"]];
    return issue;
}

static NSArray *GSMap(NSArray *array, id (^transform)(id))
{
    NSMutableArray *mapped = [NSMutableArray arrayWithCapacity:[array count]];

    for (id item in array) {
        [mapped addObject:transform(item)];
    }
    return mapped;
}

static NSDictionary *GSPlistFromTest(GSXCTestCaseResult *test)
{
    NSMutableDictionary *plist = [NSMutableDictionary dictionary];

    [plist setObject:[test className] forKey:@"class"];
    [plist setObject:[test methodName] forKey:@"method"];
    [plist setObject:[NSNumber numberWithInt:[test status]] forKey:@"status"];
    [plist setObject:[NSNumber numberWithDouble:[[test startDate] timeIntervalSinceReferenceDate]] forKey:@"start"];
    [plist setObject:[NSNumber numberWithDouble:[test duration]] forKey:@"duration"];
    [plist setObject:[NSNumber numberWithUnsignedInteger:[test iteration]] forKey:@"iteration"];
    [plist setObject:[NSNumber numberWithUnsignedInteger:[test iterationCount]] forKey:@"iterationCount"];
    [plist setObject:GSMap([test failures], ^id(id issue) { return GSPlistFromIssue(issue); }) forKey:@"failures"];
    [plist setObject:GSMap([test expectedFailures], ^id(id issue) { return GSPlistFromIssue(issue); })
              forKey:@"expectedFailures"];
    if ([test skip] != nil) {
        [plist setObject:GSPlistFromIssue([test skip]) forKey:@"skip"];
    }
    [plist setObject:GSMap([test measurements], ^id(id item) {
        GSXCTMeasurement *measurement = item;
        NSMutableDictionary *m = [NSMutableDictionary dictionary];

        [m setObject:[measurement metricIdentifier] forKey:@"identifier"];
        [m setObject:([measurement displayName] ? [measurement displayName] : @"") forKey:@"displayName"];
        [m setObject:([measurement unitSymbol] ? [measurement unitSymbol] : @"") forKey:@"unit"];
        [m setObject:[NSNumber numberWithInt:[measurement polarity]] forKey:@"polarity"];
        [m setObject:[measurement values] forKey:@"values"];
        if ([measurement baselineAverage] != nil) {
            [m setObject:[measurement baselineAverage] forKey:@"baselineAverage"];
        }
        [m setObject:[NSNumber numberWithDouble:[measurement maxPercentRegression]] forKey:@"maxPercentRegression"];
        return m;
    }) forKey:@"measurements"];
    [plist setObject:GSMap([test attachments], ^id(id item) {
        GSXCTAttachmentRecord *record = item;
        NSMutableDictionary *a = [NSMutableDictionary dictionary];

        [a setObject:[record displayName] forKey:@"name"];
        if ([record savedPath] != nil) {
            [a setObject:[record savedPath] forKey:@"savedPath"];
        }
        if ([record activityPath] != nil) {
            [a setObject:[record activityPath] forKey:@"activityPath"];
        }
        return a;
    }) forKey:@"attachments"];
    return plist;
}

static GSXCTestCaseResult *GSTestFromPlist(NSDictionary *plist)
{
    GSXCTestCaseResult *test = [[[GSXCTestCaseResult alloc] initWithClassName:[plist objectForKey:@"class"]
                                                                  methodName:[plist objectForKey:@"method"]] autorelease];

    [test setStatus:(GSXCTestStatus)[[plist objectForKey:@"status"] intValue]];
    [test setStartDate:[NSDate dateWithTimeIntervalSinceReferenceDate:[[plist objectForKey:@"start"] doubleValue]]];
    [test setDuration:[[plist objectForKey:@"duration"] doubleValue]];
    [test setIteration:[[plist objectForKey:@"iteration"] unsignedIntegerValue]];
    [test setIterationCount:[[plist objectForKey:@"iterationCount"] unsignedIntegerValue]];
    for (NSDictionary *issue in [plist objectForKey:@"failures"]) {
        [[test failures] addObject:GSIssueFromPlist(issue)];
    }
    for (NSDictionary *issue in [plist objectForKey:@"expectedFailures"]) {
        [[test expectedFailures] addObject:GSIssueFromPlist(issue)];
    }
    if ([plist objectForKey:@"skip"] != nil) {
        [test setSkip:GSIssueFromPlist([plist objectForKey:@"skip"])];
    }
    for (NSDictionary *m in [plist objectForKey:@"measurements"]) {
        GSXCTMeasurement *measurement = [[[GSXCTMeasurement alloc] init] autorelease];

        [measurement setMetricIdentifier:[m objectForKey:@"identifier"]];
        [measurement setDisplayName:[m objectForKey:@"displayName"]];
        [measurement setUnitSymbol:[m objectForKey:@"unit"]];
        [measurement setPolarity:[[m objectForKey:@"polarity"] intValue]];
        [measurement setValues:[m objectForKey:@"values"]];
        [measurement setBaselineAverage:[m objectForKey:@"baselineAverage"]];
        [measurement setMaxPercentRegression:[[m objectForKey:@"maxPercentRegression"] doubleValue]];
        [[test measurements] addObject:measurement];
    }
    for (NSDictionary *a in [plist objectForKey:@"attachments"]) {
        XCTAttachment *attachment = [XCTAttachment attachmentWithData:[NSData data]];
        GSXCTAttachmentRecord *record = nil;

        [attachment setName:[a objectForKey:@"name"]];
        record = [[[GSXCTAttachmentRecord alloc] initWithAttachment:attachment
                                                       activityPath:[a objectForKey:@"activityPath"]] autorelease];
        [record setSavedPath:[a objectForKey:@"savedPath"]];
        [[test attachments] addObject:record];
    }
    return test;
}

static NSDictionary *GSPlistFromSuite(GSXCTestSuiteResult *suite)
{
    return [NSDictionary dictionaryWithObjectsAndKeys:
        [suite name], @"name",
        [NSNumber numberWithDouble:[[suite startDate] timeIntervalSinceReferenceDate]], @"start",
        [NSNumber numberWithDouble:[suite duration]], @"duration",
        GSMap([suite classFailures], ^id(id issue) { return GSPlistFromIssue(issue); }), @"classFailures",
        GSMap([suite testResults], ^id(id test) { return GSPlistFromTest(test); }), @"tests",
        nil];
}

static GSXCTestSuiteResult *GSSuiteFromPlist(NSDictionary *plist)
{
    GSXCTestSuiteResult *suite = [[[GSXCTestSuiteResult alloc] initWithName:[plist objectForKey:@"name"]] autorelease];

    [suite setStartDate:[NSDate dateWithTimeIntervalSinceReferenceDate:[[plist objectForKey:@"start"] doubleValue]]];
    [suite setDuration:[[plist objectForKey:@"duration"] doubleValue]];
    for (NSDictionary *issue in [plist objectForKey:@"classFailures"]) {
        [[suite classFailures] addObject:GSIssueFromPlist(issue)];
    }
    for (NSDictionary *test in [plist objectForKey:@"tests"]) {
        [[suite testResults] addObject:GSTestFromPlist(test)];
    }
    return suite;
}

#pragma mark - Worker side

@implementation GSXCTestWorkerResultsReporter

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
- (void) test: (GSXCTestCaseResult *)test didRecordFailureAfterFinishing: (GSXCTestIssue *)failure {}
- (void) test: (GSXCTestCaseResult *)test didRecordExpectedFailure: (GSXCTestIssue *)failure {}
- (void) test: (GSXCTestCaseResult *)test didMeasure: (GSXCTMeasurement *)measurement {}
- (void) test: (GSXCTestCaseResult *)test didStartActivity: (NSArray *)activityPath atTime: (NSTimeInterval)time {}
- (void) suite: (GSXCTestSuiteResult *)suite didRecordClassFailure: (GSXCTestIssue *)failure {}
- (void) test: (GSXCTestCaseResult *)test didSaveAttachment: (GSXCTAttachmentRecord *)attachment {}
- (void) testDidFinish: (GSXCTestCaseResult *)test {}
- (void) testWillBeRetried: (GSXCTestCaseResult *)test {}
- (void) suiteDidFinish: (GSXCTestSuiteResult *)suite {}

- (void) runDidFinish: (GSXCTestRunResult *)run
{
    NSDictionary *results = [NSDictionary dictionaryWithObject:GSMap([run suiteResults], ^id(id suite) {
        return GSPlistFromSuite(suite);
    }) forKey:@"suites"];
    NSData *data = [NSJSONSerialization dataWithJSONObject:results options:0 error:NULL];

    if (data == nil || ![data writeToFile:_path atomically:YES]) {
        NSLog(@"XCTest: Could not write worker results to '%@'", _path);
    }
}

@end

@implementation GSXCTestWorkerConsoleReporter

- (id) initWithReporter: (id<GSXCTestReporter>)reporter
{
    self = [super init];
    if (self) {
        _reporter = [reporter retain];
    }
    return self;
}

- (void) dealloc
{
    [_reporter release];
    [super dealloc];
}

// The coordinator prints the run's opening and closing lines.
- (void) runDidStart: (GSXCTestRunResult *)run {}
- (void) runDidFinish: (GSXCTestRunResult *)run {}
- (void) suiteHasNoSelectedTests: (GSXCTestSuiteResult *)suite {}

- (id) forwardingTargetForSelector: (SEL)selector
{
    return _reporter;
}

- (BOOL) respondsToSelector: (SEL)selector
{
    return [super respondsToSelector:selector] || [_reporter respondsToSelector:selector];
}

@end

#pragma mark - Coordinator

/*! A worker process running one class. */
@interface GSXCTestWorker : NSObject {
@public
    NSString *className;
    NSArray *methods;
    NSTask *task;
    NSString *outputPath;
    NSString *resultsPath;
}
@end

@implementation GSXCTestWorker

- (void) dealloc
{
    [className release];
    [methods release];
    [task release];
    [outputPath release];
    [resultsPath release];
    [super dealloc];
}

@end

// This program, to start workers with.
static NSString *GSExecutablePath(void)
{
#if defined(_WIN32)
    // No /proc; GNUstep asks Windows (GetModuleFileNameW).
    NSString *executable = [[NSBundle mainBundle] executablePath];

    return executable != nil ? executable : [[[NSProcessInfo processInfo] arguments] objectAtIndex:0];
#else
    char path[PATH_MAX];
    ssize_t length = readlink("/proc/self/exe", path, sizeof(path) - 1);

    if (length <= 0) {
        return [[[NSProcessInfo processInfo] arguments] objectAtIndex:0];
    }
    path[length] = '\0';
    return [NSString stringWithUTF8String:path];
#endif
}

static NSString *GSAbsolutePath(NSString *path)
{
    if (path == nil || [path isAbsolutePath]) {
        return path;
    }
    return [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:path];
}

@implementation GSXCTestRunner (GSParallel)

// The options every worker gets, from the runner's settings.
- (NSArray *) _gsWorkerArguments
{
    NSMutableArray *arguments = [NSMutableArray array];
    NSString *attachments = attachmentsPath;

    [arguments addObject:@"-output-format"];
    [arguments addObject:(outputFormat == GSXCTestOutputFormatApple ? @"apple" : @"classic")];
    if (performanceBaselinesPath != nil) {
        [arguments addObject:@"-performance-baselines"];
        [arguments addObject:GSAbsolutePath(performanceBaselinesPath)];
    }
    if (repetitionMode != GSXCTestRepetitionNone) {
        if (repetitionMode == GSXCTestRepetitionUntilFailure) {
            [arguments addObject:@"-run-tests-until-failure"];
        } else if (repetitionMode == GSXCTestRepetitionRetryOnFailure) {
            [arguments addObject:@"-retry-tests-on-failure"];
        }
        [arguments addObject:@"-test-iterations"];
        [arguments addObject:[NSString stringWithFormat:@"%lu", (unsigned long)testIterations]];
    }
    if (testTimeoutsEnabled) {
        [arguments addObject:@"-test-timeouts-enabled"];
        [arguments addObject:@"YES"];
        if (defaultExecutionTimeAllowance > 0) {
            [arguments addObject:@"-default-test-execution-time-allowance"];
            [arguments addObject:[NSString stringWithFormat:@"%g", defaultExecutionTimeAllowance]];
        }
        if (maximumExecutionTimeAllowance > 0) {
            [arguments addObject:@"-maximum-test-execution-time-allowance"];
            [arguments addObject:[NSString stringWithFormat:@"%g", maximumExecutionTimeAllowance]];
        }
    }
    if (randomizeExecutionOrder) {
        [arguments addObject:@"-test-execution-order-seed"];
        [arguments addObject:[NSString stringWithFormat:@"%llu", executionOrderSeed]];
    }
    // Workers don't write the JUnit report, but save attachments where a
    // single run would.
    if (attachments == nil && junitReportPath != nil) {
        attachments = [[junitReportPath stringByDeletingPathExtension] stringByAppendingString:@"-attachments"];
    }
    if (attachments != nil) {
        [arguments addObject:@"-attachments-path"];
        [arguments addObject:GSAbsolutePath(attachments)];
    }
    return arguments;
}

- (BOOL) runTestsInParallelForTargetName: (NSString *)targetName
                     onlyTestIdentifiers: (NSArray *)onlyTestIdentifiers
                     skipTestIdentifiers: (NSArray *)skipTestIdentifiers
                             workerCount: (NSUInteger)workerCount
{
    NSArray *identifiers = [self testIdentifiersForTargetName:targetName
                                          onlyTestIdentifiers:onlyTestIdentifiers
                                          skipTestIdentifiers:skipTestIdentifiers];
    NSMutableArray *classNames = [NSMutableArray array];
    NSMutableDictionary *methodsByClass = [NSMutableDictionary dictionary];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *workDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"xctest-parallel-%d-%@", getpid(), [[NSProcessInfo processInfo] globallyUniqueString]]];
    NSString *executable = GSExecutablePath();
    NSArray *commonArguments = nil;
    BOOL filtersActive = [onlyTestIdentifiers count] > 0 || [skipTestIdentifiers count] > 0;
    NSString *runBundleName = bundleName ? bundleName : (targetName ? targetName : @"XCTest");
    GSXCTestRunResult *run = nil;
    id<GSXCTestReporter> consoleReporter = nil;
    GSXCTestJUnitReporter *junitReporter = nil;
    NSArray *reporters = nil;
    NSMutableArray *running = [NSMutableArray array];
    NSUInteger nextClass = 0;
    NSUInteger workerNumber = 0;
    BOOL workerFailed = NO;
    FILE *console = outputFormat == GSXCTestOutputFormatApple ? stdout : stderr;

    if (identifiers == nil) {
        return NO;
    }
    if (bundleName == nil && testBundle != nil) {
        runBundleName = [[testBundle bundlePath] lastPathComponent];
    }

    // Classes in run order, each with its selected tests.
    for (NSString *identifier in identifiers) {
        NSArray *components = [identifier componentsSeparatedByString:@"/"];
        NSString *className = [components objectAtIndex:1];

        if ([methodsByClass objectForKey:className] == nil) {
            [methodsByClass setObject:[NSMutableArray array] forKey:className];
            [classNames addObject:className];
        }
        [[methodsByClass objectForKey:className] addObject:[components objectAtIndex:2]];
    }

    if (workerCount == 0) {
        workerCount = [[NSProcessInfo processInfo] activeProcessorCount];
    }
    workerCount = MAX((NSUInteger)1, MIN(workerCount, [classNames count]));

    run = [[[GSXCTestRunResult alloc] initWithName:(filtersActive ? @"Selected tests" : @"All tests")
                                        bundleName:runBundleName] autorelease];
    [run setFiltersActive:filtersActive];
    [run setExecutionOrderSeed:(randomizeExecutionOrder ? executionOrderSeed : 0)];
    [run setStartDate:[NSDate date]];
    consoleReporter = outputFormat == GSXCTestOutputFormatApple
        ? (id<GSXCTestReporter>)[[[GSXCTestAppleReporter alloc] init] autorelease]
        : (id<GSXCTestReporter>)[[[GSXCTestClassicReporter alloc] init] autorelease];
    junitReporter = junitReportPath ? [[[GSXCTestJUnitReporter alloc] initWithPath:junitReportPath] autorelease] : nil;
    reporters = [NSArray arrayWithObjects:consoleReporter, junitReporter, nil];

    if (![fileManager createDirectoryAtPath:workDirectory withIntermediateDirectories:YES attributes:nil error:NULL]) {
        NSLog(@"XCTest: Could not create '%@' for parallel workers.", workDirectory);
        return NO;
    }
    commonArguments = [self _gsWorkerArguments];

    for (id<GSXCTestReporter> reporter in reporters) {
        [reporter runDidStart:run];
    }
    if ([classNames count] > 0) {
        NSLog(@"XCTest: Running %lu test classes in parallel, %lu at a time",
            (unsigned long)[classNames count], (unsigned long)workerCount);
    }
    fflush(stdout);
    fflush(stderr);

    while (nextClass < [classNames count] || [running count] > 0) {
        // Start workers while there are classes and free slots.
        while (nextClass < [classNames count] && [running count] < workerCount) {
            GSXCTestWorker *worker = [[[GSXCTestWorker alloc] init] autorelease];
            NSMutableArray *arguments = [NSMutableArray arrayWithObject:[[testBundle bundlePath] stringByStandardizingPath]];
            NSFileHandle *output = nil;

            worker->className = [[classNames objectAtIndex:nextClass++] retain];
            worker->methods = [[methodsByClass objectForKey:worker->className] retain];
            worker->outputPath = [[workDirectory stringByAppendingPathComponent:
                [NSString stringWithFormat:@"worker-%lu.log", (unsigned long)workerNumber]] retain];
            worker->resultsPath = [[workDirectory stringByAppendingPathComponent:
                [NSString stringWithFormat:@"worker-%lu.json", (unsigned long)workerNumber]] retain];
            workerNumber++;

            [arguments addObjectsFromArray:commonArguments];
            [arguments addObject:@"-gs-parallel-worker-results"];
            [arguments addObject:worker->resultsPath];
            for (NSString *method in worker->methods) {
                [arguments addObject:[NSString stringWithFormat:@"-only-testing:%@/%@/%@",
                    targetName, worker->className, method]];
            }

            [fileManager createFileAtPath:worker->outputPath contents:nil attributes:nil];
            output = [NSFileHandle fileHandleForWritingAtPath:worker->outputPath];
            worker->task = [[NSTask alloc] init];
            [worker->task setLaunchPath:executable];
            [worker->task setArguments:arguments];
            // One file for both, so the worker's lines stay in order.
            [worker->task setStandardOutput:output];
            [worker->task setStandardError:output];
            [worker->task launch];
            [output closeFile];
            [running addObject:worker];
        }

        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];

        for (GSXCTestWorker *worker in [[running copy] autorelease]) {
            NSData *output = nil;
            NSData *results = nil;
            NSDictionary *plist = nil;

            if ([worker->task isRunning]) {
                continue;
            }
            [worker->task waitUntilExit];
            [running removeObject:worker];

            output = [NSData dataWithContentsOfFile:worker->outputPath];
            fwrite([output bytes], 1, [output length], console);
            fflush(console);

            results = [NSData dataWithContentsOfFile:worker->resultsPath];
            plist = results ? [NSJSONSerialization JSONObjectWithData:results options:0 error:NULL] : nil;
            if ([plist isKindOfClass:[NSDictionary class]]) {
                for (NSDictionary *suite in [plist objectForKey:@"suites"]) {
                    [[run suiteResults] addObject:GSSuiteFromPlist(suite)];
                }
                continue;
            }

            // The worker died without reporting: its tests' results are
            // unknown, so they count as failed.
            {
                BOOL signaled = [worker->task terminationReason] == NSTaskTerminationReasonUncaughtSignal;
                int code = [worker->task terminationStatus];
                NSString *how = [NSString stringWithFormat:@"%@ %d", signaled ? @"signal" : @"status", code];
#if defined(_WIN32)
                // A crash ends a Windows process with an NTSTATUS code, such as
                // 0xC0000409 for abort(), which reads better in hex.
                if (code < 0) {
                    how = [NSString stringWithFormat:@"status 0x%08X", (unsigned int)code];
                }
#endif
                GSXCTestSuiteResult *suite = [[[GSXCTestSuiteResult alloc] initWithName:worker->className] autorelease];

                workerFailed = YES;
                fprintf(stderr, "xctest: the process running %s exited (%s) without reporting its results\n",
                    [worker->className UTF8String], [how UTF8String]);
                [suite setStartDate:[NSDate date]];
                for (NSString *method in worker->methods) {
                    GSXCTestCaseResult *test = [[[GSXCTestCaseResult alloc] initWithClassName:worker->className
                                                                                   methodName:method] autorelease];

                    [test setStatus:GSXCTestStatusFailed];
                    [test setStartDate:[suite startDate]];
                    [[test failures] addObject:[GSXCTestIssue issueWithMessage:
                        [NSString stringWithFormat:@"The test process exited (%@) before reporting this test's result", how]
                                                                      filePath:nil lineNumber:0 unexpected:YES]];
                    [[suite testResults] addObject:test];
                }
                [[run suiteResults] addObject:suite];
            }
        }
    }

    [run setDuration:[[NSDate date] timeIntervalSinceDate:[run startDate]]];
    for (id<GSXCTestReporter> reporter in reporters) {
        [reporter runDidFinish:run];
    }
    [fileManager removeItemAtPath:workDirectory error:NULL];

    return [identifiers count] > 0 && ![run hasFailed] && !workerFailed && (junitReporter == nil || [junitReporter wroteReport]);
}

@end
