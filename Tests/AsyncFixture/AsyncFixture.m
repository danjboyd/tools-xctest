#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

static NSString * const FixtureNotification = @"FixtureNotification";

@interface FixtureModel : NSObject {
    NSNumber *_level;
}
@property (retain) NSNumber *level;
@end

@implementation FixtureModel
@synthesize level = _level;
- (void)dealloc { [_level release]; [super dealloc]; }
@end

// Shared helpers for scheduling work on the run loop or another thread.
@interface XCTestCase (AsyncFixtureHelpers)
- (void)postFixtureNotification:(NSNumber *)value;
- (void)fulfillFromBackgroundThread:(XCTestExpectation *)expectation;
@end

@implementation XCTestCase (AsyncFixtureHelpers)

- (void)postFixtureNotification:(NSNumber *)value
{
    [[NSNotificationCenter defaultCenter] postNotificationName:FixtureNotification
                                                        object:nil
                                                      userInfo:[NSDictionary dictionaryWithObject:value forKey:@"value"]];
}

- (void)fulfillFromBackgroundThread:(XCTestExpectation *)expectation
{
    @autoreleasepool {
        [NSThread sleepForTimeInterval:0.05];
        [expectation fulfill];
    }
}

@end

// Every test here should pass.
@interface AsyncPassingTests : XCTestCase
@end

@implementation AsyncPassingTests

- (void)testDelayedFulfill
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"delayed"];
    __block BOOL handlerCalled = NO;

    [expectation performSelector:@selector(fulfill) withObject:nil afterDelay:0.05];
    [self waitForExpectationsWithTimeout:2 handler:^(NSError *error) {
        XCTAssertNil(error);
        handlerCalled = YES;
    }];
    XCTAssertTrue(handlerCalled);
}

