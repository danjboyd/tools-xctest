// Typechecked by run-swift-overlay-tests.sh against the real headers, not the
// stub: what Swift code gets without the overlay's help. It isn't run.

// An initializer that imports as optional doesn't fit: Optional isn't AnyObject.
func nonOptional<Argument, Object: AnyObject>(_ initializer: (Argument) -> Object) {}

func importedNames(_ attachment: XCTAttachment) {
    nonOptional(XCTAttachment.init(string:))
    nonOptional(XCTAttachment.init(data:))
    nonOptional(XCTAttachment.init(contentsOfFile:))
    nonOptional(XCTAttachment.init(plistObject:))
    nonOptional(XCTAttachment.init(archivableObject:))
    attachment.lifetime = .keepAlways
    attachment.lifetime = .deleteOnSuccess

    // Not the metrics' init: looking through NSObject's members makes stock
    // swiftc 6.0 crash on GNUstepBase's -notImplemented:.
    let _: XCTMeasureOptions = XCTMeasureOptions.default

    // What Helpers.swift and Expectations.swift call.
    _ = XCTExpectFailureWithOptions(_:_:)
    _ = XCTExpectFailureWithOptionsInBlock(_:_:_:)
    _ = \XCTExpectedFailureOptions.isEnabled
    _ = \XCTExpectedFailureOptions.isStrict
    _ = \XCTExpectedFailureOptions.issueMatcher
    _ = XCTContext.runActivityNamed(_:block:)
    _ = XCTestCase.measure(withMetrics:block:)
    _ = XCTestCase.measure(withMetrics:options:block:)
    _ = XCTestCase.measure(with:block:)
    _ = XCTestCase.expectation(withDescription:)
    _ = XCTestCase.wait(forExpectations:timeout:enforceOrder:)
    _ = XCTestCase.waitForExpectations(withTimeout:handler:)
    _ = XCTestCase._gsWaitInBackground(forExpectations:timeout:enforceOrder:completion:)
    _ = XCTWaiter._gsWaitInBackground(forExpectations:timeout:enforceOrder:completion:)
}
