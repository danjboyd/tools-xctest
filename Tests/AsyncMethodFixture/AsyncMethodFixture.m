#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#include <objc/runtime.h>

// A Swift `func testFoo() async` reaches the Objective-C runtime as
// -(void)testFooWithCompletionHandler:(void (^)(void)), and `async throws`
// with a block taking an NSError *. These are written that way.

@interface AsyncTests : XCTestCase
@end

@implementation AsyncTests

- (void)testCompletesNowWithCompletionHandler:(void (^)(void))completion
{
    NSLog(@"fixture: AsyncTests.testCompletesNow");
    completion();
}

- (void)finishLater:(id)completion
{
    NSLog(@"fixture: AsyncTests.testCompletesLater finished");
    ((void (^)(void))completion)();
}

// Completes from the test thread's run loop, after the method returned.
- (void)testCompletesLaterWithCompletionHandler:(void (^)(void))completion
{
    NSLog(@"fixture: AsyncTests.testCompletesLater started");
    [self performSelector:@selector(finishLater:) withObject:[[completion copy] autorelease] afterDelay:0.1];
}

- (void)finishOnThread:(id)completion
{
    @autoreleasepool {
        [NSThread sleepForTimeInterval:0.05];
        NSLog(@"fixture: AsyncTests.testCompletesOnAnotherThread finished on main thread: %d",
              (int)[NSThread isMainThread]);
        ((void (^)(void))completion)();
    }
}

- (void)testCompletesOnAnotherThreadWithCompletionHandler:(void (^)(void))completion
{
    [NSThread detachNewThreadSelector:@selector(finishOnThread:) toTarget:self
                           withObject:[[completion copy] autorelease]];
}

- (void)testAssertionFailsWithCompletionHandler:(void (^)(void))completion
{
    XCTFail(@"async assertion");
    completion();
}

@end

// async throws methods, with the extended block signatures that say their
// completion takes an NSError *: registered at runtime, because clang
// doesn't write those into method encodings.

static NSError *AsyncFixtureError(NSString *message)
{
    return [NSError errorWithDomain:@"AsyncFixture" code:1
                           userInfo:[NSDictionary dictionaryWithObject:message
                                                                forKey:NSLocalizedDescriptionKey]];
}

static void ThrowsIMP(id self, SEL _cmd, void (^completion)(NSError *))
{
    NSLog(@"fixture: AsyncTests.testThrows");
    completion(AsyncFixtureError(@"async error"));
}

static void PassesIMP(id self, SEL _cmd, void (^completion)(NSError *))
{
    NSLog(@"fixture: AsyncTests.testPassesWithErrorBlock");
    completion(nil);
}

static void SkipsIMP(id self, SEL _cmd, void (^completion)(NSError *))
{
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
        @"Test skipped - async skip", @"message",
        @"/src/AsyncTests.swift", @"file",
        [NSNumber numberWithUnsignedInteger:7], @"line",
        nil];

    completion([NSError errorWithDomain:@"" _XCT_CONTROL_FLOW_ERROR_DOMAIN
                                   code:_XCTControlFlowCodeSkip userInfo:info]);
}

static void NoArgumentIMP(id self, SEL _cmd, void (^completion)(void))
{
    NSLog(@"fixture: AsyncTests.testNoArgumentSignature");
    completion();
}

@interface AsyncFixtureRegistrar : NSObject
@end

@implementation AsyncFixtureRegistrar

+ (void)load
{
    Class cls = [AsyncTests class];
    const char *errorBlock = "v24@0:8@?<v@?@>16";

    class_addMethod(cls, sel_registerName("testThrowsWithCompletionHandler:"), (IMP)ThrowsIMP, errorBlock);
    class_addMethod(cls, sel_registerName("testPassesWithErrorBlockWithCompletionHandler:"), (IMP)PassesIMP, errorBlock);
    class_addMethod(cls, sel_registerName("testSkipsWithCompletionHandler:"), (IMP)SkipsIMP, errorBlock);
    class_addMethod(cls, sel_registerName("testNoArgumentSignatureWithCompletionHandler:"), (IMP)NoArgumentIMP,
                    "v24@0:8@?<v@?>16");
}

@end

// Never completes: run only with timeouts enabled.
@interface AsyncHangTests : XCTestCase
@end

@implementation AsyncHangTests

- (void)testNeverCompletesWithCompletionHandler:(void (^)(void))completion
{
    NSLog(@"fixture: AsyncHangTests.testNeverCompletes");
}

@end

// continueAfterFailure = NO: run on its own. Tests run in this order.
@interface AsyncStopTests : XCTestCase
@end

@implementation AsyncStopTests

// In the call itself, nothing but the runner is on the stack: this stops.
- (void)testAStopsDuringTheCallWithCompletionHandler:(void (^)(void))completion
{
    [self setContinueAfterFailure:NO];
    XCTFail(@"during the call");
    NSLog(@"fixture: AsyncStopTests.testAStopsDuringTheCall continued");
    completion();
}

- (void)failOnRunLoop:(id)completion
{
    [self setContinueAfterFailure:NO];
    XCTFail(@"on the run loop");
    NSLog(@"fixture: AsyncStopTests.testBContinuesOnTheRunLoop continued");
    ((void (^)(void))completion)();
}

// Later, the run loop is on the stack, as it is for a @MainActor Swift test:
// this must not unwind through it.
- (void)testBContinuesOnTheRunLoopWithCompletionHandler:(void (^)(void))completion
{
    [self performSelector:@selector(failOnRunLoop:) withObject:[[completion copy] autorelease] afterDelay:0.01];
}

- (void)testCRunsNextWithCompletionHandler:(void (^)(void))completion
{
    NSLog(@"fixture: AsyncStopTests.testCRunsNext");
    completion();
}

// A plain test still stops once the async test's wait is over.
- (void)testDPlainTestStops
{
    [self setContinueAfterFailure:NO];
    XCTFail(@"in a plain test");
    NSLog(@"fixture: AsyncStopTests.testDPlainTestStops continued");
}

@end
