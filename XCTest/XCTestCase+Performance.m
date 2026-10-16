/*
 This file is part of the GNUstep XCTEST Library.

 This library is free software; you can redistribute it and/or
 modify it under the terms of the GNU Lesser General Public
 License as published by the Free Software Foundation; either
 version 2 of the License, or (at your option) any later version.

 This library is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.     See the GNU
 Lesser General Public License for more details.

 You should have received a copy of the GNU Lesser General Public
 License along with this library; see the file COPYING.LIB.
 If not, see <http://www.gnu.org/licenses/> or write to the
 Free Software Foundation, 51 Franklin Street, Fifth Floor,
 Boston, MA 02110-1301, USA.
*/

#import <XCTest/XCTestCase.h>
#import <XCTest/XCTMetric.h>
#import <XCTest/XCTestPrivate.h>
#import <XCTest/GSXCTStatistics.h>

#include <math.h>

XCTPerformanceMetric const XCTPerformanceMetric_WallClockTime = @"com.apple.XCTPerformanceMetric_WallClockTime";

// Apple's measureBlock: also runs its block 10 times.
static const NSUInteger GSMeasureIterations = 10;
static const double GSDefaultMaxPercentRegression = 10.0;

// A number in a baseline entry, or nil if it's missing or not a number.
static NSNumber *GSBaselineNumber(NSDictionary *baseline, NSString *key)
{
    id value = [baseline objectForKey:key];

    return [value isKindOfClass:[NSNumber class]] ? value : nil;
}

/*! The metric behind -measureBlock:, reported as Apple reports it. */
@interface GSXCTWallClockMetric : XCTClockMetric
@end

@implementation GSXCTWallClockMetric

- (NSArray *) reportMeasurementsFromStartTime: (XCTPerformanceMeasurementTimestamp *)startTime
                                    toEndTime: (XCTPerformanceMeasurementTimestamp *)endTime
                                        error: (NSError **)error
{
    double seconds = ([endTime absoluteTime] - [startTime absoluteTime]) / 1e9;

    return [NSArray arrayWithObject:[[[XCTPerformanceMeasurement alloc]
        initWithIdentifier:XCTPerformanceMetric_WallClockTime
               displayName:@"Time"
               doubleValue:seconds
                unitSymbol:@"seconds"] autorelease]];
}

@end

/*! Per-test measuring state. */
@interface GSXCTPerformanceState : NSObject {
@public
    BOOL measured;
    BOOL insideMeasureBlock;
    NSUInteger startCount;
    NSUInteger stopCount;
    NSArray *metrics;
    XCTPerformanceMeasurementTimestamp *startTime;
    XCTPerformanceMeasurementTimestamp *endTime;
}
@end

@implementation GSXCTPerformanceState

- (void) dealloc
{
    [metrics release];
    [startTime release];
    [endTime release];
    [super dealloc];
}

@end

@implementation GSXCTMeasurement

@synthesize metricIdentifier = _metricIdentifier;
@synthesize displayName = _displayName;
@synthesize unitSymbol = _unitSymbol;
@synthesize polarity = _polarity;
@synthesize values = _values;
@synthesize baselineAverage = _baselineAverage;
@synthesize maxPercentRegression = _maxPercentRegression;
@synthesize baselineStandardDeviation = _baselineStandardDeviation;
@synthesize baselineCount = _baselineCount;
@synthesize maxPercentRelativeStandardDeviation = _maxPercentRelativeStandardDeviation;
@synthesize verdict = _verdict;
@synthesize percentWorse = _percentWorse;
@synthesize pValue = _pValue;

- (id) init
{
    self = [super init];
    if (self) {
        _pValue = NAN;
    }
    return self;
}

- (void) dealloc
{
    [_metricIdentifier release];
    [_displayName release];
    [_unitSymbol release];
    [_values release];
    [_baselineAverage release];
    [_baselineStandardDeviation release];
    [_maxPercentRelativeStandardDeviation release];
    [super dealloc];
}

- (double) average
{
    return GSXCTSummarize(_values).mean;
}

- (double) median
{
    return GSXCTSummarize(_values).median;
}

- (double) minimum
{
    return GSXCTSummarize(_values).minimum;
}

- (double) maximum
{
    return GSXCTSummarize(_values).maximum;
}

