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

// XCTAssert* for Swift, with the signatures and messages of Apple's XCTest
// and swift-corelibs-xctest. Each operand is evaluated once; an operand
// that throws is an unexpected failure.

private enum _GSAssertionResult {
    case success
    case expectedFailure(String?)
    case unexpectedFailure(Swift.Error)
}

private func _gsEvaluate(_ name: String?, _ message: () -> String,
                         _ file: StaticString, _ line: UInt,
                         _ body: () throws -> _GSAssertionResult) {
    let result: _GSAssertionResult
    do {
        result = try body()
    } catch {
        result = .unexpectedFailure(error)
    }

    let explanation: String
    let expected: Bool
    switch result {
    case .success:
        return
    case .expectedFailure(let details?):
        explanation = "failed: \(details)"
        expected = true
    case .expectedFailure(nil):
        explanation = "failed"
        expected = true
    case .unexpectedFailure(let error):
        explanation = "threw error \"\(error)\""
        expected = false
    }

    var description = name.map { "\($0) \(explanation)" } ?? explanation
    let text = message()
    if !text.isEmpty {
        description += " - \(text)"
    }
    _gsRecordFailure(description, expected: expected, file: file, line: line)
}

// MARK: Booleans

/// Records a failure unless `expression` is true. The same as `XCTAssertTrue`.
public func XCTAssert(_ expression: @autoclosure () throws -> Bool,
                      _ message: @autoclosure () -> String = "",
                      file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(try expression(), message(), file: file, line: line)
}

/// Records a failure unless `expression` is true.
public func XCTAssertTrue(_ expression: @autoclosure () throws -> Bool,
                          _ message: @autoclosure () -> String = "",
                          file: StaticString = #filePath, line: UInt = #line) {
    _gsEvaluate("XCTAssertTrue", message, file, line) {
        try expression() ? .success : .expectedFailure(nil)
    }
}

/// Records a failure unless `expression` is false.
public func XCTAssertFalse(_ expression: @autoclosure () throws -> Bool,
                           _ message: @autoclosure () -> String = "",
                           file: StaticString = #filePath, line: UInt = #line) {
    _gsEvaluate("XCTAssertFalse", message, file, line) {
        try expression() ? .expectedFailure(nil) : .success
    }
}

// MARK: Nil

/// Records a failure, showing the value, unless `expression` is `nil`.
public func XCTAssertNil(_ expression: @autoclosure () throws -> Any?,
                         _ message: @autoclosure () -> String = "",
                         file: StaticString = #filePath, line: UInt = #line) {
    _gsEvaluate("XCTAssertNil", message, file, line) {
        if let value = try expression() {
            return .expectedFailure("\"\(value)\"")
        }
        return .success
    }
}

/// Records a failure if `expression` is `nil`.
public func XCTAssertNotNil(_ expression: @autoclosure () throws -> Any?,
                            _ message: @autoclosure () -> String = "",
                            file: StaticString = #filePath, line: UInt = #line) {
    _gsEvaluate("XCTAssertNotNil", message, file, line) {
        try expression() == nil ? .expectedFailure(nil) : .success
    }
}

// MARK: Equality

/// Records a failure, showing both values, unless they are equal (`==`).
public func XCTAssertEqual<T: Equatable>(_ expression1: @autoclosure () throws -> T,
                                         _ expression2: @autoclosure () throws -> T,
                                         _ message: @autoclosure () -> String = "",
                                         file: StaticString = #filePath, line: UInt = #line) {
    _gsEvaluate("XCTAssertEqual", message, file, line) {
        let (value1, value2) = (try expression1(), try expression2())
        return value1 == value2
            ? .success
            : .expectedFailure("(\"\(value1)\") is not equal to (\"\(value2)\")")
    }
}

/// Records a failure, showing both values, if they are equal (`==`).
public func XCTAssertNotEqual<T: Equatable>(_ expression1: @autoclosure () throws -> T,
                                            _ expression2: @autoclosure () throws -> T,
                                            _ message: @autoclosure () -> String = "",
                                            file: StaticString = #filePath, line: UInt = #line) {
    _gsEvaluate("XCTAssertNotEqual", message, file, line) {
        let (value1, value2) = (try expression1(), try expression2())
        return value1 != value2
            ? .success
            : .expectedFailure("(\"\(value1)\") is equal to (\"\(value2)\")")
    }
}

// Equal within the accuracy. Compared with == first, so that infinities
// equal themselves; NaN equals nothing, as <= with NaN is false.
private func _gsEqual<T: Numeric>(_ value1: T, _ value2: T, accuracy: T) -> Bool {
    if value1 == value2 {
        return true
    }
    let difference = (value1.magnitude > value2.magnitude) ? value1 - value2 : value2 - value1
    return difference.magnitude <= accuracy.magnitude
}

