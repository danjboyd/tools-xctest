#import <XCTest/XCTestCase.h>
#import <XCTest/XCTestAssertionsImpl.h>
#import <objc/runtime.h>
#include <string.h>

@interface XCTestExpectation (GSWaiting)
- (NSUInteger)_waitStatus;
@end

@interface _GSXCPredicateExpectation : XCTestExpectation
{
@public
    NSPredicate *predicate;
    id object;
    XCPredicateExpectationHandler handler;
    BOOL matched;
}
@end
@implementation _GSXCPredicateExpectation
- (void)dealloc
{
    [predicate release]; [object release]; [handler release]; [super dealloc];
}
- (NSUInteger)_waitStatus
{
    if (!matched && [predicate evaluateWithObject:object] && (!handler || handler())) {
        matched = YES;
        [self fulfill];
    }
    return [super _waitStatus];
}
@end

@implementation XCTestCase
@synthesize invocation = _invocation;
@synthesize continueAfterFailure = _continueAfterFailure;

+ (void)setUp {}
+ (void)tearDown {}
- (void)setUp {}
- (void)tearDown {}

+ (NSArray *)testInvocations
{
    NSMutableSet *seen = [NSMutableSet set];
    NSMutableArray *names = [NSMutableArray array];
    for (Class cls = self; cls && cls != [XCTestCase class]; cls = class_getSuperclass(cls)) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            NSString *name = NSStringFromSelector(method_getName(methods[i]));
            if ([seen containsObject:name]) continue;
            [seen addObject:name];
            char *type = method_copyReturnType(methods[i]);
            BOOL valid = [name hasPrefix:@"test"] &&
                method_getNumberOfArguments(methods[i]) == 2 && strcmp(type, @encode(void)) == 0;
            free(type);
            if (valid) [names addObject:name];
        }
        free(methods);
    }
    [names sortUsingSelector:@selector(compare:)];
    NSMutableArray *invocations = [NSMutableArray array];
    for (NSString *name in names) {
        SEL selector = NSSelectorFromString(name);
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:
            [self instanceMethodSignatureForSelector:selector]];
        [invocation setSelector:selector];
        [invocations addObject:invocation];
    }
    return invocations;
}

