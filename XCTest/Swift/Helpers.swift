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

// Apple's Swift names for measuring and activities, over the Objective-C
// methods as they import. Every method here is @nonobjc: see Expectations.swift.

import Foundation

extension XCTestCase {
    @nonobjc
    public func measure(metrics: [XCTMetric], block: @escaping () -> Void) {
        measure(withMetrics: metrics, block: block)
    }

    @nonobjc
    public func measure(metrics: [XCTMetric], options: XCTMeasureOptions, block: @escaping () -> Void) {
        measure(withMetrics: metrics, options: options, block: block)
    }

    @nonobjc
    public func measure(options: XCTMeasureOptions, block: @escaping () -> Void) {
        measure(with: options, block: block)
    }
}

extension XCTContext {
    /// Runs `block` as a named step of the current test, and returns its result.
    @nonobjc
    public class func runActivity<Result>(named name: String, block: (XCTActivity) -> Result) -> Result {
        var result: Result?
        withoutActuallyEscaping(block) { block in
            runActivityNamed(name) { activity in
                result = block(activity!)
            }
        }
        return result!
    }

    /// As above, for a block that can throw, such as one using `XCTUnwrap`.
    @nonobjc
    public class func runActivity<Result>(named name: String, block: (XCTActivity) throws -> Result) throws -> Result {
        var result: Swift.Result<Result, Error>?
        withoutActuallyEscaping(block) { block in
            runActivityNamed(name) { activity in
                result = Swift.Result { try block(activity!) }
            }
        }
        return try result!.get()
    }
}
