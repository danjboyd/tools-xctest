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

/*!
 * An expected outcome of an asynchronous test. Call -fulfill when the
 * outcome happens; XCTWaiter or XCTestCase waits for it. -fulfill may be
 * called from any thread.
 */
@interface XCTestExpectation : NSObject {
    NSString *_expectationDescription;
    NSUInteger _expectedFulfillmentCount;
    NSUInteger _fulfillmentCount;
    NSUInteger _fulfillmentToken;
    BOOL _inverted;
    BOOL _assertForOverFulfill;
    BOOL _hasBeenWaitedOn;
}

- (id) initWithDescription: (NSString *)expectationDescription;

@property (copy) NSString *expectationDescription;

/*! If YES, the expectation fails a wait when it IS fulfilled. */
@property (getter=isInverted) BOOL inverted;

/*! How many calls to -fulfill are needed. Defaults to 1. */
@property NSUInteger expectedFulfillmentCount;

/*! If YES, fulfilling more than expectedFulfillmentCount times is a test
 * failure. Defaults to NO, but YES for expectations created through
 * XCTestCase. */
@property BOOL assertForOverFulfill;

- (void) fulfill;

@end

typedef BOOL (^XCNotificationExpectationHandler)(NSNotification *notification);

/*!
 * Fulfilled when a notification is posted. If a handler is set, it decides
 * whether a given notification fulfills the expectation.
 */
@interface XCTNSNotificationExpectation : XCTestExpectation {
    NSString *_notificationName;
    id _observedObject;
    NSNotificationCenter *_notificationCenter;
    XCNotificationExpectationHandler _handler;
    BOOL _observing;
}

- (id) initWithName: (NSString *)notificationName;
- (id) initWithName: (NSString *)notificationName object: (id)object;
- (id) initWithName: (NSString *)notificationName
             object: (id)object
 notificationCenter: (NSNotificationCenter *)notificationCenter;

@property (readonly, copy) NSString *notificationName;
@property (readonly, retain) id observedObject;
@property (readonly, retain) NSNotificationCenter *notificationCenter;
@property (copy) XCNotificationExpectationHandler handler;

@end

typedef BOOL (^XCKVOExpectationHandler)(id observedObject, NSDictionary *change);

/*!
 * Fulfilled when a key path of an object changes to an expected value, or
 * when the handler returns YES. With neither, any change fulfills it.
 */
@interface XCTKVOExpectation : XCTestExpectation {
    NSString *_keyPath;
    id _observedObject;
    id _expectedValue;
    XCKVOExpectationHandler _handler;
    BOOL _observing;
}

- (id) initWithKeyPath: (NSString *)keyPath object: (id)object;
- (id) initWithKeyPath: (NSString *)keyPath
                object: (id)object
         expectedValue: (id)expectedValue;

@property (readonly, copy) NSString *keyPath;
@property (readonly, retain) id observedObject;
@property (readonly, retain) id expectedValue;
@property (copy) XCKVOExpectationHandler handler;

@end

typedef BOOL (^XCPredicateExpectationHandler)(void);

/*!
 * Fulfilled when a predicate evaluates to YES for an object. The predicate
 * is re-evaluated while a waiter is waiting.
 */
@interface XCTNSPredicateExpectation : XCTestExpectation {
    NSPredicate *_predicate;
    id _object;
    XCPredicateExpectationHandler _handler;
}

- (id) initWithPredicate: (NSPredicate *)predicate object: (id)object;

@property (readonly, copy) NSPredicate *predicate;
@property (readonly, retain) id object;
@property (copy) XCPredicateExpectationHandler handler;

@end
