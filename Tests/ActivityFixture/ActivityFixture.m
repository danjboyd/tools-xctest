#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

@interface ActivityTests : XCTestCase
@end

@implementation ActivityTests

+ (void)setUp
{
    // Outside a test, an activity just runs its block.
    [XCTContext runActivityNamed:@"Class set up" block:^(id<XCTActivity> activity) {
        NSLog(@"fixture: class activity ran");
    }];
}

- (void)testNestedActivityFailure
{
    [XCTContext runActivityNamed:@"Log in" block:^(id<XCTActivity> outer) {
        [XCTContext runActivityNamed:@"Enter password" block:^(id<XCTActivity> inner) {
            XCTFail(@"wrong password");
        }];
    }];
}

- (void)testFailureAfterActivity
{
    [XCTContext runActivityNamed:@"Prepare" block:^(id<XCTActivity> activity) {
    }];
    XCTFail(@"outside any activity");
}

- (void)testActivityObject
{
    [XCTContext runActivityNamed:@"Named step" block:^(id<XCTActivity> activity) {
        XCTAssertEqualObjects([activity name], @"Named step");
        XCTAssertTrue([(id)activity conformsToProtocol:@protocol(XCTActivity)]);
    }];
}

- (void)testExceptionPropagates
{
    @try {
        [XCTContext runActivityNamed:@"Throws" block:^(id<XCTActivity> activity) {
            [NSException raise:NSGenericException format:@"from activity"];
        }];
    }
    @catch (NSException *exception) {
        NSLog(@"fixture: caught '%@'", [exception reason]);
    }
    XCTFail(@"after the exception");
}

- (void)testActivityOnAnotherThread
{
    XCTestExpectation *done = [self expectationWithDescription:@"background activity"];

    [NSThread detachNewThreadWithBlock:^{
        [XCTContext runActivityNamed:@"Background" block:^(id<XCTActivity> activity) {
            XCTFail(@"on another thread");
        }];
        [done fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testExpectedFailureInActivity
{
    XCTExpectFailure(@"known issue");
    [XCTContext runActivityNamed:@"Flaky step" block:^(id<XCTActivity> activity) {
        XCTFail(@"expected inside activity");
    }];
}

@end
