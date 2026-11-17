// A small application with a few kinds of control, for the XCUI
// regressions (Tests/run-ui-tests.sh, with Tests/UIFixture).

#import <AppKit/AppKit.h>

@interface UIHostAppDelegate : NSObject {
    NSWindow *_window;
    NSWindow *_second;
    NSInteger _count;
    NSTextField *_countLabel;
    NSTextField *_nameField;
    NSTextField *_greetingLabel;
    NSTextField *_alertLabel;
    NSButton *_rememberBox;
}
@end

@implementation UIHostAppDelegate

static NSButton *UIHostButton(NSView *parent, NSString *title, NSString *identifier, NSRect frame,
                              id target, SEL action)
{
    NSButton *button = [[[NSButton alloc] initWithFrame:frame] autorelease];

    [button setTitle:title];
    [button setIdentifier:identifier];
    [button setTarget:target];
    [button setAction:action];
    [parent addSubview:button];
    return button;
}

static NSTextField *UIHostLabel(NSView *parent, NSString *text, NSString *identifier, NSRect frame)
{
    NSTextField *label = [[[NSTextField alloc] initWithFrame:frame] autorelease];

    [label setStringValue:text];
    [label setIdentifier:identifier];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [parent addSubview:label];
    return label;
}

- (void) updateCount
{
    [_countLabel setStringValue:[NSString stringWithFormat:@"Count: %ld", (long)_count]];
}

- (void) increment: (id)sender
{
    _count++;
    [self updateCount];
}

- (void) greet: (id)sender
{
    [_greetingLabel setStringValue:[NSString stringWithFormat:@"Hello, %@", [_nameField stringValue]]];
}

- (void) showAlert: (id)sender
{
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    NSInteger result;

    [alert setMessageText:@"Are you sure?"];
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    result = [alert runModal];
    [_alertLabel setStringValue:result == NSAlertFirstButtonReturn ? @"Alert: OK" : @"Alert: Cancel"];
}

- (void) openSecondWindow
{
    if (_second == nil) {
        _second = [[NSWindow alloc] initWithContentRect:NSMakeRect(420, 100, 200, 100)
                                              styleMask:NSTitledWindowMask
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
        [_second setTitle:@"Second"];
        [_second setReleasedWhenClosed:NO];
    }
    [_second orderFront:nil];
}

- (void) openLater: (id)sender
{
    [self performSelector:@selector(openSecondWindow) withObject:nil afterDelay:0.3];
}

// Puts everything back as it was at launch.
- (void) reset: (id)sender
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    _count = 0;
    [self updateCount];
    [_window makeFirstResponder:nil];
    [_nameField setStringValue:@""];
    [_greetingLabel setStringValue:@""];
    [_alertLabel setStringValue:@""];
    [_rememberBox setState:NSOffState];
    [_second orderOut:nil];
}

// Never sent: the menu item is disabled. If it ever is, the alert label
// says so, and the failure test that clicks it checks the label.
- (void) unavailable: (id)sender
{
    [_alertLabel setStringValue:@"Unavailable ran"];
}

- (BOOL) validateMenuItem: (NSMenuItem *)item
{
    return [item action] != @selector(unavailable:);
}

- (void) buildMenu
{
    NSMenu *mainMenu = [[[NSMenu alloc] initWithTitle:@"UIHostApp"] autorelease];
    NSMenu *actions = [[[NSMenu alloc] initWithTitle:@"Actions"] autorelease];
    NSMenuItem *actionsItem = [mainMenu addItemWithTitle:@"Actions" action:NULL keyEquivalent:@""];

    [[actions addItemWithTitle:@"Reset" action:@selector(reset:) keyEquivalent:@""] setTarget:self];
    [[actions addItemWithTitle:@"Unavailable" action:@selector(unavailable:) keyEquivalent:@""] setTarget:self];
    [mainMenu setSubmenu:actions forItem:actionsItem];
    [NSApp setMainMenu:mainMenu];
}

- (void) applicationDidFinishLaunching: (NSNotification *)notification
{
    NSView *content;
    NSTextField *password;
    NSButton *radio;
    NSButton *hidden;
    NSPopUpButton *popUp;

    [self buildMenu];
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 400, 330)
                                          styleMask:NSTitledWindowMask
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    [_window setTitle:@"Main"];
    content = [_window contentView];

    UIHostButton(content, @"Increment", @"incrementButton", NSMakeRect(10, 290, 100, 24), self, @selector(increment:));
    _countLabel = UIHostLabel(content, @"Count: 0", @"countLabel", NSMakeRect(120, 290, 150, 24));

    _nameField = [[[NSTextField alloc] initWithFrame:NSMakeRect(10, 255, 150, 24)] autorelease];
    [_nameField setIdentifier:@"nameField"];
    [[_nameField cell] setPlaceholderString:@"Name"];
    [_nameField setTarget:self];
    [_nameField setAction:@selector(greet:)];
    [content addSubview:_nameField];
    _greetingLabel = UIHostLabel(content, @"", @"greetingLabel", NSMakeRect(170, 255, 200, 24));

    password = [[[NSSecureTextField alloc] initWithFrame:NSMakeRect(10, 220, 150, 24)] autorelease];
    [password setIdentifier:@"passwordField"];
    [content addSubview:password];

    _rememberBox = UIHostButton(content, @"Remember me", @"rememberBox", NSMakeRect(10, 185, 150, 24), nil, NULL);
    [_rememberBox setButtonType:NSSwitchButton];
    radio = UIHostButton(content, @"Small", @"smallRadio", NSMakeRect(170, 185, 100, 24), nil, NULL);
    [radio setButtonType:NSRadioButton];

    popUp = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(10, 150, 150, 24) pullsDown:NO] autorelease];
    [popUp setIdentifier:@"colourPopUp"];
    [popUp addItemsWithTitles:[NSArray arrayWithObjects:@"Red", @"Green", nil]];
    [content addSubview:popUp];

    [UIHostButton(content, @"Disabled", @"disabledButton", NSMakeRect(10, 115, 100, 24), self, @selector(increment:))
        setEnabled:NO];
    hidden = UIHostButton(content, @"Hidden", @"hiddenButton", NSMakeRect(120, 115, 100, 24), self, @selector(increment:));
    [hidden setHidden:YES];
    // Outside the window's content: not hittable.
    UIHostButton(content, @"Outside", @"outsideButton", NSMakeRect(1000, 115, 100, 24), self, @selector(increment:));

    UIHostButton(content, @"Twin", @"twinA", NSMakeRect(10, 80, 80, 24), self, @selector(increment:));
    UIHostButton(content, @"Twin", @"twinB", NSMakeRect(100, 80, 80, 24), self, @selector(increment:));
    UIHostButton(content, @"Open Later", @"openLaterButton", NSMakeRect(190, 80, 100, 24), self, @selector(openLater:));

    UIHostButton(content, @"Show Alert", @"alertButton", NSMakeRect(10, 45, 100, 24), self, @selector(showAlert:));
    _alertLabel = UIHostLabel(content, @"", @"alertLabel", NSMakeRect(120, 45, 150, 24));

    [_window makeKeyAndOrderFront:nil];
    NSLog(@"uihostapp: launched");
}

@end

int main(int argc, const char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSApplication *application = [NSApplication sharedApplication];

    [application setDelegate:[[UIHostAppDelegate alloc] init]];
    [application run];
    [pool release];
    return 0;
}
