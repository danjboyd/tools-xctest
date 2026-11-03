// Stands in for the XCTest Clang module, so that the overlay's Swift code
// can be built and checked with a stock Swift toolchain, which can't import
// Objective-C. These have the shapes the overlay expects the real
// declarations in XCTestAssertionsImpl.h to import as.

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
