// Stands in for the XCTest Clang module, so that the overlay's Swift code
// can be built and checked with a stock Swift toolchain, which can't import
// Objective-C. These have the shapes the overlay expects the real
// declarations in XCTestAssertionsImpl.h, XCTestExpectation.h, XCTWaiter.h and
// XCTestCase+AsynchronousTesting.h to import as.

import Foundation

struct RecordedFailure: Equatable {
    var description: String
    var expected: Bool
    var file: String
    var line: UInt
}

var recordedFailures: [RecordedFailure] = []

// void _XCTPreformattedFailureHandler(id test, BOOL expected, NSString *filePath,
//     NSUInteger lineNumber, NSString *condition, NSString *message);
func _XCTPreformattedFailureHandler(_ test: Any!, _ expected: Bool, _ filePath: String!,
                                    _ lineNumber: UInt, _ condition: String!, _ message: String!) {
    precondition(test == nil, "the overlay must leave the test to the runner")
    precondition(message == nil, "the overlay passes the whole description as the condition")
    recordedFailures.append(RecordedFailure(description: condition, expected: expected,
                                            file: filePath, line: lineNumber))
}

// #define _XCT_CONTROL_FLOW_ERROR_DOMAIN "org.gnustep.XCTest.ControlFlow"
let _XCT_CONTROL_FLOW_ERROR_DOMAIN = "org.gnustep.XCTest.ControlFlow"

typealias XCWaitCompletionHandler = (NSError?) -> Void
typealias XCNotificationExpectationHandler = (Notification?) -> Bool
typealias XCPredicateExpectationHandler = () -> Bool
typealias XCKVOExpectationHandler = (Any?, [AnyHashable: Any]?) -> Bool

// What the stubbed Objective-C methods were called with.
var importedCalls: [String] = []

class XCTestExpectation: NSObject {
    var expectationDescription: String
    init(description: String) { expectationDescription = description }
}

enum XCTWaiterResult: Int {
    case completed = 1, timedOut, incorrectOrder, invertedFulfillment, interrupted
}

func describeWait(_ expectations: [Any]?, _ timeout: Double, _ enforceOrder: Bool) -> String {
    let names = (expectations ?? []).map { ($0 as! XCTestExpectation).expectationDescription }
    return "\(names) timeout \(timeout) enforceOrder \(enforceOrder)"
}

// Public, as the overlay's public functions take them.
public class XCTIssue: NSObject {}

public class XCTExpectedFailureOptions: NSObject {
    var isEnabled = true
    var isStrict = true
    var issueMatcher: ((XCTIssue?) -> Bool)!
}

// void XCTExpectFailure(NSString *failureReason): the imported one-argument form.
func XCTExpectFailure(_ failureReason: String!) {
    importedCalls.append("XCTExpectFailure(\(failureReason ?? "nil"))")
}

func describeOptions(_ options: XCTExpectedFailureOptions!) -> String {
    let matched = options.issueMatcher.map { $0(XCTIssue()) ? "matches" : "no match" } ?? "none"
    return "enabled \(options.isEnabled) strict \(options.isStrict) matcher \(matched)"
}

func XCTExpectFailureWithOptions(_ failureReason: String!, _ options: XCTExpectedFailureOptions!) {
    importedCalls.append("options(\(failureReason ?? "nil"), \(describeOptions(options)))")
}

func XCTExpectFailureWithOptionsInBlock(_ failureReason: String!, _ options: XCTExpectedFailureOptions!,
                                        _ failingBlock: (() -> Void)!) {
    importedCalls.append("in block(\(failureReason ?? "nil"), \(describeOptions(options)))")
    failingBlock()
}

protocol XCTMetric {}
final class XCTClockMetric: XCTMetric {}

class XCTMeasureOptions: NSObject {
    static var `default`: XCTMeasureOptions { XCTMeasureOptions() }
}

protocol XCTActivity {}
final class StubActivity: XCTActivity {}

class XCTContext: NSObject {
    class func runActivityNamed(_ name: String!, block: ((XCTActivity?) -> Void)!) {
        importedCalls.append("runActivityNamed(\(name!))")
        block(StubActivity())
    }
}

