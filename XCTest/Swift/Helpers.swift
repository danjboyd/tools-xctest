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

/// Apple's name for the options, `XCTExpectedFailure.Options`.
public enum XCTExpectedFailure {
    public typealias Options = XCTExpectedFailureOptions
}

private func _gsExpectedFailureOptions(enabled: Bool, strict: Bool,
                                       issueMatcher: ((XCTIssue) -> Bool)?) -> XCTExpectedFailureOptions {
    let options: XCTExpectedFailureOptions = XCTExpectedFailureOptions()
    options.isEnabled = enabled
    options.isStrict = strict
    if let issueMatcher = issueMatcher {
        options.issueMatcher = { issue in issueMatcher(issue!) }
    }
    return options
}

/// Marks failures from here to the end of the test as expected. `file` and
/// `line` are Apple's, and aren't used: the runner reports the failures' own.
public func XCTExpectFailure(_ failureReason: String? = nil, enabled: Bool = true, strict: Bool = true,
                             file: StaticString = #filePath, line: UInt = #line,
                             issueMatcher: ((XCTIssue) -> Bool)? = nil) {
    XCTExpectFailureWithOptions(failureReason, _gsExpectedFailureOptions(enabled: enabled, strict: strict,
                                                                         issueMatcher: issueMatcher))
}

public func XCTExpectFailure(_ failureReason: String? = nil, options: XCTExpectedFailure.Options) {
    XCTExpectFailureWithOptions(failureReason, options)
}

/// Only for failures inside `failingBlock`.
public func XCTExpectFailure<Result>(_ failureReason: String? = nil, options: XCTExpectedFailure.Options,
                                     failingBlock: () -> Result) -> Result {
    var result: Result?
    withoutActuallyEscaping(failingBlock) { failingBlock in
        XCTExpectFailureWithOptionsInBlock(failureReason, options) {
            result = failingBlock()
        }
    }
    return result!
}

public func XCTExpectFailure<Result>(_ failureReason: String? = nil, options: XCTExpectedFailure.Options,
                                     failingBlock: () throws -> Result) throws -> Result {
    var result: Swift.Result<Result, Error>?
    withoutActuallyEscaping(failingBlock) { failingBlock in
        XCTExpectFailureWithOptionsInBlock(failureReason, options) {
            result = Swift.Result { try failingBlock() }
        }
    }
    return try result!.get()
}

public func XCTExpectFailure<Result>(_ failureReason: String? = nil, enabled: Bool = true, strict: Bool = true,
                                     file: StaticString = #filePath, line: UInt = #line,
                                     failingBlock: () -> Result,
                                     issueMatcher: ((XCTIssue) -> Bool)? = nil) -> Result {
    return XCTExpectFailure(failureReason,
                            options: _gsExpectedFailureOptions(enabled: enabled, strict: strict,
                                                               issueMatcher: issueMatcher),
                            failingBlock: failingBlock)
}

public func XCTExpectFailure<Result>(_ failureReason: String? = nil, enabled: Bool = true, strict: Bool = true,
                                     file: StaticString = #filePath, line: UInt = #line,
                                     failingBlock: () throws -> Result,
                                     issueMatcher: ((XCTIssue) -> Bool)? = nil) throws -> Result {
    return try XCTExpectFailure(failureReason,
                                options: _gsExpectedFailureOptions(enabled: enabled, strict: strict,
                                                                   issueMatcher: issueMatcher),
                                failingBlock: failingBlock)
}
