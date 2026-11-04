// Checks the Swift overlay's assertions (XCTest/Swift) against the stub in
// Stub.swift: what each records, with which file and line, and what the
// skip and unwrap errors look like to the runner.

import Dispatch
import Foundation

var failures = 0

func report(_ ok: Bool, _ what: String, _ detail: @autoclosure () -> String = "") {
    if ok {
        print("PASS  \(what)")
    } else {
        failures += 1
        print("FAIL  \(what)\(detail().isEmpty ? "" : ": \(detail())")")
    }
}

// Runs body, which must sit on the caller's line, and checks what it
// recorded: nothing (description nil), or one failure at that line.
func check(_ what: String, records description: String?, expected: Bool = true,
           file: StaticString = #filePath, line: UInt = #line, _ body: () throws -> Void) {
    recordedFailures = []
    // Swift infers a closure as throwing from any `try` in it, even inside
    // an autoclosure argument; none of these throws out of an assertion.
    do {
        try body()
    } catch {
        report(false, what, "threw \(error)")
        return
    }
    if let description = description {
        let want = RecordedFailure(description: description, expected: expected,
                                   file: String(describing: file), line: line)
        report(recordedFailures == [want], what, "recorded \(recordedFailures)")
    } else {
        report(recordedFailures.isEmpty, what, "recorded \(recordedFailures)")
    }
}

enum TestError: Error { case boom }
func boom() throws -> Int { throw TestError.boom }
final class Box {}

// Booleans and nil
check("XCTAssert passes", records: nil) { XCTAssert(true) }
check("XCTAssertTrue fails", records: "XCTAssertTrue failed") { XCTAssertTrue(false) }
check("a message follows ' - '", records: "XCTAssertTrue failed - why") { XCTAssertTrue(false, "why") }
check("XCTAssertFalse fails", records: "XCTAssertFalse failed") { XCTAssertFalse(true) }
check("XCTAssertNil fails", records: "XCTAssertNil failed: \"1\"") { XCTAssertNil(1 as Int?) }
check("XCTAssertNil passes", records: nil) { XCTAssertNil(nil as Int?) }
check("XCTAssertNotNil fails", records: "XCTAssertNotNil failed") { XCTAssertNotNil(nil as Int?) }

// Equality
check("XCTAssertEqual passes", records: nil) { XCTAssertEqual("a", "a") }
check("XCTAssertEqual fails", records: "XCTAssertEqual failed: (\"1\") is not equal to (\"2\")") { XCTAssertEqual(1, 2) }
check("XCTAssertNotEqual fails", records: "XCTAssertNotEqual failed: (\"1\") is equal to (\"1\")") { XCTAssertNotEqual(1, 1) }
check("accuracy: within", records: nil) { XCTAssertEqual(1.0, 1.05, accuracy: 0.1) }
check("accuracy: outside", records: "XCTAssertEqual failed: (\"1.0\") is not equal to (\"1.2\") +/- (\"0.1\")") { XCTAssertEqual(1.0, 1.2, accuracy: 0.1) }
check("accuracy: infinity equals itself", records: nil) { XCTAssertEqual(Double.infinity, Double.infinity, accuracy: 0.1) }
check("accuracy: NaN equals nothing", records: "XCTAssertEqual failed: (\"nan\") is not equal to (\"nan\") +/- (\"0.1\")") { XCTAssertEqual(Double.nan, Double.nan, accuracy: 0.1) }
check("accuracy: a negative accuracy is its magnitude", records: nil) { XCTAssertEqual(1.0, 1.05, accuracy: -0.1) }
check("accuracy: integers", records: nil) { XCTAssertEqual(10, 12, accuracy: 3) }
check("not equal with accuracy fails", records: "XCTAssertNotEqual failed: (\"1.0\") is equal to (\"1.05\") +/- (\"0.1\")") { XCTAssertNotEqual(1.0, 1.05, accuracy: 0.1) }

