#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

// Logs the end of the bundle, which observers still get when a test runs
// out of time.
@interface TimeoutObserver : NSObject <XCTestObservation>
@end

@implementation TimeoutObserver

- (void)testBundleDidFinish:(NSBundle *)testBundle
{
    NSLog(@"observer: bundle did finish");
}

- (void)testSuiteDidFinish:(XCTestSuite *)testSuite
{
    if ([[testSuite name] isEqualToString:@"HangTests"]) {
        XCTestRun *run = [testSuite testRun];
        NSLog(@"observer: HangTests finished executed=%lu failures=%lu",
              (unsigned long)[run executionCount], (unsigned long)[run totalFailureCount]);
    }
}

@end

@interface TimeoutObserverRegistrar : NSObject
@end

@implementation TimeoutObserverRegistrar

- (id)init
{
    self = [super init];
    if (self) {
        [[XCTestObservationCenter sharedTestObservationCenter]
            addTestObserver:[[[TimeoutObserver alloc] init] autorelease]];
    }
    return self;
}

@end

// Runs (alphabetically) before the hang.
@interface AQuickTests : XCTestCase
@end

@implementation AQuickTests

- (void)testReportsDefaultAllowance
{
    NSLog(@"fixture: default allowance %g", [self executionTimeAllowance]);
}

@end

@interface HangTests : XCTestCase
@end

@implementation HangTests

- (void)testHangs
{
    NSLog(@"fixture: hanging");
    [NSThread sleepForTimeInterval:30];
    NSLog(@"fixture: hang ended");
}

@end

// Sets its own allowance, longer than the default the regressions use.
@interface OwnAllowanceTests : XCTestCase
@end

@implementation OwnAllowanceTests

- (void)setUp
{
    [self setExecutionTimeAllowance:5];
}

- (void)testTakesTwoSeconds
{
    NSLog(@"fixture: own allowance %g", [self executionTimeAllowance]);
    [NSThread sleepForTimeInterval:2];
}

@end

// Never reached when HangTests runs out of time.
@interface ZLaterTests : XCTestCase
@end

@implementation ZLaterTests

- (void)testAfterTheHang
{
    NSLog(@"fixture: ran after the hang");
}

@end
