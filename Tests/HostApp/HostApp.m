#import <AppKit/AppKit.h>

#include <stdlib.h>
#include <unistd.h>

@interface HostAppDelegate : NSObject {
    NSWindow *_window;
    BOOL _launched;
}
@property (readonly) NSWindow *window;
@property (readonly) BOOL launched;
@end

@implementation HostAppDelegate

@synthesize window = _window;
@synthesize launched = _launched;

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100)
                                          styleMask:NSTitledWindowMask
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    [_window setTitle:@"HostAppWindow"];
    [_window orderFront:nil];
    _launched = YES;
    NSLog(@"hostapp: launched");
}

@end

int main(int argc, const char *argv[])
{
    // Lets the regressions check what happens when an app quits early.
    if (getenv("HOSTAPP_EXIT_EARLY") != NULL) {
        return 0;
    }

    // ... or never finishes launching.
    if (getenv("HOSTAPP_HANG") != NULL) {
        for (;;) {
            sleep(1);
        }
    }

    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        [application setDelegate:[[HostAppDelegate alloc] init]];
        [application run];
    }
    return 0;
}
