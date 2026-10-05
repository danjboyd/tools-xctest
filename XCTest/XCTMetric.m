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

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#import <XCTest/XCTMetric.h>
#import <XCTest/XCTestPrivate.h>

#include <stdio.h>
#include <string.h>
#include <sys/resource.h>
#include <time.h>

static uint64_t GSMonotonicNanoseconds(void)
{
    struct timespec now;

    clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint64_t)now.tv_sec * 1000000000ULL + (uint64_t)now.tv_nsec;
}

// The value of a "Name:   1234 ..." line in a /proc file, or -1.
static double GSProcValue(const char *path, const char *name)
{
    FILE *file = fopen(path, "r");
    char line[256];
    size_t length = strlen(name);
    double value = -1;

    if (file == NULL) {
        return -1;
    }
    while (fgets(line, sizeof(line), file) != NULL) {
        if (strncmp(line, name, length) == 0 && line[length] == ':') {
            value = strtod(line + length + 1, NULL);
            break;
        }
    }
    fclose(file);
    return value;
}

@implementation XCTPerformanceMeasurementTimestamp

- (id) init
{
    return [self initWithAbsoluteTime:GSMonotonicNanoseconds() date:[NSDate date]];
}

- (id) initWithAbsoluteTime: (uint64_t)absoluteTime date: (NSDate *)date
{
    self = [super init];
    if (self) {
        _absoluteTime = absoluteTime;
        _date = [(date ? date : [NSDate date]) retain];
    }
    return self;
}

- (void) dealloc
{
    [_date release];
    [super dealloc];
}

- (uint64_t) absoluteTime
{
    return _absoluteTime;
}

- (uint64_t) absoluteTimeNanoSeconds
{
    return _absoluteTime;
}

- (NSDate *) date
{
    return _date;
}

@end

@implementation XCTPerformanceMeasurement

- (id) initWithIdentifier: (NSString *)identifier
              displayName: (NSString *)displayName
              doubleValue: (double)doubleValue
               unitSymbol: (NSString *)unitSymbol
{
    return [self initWithIdentifier:identifier displayName:displayName doubleValue:doubleValue
                         unitSymbol:unitSymbol polarity:XCTPerformanceMeasurementPolarityPrefersSmaller];
}

- (id) initWithIdentifier: (NSString *)identifier
              displayName: (NSString *)displayName
              doubleValue: (double)doubleValue
               unitSymbol: (NSString *)unitSymbol
                 polarity: (XCTPerformanceMeasurementPolarity)polarity
{
    NSUnit *unit = [[[NSUnit alloc] initWithSymbol:(unitSymbol ? unitSymbol : @"")] autorelease];
    NSMeasurement *value = [[[NSMeasurement alloc] initWithDoubleValue:doubleValue unit:unit] autorelease];

    return [self initWithIdentifier:identifier displayName:displayName value:value polarity:polarity];
}

- (id) initWithIdentifier: (NSString *)identifier
              displayName: (NSString *)displayName
                    value: (NSMeasurement *)value
{
    return [self initWithIdentifier:identifier displayName:displayName value:value
                           polarity:XCTPerformanceMeasurementPolarityPrefersSmaller];
}

- (id) initWithIdentifier: (NSString *)identifier
              displayName: (NSString *)displayName
                    value: (NSMeasurement *)value
                 polarity: (XCTPerformanceMeasurementPolarity)polarity
{
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _displayName = [(displayName ? displayName : identifier) copy];
        _value = [value copy];
        _polarity = polarity;
    }
    return self;
}

- (void) dealloc
{
    [_identifier release];
    [_displayName release];
    [_value release];
    [super dealloc];
}

- (NSString *) identifier
{
    return _identifier;
}

- (NSString *) displayName
{
    return _displayName;
}

- (NSMeasurement *) value
{
    return _value;
}

- (double) doubleValue
{
    return [_value doubleValue];
}

- (NSString *) unitSymbol
{
    return [[_value unit] symbol];
}

- (XCTPerformanceMeasurementPolarity) polarity
{
    return _polarity;
}

@end

static XCTPerformanceMeasurement *GSMeasurement(NSString *identifier, NSString *name, double value, NSString *unit)
{
    return [[[XCTPerformanceMeasurement alloc] initWithIdentifier:identifier
                                                      displayName:name
                                                      doubleValue:value
                                                       unitSymbol:unit] autorelease];
}

@implementation XCTClockMetric

- (id) copyWithZone: (NSZone *)zone
{
    return [[[self class] allocWithZone:zone] init];
}

- (NSArray *) reportMeasurementsFromStartTime: (XCTPerformanceMeasurementTimestamp *)startTime
                                    toEndTime: (XCTPerformanceMeasurementTimestamp *)endTime
                                        error: (NSError **)error
{
    double seconds = ([endTime absoluteTime] - [startTime absoluteTime]) / 1e9;

    return [NSArray arrayWithObject:GSMeasurement(@"com.apple.dt.XCTMetric_Clock.time.monotonic",
                                                  @"Clock Monotonic Time", seconds, @"s")];
}

@end

@implementation XCTCPUMetric

- (id) init
{
    return [self initLimitingToCurrentThread:NO];
}

