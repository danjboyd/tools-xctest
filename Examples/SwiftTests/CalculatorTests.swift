// A Swift test bundle for tools-xctest, built without SwiftPM; see the
// GNUmakefile next to it. The code under test is here too, to keep the
// example to one file.
import Dispatch
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

    func addLater(_ a: Int, _ b: Int) async -> Int {
        try? await Task.sleep(nanoseconds: 1_000_000)
        return a + b
    }

    func add(_ a: Int, _ b: Int, on queue: DispatchQueue, completion: @escaping (Int) -> Void) {
        queue.async { completion(a + b) }
    }
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

// Asynchronous code: async tests, set up and tear down, and expectations for
// code that calls back.
class AsyncCalculatorTests: XCTestCase {
    var calculator: Calculator!

    override func setUp() async throws {
        calculator = Calculator()
    }

    override func tearDown() async throws {
        calculator = nil
    }

    func testAddLater() async {
        let sum = await calculator.addLater(2, 3)
        XCTAssertEqual(sum, 5)
    }

    // A synchronous test waits with wait(for:timeout:).
    func testCallbackWithWait() {
        let called = expectation(description: "called back")
        calculator.add(2, 3, on: .main) { sum in
            XCTAssertEqual(sum, 5)
            called.fulfill()
        }
        wait(for: [called], timeout: 5)
    }

    // An async test awaits fulfillment(of:), which lets the main queue run
    // while a @MainActor test waits.
    @MainActor
    func testCallbackOnMainActor() async {
        let called = expectation(description: "called back")
        calculator.add(2, 3, on: .main) { sum in
            XCTAssertEqual(sum, 5)
            called.fulfill()
        }
        await fulfillment(of: [called], timeout: 5)
    }
}
