//
//  GSXCTestRunner.m
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


#import <XCTest/GSXCTestRunner.h>
#import <XCTest/XCTestCase.h>
#import <XCTest/XCTestAssertionsImpl.h>
#import <XCTest/XCTestPrivate.h>
#import <XCTest/GSXCTestReporting.h>

#import <objc/runtime.h>

@interface GSXCTestRunner ()
- (NSArray *)testPlanForTargetName:(NSString *)targetName
               onlyTestIdentifiers:(NSArray *)onlyTestIdentifiers
               skipTestIdentifiers:(NSArray *)skipTestIdentifiers
                   legacyTestNames:(NSArray *)legacyTestNames
                     filtersActive:(BOOL *)filtersActive;
- (BOOL)runTestsForTargetName:(NSString *)targetName
          onlyTestIdentifiers:(NSArray *)onlyTestIdentifiers
          skipTestIdentifiers:(NSArray *)skipTestIdentifiers
              legacyTestNames:(NSArray *)legacyTestNames;
- (BOOL)runClassMethod:(SEL)selector ofClass:(Class)testCaseClass;
- (void)runTest:(GSXCTestCaseResult *)test ofClass:(Class)testCaseClass;
- (BOOL)runPhase:(NSString *)phaseName
          ofTest:(GSXCTestCaseResult *)test
           block:(BOOL (^)(NSError **error))block;
@end

static NSArray *GSParseAppleTestIdentifier(NSString *identifier)
{
    NSArray *components = [identifier componentsSeparatedByString:@"/"];

    if ([components count] == 0 || [components count] > 3)
    {
        return nil;
    }

    for (NSString *component in components)
    {
        if ([component length] == 0)
        {
            return nil;
        }
    }

    return components;
}

static BOOL GSAppleTestIdentifierMatches(NSArray *identifierComponents,
                                         NSString *targetName,
                                         NSString *className,
                                         NSString *methodName)
{
    if (![targetName isEqualToString:[identifierComponents objectAtIndex:0]])
    {
        return NO;
    }

    if ([identifierComponents count] >= 2 &&
        ![className isEqualToString:[identifierComponents objectAtIndex:1]])
    {
        return NO;
    }

    if ([identifierComponents count] == 3 &&
        ![methodName isEqualToString:[identifierComponents objectAtIndex:2]])
    {
        return NO;
    }

    return YES;
}

static BOOL GSLegacyTestNameMatches(NSString *testName,
                                    NSString *className,
                                    NSString *methodName)
{
    NSArray *tuple = [testName componentsSeparatedByString:@"."];

    if ([tuple count] == 2)
    {
        return [className isEqualToString:[tuple objectAtIndex:0]] &&
               [methodName isEqualToString:[tuple objectAtIndex:1]];
    }

    if ([tuple count] == 1)
    {
        return [className isEqualToString:[tuple objectAtIndex:0]];
    }

    return NO;
}

// From: https://www.cocoawithlove.com/2010/01/getting-subclasses-of-objective-c-class.html
NSArray *ClassGetSubclasses(Class parentClass)
{
    int numClasses = objc_getClassList(NULL, 0);
    Class *classes = NULL;

    classes = malloc(sizeof(Class) * numClasses);
    numClasses = objc_getClassList(classes, numClasses);
    
    NSMutableArray *result = [NSMutableArray array];
    for (NSInteger i = 0; i < numClasses; i++)
    {
        Class superClass = classes[i];
        do
        {
            superClass = class_getSuperclass(superClass);
        } while(superClass && superClass != parentClass);
        
        if (superClass == nil)
        {
            continue;
        }
        
        [result addObject:classes[i]];
    }

    free(classes);
    
    return result;
}

// Test methods of a class, including those inherited from superclasses
// below XCTestCase, sorted by name to match Apple's run order.
static NSArray *GSTestMethodNames(Class testCaseClass)
{
    NSMutableSet *names = [NSMutableSet set];

    for (Class cls = testCaseClass;
         cls != Nil && cls != [XCTestCase class];
         cls = class_getSuperclass(cls))
    {
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);

        for (unsigned int i = 0; i < methodCount; i++)
        {
            Method method = methods[i];
            NSString *methodName = [NSString stringWithUTF8String:sel_getName(method_getName(method))];

            if ([methodName hasPrefix:@"test"]
                && method_getNumberOfArguments(method) == 2)
            {
                [names addObject:methodName];
            }
        }

        free(methods);
    }

    return [[names allObjects] sortedArrayUsingSelector:@selector(compare:)];
}

