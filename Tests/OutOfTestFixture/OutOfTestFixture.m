#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

// Failures that arrive outside the window in which their test runs.

// Runs the run loop for a while, so delayed work from earlier tests fires
// during this test.
static void SpinRunLoop(NSTimeInterval seconds)
{
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

@interface LateFailureTests : XCTestCase
@end

@implementation LateFailureTests

- (void)failLater
{
    XCTFail(@"late failure on the main thread");
}

- (void)failFromBackgroundThread
{
    @autoreleasepool {
        [NSThread sleepForTimeInterval:0.05];
        XCTFail(@"late failure on a background thread");
    }
}

// Both schedule a failure for after they return.
- (void)testA_SchedulesMainThreadFailure
{
    self.continueAfterFailure = NO;
    [self performSelector:@selector(failLater) withObject:nil afterDelay:0.05];
}

- (void)testB_SchedulesBackgroundFailure
{
    [NSThread detachNewThreadSelector:@selector(failFromBackgroundThread) toTarget:self withObject:nil];
}

// Must not be blamed for, or stopped by, the earlier tests' failures.
- (void)testC_RunsWhileTheyArrive
{
    SpinRunLoop(0.3);
    NSLog(@"fixture: testC_RunsWhileTheyArrive finished");
}

@end

@interface OverFulfillTests : XCTestCase
@end

@implementation OverFulfillTests

- (void)testA_FulfillsAgainLater
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"fulfilled twice"];

    [expectation fulfill];
    [self waitForExpectationsWithTimeout:1 handler:nil];
    [expectation performSelector:@selector(fulfill) withObject:nil afterDelay:0.05];
}

- (void)testB_RunsWhileItArrives
{
    SpinRunLoop(0.3);
}

@end

// Registered before xctest's own reporting; fails one test as it starts.
@interface EarlyObserver : NSObject <XCTestObservation>
@end

@implementation EarlyObserver

- (void)testCaseWillStart:(XCTestCase *)testCase
{
    if ([[testCase name] isEqualToString:@"-[EarlyObserverTests testFailedByObserver]"]) {
        [testCase recordFailureWithDescription:@"failure from an observer" inFile:nil atLine:0 expected:YES];
    }
}

@end

@interface EarlyObserverRegistrar : NSObject
@end

@implementation EarlyObserverRegistrar

- (id)init
{
    self = [super init];
    if (self) {
        [[XCTestObservationCenter sharedTestObservationCenter]
            addTestObserver:[[[EarlyObserver alloc] init] autorelease]];
    }
    return self;
}

@end

@interface EarlyObserverTests : XCTestCase
@end

@implementation EarlyObserverTests

- (void)testFailedByObserver { }

@end
