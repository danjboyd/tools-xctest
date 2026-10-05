#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#include <stdlib.h>
#include <string.h>

// A custom metric: logs its hooks and reports a count that prefers larger.
@interface WidgetMetric : NSObject <XCTMetric> {
@public
    NSUInteger runs;
    BOOL fail;
}
@end

@implementation WidgetMetric

- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (void)willBeginMeasuring { NSLog(@"widget: willBegin"); }
- (void)didStartMeasuring { NSLog(@"widget: didStart"); }
- (void)didStopMeasuring { NSLog(@"widget: didStop"); runs++; }

- (NSArray *)reportMeasurementsFromStartTime:(XCTPerformanceMeasurementTimestamp *)startTime
                                   toEndTime:(XCTPerformanceMeasurementTimestamp *)endTime
                                       error:(NSError **)error
{
    if (fail) {
        *error = [NSError errorWithDomain:@"Widget" code:1
                                 userInfo:[NSDictionary dictionaryWithObject:@"widget counter broke"
                                                                      forKey:NSLocalizedDescriptionKey]];
        return nil;
    }
    if ([endTime absoluteTime] < [startTime absoluteTime]) {
        NSLog(@"widget: timestamps out of order");
    }
    return [NSArray arrayWithObject:[[[XCTPerformanceMeasurement alloc]
        initWithIdentifier:@"com.example.widgets" displayName:@"Widgets" doubleValue:(double)runs
                unitSymbol:@"w" polarity:XCTPerformanceMeasurementPolarityPrefersLarger] autorelease]];
}

@end

@interface MetricPassingTests : XCTestCase
@end

@implementation MetricPassingTests

- (void)testClock
{
    [self measureWithMetrics:[NSArray arrayWithObject:[[[XCTClockMetric alloc] init] autorelease]] block:^{
        [NSThread sleepForTimeInterval:0.01];
    }];
}

- (void)testAllMetrics
{
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"metric-fixture.dat"];
    NSArray *metrics = [NSArray arrayWithObjects:[[[XCTClockMetric alloc] init] autorelease],
        [[[XCTCPUMetric alloc] init] autorelease], [[[XCTMemoryMetric alloc] init] autorelease],
        [[[XCTStorageMetric alloc] init] autorelease], nil];
    XCTMeasureOptions *options = [XCTMeasureOptions defaultOptions];

    [options setIterationCount:3];
    [self measureWithMetrics:metrics options:options block:^{
        // CPU: spin for 20ms; storage: write 100 kB; memory: touch 8 MB.
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:0.02];
        volatile unsigned long spin = 0;
        while ([until timeIntervalSinceNow] > 0) { spin++; }
        FILE *file = fopen([path fileSystemRepresentation], "w");
        char chunk[1024];
        memset(chunk, 'x', sizeof(chunk));
        for (int i = 0; i < 100; i++) { fwrite(chunk, 1, sizeof(chunk), file); fflush(file); }
        fclose(file);
        char *memory = malloc(8 * 1024 * 1024);
        memset(memory, 1, 8 * 1024 * 1024);
        free(memory);
    }];
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

- (void)testManualStartAndCustomMetric
{
    WidgetMetric *widgets = [[[WidgetMetric alloc] init] autorelease];
    XCTMeasureOptions *options = [[[XCTMeasureOptions alloc] init] autorelease];

    [options setIterationCount:2];
    [options setInvocationOptions:XCTMeasurementInvocationManuallyStart];
    [self measureWithMetrics:[NSArray arrayWithObject:widgets] options:options block:^{
        NSLog(@"widget: block before start");
        [self startMeasuring];
        NSLog(@"widget: block measuring");
    }];
}

- (void)testManualStop
{
    XCTMeasureOptions *options = [[[XCTMeasureOptions alloc] init] autorelease];

    [options setIterationCount:2];
    [options setInvocationOptions:XCTMeasurementInvocationManuallyStop];
    [self measureWithOptions:options block:^{
        [self stopMeasuring];
        NSLog(@"metric: after stop");
    }];
}

- (void)testDefaults
{
    XCTAssertEqual([[XCTMeasureOptions defaultOptions] iterationCount], (NSUInteger)5);
    XCTAssertTrue([[[[self class] defaultMetrics] objectAtIndex:0] isKindOfClass:[XCTClockMetric class]]);
    XCTPerformanceMeasurement *m = [[[XCTPerformanceMeasurement alloc] initWithIdentifier:@"id" displayName:@"Name"
                                                                                 doubleValue:2.5 unitSymbol:@"u"] autorelease];
    XCTAssertEqual([m doubleValue], 2.5);
    XCTAssertEqualObjects([m unitSymbol], @"u");
    XCTAssertEqual([m polarity], XCTPerformanceMeasurementPolarityPrefersSmaller);
    XCTAssertEqualObjects([[m value] unit].symbol, @"u");
}

@end

@interface MetricFailingTests : XCTestCase
@end

@implementation MetricFailingTests

- (void)testNeverStarts
{
    XCTMeasureOptions *options = [[[XCTMeasureOptions alloc] init] autorelease];

    [options setInvocationOptions:XCTMeasurementInvocationManuallyStart];
    [self measureWithOptions:options block:^{}];
}

- (void)testMeasuresTwice
{
    [self measureWithMetrics:[[self class] defaultMetrics] block:^{}];
    [self measureWithMetrics:[[self class] defaultMetrics] block:^{}];
}

- (void)testMetricError
{
    WidgetMetric *widgets = [[[WidgetMetric alloc] init] autorelease];

    widgets->fail = YES;
    [self measureWithMetrics:[NSArray arrayWithObject:widgets] block:^{}];
}

- (void)testZeroIterations
{
    XCTMeasureOptions *options = [[[XCTMeasureOptions alloc] init] autorelease];

    [options setIterationCount:0];
    [self measureWithOptions:options block:^{}];
}

// Baselined to 100 widgets; reports far fewer, which is worse.
- (void)testWidgetsRegress
{
    [self measureWithMetrics:[NSArray arrayWithObject:[[[WidgetMetric alloc] init] autorelease]] block:^{}];
}

@end
