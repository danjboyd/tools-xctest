#import <XCTest/XCTest.h>
#import "Counter.h"

@interface CounterTests : XCTestCase
@end

@implementation CounterTests

- (void) testStartsAtZero
{
  Counter *counter = [[Counter alloc] init];
  XCTAssertEqual([counter value], 0);
}

- (void) testIncrementAddsOne
{
  Counter *counter = [[Counter alloc] init];
  [counter increment];
  [counter increment];
  XCTAssertEqual([counter value], 2);
}

- (void) testResetGoesBackToZero
{
  Counter *counter = [[Counter alloc] init];
  [counter increment];
  [counter reset];
  XCTAssertEqual([counter value], 0);
}

@end
