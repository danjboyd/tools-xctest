# UI testing for hosted tests: design (issue #26)

A design pass, before any code. It proposes an API for driving a GNUstep
application's UI from hosted tests (`xctest -host`), and lists the decisions
that need an answer first. Nothing here is built yet.

## Where things stand

- `xctest -host MyApp.app MyTests.xctest` launches the app with
  `libXCTestHost` preloaded. When the app posts
  `NSApplicationDidFinishLaunchingNotification`, the loader waits one turn of
  the run loop, loads the bundle and runs the tests **on the main thread**,
  then exits with the result (`XCTest/GSXCTestHostLoader.m`).
- So a test can already reach the app's objects (`NSApp`, its delegate,
  `[NSApp windows]`) and attach screenshots (`XCTAttachment` takes an
  `NSImage`). What's missing is a way to find controls and act on them the
  way a user would, and to wait for the UI to change.
- `libXCTest` doesn't link AppKit, and `libXCTestHost` only listens for a
  notification by name. Non-GUI users must keep getting an AppKit-free
  library.

## Approach: in process, over AppKit

Apple's XCUITest drives the app from another process through the
accessibility API. On GNUstep the accessibility layer is thin, and there's
no cross-process automation service. A hosted test, though, already runs
inside the app, so it can walk the view hierarchy and call AppKit directly.
That's simpler, has no IPC, and covers the common cases: find a control,
click or type, check what changed.

The cost is fidelity. Calling `performClick:` doesn't go through hit
testing, so it will "click" a hidden or covered button. The design deals
with that in the actions (below) by checking that an element is hittable
before acting.

## Proposed API

The names follow Apple's where the behaviour matches, so tests read
familiarly. There's no promise of source compatibility with XCUITest.

```objc
XCUIApplication *app = [XCUIApplication currentApplication]; // the host app

XCUIElement *window = [[app windows] elementMatchingTitle:@"Preferences"];
[[[window buttons] elementMatchingTitle:@"OK"] click];

XCUIElement *name = [[app textFields] elementMatchingIdentifier:@"nameField"];
[name click];
[name typeText:@"Ada"];
XCTAssertEqualObjects([name value], @"Ada");

[[app menuItems] elementMatchingPath:@[@"File", @"Open…"]] ... ;
XCTAssertTrue([[[app sheets] firstMatch] waitForExistenceWithTimeout:2]);
```

**XCUIApplication.** `+currentApplication` wraps `NSApp`. There's no
`launch`/`terminate`: `xctest -host` owns the app's lifetime. It's also an
`XCUIElement` whose children are the app's windows and main menu.

**XCUIElement.** It's a lazy query: it holds the query that found it and
resolves it again whenever it's used, as Apple's does, so it stays valid
when the window is rebuilt.
- *State:* `exists`, `hittable` (visible, in an on-screen window, enabled,
  not covered), `title`, `label`, `identifier`, `value`, `enabled`,
  `selected`, `frame`, `elementType`.
- *Actions:* `click`, `doubleClick`, `typeText:`, `typeKey:modifierFlags:`,
  and `chooseMenuItem` for menu items.
- *Waiting:* `waitForExistenceWithTimeout:` and
  `waitForNonExistenceWithTimeout:` (built on `XCTWaiter` and
  `XCTNSPredicateExpectation`, which already exist).
- `screenshot`, returning an `XCTAttachment`.

**XCUIElementQuery.** It's built from typed descendants: `windows`,
`sheets`, `buttons`, `checkBoxes`, `radioButtons`, `textFields`,
`secureTextFields`, `staticTexts`, `popUpButtons`, `menuItems`, `tables`,
`cells`, `otherElements`.
- *Matching:* by title or label, identifier, class, or an `NSPredicate`.
- *Results:* `elementMatchingTitle:` / `…Identifier:`, `elementBoundByIndex:`,
  `firstMatch`, `count`, `allElements`.
- A query that matches several elements fails the test when it's used where
  one is needed, naming the matches, as Apple's does.

**Element types.** They're mapped from AppKit classes:
- `NSButton` → button, checkbox or radio, by its button type.
- `NSTextField` → text field when it's editable, static text when it isn't.
- `NSSecureTextField` → secure text field.
- `NSPopUpButton` → pop-up button.
- `NSTableView` and its rows → table and cells.
- `NSMenuItem` → menu item.
- A window with a sheet parent → sheet.
- Anything else → other element.

Identifiers come from `-[NSView identifier]`
(`NSUserInterfaceItemIdentification`, which GNUstep has). Labels come from
the title, or else `accessibilityLabel` where a class implements it.

**Actions are AppKit calls by default**, with synthesized events as a
fallback:
- `click`: `performClick:` on an `NSControl`, which runs the target/action
  and its bindings the way a real click does. A click on something that
  isn't a control goes as synthesized mouse-down and mouse-up events
  through `-[NSWindow sendEvent:]` at the element's centre.
