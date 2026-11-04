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
#import <XCTest/GSXCTestSwiftOverlay.h>
#import <XCTest/XCTestPrivate.h>
#import <XCTest/XCTestAssertionsImpl.h>

#import <objc/runtime.h>
#include <string.h>

GSXCTestIssue *_GSXCTIssueForSkip(_XCTSkipFailureException *skip)
{
    NSDictionary *info = [skip userInfo];

    return [GSXCTestIssue issueWithMessage:[info objectForKey:@"message"]
                                  filePath:[info objectForKey:@"file"]
                                lineNumber:[[info objectForKey:@"line"] unsignedIntegerValue]
                                unexpected:NO];
}

// The test being run. Not retained; cleared after each test.
static XCTestCase *GSCurrentTestCase = nil;

// Whether a method returns one of the given type encodings ("v" for void).
// Like Apple, only void methods are tests; this skips getters such as a
// testData property, which also must not be called through a void cast.
static BOOL GSReturnsType(Method method, const char *const *encodings)
{
    char *returnType = method_copyReturnType(method);
    const char *type = returnType;
    BOOL matches = NO;

    if (type != NULL) {
        // Skip qualifiers such as oneway ('V').
        while (*type != '\0' && strchr("rnNoORV", *type) != NULL) {
            type++;
        }
        for (; *encodings != NULL && !matches; encodings++) {
            matches = strcmp(type, *encodings) == 0;
        }
    }
    free(returnType);

    return matches;
}

static const char *const GSVoidEncodings[] = { "v", NULL };
// BOOL's encoding varies by target and runtime; Swift's Bool may be a C99 bool.
static const char *const GSBoolEncodings[] = { @encode(BOOL), "B", NULL };

// A Swift test method that throws, `func testFoo() throws`, reaches the
// runtime as -(BOOL)testFooAndReturnError:(NSError **)error.
static NSString *const GSThrowingTestSuffix = @"AndReturnError:";

static BOOL GSIsThrowingTestName(NSString *methodName)
{
    return [methodName hasSuffix:GSThrowingTestSuffix];
}

// A Swift `func testFoo() async` reaches the runtime as
// -(void)testFooWithCompletionHandler:(void (^)(void))completion, and an
// `async throws` one with a completion block taking an NSError *.
static NSString *const GSAsyncTestSuffix = @"WithCompletionHandler:";

static BOOL GSIsAsyncTestName(NSString *methodName)
{
    return [methodName hasSuffix:GSAsyncTestSuffix];
}

static BOOL GSIsBlockType(const char *type)
{
    // Skip qualifiers, as for return types.
    while (type != NULL && *type != '\0' && strchr("rnNoORV", *type) != NULL) {
        type++;
    }
    return type != NULL && type[0] == '@' && type[1] == '?';
}

// Whether an async test's completion block takes an NSError * (async
// throws). Only an extended block signature says so: @?<v@?@"NSError">, as
// gnustep-swift's toolchain emits it, or @?<v@?@> (class_addMethod can't
// take @"..." in libobjc2);
// without one the block is called as void (^)(void), which is safe either
// way: a block given an argument it doesn't read ignores it, but one that
// reads an argument it wasn't given reads garbage.
static BOOL GSAsyncCompletionTakesError(Class cls, SEL selector)
{
    Method method = class_getInstanceMethod(cls, selector);
    const char *types = method ? method_getTypeEncoding(method) : NULL;
    const char *signature = types ? strstr(types, "@?<") : NULL;

    if (signature == NULL) {
        return NO;
    }
    // <return type, the block itself (@?), then its parameters>
    signature += 3;
    if (*signature == 'v') {
        signature++;
    }
    while (*signature >= '0' && *signature <= '9') {
        signature++;
    }
    if (strncmp(signature, "@?", 2) == 0) {
        signature += 2;
    }
    while (*signature >= '0' && *signature <= '9') {
        signature++;
    }
    return *signature != '>' && *signature != '\0';
}

