#import <AppKit/AppKit.h>
#import <XCTest/XCTest.h>

// Tests meant to run inside HostApp via `xctest -host`. Without a host
// application there is no NSApp, so they skip.
@interface HostedTests : XCTestCase
@end

@implementation HostedTests

- (void)setUp
{
    XCTSkipUnless(NSApp != nil, @"needs a host application");
}

- (void)testRunsInsideTheLaunchedApplication
{
    XCTAssertTrue([NSThread isMainThread]);
    XCTAssertEqualObjects(NSStringFromClass([[NSApp delegate] class]), @"HostAppDelegate");
    // The app's own applicationDidFinishLaunching: has already run.
    XCTAssertEqualObjects([(NSObject *)[NSApp delegate] valueForKey:@"launched"], [NSNumber numberWithBool:YES]);
}

- (void)testCanSeeTheApplicationsWindows
{
    BOOL found = NO;

    for (NSWindow *window in [NSApp windows]) {
        if ([[window title] isEqualToString:@"HostAppWindow"]) {
            found = YES;
        }
    }
    XCTAssertTrue(found);
}

- (void)testAsyncWorkRunsOnTheApplicationsRunLoop
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"delayed"];

    [expectation performSelector:@selector(fulfill) withObject:nil afterDelay:0.05];
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testChildProcessesDoNotRunTheTestsAgain
{
    NSTask *task = [[[NSTask alloc] init] autorelease];
    NSPipe *pipe = [NSPipe pipe];

    [task setLaunchPath:@"/usr/bin/env"];
    [task setStandardOutput:pipe];
    [task launch];
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];

    NSString *environment = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    XCTAssertTrue([environment rangeOfString:@"XCTEST_HOST_CONFIG"].location == NSNotFound);
    XCTAssertTrue([environment rangeOfString:@"libXCTestHost"].location == NSNotFound);
}

@end

@interface HostedFailureTests : XCTestCase
@end

@implementation HostedFailureTests

- (void)testFailsInHost
{
    XCTSkipUnless(NSApp != nil);
    XCTFail(@"hosted failure");
}

@end

// Takes longer than the launch timeout used by the regressions.
@interface HostedSlowTests : XCTestCase
@end

@implementation HostedSlowTests

- (void)testSlow
{
    XCTSkipUnless(NSApp != nil);
    [NSThread sleepForTimeInterval:3];
}

@end

// Attaches an image drawn in the host.
@interface HostedAttachmentTests : XCTestCase
@end

@implementation HostedAttachmentTests

- (void)testAttachesImage
{
    XCTSkipUnless(NSApp != nil);
    NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize(4, 4)] autorelease];

    [image lockFocus];
    [[NSColor redColor] set];
    NSRectFill(NSMakeRect(0, 0, 4, 4));
    [image unlockFocus];

    XCTAttachment *attachment = [XCTAttachment attachmentWithImage:image];
    [attachment setName:@"swatch"];
    [attachment setLifetime:XCTAttachmentLifetimeKeepAlways];
    XCTAssertEqualObjects([attachment uniformTypeIdentifier], @"public.png");
    [self addAttachment:attachment];
}

@end
