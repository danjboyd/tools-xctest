#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#include <stdlib.h>

@interface HelperTests : XCTestCase
@end

@implementation HelperTests

- (void)testPasses
{
    NSLog(@"helper: HelperTests testPasses ran");
}

- (void)testFailsWhenAsked
{
    if (getenv("HELPER_FIXTURE_FAIL")) {
        XCTFail(@"asked to fail");
    }
}

@end