static BOOL GSIsTestSignature(NSMethodSignature *signature, NSString *methodName)
{
    const char *const *encodings = NULL;

    if (signature == nil) {
        return NO;
    }
    if ([signature numberOfArguments] == 2) {
        return strcmp([signature methodReturnType], @encode(void)) == 0;
    }
    if ([signature numberOfArguments] == 3 && GSIsAsyncTestName(methodName)) {
        return GSIsBlockType([signature getArgumentTypeAtIndex:2])
            && strcmp([signature methodReturnType], @encode(void)) == 0;
    }
    if ([signature numberOfArguments] != 3 || !GSIsThrowingTestName(methodName)
        || [signature getArgumentTypeAtIndex:2][0] != '^') {
        return NO;
    }
    for (encodings = GSBoolEncodings; *encodings != NULL; encodings++) {
        if (strcmp([signature methodReturnType], *encodings) == 0) {
            return YES;
        }
    }
    return NO;
}

static BOOL GSIsTestMethod(Method method, NSString *methodName)
{
    if (![methodName hasPrefix:@"test"]) {
        return NO;
    }
    if (method_getNumberOfArguments(method) == 2) {
        return GSReturnsType(method, GSVoidEncodings);
    }
    if (method_getNumberOfArguments(method) == 3 && GSIsAsyncTestName(methodName)) {
        char *argumentType = method_copyArgumentType(method, 2);
        BOOL isBlock = GSIsBlockType(argumentType);

        free(argumentType);
        return isBlock && GSReturnsType(method, GSVoidEncodings);
    }
    if (method_getNumberOfArguments(method) == 3 && GSIsThrowingTestName(methodName)) {
        char *argumentType = method_copyArgumentType(method, 2);
        BOOL isErrorPointer = argumentType != NULL && argumentType[0] == '^';

        free(argumentType);
        return isErrorPointer && GSReturnsType(method, GSBoolEncodings);
    }
    return NO;
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

            if (GSIsTestMethod(method, methodName))
            {
                [names addObject:methodName];
            }
        }

        free(methods);
    }

    return [[names allObjects] sortedArrayUsingSelector:@selector(compare:)];
}

// Whether an async test's completion block has been called, and with what
// error. The block may be called on any thread.
@interface GSXCTAsyncCompletion : NSObject
{
    BOOL _finished;
    NSError *_error;
}
- (void)finishWithError:(NSError *)error;
- (BOOL)isFinished;
- (NSError *)error;
@end

@implementation GSXCTAsyncCompletion

- (void)dealloc
{
    [_error release];
    [super dealloc];
}

- (void)finishWithError:(NSError *)error
{
    @synchronized (self) {
        if (!_finished) {
            _finished = YES;
            _error = [error retain];
        }
    }
}

- (BOOL)isFinished
{
    @synchronized (self) {
        return _finished;
    }
}

- (NSError *)error
{
    @synchronized (self) {
        return [[_error retain] autorelease];
    }
}

@end

@implementation XCTestCase

@synthesize continueAfterFailure = _continueAfterFailure;

+ (NSArray *)testInvocations
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

+ (XCTestSuite *)defaultTestSuite
{
    GSXCTestCaseSuite *suite = [GSXCTestCaseSuite suiteForTestCaseClass:self];

    for (NSInvocation *invocation in [self testInvocations]) {
        [suite addTest:[self testCaseWithInvocation:invocation]];
    }

    return suite;
}

+ (instancetype)testCaseWithInvocation:(NSInvocation *)invocation
{
    return [[[self alloc] initWithInvocation:invocation] autorelease];
}

+ (instancetype)testCaseWithSelector:(SEL)selector
{
    return [[[self alloc] initWithSelector:selector] autorelease];
}

- (void)setUpWithCompletionHandler:(void (^)(NSError *error))completion
{
    completion(nil);
}

- (void)tearDownWithCompletionHandler:(void (^)(NSError *error))completion
{
    completion(nil);
}

+ (void)setUp
{
}

+ (void)tearDown
{
}

- (instancetype)init
{
    return [self initWithInvocation:nil];
}

- (instancetype)initWithInvocation:(NSInvocation *)invocation
{
    self = [super init];
    if (self) {
        _continueAfterFailure = YES;
        _invocation = [invocation retain];
    }

    return self;
}

- (instancetype)initWithSelector:(SEL)selector
{
    NSMethodSignature *signature = [[self class] instanceMethodSignatureForSelector:selector];
    NSInvocation *invocation = nil;

    // A test method takes no arguments and returns void, or is a throwing
    // test (see GSIsThrowingTestName).
    if (!GSIsTestSignature(signature, NSStringFromSelector(selector))) {
        [self release];
        [NSException raise:NSInvalidArgumentException
                    format:@"Invalid test selector %@", NSStringFromSelector(selector)];
        return nil;
    }
    invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setSelector:selector];

    return [self initWithInvocation:invocation];
}

