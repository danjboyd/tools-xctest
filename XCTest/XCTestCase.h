#import <Foundation/Foundation.h>
#import <XCTest/XCTestExpectation.h>

typedef BOOL (^XCPredicateExpectationHandler)(void);

@interface XCTestCase : NSObject
{
    NSInvocation *_invocation;
    BOOL _continueAfterFailure;
    NSUInteger _failureCount;
    NSMutableArray *_expectations;
    BOOL _waiting;
}

+ (void)setUp;
+ (void)tearDown;
+ (NSArray *)testInvocations;
+ (instancetype)testCaseWithSelector:(SEL)selector;
+ (instancetype)testCaseWithInvocation:(NSInvocation *)invocation;
- (instancetype)initWithSelector:(SEL)selector;
- (instancetype)initWithInvocation:(NSInvocation *)invocation;
@property (retain) NSInvocation *invocation;
@property BOOL continueAfterFailure;
@property (readonly, copy) NSString *name;
/* GNUstep extension: failures recorded during the most recent invocation. */
@property (readonly) NSUInteger failureCount;
- (void)setUp;
- (void)tearDown;
- (void)invokeTest;
- (XCTestExpectation *)expectationForPredicate:(NSPredicate *)predicate evaluatedWithObject:(id)object handler:(XCPredicateExpectationHandler)handler;
- (XCTestExpectation *)expectationWithDescription:(NSString *)description;
- (void)waitForExpectationsWithTimeout:(NSTimeInterval)timeout handler:(XCWaitCompletionHandler)handler;
- (void)waitForExpectations:(NSArray *)expectations timeout:(NSTimeInterval)timeout;
- (void)recordFailureWithDescription:(NSString *)description
                            inFile:(NSString *)filePath
                            atLine:(NSUInteger)lineNumber
                          expected:(BOOL)expected;
@end
