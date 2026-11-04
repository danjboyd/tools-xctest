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

// The Swift overlay for XCTest. It's built as a Swift module named XCTest
// over the Clang module of the same name (-import-underlying-module), so
// `import XCTest` gives a test both the Objective-C classes and these
// functions.
//
// This file, Expectations.swift and Helpers.swift are the overlay's only contact
// with the Objective-C side; the other files use just what this one declares.

@_exported import XCTest
import Foundation

/// Records a failure in the running test (or, during `class func setUp()`,
/// its class), the way the `XCTAssert*` macros do: a `nil` test means the
/// current one. `expected` is false when an operand threw.
@usableFromInline
internal func _gsRecordFailure(_ description: String, expected: Bool, file: StaticString, line: UInt) {
    _XCTPreformattedFailureHandler(nil, expected, String(describing: file), numericCast(line), description, nil)
}

/// The domain of the errors the runner treats as control flow rather than as
/// failures (`_XCT_CONTROL_FLOW_ERROR_DOMAIN` in XCTestAssertionsImpl.h).
internal let _gsControlFlowErrorDomain: String = _XCT_CONTROL_FLOW_ERROR_DOMAIN

/// `_XCTControlFlowCode` in XCTestAssertionsImpl.h.
internal enum _GSControlFlowCode: Int {
    case alreadyRecorded = 1
    case skip = 2
}
