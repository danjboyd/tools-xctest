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
#import <XCTest/XCTestExpectation.h>
#import <XCTest/XCTWaiter.h>
#import <XCTest/XCTestErrors.h>

typedef void (^XCWaitCompletionHandler)(NSError *error);

@interface XCTestCase (AsynchronousTesting) <XCTWaiterDelegate>

/*!
 * Creates an expectation that -waitForExpectationsWithTimeout:handler:
 * waits for. A test that creates one and never waits on it fails.
 */
- (XCTestExpectation *) expectationWithDescription: (NSString *)description;

/*!
 * Waits for every expectation created by this test that hasn't been waited
 * on yet. A timeout is a test failure; the handler, if any, is then called
 * with an XCTestErrorDomain error (or nil on success).
 */
- (void) waitForExpectationsWithTimeout: (NSTimeInterval)timeout
                                handler: (XCWaitCompletionHandler)handler;

/*! Waits for specific expectations; a failed wait is a test failure. */
- (void) waitForExpectations: (NSArray *)expectations timeout: (NSTimeInterval)seconds;
- (void) waitForExpectations: (NSArray *)expectations
                     timeout: (NSTimeInterval)seconds
                enforceOrder: (BOOL)enforceOrderOfFulfillment;

- (XCTestExpectation *) expectationForNotification: (NSString *)notificationName
                                            object: (id)objectToObserve
                                           handler: (XCNotificationExpectationHandler)handler;
- (XCTestExpectation *) expectationForNotification: (NSString *)notificationName
                                            object: (id)objectToObserve
                                notificationCenter: (NSNotificationCenter *)notificationCenter
                                           handler: (XCNotificationExpectationHandler)handler;

- (XCTestExpectation *) keyValueObservingExpectationForObject: (id)objectToObserve
                                                      keyPath: (NSString *)keyPath
                                                expectedValue: (id)expectedValue;
- (XCTestExpectation *) keyValueObservingExpectationForObject: (id)objectToObserve
                                                      keyPath: (NSString *)keyPath
                                                      handler: (XCKVOExpectationHandler)handler;

- (XCTestExpectation *) expectationForPredicate: (NSPredicate *)predicate
                            evaluatedWithObject: (id)object
                                        handler: (XCPredicateExpectationHandler)handler;

@end