- `typeText:`: makes the element first responder, then sends key events
  through `-[NSWindow sendEvent:]` so that field editors, formatters and
  delegates see them. `insertText:` would skip `keyDown:` overrides.
- Menu items: `-[NSMenu performActionForItemAtIndex:]`, after finding the
  item by its path of titles.
- Every action first checks that the element exists and is hittable, and
  records a failure (not an exception) if it isn't.
- Every action then lets the run loop turn over once before returning, so
  the UI has updated.

## Decisions needed

1. **Main thread or a test thread.** Today a hosted test runs on the main
   thread. That breaks on anything modal:
   - If a click opens `runModalForWindow:` or an `NSAlert`, the app's modal
     loop runs inside the test's own call, and the test can't continue
     until something ends the modal session.
   - Apple avoids this because its tests are another process.

   - **(a) Recommended:** run UI tests (classes that use `XCUIApplication`,
     or are marked to) on a separate test thread, while the main thread
     keeps running the app normally. Every query and action hops to the
     main thread, synchronously, in the default *and* modal run-loop modes,
     so tests can drive alerts and modal windows. That's closest to how
     Apple's UI tests behave.
     - Costs: a second threading model in the runner.
     - Costs: `XCTWaiter` and expectations must work from a non-main thread.
     - Costs: tests must not touch AppKit objects directly, only through
       the API.
   - **(b)** Keep the main thread and don't support modal loops in the
     first cut. Tests would have to avoid alerts and modal windows, or
     stub them. Simpler, but it hits a common case early.
   - **(c)** Keep the main thread and make each action asynchronous, so a
     click that opens a modal loop returns first. The modal session still
     can't be driven from straight-line test code, so this doesn't solve
     the problem.

2. **Where it lives.** It needs AppKit, which `libXCTest` mustn't link.
   - **Proposed:** a separate optional library, `libXCTestUI`, with its
     header `XCTest/XCUI.h` (`#import <XCTest/XCUI.h>`). It's built only
     when gnustep-gui is found (gnustep-make and Meson). `xctest.make`
     links it for bundles that set `<Bundle>_XCTEST_UI = yes`, or whenever
     `XCTEST_HOST` is set.
   - `XCTest/XCTest.h` stays as it is. Apple's umbrella header includes the
     XCUI classes; ours wouldn't, so that non-GUI tests keep building
     without AppKit.

3. **Names.** `XCUIApplication`, `XCUIElement` and `XCUIElementQuery`, as
   Apple's (recommended), or GNUstep-prefixed names (`GSXCUIElement`, ...)
   that make clear it isn't XCUITest. Apple's names read better in tests
   ported from Xcode. The risk is that people expect behaviour we don't
   have, such as `launch` and cross-process queries.

4. **Hittability.** It needs care to get right (covered views, clipped
   scroll views, hidden ancestors, off-screen windows under Xvfb).
   - **Proposed:** start with "visible, enabled, in an ordered-in window,
     frame inside the window's content", and leave occlusion by other
     windows for later.

## Testing it

- A new `Tests/UIHostApp`, a small app built in code (no .gorm/.nib):
  - a main window with a button that updates a label;
  - a text field with an identifier;
  - a checkbox;
  - a pop-up button;
  - a menu with a nested item;
  - a button that opens a sheet;
  - a button that runs an `NSAlert` modally.
- `Tests/UIFixture` holds the tests, run by a new
  `Tests/run-ui-tests.sh` under `xvfb-run -a` (as the hosted tests are),
  and skipped without a display.
- Each action is checked by its effect on the app: the label's text, the
  delegate's state, a sheet appearing and closing. Failure messages are
  checked as well: an ambiguous query, a missing element, a click on a
  disabled button.
- Windows: `-host` isn't supported there (it relies on `LD_PRELOAD`), so
  this is Linux-only until hosting works on Windows.

## Phases

1. Answer the decisions above.
2. If 1(a): run a test class on a test thread inside the host, with the
   main thread running the app. Make `XCTWaiter` and expectations work
   there. This is runner work, with its own PR and tests.
3. `libXCTestUI`:
   - queries and element types;
   - `click`, `typeText:`, menus;
   - waiting;
   - screenshots;
   - the UIHostApp tests.
4. Modal windows and alerts (with 1a), sheets, tables.
5. Docs: a README section and the man page's `-host` entry.

## Not covered

- Launching or terminating the app from a test (`-[XCUIApplication launch]`):
  `xctest -host` launches it.
- Testing several apps, or a system UI.
- Gestures beyond click, double-click and typing; drag and drop.
- Recording tests (Xcode's UI recorder).
- Swift names for this API. They would come later through the Swift
  overlay, kept separate as the rest of it is.
