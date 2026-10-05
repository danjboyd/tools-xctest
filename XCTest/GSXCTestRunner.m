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

#include <stdio.h>
#include <unistd.h>

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

// Adds the test cases in a test (itself, or a suite's, recursively).
static void GSCollectTestCases(XCTest *test, NSMutableArray *testCases)
{
    if ([test isKindOfClass:[XCTestCase class]]) {
        [testCases addObject:test];
    } else if ([test isKindOfClass:[XCTestSuite class]]) {
        for (XCTest *child in [(XCTestSuite *)test tests]) {
            GSCollectTestCases(child, testCases);
        }
    }
}

@implementation GSXCTestRunner

@synthesize outputFormat;
@synthesize bundleName;
@synthesize junitReportPath;
@synthesize testBundle;
@synthesize performanceBaselinesPath;
@synthesize updatePerformanceBaselines;
@synthesize repetitionMode;
@synthesize testIterations;
@synthesize testTimeoutsEnabled;
@synthesize defaultExecutionTimeAllowance;
@synthesize maximumExecutionTimeAllowance;
@synthesize terminationHandler;

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
    [testBundle release];
    [principalObject release];
    [performanceBaselinesPath release];
    [performanceBaselines release];
    [bundleName release];
    [junitReportPath release];
    [terminationHandler release];
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

    // Each class's tests come from its +defaultTestSuite, so a class can
    // override that (or +testInvocations) to change what runs.
    for (Class testCaseClass in _GSXCTestCaseSubclasses())
    {
        GSXCTestCaseSuite *suite = [GSXCTestCaseSuite suiteForTestCaseClass:testCaseClass];
        NSMutableArray *testCases = [NSMutableArray array];

        GSCollectTestCases([testCaseClass defaultTestSuite], testCases);
        for (XCTestCase *testCase in testCases)
        {
            NSString *className = NSStringFromClass([testCase class]);
            NSString *methodName = [testCase _gsMethodName];
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
                [suite addTest:testCase];
            }
        }

        [plan addObject:suite];
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

    for (XCTestSuite *suite in plan) {
        for (XCTestCase *testCase in [suite tests]) {
            [identifiers addObject:[NSString stringWithFormat:@"%@/%@/%@",
                targetName ? targetName : @"", NSStringFromClass([testCase class]), [testCase _gsMethodName]]];
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

    if (![self _gsLoadPerformanceBaselines]) {
        [runLock unlock];
        return NO;
    }

    NSString *runBundleName = bundleName ? bundleName
        : (testBundle ? [[testBundle bundlePath] lastPathComponent] : (targetName ? targetName : @"XCTest"));
    XCTestSuite *topSuite = [XCTestSuite testSuiteWithName:(filtersActive ? @"Selected tests" : @"All tests")];
    XCTestSuite *bundleSuite = [XCTestSuite testSuiteWithName:runBundleName];
    GSXCTestRunResult *run = [[[GSXCTestRunResult alloc]
        initWithName:[topSuite name] bundleName:runBundleName] autorelease];
    id<GSXCTestReporter> consoleReporter = (outputFormat == GSXCTestOutputFormatApple)
        ? (id<GSXCTestReporter>)[[[GSXCTestAppleReporter alloc] init] autorelease]
        : (id<GSXCTestReporter>)[[[GSXCTestClassicReporter alloc] init] autorelease];
    GSXCTestJUnitReporter *junitReporter = junitReportPath
        ? [[[GSXCTestJUnitReporter alloc] initWithPath:junitReportPath] autorelease]
        : nil;
    NSArray *reporters = [NSArray arrayWithObjects:consoleReporter, junitReporter, nil];
    GSXCTestReportingObserver *reportingObserver = [[[GSXCTestReportingObserver alloc]
        initWithReporters:reporters run:run topSuite:topSuite] autorelease];
    XCTestObservationCenter *center = [XCTestObservationCenter sharedTestObservationCenter];

    for (XCTestSuite *suite in plan) {
        [bundleSuite addTest:suite];
    }
    [topSuite addTest:bundleSuite];
    [run setFiltersActive:filtersActive];

    [GSXCTestCaseSuite _gsSetRepetitionMode:repetitionMode iterations:testIterations];
    _GSXCTSetTimeouts(testTimeoutsEnabled, defaultExecutionTimeAllowance, maximumExecutionTimeAllowance);
    [self _gsCreatePrincipalObject];
    // First, so its results exist before other observers' callbacks run.
    [center _gsAddTestObserverFirst:(id<XCTestObservation>)reportingObserver];

    if (testBundle != nil) {
        [center _gsNotifyObservers:^(id observer) {
            if ([observer respondsToSelector:@selector(testBundleWillStart:)]) {
                [observer testBundleWillStart:testBundle];
            }
        }];
    }

    [topSuite runTest];

    if (testBundle != nil) {
        [center _gsNotifyObservers:^(id observer) {
            if ([observer respondsToSelector:@selector(testBundleDidFinish:)]) {
                [observer testBundleDidFinish:testBundle];
            }
        }];
    }

    [center removeTestObserver:(id<XCTestObservation>)reportingObserver];

    BOOL savedBaselines = [self _gsSavePerformanceBaselines];

    [runLock unlock];

    return [[topSuite testRun] hasSucceeded] && savedBaselines
        && (junitReporter == nil || [junitReporter wroteReport]);
}

// Reads performanceBaselinesPath. A missing file is fine when updating
// (it will be created); otherwise, or if it isn't valid, the run fails.
- (BOOL)_gsLoadPerformanceBaselines
{
    NSData *data = nil;
    id baselines = nil;

    [performanceBaselines release];
    performanceBaselines = [[NSMutableDictionary alloc] init];

    if (performanceBaselinesPath == nil) {
        return YES;
    }

    data = [NSData dataWithContentsOfFile:performanceBaselinesPath];
    if (data == nil) {
        if (updatePerformanceBaselines) {
            return YES;
        }
        NSLog(@"XCTest: Could not read performance baselines from '%@'.", performanceBaselinesPath);
        return NO;
    }

    baselines = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![baselines isKindOfClass:[NSDictionary class]]) {
        NSLog(@"XCTest: Performance baselines in '%@' are not a JSON object.", performanceBaselinesPath);
        return NO;
    }

    for (NSString *identifier in baselines) {
        id baseline = [baselines objectForKey:identifier];
        if ([baseline isKindOfClass:[NSDictionary class]]) {
            [performanceBaselines setObject:[[baseline mutableCopy] autorelease] forKey:identifier];
        }
    }

    return YES;
}

