// A Swift test bundle for tools-xctest, built without SwiftPM; see the
// GNUmakefile next to it. The code under test is here too, to keep the
// example to one file.
import Foundation
import XCTest

struct Calculator {
    enum Error: Swift.Error { case divisionByZero }

    func add(_ a: Int, _ b: Int) -> Int { a + b }

    func divide(_ a: Double, by b: Double) throws -> Double {
        guard b != 0 else { throw Error.divisionByZero }
        return a / b
    }

    func parse(_ text: String) -> Int? { Int(text) }
}

// Found through the Objective-C runtime: no @objc needed. Selected as
// CalculatorTests/CalculatorTests/<test>, the bundle being CalculatorTests.
class CalculatorTests: XCTestCase {
    var calculator: Calculator!

    override func setUp() {
        super.setUp()
        calculator = Calculator()
    }

    func testAdd() {
        XCTAssertEqual(calculator.add(2, 3), 5)
        XCTAssertGreaterThan(calculator.add(1, 1), 1)
    }

    func testDivide() throws {
        XCTAssertEqual(try calculator.divide(1, by: 3), 0.333, accuracy: 0.001)
        XCTAssertThrowsError(try calculator.divide(1, by: 0)) { error in
            XCTAssertEqual(error as? Calculator.Error, .divisionByZero)
        }
    }

    func testParse() throws {
        XCTAssertNil(calculator.parse("x"))
        let value = try XCTUnwrap(calculator.parse("42"))
        XCTAssertEqual(value, 42)
    }

    func testOnlyOnSixtyFourBit() throws {
        try XCTSkipUnless(MemoryLayout<Int>.size == 8, "needs a 64-bit Int")
        XCTAssertEqual(Int.max, 9_223_372_036_854_775_807)
    }
}
