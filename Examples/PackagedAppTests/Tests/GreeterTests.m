#import <XCTest/XCTest.h>
#import "Greeter.h"

@interface GreeterTests : XCTestCase
{
  Greeter *greeter;
}
@end

@implementation GreeterTests

- (void) setUp
{
  greeter = [[Greeter alloc] init];
}

- (void) tearDown
{
  [greeter release];
  greeter = nil;
}

- (void) testGreetsByName
{
  XCTAssertEqualObjects([greeter greetingForName: @"Ada"], @"Hello, Ada?"); // TEMPORARY: proves a failing test stops the MSI
}

- (void) testTrimsWhitespace
{
  XCTAssertEqualObjects([greeter greetingForName: @"  Ada\n"], @"Hello, Ada!");
}

- (void) testEmptyNameGreetsTheWorld
{
  XCTAssertEqualObjects([greeter greetingForName: @""], @"Hello, world!");
  XCTAssertEqualObjects([greeter greetingForName: @"   "], @"Hello, world!");
  XCTAssertEqualObjects([greeter greetingForName: nil], @"Hello, world!");
}

@end