// "Name", "reason" -- the way Apple's XCTest describes a caught exception.
static NSString *GSDescribeException(NSException *exception)
{
    return [NSString stringWithFormat:@"\"%@\", \"%@\"", [exception name], [exception reason]];
}

// Sends a reporter message to every reporter.
#define GS_REPORT(reporters, call) \
    for (id<GSXCTestReporter> reporter in (reporters)) { [reporter call]; }

@implementation GSXCTestRunner

@synthesize outputFormat;
@synthesize bundleName;
@synthesize junitReportPath;

- (id)init
{
    self = [super init];
    if (self) {
        runLock = [[NSLock alloc] init];
    }
    
    return self;
}

- (void)dealloc
{
    [runLock release];
    [reporters release];
    [bundleName release];
    [junitReportPath release];
    [super dealloc];
}

- (BOOL)runAll
{
    return [self runTestsForTargetName:nil
                   onlyTestIdentifiers:nil
                   skipTestIdentifiers:nil];
}

- (BOOL)runTestsNamed:(NSArray *)testNames
{
    return [self runTestsForTargetName:nil
                   onlyTestIdentifiers:nil
                   skipTestIdentifiers:nil
                       legacyTestNames:testNames];
}

- (BOOL)runTestsForTargetName:(NSString *)targetName
          onlyTestIdentifiers:(NSArray *)onlyTestIdentifiers
          skipTestIdentifiers:(NSArray *)skipTestIdentifiers
{
    return [self runTestsForTargetName:targetName
                   onlyTestIdentifiers:onlyTestIdentifiers
                   skipTestIdentifiers:skipTestIdentifiers
                       legacyTestNames:nil];
}

- (NSArray *)testPlanForTargetName:(NSString *)targetName
               onlyTestIdentifiers:(NSArray *)onlyTestIdentifiers
               skipTestIdentifiers:(NSArray *)skipTestIdentifiers
                   legacyTestNames:(NSArray *)legacyTestNames
                     filtersActive:(BOOL *)filtersActive
{
    NSMutableArray *parsedOnlyIdentifiers = nil;
    NSMutableArray *parsedSkipIdentifiers = nil;
    BOOL usingAppleStyleFilters = (legacyTestNames == nil);
    BOOL usingAnyFilters = NO;
    NSMutableArray *plan = [NSMutableArray array];

    if (usingAppleStyleFilters)
    {
        if ([onlyTestIdentifiers count] > 0)
        {
            parsedOnlyIdentifiers = [NSMutableArray arrayWithCapacity:[onlyTestIdentifiers count]];
            usingAnyFilters = YES;

            for (NSString *identifier in onlyTestIdentifiers)
            {
                NSArray *components = GSParseAppleTestIdentifier(identifier);
                if (components == nil)
                {
                    NSLog(@"XCTest: Invalid test identifier '%@'. Expected TestTarget[/TestClass[/TestMethod]].", identifier);
                    return nil;
                }

                [parsedOnlyIdentifiers addObject:components];
            }
        }

        if ([skipTestIdentifiers count] > 0)
        {
            parsedSkipIdentifiers = [NSMutableArray arrayWithCapacity:[skipTestIdentifiers count]];
            usingAnyFilters = YES;

            for (NSString *identifier in skipTestIdentifiers)
            {
                NSArray *components = GSParseAppleTestIdentifier(identifier);
                if (components == nil)
                {
                    NSLog(@"XCTest: Invalid test identifier '%@'. Expected TestTarget[/TestClass[/TestMethod]].", identifier);
                    return nil;
                }

                [parsedSkipIdentifiers addObject:components];
            }
        }

        if (usingAnyFilters && ([targetName length] == 0))
        {
            NSLog(@"XCTest: A target name is required when using -only-testing or -skip-testing filters.");
            return nil;
        }
    }

    if (filtersActive) {
        *filtersActive = usingAnyFilters;
    }

    NSArray *testCaseClasses = [ClassGetSubclasses([XCTestCase class])
        sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
            return [NSStringFromClass(a) compare:NSStringFromClass(b)];
        }];
    for (Class testCaseClass in testCaseClasses)
    {
        NSString *className = NSStringFromClass(testCaseClass);
        NSMutableArray *selectedMethodNames = [NSMutableArray array];

        for (NSString *methodName in GSTestMethodNames(testCaseClass))
        {
            BOOL testIsEnabled = YES;
            if (usingAppleStyleFilters)
            {
                if ([parsedOnlyIdentifiers count] > 0)
                {
                    testIsEnabled = NO;
                    for (NSArray *identifierComponents in parsedOnlyIdentifiers)
                    {
                        if (GSAppleTestIdentifierMatches(identifierComponents,
                                                         targetName,
                                                         className,
                                                         methodName))
                        {
                            testIsEnabled = YES;
                            break;
                        }
                    }
                }

                if (testIsEnabled && [parsedSkipIdentifiers count] > 0)
                {
                    for (NSArray *identifierComponents in parsedSkipIdentifiers)
                    {
                        if (GSAppleTestIdentifierMatches(identifierComponents,
                                                         targetName,
                                                         className,
                                                         methodName))
                        {
                            testIsEnabled = NO;
                            break;
                        }
                    }
                }
            }
            else if (legacyTestNames)
            {
                testIsEnabled = NO; // default to disabled when tests are specified
                for (NSString *testName in legacyTestNames)
                {
                    if (GSLegacyTestNameMatches(testName, className, methodName))
                    {
                        testIsEnabled = YES;
                        break;
                    }
                }
            }

            if (testIsEnabled)
            {
                [selectedMethodNames addObject:methodName];
            }
        }

        [plan addObject:[NSArray arrayWithObjects:testCaseClass, selectedMethodNames, nil]];
    }

    return plan;
}