- (double) standardDeviation
{
    return GSXCTSummarize(_values).standardDeviation;
}

- (double) relativeStandardDeviation
{
    GSXCTSummary summary = GSXCTSummarize(_values);

    if (summary.mean == 0) {
        return 0;
    }
    return fabs(summary.standardDeviation / summary.mean * 100.0);
}

- (void) judge
{
    GSXCTSummary summary = GSXCTSummarize(_values);
    double baseline = [_baselineAverage doubleValue];
    BOOL prefersLarger = (_polarity == XCTPerformanceMeasurementPolarityPrefersLarger);
    BOOL overThreshold, significant, noisy;

    _verdict = GSXCTMeasurementVerdictNone;
    _percentWorse = 0;
    _pValue = NAN;

    // Only a known polarity says which way is worse.
    if (_baselineAverage == nil || _polarity == XCTPerformanceMeasurementPolarityUnspecified) {
        return;
    }

    if (baseline > 0) {
        _percentWorse = (prefersLarger ? baseline - summary.mean : summary.mean - baseline) / baseline * 100.0;
    }
    if (_baselineStandardDeviation != nil && _baselineCount >= 2) {
        double baselineDeviation = [_baselineStandardDeviation doubleValue];

        _pValue = prefersLarger
            ? GSXCTWelchPValue(baseline, baselineDeviation, _baselineCount,
                               summary.mean, summary.standardDeviation, summary.count)
            : GSXCTWelchPValue(summary.mean, summary.standardDeviation, summary.count,
                               baseline, baselineDeviation, _baselineCount);
    }

    overThreshold = _percentWorse > _maxPercentRegression;
    // Without the statistics to test, past the threshold is a regression.
    significant = isnan(_pValue) || _pValue < GSXCTSignificanceLevel;
    noisy = _maxPercentRelativeStandardDeviation != nil
        && [self relativeStandardDeviation] > [_maxPercentRelativeStandardDeviation doubleValue];

    if (overThreshold && significant && !(noisy && isnan(_pValue))) {
        _verdict = GSXCTMeasurementVerdictRegressed;
    } else if (overThreshold || noisy) {
        _verdict = GSXCTMeasurementVerdictInconclusive;
    } else {
        _verdict = GSXCTMeasurementVerdictPassed;
    }
}

- (NSString *) verdictDescription
{
    NSString *comparison = [NSString stringWithFormat:
        @"%@ average: %.6f, %.1f%% worse than baseline %.6f (max allowed regression %.1f%%)",
        [self metricDescription], [self average], _percentWorse, [_baselineAverage doubleValue],
        _maxPercentRegression];

    if (_verdict == GSXCTMeasurementVerdictRegressed) {
        return isnan(_pValue) ? comparison : [comparison stringByAppendingFormat:@", p = %.3g", _pValue];
    }
    if (_verdict != GSXCTMeasurementVerdictInconclusive) {
        return nil;
    }
    if (_percentWorse > _maxPercentRegression && !isnan(_pValue)) {
        return [comparison stringByAppendingFormat:@", but not significantly (p = %.3f); inconclusive", _pValue];
    }
    return [NSString stringWithFormat:
        @"%@ relative standard deviation %.1f%% is above the baseline's maximum of %.1f%%; inconclusive",
        [self metricDescription], [self relativeStandardDeviation],
        [_maxPercentRelativeStandardDeviation doubleValue]];
}

- (NSString *) verdictName
{
    switch (_verdict) {
        case GSXCTMeasurementVerdictPassed: return @"passed";
        case GSXCTMeasurementVerdictRegressed: return @"regressed";
        case GSXCTMeasurementVerdictInconclusive: return @"inconclusive";
        default: return nil;
    }
}

- (NSString *) valuesDescription
{
    NSMutableArray *values = [NSMutableArray array];

    for (NSNumber *value in _values) {
        [values addObject:[NSString stringWithFormat:@"%.6f", [value doubleValue]]];
    }

    return [NSString stringWithFormat:@"[%@]", [values componentsJoinedByString:@", "]];
}

- (NSString *) metricDescription
{
    return [NSString stringWithFormat:@"[%@, %@]", _displayName, _unitSymbol];
}

- (NSString *) polarityDescription
{
    switch (_polarity) {
        case XCTPerformanceMeasurementPolarityPrefersLarger: return @"prefers larger";
        case XCTPerformanceMeasurementPolarityUnspecified: return @"unspecified";
        default: return @"prefers smaller";
    }
}

