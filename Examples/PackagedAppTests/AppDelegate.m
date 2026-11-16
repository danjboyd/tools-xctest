#import "AppDelegate.h"
#import "Greeter.h"

@implementation AppDelegate

- (void) applicationDidFinishLaunching: (NSNotification *)notification
{
  Greeter *greeter = [[[Greeter alloc] init] autorelease];
  NSTextField *label;

  window = [[NSWindow alloc]
    initWithContentRect: NSMakeRect(200, 200, 320, 120)
              styleMask: NSTitledWindowMask | NSClosableWindowMask
                backing: NSBackingStoreBuffered
                  defer: NO];
  [window setTitle: @"Greeter"];

  label = [[[NSTextField alloc]
    initWithFrame: NSMakeRect(20, 45, 280, 30)] autorelease];
  [label setEditable: NO];
  [label setBezeled: NO];
  [label setDrawsBackground: NO];
  [label setStringValue: [greeter greetingForName: NSUserName()]];
  [[window contentView] addSubview: label];

  [window makeKeyAndOrderFront: nil];
}

- (BOOL) applicationShouldTerminateAfterLastWindowClosed: (NSApplication *)app
{
  return YES;
}

- (void) dealloc
{
  [window release];
  [super dealloc];
}

@end