class XCTestCase: NSObject {
    func measure(withMetrics metrics: [Any]!, block: (() -> Void)!) {
        importedCalls.append("measure(withMetrics: \(metrics.count))")
        block()
    }

    func measure(withMetrics metrics: [Any]!, options: XCTMeasureOptions!, block: (() -> Void)!) {
        importedCalls.append("measure(withMetrics: \(metrics.count), options)")
        block()
    }

    func measure(with options: XCTMeasureOptions!, block: (() -> Void)!) {
        importedCalls.append("measure(with: options)")
        block()
    }

    func expectation(withDescription description: String!) -> XCTestExpectation! {
        importedCalls.append("expectation(withDescription: \(description!))")
        return XCTestExpectation(description: description)
    }

    func wait(forExpectations expectations: [Any]!, timeout: Double, enforceOrder: Bool) {
        importedCalls.append("wait(forExpectations: \(describeWait(expectations, timeout, enforceOrder)))")
    }

    func waitForExpectations(withTimeout timeout: Double, handler: XCWaitCompletionHandler!) {
        importedCalls.append("waitForExpectations(withTimeout: \(timeout), handler: \(handler != nil))")
    }

    var asyncTeardownBlocks: [(((NSError?) -> Void)?) -> Void] = []

    func _gsAddAsyncTeardownBlock(_ block: ((((NSError?) -> Void)?) -> Void)!) {
        asyncTeardownBlocks.append(block)
    }

    func _gsWaitInBackground(forExpectations expectations: [Any]!, timeout: Double, enforceOrder: Bool,
                             completion: (() -> Void)!) {
        importedCalls.append("background wait(forExpectations: \(describeWait(expectations, timeout, enforceOrder)))")
        completion()
    }

    func expectation(forNotification name: String!, object: Any!, notificationCenter: NotificationCenter!,
                     handler: XCNotificationExpectationHandler!) -> XCTestExpectation! {
        importedCalls.append("expectation(forNotification: \(name!), object: \(object != nil), "
                             + "notificationCenter: \(notificationCenter != nil), handler: \(handler != nil))")
        return XCTestExpectation(description: name)
    }

    func expectation(for predicate: NSPredicate!, evaluatedWith object: Any!,
                     handler: XCPredicateExpectationHandler!) -> XCTestExpectation! {
        importedCalls.append("expectation(for: predicate, evaluatedWith: \(object != nil), handler: \(handler != nil))")
        return XCTestExpectation(description: "predicate")
    }

    func keyValueObservingExpectation(for object: Any!, keyPath: String!, expectedValue: Any!) -> XCTestExpectation! {
        importedCalls.append("keyValueObservingExpectation(keyPath: \(keyPath!), expectedValue: \(expectedValue != nil))")
        return XCTestExpectation(description: keyPath)
    }

    func keyValueObservingExpectation(for object: Any!, keyPath: String!,
                                      handler: XCKVOExpectationHandler!) -> XCTestExpectation! {
        importedCalls.append("keyValueObservingExpectation(keyPath: \(keyPath!), handler: \(handler != nil))")
        return XCTestExpectation(description: keyPath)
    }
}

class XCTWaiter: NSObject {
    func _gsWaitInBackground(forExpectations expectations: [Any]!, timeout: Double, enforceOrder: Bool,
                             completion: ((XCTWaiterResult) -> Void)!) {
        importedCalls.append("waiter background wait(forExpectations: \(describeWait(expectations, timeout, enforceOrder)))")
        completion(.incorrectOrder)
    }

    func wait(forExpectations expectations: [Any]!, timeout: Double, enforceOrder: Bool) -> XCTWaiterResult {
        importedCalls.append("instance wait(forExpectations: \(describeWait(expectations, timeout, enforceOrder)))")
        return .timedOut
    }

    class func wait(forExpectations expectations: [Any]!, timeout: Double, enforceOrder: Bool) -> XCTWaiterResult {
        importedCalls.append("class wait(forExpectations: \(describeWait(expectations, timeout, enforceOrder)))")
        return .completed
    }
}