private func _gsAssertEqual<T: Numeric>(_ expression1: () throws -> T, _ expression2: () throws -> T,
                                        accuracy: T, _ message: () -> String,
                                        file: StaticString, line: UInt) {
    _gsEvaluate("XCTAssertEqual", message, file, line) {
        let (value1, value2) = (try expression1(), try expression2())
        return _gsEqual(value1, value2, accuracy: accuracy)
            ? .success
            : .expectedFailure("(\"\(value1)\") is not equal to (\"\(value2)\") +/- (\"\(accuracy)\")")
    }
}

private func _gsAssertNotEqual<T: Numeric>(_ expression1: () throws -> T, _ expression2: () throws -> T,
                                           accuracy: T, _ message: () -> String,
                                           file: StaticString, line: UInt) {
    _gsEvaluate("XCTAssertNotEqual", message, file, line) {
        let (value1, value2) = (try expression1(), try expression2())
        return _gsEqual(value1, value2, accuracy: accuracy)
            ? .expectedFailure("(\"\(value1)\") is equal to (\"\(value2)\") +/- (\"\(accuracy)\")")
            : .success
    }
}

/// Records a failure unless the values differ by at most `accuracy`. Infinities equal themselves; NaN equals nothing.
public func XCTAssertEqual<T: FloatingPoint>(_ expression1: @autoclosure () throws -> T,
                                             _ expression2: @autoclosure () throws -> T,
                                             accuracy: T,
                                             _ message: @autoclosure () -> String = "",
                                             file: StaticString = #filePath, line: UInt = #line) {
    _gsAssertEqual(expression1, expression2, accuracy: accuracy, message, file: file, line: line)
}

/// Records a failure unless the values differ by at most `accuracy`.
public func XCTAssertEqual<T: Numeric>(_ expression1: @autoclosure () throws -> T,
                                       _ expression2: @autoclosure () throws -> T,
                                       accuracy: T,
                                       _ message: @autoclosure () -> String = "",
                                       file: StaticString = #filePath, line: UInt = #line) {
    _gsAssertEqual(expression1, expression2, accuracy: accuracy, message, file: file, line: line)
}

/// Records a failure if the values differ by at most `accuracy`.
public func XCTAssertNotEqual<T: FloatingPoint>(_ expression1: @autoclosure () throws -> T,
                                                _ expression2: @autoclosure () throws -> T,
                                                accuracy: T,
                                                _ message: @autoclosure () -> String = "",
                                                file: StaticString = #filePath, line: UInt = #line) {
    _gsAssertNotEqual(expression1, expression2, accuracy: accuracy, message, file: file, line: line)
}

/// Records a failure if the values differ by at most `accuracy`.
public func XCTAssertNotEqual<T: Numeric>(_ expression1: @autoclosure () throws -> T,
                                          _ expression2: @autoclosure () throws -> T,
                                          accuracy: T,
                                          _ message: @autoclosure () -> String = "",
                                          file: StaticString = #filePath, line: UInt = #line) {
    _gsAssertNotEqual(expression1, expression2, accuracy: accuracy, message, file: file, line: line)
}

// MARK: Comparison

private func _gsCompare<T: Comparable>(_ name: String, _ expression1: () throws -> T,
                                       _ expression2: () throws -> T, _ message: () -> String,
                                       _ file: StaticString, _ line: UInt,
                                       holds: (T, T) -> Bool, relation: String) {
    _gsEvaluate(name, message, file, line) {
        let (value1, value2) = (try expression1(), try expression2())
        return holds(value1, value2)
            ? .success
            : .expectedFailure("(\"\(value1)\") is not \(relation) (\"\(value2)\")")
    }
}

/// Records a failure unless the first value is greater than the second.
public func XCTAssertGreaterThan<T: Comparable>(_ expression1: @autoclosure () throws -> T,
                                                _ expression2: @autoclosure () throws -> T,
                                                _ message: @autoclosure () -> String = "",
                                                file: StaticString = #filePath, line: UInt = #line) {
    _gsCompare("XCTAssertGreaterThan", expression1, expression2, message, file, line,
               holds: { $0 > $1 }, relation: "greater than")
}

/// Records a failure unless the first value is greater than or equal to the second.
public func XCTAssertGreaterThanOrEqual<T: Comparable>(_ expression1: @autoclosure () throws -> T,
                                                       _ expression2: @autoclosure () throws -> T,
                                                       _ message: @autoclosure () -> String = "",
                                                       file: StaticString = #filePath, line: UInt = #line) {
    _gsCompare("XCTAssertGreaterThanOrEqual", expression1, expression2, message, file, line,
               holds: { $0 >= $1 }, relation: "greater than or equal to")
}

