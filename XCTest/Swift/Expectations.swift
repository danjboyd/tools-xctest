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

// Apple's Swift names for waiting on expectations, over the Objective-C
// methods as they import. Each returns its expectation as non-optional:
// the imported methods have implicitly unwrapped results, which a `let`
// would infer as optional.
//
// Where Apple's name is also the imported one, the optional arguments in the
// calls below select the imported method instead of the method making the call.

import Foundation

extension XCTestCase {
    public func expectation(description: String) -> XCTestExpectation {
        return expectation(withDescription: description)
    }

    @available(*, noasync, message: "Use await fulfillment(of:timeout:enforceOrder:) instead.")
    public func wait(for expectations: [XCTestExpectation], timeout seconds: Double,
                     enforceOrder enforceOrderOfFulfillment: Bool = false) {
        wait(forExpectations: expectations, timeout: seconds, enforceOrder: enforceOrderOfFulfillment)
    }

    @available(*, noasync, message: "Use await fulfillment(of:timeout:enforceOrder:) instead.")
    public func waitForExpectations(timeout: Double, handler: XCWaitCompletionHandler? = nil) {
        waitForExpectations(withTimeout: timeout, handler: handler)
    }

    /// Waits without blocking a thread, so a `@MainActor` test's main-queue
    /// callbacks can run. The wait itself runs on a thread of its own.
    public func fulfillment(of expectations: [XCTestExpectation], timeout seconds: Double = .infinity,
                            enforceOrder enforceOrderOfFulfillment: Bool = false) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            _gsWaitInBackground(forExpectations: expectations, timeout: seconds,
                                enforceOrder: enforceOrderOfFulfillment) {
                continuation.resume()
            }
        }
    }

    /// GNUstep has no `NSNotification.Name`, so `notificationName` is a string.
    public func expectation(forNotification notificationName: String, object objectToObserve: Any? = nil,
                            notificationCenter: NotificationCenter? = nil,
                            handler: XCNotificationExpectationHandler? = nil) -> XCTestExpectation {
        let imported: XCTestExpectation? = expectation(forNotification: notificationName as String?,
                                                       object: objectToObserve,
                                                       notificationCenter: notificationCenter, handler: handler)
        return imported!
    }

    public func expectation(for predicate: NSPredicate, evaluatedWith object: Any? = nil,
                            handler: XCPredicateExpectationHandler? = nil) -> XCTestExpectation {
        let imported: XCTestExpectation? = expectation(for: predicate as NSPredicate?, evaluatedWith: object,
                                                       handler: handler)
        return imported!
    }

    public func keyValueObservingExpectation(for objectToObserve: Any, keyPath: String,
                                             expectedValue: Any?) -> XCTestExpectation {
        let imported: XCTestExpectation? = keyValueObservingExpectation(for: objectToObserve as Any?,
                                                                        keyPath: keyPath as String?,
                                                                        expectedValue: expectedValue)
        return imported!
    }

    public func keyValueObservingExpectation(for objectToObserve: Any, keyPath: String,
                                             handler: XCKVOExpectationHandler? = nil) -> XCTestExpectation {
        let imported: XCTestExpectation? = keyValueObservingExpectation(for: objectToObserve as Any?,
                                                                        keyPath: keyPath as String?,
                                                                        handler: handler)
        return imported!
    }
}

extension XCTWaiter {
    public typealias Result = XCTWaiterResult

    @available(*, noasync, message: "Use await fulfillment(of:timeout:enforceOrder:) instead.")
    @discardableResult
    public func wait(for expectations: [XCTestExpectation], timeout seconds: Double,
                     enforceOrder enforceOrderOfFulfillment: Bool = false) -> Result {
        return wait(forExpectations: expectations, timeout: seconds, enforceOrder: enforceOrderOfFulfillment)
    }

    @available(*, noasync, message: "Use await fulfillment(of:timeout:enforceOrder:) instead.")
    @discardableResult
    public class func wait(for expectations: [XCTestExpectation], timeout seconds: Double,
                           enforceOrder enforceOrderOfFulfillment: Bool = false) -> Result {
        return wait(forExpectations: expectations, timeout: seconds, enforceOrder: enforceOrderOfFulfillment)
    }

    /// Waits without blocking a thread, on a thread of its own.
    public func fulfillment(of expectations: [XCTestExpectation], timeout seconds: Double = .infinity,
                            enforceOrder enforceOrderOfFulfillment: Bool = false) async -> Result {
        return await withCheckedContinuation { (continuation: CheckedContinuation<Result, Never>) in
            _gsWaitInBackground(forExpectations: expectations, timeout: seconds,
                                enforceOrder: enforceOrderOfFulfillment) { result in
                continuation.resume(returning: result)
            }
        }
    }

    public class func fulfillment(of expectations: [XCTestExpectation], timeout seconds: Double = .infinity,
                                  enforceOrder enforceOrderOfFulfillment: Bool = false) async -> Result {
        return await XCTWaiter().fulfillment(of: expectations, timeout: seconds, enforceOrder: enforceOrderOfFulfillment)
    }
}
