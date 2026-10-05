#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#include <stdlib.h>
#include <unistd.h>

// Four classes that each take a second, to show they run at the same time.

@interface SlowATests : XCTestCase
@end

@implementation SlowATests
- (void)testFirst { NSLog(@"parallel: SlowA first in pid %d", getpid()); [NSThread sleepForTimeInterval:0.5]; }
- (void)testSecond { NSLog(@"parallel: SlowA second in pid %d", getpid()); [NSThread sleepForTimeInterval:0.5]; }
@end

@interface SlowBTests : XCTestCase
@end

@implementation SlowBTests
- (void)testFirst { NSLog(@"parallel: SlowB first in pid %d", getpid()); [NSThread sleepForTimeInterval:0.5]; }
- (void)testSecond { NSLog(@"parallel: SlowB second in pid %d", getpid()); [NSThread sleepForTimeInterval:0.5]; }
@end

@interface SlowCTests : XCTestCase
@end

@implementation SlowCTests
- (void)testFirst { NSLog(@"parallel: SlowC first in pid %d", getpid()); [NSThread sleepForTimeInterval:0.5]; }
- (void)testSecond { NSLog(@"parallel: SlowC second in pid %d", getpid()); [NSThread sleepForTimeInterval:0.5]; }
@end

@interface SlowDTests : XCTestCase
@end

@implementation SlowDTests
- (void)testFirst { NSLog(@"parallel: SlowD first in pid %d", getpid()); [NSThread sleepForTimeInterval:0.5]; }
- (void)testSecond { NSLog(@"parallel: SlowD second in pid %d", getpid()); [NSThread sleepForTimeInterval:0.5]; }
@end

@interface FailingTests : XCTestCase
@end

@implementation FailingTests
- (void)testFails { XCTFail(@"fails in a worker"); }
- (void)testPasses { }
- (void)testSkips { XCTSkip(@"skipped in a worker"); }
- (void)testMeasures { [self measureBlock:^{}]; }
@end

// Crash or hang only when asked, so the rest of the suite stays usable.
@interface TroubleTests : XCTestCase
@end

@implementation TroubleTests
- (void)testCrashes
{
    if (getenv("PARALLEL_FIXTURE_CRASH")) {
        NSLog(@"parallel: about to crash");
        abort();
    }
}
- (void)testHangs
{
    if (getenv("PARALLEL_FIXTURE_HANG")) {
        [NSThread sleepForTimeInterval:30];
    }
}
@end
