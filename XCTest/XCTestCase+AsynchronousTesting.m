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

#import <XCTest/XCTestCase+AsynchronousTesting.h>
#import <XCTest/XCTestPrivate.h>

NSString * const XCTestErrorDomain = @"com.apple.XCTestErrorDomain";

static NSString *GSQuotedDescriptions(NSArray *expectations)
{
    NSMutableArray *quoted = [NSMutableArray arrayWithCapacity:[expectations count]];

    for (XCTestExpectation *expectation in expectations) {
        [quoted addObject:[NSString stringWithFormat:@"\"%@\"", [expectation expectationDescription]]];
    }

    return [quoted componentsJoinedByString:@", "];
}

@implementation XCTestCase (AsynchronousTesting)

- (id) _gsAddExpectation: (XCTestExpectation *)expectation
{
    @synchronized (self) {
        if (_expectations == nil) {
            _expectations = [[NSMutableArray alloc] init];
        }
        [_expectations addObject:expectation];
    }

    return expectation;
}

- (XCTestExpectation *) expectationWithDescription: (NSString *)description
{
    XCTestExpectation *expectation = [[[XCTestExpectation alloc] initWithDescription:description] autorelease];

    [expectation setAssertForOverFulfill:YES];
    return [self _gsAddExpectation:expectation];
}

- (void) waitForExpectationsWithTimeout: (NSTimeInterval)timeout
                                handler: (XCWaitCompletionHandler)handler
{
    NSMutableArray *pending = [NSMutableArray array];
    XCTWaiter *waiter = nil;
    XCTWaiterResult result;
    NSError *error = nil;

    @synchronized (self) {
        for (XCTestExpectation *expectation in _expectations) {
            if (![expectation _gsHasBeenWaitedOn]) {
                [pending addObject:expectation];
            }
        }
    }

    if ([pending count] == 0) {
        _XCTRecordFailure(self, @"API violation - call made to wait without any expectations having been set.");
        return;
    }

    for (XCTestExpectation *expectation in pending) {
        [expectation _gsSetHasBeenWaitedOn:YES];
    }

    waiter = [[[XCTWaiter alloc] initWithDelegate:self] autorelease];
    result = [waiter waitForExpectations:pending timeout:timeout];

    if (handler != nil) {
        if (result != XCTWaiterResultCompleted) {
            error = [NSError errorWithDomain:XCTestErrorDomain
                                        code:(result == XCTWaiterResultTimedOut
                                              ? XCTestErrorCodeTimeoutWhileWaiting
                                              : XCTestErrorCodeFailureWhileWaiting)
                                    userInfo:nil];
        }
        handler(error);
    }
}

- (void) waitForExpectations: (NSArray *)expectations timeout: (NSTimeInterval)seconds
{
    [self waitForExpectations:expectations timeout:seconds enforceOrder:NO];
}

- (void) waitForExpectations: (NSArray *)expectations
                     timeout: (NSTimeInterval)seconds
                enforceOrder: (BOOL)enforceOrderOfFulfillment
{
    XCTWaiter *waiter = [[[XCTWaiter alloc] initWithDelegate:self] autorelease];

    for (XCTestExpectation *expectation in expectations) {
        [expectation _gsSetHasBeenWaitedOn:YES];
    }

    [waiter waitForExpectations:expectations timeout:seconds enforceOrder:enforceOrderOfFulfillment];
}

- (XCTestExpectation *) expectationForNotification: (NSString *)notificationName
                                            object: (id)objectToObserve
                                           handler: (XCNotificationExpectationHandler)handler
{
    return [self expectationForNotification:notificationName
                                     object:objectToObserve
                         notificationCenter:nil
                                    handler:handler];
}

