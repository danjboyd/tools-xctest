#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

// Should pass (the script supplies a generous baseline for testWithinBaseline).
@interface PerfPassingTests : XCTestCase
@end

@implementation PerfPassingTests

- (void)testMeasureBlock
{
    __block int runs = 0;

    [self measureBlock:^{
        runs++;
        [NSThread sleepForTimeInterval:0.002];
    }];
    XCTAssertEqual(runs, 10);
}

- (void)testManualMeasuring
{
    [self measureMetrics:[[self class] defaultPerformanceMetrics] automaticallyStartMeasuring:NO forBlock:^{
        [NSThread sleepForTimeInterval:0.02];   // not measured
        [self startMeasuring];
        [NSThread sleepForTimeInterval:0.001];
        [self stopMeasuring];
    }];
}

- (void)testWithinBaseline
{
    [self measureBlock:^{
        [NSThread sleepForTimeInterval:0.001];
    }];
}

@end

// Each should fail.
@interface PerfFailingTests : XCTestCase
@end

@implementation PerfFailingTests

- (void)testMeasureTwice
{
    [self measureBlock:^{}];
    [self measureBlock:^{}];
}

- (void)testMissingStartMeasuring
{
    [self measureMetrics:[[self class] defaultPerformanceMetrics] automaticallyStartMeasuring:NO forBlock:^{}];
}

- (void)testUnsupportedMetric
{
    [self measureMetrics:[NSArray arrayWithObject:@"com.example.Bogus"] automaticallyStartMeasuring:YES forBlock:^{}];
}

- (void)testStartOutsideMeasureBlock
{
    [self startMeasuring];
}

- (void)testRegression
{
    [self measureBlock:^{
        [NSThread sleepForTimeInterval:0.005];
    }];
}

@end
