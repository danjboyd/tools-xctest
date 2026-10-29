#import <XCTest/XCTestCase.h>
#import <XCTest/XCTestAssertionsImpl.h>
#import <XCTest/XCTestExpectation.h>

NSString * const XCTestErrorDomain = @"XCTestErrorDomain";

@implementation XCTestExpectation
- (instancetype)initWithDescription:(NSString *)description
{
    if ((self = [super init])) {
        _expectationDescription = [description copy];
        _expectedFulfillmentCount = 1;
    }
    return self;
}
- (instancetype)init { return [self initWithDescription:@"Expectation"]; }
- (void)dealloc { [_expectationDescription release]; [super dealloc]; }
- (NSString *)expectationDescription
{
    @synchronized (self) { return [[_expectationDescription retain] autorelease]; }
}
- (void)setExpectationDescription:(NSString *)description
{
    description = [description copy];
    @synchronized (self) {
        [_expectationDescription release];
        _expectationDescription = description;
    }
}
- (NSUInteger)expectedFulfillmentCount
{
    @synchronized (self) { return _expectedFulfillmentCount; }
}
- (void)setExpectedFulfillmentCount:(NSUInteger)count
{
    if (!count) [NSException raise:NSInvalidArgumentException format:@"Expected fulfillment count must be positive"];
    @synchronized (self) { _expectedFulfillmentCount = count; }
}
- (BOOL)isInverted { @synchronized (self) { return _inverted; } }
- (void)setInverted:(BOOL)value { @synchronized (self) { _inverted = value; } }
- (BOOL)assertForOverFulfill { @synchronized (self) { return _assertForOverFulfill; } }
- (void)setAssertForOverFulfill:(BOOL)value { @synchronized (self) { _assertForOverFulfill = value; } }
- (void)fulfill
{
    @synchronized (self) {
        _fulfillmentCount++;
        /* A wait reports over-fulfillment it sees; once the wait is over, -fulfill does. */
        if (_testCase && _assertForOverFulfill && _fulfillmentCount > _expectedFulfillmentCount) {
            @try {
                [_testCase recordFailureWithDescription:[NSString stringWithFormat:
                    @"API violation - multiple calls made to fulfill for %@", _expectationDescription]
                    inFile:nil atLine:0 expected:YES];
            }
            @catch (_XCTestCaseInterruptionException *interruption) {}
        }
    }
}
- (void)_setTestCase:(XCTestCase *)testCase { @synchronized (self) { _testCase = testCase; } }
/* Internal snapshot: 0 pending, 1 satisfied, 2 violated. */
- (NSUInteger)_waitStatus
{
    @synchronized (self) {
        if ((_inverted && _fulfillmentCount) ||
            (_assertForOverFulfill && _fulfillmentCount > _expectedFulfillmentCount)) return 2;
        return !_inverted && _fulfillmentCount >= _expectedFulfillmentCount ? 1 : 0;
    }
}
@end
