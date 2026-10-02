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

#import <XCTest/XCTWaiter.h>
#import <XCTest/XCTestExpectation.h>
#import <XCTest/XCTestPrivate.h>

// How often the run loop is woken while waiting, so predicate expectations
// are re-evaluated and fulfillment from other threads is noticed promptly.
static const NSTimeInterval GSWaiterPollInterval = 0.01;

// The outcome of checking a set of expectations; 0 means keep waiting.
static XCTWaiterResult GSEvaluateExpectations(NSArray *expectations,
                                              BOOL enforceOrder,
                                              BOOL deadlinePassed,
                                              XCTestExpectation **culprit,
                                              XCTestExpectation **required)
{
    BOOL allFulfilled = YES;
    BOOL hasInverted = NO;
    NSUInteger lastToken = 0;
    XCTestExpectation *lastFulfilled = nil;
    XCTestExpectation *firstUnfulfilled = nil;

    for (XCTestExpectation *expectation in expectations) {
        if ([expectation isInverted]) {
            hasInverted = YES;
            if ([expectation _gsIsFulfilled]) {
                *culprit = expectation;
                return XCTWaiterResultInvertedFulfillment;
            }
            continue;
        }

        if (![expectation _gsIsFulfilled]) {
            allFulfilled = NO;
            if (firstUnfulfilled == nil) {
                firstUnfulfilled = expectation;
            }
            continue;
        }

        if (enforceOrder) {
            // Fulfilled while an earlier one is still outstanding, or
            // before an earlier one that has been fulfilled since.
            if (firstUnfulfilled != nil) {
                *culprit = expectation;
                *required = firstUnfulfilled;
                return XCTWaiterResultIncorrectOrder;
            }
            if ([expectation _gsFulfillmentToken] < lastToken) {
                *culprit = expectation;
                *required = lastFulfilled;
                return XCTWaiterResultIncorrectOrder;
            }
            lastToken = [expectation _gsFulfillmentToken];
            lastFulfilled = expectation;
        }
    }

    // Inverted expectations can only pass by surviving the whole timeout.
    if (allFulfilled && !hasInverted) {
        return XCTWaiterResultCompleted;
    }

    if (deadlinePassed) {
        return allFulfilled ? XCTWaiterResultCompleted : XCTWaiterResultTimedOut;
    }

    return 0;
}

static NSComparisonResult GSCompareFulfillmentOrder(id a, id b, void *context)
{
    NSUInteger tokenA = [a _gsFulfillmentToken];
    NSUInteger tokenB = [b _gsFulfillmentToken];

    if (tokenA < tokenB) {
        return NSOrderedAscending;
    }

    return tokenA > tokenB ? NSOrderedDescending : NSOrderedSame;
}

@implementation XCTWaiter

@synthesize delegate = _delegate;

- (id) init
{
    return [self initWithDelegate:nil];
}

- (id) initWithDelegate: (id<XCTWaiterDelegate>)delegate
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        _fulfilledExpectations = [[NSArray alloc] init];
    }

    return self;
}

- (void) dealloc
{
    [_fulfilledExpectations release];
    [super dealloc];
}

- (NSArray *) fulfilledExpectations
{
    return [[_fulfilledExpectations copy] autorelease];
}

- (NSTimeInterval) _gsTimeout
{
    return _timeout;
}

- (void) _gsPollTimerFired: (NSTimer *)timer
{
    // Nothing to do: firing wakes the run loop so the wait loop re-checks.
}

- (XCTWaiterResult) waitForExpectations: (NSArray *)expectations
                                timeout: (NSTimeInterval)seconds
{
    return [self waitForExpectations:expectations timeout:seconds enforceOrder:NO];
}

- (XCTWaiterResult) waitForExpectations: (NSArray *)expectations
                                timeout: (NSTimeInterval)seconds
                           enforceOrder: (BOOL)enforceOrderOfFulfillment
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
    NSTimer *pollTimer = [NSTimer timerWithTimeInterval:GSWaiterPollInterval
                                                 target:self
                                               selector:@selector(_gsPollTimerFired:)
                                               userInfo:nil
                                                repeats:YES];
    XCTestExpectation *culprit = nil;
    XCTestExpectation *required = nil;
    XCTWaiterResult result = 0;

    _timeout = seconds;
    [runLoop addTimer:pollTimer forMode:NSDefaultRunLoopMode];

    while (result == 0) {
        @autoreleasepool {
            for (XCTestExpectation *expectation in expectations) {
                [expectation _gsPoll];
            }

            result = GSEvaluateExpectations(expectations, enforceOrderOfFulfillment,
                                            [deadline timeIntervalSinceNow] <= 0,
                                            &culprit, &required);
            if (result == 0) {
                [runLoop runMode:NSDefaultRunLoopMode beforeDate:deadline];
            }
        }
    }

    [pollTimer invalidate];

    NSMutableArray *fulfilled = [NSMutableArray array];
    for (XCTestExpectation *expectation in expectations) {
        if ([expectation _gsIsFulfilled]) {
            [fulfilled addObject:expectation];
        }
    }
    [_fulfilledExpectations release];
    _fulfilledExpectations = [[fulfilled sortedArrayUsingFunction:GSCompareFulfillmentOrder context:NULL] retain];

    switch (result) {
        case XCTWaiterResultTimedOut:
            if ([_delegate respondsToSelector:@selector(waiter:didTimeoutWithUnfulfilledExpectations:)]) {
                NSMutableArray *unfulfilled = [NSMutableArray array];
                for (XCTestExpectation *expectation in expectations) {
                    if (![expectation isInverted] && ![expectation _gsIsFulfilled]) {
                        [unfulfilled addObject:expectation];
                    }
                }
                [_delegate waiter:self didTimeoutWithUnfulfilledExpectations:unfulfilled];
            }
            break;
        case XCTWaiterResultIncorrectOrder:
            if ([_delegate respondsToSelector:@selector(waiter:fulfillmentDidViolateOrderingConstraintsForExpectation:requiredExpectation:)]) {
                [_delegate waiter:self fulfillmentDidViolateOrderingConstraintsForExpectation:culprit
                                                                          requiredExpectation:required];
            }
            break;
        case XCTWaiterResultInvertedFulfillment:
            if ([_delegate respondsToSelector:@selector(waiter:didFulfillInvertedExpectation:)]) {
                [_delegate waiter:self didFulfillInvertedExpectation:culprit];
            }
            break;
        default:
            break;
    }

    return result;
}

+ (XCTWaiterResult) waitForExpectations: (NSArray *)expectations
                                timeout: (NSTimeInterval)seconds
{
    return [self waitForExpectations:expectations timeout:seconds enforceOrder:NO];
}

+ (XCTWaiterResult) waitForExpectations: (NSArray *)expectations
                                timeout: (NSTimeInterval)seconds
                           enforceOrder: (BOOL)enforceOrderOfFulfillment
{
    XCTWaiter *waiter = [[[self alloc] initWithDelegate:nil] autorelease];

    return [waiter waitForExpectations:expectations
                               timeout:seconds
                          enforceOrder:enforceOrderOfFulfillment];
}

@end