- (NSArray *)testIdentifiersForTargetName:(NSString *)targetName
                      onlyTestIdentifiers:(NSArray *)onlyTestIdentifiers
                      skipTestIdentifiers:(NSArray *)skipTestIdentifiers
{
    NSArray *plan = [self testPlanForTargetName:targetName
                            onlyTestIdentifiers:onlyTestIdentifiers
                            skipTestIdentifiers:skipTestIdentifiers
                                legacyTestNames:nil
                                  filtersActive:NULL];
    NSMutableArray *identifiers = [NSMutableArray array];

    if (plan == nil) {
        return nil;
    }

    for (NSArray *entry in plan) {
        NSString *className = NSStringFromClass([entry objectAtIndex:0]);

        for (NSString *methodName in [entry objectAtIndex:1]) {
            [identifiers addObject:[NSString stringWithFormat:@"%@/%@/%@",
                targetName ? targetName : @"", className, methodName]];
        }
    }

    return identifiers;
}

- (BOOL)runTestsForTargetName:(NSString *)targetName
          onlyTestIdentifiers:(NSArray *)onlyTestIdentifiers
          skipTestIdentifiers:(NSArray *)skipTestIdentifiers
              legacyTestNames:(NSArray *)legacyTestNames
{
    BOOL filtersActive = NO;
    NSArray *plan = [self testPlanForTargetName:targetName
                            onlyTestIdentifiers:onlyTestIdentifiers
                            skipTestIdentifiers:skipTestIdentifiers
                                legacyTestNames:legacyTestNames
                                  filtersActive:&filtersActive];

    if (plan == nil) {
        return NO;
    }

    [runLock lock];

    NSString *runBundleName = bundleName ? bundleName : (targetName ? targetName : @"XCTest");
    GSXCTestRunResult *run = [[[GSXCTestRunResult alloc]
        initWithName:(filtersActive ? @"Selected tests" : @"All tests")
          bundleName:runBundleName] autorelease];
    id<GSXCTestReporter> consoleReporter = (outputFormat == GSXCTestOutputFormatApple)
        ? (id<GSXCTestReporter>)[[[GSXCTestAppleReporter alloc] init] autorelease]
        : (id<GSXCTestReporter>)[[[GSXCTestClassicReporter alloc] init] autorelease];

    GSXCTestJUnitReporter *junitReporter = junitReportPath
        ? [[[GSXCTestJUnitReporter alloc] initWithPath:junitReportPath] autorelease]
        : nil;

    [reporters release];
    reporters = [[NSArray alloc] initWithObjects:consoleReporter, junitReporter, nil];

    [run setFiltersActive:filtersActive];
    [run setStartDate:[NSDate date]];
    GS_REPORT(reporters, runDidStart:run)

    for (NSArray *entry in plan)
    {
        @autoreleasepool {
            Class testCaseClass = [entry objectAtIndex:0];
            NSArray *selectedMethodNames = [entry objectAtIndex:1];
            GSXCTestSuiteResult *suite = [[[GSXCTestSuiteResult alloc]
                initWithName:NSStringFromClass(testCaseClass)] autorelease];

            if ([selectedMethodNames count] == 0)
            {
                GS_REPORT(reporters, suiteHasNoSelectedTests:suite)
                continue;
            }

            [run.suiteResults addObject:suite];
            [suite setStartDate:[NSDate date]];
            currentSuiteResult = suite;
            GS_REPORT(reporters, suiteDidStart:suite)

            BOOL classSetUpSucceeded = [self runClassMethod:@selector(setUp)
                                                    ofClass:testCaseClass];

            for (NSString *methodName in selectedMethodNames)
            {
                GSXCTestCaseResult *test = [[[GSXCTestCaseResult alloc]
                    initWithClassName:[suite name] methodName:methodName] autorelease];

                [suite.testResults addObject:test];
                if (classSetUpSucceeded)
                {
                    [self runTest:test ofClass:testCaseClass];
                }
                else
                {
                    // Report each test as failed without running it.
                    [test setStartDate:[NSDate date]];
                    currentTestResult = test;
                    GS_REPORT(reporters, testDidStart:test)
                    GSXCTestIssue *cause = [[suite classFailures] objectAtIndex:0];
                    [self recordFailureWithMessage:[NSString stringWithFormat:@"+setUp failed: %@", [cause message]]
                                          filePath:[cause filePath]
                                        lineNumber:[cause lineNumber]
                                        unexpected:[cause unexpected]];
                    [test setStatus:GSXCTestStatusFailed];
                    currentTestResult = nil;
                    GS_REPORT(reporters, testDidFinish:test)
                }
            }

            if (classSetUpSucceeded)
            {
                [self runClassMethod:@selector(tearDown) ofClass:testCaseClass];
            }

            currentSuiteResult = nil;
            [suite setDuration:-[[suite startDate] timeIntervalSinceNow]];
            GS_REPORT(reporters, suiteDidFinish:suite)
        } // @autoreleasepool
    }

    [run setDuration:-[[run startDate] timeIntervalSinceNow]];
    GS_REPORT(reporters, runDidFinish:run)

    [reporters release];
    reporters = nil;

    [runLock unlock];
    
    return ![run hasFailed] && (junitReporter == nil || [junitReporter wroteReport]);
}

