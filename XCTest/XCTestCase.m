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

#import <XCTest/XCTestCase.h>
#import <XCTest/XCTestPrivate.h>
#import <XCTest/XCTestAssertionsImpl.h>

#import <objc/runtime.h>

// The test being run. Not retained; cleared after each test.
static XCTestCase *GSCurrentTestCase = nil;

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

@implementation XCTestCase

@synthesize continueAfterFailure = _continueAfterFailure;

+ (NSArray *) testInvocations
{
    NSMutableArray *invocations = [NSMutableArray array];

    for (NSString *methodName in GSTestMethodNames(self)) {
        SEL selector = NSSelectorFromString(methodName);
        NSMethodSignature *signature = [self instanceMethodSignatureForSelector:selector];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];

        [invocation setSelector:selector];
        [invocations addObject:invocation];
    }

    return invocations;
}

+ (XCTestSuite *) defaultTestSuite
{
    GSXCTestCaseSuite *suite = [GSXCTestCaseSuite suiteForTestCaseClass:self];

    for (NSInvocation *invocation in [self testInvocations]) {
        [suite addTest:[self testCaseWithInvocation:invocation]];
    }

    return suite;
}

+ (id) testCaseWithInvocation: (NSInvocation *)invocation
{
    return [[[self alloc] initWithInvocation:invocation] autorelease];
}

+ (id) testCaseWithSelector: (SEL)selector
{
    return [[[self alloc] initWithSelector:selector] autorelease];
}

+ (void) setUp
{
}

+ (void) tearDown
{
}

- (id) init
{
    return [self initWithInvocation:nil];
}

- (id) initWithInvocation: (NSInvocation *)invocation
{
    self = [super init];
    if (self) {
        _continueAfterFailure = YES;
        _invocation = [invocation retain];
    }

    return self;
}

- (id) initWithSelector: (SEL)selector
{
    NSMethodSignature *signature = [[self class] instanceMethodSignatureForSelector:selector];
    NSInvocation *invocation = nil;

    if (signature != nil) {
        invocation = [NSInvocation invocationWithMethodSignature:signature];
        [invocation setSelector:selector];
    }

    return [self initWithInvocation:invocation];
}

- (void) dealloc
{
    [self _gsInvalidateExpectations];
    [_teardownBlocks release];
    [_invocation release];
    [super dealloc];
}

- (NSInvocation *) invocation
{
    return [[_invocation retain] autorelease];
}

- (void) setInvocation: (NSInvocation *)invocation
{
    if (invocation != _invocation) {
        [_invocation release];
        _invocation = [invocation retain];
    }
}

- (NSString *) name
{
    return [NSString stringWithFormat:@"-[%@ %@]", NSStringFromClass([self class]), [self _gsMethodName]];
}

- (NSUInteger) testCaseCount
{
    return 1;
}

- (Class) testRunClass
{
    return [XCTestCaseRun class];
}

- (void) recordFailureWithDescription: (NSString *)description
                               inFile: (NSString *)filePath
                               atLine: (NSUInteger)lineNumber
                             expected: (BOOL)expected
{
    if ([self testRun] != nil) {
        [[self testRun] recordFailureWithDescription:description
                                              inFile:filePath
                                              atLine:lineNumber
                                            expected:expected];
    } else {
        NSLog(@"XCTest: Failure in %@, which is not running: %@", [self name], description);
    }

    _XCTInterruptIfNeeded(self);
}

// Records a failure without letting continueAfterFailure = NO stop the
// test, for failures found while already handling an exception.
- (void) _gsRecordFailure: (NSString *)description expected: (BOOL)expected
{
    @try {
        [self recordFailureWithDescription:description inFile:nil atLine:0 expected:expected];
    }
    @catch (_XCTestCaseInterruptionException *interruption) {
    }
}

- (void) _gsRecordSkip: (_XCTSkipFailureException *)skip
{
    NSDictionary *info = [skip userInfo];

    [(XCTestCaseRun *)[self testRun] _gsRecordSkip:
        [GSXCTestIssue issueWithMessage:[info objectForKey:@"message"]
                               filePath:[info objectForKey:@"file"]
                             lineNumber:[[info objectForKey:@"line"] unsignedIntegerValue]
                             unexpected:NO]];
}

// Runs one step of a test. A skip, a failure that stops the test, or an
// exception ends the step; returns NO if so (or if it returned NO).
- (BOOL) _gsRunPhase: (NSString *)phaseName block: (BOOL (^)(NSError **error))block
{
    NSString *where = phaseName ? [NSString stringWithFormat:@" in %@", phaseName] : @"";
    NSError *error = nil;
    BOOL succeeded = NO;

    @try {
        succeeded = block(&error);
        if (!succeeded) {
            [self _gsRecordFailure:[NSString stringWithFormat:@"failed%@ - %@", where,
                                       error ? [error localizedDescription] : @"returned NO without an error"]
                          expected:YES];
        }
    }
    @catch (_XCTSkipFailureException *skip) {
        // Remaining set up and the test body are skipped; teardown still runs.
        [self _gsRecordSkip:skip];
    }
    @catch (_XCTestCaseInterruptionException *interruption) {
        // continueAfterFailure is NO; the failure has already been recorded.
    }
    @catch (NSException *exception) {
        [self _gsRecordFailure:[NSString stringWithFormat:@"threw exception%@: %@", where,
                                   _GSXCTDescribeException(exception)]
                      expected:NO];
    }

    return succeeded;
}