- (XCTestExpectation *) expectationForNotification: (NSString *)notificationName
                                            object: (id)objectToObserve
                                notificationCenter: (NSNotificationCenter *)notificationCenter
                                           handler: (XCNotificationExpectationHandler)handler
{
    XCTNSNotificationExpectation *expectation =
        [[[XCTNSNotificationExpectation alloc] initWithName:notificationName
                                                     object:objectToObserve
                                         notificationCenter:notificationCenter] autorelease];

    [expectation setHandler:handler];
    return [self _gsAddExpectation:expectation];
}

- (XCTestExpectation *) keyValueObservingExpectationForObject: (id)objectToObserve
                                                      keyPath: (NSString *)keyPath
                                                expectedValue: (id)expectedValue
{
    XCTKVOExpectation *expectation =
        [[[XCTKVOExpectation alloc] initWithKeyPath:keyPath
                                             object:objectToObserve
                                      expectedValue:expectedValue] autorelease];

    return [self _gsAddExpectation:expectation];
}

- (XCTestExpectation *) keyValueObservingExpectationForObject: (id)objectToObserve
                                                      keyPath: (NSString *)keyPath
                                                      handler: (XCKVOExpectationHandler)handler
{
    XCTKVOExpectation *expectation =
        [[[XCTKVOExpectation alloc] initWithKeyPath:keyPath object:objectToObserve] autorelease];

    [expectation setHandler:handler];
    return [self _gsAddExpectation:expectation];
}

- (XCTestExpectation *) expectationForPredicate: (NSPredicate *)predicate
                            evaluatedWithObject: (id)object
                                        handler: (XCPredicateExpectationHandler)handler
{
    XCTNSPredicateExpectation *expectation =
        [[[XCTNSPredicateExpectation alloc] initWithPredicate:predicate object:object] autorelease];

    [expectation setHandler:handler];
    return [self _gsAddExpectation:expectation];
}

#pragma mark XCTWaiterDelegate

- (void) waiter: (XCTWaiter *)waiter didTimeoutWithUnfulfilledExpectations: (NSArray *)unfulfilledExpectations
{
    _XCTRecordFailure(self, [NSString stringWithFormat:
        @"Asynchronous wait failed: Exceeded timeout of %g seconds, with unfulfilled expectations: %@.",
        [waiter _gsTimeout], GSQuotedDescriptions(unfulfilledExpectations)]);
}

- (void) waiter: (XCTWaiter *)waiter fulfillmentDidViolateOrderingConstraintsForExpectation: (XCTestExpectation *)expectation requiredExpectation: (XCTestExpectation *)requiredExpectation
{
    _XCTRecordFailure(self, [NSString stringWithFormat:
        @"Failed due to expectation fulfilled in incorrect order: requires '%@', actually fulfilled '%@'.",
        [requiredExpectation expectationDescription], [expectation expectationDescription]]);
}

- (void) waiter: (XCTWaiter *)waiter didFulfillInvertedExpectation: (XCTestExpectation *)expectation
{
    _XCTRecordFailure(self, [NSString stringWithFormat:
        @"Asynchronous wait failed: Fulfilled inverted expectation \"%@\".",
        [expectation expectationDescription]]);
}

@end

@implementation XCTestCase (GSAsynchronousTestingPrivate)

- (void) _gsRecordUnwaitedExpectations
{
    NSArray *expectations = nil;

    @synchronized (self) {
        expectations = [[_expectations copy] autorelease];
    }

    for (XCTestExpectation *expectation in expectations) {
        if (![expectation _gsHasBeenWaitedOn]) {
            _XCTRecordFailure(self, [NSString stringWithFormat:
                @"Failed due to unwaited expectation '%@'.", [expectation expectationDescription]]);
        }
    }
}

- (void) _gsInvalidateExpectations
{
    NSArray *expectations = nil;

    @synchronized (self) {
        expectations = [_expectations autorelease];
        _expectations = nil;
    }

    for (XCTestExpectation *expectation in expectations) {
        [expectation _gsInvalidate];
    }
}

@end