// Comparison
check("XCTAssertGreaterThan fails", records: "XCTAssertGreaterThan failed: (\"1\") is not greater than (\"2\")") { XCTAssertGreaterThan(1, 2) }
check("XCTAssertGreaterThanOrEqual passes", records: nil) { XCTAssertGreaterThanOrEqual(2, 2) }
check("XCTAssertLessThan fails", records: "XCTAssertLessThan failed: (\"2\") is not less than (\"2\")") { XCTAssertLessThan(2, 2) }
check("XCTAssertLessThanOrEqual fails", records: "XCTAssertLessThanOrEqual failed: (\"3\") is not less than or equal to (\"2\")") { XCTAssertLessThanOrEqual(3, 2) }

// Identity
let box = Box()
check("XCTAssertIdentical passes", records: nil) { XCTAssertIdentical(box, box) }
check("XCTAssertNotIdentical passes", records: nil) { XCTAssertNotIdentical(box, Box()) }
recordedFailures = []
XCTAssertIdentical(box, Box())
report(recordedFailures.count == 1 && recordedFailures[0].description.hasPrefix("XCTAssertIdentical failed: (")
       && recordedFailures[0].description.contains(") is not identical to ("), "XCTAssertIdentical fails",
       "\(recordedFailures)")

// Throwing operands are unexpected failures
check("an operand that throws", records: "XCTAssertEqual threw error \"boom\"", expected: false) { XCTAssertEqual(try boom(), 1) }
check("a throwing operand, with a message", records: "XCTAssertTrue threw error \"boom\" - why", expected: false) { XCTAssertTrue(try boom() == 1, "why") }

// Errors
var handled: Error?
check("XCTAssertThrowsError passes", records: nil) { XCTAssertThrowsError(try boom()) { handled = $0 } }
report((handled as? TestError) == .boom, "XCTAssertThrowsError hands the error to its handler")
check("XCTAssertThrowsError fails", records: "XCTAssertThrowsError failed: did not throw an error") { XCTAssertThrowsError(1) }
check("XCTAssertNoThrow passes", records: nil) { XCTAssertNoThrow(1) }
check("XCTAssertNoThrow fails", records: "XCTAssertNoThrow failed: threw error \"boom\"") { XCTAssertNoThrow(try boom()) }

// Fail
check("XCTFail", records: "failed") { XCTFail() }
check("XCTFail with a message", records: "failed - why") { XCTFail("why") }

// Operands are evaluated once
var evaluations = 0
func counted() -> Int { evaluations += 1; return evaluations }
recordedFailures = []
XCTAssertEqual(counted(), 99)
report(evaluations == 1, "an operand is evaluated once", "\(evaluations) evaluations")

// The message is only built when the assertion fails
var messageBuilt = false
func message() -> String { messageBuilt = true; return "m" }
XCTAssertTrue(true, message())
report(!messageBuilt, "the message isn't built when the assertion passes")

// XCTUnwrap
recordedFailures = []
let unwrapped = try? XCTUnwrap(5 as Int?)
report(unwrapped == 5 && recordedFailures.isEmpty, "XCTUnwrap returns the value")

