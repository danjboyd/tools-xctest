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