@end

@implementation XCTestCase (XCTPerformanceMeasurement)

+ (NSArray *) defaultPerformanceMetrics
{
    return [NSArray arrayWithObject:XCTPerformanceMetric_WallClockTime];
}

- (GSXCTPerformanceState *) _gsPerformanceState
{
    if (_gsPerformance == nil) {
        _gsPerformance = [[GSXCTPerformanceState alloc] init];
    }

    return _gsPerformance;
}

- (void) _gsPerformanceFailure: (NSString *)description
{
    [self recordIssue:_GSXCTMakeIssue(XCTIssueTypeAssertionFailure, description, nil, 0, nil)];
}

- (void) _gsPerformanceRegression: (NSString *)description
{
    [self recordIssue:_GSXCTMakeIssue(XCTIssueTypePerformanceRegression, description, nil, 0, nil)];
}

- (void) measureBlock: (void (^)(void))block
{
    [self measureMetrics:[[self class] defaultPerformanceMetrics]
         automaticallyStartMeasuring:YES
                            forBlock:block];
}

- (void) measureMetrics: (NSArray *)metrics
automaticallyStartMeasuring: (BOOL)automaticallyStartMeasuring
               forBlock: (void (^)(void))block
{
    GSXCTPerformanceState *state = [self _gsPerformanceState];

    if (state->measured) {
        [self _gsPerformanceFailure:@"API violation - measure methods can only be called once per test."];
        return;
    }

    for (NSString *metric in metrics) {
        if (![metric isEqualToString:XCTPerformanceMetric_WallClockTime]) {
            state->measured = YES;
            [self _gsPerformanceFailure:[NSString stringWithFormat:@"Unsupported performance metric: %@", metric]];
            return;
        }
    }
    if (![metrics containsObject:XCTPerformanceMetric_WallClockTime]) {
        state->measured = YES;
        [self _gsPerformanceFailure:@"No performance metrics to measure."];
        return;
    }

    // As Apple's does, every one of the 10 runs counts.
    [self _gsMeasureMetrics:[NSArray arrayWithObject:[[[GSXCTWallClockMetric alloc] init] autorelease]]
                 iterations:GSMeasureIterations
           warmUpIterations:0
             automaticStart:automaticallyStartMeasuring
              automaticStop:automaticallyStartMeasuring
                      block:block];
}

// Runs \a block \a warmUpIterations times, unless the runner's
// performanceWarmUpIterations overrides it, then \a iterations times, with
// \a metrics measuring each run; reports what they measured in the runs
// after the warm-up.
- (void) _gsMeasureMetrics: (NSArray *)metrics
                iterations: (NSUInteger)iterations
          warmUpIterations: (NSUInteger)warmUpIterations
            automaticStart: (BOOL)automaticStart
             automaticStop: (BOOL)automaticStop
                     block: (void (^)(void))block
{
    GSXCTPerformanceState *state = [self _gsPerformanceState];
    NSInteger warmUpOverride = [[GSXCTestRunner sharedRunner] performanceWarmUpIterations];
    // Measurement identifier -> GSXCTMeasurement, in the order first reported.
    NSMutableArray *identifiers = [NSMutableArray array];
    NSMutableDictionary *measurements = [NSMutableDictionary dictionary];
    NSMutableDictionary *values = [NSMutableDictionary dictionary];

    if (state->measured) {
        [self _gsPerformanceFailure:@"API violation - measure methods can only be called once per test."];
        return;
    }
    state->measured = YES;

    if ([metrics count] == 0) {
        [self _gsPerformanceFailure:@"No performance metrics to measure."];
        return;
    }
    if (iterations == 0) {
        [self _gsPerformanceFailure:@"The iteration count must be at least 1."];
        return;
    }

    [state->metrics release];
    state->metrics = [metrics copy];
    if (warmUpOverride >= 0) {
        warmUpIterations = (NSUInteger)warmUpOverride;
    }

    @try {
        [self _gsRunMetrics:metrics iterations:iterations warmUpIterations:warmUpIterations
             automaticStart:automaticStart automaticStop:automaticStop identifiers:identifiers
               measurements:measurements values:values block:block];
    }
    @finally {
        // Metrics can let go of what they held (the counters' files) now,
        // rather than when the test case is released at the end of the run.
        for (id<XCTMetric> metric in metrics) {
            if ([metric respondsToSelector:@selector(_gsDidFinishMeasuring)]) {
                [(id<GSXCTMetricFinishing>)metric _gsDidFinishMeasuring];
            }
        }
    }
}

