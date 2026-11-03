#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

// The errors Swift's XCTSkip and XCTUnwrap return (see
// XCTestAssertionsImpl.h), returned here from Objective-C.

static NSError *ControlFlowError(_XCTControlFlowCode code, NSString *message)
{
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
        message, @"message",
        @"/src/FixtureTests.swift", @"file",
        [NSNumber numberWithUnsignedInteger:42], @"line",
        nil];

    return [NSError errorWithDomain:@"" _XCT_CONTROL_FLOW_ERROR_DOMAIN code:code userInfo:info];
}

@interface ControlFlowTests : XCTestCase
@end

@implementation ControlFlowTests

- (BOOL)testSkipsAndReturnError:(NSError **)error
{
    NSLog(@"fixture: ControlFlowTests.testSkips");
    *error = ControlFlowError(_XCTControlFlowCodeSkip, @"Test skipped - not on this platform");
    return NO;
}

// A skip whose userInfo was lost on the way (as in a Swift image linked
// without swiftrt.o, where CustomNSError's errorUserInfo isn't seen).
- (BOOL)testSkipsWithoutInfoAndReturnError:(NSError **)error
{
    NSLog(@"fixture: ControlFlowTests.testSkipsWithoutInfo");
    *error = [NSError errorWithDomain:@"" _XCT_CONTROL_FLOW_ERROR_DOMAIN code:_XCTControlFlowCodeSkip userInfo:nil];
    return NO;
}

// XCTUnwrap records its failure, then throws.
- (BOOL)testAlreadyRecordedAndReturnError:(NSError **)error
{
    NSLog(@"fixture: ControlFlowTests.testAlreadyRecorded");
    XCTFail(@"recorded once");
    *error = ControlFlowError(_XCTControlFlowCodeAlreadyRecorded, nil);
    return NO;
}

- (BOOL)testOtherCodeAndReturnError:(NSError **)error
{
    NSLog(@"fixture: ControlFlowTests.testOtherCode");
    *error = [NSError errorWithDomain:@"" _XCT_CONTROL_FLOW_ERROR_DOMAIN code:99
                             userInfo:[NSDictionary dictionaryWithObject:@"unknown control flow"
                                                                  forKey:NSLocalizedDescriptionKey]];
    return NO;
}

@end

@interface SkipInSetUpTests : XCTestCase
@end

@implementation SkipInSetUpTests

- (BOOL)setUpWithError:(NSError **)error
{
    *error = ControlFlowError(_XCTControlFlowCodeSkip, @"Test skipped - set up");
    return NO;
}

- (void)testNeverRuns
{
    NSLog(@"fixture: SkipInSetUpTests.testNeverRuns");
}

- (void)tearDown
{
    NSLog(@"fixture: SkipInSetUpTests.tearDown");
}

@end
