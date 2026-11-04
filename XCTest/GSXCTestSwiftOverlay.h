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
#import <XCTest/XCTWaiter.h>

/*
 * Methods only the Swift overlay calls, through the module map. Nothing else
 * in tools-xctest includes this header.
 */

@interface XCTestCase (GSXCTestSwiftOverlay)

/*!
 * For fulfillment(of:): waits as -waitForExpectations:timeout:enforceOrder:
 * does, but on a thread of its own, and calls the completion there. The
 * caller's thread and run loop stay free, so a @MainActor test's main-queue
 * callbacks can run. A failed wait is a test failure, but doesn't stop the
 * test.
 */
- (void) _gsWaitInBackgroundForExpectations: (NSArray *)expectations
                                    timeout: (NSTimeInterval)seconds
                               enforceOrder: (BOOL)enforceOrderOfFulfillment
                                 completion: (void (^)(void))completion;

/*!
 * For addTeardownBlock with an async closure: a teardown block that finishes
 * when it calls its completion, from any thread, with any error. The test
 * thread's run loop runs until then.
 */
- (void) _gsAddAsyncTeardownBlock: (void (^)(void (^completion)(NSError *error)))block;

@end

@interface XCTWaiter (GSXCTestSwiftOverlay)

/*! For XCTWaiter's fulfillment(of:): as XCTestCase's, giving the result. */
- (void) _gsWaitInBackgroundForExpectations: (NSArray *)expectations
                                    timeout: (NSTimeInterval)seconds
                               enforceOrder: (BOOL)enforceOrderOfFulfillment
                                 completion: (void (^)(XCTWaiterResult result))completion;

@end
