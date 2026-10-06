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
- (NSString *)expectationDescription { return _expectationDescription; }
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
- (void)fulfill { @synchronized (self) { _fulfillmentCount++; } }
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