- (BOOL)runClassMethod:(SEL)selector ofClass:(Class)testCaseClass
{
    GSXCTestSuiteResult *suite = currentSuiteResult;
    NSUInteger failuresBefore = [[suite classFailures] count];

    currentClassContext = (selector == @selector(setUp)) ? @"+setUp" : @"+tearDown";
    @try {
        [testCaseClass performSelector:selector];
    }
    @catch (NSException *exception) {
        [self recordFailureWithMessage:[NSString stringWithFormat:@"threw exception: %@", GSDescribeException(exception)]
                              filePath:nil
                            lineNumber:0
                            unexpected:YES];
    }
    currentClassContext = nil;

    return [[suite classFailures] count] == failuresBefore;
}

- (void)runTest:(GSXCTestCaseResult *)test ofClass:(Class)testCaseClass
{
    [test setStartDate:[NSDate date]];
    currentTestResult = test;
    GS_REPORT(reporters, testDidStart:test)

    @autoreleasepool {
        SEL selector = NSSelectorFromString([test methodName]);
        XCTestCase *testCase = [[[testCaseClass alloc] init] autorelease];
        void (^teardownBlock)(void) = nil;

        [XCTestCase _gsSetCurrentTestCase:testCase];

        BOOL setUpSucceeded = [self runPhase:@"setUpWithError:" ofTest:test block:^BOOL(NSError **error) {
            return [testCase setUpWithError:error];
        }];

        if (setUpSucceeded) {
            setUpSucceeded = [self runPhase:@"setUp" ofTest:test block:^BOOL(NSError **error) {
                [testCase setUp];
                return YES;
            }];
        }

        if (setUpSucceeded) {
            BOOL testCompleted = [self runPhase:nil ofTest:test block:^BOOL(NSError **error) {
                ((void (*)(id, SEL))[testCase methodForSelector:selector])(testCase, selector);
                return YES;
            }];

            // Only a test that ran to the end could have waited on everything.
            if (testCompleted) {
                [self runPhase:nil ofTest:test block:^BOOL(NSError **error) {
                    [testCase _gsRecordUnwaitedExpectations];
                    return YES;
                }];
            }
        }

        // Teardown always runs, whether or not set up or the test failed.
        while ((teardownBlock = [testCase _gsPopTeardownBlock]) != nil) {
            [self runPhase:@"a teardown block" ofTest:test block:^BOOL(NSError **error) {
                teardownBlock();
                return YES;
            }];
        }

        [self runPhase:@"tearDown" ofTest:test block:^BOOL(NSError **error) {
            [testCase tearDown];
            return YES;
        }];

        [self runPhase:@"tearDownWithError:" ofTest:test block:^BOOL(NSError **error) {
            return [testCase tearDownWithError:error];
        }];

        [testCase _gsInvalidateExpectations];
        [XCTestCase _gsSetCurrentTestCase:nil];
    }

    // A failure outranks a skip, as in Apple's XCTest.
    if ([[test failures] count] > 0) {
        [test setStatus:GSXCTestStatusFailed];
    } else if ([test skip] != nil) {
        [test setStatus:GSXCTestStatusSkipped];
    } else {
        [test setStatus:GSXCTestStatusPassed];
    }

    [test setDuration:-[[test startDate] timeIntervalSinceNow]];
    currentTestResult = nil;
    GS_REPORT(reporters, testDidFinish:test)
}

