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

#import <objc/runtime.h>

@interface XCTestCase (GSXCTestRunnerPrivate)
- (void (^)(void))_gsPopTeardownBlock;
@end

typedef enum {
    GSXCTestResultPassed,
    GSXCTestResultFailed,
    GSXCTestResultSkipped,
} GSXCTestResult;

@interface GSXCTestRunner ()
- (BOOL)runTestsForTargetName:(NSString *)targetName
          onlyTestIdentifiers:(NSArray *)onlyTestIdentifiers
          skipTestIdentifiers:(NSArray *)skipTestIdentifiers
              legacyTestNames:(NSArray *)legacyTestNames;
- (BOOL)runClassMethod:(SEL)selector ofClass:(Class)testCaseClass;
- (GSXCTestResult)runTestMethod:(NSString *)methodName ofClass:(Class)testCaseClass;
- (BOOL)runPhase:(NSString *)phaseName
          ofTest:(NSString *)methodName
           block:(BOOL (^)(NSError **error))block;
- (void)registerAssertionFailed;
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

static NSString *GSSkippedSummary(NSUInteger skipCount)
{
    if (skipCount == 0) {
        return @"";
    }

    return [NSString stringWithFormat:@" (%lu %@ skipped)",
        (unsigned long)skipCount, skipCount == 1 ? @"test" : @"tests"];
}

@implementation GSXCTestRunner

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
    [skipReason release];
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

- (BOOL)runTestsForTargetName:(NSString *)targetName
          onlyTestIdentifiers:(NSArray *)onlyTestIdentifiers
          skipTestIdentifiers:(NSArray *)skipTestIdentifiers
              legacyTestNames:(NSArray *)legacyTestNames
{
    NSMutableArray *parsedOnlyIdentifiers = nil;
    NSMutableArray *parsedSkipIdentifiers = nil;
    BOOL usingAppleStyleFilters = (legacyTestNames == nil);
    BOOL usingAnyFilters = NO;

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
                    return NO;
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
                    return NO;
                }

                [parsedSkipIdentifiers addObject:components];
            }
        }

        if (usingAnyFilters && ([targetName length] == 0))
        {
            NSLog(@"XCTest: A target name is required when using -only-testing or -skip-testing filters.");
            return NO;
        }
    }

    [runLock lock];
    
    NSLog(@"XCTest: Running Unit Tests");
    NSUInteger testCaseFailureCount = 0;
    NSUInteger testCaseSuccessCount = 0;
    NSUInteger selectedTestCount = 0;
    NSUInteger totalSkipCount = 0;
    
    NSArray *testCaseClasses = [ClassGetSubclasses([XCTestCase class])
        sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
            return [NSStringFromClass(a) compare:NSStringFromClass(b)];
        }];
    for (Class testCaseClass in testCaseClasses)
    {
        @autoreleasepool {
            NSString *className = NSStringFromClass(testCaseClass);
            NSUInteger methodFailureCount = 0;
            NSUInteger methodSuccessCount = 0;
            NSUInteger methodSkipCount = 0;
            BOOL classTearDownFailed = NO;
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

            selectedTestCount += [selectedMethodNames count];

            if ([selectedMethodNames count] > 0)
            {
                NSLog(@"XCTest:   Running %@", className);

                BOOL classSetUpSucceeded = [self runClassMethod:@selector(setUp)
                                                        ofClass:testCaseClass];

                for (NSString *methodName in selectedMethodNames)
                {
                    if (!classSetUpSucceeded)
                    {
                        NSLog(@"XCTest:     %@ FAILED, +setUp failed", methodName);
                        methodFailureCount++;
                    }
                    else
                    {
                        switch ([self runTestMethod:methodName ofClass:testCaseClass])
                        {
                            case GSXCTestResultPassed:
                                methodSuccessCount++;
                                break;
                            case GSXCTestResultSkipped:
                                methodSkipCount++;
                                break;
                            case GSXCTestResultFailed:
                                methodFailureCount++;
                                break;
                        }
                    }
                }

                if (classSetUpSucceeded
                    && ![self runClassMethod:@selector(tearDown) ofClass:testCaseClass])
                {
                    classTearDownFailed = YES;
                }
            }
            
            NSString *skippedSuffix = methodSkipCount > 0
                ? [NSString stringWithFormat:@", %lu skipped", (unsigned long)methodSkipCount]
                : @"";
            totalSkipCount += methodSkipCount;

            if ([selectedMethodNames count] == 0) {
                NSLog(@"XCTest:   %@ SKIPPED", className);
            }
            else if (methodFailureCount > 0) {
                testCaseFailureCount++;
                NSLog(@"XCTest:   %@: %lu/%lu tests FAILED%@", className, methodFailureCount, [selectedMethodNames count], skippedSuffix);
            }
            else if (classTearDownFailed) {
                testCaseFailureCount++;
                NSLog(@"XCTest:   %@: %lu tests passed%@, +tearDown FAILED", className, methodSuccessCount, skippedSuffix);
            } else {
                testCaseSuccessCount++;
                NSLog(@"XCTest:   %@: %lu tests PASSED%@", className, methodSuccessCount, skippedSuffix);
            }
        } // @autoreleasepool
    }
    
    if (testCaseSuccessCount == 0 && testCaseFailureCount == 0) {
        if (usingAppleStyleFilters && usingAnyFilters && selectedTestCount == 0) {
            NSLog(@"XCTest: No tests matched the provided filters.");
        } else {
            NSLog(@"XCTest: No tests found.");
        }
    }
    else if (testCaseFailureCount > 0) {
        NSLog(@"XCTest: %lu/%lu test cases FAILED%@", testCaseFailureCount, testCaseFailureCount + testCaseSuccessCount, GSSkippedSummary(totalSkipCount));
    } else {
        NSLog(@"XCTest: %lu tests PASSED%@", testCaseSuccessCount, GSSkippedSummary(totalSkipCount));
    }
    
    [runLock unlock];
    
    return testCaseFailureCount == 0;
}