- (id) initLimitingToCurrentThread: (BOOL)limitToCurrentThread
{
    self = [super init];
    if (self) {
        _currentThreadOnly = limitToCurrentThread;
    }
    return self;
}

- (id) copyWithZone: (NSZone *)zone
{
    return [[[self class] allocWithZone:zone] initLimitingToCurrentThread:_currentThreadOnly];
}

- (double) _gsCPUTime
{
    struct rusage usage;

    if (getrusage(_currentThreadOnly ? RUSAGE_THREAD : RUSAGE_SELF, &usage) != 0) {
        return 0;
    }
    return usage.ru_utime.tv_sec + usage.ru_utime.tv_usec / 1e6
        + usage.ru_stime.tv_sec + usage.ru_stime.tv_usec / 1e6;
}

- (void) didStartMeasuring
{
    _startCPUTime = [self _gsCPUTime];
}

- (void) didStopMeasuring
{
    _stopCPUTime = [self _gsCPUTime];
}

- (NSArray *) reportMeasurementsFromStartTime: (XCTPerformanceMeasurementTimestamp *)startTime
                                    toEndTime: (XCTPerformanceMeasurementTimestamp *)endTime
                                        error: (NSError **)error
{
    return [NSArray arrayWithObject:GSMeasurement(@"com.apple.dt.XCTMetric_CPU.time", @"CPU Time",
                                                  _stopCPUTime - _startCPUTime, @"s")];
}

@end

@implementation XCTMemoryMetric

- (id) copyWithZone: (NSZone *)zone
{
    return [[[self class] allocWithZone:zone] init];
}

- (void) didStartMeasuring
{
    // Resets the peak (VmHWM) to the current size, where allowed.
    FILE *clearRefs = fopen("/proc/self/clear_refs", "w");

    if (clearRefs != NULL) {
        fputs("5", clearRefs);
        fclose(clearRefs);
    }
    _startResident = GSProcValue("/proc/self/status", "VmRSS");
}

- (void) didStopMeasuring
{
    _stopResident = GSProcValue("/proc/self/status", "VmRSS");
    _peakResident = GSProcValue("/proc/self/status", "VmHWM");
}

- (NSArray *) reportMeasurementsFromStartTime: (XCTPerformanceMeasurementTimestamp *)startTime
                                    toEndTime: (XCTPerformanceMeasurementTimestamp *)endTime
                                        error: (NSError **)error
{
    if (_startResident < 0 || _stopResident < 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"XCTestErrorDomain" code:0 userInfo:
                [NSDictionary dictionaryWithObject:@"Could not read /proc/self/status"
                                            forKey:NSLocalizedDescriptionKey]];
        }
        return nil;
    }

    return [NSArray arrayWithObjects:
        GSMeasurement(@"com.apple.dt.XCTMetric_Memory.physical", @"Memory Physical",
                      _stopResident - _startResident, @"kB"),
        GSMeasurement(@"com.apple.dt.XCTMetric_Memory.physical_peak", @"Memory Peak Physical",
                      _peakResident, @"kB"),
        nil];
}

@end

@implementation XCTStorageMetric

- (id) copyWithZone: (NSZone *)zone
{
    return [[[self class] allocWithZone:zone] init];
}

- (void) didStartMeasuring
{
    _startWritten = GSProcValue("/proc/self/io", "wchar");
}

- (void) didStopMeasuring
{
    _stopWritten = GSProcValue("/proc/self/io", "wchar");
}

- (NSArray *) reportMeasurementsFromStartTime: (XCTPerformanceMeasurementTimestamp *)startTime
                                    toEndTime: (XCTPerformanceMeasurementTimestamp *)endTime
                                        error: (NSError **)error
{
    if (_startWritten < 0 || _stopWritten < 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"XCTestErrorDomain" code:0 userInfo:
                [NSDictionary dictionaryWithObject:@"Could not read /proc/self/io"
                                            forKey:NSLocalizedDescriptionKey]];
        }
        return nil;
    }

    return [NSArray arrayWithObject:GSMeasurement(@"com.apple.dt.XCTMetric_Disk.logical_writes",
                                                  @"Disk Logical Writes", (_stopWritten - _startWritten) / 1024.0, @"kB")];
}

@end

@implementation XCTMeasureOptions

+ (XCTMeasureOptions *) defaultOptions
{
    return [[[self alloc] init] autorelease];
}

- (id) init
{
    self = [super init];
    if (self) {
        _iterationCount = 5;
    }
    return self;
}

- (id) copyWithZone: (NSZone *)zone
{
    XCTMeasureOptions *copy = [[[self class] allocWithZone:zone] init];

    [copy setInvocationOptions:_invocationOptions];
    [copy setIterationCount:_iterationCount];
    return copy;
}

- (XCTMeasurementInvocationOptions) invocationOptions
{
    return _invocationOptions;
}

- (void) setInvocationOptions: (XCTMeasurementInvocationOptions)invocationOptions
{
    _invocationOptions = invocationOptions;
}

- (NSUInteger) iterationCount
{
    return _iterationCount;
}

- (void) setIterationCount: (NSUInteger)iterationCount
{
    _iterationCount = iterationCount;
}

@end
