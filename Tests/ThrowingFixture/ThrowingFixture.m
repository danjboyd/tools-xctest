#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

// A Swift `func testFoo() throws` reaches the Objective-C runtime as
// -(BOOL)testFooAndReturnError:(NSError **)error; these are written that way.
@interface ThrowingTests : XCTestCase
@end

@implementation ThrowingTests

- (void)testPlain
{
    NSLog(@"fixture: ThrowingTests.testPlain");
}

- (BOOL)testSucceedsAndReturnError:(NSError **)error
{
    NSLog(@"fixture: ThrowingTests.testSucceeds");
    return YES;
}

- (BOOL)testThrowsAndReturnError:(NSError **)error
{
    NSLog(@"fixture: ThrowingTests.testThrows");
    *error = [NSError errorWithDomain:@"ThrowingFixture" code:1
                             userInfo:[NSDictionary dictionaryWithObject:@"fixture error"
                                                                  forKey:NSLocalizedDescriptionKey]];
    return NO;
}

@end
