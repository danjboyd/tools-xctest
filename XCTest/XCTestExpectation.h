#import <Foundation/Foundation.h>

/* Not FOUNDATION_EXPORT: that is gnustep-base's GS_EXPORT, which on Windows
 * is __declspec(dllimport) outside gnustep-base, so the XCTest DLL never
 * exported the constant and clients failed to link. */
extern NSString * const XCTestErrorDomain;
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
