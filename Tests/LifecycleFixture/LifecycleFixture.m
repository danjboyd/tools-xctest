#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

// Each class exercises one lifecycle rule. run-lifecycle-tests.sh checks the
// "fixture:" lines and the per-class summaries in the runner output.

@interface OrderTests : XCTestCase
@end

@implementation OrderTests

- (void)testC { NSLog(@"fixture: OrderTests.testC"); }
- (void)testA { NSLog(@"fixture: OrderTests.testA"); }
- (void)testB { NSLog(@"fixture: OrderTests.testB"); }

@end

@interface PhaseOrderTests : XCTestCase
@end

@implementation PhaseOrderTests

+ (void)setUp { NSLog(@"fixture: phase +setUp"); }
+ (void)tearDown { NSLog(@"fixture: phase +tearDown"); }

- (BOOL)setUpWithError:(NSError **)error
{
    NSLog(@"fixture: phase setUpWithError");
    return YES;
}

- (void)setUp { NSLog(@"fixture: phase setUp"); }

- (void)testPhases
{
    NSLog(@"fixture: phase test");
    [self addTeardownBlock:^{ NSLog(@"fixture: phase teardownBlock1"); }];
    [self addTeardownBlock:^{ NSLog(@"fixture: phase teardownBlock2"); }];
}

- (void)tearDown { NSLog(@"fixture: phase tearDown"); }

- (BOOL)tearDownWithError:(NSError **)error
{
    NSLog(@"fixture: phase tearDownWithError");
    return YES;
}

@end

@interface ClassSetUpOnceTests : XCTestCase
@end

@implementation ClassSetUpOnceTests

+ (void)setUp { NSLog(@"fixture: ClassSetUpOnceTests +setUp"); }
+ (void)tearDown { NSLog(@"fixture: ClassSetUpOnceTests +tearDown"); }
- (void)testOne { NSLog(@"fixture: ClassSetUpOnceTests.testOne"); }
- (void)testTwo { NSLog(@"fixture: ClassSetUpOnceTests.testTwo"); }

@end

@interface TestThrowsTests : XCTestCase
@end

@implementation TestThrowsTests

- (void)testThrows
{
    [NSException raise:NSInternalInconsistencyException format:@"fixture exception"];
}

- (void)tearDown { NSLog(@"fixture: TestThrowsTests tearDown ran"); }

@end

@interface SetUpThrowsTests : XCTestCase
@end

@implementation SetUpThrowsTests

- (void)setUp
{
    [NSException raise:NSInternalInconsistencyException format:@"fixture setUp exception"];
}

- (void)testShouldNotRun { NSLog(@"fixture: SetUpThrowsTests test ran"); }
- (void)tearDown { NSLog(@"fixture: SetUpThrowsTests tearDown ran"); }

@end

@interface SetUpErrorTests : XCTestCase
@end

@implementation SetUpErrorTests

- (BOOL)setUpWithError:(NSError **)error
{
    if (error) {
        *error = [NSError errorWithDomain:@"Fixture" code:1
                                 userInfo:[NSDictionary dictionaryWithObject:@"fixture setUpWithError error"
                                                                      forKey:NSLocalizedDescriptionKey]];
    }
    return NO;
}

- (void)testShouldNotRun { NSLog(@"fixture: SetUpErrorTests test ran"); }
- (void)tearDown { NSLog(@"fixture: SetUpErrorTests tearDown ran"); }

@end

@interface TearDownFailsTests : XCTestCase
@end

@implementation TearDownFailsTests

- (void)testPasses { }
- (void)tearDown { XCTFail(@"fixture tearDown failure"); }

@end

@interface ClassSetUpThrowsTests : XCTestCase
@end

@implementation ClassSetUpThrowsTests

+ (void)setUp
{
    [NSException raise:NSInternalInconsistencyException format:@"fixture +setUp exception"];
}

+ (void)tearDown { NSLog(@"fixture: ClassSetUpThrowsTests +tearDown ran"); }
- (void)testShouldNotRun { NSLog(@"fixture: ClassSetUpThrowsTests test ran"); }

@end

@interface StopAfterFailureTests : XCTestCase
@end

@implementation StopAfterFailureTests

- (void)setUp { self.continueAfterFailure = NO; }

- (void)testStops
{
    XCTAssertTrue(NO, @"fixture stop");
    NSLog(@"fixture: StopAfterFailureTests continued");
}

- (void)tearDown { NSLog(@"fixture: StopAfterFailureTests tearDown ran"); }

@end

@interface ContinueAfterFailureTests : XCTestCase
@end

@implementation ContinueAfterFailureTests

