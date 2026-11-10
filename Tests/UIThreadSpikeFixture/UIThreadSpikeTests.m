// SPIKE (#26), not production code. Run by Tests/run-ui-thread-spike.sh in
// a host app, with XCTEST_SPIKE_UI_TEST_THREAD set so the loader runs these
// tests on a test thread while the main thread runs the application.
//
// It checks the dispatch described in Docs/ui-testing-design.md:
// an asynchronously dispatched action that enters a modal loop, a probe
// queued after the action has started, queries serviced inside the modal
// loop, a main thread blocked outside any run loop, teardown of a modal
// session left open, and an expectation fulfilled from the main thread.

#import <AppKit/AppKit.h>
#import <XCTest/XCTest.h>

typedef id (^SpikeBlock)(void);

// One block to run on the main thread, and what the test thread learns
// about it: started, finished, its result or exception, or cancelled.
@interface SpikeHop : NSObject
{
@public
    SpikeBlock block;
    NSCondition *condition;
    BOOL started;
    BOOL finished;
    BOOL cancelled;
    id result;
    NSException *exception;
}
@end

@implementation SpikeHop

- (id) initWithBlock: (SpikeBlock)aBlock
{
    if ((self = [super init]) != nil) {
        block = [aBlock copy];
        condition = [NSCondition new];
    }
    return self;
}

- (void) dealloc
{
    [block release];
    [condition release];
    [result release];
    [exception release];
    [super dealloc];
}

- (void) run
{
    id value = nil;
    NSException *caught = nil;

    [condition lock];
    if (cancelled) {
        [condition unlock];
        return;
    }
    started = YES;
    [condition broadcast];
    [condition unlock];

    @try {
        value = block();
    } @catch (NSException *e) {
        caught = e;
    }

    [condition lock];
    finished = YES;
    result = [value retain];
    exception = [caught retain];
    [condition broadcast];
    [condition unlock];
}

// Waits until started (or finished) or the timeout; returns whether it
// happened.
- (BOOL) waitForStarted: (BOOL)wantFinished timeout: (NSTimeInterval)timeout
{
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:timeout];
    BOOL done;

    [condition lock];
    while (!(done = wantFinished ? finished : started)) {
        if (![condition waitUntilDate:limit]) {
            done = wantFinished ? finished : started;
            break;
        }
    }
    [condition unlock];
    return done;
}

// Cancels it if it hasn't started; returns whether it had started.
- (BOOL) cancelUnlessStarted
{
    BOOL hadStarted;

    [condition lock];
    hadStarted = started;
    if (!started) {
        cancelled = YES;
    }
    [condition unlock];
    return hadStarted;
}

@end

static NSArray *SpikeModes(void)
{
    return [NSArray arrayWithObjects:NSDefaultRunLoopMode, NSModalPanelRunLoopMode,
                                     NSEventTrackingRunLoopMode, nil];
}

static SpikeHop *SpikeQueue(SpikeBlock block)
{
    SpikeHop *hop = [[[SpikeHop alloc] initWithBlock:block] autorelease];

    [hop performSelectorOnMainThread:@selector(run) withObject:nil waitUntilDone:NO modes:SpikeModes()];
    return hop;
}

typedef enum {
    SpikeActionCompleted,
    SpikeActionInNestedLoop,
    SpikeActionNeverStarted,
    SpikeActionBlockedOutsideRunLoop
} SpikeActionState;

static NSString *SpikeStateName(SpikeActionState state)
{
    switch (state) {
    case SpikeActionCompleted: return @"completed";
    case SpikeActionInNestedLoop: return @"in a nested loop";
    case SpikeActionNeverStarted: return @"never started";
    default: return @"blocked outside a run loop";
    }
}

// A query: runs on the main thread, waited for up to the timeout.
static id SpikeQuery(SpikeBlock block, NSTimeInterval timeout, BOOL *timedOut)
{
    SpikeHop *hop = SpikeQueue(block);

    if (![hop waitForStarted:YES timeout:timeout]) {
        [hop cancelUnlessStarted];
        *timedOut = YES;
        return nil;
    }
    *timedOut = NO;
    if (hop->exception != nil) {
        [hop->exception raise];
    }
    return hop->result;
}

// An action: queued, then a probe queued once the action has started.
static SpikeActionState SpikeAction(SpikeBlock block, NSTimeInterval timeout, SpikeHop **actionOut)
{
    SpikeHop *action = SpikeQueue(block);
    SpikeHop *probe;

    *actionOut = action;
    if (![action waitForStarted:NO timeout:timeout]) {
        if (![action cancelUnlessStarted]) {
            return SpikeActionNeverStarted;
        }
    }
    probe = SpikeQueue(^id (void) {
        BOOL done;

        [action->condition lock];
        done = action->finished;
        [action->condition unlock];
        return [NSNumber numberWithBool:done];
    });
    if (![probe waitForStarted:YES timeout:timeout]) {
        [probe cancelUnlessStarted];
        return SpikeActionBlockedOutsideRunLoop;
    }
    return [probe->result boolValue] ? SpikeActionCompleted : SpikeActionInNestedLoop;
}

static NSAlert *SpikeAlert = nil;
static NSInteger SpikeAlertResult = 0;

// Opens an alert with runModal, through an action.
static SpikeActionState SpikeOpenAlert(NSString *message, SpikeHop **action)
{
    SpikeAlertResult = 0;
    return SpikeAction(^id (void) {
        NSAlert *alert = [[NSAlert alloc] init];

        [alert setMessageText:message];
        [alert addButtonWithTitle:@"OK"];
        [alert addButtonWithTitle:@"Cancel"];
        SpikeAlert = alert;
        SpikeAlertResult = [alert runModal];
        SpikeAlert = nil;
        [alert release];
        return nil;
    }, 5, action);
}