+ (instancetype)testCaseWithSelector:(SEL)selector
{
    return [[[self alloc] initWithSelector:selector] autorelease];
}
+ (instancetype)testCaseWithInvocation:(NSInvocation *)invocation
{
    return [[[self alloc] initWithInvocation:invocation] autorelease];
}
- (instancetype)init
{
    return [self initWithInvocation:nil];
}
- (instancetype)initWithSelector:(SEL)selector
{
    NSMethodSignature *signature = [[self class] instanceMethodSignatureForSelector:selector];
    if (!signature || [signature numberOfArguments] != 2 ||
        strcmp([signature methodReturnType], @encode(void)) != 0) {
        [self release];
        [NSException raise:NSInvalidArgumentException format:@"Invalid test selector %@", NSStringFromSelector(selector)];
        return nil;
    }
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setSelector:selector];
    return [self initWithInvocation:invocation];
}
- (instancetype)initWithInvocation:(NSInvocation *)invocation
{
    if ((self = [super init])) {
        _invocation = [invocation retain];
        _continueAfterFailure = YES;
        _expectations = [NSMutableArray new];
    }
    return self;
}
- (void)dealloc
{
    [_invocation release];
    [_expectations release];
    [super dealloc];
}
- (NSString *)name
{
    return [NSString stringWithFormat:@"-[%@ %@]", NSStringFromClass([self class]),
        _invocation ? NSStringFromSelector([_invocation selector]) : @"(null)"];
}
- (NSUInteger)failureCount
{
    @synchronized (self) { return _failureCount; }
}
- (void)recordFailureWithDescription:(NSString *)description inFile:(NSString *)filePath
                            atLine:(NSUInteger)lineNumber expected:(BOOL)expected
{
    @synchronized (self) { _failureCount++; }
    NSLog(@"XCTest: %@:%lu: %@: %@%@", filePath ?: @"<unknown>",
        (unsigned long)lineNumber, [self name], expected ? @"" : @"unexpected failure: ", description);
    if (!_continueAfterFailure) {
        @throw [_XCTestCaseInterruptionException exceptionWithName:@"XCTestCaseInterruption"
            reason:description userInfo:nil];
    }
}
- (void)recordException:(id)exception phase:(NSString *)phase
{
    /* A failure in teardown must not escape and prevent the next test running. */
    @try {
        [self recordFailureWithDescription:[NSString stringWithFormat:@"%@ threw %@", phase, exception]
            inFile:nil atLine:0 expected:NO];
    }
    @catch (_XCTestCaseInterruptionException *interruption) {}
}
- (void)invokeTest
{
    @synchronized (self) { _failureCount = 0; }
    [_expectations removeAllObjects];
    @try {
        [self setUp];
        NSMethodSignature *signature = [_invocation methodSignature];
        if (!signature || [signature numberOfArguments] != 2 ||
            strcmp([signature methodReturnType], @encode(void)) != 0 ||
            ![self respondsToSelector:[_invocation selector]]) {
            [NSException raise:NSInvalidArgumentException format:@"No valid test invocation configured"];
        }
        [_invocation invokeWithTarget:self];
    }
    @catch (_XCTestCaseInterruptionException *interruption) {}
    @catch (id exception) { [self recordException:exception phase:@"Test or setUp"]; }
    @finally {
        [_invocation setTarget:nil];
        @try { [self tearDown]; }
        @catch (_XCTestCaseInterruptionException *interruption) {}
        @catch (id exception) { [self recordException:exception phase:@"tearDown"]; }
        if ([_expectations count]) {
            @try {
                [self recordFailureWithDescription:@"Created expectations were never waited on"
                    inFile:nil atLine:0 expected:YES];
            }
            @catch (_XCTestCaseInterruptionException *interruption) {}
            [_expectations removeAllObjects];
        }
    }
}
- (XCTestExpectation *)expectationForPredicate:(NSPredicate *)predicate evaluatedWithObject:(id)object handler:(XCPredicateExpectationHandler)handler
{
    if (!predicate) [NSException raise:NSInvalidArgumentException format:@"Predicate must not be nil"];
    _GSXCPredicateExpectation *expectation = [[[_GSXCPredicateExpectation alloc]
        initWithDescription:[NSString stringWithFormat:@"Predicate %@", predicate]] autorelease];
    expectation->predicate = [predicate retain];
    expectation->object = [object retain];
    expectation->handler = [handler copy];
    [_expectations addObject:expectation];
    return expectation;
}
- (XCTestExpectation *)expectationWithDescription:(NSString *)description
{
    XCTestExpectation *expectation = [[[XCTestExpectation alloc] initWithDescription:description] autorelease];
    [_expectations addObject:expectation];
    return expectation;
}
- (NSError *)_waitForExpectations:(NSArray *)expectations timeout:(NSTimeInterval)timeout
{
    if (_waiting || ![expectations count] || !isfinite(timeout) || timeout < 0) {
        [NSException raise:NSInvalidArgumentException format:@"Wait requires expectations, a finite nonnegative timeout, and no nested wait"];
    }
    for (id expectation in expectations) {
        if (![expectation isKindOfClass:[XCTestExpectation class]])
            [NSException raise:NSInvalidArgumentException format:@"Invalid expectation %@", expectation];
    }
    NSArray *pending = [[expectations copy] autorelease];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    NSError *error = nil;
    _waiting = YES;
    @try {
        while (YES) {
            NSMutableArray *unfulfilled = [NSMutableArray array];
            NSString *violation = nil;
            BOOL hasInverted = NO;
            for (XCTestExpectation *expectation in pending) {
                NSUInteger status = [expectation _waitStatus];
                if (status == 2) {
                    violation = [NSString stringWithFormat:@"Expectation violated: %@", [expectation expectationDescription]];
                    break;
                }
                if ([expectation isInverted]) hasInverted = YES;
                else if (status == 0) [unfulfilled addObject:[expectation expectationDescription] ?: @"Expectation"];
            }
            BOOL expired = [deadline timeIntervalSinceNow] <= 0;
            if (violation || (expired && [unfulfilled count])) {
                NSString *description = violation ?: [NSString stringWithFormat:@"Timed out waiting for: %@",
                    [unfulfilled componentsJoinedByString:@", "]];
                error = [NSError errorWithDomain:XCTestErrorDomain
                    code:violation ? XCTestErrorCodeFailureWhileWaiting : XCTestErrorCodeTimeoutWhileWaiting
                    userInfo:[NSDictionary dictionaryWithObject:description forKey:NSLocalizedDescriptionKey]];
                break;
            }
            if (![unfulfilled count] && (!hasInverted || expired)) break;
            NSDate *slice = [NSDate dateWithTimeIntervalSinceNow:MIN(0.01, MAX(0, [deadline timeIntervalSinceNow]))];
            if (![[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:slice])
                [NSThread sleepUntilDate:slice];
        }
    }
    @finally {
        _waiting = NO;
        [_expectations removeObjectsInArray:pending];
    }
    return error;
}
- (void)waitForExpectationsWithTimeout:(NSTimeInterval)timeout handler:(XCWaitCompletionHandler)handler
{
    NSError *error = [self _waitForExpectations:_expectations timeout:timeout];
    @try {
        if (error) [self recordFailureWithDescription:[error localizedDescription] inFile:nil atLine:0 expected:YES];
    }
    @finally { if (handler) handler(error); }
}
- (void)waitForExpectations:(NSArray *)expectations timeout:(NSTimeInterval)timeout
{
    NSError *error = [self _waitForExpectations:expectations timeout:timeout];
    if (error) [self recordFailureWithDescription:[error localizedDescription] inFile:nil atLine:0 expected:YES];
}
@end