- (void)dealloc
{
    [self _gsInvalidateExpectations];
    [_teardownBlocks release];
    [_invocation release];
    [_expectedFailureScopes release];
    [_gsPerformance release];
    [_gsReportResult release];
    [super dealloc];
}

- (NSTimeInterval)executionTimeAllowance
{
    return _executionTimeAllowance > 0 ? _executionTimeAllowance : _GSXCTDefaultExecutionTimeAllowance();
}

- (void)setExecutionTimeAllowance:(NSTimeInterval)executionTimeAllowance
{
    _executionTimeAllowance = executionTimeAllowance;
    _GSXCTWatchdogAllowanceDidChange();
}

- (NSInvocation *)invocation
{
    return [[_invocation retain] autorelease];
}

- (void)setInvocation:(NSInvocation *)invocation
{
    if (invocation != _invocation) {
        [_invocation release];
        _invocation = [invocation retain];
    }
}

- (NSUInteger)failureCount
{
    return [[self testRun] totalFailureCount];
}

- (NSString *)name
{
    return [NSString stringWithFormat:@"-[%@ %@]", NSStringFromClass([self class]), [self _gsMethodName]];
}

- (NSUInteger)testCaseCount
{
    return 1;
}

- (Class)testRunClass
{
    return [XCTestCaseRun class];
}

// While an issue is passed through an override of the legacy
// -recordFailureWithDescription:..., the test and issue involved, so the
// two methods don't call each other in a loop.
static __thread XCTestCase *GSLegacyRecordingTest = nil;
static __thread XCTIssue *GSLegacyRecordingIssue = nil;

- (BOOL)_gsOverridesLegacyRecordFailure
{
    SEL selector = @selector(recordFailureWithDescription:inFile:atLine:expected:);

    return [self methodForSelector:selector] != [XCTestCase instanceMethodForSelector:selector];
}

- (void)recordIssue:(XCTIssue *)issue
{
    if (GSLegacyRecordingTest != self && [self _gsOverridesLegacyRecordFailure]) {
        XCTestCase *previousTest = GSLegacyRecordingTest;
        XCTIssue *previousIssue = GSLegacyRecordingIssue;

        GSLegacyRecordingTest = self;
        GSLegacyRecordingIssue = issue;
        @try {
            [self recordFailureWithDescription:[issue compactDescription]
                                        inFile:_GSXCTIssueFilePath(issue)
                                        atLine:_GSXCTIssueLineNumber(issue)
                                      expected:!_GSXCTIssueIsUnexpected(issue)];
        }
        @finally {
            GSLegacyRecordingTest = previousTest;
            GSLegacyRecordingIssue = previousIssue;
        }
        return;
    }

    [self _gsRecordIssue:issue];
}

- (void)recordFailureWithDescription:(NSString *)description
                               inFile:(NSString *)filePath
                               atLine:(NSUInteger)lineNumber
                             expected:(BOOL)expected
{
    XCTestCase *previousTest = GSLegacyRecordingTest;
    XCTIssue *previousIssue = GSLegacyRecordingIssue;
    XCTIssue *issue = nil;

    if (GSLegacyRecordingTest == self && GSLegacyRecordingIssue != nil) {
        // Called by an override that -recordIssue: went through: record
        // the original issue, with any changes the override made.
        XCTMutableIssue *changed = [[GSLegacyRecordingIssue mutableCopy] autorelease];

        if (![description isEqualToString:[changed compactDescription]]) {
            [changed setCompactDescription:description];
            [changed setDetailedDescription:nil];
        }
        if (filePath != _GSXCTIssueFilePath(changed) || lineNumber != _GSXCTIssueLineNumber(changed)) {
            [changed setSourceCodeContext:[_GSXCTMakeIssue([changed type], description, filePath, lineNumber, nil)
                                              sourceCodeContext]];
        }
        if (expected == _GSXCTIssueIsUnexpected(changed)) {
            [changed setType:expected ? XCTIssueTypeAssertionFailure : XCTIssueTypeUncaughtException];
        }
        // Once only: a second call from the same override is a new issue.
        GSLegacyRecordingIssue = nil;
        [self _gsRecordIssue:changed];
        return;
    }

    issue = _GSXCTMakeIssue(expected ? XCTIssueTypeAssertionFailure : XCTIssueTypeUncaughtException,
                            description, filePath, lineNumber, nil);
    // An override of this method has already seen the issue.
    GSLegacyRecordingTest = self;
    GSLegacyRecordingIssue = nil;
    @try {
        [self recordIssue:issue];
    }
    @finally {
        GSLegacyRecordingTest = previousTest;
        GSLegacyRecordingIssue = previousIssue;
    }
}