- (BOOL)_gsSavePerformanceBaselines
{
    NSData *data = nil;

    if (!updatePerformanceBaselines || performanceBaselinesPath == nil) {
        return YES;
    }

    data = [NSJSONSerialization dataWithJSONObject:performanceBaselines
                                           options:NSJSONWritingPrettyPrinted
                                             error:NULL];
    if (data == nil || ![data writeToFile:performanceBaselinesPath atomically:YES]) {
        NSLog(@"XCTest: Could not write performance baselines to '%@'.", performanceBaselinesPath);
        return NO;
    }

    return YES;
}

- (NSDictionary *)_gsPerformanceBaselineForTest:(NSString *)identifier
{
    // When recording new baselines, don't judge against the old ones.
    if (updatePerformanceBaselines) {
        return nil;
    }

    return [performanceBaselines objectForKey:identifier];
}

- (void)_gsRecordPerformanceAverage:(double)average forTest:(NSString *)identifier
{
    NSMutableDictionary *baseline = [performanceBaselines objectForKey:identifier];

    if (!updatePerformanceBaselines) {
        return;
    }

    if (baseline == nil) {
        baseline = [NSMutableDictionary dictionary];
        [performanceBaselines setObject:baseline forKey:identifier];
    }
    [baseline setObject:[NSNumber numberWithDouble:average] forKey:@"average"];
}

// Creates the test bundle's principal class (NSPrincipalClass in its
// Info.plist), once, so it can register test observers before tests run.
- (void)_gsCreatePrincipalObject
{
    NSString *className = [[testBundle infoDictionary] objectForKey:@"NSPrincipalClass"];
    Class principalClass = className ? NSClassFromString(className) : Nil;

    if (principalObject != nil || principalClass == Nil
        || [principalClass isSubclassOfClass:[XCTest class]]) {
        return;
    }

    principalObject = [[principalClass alloc] init];
}

- (void)_gsTerminateWithExitCode:(int)exitCode
{
    void (^handler)(int) = [[terminationHandler retain] autorelease];

    if (testBundle != nil) {
        [[XCTestObservationCenter sharedTestObservationCenter] _gsNotifyObservers:^(id observer) {
            if ([observer respondsToSelector:@selector(testBundleDidFinish:)]) {
                [observer testBundleDidFinish:testBundle];
            }
        }];
    }

    fflush(stdout);
    fflush(stderr);
    if (handler != nil) {
        handler(exitCode);
    }
    _exit(exitCode);
}

- (void)waitForCompletion
{
    [runLock lock];
    [runLock unlock];
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