// The runs of -_gsMeasureMetrics:..., reporting their measurements; stops
// at a failure (which it records).
- (void) _gsRunMetrics: (NSArray *)metrics
            iterations: (NSUInteger)iterations
      warmUpIterations: (NSUInteger)warmUpIterations
        automaticStart: (BOOL)automaticStart
         automaticStop: (BOOL)automaticStop
           identifiers: (NSMutableArray *)identifiers
          measurements: (NSMutableDictionary *)measurements
                values: (NSMutableDictionary *)values
                 block: (void (^)(void))block
{
    GSXCTPerformanceState *state = [self _gsPerformanceState];

    for (NSUInteger iteration = 0; iteration < warmUpIterations + iterations; iteration++) {
        BOOL warmingUp = (iteration < warmUpIterations);

        state->startCount = 0;
        state->stopCount = 0;
        state->insideMeasureBlock = YES;

        for (id<XCTMetric> metric in metrics) {
            if ([metric respondsToSelector:@selector(willBeginMeasuring)]) {
                [metric willBeginMeasuring];
            }
        }

        @try {
            @autoreleasepool {
                if (automaticStart) {
                    [self startMeasuring];
                }
                block();
                // A run that never started is reported below, not stopped.
                if (automaticStop && state->stopCount == 0 && state->startCount > 0) {
                    [self stopMeasuring];
                }
            }
        }
        @finally {
            state->insideMeasureBlock = NO;
        }

        if (state->startCount != 1 || state->stopCount != 1) {
            [self _gsPerformanceFailure:@"Must call -startMeasuring and -stopMeasuring once in each run of the measured block."];
            return;
        }

        for (id<XCTMetric> metric in metrics) {
            NSError *error = nil;
            NSArray *reported = [metric reportMeasurementsFromStartTime:state->startTime
                                                              toEndTime:state->endTime
                                                                  error:&error];

            if (reported == nil) {
                [self _gsPerformanceFailure:[NSString stringWithFormat:@"Failed to measure %@: %@",
                    NSStringFromClass([(NSObject *)metric class]),
                    error ? [error localizedDescription] : @"no measurements"]];
                return;
            }
            // A warm-up run goes through the same steps, but isn't counted.
            if (warmingUp) {
                continue;
            }
            for (XCTPerformanceMeasurement *reportedMeasurement in reported) {
                NSString *identifier = [reportedMeasurement identifier];

                if ([measurements objectForKey:identifier] == nil) {
                    GSXCTMeasurement *measurement = [[[GSXCTMeasurement alloc] init] autorelease];

                    [measurement setMetricIdentifier:identifier];
                    [measurement setDisplayName:[reportedMeasurement displayName]];
                    [measurement setUnitSymbol:[reportedMeasurement unitSymbol]];
                    [measurement setPolarity:[reportedMeasurement polarity]];
                    [measurements setObject:measurement forKey:identifier];
                    [values setObject:[NSMutableArray array] forKey:identifier];
                    [identifiers addObject:identifier];
                }
                [[values objectForKey:identifier] addObject:
                    [NSNumber numberWithDouble:[reportedMeasurement doubleValue]]];
            }
        }
    }

    for (NSString *identifier in identifiers) {
        GSXCTMeasurement *measurement = [measurements objectForKey:identifier];

        [measurement setValues:[values objectForKey:identifier]];
        [self _gsReportMeasurement:measurement];
    }
}