var unwrapLine: UInt = 0
do {
    unwrapLine = #line; _ = try XCTUnwrap(nil as Int?)
    report(false, "XCTUnwrap of nil throws")
} catch {
    let nsError = error as NSError
    report(nsError.domain == "org.gnustep.XCTest.ControlFlow" && nsError.code == 1,
           "XCTUnwrap of nil throws the already-recorded error", "\(nsError.domain) \(nsError.code)")
    report(recordedFailures == [RecordedFailure(description: "XCTUnwrap failed: expected non-nil value of type \"Int\"",
                                                expected: true, file: #filePath, line: unwrapLine)],
           "XCTUnwrap of nil records one failure at its line", "\(recordedFailures)")
}

recordedFailures = []
do {
    _ = try XCTUnwrap(try boom() as Int?)
} catch {
    report((error as? TestError) == .boom, "XCTUnwrap rethrows an operand's error as it is")
    report(recordedFailures.count == 1 && recordedFailures[0].description == "XCTUnwrap threw error \"boom\""
           && !recordedFailures[0].expected, "XCTUnwrap records an operand's error as unexpected",
           "\(recordedFailures)")
}

// XCTSkip, as the runner sees it
func skipInfo(_ body: () throws -> Void) -> (NSError?, UInt) {
    do {
        try body()
        return (nil, 0)
    } catch {
        return (error as NSError, 0)
    }
}

let skipLine: UInt = #line; let skip = XCTSkip("not here") as NSError
report(skip.domain == "org.gnustep.XCTest.ControlFlow" && skip.code == 2, "XCTSkip's domain and code",
       "\(skip.domain) \(skip.code)")
report(skip.userInfo["message"] as? String == "Test skipped - not here", "XCTSkip's message",
       "\(String(describing: skip.userInfo["message"]))")
report(skip.userInfo["file"] as? String == #filePath, "XCTSkip's file")
report((skip.userInfo["line"] as? NSNumber)?.uintValue == skipLine, "XCTSkip's line",
       "\(String(describing: skip.userInfo["line"]))")
report((XCTSkip("x") as Error as? XCTSkip)?.message == "x", "XCTSkip's message property")

let (skippedIf, _) = skipInfo { try XCTSkipIf(true, "on CI") }
report(skippedIf?.userInfo["message"] as? String == "Test skipped: required false value but got true - on CI",
       "XCTSkipIf(true) skips", "\(String(describing: skippedIf?.userInfo["message"]))")
let (notSkippedIf, _) = skipInfo { try XCTSkipIf(false) }
report(notSkippedIf == nil, "XCTSkipIf(false) doesn't skip")
let (skippedUnless, _) = skipInfo { try XCTSkipUnless(false) }
report(skippedUnless?.userInfo["message"] as? String == "Test skipped: required true value but got false",
       "XCTSkipUnless(false) skips", "\(String(describing: skippedUnless?.userInfo["message"]))")
let (skippedThrow, _) = skipInfo { try XCTSkipIf(try boom() == 1) }
report(skippedThrow?.userInfo["message"] as? String == "Test skipped: threw error \"boom\"",
       "XCTSkipIf skips when its condition throws", "\(String(describing: skippedThrow?.userInfo["message"]))")

// Apple's expectation names (Expectations.swift), each calling the imported
// Objective-C method it stands for, and not itself.
func checkCall(_ what: String, _ want: String, _ body: () -> Void) {
    importedCalls = []
    body()
    report(importedCalls == [want], what, "called \(importedCalls)")
}

let testCase = XCTestCase()
let first = XCTestExpectation(description: "first")
let second = XCTestExpectation(description: "second")
let center = NotificationCenter()
let handledNotification: XCNotificationExpectationHandler = { _ in true }

checkCall("expectation(description:)", "expectation(withDescription: x)") {
    // Non-optional, or `.expectationDescription` wouldn't compile.
    let expectation = testCase.expectation(description: "x")
    report(expectation.expectationDescription == "x", "expectation(description:) keeps its description")
}
checkCall("wait(for:timeout:)", "wait(forExpectations: [\"first\", \"second\"] timeout 2.0 enforceOrder false)") {
    testCase.wait(for: [first, second], timeout: 2)
}
checkCall("wait(for:timeout:enforceOrder:)", "wait(forExpectations: [\"first\"] timeout 2.0 enforceOrder true)") {
    testCase.wait(for: [first], timeout: 2, enforceOrder: true)
}
checkCall("waitForExpectations(timeout:)", "waitForExpectations(withTimeout: 3.0, handler: false)") {
    testCase.waitForExpectations(timeout: 3)
}
checkCall("waitForExpectations(timeout:handler:)", "waitForExpectations(withTimeout: 3.0, handler: true)") {
    testCase.waitForExpectations(timeout: 3) { _ in }
}
checkCall("expectation(forNotification:)",
          "expectation(forNotification: n, object: false, notificationCenter: false, handler: false)") {
    let expectation = testCase.expectation(forNotification: "n")
    _ = expectation.expectationDescription
}
checkCall("expectation(forNotification:object:notificationCenter:handler:)",
          "expectation(forNotification: n, object: true, notificationCenter: true, handler: true)") {
    let expectation = testCase.expectation(forNotification: "n", object: first, notificationCenter: center,
                                           handler: handledNotification)
    _ = expectation.expectationDescription
}
checkCall("expectation(for:)", "expectation(for: predicate, evaluatedWith: false, handler: false)") {
    let expectation = testCase.expectation(for: NSPredicate(value: true))
    _ = expectation.expectationDescription
}
checkCall("expectation(for:evaluatedWith:handler:)", "expectation(for: predicate, evaluatedWith: true, handler: true)") {
    let expectation = testCase.expectation(for: NSPredicate(value: true), evaluatedWith: first) { true }
    _ = expectation.expectationDescription
}
checkCall("keyValueObservingExpectation(for:keyPath:expectedValue:)",
          "keyValueObservingExpectation(keyPath: k, expectedValue: true)") {
    let expectation = testCase.keyValueObservingExpectation(for: first, keyPath: "k", expectedValue: 1)
    _ = expectation.expectationDescription
}
checkCall("keyValueObservingExpectation(for:keyPath:handler:)",
          "keyValueObservingExpectation(keyPath: k, handler: false)") {
    let expectation = testCase.keyValueObservingExpectation(for: first, keyPath: "k")
    _ = expectation.expectationDescription
}
checkCall("XCTWaiter().wait(for:timeout:)",
          "instance wait(forExpectations: [\"first\"] timeout 1.0 enforceOrder false)") {
    report(XCTWaiter().wait(for: [first], timeout: 1) == XCTWaiter.Result.timedOut, "XCTWaiter.Result from an instance")
}
checkCall("XCTWaiter.wait(for:timeout:enforceOrder:)",
          "class wait(forExpectations: [\"second\"] timeout 1.0 enforceOrder true)") {
    report(XCTWaiter.wait(for: [second], timeout: 1, enforceOrder: true) == .completed, "XCTWaiter.Result from the class")
}

// fulfillment(of:), which suspends until the background wait completes.
func checkAsyncCall(_ what: String, _ want: String, _ body: @escaping () async -> Void) {
    importedCalls = []
    let done = DispatchSemaphore(value: 0)
    Task {
        await body()
        done.signal()
    }
    done.wait()
    report(importedCalls == [want], what, "called \(importedCalls)")
}

checkAsyncCall("fulfillment(of:)", "background wait(forExpectations: [\"first\"] timeout inf enforceOrder false)") {
    await testCase.fulfillment(of: [first])
}
checkAsyncCall("fulfillment(of:timeout:enforceOrder:)",
               "background wait(forExpectations: [\"first\", \"second\"] timeout 2.0 enforceOrder true)") {
    await testCase.fulfillment(of: [first, second], timeout: 2, enforceOrder: true)
}
checkAsyncCall("XCTWaiter().fulfillment(of:)",
               "waiter background wait(forExpectations: [\"first\"] timeout 1.0 enforceOrder false)") {
    let result = await XCTWaiter().fulfillment(of: [first], timeout: 1)
    report(result == .incorrectOrder, "XCTWaiter().fulfillment(of:) returns the result")
}
checkAsyncCall("XCTWaiter.fulfillment(of:)",
               "waiter background wait(forExpectations: [\"second\"] timeout inf enforceOrder true)") {
    let result = await XCTWaiter.fulfillment(of: [second], enforceOrder: true)
    report(result == .incorrectOrder, "XCTWaiter.fulfillment(of:) returns the result")
}

// Helpers.swift: measure and activities.
var measured = 0
checkCall("measure(metrics:block:)", "measure(withMetrics: 1)") {
    testCase.measure(metrics: [XCTClockMetric()]) { measured += 1 }
}
checkCall("measure(metrics:options:block:)", "measure(withMetrics: 1, options)") {
    testCase.measure(metrics: [XCTClockMetric()], options: XCTMeasureOptions.default) { measured += 1 }
}
checkCall("measure(options:block:)", "measure(with: options)") {
    testCase.measure(options: .default) { measured += 1 }
}
report(measured == 3, "measure runs its blocks")

checkCall("runActivity(named:block:)", "runActivityNamed(step)") {
    let value: Int = XCTContext.runActivity(named: "step") { _ in 7 }
    report(value == 7, "runActivity returns its block's result")
}
checkCall("a runActivity block with no result", "runActivityNamed(step)") {
    XCTContext.runActivity(named: "step") { _ in }
}
checkCall("a throwing runActivity block", "runActivityNamed(step)") {
    do {
        let _: Int = try XCTContext.runActivity(named: "step") { _ in try boom() }
        report(false, "runActivity rethrows its block's error")
    } catch {
        report(error as? TestError == .boom, "runActivity rethrows its block's error", "\(error)")
    }
}
checkCall("a runActivity block using try that doesn't throw", "runActivityNamed(step)") {
    let value = try? XCTContext.runActivity(named: "step") { _ -> Int in try XCTUnwrap(Optional(3)) }
    report(value == 3, "runActivity returns a throwing block's result")
}

// Swift's async addTeardownBlock: the completion gets what the block threw,
// so that a skip keeps its control-flow domain.
func runTeardownBlock(_ block: @escaping @Sendable () async throws -> Void) -> NSError? {
    let test = XCTestCase()
    test.addTeardownBlock(block)
    report(test.asyncTeardownBlocks.count == 1, "async addTeardownBlock adds one block")

    let done = DispatchSemaphore(value: 0)
    final class Box: @unchecked Sendable { var error: NSError? }
    let box = Box()
    test.asyncTeardownBlocks[0]({ error in
        box.error = error
        done.signal()
    })
    done.wait()
    return box.error
}

report(runTeardownBlock({ try await Task.sleep(nanoseconds: 1_000) }) == nil, "an async teardown block finishes without an error")
report(runTeardownBlock({ throw TestError.boom })?.domain.contains("TestError") == true,
       "an async teardown block's error reaches the completion")
report(runTeardownBlock({ throw XCTSkip("x") })?.domain == _XCT_CONTROL_FLOW_ERROR_DOMAIN,
       "an async teardown block's skip keeps its domain")

// XCTExpectFailure's forms.
let matchAll: (XCTIssue) -> Bool = { _ in true }
checkCall("XCTExpectFailure(reason), the imported form", "XCTExpectFailure(why)") { XCTExpectFailure("why") }
checkCall("XCTExpectFailure() with no reason", "options(nil, enabled true strict true matcher none)") {
    XCTExpectFailure()
}
checkCall("XCTExpectFailure(strict:)", "options(why, enabled true strict false matcher none)") {
    XCTExpectFailure("why", strict: false)
}
checkCall("XCTExpectFailure(enabled:)", "options(why, enabled false strict true matcher none)") {
    XCTExpectFailure("why", enabled: false)
}
checkCall("XCTExpectFailure(issueMatcher:)", "options(why, enabled true strict true matcher matches)") {
    XCTExpectFailure("why", issueMatcher: matchAll)
}
checkCall("XCTExpectFailure(options:)", "options(why, enabled true strict true matcher none)") {
    XCTExpectFailure("why", options: XCTExpectedFailure.Options())
}
checkCall("XCTExpectFailure with a trailing failing block", "in block(why, enabled true strict true matcher none)") {
    var ran = false
    XCTExpectFailure("why") { ran = true }
    report(ran, "a failing block runs")
}
checkCall("XCTExpectFailure(strict:failingBlock:) returns its result",
          "in block(why, enabled true strict false matcher none)") {
    let value = XCTExpectFailure("why", strict: false) { 5 }
    report(value == 5, "a failing block's result is returned")
}
checkCall("XCTExpectFailure(failingBlock:issueMatcher:)", "in block(why, enabled true strict true matcher matches)") {
    XCTExpectFailure("why", failingBlock: { }, issueMatcher: matchAll)
}
checkCall("XCTExpectFailure(options:failingBlock:)", "in block(nil, enabled true strict true matcher none)") {
    XCTExpectFailure(options: XCTExpectedFailureOptions()) { }
}
checkCall("a throwing failing block", "in block(why, enabled true strict true matcher none)") {
    do {
        let _: Int = try XCTExpectFailure("why") { try boom() }
        report(false, "a failing block's error is rethrown")
    } catch {
        report(error as? TestError == .boom, "a failing block's error is rethrown", "\(error)")
    }
}

if failures > 0 {
    print("\(failures) overlay check(s) failed.")
    exit(1)
}
print("All overlay checks passed.")
