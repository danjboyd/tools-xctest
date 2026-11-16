#import <AppKit/AppKit.h>
#import "AppDelegate.h"

int
main(int argc, const char *argv[])
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  [NSApplication sharedApplication];
  [NSApp setDelegate: [[AppDelegate alloc] init]];
  [pool release];
  return NSApplicationMain(argc, argv);
}
