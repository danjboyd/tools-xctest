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

@class XCTestExpectation;
@class XCTWaiter;

typedef enum {
    /*! All expectations were fulfilled (and no inverted one was). */
    XCTWaiterResultCompleted = 1,
    /*! The timeout passed with expectations still unfulfilled. */
    XCTWaiterResultTimedOut = 2,
    /*! With enforceOrder, expectations were fulfilled out of order. */
    XCTWaiterResultIncorrectOrder = 3,
    /*! An inverted expectation was fulfilled. */
    XCTWaiterResultInvertedFulfillment = 4,
    /*! Reserved; not currently produced. */
    XCTWaiterResultInterrupted = 5,
} XCTWaiterResult;

@protocol XCTWaiterDelegate <NSObject>
@optional
- (void) waiter: (XCTWaiter *)waiter didTimeoutWithUnfulfilledExpectations: (NSArray *)unfulfilledExpectations;
- (void) waiter: (XCTWaiter *)waiter fulfillmentDidViolateOrderingConstraintsForExpectation: (XCTestExpectation *)expectation requiredExpectation: (XCTestExpectation *)requiredExpectation;
- (void) waiter: (XCTWaiter *)waiter didFulfillInvertedExpectation: (XCTestExpectation *)expectation;
@end

/*!
 * Waits for expectations by running the current run loop in the default
 * mode, so timers, notifications and other run loop sources keep firing.
 */
@interface XCTWaiter : NSObject {
    id<XCTWaiterDelegate> _delegate;
    NSArray *_fulfilledExpectations;
    NSTimeInterval _timeout;
}

- (id) initWithDelegate: (id<XCTWaiterDelegate>)delegate;

/*! Not retained. */
@property (assign) id<XCTWaiterDelegate> delegate;

/*! The waited-on expectations that were fulfilled, in fulfillment order. */
@property (readonly, copy) NSArray *fulfilledExpectations;

- (XCTWaiterResult) waitForExpectations: (NSArray *)expectations
                                timeout: (NSTimeInterval)seconds;
- (XCTWaiterResult) waitForExpectations: (NSArray *)expectations
                                timeout: (NSTimeInterval)seconds
                           enforceOrder: (BOOL)enforceOrderOfFulfillment;

+ (XCTWaiterResult) waitForExpectations: (NSArray *)expectations
                                timeout: (NSTimeInterval)seconds;
+ (XCTWaiterResult) waitForExpectations: (NSArray *)expectations
                                timeout: (NSTimeInterval)seconds
                           enforceOrder: (BOOL)enforceOrderOfFulfillment;

@end
