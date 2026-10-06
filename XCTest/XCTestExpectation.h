#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString * const XCTestErrorDomain;
typedef NS_ENUM(NSInteger, XCTestErrorCode) {
    XCTestErrorCodeTimeoutWhileWaiting = 0,
    XCTestErrorCodeFailureWhileWaiting = 1
};
typedef void (^XCWaitCompletionHandler)(NSError *error);

@interface XCTestExpectation : NSObject
{
    NSString *_expectationDescription;
    NSUInteger _expectedFulfillmentCount;
    NSUInteger _fulfillmentCount;
    BOOL _inverted;
    BOOL _assertForOverFulfill;
}
- (instancetype)initWithDescription:(NSString *)expectationDescription;
@property (readonly, copy) NSString *expectationDescription;
@property NSUInteger expectedFulfillmentCount;
@property (getter=isInverted) BOOL inverted;
@property BOOL assertForOverFulfill;
- (void)fulfill;
@end
