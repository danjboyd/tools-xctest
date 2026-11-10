// Run by Tests/run-ui-thread-tests.sh in Tests/HostApp (xctest -host).
// UIThreadDispatchTests opts in to the UI test thread; the Ordinary
// classes, before and after it, don't, and must still run on the main
// thread. UIThreadTeardownTests and UIThreadWedgedTests are run on their
// own, as they're meant to fail.

#import <AppKit/AppKit.h>
#import <XCTest/XCTest.h>
#import <XCTest/GSXCTestMainThread.h>

#include <unistd.h>

static NSInteger UIThreadAlertResult = 0;

// Opens an alert with runModal, as an action.
static GSXCTestMainThreadAction *UIThreadOpenAlert(NSString *message)
{
    UIThreadAlertResult = 0;
    return [GSXCTestMainThread performAction:^id (void) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];

        [alert setMessageText:message];
        [alert addButtonWithTitle:@"OK"];
        [alert addButtonWithTitle:@"Cancel"];
        UIThreadAlertResult = [alert runModal];
        return nil;
    } timeout:5];
}

// The button titled \a title under \a view. Main thread only.
static NSButton *UIThreadFindButton(NSView *view, NSString *title)
{
    if ([view isKindOfClass:[NSButton class]] && [[(NSButton *)view title] isEqual:title]) {
        return (NSButton *)view;
    }
    for (NSView *subview in [view subviews]) {
        NSButton *found = UIThreadFindButton(subview, title);

        if (found != nil) {
            return found;
        }
    }
    return nil;
}

static BOOL UIThreadModalWindowIsUp(void)
{
    BOOL timedOut = NO;
    id up = [GSXCTestMainThread performQuery:^id (void) {
        return [NSNumber numberWithBool:[NSApp modalWindow] != nil];
    } timeout:5 timedOut:&timedOut];

    return !timedOut && [up boolValue];
}

@interface UIThreadAOrdinaryTests : XCTestCase
@end

@implementation UIThreadAOrdinaryTests

- (void) testRunsOnTheMainThread
{
    XCTAssertTrue([NSThread isMainThread], @"expected a class that doesn't opt in to run on the main thread");
    NSLog(@"uithread: ordinary class before ran on the main thread");
}

@end

@interface UIThreadDispatchTests : XCTestCase
@end

@implementation UIThreadDispatchTests

+ (BOOL) runsOnUITestThread
{
    return YES;
}

- (void) setUp
{
    XCTAssertFalse([NSThread isMainThread], @"expected an opted-in class to run on the test thread");
    XCTAssertTrue([GSXCTestMainThread isTestThreadActive]);
}

// An alert opened by an action is found by a query inside its modal loop
// and dismissed by clicking OK; then the opening action completes.
- (void) testAModalAlertOpensAndIsDismissed
{
    GSXCTestMainThreadAction *open = UIThreadOpenAlert(@"Dispatch alert");
    GSXCTestMainThreadAction *click;
    BOOL timedOut = NO;
    NSString *title;

    XCTAssertEqual([open state], GSXCTestMainThreadActionInNestedLoop);
    XCTAssertFalse([open isFinished]);
    XCTAssertTrue(UIThreadModalWindowIsUp());

    title = [GSXCTestMainThread performQuery:^id (void) {
        return [UIThreadFindButton([[NSApp modalWindow] contentView], @"OK") title];
    } timeout:5 timedOut:&timedOut];
    XCTAssertFalse(timedOut, @"expected the query to be serviced inside the modal loop");
    XCTAssertEqualObjects(title, @"OK");

    // performClick: shows the highlight in a short nested loop, so the click
    // may be reported in a nested loop; either way it then completes.
    click = [GSXCTestMainThread performAction:^id (void) {
        [UIThreadFindButton([[NSApp modalWindow] contentView], @"OK") performClick:nil];
        return nil;
    } timeout:5];
    XCTAssertTrue([click state] == GSXCTestMainThreadActionCompleted
                  || [click state] == GSXCTestMainThreadActionInNestedLoop);
    XCTAssertTrue([GSXCTestMainThread waitForIdleWithTimeout:5], @"expected the click and the alert to finish");
    XCTAssertTrue([open isFinished]);
    XCTAssertEqual(UIThreadAlertResult, (NSInteger)NSAlertFirstButtonReturn);
    XCTAssertFalse(UIThreadModalWindowIsUp());
    NSLog(@"uithread: alert opened and dismissed");
}

