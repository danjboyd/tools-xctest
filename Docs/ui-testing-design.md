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

   - **(a) Recommended:** run UI tests (classes that opt in) on a separate
     test thread, while the main thread keeps running the app normally.
     Queries and actions are carried out on the main thread, in the
     default, modal-panel and event-tracking run-loop modes, so tests can
     drive alerts and modal windows. A *synchronous* hop isn't enough: an
     action that opens a modal loop never returns while the loop runs, so
     the test thread would block as it does today. Actions are therefore
     dispatched asynchronously and complete in one of two ways; see
     [Threading and dispatch](#threading-and-dispatch-for-1a). That's
     closest to how Apple's UI tests behave.
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

## Threading and dispatch (for 1a)

This section answers the review of the first draft: a synchronous
main-thread dispatch of an action that enters `runModal` still blocks the
test thread. Nothing here changes hosted tests that don't opt in.

### Who runs where

- **Opt-in.** A test class opts in with `+ (BOOL) runsOnUITestThread`
  returning YES. (A later `libXCTestUI` base class could return YES.)
  Every other class runs exactly as today: on the main thread, in the
  usual order.
- **The test thread.** If a loaded class opts in, the loader runs the
  whole run on one test thread and the main thread returns to its run
  loop. The test thread hands each class that doesn't opt in to the main
  thread and waits for it, so those still run on the main thread, in
  order. When the run ends, it hands the result back to the main thread,
  which exits as today. **The main thread never waits on the test
  thread.** That one rule removes the deadlocks where each thread waits
  for the other. A run where no class opts in takes the old path
  unchanged.
- **AppKit stays on the main thread.** Tests use the API. They don't touch
  `NSView`s or `NSWindow`s directly. Called on the main thread, the API
  runs blocks directly.

### How a query is serviced

A query, such as finding a button or reading a label, is a block that
runs on the main thread and returns a value-only snapshot: no AppKit
objects cross threads.
- It's queued with `-performSelector:onThread:withObject:waitUntilDone:NO
  modes:` in `NSDefaultRunLoopMode`, `NSModalPanelRunLoopMode` and
  `NSEventTrackingRunLoopMode`.
  - GNUstep's `runModalForWindow:` waits for events in
    `NSModalPanelRunLoopMode` (`NSApplication.m`), so a query is serviced
    while an alert or modal window is up.
  - Control and scroller tracking, and other `nextEventMatchingMask:` loops,
    wait in `NSEventTrackingRunLoopMode`.
- The test thread waits on a condition for the result, up to the query
  timeout (default 10 s). It doesn't pump the main thread or wait without a
  limit.
- If the main thread is in a nested loop running some other mode, or busy
  and not in a loop at all, the query times out. The test then records a
  failure naming the query and the main thread's current run-loop mode,
  not a hang.

### How an action completes

An action (`click`, `typeText:`, a menu item) can run a nested loop and
not return for as long as that loop runs. So it isn't waited on directly:
1. The test thread queues the action block, in the same modes as a query.
   It waits, up to the timeout, for the block to signal that it has
   *started*.
2. Only then does it queue a *probe* block. Queuing the probe later
   matters: a run loop may take a batch of queued performers at once, and
   a probe in the same batch as the action wouldn't run until the action
   returned. Queued after the action has started, the probe runs either
   after the action has returned, or **inside** the action's nested loop:
   the modal loop services `NSModalPanelRunLoopMode` performers.
3. The probe tells the test thread which case it was:
   - **Completed.** The action returned. Its exceptions and failures go
     back to the test thread and are recorded there.
   - **Running in a nested loop.** The action started a modal session or a
     tracking loop, and it's still on the stack. `click` returns, and the
     test goes on to drive the alert. The action is recorded as
     *outstanding* on the app object.
4. After each action block, the dispatch posts an `NSApplicationDefined`
   event. GNUstep's modal loop only notices `stopModal` or `abortModal` on
   its next event, and a synthetic click doesn't produce one.
   When an outstanding action's block finally returns, for example after
   the test clicks the alert's OK button, it marks itself completed.
   `-[XCUIApplication waitForIdleWithTimeout:]` waits for every
   outstanding action to complete.
5. If the probe doesn't run within the action timeout, the action never
   started, or it is blocked outside any run loop (a busy loop, or a lock).
   The test records a failure saying which.

Apple's `click` returns once the app is idle. Ours returns once the app
is idle *or* parked in a nested loop, which is when a test can do anything
useful next.

### Timeouts, cancellation and teardown

- **Timeouts.** Each query and action has a timeout (default 10 s). It's
  set per call, and the default with
  `+[GSXCTestMainThread setDefaultTimeout:]` (the phase 2 dispatch API). The existing per-test execution
  time allowance still applies on top and ends the run if a test overruns.
- **Cancellation.** A block that hasn't started by its timeout is
  cancelled: it checks a shared flag when it starts and returns at once if
  it was cancelled. A block that has started can't be stopped from
  another thread. The action reports *blocked*, and the test decides; it
  may well recover once the main thread is free.
- **Wedged.** If the main thread still doesn't answer during teardown
  (below), the app is *wedged*. That test fails, and every later test,
  UI or not, fails without running ("the application stopped responding
  in an earlier test"). The results are still written. The loader then
  exits from the test thread, since the main thread can't run the exit,
  so a wedged app can't hang the run. xctest's own host timeout stays as
  the last resort.
- **Teardown after each test.** Before `tearDown` returns, the runner, on
  the main thread through the same dispatch:
  - fails the test if actions are still outstanding, or a modal session
    the test started is still running;
  - ends those sessions with `-[NSApp abortModal]` plus a wake event (see
    the spike results) (queued in
    `NSModalPanelRunLoopMode`), up to 3 nested sessions, waiting up to the
    timeout for each to unwind;
  - reports an exception an action raised as a failure of the test.

  Closing windows the test opened is left for later; phase 2 doesn't do
  it.

  If cleanup itself times out, the app is wedged, as above.
- **End of run.** The test thread finishes, posts the result to the main
  thread, and the main thread exits as today. Only a wedged app exits from
  the test thread.

### Expectations

- `XCTestExpectation`, `XCTWaiter` and `waitForExpectations…` already wait
  by running the *calling* thread's run loop and are thread-safe to
  fulfil. On the test thread they run the test thread's run loop.
- Main-thread callbacks that fulfil an expectation (a notification, a
  delegate method) work unchanged. `-fulfill` is thread-safe.
- `waitForExistenceWithTimeout:` is an `XCTNSPredicateExpectation`. Its
  predicate is evaluated on the test thread, and each evaluation is one
  main-thread query with a short timeout.
- **Not supported:** waiting for an expectation *on the main thread* from a
  UI test (that would mean dispatching a wait), and a non-UI test
  (main thread) waiting on something a UI test does.
- The runner's existing nested-wait check applies per thread.

### The spike (proof before approval)

One bounded, runner-first experiment, not production code:
- an opt-in test class on a test thread in a hosted app built in code;
- it opens an `NSAlert` with `runModal` through an asynchronously
  dispatched action, sees the probe report "running in a nested loop",
  queries the alert, clicks OK, and sees the action complete;
- a failure path: an action that blocks the main thread past its timeout
  is reported, the app is marked wedged, and the run exits cleanly;
- teardown with an alert left open is failed and cleaned up by
  `abortModal`.

It runs under a private Xvfb with a scratch GNUstep user configuration
(`GNUSTEP_USER_CONFIG_FILE`, with absolute `GNUSTEP_USER_DIR` and
`GNUSTEP_USER_DEFAULTS_DIR`) and a hard outer timeout. It must also clean
up its own processes. The results, including any failure, are recorded
below before the direction goes for approval.

#### Results

Run on 2026-11-10 on branch `spike/ui-test-thread` (danjboyd fork), on
Debian 13 with clang 19 and the installed gnustep-gui, with
`Tests/run-ui-thread-spike.sh` (private `xvfb-run -a`, scratch GNUstep
config, 90 s outer limit). The final run passed 4/4 tests in about 3.5 s
and exited 0 by itself. No HostApp, Xvfb or scratch directory was left
behind.

- **Alert open and dismiss: works.** `runModal` dispatched as an action
  was reported "in a nested loop". A query inside the modal loop found the
  alert's OK button. Clicking it ended the loop, the opening action
  completed, `runModal` returned `NSAlertFirstButtonReturn`, and no modal
  window was left.
- **Teardown of an alert left open: works.** `abortModal`, queued in the
  modal mode, ended one session, and the opening action completed.
- **Expectation on the test thread** fulfilled from a main-thread timer:
  works.
- **Failure path: works.** An action that blocks the main thread for 3 s
  was reported "blocked outside a run loop" after its 1 s timeout. A query
  meanwhile timed out at 0.5 s. Queries worked again once the main thread
  was free. Nothing hung.

What the runs found, now part of the design:
1. **Programmatic stops need a wake event.** GNUstep's
   `stopModalWithCode:` and `abortModal` only set the session's state, and
   the modal loop notices on its next event. A synthetic click or
   teardown has none, so the dispatch posts an `NSApplicationDefined` event
   after each action. In a control run without it, the OK click left the
   alert up, and the opening action never completed within its timeout.
2. **A completed click may first show as "in a nested loop".** GNUstep's
   `performClick:` runs the run loop for 0.1 s to show the highlight, and
   the probe can run in that loop. So `click` returns either way, and
   completion is judged by `waitForIdle`, as described above, never by the
   probe's first answer.
3. **Find controls in the window, not through the model.**
   `-[NSAlert buttons]` returns templates that are never in a window; the
   panel copies their titles and tags. Clicking a template does nothing.
   The first run failed this way. Queries walk the real window's views,
   which the proposed API does anyway.
4. **A modal left over affects the next test.** In the first run, test A's
   alert stayed up beneath test B's, and teardown ended both. That's why
   per-test teardown has to check for and end modal sessions.

Not covered by the spike: sheets, menu tracking
(`NSEventTrackingRunLoopMode`), nested modals deeper than two, and
`typeText:`.

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

1. Run the spike above and record its results. Then answer the decisions
   above.
2. If 1(a): run opted-in test classes on a test thread inside the host,
   with the main thread running the app. That means the dispatch, probe,
   timeouts and teardown described above, with expectations checked on
   that thread. This is runner work, with its own PR and tests.
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
