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

#import <XCTest/XCTestRun.h>
#import <XCTest/XCTestPrivate.h>

NSString *_GSXCTDescribeException(NSException *exception)
{
    return [NSString stringWithFormat:@"\"%@\", \"%@\"", [exception name], [exception reason]];
}

@implementation XCTestRun

@synthesize test = _test;

+ (id) testRunWithTest: (XCTest *)test
{
    return [[[self alloc] initWithTest:test] autorelease];
}

- (id) initWithTest: (XCTest *)test
{
    self = [super init];
    if (self) {
        _test = [test retain];
    }

    return self;
}

- (void) dealloc
{
    [_test release];
    [_startDate release];
    [_stopDate release];
    [super dealloc];
}

- (void) start
{
    if (_startDate == nil) {
        _startDate = [[NSDate alloc] init];
    }
}

- (void) stop
{
    if (_startDate != nil && _stopDate == nil) {
        _stopDate = [[NSDate alloc] init];
    }
}

- (NSDate *) startDate
{
    return [[_startDate retain] autorelease];
}

- (NSDate *) stopDate
{
    return [[_stopDate retain] autorelease];
}

- (NSTimeInterval) totalDuration
{
    if (_startDate == nil) {
        return 0;
    }

    return [(_stopDate ? _stopDate : [NSDate date]) timeIntervalSinceDate:_startDate];
}

- (NSTimeInterval) testDuration
{
    return [self totalDuration];
}

- (NSUInteger) testCaseCount
{
    return [_test testCaseCount];
}

- (NSUInteger) executionCount
{
    return _stopDate != nil ? 1 : 0;
}

- (NSUInteger) skipCount
{
    return _hasBeenSkipped ? 1 : 0;
}

- (NSUInteger) failureCount
{
    @synchronized (self) {
        return _failureCount;
    }
}

- (NSUInteger) unexpectedExceptionCount
{
    @synchronized (self) {
        return _unexpectedExceptionCount;
    }
}

- (NSUInteger) totalFailureCount
{
    return [self failureCount] + [self unexpectedExceptionCount];
}

- (BOOL) hasSucceeded
{
    return [self totalFailureCount] == 0;
}

- (BOOL) hasBeenSkipped
{
    return _hasBeenSkipped;
}

- (void) recordFailureWithDescription: (NSString *)description
                               inFile: (NSString *)filePath
                               atLine: (NSUInteger)lineNumber
                             expected: (BOOL)expected
{
    [self _gsRecordIssue:[GSXCTestIssue issueWithMessage:description
                                                filePath:filePath
                                              lineNumber:lineNumber
                                              unexpected:!expected]];
}

- (void) _gsRecordIssue: (GSXCTestIssue *)issue
{
    @synchronized (self) {
        if ([issue unexpected]) {
            _unexpectedExceptionCount++;
        } else {
            _failureCount++;
        }
    }
}

@end

@implementation XCTestCaseRun

- (void) start
{
    XCTestCase *testCase = (XCTestCase *)[self test];

    [super start];
    [[XCTestObservationCenter sharedTestObservationCenter] _gsNotifyObservers:^(id observer) {
        if ([observer respondsToSelector:@selector(testCaseWillStart:)]) {
            [observer testCaseWillStart:testCase];
        }
    }];
}

- (void) stop
{
    XCTestCase *testCase = (XCTestCase *)[self test];

    [super stop];
    [[XCTestObservationCenter sharedTestObservationCenter] _gsNotifyObservers:^(id observer) {
        if ([observer respondsToSelector:@selector(testCaseDidFinish:)]) {
            [observer testCaseDidFinish:testCase];
        }
    }];
}

- (void) _gsRecordIssue: (GSXCTestIssue *)issue
{
    XCTestCase *testCase = (XCTestCase *)[self test];

    [super _gsRecordIssue:issue];
    [[XCTestObservationCenter sharedTestObservationCenter] _gsNotifyObservers:^(id observer) {
        if ([observer respondsToSelector:@selector(testCase:didFailWithDescription:inFile:atLine:)]) {
            [observer testCase:testCase didFailWithDescription:[issue message]
                        inFile:[issue filePath] atLine:[issue lineNumber]];
        }
        if ([observer respondsToSelector:@selector(_gsTestCase:didRecordIssue:)]) {
            [observer _gsTestCase:testCase didRecordIssue:issue];
        }
    }];
}

