#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

// Every test fails one assertion; run-assertion-tests.sh checks the message.

@interface FixtureException : NSException
@end

@interface PassingIdentityTests : XCTestCase
@end

@implementation PassingIdentityTests

- (void)testIdentityAssertionsPass
{
    NSString *a = [NSMutableString stringWithString:@"a"];
    NSString *b = [NSMutableString stringWithString:@"a"];

    XCTAssertIdentical(a, a);
    XCTAssertNotIdentical(a, b);
    XCTAssertEqualObjects(a, b);
}

@end

@implementation FixtureException
@end

@interface AssertionMessageTests : XCTestCase
@end

@implementation AssertionMessageTests

- (int)boom
{
    [NSException raise:NSInternalInconsistencyException format:@"boom"];
    return 0;
}

- (void)testFail { XCTFail(@"fixture %@", @"message"); }
- (void)testEqual { XCTAssertEqual(1 + 1, 3); }
- (void)testEqualBool { XCTAssertEqual(YES, NO); }
- (void)testEqualThrows { XCTAssertEqual([self boom], 1); }
- (void)testNotEqual { XCTAssertNotEqual(2, 2); }
- (void)testEqualWithAccuracy { XCTAssertEqualWithAccuracy(0.1 + 0.2, 0.4, 0.001); }
- (void)testNotEqualWithAccuracy { XCTAssertNotEqualWithAccuracy(1.0, 1.05, 0.1); }
- (void)testEqualObjects { XCTAssertEqualObjects(@"a", @"b"); }
- (void)testNotEqualObjects { XCTAssertNotEqualObjects(@"a", @"a"); }
- (void)testIdentical { XCTAssertIdentical([NSMutableString stringWithString:@"a"], [NSMutableString stringWithString:@"a"]); }
- (void)testNotIdentical { NSObject *object = [NSObject new]; XCTAssertNotIdentical(object, object); [object release]; }
- (void)testNil { XCTAssertNil(@"x"); }
- (void)testNotNil { XCTAssertNotNil(nil); }
- (void)testGreaterThan { XCTAssertGreaterThan(1, 2); }
- (void)testGreaterThanOrEqual { XCTAssertGreaterThanOrEqual(1, 2); }
- (void)testLessThan { XCTAssertLessThan(2, 1); }
- (void)testLessThanOrEqual { XCTAssertLessThanOrEqual(2, 1); }
- (void)testTrue { XCTAssertTrue(1 > 2); }
- (void)testFalse { XCTAssertFalse(2 > 1); }
- (void)testThrows { XCTAssertThrows(1); }
- (void)testThrowsSpecific { XCTAssertThrowsSpecific([self boom], FixtureException); }
- (void)testThrowsSpecificNamed { XCTAssertThrowsSpecificNamed([self boom], NSException, @"OtherName"); }
- (void)testNoThrow { XCTAssertNoThrow([self boom]); }
- (void)testNoThrowSpecific { XCTAssertNoThrowSpecific([self boom], NSException); }
- (void)testNoThrowSpecificNamed { XCTAssertNoThrowSpecificNamed([self boom], NSException, NSInternalInconsistencyException); }

@end