// GNUstep's stopModalWithCode: and abortModal only set the session's
// state; the modal loop notices on its next event. Programmatic clicks
// and teardown have none, so they post an application-defined event to
// wake it.
static void SpikeWakeModalLoop(void)
{
    NSEvent *wake = [NSEvent otherEventWithType:NSApplicationDefined
                                       location:NSZeroPoint
                                  modifierFlags:0
                                      timestamp:0
                                   windowNumber:0
                                        context:nil
                                        subtype:0
                                          data1:0
                                          data2:0];

    [NSApp postEvent:wake atStart:NO];
}

static BOOL SpikeModalWindowIsUp(void)
{
    BOOL timedOut;
    id up = SpikeQuery(^id (void) {
        return [NSNumber numberWithBool:[NSApp modalWindow] != nil];
    }, 5, &timedOut);

    return !timedOut && [up boolValue];
}

@interface UIThreadSpikeTests : XCTestCase
@end

@implementation UIThreadSpikeTests

- (void) setUp
{
    XCTAssertFalse([NSThread isMainThread], @"expected UI tests to run on a test thread");
}

// An alert is opened by an action, queried and dismissed through the
// dispatch, and the opening action then completes.
- (void) testAModalAlertOpensAndIsDismissed
{
    SpikeHop *open = nil;
    SpikeActionState state = SpikeOpenAlert(@"Spike alert", &open);
    BOOL timedOut;
    NSString *title;
    SpikeHop *click = nil;

    NSLog(@"spike: opening the alert: %@", SpikeStateName(state));
    XCTAssertEqual(state, SpikeActionInNestedLoop, @"expected runModal to leave the action in a nested loop");
    XCTAssertTrue(SpikeModalWindowIsUp(), @"expected a modal window to be up");

    // A query serviced inside the modal loop.
    title = SpikeQuery(^id (void) {
        return [[[SpikeAlert buttons] objectAtIndex:0] title];
    }, 5, &timedOut);
    XCTAssertFalse(timedOut, @"expected the query to be serviced inside the modal loop");
    XCTAssertEqualObjects(title, @"OK");

    // Clicking OK is itself an action; it completes, and ends the modal loop.
    state = SpikeAction(^id (void) {
        [[[SpikeAlert buttons] objectAtIndex:0] performClick:nil];
        SpikeWakeModalLoop();
        return nil;
    }, 5, &click);
    NSLog(@"spike: clicking OK: %@", SpikeStateName(state));
    XCTAssertEqual(state, SpikeActionCompleted);

    XCTAssertTrue([open waitForStarted:YES timeout:5], @"expected the opening action to complete once OK was clicked");
    XCTAssertEqual(SpikeAlertResult, (NSInteger)NSAlertFirstButtonReturn);
    XCTAssertFalse(SpikeModalWindowIsUp(), @"expected no modal window after OK");
}

// A test that leaves an alert open: teardown finds it and ends it with
// abortModal, queued in the modal mode.
- (void) testBTeardownEndsAnAlertLeftOpen
{
    SpikeHop *open = nil;
    SpikeActionState state = SpikeOpenAlert(@"Left open", &open);
    BOOL timedOut;
    NSUInteger sessions = 0;

    XCTAssertEqual(state, SpikeActionInNestedLoop);

    // Teardown, as the runner would do it.
    while (SpikeModalWindowIsUp() && sessions < 3) {
        sessions++;
        SpikeQuery(^id (void) {
            [NSApp abortModal];
            SpikeWakeModalLoop();
            return nil;
        }, 5, &timedOut);
        XCTAssertFalse(timedOut, @"expected abortModal to be serviced inside the modal loop");
        [open waitForStarted:YES timeout:5];
    }
    NSLog(@"spike: teardown ended %lu modal session(s)", (unsigned long)sessions);
    XCTAssertEqual(sessions, (NSUInteger)1);
    XCTAssertTrue(open->finished, @"expected the opening action to complete after abortModal");
    XCTAssertEqual(SpikeAlertResult, (NSInteger)NSRunAbortedResponse);
    XCTAssertFalse(SpikeModalWindowIsUp());
}

// An expectation on the test thread, fulfilled from the main thread.
- (void) testCExpectationFulfilledOnTheMainThread
{
    XCTestExpectation *done = [self expectationWithDescription:@"fulfilled on the main thread"];
    BOOL timedOut;

    SpikeQuery(^id (void) {
        [done performSelector:@selector(fulfill) withObject:nil afterDelay:0.2];
        return nil;
    }, 5, &timedOut);
    XCTAssertFalse(timedOut);
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

// The failure path: an action that blocks the main thread outside any run
// loop is reported within its timeout instead of hanging the test. A
// later query, after it ends, works again.
- (void) testDBlockedMainThreadIsReported
{
    SpikeHop *busy = nil;
    SpikeActionState state = SpikeAction(^id (void) {
        sleep(3);
        return nil;
    }, 1, &busy);
    NSDate *start = [NSDate date];
    BOOL timedOut;

    NSLog(@"spike: a blocked main thread: %@", SpikeStateName(state));
    XCTAssertEqual(state, SpikeActionBlockedOutsideRunLoop);

    SpikeQuery(^id (void) { return nil; }, 0.5, &timedOut);
    XCTAssertTrue(timedOut, @"expected a query to time out while the main thread is blocked");

    XCTAssertTrue([busy waitForStarted:YES timeout:5], @"expected the blocking action to end");
    SpikeQuery(^id (void) { return nil; }, 5, &timedOut);
    XCTAssertFalse(timedOut, @"expected queries to work again once the main thread is free");
    NSLog(@"spike: recovered after %.1f s", -[start timeIntervalSinceNow]);
}

@end
