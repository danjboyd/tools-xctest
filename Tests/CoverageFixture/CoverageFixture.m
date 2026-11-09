#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#include <stdlib.h>

// Called by the tests; the coverage regressions check it was counted.
int CoverageFixtureCovered(int value)
{
    return value + 1;
}

// Never called; the coverage regressions check it wasn't.
int CoverageFixtureUncovered(int value)
{
    return value - 1;
}

@interface CoverageAlphaTests : XCTestCase
@end

@implementation CoverageAlphaTests

- (void)testCovered
{
    XCTAssertEqual(CoverageFixtureCovered(1), 2);
}

// Fails when COVERAGE_FIXTURE_FAIL is set, to check the exit status.
- (void)testMaybeFails
{
    XCTAssertTrue(getenv("COVERAGE_FIXTURE_FAIL") == NULL);
}

@end

@interface CoverageBetaTests : XCTestCase
@end

@implementation CoverageBetaTests

- (void)testCoveredAgain
{
    XCTAssertEqual(CoverageFixtureCovered(2), 3);
}

@end