// Where -recordIssue: ends up: reports the issue as expected, or records
// it in the run and stops the test if it shouldn't continue.
- (void)_gsRecordIssue:(XCTIssue *)issue
{
    GSXCTestIssue *failure = [GSXCTestIssue issueWithXCTIssue:issue];

    for (XCTAttachment *attachment in [issue attachments]) {
        _GSXCTAddAttachment(self, attachment, [failure activityPath]);
    }

    // Failures inside XCTExpectFailure are reported, but neither fail nor
    // stop the test.
    if ([self _gsAbsorbExpectedFailure:failure]) {
        return;
    }

    if ([self testRun] != nil) {
        [[self testRun] recordIssue:issue];
    } else {
        NSLog(@"XCTest: Failure in %@, which is not running: %@", [self name], [issue compactDescription]);
    }

    _XCTInterruptIfNeeded(self);
}

// Records an issue without letting continueAfterFailure = NO stop the
// test, for failures found while already handling an exception.
- (void)_gsRecordIssueWithoutInterrupting:(XCTIssue *)issue
{
    @try {
        [self recordIssue:issue];
    }
    @catch (_XCTestCaseInterruptionException *interruption) {
    }
}

- (void)_gsRecordException:(NSException *)exception where:(NSString *)where
{
    [self _gsRecordIssueWithoutInterrupting:
        _GSXCTMakeIssue(XCTIssueTypeUncaughtException,
                        [NSString stringWithFormat:@"threw exception%@: %@", where, _GSXCTDescribeException(exception)],
                        nil, 0, nil)];
}

- (void)_gsRecordSkip:(_XCTSkipFailureException *)skip
{
    [(XCTestCaseRun *)[self testRun] _gsRecordSkip:_GSXCTIssueForSkip(skip)];
}