/// Records a failure unless the first value is less than the second.
public func XCTAssertLessThan<T: Comparable>(_ expression1: @autoclosure () throws -> T,
                                             _ expression2: @autoclosure () throws -> T,
                                             _ message: @autoclosure () -> String = "",
                                             file: StaticString = #filePath, line: UInt = #line) {
    _gsCompare("XCTAssertLessThan", expression1, expression2, message, file, line,
               holds: { $0 < $1 }, relation: "less than")
}

/// Records a failure unless the first value is less than or equal to the second.
public func XCTAssertLessThanOrEqual<T: Comparable>(_ expression1: @autoclosure () throws -> T,
                                                    _ expression2: @autoclosure () throws -> T,
                                                    _ message: @autoclosure () -> String = "",
                                                    file: StaticString = #filePath, line: UInt = #line) {
    _gsCompare("XCTAssertLessThanOrEqual", expression1, expression2, message, file, line,
               holds: { $0 <= $1 }, relation: "less than or equal to")
}

// MARK: Identity

/// Records a failure unless both are the same object (`===`), or both `nil`.
public func XCTAssertIdentical(_ expression1: @autoclosure () throws -> AnyObject?,
                               _ expression2: @autoclosure () throws -> AnyObject?,
                               _ message: @autoclosure () -> String = "",
                               file: StaticString = #filePath, line: UInt = #line) {
    _gsEvaluate("XCTAssertIdentical", message, file, line) {
        let (value1, value2) = (try expression1(), try expression2())
        return value1 === value2
            ? .success
            : .expectedFailure("(\"\(String(describing: value1))\") is not identical to (\"\(String(describing: value2))\")")
    }
}

/// Records a failure if both are the same object (`===`), or both `nil`.
public func XCTAssertNotIdentical(_ expression1: @autoclosure () throws -> AnyObject?,
                                  _ expression2: @autoclosure () throws -> AnyObject?,
                                  _ message: @autoclosure () -> String = "",
                                  file: StaticString = #filePath, line: UInt = #line) {
    _gsEvaluate("XCTAssertNotIdentical", message, file, line) {
        let (value1, value2) = (try expression1(), try expression2())
        return value1 !== value2
            ? .success
            : .expectedFailure("(\"\(String(describing: value1))\") is identical to (\"\(String(describing: value2))\")")
    }
}

// MARK: Errors

/// Records a failure unless `expression` throws; `errorHandler` gets the error.
public func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T,
                                    _ message: @autoclosure () -> String = "",
                                    file: StaticString = #filePath, line: UInt = #line,
                                    _ errorHandler: (_ error: Swift.Error) -> Void = { _ in }) {
    _gsEvaluate("XCTAssertThrowsError", message, file, line) {
        do {
            _ = try expression()
            return .expectedFailure("did not throw an error")
        } catch {
            errorHandler(error)
            return .success
        }
    }
}

/// Records a failure, showing the error, if `expression` throws.
public func XCTAssertNoThrow<T>(_ expression: @autoclosure () throws -> T,
                                _ message: @autoclosure () -> String = "",
                                file: StaticString = #filePath, line: UInt = #line) {
    _gsEvaluate("XCTAssertNoThrow", message, file, line) {
        do {
            _ = try expression()
            return .success
        } catch {
            return .expectedFailure("threw error \"\(error)\"")
        }
    }
}

// MARK: Fail and unwrap

/// Records a failure at the caller, unconditionally.
public func XCTFail(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    _gsEvaluate(nil, { message }, file, line) {
        .expectedFailure(nil)
    }
}

/// Returns the unwrapped value, or records a failure and throws. The
/// runner doesn't record the thrown error again; an error the expression
/// throws is rethrown as it is.
public func XCTUnwrap<T>(_ expression: @autoclosure () throws -> T?,
                         _ message: @autoclosure () -> String = "",
                         file: StaticString = #filePath, line: UInt = #line) throws -> T {
    var value: T?
    var thrown: Swift.Error?

    _gsEvaluate("XCTUnwrap", message, file, line) {
        do {
            value = try expression()
        } catch {
            thrown = error
            return .unexpectedFailure(error)
        }
        return value != nil ? .success : .expectedFailure("expected non-nil value of type \"\(T.self)\"")
    }

    if let value = value {
        return value
    }
    if let thrown = thrown {
        throw thrown
    }
    throw _GSUnwrapFailure()
}
