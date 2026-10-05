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
#import <XCTest/XCTestPrivate.h>

#include <math.h>
#include <time.h>

XCTPerformanceMetric const XCTPerformanceMetric_WallClockTime = @"com.apple.XCTPerformanceMetric_WallClockTime";

// Apple's measureBlock: also runs its block 10 times.
static const NSUInteger GSMeasureIterations = 10;
static const double GSDefaultMaxPercentRegression = 10.0;

static double GSMonotonicSeconds(void)
{
    struct timespec now;

    clock_gettime(CLOCK_MONOTONIC, &now);
    return now.tv_sec + now.tv_nsec / 1e9;
}

/*! Per-test measuring state. */
@interface GSXCTPerformanceState : NSObject {
@public
    BOOL measured;
    BOOL insideMeasureBlock;
    NSUInteger startCount;
    NSUInteger stopCount;
    double startTime;
    double elapsed;
}
@end

@implementation GSXCTPerformanceState
@end

@implementation GSXCTMeasurement

@synthesize metricIdentifier = _metricIdentifier;
@synthesize values = _values;
@synthesize baselineAverage = _baselineAverage;
@synthesize maxPercentRegression = _maxPercentRegression;

- (void) dealloc
{
    [_metricIdentifier release];
    [_values release];
    [_baselineAverage release];
    [super dealloc];
}

- (double) average
{
    double sum = 0;

    for (NSNumber *value in _values) {
        sum += [value doubleValue];
    }

    return [_values count] ? sum / [_values count] : 0;
}

- (double) relativeStandardDeviation
{
    double average = [self average];
    double squares = 0;

    if ([_values count] < 2 || average == 0) {
        return 0;
    }

    for (NSNumber *value in _values) {
        squares += ([value doubleValue] - average) * ([value doubleValue] - average);
    }

    return sqrt(squares / ([_values count] - 1)) / average * 100.0;
}

- (NSString *) valuesDescription
{
    NSMutableArray *values = [NSMutableArray array];

    for (NSNumber *value in _values) {
        [values addObject:[NSString stringWithFormat:@"%.6f", [value doubleValue]]];
    }

    return [NSString stringWithFormat:@"[%@]", [values componentsJoinedByString:@", "]];
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
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:GSMeasureIterations];

    if (state->measured) {
        [self _gsPerformanceFailure:@"API violation - measure methods can only be called once per test."];
        return;
    }
    state->measured = YES;

    for (NSString *metric in metrics) {
        if (![metric isEqualToString:XCTPerformanceMetric_WallClockTime]) {
            [self _gsPerformanceFailure:[NSString stringWithFormat:@"Unsupported performance metric: %@", metric]];
            return;
        }
    }
    if (![metrics containsObject:XCTPerformanceMetric_WallClockTime]) {
        [self _gsPerformanceFailure:@"No performance metrics to measure."];
        return;
    }

    for (NSUInteger iteration = 0; iteration < GSMeasureIterations; iteration++) {
        state->startCount = 0;
        state->stopCount = 0;
        state->elapsed = 0;
        state->insideMeasureBlock = YES;

        @try {
            @autoreleasepool {
                if (automaticallyStartMeasuring) {
                    [self startMeasuring];
                }
                block();
                if (automaticallyStartMeasuring && state->stopCount == 0) {
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
        [values addObject:[NSNumber numberWithDouble:state->elapsed]];
    }

    [self _gsReportMeasurementWithValues:values];
}

- (void) _gsReportMeasurementWithValues: (NSArray *)values
{
    GSXCTestRunner *runner = [GSXCTestRunner sharedRunner];
    NSString *identifier = [NSString stringWithFormat:@"%@/%@",
        NSStringFromClass([self class]), [self _gsMethodName]];
    NSDictionary *baseline = [runner _gsPerformanceBaselineForTest:identifier];
    GSXCTMeasurement *measurement = [[[GSXCTMeasurement alloc] init] autorelease];
    NSNumber *maxRegression = [baseline objectForKey:@"maxPercentRegression"];

    [measurement setMetricIdentifier:XCTPerformanceMetric_WallClockTime];
    [measurement setValues:values];
    [measurement setBaselineAverage:[baseline objectForKey:@"average"]];
    [measurement setMaxPercentRegression:maxRegression ? [maxRegression doubleValue] : GSDefaultMaxPercentRegression];

    [[XCTestObservationCenter sharedTestObservationCenter] _gsNotifyObservers:^(id observer) {
        if ([observer respondsToSelector:@selector(_gsTestCase:didMeasure:)]) {
            [observer _gsTestCase:self didMeasure:measurement];
        }
    }];

    [runner _gsRecordPerformanceAverage:[measurement average] forTest:identifier];

    if ([measurement baselineAverage] != nil) {
        double baselineAverage = [[measurement baselineAverage] doubleValue];
        double percentWorse = baselineAverage > 0
            ? ([measurement average] - baselineAverage) / baselineAverage * 100.0
            : 0;

        if (percentWorse > [measurement maxPercentRegression]) {
            [self _gsPerformanceRegression:[NSString stringWithFormat:
                @"[Time, seconds] average: %.6f, %.1f%% worse than baseline %.6f (max allowed regression %.1f%%)",
                [measurement average], percentWorse, baselineAverage, [measurement maxPercentRegression]]];
        }
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

    state->startTime = GSMonotonicSeconds();
}

- (void) stopMeasuring
{
    double now = GSMonotonicSeconds();
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

    state->elapsed = now - state->startTime;
}

@end