- (BOOL)runPhase:(NSString *)phaseName
          ofTest:(GSXCTestCaseResult *)test
           block:(BOOL (^)(NSError **error))block
{
    NSString *where = phaseName ? [NSString stringWithFormat:@" in %@", phaseName] : @"";
    NSError *error = nil;
    BOOL succeeded = NO;

    @try {
        succeeded = block(&error);
        if (!succeeded) {
            [self recordFailureWithMessage:[NSString stringWithFormat:@"failed%@ - %@", where,
                                               error ? [error localizedDescription] : @"returned NO without an error"]
                                  filePath:nil
                                lineNumber:0
                                unexpected:NO];
        }
    }
    @catch (_XCTSkipFailureException *skip) {
        // Remaining set up and the test body are skipped; teardown still runs.
        if ([test skip] == nil) {
            NSDictionary *info = [skip userInfo];
            [test setSkip:[GSXCTestIssue issueWithMessage:[info objectForKey:@"message"]
                                                 filePath:[info objectForKey:@"file"]
                                               lineNumber:[[info objectForKey:@"line"] unsignedIntegerValue]
                                               unexpected:NO]];
        }
    }
    @catch (_XCTestCaseInterruptionException *interruption) {
        // continueAfterFailure is NO; the failure has already been reported.
    }
    @catch (NSException *exception) {
        [self recordFailureWithMessage:[NSString stringWithFormat:@"threw exception%@: %@", where, GSDescribeException(exception)]
                              filePath:nil
                            lineNumber:0
                            unexpected:YES];
    }

    return succeeded;
}

- (void)waitForCompletion
{
    [runLock lock];
    [runLock unlock];
}

- (void)recordFailureWithMessage:(NSString *)message
                        filePath:(NSString *)filePath
                      lineNumber:(NSUInteger)lineNumber
                      unexpected:(BOOL)unexpected
{
    GSXCTestIssue *failure = [GSXCTestIssue issueWithMessage:message
                                                    filePath:filePath
                                                  lineNumber:lineNumber
                                                  unexpected:unexpected];

    @synchronized (self) {
        if (currentTestResult != nil) {
            [[currentTestResult failures] addObject:failure];
            GS_REPORT(reporters, test:currentTestResult didRecordFailure:failure)
        } else if (currentSuiteResult != nil) {
            [failure setContext:currentClassContext ? currentClassContext : @"+setUp"];
            [[currentSuiteResult classFailures] addObject:failure];
            GS_REPORT(reporters, suite:currentSuiteResult didRecordClassFailure:failure)
        } else {
            NSLog(@"XCTest: Failure outside of a test: %@", message);
        }
    }
}

+ (GSXCTestRunner *)sharedRunner
{
    static GSXCTestRunner *runner = nil;
    if (!runner) {
        runner = [[GSXCTestRunner alloc] init];
    }
    
    return runner;
}

@end
