#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString * const XCTestErrorDomain;
typedef NS_ENUM(NSInteger, XCTestErrorCode) {
    XCTestErrorCodeTimeoutWhileWaiting = 0,
    XCTestErrorCodeFailureWhileWaiting = 1
};
typedef void (^XCWaitCompletionHandler)(NSError *error);

@class XCTestCase;

@interface XCTestExpectation : NSObject
{
    NSString *_expectationDescription;
    NSUInteger _expectedFulfillmentCount;
    NSUInteger _fulfillmentCount;
    BOOL _inverted;
    BOOL _assertForOverFulfill;
    XCTestCase *_testCase; /* not retained; set while a waited-on expectation's test runs */
}
- (instancetype)initWithDescription:(NSString *)expectationDescription;
@property (copy) NSString *expectationDescription;
@property NSUInteger expectedFulfillmentCount;
@property (getter=isInverted) BOOL inverted;
@property BOOL assertForOverFulfill;
- (void)fulfill;
@end