- (void) _gsInvokeTestMethod
{
    SEL selector = [_invocation selector];

    if (_invocation == nil) {
        return;
    }

    // Plain test methods are called directly; anything else (e.g. a custom
    // invocation with arguments) goes through NSInvocation.
    if ([[_invocation methodSignature] numberOfArguments] == 2) {
        ((void (*)(id, SEL))[self methodForSelector:selector])(self, selector);
    } else {
        [_invocation invokeWithTarget:self];
    }
}

- (void) invokeTest
{
    void (^teardownBlock)(void) = nil;

    BOOL setUpSucceeded = [self _gsRunPhase:@"setUpWithError:" block:^BOOL(NSError **error) {
        return [self setUpWithError:error];
    }];

    if (setUpSucceeded) {
        setUpSucceeded = [self _gsRunPhase:@"setUp" block:^BOOL(NSError **error) {
            [self setUp];
            return YES;
        }];
    }

    if (setUpSucceeded) {
        BOOL testCompleted = [self _gsRunPhase:nil block:^BOOL(NSError **error) {
            [self _gsInvokeTestMethod];
            return YES;
        }];

        // Only a test that ran to the end could have waited on everything.
        if (testCompleted) {
            [self _gsRunPhase:nil block:^BOOL(NSError **error) {
                [self _gsRecordUnwaitedExpectations];
                return YES;
            }];
        }
    }

    // Teardown always runs, whether or not set up or the test failed.
    while ((teardownBlock = [self _gsPopTeardownBlock]) != nil) {
        [self _gsRunPhase:@"a teardown block" block:^BOOL(NSError **error) {
            teardownBlock();
            return YES;
        }];
    }

    [self _gsRunPhase:@"tearDown" block:^BOOL(NSError **error) {
        [self tearDown];
        return YES;
    }];

    [self _gsRunPhase:@"tearDownWithError:" block:^BOOL(NSError **error) {
        return [self tearDownWithError:error];
    }];
}

- (void) performTest: (XCTestRun *)run
{
    XCTestCase *previous = GSCurrentTestCase;

    [self _gsSetTestRun:run];
    GSCurrentTestCase = self;
    [run start];

    @autoreleasepool {
        // invokeTest handles its own failures; this catches anything an
        // overriding invokeTest lets escape.
        @try {
            [self invokeTest];
        }
        @catch (_XCTSkipFailureException *skip) {
            [self _gsRecordSkip:skip];
        }
        @catch (_XCTestCaseInterruptionException *interruption) {
        }
        @catch (NSException *exception) {
            [self _gsRecordFailure:[NSString stringWithFormat:@"threw exception: %@",
                                       _GSXCTDescribeException(exception)]
                          expected:NO];
        }

        [self _gsInvalidateExpectations];
    }

    [run stop];
    GSCurrentTestCase = previous;
}

- (void) addTeardownBlock: (void (^)(void))block
{
    if (block == nil) {
        return;
    }

    @synchronized (self) {
        if (_teardownBlocks == nil) {
            _teardownBlocks = [[NSMutableArray alloc] init];
        }
        void (^copiedBlock)(void) = [block copy];
        [_teardownBlocks addObject:copiedBlock];
        [copiedBlock release];
    }
}

@end

@implementation XCTestCase (GSXCTestRunnerPrivate)

+ (XCTestCase *) _gsCurrentTestCase
{
    return GSCurrentTestCase;
}

+ (void) _gsSetCurrentTestCase: (XCTestCase *)testCase
{
    GSCurrentTestCase = testCase;
}

- (NSString *) _gsMethodName
{
    return _invocation ? NSStringFromSelector([_invocation selector]) : @"(no test method)";
}

- (void) _gsFailWithoutRunning: (GSXCTestIssue *)cause
{
    XCTestRun *run = [[[self testRunClass] alloc] initWithTest:self];

    [self _gsSetTestRun:run];
    [run start];
    [run recordFailureWithDescription:[NSString stringWithFormat:@"+setUp failed: %@", [cause message]]
                               inFile:[cause filePath]
                               atLine:[cause lineNumber]
                             expected:![cause unexpected]];
    [run stop];
    [run release];
}

- (void (^)(void)) _gsPopTeardownBlock
{
    void (^block)(void) = nil;

    @synchronized (self) {
        block = [[[_teardownBlocks lastObject] retain] autorelease];
        if (block != nil) {
            [_teardownBlocks removeLastObject];
        }
    }

    return block;
}

@end
