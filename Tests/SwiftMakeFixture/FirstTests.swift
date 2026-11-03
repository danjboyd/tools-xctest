// Objective-C, not Swift: run-make-swift-tests.sh's stand-in swift-frontend
// compiles these files as Objective-C, so the bundle has real tests to run
// without a Swift toolchain. What's under test is how xctest.make and
// gnustep-make build and link the bundle.
#import <XCTest/XCTest.h>

@interface FirstTests : XCTestCase
@end

@implementation FirstTests
- (void)testFirst
{
    NSLog(@"swift-make: FirstTests.testFirst ran");
}
@end
