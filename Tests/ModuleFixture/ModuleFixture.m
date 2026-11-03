#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#include <objc/runtime.h>

// The Swift runtime registers a test class as <Module>.<Class>, for example
// "ModuleFixture.SwiftStyleTests". Objective-C can't declare such a name, so
// this registers one at load time, as a subclass of XCTestCase.

static void GSFixtureTestOne(id self, SEL _cmd)
{
    NSLog(@"fixture: SwiftStyleTests.testOne");
}

static void GSFixtureTestTwo(id self, SEL _cmd)
{
    NSLog(@"fixture: SwiftStyleTests.testTwo");
}

@interface ModuleFixtureRegistrar : NSObject
@end

@implementation ModuleFixtureRegistrar

+ (void)load
{
    Class cls = objc_allocateClassPair([XCTestCase class], "ModuleFixture.SwiftStyleTests", 0);

    class_addMethod(cls, @selector(testOne), (IMP)GSFixtureTestOne, "v@:");
    class_addMethod(cls, @selector(testTwo), (IMP)GSFixtureTestTwo, "v@:");
    objc_registerClassPair(cls);
}

@end

// An ordinary Objective-C test class next to it.
@interface PlainTests : XCTestCase
@end

@implementation PlainTests

- (void)testPlain
{
    NSLog(@"fixture: PlainTests.testPlain");
}

@end