- (void)testContinues
{
    XCTFail(@"fixture continue");
    NSLog(@"fixture: ContinueAfterFailureTests continued");
}

@end

@interface InheritedBaseTests : XCTestCase
@end

@implementation InheritedBaseTests

- (void)testInherited
{
    NSLog(@"fixture: %@.testInherited", NSStringFromClass([self class]));
}

@end

@interface InheritedDerivedTests : InheritedBaseTests
@end

@implementation InheritedDerivedTests

- (void)testOwn { NSLog(@"fixture: InheritedDerivedTests.testOwn"); }

@end

@interface SkipTests : XCTestCase
@end

@implementation SkipTests

- (void)testSkip
{
    XCTSkip(@"fixture skip reason %d", 42);
    NSLog(@"fixture: SkipTests continued");
}

- (void)tearDown { NSLog(@"fixture: SkipTests tearDown ran"); }

@end

@interface SkipConditionTests : XCTestCase
@end

@implementation SkipConditionTests

- (void)testSkipIfFalse
{
    XCTSkipIf(1 + 1 == 3);
    NSLog(@"fixture: SkipConditionTests.testSkipIfFalse continued");
}

- (void)testSkipIfTrue
{
    XCTSkipIf(1 + 1 == 2, @"fixture skipIf");
    NSLog(@"fixture: SkipConditionTests.testSkipIfTrue continued");
}

- (void)testSkipUnlessFalse
{
    XCTSkipUnless(1 + 1 == 3);
    NSLog(@"fixture: SkipConditionTests.testSkipUnlessFalse continued");
}

- (void)testSkipUnlessTrue
{
    XCTSkipUnless(1 + 1 == 2);
    NSLog(@"fixture: SkipConditionTests.testSkipUnlessTrue continued");
}

@end

@interface SkipInSetUpTests : XCTestCase
@end

@implementation SkipInSetUpTests

- (void)setUp { XCTSkip(@"fixture skip in setUp"); }
- (void)testShouldNotRun { NSLog(@"fixture: SkipInSetUpTests test ran"); }
- (void)tearDown { NSLog(@"fixture: SkipInSetUpTests tearDown ran"); }

@end

@interface SkipInsideAssertionTests : XCTestCase
@end

@implementation SkipInsideAssertionTests

- (void)skipFromHelper
{
    XCTSkip(@"fixture skip from helper");
}

- (void)testSkipInsideAssertion
{
    XCTAssertNoThrow([self skipFromHelper]);
    NSLog(@"fixture: SkipInsideAssertionTests continued");
}

@end

@interface FailThenSkipTests : XCTestCase
@end

@implementation FailThenSkipTests

- (void)testFailThenSkip
{
    XCTFail(@"fixture failure before skip");
    XCTSkip();
}

@end

@interface SkipConditionThrowsTests : XCTestCase
@end

@implementation SkipConditionThrowsTests

- (BOOL)throwingCondition
{
    [NSException raise:NSInternalInconsistencyException format:@"fixture condition exception"];
    return YES;
}

- (void)testConditionThrows
{
    XCTSkipIf([self throwingCondition]);
    NSLog(@"fixture: SkipConditionThrowsTests continued");
}

@end

@interface StopInsideAssertionTests : XCTestCase
@end

@implementation StopInsideAssertionTests

- (void)failFromHelper
{
    XCTFail(@"fixture failure from helper");
}

- (void)testStopsInsideAssertion
{
    self.continueAfterFailure = NO;
    XCTAssertNoThrow([self failFromHelper]);
    NSLog(@"fixture: StopInsideAssertionTests continued");
}

@end

@interface ClassTearDownThrowsTests : XCTestCase
@end

@implementation ClassTearDownThrowsTests

+ (void)tearDown
{
    [NSException raise:NSInternalInconsistencyException format:@"fixture +tearDown <exception> & \"quotes\""];
}

- (void)testPasses { }

@end

@interface ClassSkipTests : XCTestCase
@end

@implementation ClassSkipTests

+ (void)setUp
{
    XCTSkip(@"fixture class skip");
}

+ (void)tearDown { NSLog(@"fixture: ClassSkipTests +tearDown ran"); }
- (void)testOne { NSLog(@"fixture: ClassSkipTests test ran"); }
- (void)testTwo { NSLog(@"fixture: ClassSkipTests test ran"); }

@end

@interface ClassSkipIfTests : XCTestCase
@end

@implementation ClassSkipIfTests

+ (void)setUp
{
    XCTSkipIf(NO, @"never");
    XCTAssertTrue(YES);
}

- (void)testRuns { NSLog(@"fixture: ClassSkipIfTests test ran"); }

@end
