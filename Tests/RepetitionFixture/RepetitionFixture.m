#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

// Counters persist across the repeated runs of a test within one process.
static int countingRuns = 0;
static int flakyRuns = 0;
static int failsOnThirdRuns = 0;
static int skipRuns = 0;
static int classSetUps = 0;

@interface CountingTests : XCTestCase
@end

@implementation CountingTests

+ (void)setUp { NSLog(@"fixture: CountingTests +setUp %d", ++classSetUps); }

- (void)testCounts
{
    NSLog(@"fixture: counting run %d", ++countingRuns);
}

@end

@interface FlakyTests : XCTestCase
@end

@implementation FlakyTests

// Fails on its first two runs, then passes.
- (void)testPassesOnThirdRun
{
    flakyRuns++;
    NSLog(@"fixture: flaky run %d", flakyRuns);
    XCTAssertGreaterThan(flakyRuns, 2, @"flaky failure");
}

@end

@interface FailsOnThirdTests : XCTestCase
@end

@implementation FailsOnThirdTests

- (void)testFailsOnThirdRun
{
    failsOnThirdRuns++;
    NSLog(@"fixture: fails-on-third run %d", failsOnThirdRuns);
    XCTAssertNotEqual(failsOnThirdRuns, 3, @"third run fails");
}

@end

@interface RepeatedSkipTests : XCTestCase
@end

@implementation RepeatedSkipTests

- (void)testSkips
{
    NSLog(@"fixture: skip run %d", ++skipRuns);
    XCTSkip(@"always skipped");
}

@end