- (BOOL)runClassMethod:(SEL)selector ofClass:(Class)testCaseClass
{
    BOOL succeeded = YES;

    assertionFailureCount = 0;
    @try {
        [testCaseClass performSelector:selector];
    }
    @catch (NSException *exception) {
        NSLog(@"XCTest:   %@ +%@ threw exception: %@",
            NSStringFromClass(testCaseClass), NSStringFromSelector(selector), exception);
        succeeded = NO;
    }

    if (assertionFailureCount > 0) {
        succeeded = NO;
    }

    if (!succeeded) {
        NSLog(@"XCTest:   %@ +%@ FAILED", NSStringFromClass(testCaseClass), NSStringFromSelector(selector));
    }

    return succeeded;
}

- (GSXCTestResult)runTestMethod:(NSString *)methodName ofClass:(Class)testCaseClass
{
    GSXCTestResult result = GSXCTestResultPassed;

    NSLog(@"XCTest:     %@...", methodName);

    @autoreleasepool {
        SEL selector = NSSelectorFromString(methodName);
        XCTestCase *testCase = [[[testCaseClass alloc] init] autorelease];
        void (^teardownBlock)(void) = nil;

        assertionFailureCount = 0;
        [skipReason release];
        skipReason = nil;

        BOOL setUpSucceeded = [self runPhase:@"setUpWithError:" ofTest:methodName block:^BOOL(NSError **error) {
            return [testCase setUpWithError:error];
        }];

        if (setUpSucceeded) {
            setUpSucceeded = [self runPhase:@"setUp" ofTest:methodName block:^BOOL(NSError **error) {
                [testCase setUp];
                return YES;
            }];
        }

        if (setUpSucceeded) {
            [self runPhase:nil ofTest:methodName block:^BOOL(NSError **error) {
                ((void (*)(id, SEL))[testCase methodForSelector:selector])(testCase, selector);
                return YES;
            }];
        }

        // Teardown always runs, whether or not set up or the test failed.
        while ((teardownBlock = [testCase _gsPopTeardownBlock]) != nil) {
            [self runPhase:@"a teardown block" ofTest:methodName block:^BOOL(NSError **error) {
                teardownBlock();
                return YES;
            }];
        }

        [self runPhase:@"tearDown" ofTest:methodName block:^BOOL(NSError **error) {
            [testCase tearDown];
            return YES;
        }];

        [self runPhase:@"tearDownWithError:" ofTest:methodName block:^BOOL(NSError **error) {
            return [testCase tearDownWithError:error];
        }];

        // A failure outranks a skip, as in Apple's XCTest.
        if (assertionFailureCount > 0) {
            result = GSXCTestResultFailed;
        } else if (skipReason != nil) {
            result = GSXCTestResultSkipped;
        }
    }

    if (result == GSXCTestResultFailed) {
        NSLog(@"XCTest:     %@ FAILED", methodName);
    } else if (result == GSXCTestResultSkipped) {
        NSLog(@"XCTest:     %@ SKIPPED %@", methodName, skipReason);
    }

    [skipReason release];
    skipReason = nil;

    return result;
}

- (BOOL)runPhase:(NSString *)phaseName
          ofTest:(NSString *)methodName
           block:(BOOL (^)(NSError **error))block
{
    NSString *where = phaseName ? [NSString stringWithFormat:@" in %@", phaseName] : @"";
    NSError *error = nil;
    BOOL succeeded = NO;

    @try {
        succeeded = block(&error);
        if (!succeeded) {
            NSLog(@"XCTest:     %@ failed%@ - %@", methodName, where,
                error ? [error localizedDescription] : @"returned NO without an error");
            [self registerAssertionFailed];
        }
    }
    @catch (_XCTSkipFailureException *skip) {
        // Remaining set up and the test body are skipped; teardown still runs.
        if (skipReason == nil) {
            skipReason = [[skip reason] copy];
        }
    }
    @catch (_XCTestCaseInterruptionException *interruption) {
        // continueAfterFailure is NO; the failure has already been reported.
    }
    @catch (NSException *exception) {
        NSLog(@"XCTest:     %@ threw exception%@: %@", methodName, where, exception);
        [self registerAssertionFailed];
    }

    return succeeded;
}

- (void)waitForCompletion
{
    [runLock lock];
    [runLock unlock];
}

- (void)registerAssertionFailed
{
    @synchronized (self) {
        assertionFailureCount++;
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