// Runs one step of a test. A skip, a failure that stops the test, or an
// exception ends the step; returns NO if so (or if it returned NO).
- (BOOL)_gsRunPhase:(NSString *)phaseName block:(BOOL (^)(NSError **error))block
{
    NSString *where = phaseName ? [NSString stringWithFormat:@" in %@", phaseName] : @"";
    NSError *error = nil;
    BOOL succeeded = NO;

    @try {
        succeeded = block(&error);
        if (!succeeded && [[error domain] isEqualToString:@"" _XCT_CONTROL_FLOW_ERROR_DOMAIN]) {
            // Swift's XCTSkip and XCTUnwrap (see XCTestAssertionsImpl.h).
            if ([error code] == _XCTControlFlowCodeSkip) {
                // userInfo can be missing: e.g. in a Swift image linked
                // without swiftrt.o, CustomNSError's userInfo is lost.
                NSDictionary *info = [error userInfo];
                NSString *message = [info objectForKey:@"message"];

                [(XCTestCaseRun *)[self testRun] _gsRecordSkip:
                    [GSXCTestIssue issueWithMessage:([message length] > 0 ? message : @"Test skipped")
                                           filePath:[info objectForKey:@"file"]
                                         lineNumber:[[info objectForKey:@"line"] unsignedIntegerValue]
                                         unexpected:NO]];
            } else if ([error code] != _XCTControlFlowCodeAlreadyRecorded) {
                [self _gsRecordIssueWithoutInterrupting:
                    _GSXCTMakeIssue(XCTIssueTypeThrownError,
                                    [NSString stringWithFormat:@"failed%@ - %@", where, [error localizedDescription]],
                                    nil, 0, error)];
            }
        } else if (!succeeded) {
            [self _gsRecordIssueWithoutInterrupting:
                _GSXCTMakeIssue(XCTIssueTypeThrownError,
                                [NSString stringWithFormat:@"failed%@ - %@", where,
                                    error ? [error localizedDescription] : @"returned NO without an error"],
                                nil, 0, error)];
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
        [self _gsRecordException:exception where:where];
    }

    return succeeded;
}

// Runs an async test (see GSIsAsyncTestName): calls it with a completion
// block, then runs the test thread's run loop until the block has been
// called, from whatever thread. There's no limit of its own: with timeouts
// enabled, the execution time allowance stops a test that never completes.
- (BOOL)_gsInvokeAsyncTestMethod:(SEL)selector error:(NSError **)error
{
    return [self _gsInvokeAsyncMethod:selector
                 completionTakesError:GSAsyncCompletionTakesError([self class], selector)
                                error:error];
}

- (BOOL)_gsInvokeAsyncMethod:(SEL)selector completionTakesError:(BOOL)takesError error:(NSError **)error
{
    GSXCTAsyncCompletion *completion = [[[GSXCTAsyncCompletion alloc] init] autorelease];
    IMP imp = [self methodForSelector:selector];

    if (takesError) {
        void (^block)(NSError *) = ^(NSError *completionError) {
            [completion finishWithError:completionError];
        };
        ((void (*)(id, SEL, id))imp)(self, selector, [[block copy] autorelease]);
    } else {
        void (^block)(void) = ^{
            [completion finishWithError:nil];
        };
        ((void (*)(id, SEL, id))imp)(self, selector, [[block copy] autorelease]);
    }

    return [self _gsWaitForAsyncCompletion:completion error:error];
}

// Runs the test thread's run loop until the completion has been called.
- (BOOL)_gsWaitForAsyncCompletion:(GSXCTAsyncCompletion *)completion error:(NSError **)error
{
    // A failure from here on can't stop the test (see _XCTRunLoopWaitWillStart):
    // the body carries on.
    _XCTRunLoopWaitWillStart();
    @try {
        while (![completion isFinished]) {
            @autoreleasepool {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                         beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
            }
        }
    }
    @finally {
        _XCTRunLoopWaitDidEnd();
        _XCTForgetStopDuringWait();
    }
    if ([completion error] != nil) {
        if (error != NULL) {
            *error = [completion error];
        }
        return NO;
    }
    return YES;
}

// Runs the test method. Returns NO, setting *error, when a throwing test
// (see GSIsThrowingTestName) returns NO, or an async one completes with an
// error.
- (BOOL)_gsInvokeTestMethod:(NSError **)error
{
    SEL selector = [_invocation selector];
    NSMethodSignature *signature = [_invocation methodSignature];

    if (_invocation == nil) {
        [NSException raise:NSInvalidArgumentException format:@"No valid test invocation configured"];
    }

    // Plain test methods are called directly; anything else (e.g. a custom
    // invocation with arguments) goes through NSInvocation.
    if ([signature numberOfArguments] == 2) {
        ((void (*)(id, SEL))[self methodForSelector:selector])(self, selector);
    } else if ([signature numberOfArguments] == 3
               && GSIsThrowingTestName(NSStringFromSelector(selector))
               && [signature methodReturnLength] == sizeof(BOOL)) {
        return ((BOOL (*)(id, SEL, NSError **))[self methodForSelector:selector])(self, selector, error);
    } else if ([signature numberOfArguments] == 3
               && GSIsAsyncTestName(NSStringFromSelector(selector))
               && GSIsBlockType([signature getArgumentTypeAtIndex:2])) {
        return [self _gsInvokeAsyncTestMethod:selector error:error];
    } else {
        [_invocation invokeWithTarget:self];
    }
    return YES;
}

- (void)invokeTest
{
    void (^teardownBlock)(void) = nil;

    // Called directly rather than from -performTest: (as -runTest does):
    // run the test in a run of its own, so its failures are counted.
    if ([self testRun] == nil || [[self testRun] stopDate] != nil) {
        [self runTest];
        return;
    }

    // As on Apple's platforms, the async set up comes first and the async
    // tear down last. Their completion blocks always take an error.
    BOOL setUpSucceeded = [self _gsRunPhase:@"setUpWithCompletionHandler:" block:^BOOL(NSError **error) {
        return [self _gsInvokeAsyncMethod:@selector(setUpWithCompletionHandler:)
                     completionTakesError:YES
                                    error:error];
    }];

    if (setUpSucceeded) {
        setUpSucceeded = [self _gsRunPhase:@"setUpWithError:" block:^BOOL(NSError **error) {
            return [self setUpWithError:error];
        }];
    }

    if (setUpSucceeded) {
        setUpSucceeded = [self _gsRunPhase:@"setUp" block:^BOOL(NSError **error) {
            [self setUp];
            return YES;
        }];
    }

    if (setUpSucceeded) {
        BOOL testCompleted = [self _gsRunPhase:nil block:^BOOL(NSError **error) {
            return [self _gsInvokeTestMethod:error];
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

    [self _gsRunPhase:@"tearDownWithCompletionHandler:" block:^BOOL(NSError **error) {
        return [self _gsInvokeAsyncMethod:@selector(tearDownWithCompletionHandler:)
                     completionTakesError:YES
                                    error:error];
    }];
}

- (void)performTest:(XCTestRun *)run
{
    XCTestCase *previous = GSCurrentTestCase;

    [self _gsSetTestRun:run];
    GSCurrentTestCase = self;
    [run start];
    _GSXCTWatchdogTestWillStart(self);

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
            [self _gsRecordException:exception where:@""];
        }

        @try {
            [self _gsFinishExpectedFailures];
        }
        @catch (NSException *exception) {
        }
        [self _gsInvalidateExpectations];
    }

    _GSXCTWatchdogTestDidFinish(self);
    [run stop];
    GSCurrentTestCase = previous;
}

- (void)addAttachment:(XCTAttachment *)attachment
{
    _GSXCTAddAttachment(self, attachment, _GSXCTCurrentActivityPath());
}

- (void)_gsAddAsyncTeardownBlock:(void (^)(void (^completion)(NSError *error)))block
{
    if (block == nil) {
        return;
    }

    // Not retained: the block runs and is released while this test runs.
    __block XCTestCase *test = self;
    void (^copied)(void (^)(NSError *)) = [[block copy] autorelease];

    // With the plain teardown blocks, in one last-added-first queue.
    [self addTeardownBlock:^{
        [test _gsRunPhase:@"a teardown block" block:^BOOL(NSError **error) {
            GSXCTAsyncCompletion *completion = [[[GSXCTAsyncCompletion alloc] init] autorelease];

            copied(^(NSError *completionError) {
                [completion finishWithError:completionError];
            });
            return [test _gsWaitForAsyncCompletion:completion error:error];
        }];
    }];
}

- (void)addTeardownBlock:(void (^)(void))block
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

+ (XCTestCase *)_gsCurrentTestCase
{
    return GSCurrentTestCase;
}

+ (void)_gsSetCurrentTestCase:(XCTestCase *)testCase
{
    GSCurrentTestCase = testCase;
}

// The test's name as its author wrote it: a throwing Swift test is
// reported, and selected, as testFoo rather than testFooAndReturnError:.
- (NSString *)_gsMethodName
{
    NSString *methodName = nil;

    if (_invocation == nil) {
        return @"(no test method)";
    }
    methodName = NSStringFromSelector([_invocation selector]);
    if ([[_invocation methodSignature] numberOfArguments] == 3 && GSIsThrowingTestName(methodName)) {
        methodName = [methodName substringToIndex:[methodName length] - [GSThrowingTestSuffix length]];
    } else if ([[_invocation methodSignature] numberOfArguments] == 3 && GSIsAsyncTestName(methodName)) {
        methodName = [methodName substringToIndex:[methodName length] - [GSAsyncTestSuffix length]];
    }
    return methodName;
}

- (void)_gsFailWithoutRunning:(GSXCTestIssue *)cause
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

- (GSXCTestCaseResult *)_gsReportResult
{
    return _gsReportResult;
}

- (void)_gsSetReportResult:(GSXCTestCaseResult *)result
{
    if (result != _gsReportResult) {
        [_gsReportResult release];
        _gsReportResult = [result retain];
    }
}

- (NSUInteger)_gsIteration
{
    return _gsIteration;
}

- (NSUInteger)_gsIterationCount
{
    return _gsIterationCount;
}

- (void)_gsSetIteration:(NSUInteger)iteration of:(NSUInteger)iterationCount
{
    _gsIteration = iteration;
    _gsIterationCount = iterationCount;
}

- (void)_gsSkipWithoutRunning:(GSXCTestIssue *)skip
{
    XCTestRun *run = [[[self testRunClass] alloc] initWithTest:self];

    [self _gsSetTestRun:run];
    [run start];
    [(XCTestCaseRun *)run _gsRecordSkip:skip];
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