- (void) _gsReportMeasurement: (GSXCTMeasurement *)measurement
{
    GSXCTestRunner *runner = [GSXCTestRunner sharedRunner];
    NSString *test = [NSString stringWithFormat:@"%@/%@",
        NSStringFromClass([self class]), [self _gsMethodName]];
    NSDictionary *baseline = [runner _gsPerformanceBaselineForTest:test metric:[measurement metricIdentifier]];
    NSNumber *maxRegression = GSBaselineNumber(baseline, @"maxPercentRegression");

    [measurement setBaselineAverage:GSBaselineNumber(baseline, @"average")];
    [measurement setMaxPercentRegression:maxRegression ? [maxRegression doubleValue] : GSDefaultMaxPercentRegression];
    [measurement setBaselineStandardDeviation:GSBaselineNumber(baseline, @"stddev")];
    [measurement setBaselineCount:[GSBaselineNumber(baseline, @"count") unsignedIntegerValue]];
    [measurement setMaxPercentRelativeStandardDeviation:GSBaselineNumber(baseline, @"maxPercentRelativeStandardDeviation")];
    [measurement judge];

    [[XCTestObservationCenter sharedTestObservationCenter] _gsNotifyObservers:^(id observer) {
        if ([observer respondsToSelector:@selector(_gsTestCase:didMeasure:)]) {
            [observer _gsTestCase:self didMeasure:measurement];
        }
    }];

    [runner _gsRecordPerformanceMeasurement:measurement forTest:test];

    if ([measurement verdict] == GSXCTMeasurementVerdictRegressed
        || ([measurement verdict] == GSXCTMeasurementVerdictInconclusive && [runner performanceInconclusiveFails])) {
        [self _gsPerformanceRegression:[measurement verdictDescription]];
    }
}

- (void) startMeasuring
{
    GSXCTPerformanceState *state = [self _gsPerformanceState];

    if (!state->insideMeasureBlock) {
        [self _gsPerformanceFailure:@"Cannot call -startMeasuring outside of a measure block."];
        return;
    }
    if (state->startCount++ > 0) {
        [self _gsPerformanceFailure:@"Cannot call -startMeasuring more than once per run of the measured block."];
        return;
    }

    for (id<XCTMetric> metric in state->metrics) {
        if ([metric respondsToSelector:@selector(didStartMeasuring)]) {
            [metric didStartMeasuring];
        }
    }
    [state->startTime release];
    state->startTime = [[XCTPerformanceMeasurementTimestamp alloc] init];
}

- (void) stopMeasuring
{
    XCTPerformanceMeasurementTimestamp *now = [[[XCTPerformanceMeasurementTimestamp alloc] init] autorelease];
    GSXCTPerformanceState *state = [self _gsPerformanceState];

    if (!state->insideMeasureBlock) {
        [self _gsPerformanceFailure:@"Cannot call -stopMeasuring outside of a measure block."];
        return;
    }
    if (state->startCount == 0) {
        [self _gsPerformanceFailure:@"Cannot call -stopMeasuring before -startMeasuring."];
        return;
    }
    if (state->stopCount++ > 0) {
        [self _gsPerformanceFailure:@"Cannot call -stopMeasuring more than once per run of the measured block."];
        return;
    }

    [state->endTime release];
    state->endTime = [now retain];
    for (id<XCTMetric> metric in state->metrics) {
        if ([metric respondsToSelector:@selector(didStopMeasuring)]) {
            [metric didStopMeasuring];
        }
    }
}

@end

@implementation XCTestCase (XCTPerformanceAnalysis)

+ (NSArray *) defaultMetrics
{
    return [NSArray arrayWithObject:[[[XCTClockMetric alloc] init] autorelease]];
}

+ (XCTMeasureOptions *) defaultMeasureOptions
{
    return [XCTMeasureOptions defaultOptions];
}

- (void) measureWithMetrics: (NSArray *)metrics block: (void (^)(void))block
{
    [self measureWithMetrics:metrics options:[[self class] defaultMeasureOptions] block:block];
}

- (void) measureWithOptions: (XCTMeasureOptions *)options block: (void (^)(void))block
{
    [self measureWithMetrics:[[self class] defaultMetrics] options:options block:block];
}

- (void) measureWithMetrics: (NSArray *)metrics
                    options: (XCTMeasureOptions *)options
                      block: (void (^)(void))block
{
    XCTMeasurementInvocationOptions invocation = [options invocationOptions];

    // Apple's metrics API runs the block once more first, as a warm-up.
    [self _gsMeasureMetrics:metrics
                 iterations:(options ? [options iterationCount] : 5)
           warmUpIterations:1
             automaticStart:!(invocation & XCTMeasurementInvocationManuallyStart)
              automaticStop:!(invocation & XCTMeasurementInvocationManuallyStop)
                      block:block];
}

@end