- (void)testBackgroundThreadFulfill
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"background"];

    [NSThread detachNewThreadSelector:@selector(fulfillFromBackgroundThread:) toTarget:self withObject:expectation];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testNotification
{
    [self expectationForNotification:FixtureNotification object:nil handler:nil];
    [self performSelector:@selector(postFixtureNotification:) withObject:[NSNumber numberWithInt:1] afterDelay:0.05];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testNotificationHandlerFilters
{
    __block int seen = 0;

    [self expectationForNotification:FixtureNotification object:nil handler:^BOOL(NSNotification *notification) {
        seen++;
        return [[[notification userInfo] objectForKey:@"value"] intValue] == 2;
    }];
    [self performSelector:@selector(postFixtureNotification:) withObject:[NSNumber numberWithInt:1] afterDelay:0.02];
    [self performSelector:@selector(postFixtureNotification:) withObject:[NSNumber numberWithInt:2] afterDelay:0.05];
    [self waitForExpectationsWithTimeout:2 handler:nil];
    XCTAssertEqual(seen, 2);
}

- (void)testKeyValueObservingExpectedValue
{
    FixtureModel *model = [[[FixtureModel alloc] init] autorelease];

    [self keyValueObservingExpectationForObject:model keyPath:@"level" expectedValue:[NSNumber numberWithInt:3]];
    [model performSelector:@selector(setLevel:) withObject:[NSNumber numberWithInt:1] afterDelay:0.02];
    [model performSelector:@selector(setLevel:) withObject:[NSNumber numberWithInt:3] afterDelay:0.05];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testKeyValueObservingAlreadyAtValue
{
    FixtureModel *model = [[[FixtureModel alloc] init] autorelease];
    NSDate *start = [NSDate date];

    [model setLevel:[NSNumber numberWithInt:7]];
    [self keyValueObservingExpectationForObject:model keyPath:@"level" expectedValue:[NSNumber numberWithInt:7]];
    [self waitForExpectationsWithTimeout:2 handler:nil];
    XCTAssertLessThan([[NSDate date] timeIntervalSinceDate:start], 1.0);
}

- (void)testKeyValueObservingHandler
{
    FixtureModel *model = [[[FixtureModel alloc] init] autorelease];

    [self keyValueObservingExpectationForObject:model keyPath:@"level" handler:^BOOL(id observedObject, NSDictionary *change) {
        return [[(FixtureModel *)observedObject level] intValue] > 4;
    }];
    [model performSelector:@selector(setLevel:) withObject:[NSNumber numberWithInt:2] afterDelay:0.02];
    [model performSelector:@selector(setLevel:) withObject:[NSNumber numberWithInt:5] afterDelay:0.05];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testPredicate
{
    FixtureModel *model = [[[FixtureModel alloc] init] autorelease];

    [self expectationForPredicate:[NSPredicate predicateWithFormat:@"level == 5"] evaluatedWithObject:model handler:nil];
    [model performSelector:@selector(setLevel:) withObject:[NSNumber numberWithInt:5] afterDelay:0.05];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testInvertedWaitsFullTimeout
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"must not happen"];
    NSDate *start = [NSDate date];

    [expectation setInverted:YES];
    [self waitForExpectations:[NSArray arrayWithObject:expectation] timeout:0.2];
    XCTAssertGreaterThanOrEqual([[NSDate date] timeIntervalSinceDate:start], 0.19);
}

- (void)testExpectedFulfillmentCount
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"three times"];

    [expectation setExpectedFulfillmentCount:3];
    [expectation performSelector:@selector(fulfill) withObject:nil afterDelay:0.01];
    [expectation performSelector:@selector(fulfill) withObject:nil afterDelay:0.02];
    [expectation performSelector:@selector(fulfill) withObject:nil afterDelay:0.03];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testEnforceOrderInOrder
{
    XCTestExpectation *first = [self expectationWithDescription:@"first"];
    XCTestExpectation *second = [self expectationWithDescription:@"second"];

    [first performSelector:@selector(fulfill) withObject:nil afterDelay:0.02];
    [second performSelector:@selector(fulfill) withObject:nil afterDelay:0.05];
    [self waitForExpectations:[NSArray arrayWithObjects:first, second, nil] timeout:2 enforceOrder:YES];
}

- (void)testStandaloneWaiter
{
    XCTestExpectation *done = [[[XCTestExpectation alloc] initWithDescription:@"done"] autorelease];
    XCTestExpectation *never = [[[XCTestExpectation alloc] initWithDescription:@"never"] autorelease];
    XCTWaiter *waiter = [[[XCTWaiter alloc] init] autorelease];

    [done performSelector:@selector(fulfill) withObject:nil afterDelay:0.02];
    XCTAssertEqual([waiter waitForExpectations:[NSArray arrayWithObject:done] timeout:2], XCTWaiterResultCompleted);
    XCTAssertEqualObjects([waiter fulfilledExpectations], [NSArray arrayWithObject:done]);

    // Without a delegate a timeout is just a result, not a test failure.
    XCTAssertEqual([XCTWaiter waitForExpectations:[NSArray arrayWithObject:never] timeout:0.05], XCTWaiterResultTimedOut);
}

@end

// Every test here should fail, with the message checked by the script.
@interface AsyncFailureTests : XCTestCase
@end

@implementation AsyncFailureTests

- (void)testTimeout
{
    [self expectationWithDescription:@"never fulfilled"];
    [self waitForExpectationsWithTimeout:0.1 handler:^(NSError *error) {
        NSLog(@"fixture: timeout handler error %@ %ld", [error domain], (long)[error code]);
    }];
}

- (void)testInvertedFulfilled
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"inverted"];

    [expectation setInverted:YES];
    [expectation performSelector:@selector(fulfill) withObject:nil afterDelay:0.02];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testWrongOrder
{
    XCTestExpectation *first = [self expectationWithDescription:@"first"];
    XCTestExpectation *second = [self expectationWithDescription:@"second"];

    [second performSelector:@selector(fulfill) withObject:nil afterDelay:0.02];
    [first performSelector:@selector(fulfill) withObject:nil afterDelay:0.05];
    [self waitForExpectations:[NSArray arrayWithObjects:first, second, nil] timeout:2 enforceOrder:YES];
}

- (void)testUnwaited
{
    [self expectationWithDescription:@"forgotten"];
}

- (void)testOverFulfill
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"once only"];

    [expectation fulfill];
    [expectation fulfill];
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testWaitWithoutExpectations
{
    [self waitForExpectationsWithTimeout:0.1 handler:nil];
}

- (void)testTimeoutStopsTest
{
    self.continueAfterFailure = NO;
    [self expectationWithDescription:@"stops"];
    [self waitForExpectationsWithTimeout:0.05 handler:nil];
    NSLog(@"fixture: AsyncFailureTests continued after timeout");
}

@end
