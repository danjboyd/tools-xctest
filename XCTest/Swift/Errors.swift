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

import Foundation

// Errors the runner treats as control flow. A throwing test, setUpWithError
// or tearDownWithError returns them to the runner as NSErrors in
// _gsControlFlowErrorDomain; see _XCTControlFlowCode in
// XCTestAssertionsImpl.h.

/// Thrown by XCTUnwrap after it has recorded its failure, so that the
/// runner ends the test without recording a second one.
internal struct _GSUnwrapFailure: Error, CustomNSError {
    static var errorDomain: String { _gsControlFlowErrorDomain }
    var errorCode: Int { _GSControlFlowCode.alreadyRecorded.rawValue }
    var errorUserInfo: [String: Any] { [:] }
}

/// Throw it to skip the test: from the test itself, `setUpWithError()`, or
/// through `XCTSkipIf` and `XCTSkipUnless`.
public struct XCTSkip: Error, CustomNSError {
    /// The message given when the skip was thrown.
    public let message: String?

    let summary: String
    let file: String
    let line: UInt

    private init(explanation: String?, message: String?, file: StaticString, line: UInt) {
        var summary = "Test skipped"
        if let explanation = explanation {
            summary += ": \(explanation)"
        }
        if let message = message, !message.isEmpty {
            summary += " - \(message)"
        }
        self.message = message
        self.summary = summary
        self.file = String(describing: file)
        self.line = line
    }

    public init(_ message: @autoclosure () -> String? = nil,
                file: StaticString = #filePath, line: UInt = #line) {
        self.init(explanation: nil, message: message(), file: file, line: line)
    }

    fileprivate init(skippingOn value: Bool, message: String?, file: StaticString, line: UInt) {
        // As Apple's: XCTSkipIf requires false, XCTSkipUnless requires true.
        let explanation = value
            ? "required false value but got true"
            : "required true value but got false"
        self.init(explanation: explanation, message: message, file: file, line: line)
    }

    fileprivate init(error: Swift.Error, message: String?, file: StaticString, line: UInt) {
        self.init(explanation: "threw error \"\(error)\"", message: message, file: file, line: line)
    }

    public static var errorDomain: String { _gsControlFlowErrorDomain }
    public var errorCode: Int { _GSControlFlowCode.skip.rawValue }
    public var errorUserInfo: [String: Any] {
        // The keys the runner reads for an Objective-C skip, too.
        ["message": summary, "file": file, "line": NSNumber(value: line)]
    }
}

public func XCTSkipIf(_ expression: @autoclosure () throws -> Bool,
                      _ message: @autoclosure () -> String? = nil,
                      file: StaticString = #filePath, line: UInt = #line) throws {
    try _gsSkip(on: true, expression, message, file: file, line: line)
}

public func XCTSkipUnless(_ expression: @autoclosure () throws -> Bool,
                          _ message: @autoclosure () -> String? = nil,
                          file: StaticString = #filePath, line: UInt = #line) throws {
    try _gsSkip(on: false, expression, message, file: file, line: line)
}

private func _gsSkip(on skipValue: Bool, _ expression: () throws -> Bool, _ message: () -> String?,
                     file: StaticString, line: UInt) throws {
    let value: Bool
    do {
        value = try expression()
    } catch {
        throw XCTSkip(error: error, message: message(), file: file, line: line)
    }
    if value == skipValue {
        throw XCTSkip(skippingOn: value, message: message(), file: file, line: line)
    }
}
