#import <XCTest/XCTest.h>
@interface CLIExample : XCTestCase @end
@implementation CLIExample
- (void)testPass { XCTAssertEqual(2 + 2, 4); }
- (void)testFail { XCTFail(@"intentional CLI failure"); }
@end
