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
#if defined(_WIN32)
        // The file system representation is UTF-16 there.
        FILE *file = _wfopen((const wchar_t *)[path fileSystemRepresentation], L"w");
#else
        FILE *file = fopen([path fileSystemRepresentation], "w");
#endif
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

// Hardware counters, where the system allows them; the test passes
// either way.
- (void)testHardwareCounters
{
    NSArray *metrics = [NSArray arrayWithObjects:[[[XCTCPUMetric alloc] init] autorelease],
        [[[GSXCTHardwareCounterMetric alloc] init] autorelease], nil];
    XCTMeasureOptions *options = [XCTMeasureOptions defaultOptions];

    [options setIterationCount:3];
    [self measureWithMetrics:metrics options:options block:^{
        volatile unsigned long sum = 0;
        for (unsigned long i = 0; i < 2000000; i++) { sum += i; }
    }];
    NSLog(@"counters available: %@", [GSXCTHardwareCounterMetric isAvailable] ? @"YES" : @"NO");
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

// Reports the next of a fixed series of values each run (the first is the
// warm-up's), so comparisons with baselines are deterministic.
@interface SeriesMetric : NSObject <XCTMetric> {
    NSArray *values;
    NSUInteger run;
}
- (id)initWithValues:(NSArray *)someValues;
@end

@implementation SeriesMetric

- (id)initWithValues:(NSArray *)someValues
{
    if ((self = [super init])) values = [someValues copy];
    return self;
}
- (void)dealloc { [values release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }

- (NSArray *)reportMeasurementsFromStartTime:(XCTPerformanceMeasurementTimestamp *)startTime
                                   toEndTime:(XCTPerformanceMeasurementTimestamp *)endTime
                                       error:(NSError **)error
{
    double value = [[values objectAtIndex:run++ % [values count]] doubleValue];

    return [NSArray arrayWithObject:[[[XCTPerformanceMeasurement alloc]
        initWithIdentifier:@"com.example.series" displayName:@"Series" doubleValue:value unitSymbol:@"u"] autorelease]];
}

@end

// Each is baselined to an average of 100 (see run-metric-tests.sh).
@interface MetricVerdictTests : XCTestCase
@end

@implementation MetricVerdictTests

- (void)measureSeries:(NSArray *)values
{
    [self measureWithMetrics:[NSArray arrayWithObject:[[[SeriesMetric alloc] initWithValues:values] autorelease]]
                       block:^{}];
}

// Steadily 11% worse: significant.
- (void)testSignificantRegression
{
    [self measureSeries:[NSArray arrayWithObjects:@0, @110, @112, @111, @113, @109, nil]];
}

// 12% worse on average, but all over the place: not significant.
- (void)testNoisyRegression
{
    [self measureSeries:[NSArray arrayWithObjects:@0, @80, @140, @100, @150, @90, nil]];
}

// Within the allowed regression, but noisier than the baseline allows.
- (void)testTooNoisy
{
    [self measureSeries:[NSArray arrayWithObjects:@0, @90, @110, @95, @105, @100, nil]];
}

// Better than the baseline.
- (void)testImprovement
{
    [self measureSeries:[NSArray arrayWithObjects:@0, @90, @91, @89, @90, @90, nil]];
}

@end