- (void) _gsRecordSkip: (GSXCTestIssue *)skip
{
    XCTestCase *testCase = (XCTestCase *)[self test];

    if (_hasBeenSkipped) {
        return;
    }

    _hasBeenSkipped = YES;
    [[XCTestObservationCenter sharedTestObservationCenter] _gsNotifyObservers:^(id observer) {
        if ([observer respondsToSelector:@selector(_gsTestCase:didSkipWithIssue:)]) {
            [observer _gsTestCase:testCase didSkipWithIssue:skip];
        }
    }];
}

@end

@implementation XCTestSuiteRun

- (id) initWithTest: (XCTest *)test
{
    self = [super initWithTest:test];
    if (self) {
        _testRuns = [[NSMutableArray alloc] init];
    }

    return self;
}

- (void) dealloc
{
    [_testRuns release];
    [_ownIssues release];
    [super dealloc];
}

- (NSArray *) testRuns
{
    return [[_testRuns copy] autorelease];
}

- (void) addTestRun: (XCTestRun *)testRun
{
    if (testRun != nil) {
        [_testRuns addObject:testRun];
    }
}

- (void) start
{
    XCTestSuite *suite = (XCTestSuite *)[self test];

    [super start];
    [[XCTestObservationCenter sharedTestObservationCenter] _gsNotifyObservers:^(id observer) {
        if ([observer respondsToSelector:@selector(testSuiteWillStart:)]) {
            [observer testSuiteWillStart:suite];
        }
    }];
}

- (void) stop
{
    XCTestSuite *suite = (XCTestSuite *)[self test];

    [super stop];
    [[XCTestObservationCenter sharedTestObservationCenter] _gsNotifyObservers:^(id observer) {
        if ([observer respondsToSelector:@selector(testSuiteDidFinish:)]) {
            [observer testSuiteDidFinish:suite];
        }
    }];
}

- (NSTimeInterval) testDuration
{
    NSTimeInterval duration = 0;

    for (XCTestRun *run in _testRuns) {
        duration += [run testDuration];
    }

    return duration;
}

- (NSUInteger) executionCount
{
    NSUInteger count = 0;

    for (XCTestRun *run in _testRuns) {
        count += [run executionCount];
    }

    return count;
}

- (NSUInteger) skipCount
{
    NSUInteger count = 0;

    for (XCTestRun *run in _testRuns) {
        count += [run skipCount];
    }

    return count;
}

- (NSUInteger) failureCount
{
    NSUInteger count = [super failureCount];

    for (XCTestRun *run in _testRuns) {
        count += [run failureCount];
    }

    return count;
}

- (NSUInteger) unexpectedExceptionCount
{
    NSUInteger count = [super unexpectedExceptionCount];

    for (XCTestRun *run in _testRuns) {
        count += [run unexpectedExceptionCount];
    }

    return count;
}

- (BOOL) hasBeenSkipped
{
    return [_testRuns count] > 0 && [self skipCount] == [_testRuns count];
}

- (NSArray *) _gsOwnIssues
{
    @synchronized (self) {
        return [[_ownIssues copy] autorelease];
    }
}

- (void) _gsRecordIssue: (GSXCTestIssue *)issue
{
    XCTestSuite *suite = (XCTestSuite *)[self test];

    [super _gsRecordIssue:issue];
    @synchronized (self) {
        if (_ownIssues == nil) {
            _ownIssues = [[NSMutableArray alloc] init];
        }
        [_ownIssues addObject:issue];
    }
    [[XCTestObservationCenter sharedTestObservationCenter] _gsNotifyObservers:^(id observer) {
        if ([observer respondsToSelector:@selector(testSuite:didFailWithDescription:inFile:atLine:)]) {
            [observer testSuite:suite didFailWithDescription:[issue message]
                         inFile:[issue filePath] atLine:[issue lineNumber]];
        }
        if ([observer respondsToSelector:@selector(_gsTestSuite:didRecordIssue:)]) {
            [observer _gsTestSuite:suite didRecordIssue:issue];
        }
    }];
}

@end
