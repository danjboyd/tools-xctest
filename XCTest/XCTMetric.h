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

#import <Foundation/Foundation.h>
#import <XCTest/XCTestCase.h>

/*! A point in time for measurements: a monotonic clock reading (in
 * nanoseconds, where Apple uses mach_absolute_time) and the date. */
@interface XCTPerformanceMeasurementTimestamp : NSObject {
    uint64_t _absoluteTime;
    NSDate *_date;
}
/*! Now. */
- (id) init;
- (id) initWithAbsoluteTime: (uint64_t)absoluteTime date: (NSDate *)date;
@property (readonly) uint64_t absoluteTime;
/*! absoluteTime in nanoseconds (the same value, on this platform). */
@property (readonly) uint64_t absoluteTimeNanoSeconds;
@property (readonly) NSDate *date;
@end

typedef enum {
    XCTPerformanceMeasurementPolarityPrefersSmaller = -1,
    XCTPerformanceMeasurementPolarityUnspecified = 0,
    XCTPerformanceMeasurementPolarityPrefersLarger = 1,
} XCTPerformanceMeasurementPolarity;

/*! One value reported by a metric for one run of the measured block. */
@interface XCTPerformanceMeasurement : NSObject {
    NSString *_identifier;
    NSString *_displayName;
    NSMeasurement *_value;
    XCTPerformanceMeasurementPolarity _polarity;
}
- (id) initWithIdentifier: (NSString *)identifier
              displayName: (NSString *)displayName
              doubleValue: (double)doubleValue
               unitSymbol: (NSString *)unitSymbol;
- (id) initWithIdentifier: (NSString *)identifier
              displayName: (NSString *)displayName
              doubleValue: (double)doubleValue
               unitSymbol: (NSString *)unitSymbol
                 polarity: (XCTPerformanceMeasurementPolarity)polarity;
- (id) initWithIdentifier: (NSString *)identifier
              displayName: (NSString *)displayName
                    value: (NSMeasurement *)value;
- (id) initWithIdentifier: (NSString *)identifier
              displayName: (NSString *)displayName
                    value: (NSMeasurement *)value
                 polarity: (XCTPerformanceMeasurementPolarity)polarity;
/*! Identifies the measurement in baselines, e.g. "com.apple.dt.XCTMetric_Clock.time.monotonic". */
@property (readonly, copy) NSString *identifier;
/*! e.g. "Clock Monotonic Time". */
@property (readonly, copy) NSString *displayName;
@property (readonly, copy) NSMeasurement *value;
@property (readonly) double doubleValue;
@property (readonly, copy) NSString *unitSymbol;
/*! Whether larger or smaller is better; a baseline regression is only
 * judged when it's known. Defaults to PrefersSmaller. */
@property (readonly) XCTPerformanceMeasurementPolarity polarity;
@end

/*!
 * Something measured around each run of a block passed to
 * -measureWithMetrics:block:. The optional methods are called around each
 * run; afterwards the metric reports its measurements for that run.
 */
@protocol XCTMetric <NSCopying, NSObject>
- (NSArray *) reportMeasurementsFromStartTime: (XCTPerformanceMeasurementTimestamp *)startTime
                                    toEndTime: (XCTPerformanceMeasurementTimestamp *)endTime
                                        error: (NSError **)error;
@optional
- (void) willBeginMeasuring;
- (void) didStartMeasuring;
- (void) didStopMeasuring;
@end

/*! Elapsed time on the monotonic clock ("Clock Monotonic Time", s). */
@interface XCTClockMetric : NSObject <XCTMetric>
@end

/*! CPU time (user + system) used by the process, or only the measuring
 * thread ("CPU Time", s). Apple's cycle and instruction counts aren't
 * reported. */
@interface XCTCPUMetric : NSObject <XCTMetric> {
    BOOL _currentThreadOnly;
    double _startCPUTime;
    double _stopCPUTime;
}
- (id) init;
- (id) initLimitingToCurrentThread: (BOOL)limitToCurrentThread;
@end

/*! The process's resident memory: its change over the run ("Memory
 * Physical", kB) and its peak during the run ("Memory Peak Physical", kB;
 * the peak is reset at the start of each run where Linux allows it). */
@interface XCTMemoryMetric : NSObject <XCTMetric> {
    double _startResident;
    double _stopResident;
    double _peakResident;
}
@end

/*! Data the process wrote through write calls ("Disk Logical Writes", kB). */
@interface XCTStorageMetric : NSObject <XCTMetric> {
    double _startWritten;
    double _stopWritten;
}
@end

typedef enum {
    XCTMeasurementInvocationNone = 0,
    /*! The block calls -startMeasuring itself. */
    XCTMeasurementInvocationManuallyStart = 1 << 0,
    /*! The block calls -stopMeasuring itself. */
    XCTMeasurementInvocationManuallyStop = 1 << 1,
} XCTMeasurementInvocationOptions;

@interface XCTMeasureOptions : NSObject <NSCopying> {
    XCTMeasurementInvocationOptions _invocationOptions;
    NSUInteger _iterationCount;
}
/*! Automatic start and stop, 5 iterations. */
+ (XCTMeasureOptions *) defaultOptions;
@property XCTMeasurementInvocationOptions invocationOptions;
/*! How many times the block runs. Defaults to 5. */
@property NSUInteger iterationCount;
@end

@interface XCTestCase (XCTPerformanceAnalysis)

/*! [XCTClockMetric]. */
+ (NSArray *) defaultMetrics;
+ (XCTMeasureOptions *) defaultMeasureOptions;

/*!
 * Runs \a block (options' iterationCount times) and reports, for each
 * measurement the metrics give, its average and relative standard
 * deviation; a baseline in -performance-baselines (under the test's
 * "metrics", by measurement identifier) fails the test if the average
 * regresses past it. Call at most one measure method per test.
 */
- (void) measureWithMetrics: (NSArray *)metrics block: (void (^)(void))block;
- (void) measureWithMetrics: (NSArray *)metrics
                    options: (XCTMeasureOptions *)options
                      block: (void (^)(void))block;
- (void) measureWithOptions: (XCTMeasureOptions *)options block: (void (^)(void))block;

@end