// An expectation on the test thread, fulfilled from the main thread.
- (void) testBExpectationFulfilledOnTheMainThread
{
    XCTestExpectation *done = [self expectationWithDescription:@"fulfilled on the main thread"];
    BOOL timedOut = NO;

    [GSXCTestMainThread performQuery:^id (void) {
        [done performSelector:@selector(fulfill) withObject:nil afterDelay:0.2];
        return nil;
    } timeout:5 timedOut:&timedOut];
    XCTAssertFalse(timedOut);
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

// A main thread blocked outside any run loop is reported within the
// timeout, and the main thread answers again once it's free.
- (void) testCBlockedMainThreadIsReported
{
    GSXCTestMainThreadAction *busy = [GSXCTestMainThread performAction:^id (void) {
        sleep(2);
        return @"done";
    } timeout:0.5];
    BOOL timedOut = NO;

    XCTAssertEqual([busy state], GSXCTestMainThreadActionBlocked);
    [GSXCTestMainThread performQuery:^id (void) { return nil; } timeout:0.2 timedOut:&timedOut];
    XCTAssertTrue(timedOut, @"expected a query to time out while the main thread is blocked");

    XCTAssertTrue([busy waitUntilFinishedWithTimeout:5]);
    XCTAssertEqualObjects([busy result], @"done");
    [GSXCTestMainThread performQuery:^id (void) { return nil; } timeout:5 timedOut:&timedOut];
    XCTAssertFalse(timedOut, @"expected queries to work again once the main thread is free");
    NSLog(@"uithread: blocked main thread reported");
}

// A query's exception is raised on the test thread; one that never starts
// is cancelled and never runs.
- (void) testDQueryExceptionAndCancellation
{
    __block BOOL ran = NO;
    GSXCTestMainThreadAction *busy;
    BOOL timedOut = NO;

    XCTAssertThrowsSpecificNamed(([GSXCTestMainThread performQuery:^id (void) {
        [NSException raise:@"UIThreadQueryException" format:@"from the main thread"];
        return nil;
    } timeout:5 timedOut:NULL]), NSException, @"UIThreadQueryException");

    busy = [GSXCTestMainThread performAction:^id (void) {
        sleep(1);
        return nil;
    } timeout:0.2];
    [GSXCTestMainThread performQuery:^id (void) {
        ran = YES;
        return nil;
    } timeout:0.1 timedOut:&timedOut];
    XCTAssertTrue(timedOut);
    XCTAssertTrue([busy waitUntilFinishedWithTimeout:5]);
    [GSXCTestMainThread performQuery:^id (void) { return nil; } timeout:5 timedOut:NULL];
    XCTAssertFalse(ran, @"expected a cancelled query never to run");
}

@end

@interface UIThreadZOrdinaryTests : XCTestCase
@end

@implementation UIThreadZOrdinaryTests

- (void) testRunsOnTheMainThreadAfterTheUIClass
{
    XCTAssertTrue([NSThread isMainThread]);
    XCTAssertNil([NSApp modalWindow], @"expected no modal window left by the UI class");
    NSLog(@"uithread: ordinary class after ran on the main thread");
}

@end

// Run on its own: the first test leaves an alert open, so teardown fails it
// and ends the alert; the second then starts clean.
@interface UIThreadTeardownTests : XCTestCase
@end

@implementation UIThreadTeardownTests

+ (BOOL) runsOnUITestThread
{
    return YES;
}

- (void) testALeavesAnAlertOpen
{
    XCTAssertEqual([UIThreadOpenAlert(@"Left open") state], GSXCTestMainThreadActionInNestedLoop);
}

- (void) testBStartsClean
{
    XCTAssertFalse(UIThreadModalWindowIsUp(), @"expected teardown to have ended the alert");
    NSLog(@"uithread: next test started clean");
}

@end

// Run on its own: the first test blocks the main thread past teardown's
// timeout, so the application is treated as stopped; the rest fail without
// running, and the run ends without waiting for the main thread.
@interface UIThreadWedgedTests : XCTestCase
@end

@implementation UIThreadWedgedTests

+ (BOOL) runsOnUITestThread
{
    return YES;
}

- (void) setUp
{
    [GSXCTestMainThread setDefaultTimeout:1];
}

- (void) testABlocksTheMainThread
{
    [GSXCTestMainThread performAction:^id (void) {
        sleep(30);
        return nil;
    } timeout:0.5];
}

- (void) testBNeverRuns
{
    NSLog(@"uithread: a test ran after the application stopped responding");
}

@end
