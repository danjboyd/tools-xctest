//
//  GSXCTestRunner.m
//  Eggplant
//
//  Created by Adam Fox on 9/17/18.
//  Copyright © 2018 TestPlant, Inc. All rights reserved.
//

#import <GSXCTestRunner.h>
#import <XCTest/XCTestCase.h>
#import <objc/runtime.h>

static NSArray *TestClassNames(void)
{
    int capacity = 0, count = 0;
    Class *classes = NULL;
    do {
        capacity = objc_getClassList(NULL, 0);
        free(classes);
        classes = calloc(MAX(capacity, 1), sizeof(Class));
        if (!classes) [NSException raise:NSMallocException format:@"Cannot enumerate test classes"];
        count = objc_getClassList(classes, capacity);
    } while (count > capacity);
    NSMutableArray *names = [NSMutableArray array];
    for (int i = 0; i < count; i++) {
        for (Class parent = class_getSuperclass(classes[i]); parent; parent = class_getSuperclass(parent)) {
            if (parent == [XCTestCase class]) {
                [names addObject:NSStringFromClass(classes[i])];
                break;
            }
        }
    }
    free(classes);
    return [names sortedArrayUsingSelector:@selector(compare:)];
}

@implementation GSXCTestRunner
- (id)init
{
    if ((self = [super init])) runLock = [[NSLock alloc] init];
    return self;
}
- (void)dealloc
{
    [runLock release];
    [super dealloc];
}
- (BOOL)runAll { return [self runTestsNamed:nil]; }

- (BOOL)runTestsNamed:(NSArray *)testNames
{
    [runLock lock];
    NSUInteger successes = 0, failures = 0, suiteFailures = 0;
    NSMutableSet *matched = [NSMutableSet set];
    @try {
        NSLog(@"XCTest: Running Unit Tests");
        for (NSString *className in TestClassNames()) {
            @autoreleasepool {
                Class cls = NSClassFromString(className);
                NSMutableArray *selected = [NSMutableArray array];
                for (NSInvocation *invocation in [cls testInvocations]) {
                    NSString *fullName = [NSString stringWithFormat:@"%@.%@", className,
                        NSStringFromSelector([invocation selector])];
                    BOOL enabled = testNames == nil;
                    for (NSString *filter in testNames) {
                        if ([filter isEqual:className] || [filter isEqual:fullName]) {
                            enabled = YES;
                            [matched addObject:filter];
                        }
                    }
                    if (enabled) [selected addObject:invocation];
                }
                if (![selected count]) continue;
                NSLog(@"XCTest:   Running %@", className);
                @try {
                    [cls setUp];
                    for (NSInvocation *invocation in selected) {
                        @autoreleasepool {
                            XCTestCase *test = [cls testCaseWithInvocation:invocation];
                            [test invokeTest];
                            if ([test failureCount]) failures++; else successes++;
                            NSLog(@"XCTest:     %@ %@", [test name], [test failureCount] ? @"FAILED" : @"PASSED");
                        }
                    }
                }
                @catch (id exception) {
                    suiteFailures++;
                    NSLog(@"XCTest:   %@ FAILED, threw %@", className, exception);
                }
                @finally {
                    @try { [cls tearDown]; }
                    @catch (id exception) {
                        suiteFailures++;
                        NSLog(@"XCTest:   %@ tearDown FAILED, threw %@", className, exception);
                    }
                }
            }
        }
        for (NSString *filter in testNames) {
            if (![matched containsObject:filter]) {
                suiteFailures++;
                NSLog(@"XCTest: No tests matched %@", filter);
            }
        }
    }
    @catch (id exception) {
        suiteFailures++;
        NSLog(@"XCTest: Test discovery or execution FAILED: %@", exception);
    }
    @finally { [runLock unlock]; }
    NSLog(@"XCTest: %lu tests executed, %lu failed, %lu suite errors",
        (unsigned long)(successes + failures), (unsigned long)failures, (unsigned long)suiteFailures);
    if (successes + failures == 0) NSLog(@"XCTest: No tests executed.");
    return successes + failures > 0 && failures == 0 && suiteFailures == 0;
}
- (void)waitForCompletion
{
    [runLock lock];
    [runLock unlock];
}
+ (GSXCTestRunner *)sharedRunner
{
    static GSXCTestRunner *runner = nil;
    @synchronized (self) {
        if (!runner) runner = [[GSXCTestRunner alloc] init];
    }
    return runner;
}
@end
