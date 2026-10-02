#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

// Every test here should pass: its failures are expected.
@interface ExpectedPassingTests : XCTestCase
@end

@implementation ExpectedPassingTests

- (void)testExpectedAssertion
{
    XCTExpectFailure(@"known bug 1");
    XCTAssertTrue(NO, @"broken");
    NSLog(@"fixture: testExpectedAssertion continued");
}

- (void)testExpectedInBlock
{
    XCTExpectFailureInBlock(@"block reason", ^{
        XCTFail(@"inside block");
    });
}

- (void)testNonStrictWithoutFailure
{
    XCTExpectFailureWithOptions(@"maybe", [XCTExpectedFailureOptions nonStrictOptions]);
}

- (void)testExpectedException
{
    XCTExpectFailure(@"throws");
    [NSException raise:NSInternalInconsistencyException format:@"expected boom"];
}

- (void)testMatcherAccepts
{
    XCTExpectedFailureOptions *options = [[[XCTExpectedFailureOptions alloc] init] autorelease];
    [options setIssueMatcher:^BOOL(XCTIssue *issue) {
        return [[issue compactDescription] rangeOfString:@"match me"].location != NSNotFound
            && [issue type] == XCTIssueTypeAssertionFailure;
    }];
    XCTExpectFailureWithOptions(@"matched", options);
    XCTFail(@"match me");
}

- (void)testExpectedFailureDoesNotStopTest
{
    self.continueAfterFailure = NO;
    XCTExpectFailure(@"keeps going");
    XCTFail(@"first");
    NSLog(@"fixture: testExpectedFailureDoesNotStopTest continued");
}

- (void)testNestedScopesUseInnermost
{
    XCTExpectFailure(@"outer");
    XCTExpectFailureInBlock(@"inner", ^{
        XCTFail(@"nested");
    });
    XCTFail(@"after block");
}

@end

// Every test here should fail.
@interface ExpectedFailingTests : XCTestCase
@end

@implementation ExpectedFailingTests

- (void)testStrictUnmatched
{
    XCTExpectFailure(@"never happens");
}

- (void)testBlockStrictUnmatched
{
    XCTExpectFailureInBlock(@"block never", ^{});
}

- (void)testFailureOutsideBlock
{
    XCTExpectFailureInBlock(@"inside only", ^{
        XCTFail(@"in");
    });
    XCTFail(@"outside the block");
}

- (void)testMatcherRejects
{
    XCTExpectedFailureOptions *options = [[[XCTExpectedFailureOptions alloc] init] autorelease];
    [options setIssueMatcher:^BOOL(XCTIssue *issue) { return NO; }];
    XCTExpectFailureWithOptions(@"picky", options);
    XCTFail(@"not matched");
}

- (void)testDisabled
{
    XCTExpectedFailureOptions *options = [[[XCTExpectedFailureOptions alloc] init] autorelease];
    [options setEnabled:NO];
    XCTExpectFailureWithOptions(@"disabled", options);
    XCTFail(@"counts anyway");
}

@end
