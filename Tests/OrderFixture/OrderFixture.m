#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

// Three classes of three tests, each logging as it runs.

@interface AlphaTests : XCTestCase
@end

@implementation AlphaTests

+ (void)setUp { NSLog(@"order: Alpha +setUp"); }
+ (void)tearDown { NSLog(@"order: Alpha +tearDown"); }
- (void)testOne { NSLog(@"order: Alpha.testOne"); }
- (void)testTwo { NSLog(@"order: Alpha.testTwo"); }
- (void)testThree { NSLog(@"order: Alpha.testThree"); }

@end

@interface BetaTests : XCTestCase
@end

@implementation BetaTests

+ (void)setUp { NSLog(@"order: Beta +setUp"); }
+ (void)tearDown { NSLog(@"order: Beta +tearDown"); }
- (void)testOne { NSLog(@"order: Beta.testOne"); }
- (void)testTwo { NSLog(@"order: Beta.testTwo"); }
- (void)testThree { NSLog(@"order: Beta.testThree"); }

@end

@interface GammaTests : XCTestCase
@end

@implementation GammaTests

+ (void)setUp { NSLog(@"order: Gamma +setUp"); }
+ (void)tearDown { NSLog(@"order: Gamma +tearDown"); }
- (void)testOne { NSLog(@"order: Gamma.testOne"); }
- (void)testTwo { NSLog(@"order: Gamma.testTwo"); }
- (void)testThree { NSLog(@"order: Gamma.testThree"); }

@end
