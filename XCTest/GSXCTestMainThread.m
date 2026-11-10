/*
 This file is part of the GNUstep XCTEST Library.

 This library is free software; you can redistribute it and/or
 modify it under the terms of the GNU Lesser General Public
 License as published by the Free Software Foundation; either
 version 2 of the License, or (at your option) any later version.

 This library is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.     See the GNU
 Lesser General Public License for more details.

 You should have received a copy of the GNU Lesser General Public
 License along with this library; see the file COPYING.LIB.
 If not, see <http://www.gnu.org/licenses/> or write to the
 Free Software Foundation, 51 Franklin Street, Fifth Floor,
 Boston, MA 02110-1301, USA.
*/

// The test thread for hosted UI tests, and dispatch to the main thread.
// The design is in issue #26 ("Threading and dispatch").
//
// libXCTest doesn't link AppKit: the few AppKit calls made here (the modal
// window, abortModal, posting a wake event) go through the runtime, on the
// main thread, and only when an NSApplication exists.

#import <XCTest/GSXCTestMainThread.h>
#import <XCTest/XCTestPrivate.h>

#include <objc/runtime.h>
#include <stdlib.h>

// NSEventTypeApplicationDefined in AppKit.
#define GSXCT_APPLICATION_DEFINED_EVENT 15
// How many nested modal sessions teardown ends at most.
#define GSXCT_MAX_MODAL_SESSIONS 3

static BOOL GSTestThreadActive = NO;
static BOOL GSWedged = NO;
static NSTimeInterval GSDefaultTimeout = 10;
// Actions dispatched by the current test, for teardown. Guarded by itself.
static NSMutableArray *GSActions = nil;

@interface GSXCTestMainThreadAction ()
{
@public
    id (^_block)(void);
    NSCondition *_condition;
    BOOL _started;
    BOOL _finished;
    BOOL _cancelled;
    BOOL _wakeModalLoop;
    BOOL _exceptionReported;
    id _result;
    NSException *_exception;
    GSXCTestMainThreadActionState _state;
}
- (id) _gsInitWithBlock: (id (^)(void))block;
@end

static NSArray *GSModes(void)
{
    static NSArray *modes = nil;

    if (modes == nil) {
        modes = [[NSArray alloc] initWithObjects:NSDefaultRunLoopMode,
                                 @"NSModalPanelRunLoopMode", @"NSEventTrackingRunLoopMode", nil];
    }
    return modes;
}

// The application object, if this process has one. Main thread only.
static id GSApplication(void)
{
    Class applicationClass = NSClassFromString(@"NSApplication");

    if (applicationClass == Nil || ![applicationClass respondsToSelector:@selector(sharedApplication)]) {
        return nil;
    }
    return [applicationClass performSelector:@selector(sharedApplication)];
}

// Main thread only.
static BOOL GSModalWindowIsUp(void)
{
    id application = GSApplication();

    return application != nil && [application respondsToSelector:@selector(modalWindow)]
        && [application performSelector:@selector(modalWindow)] != nil;
}

// GNUstep's modal loop notices stopModal and abortModal only on its next
// event, and a programmatic click or abortModal brings none: post one.
// Main thread only.
static void GSWakeModalLoop(void)
{
    Class eventClass = NSClassFromString(@"NSEvent");
    id application = GSApplication();
    SEL make = @selector(otherEventWithType:location:modifierFlags:timestamp:windowNumber:context:subtype:data1:data2:);
    id (*makeEvent)(id, SEL, NSUInteger, NSPoint, NSUInteger, NSTimeInterval, NSInteger, id, short, NSInteger, NSInteger);
    void (*postEvent)(id, SEL, id, BOOL);
    id event;

    if (eventClass == Nil || application == nil || ![eventClass respondsToSelector:make]
        || ![application respondsToSelector:@selector(postEvent:atStart:)]) {
        return;
    }
    makeEvent = (id (*)(id, SEL, NSUInteger, NSPoint, NSUInteger, NSTimeInterval, NSInteger, id, short, NSInteger, NSInteger))
        [eventClass methodForSelector:make];
    postEvent = (void (*)(id, SEL, id, BOOL))[application methodForSelector:@selector(postEvent:atStart:)];
    event = makeEvent(eventClass, make, GSXCT_APPLICATION_DEFINED_EVENT, NSMakePoint(0, 0), 0, 0, 0, nil, 0, 0, 0);
    if (event != nil) {
        postEvent(application, @selector(postEvent:atStart:), event, NO);
    }
}

@implementation GSXCTestMainThreadAction

- (id) _gsInitWithBlock: (id (^)(void))block
{
    if ((self = [super init]) != nil) {
        _block = [block copy];
        _condition = [[NSCondition alloc] init];
    }
    return self;
}

- (void) dealloc
{
    [_block release];
    [_condition release];
    [_result release];
    [_exception release];
    [super dealloc];
}

// On the main thread.
- (void) _gsRun
{
    id value = nil;
    NSException *caught = nil;

    [_condition lock];
    if (_cancelled) {
        [_condition unlock];
        return;
    }
    _started = YES;
    [_condition broadcast];
    [_condition unlock];

    @autoreleasepool {
        @try {
            value = [_block() retain];
        }
        @catch (NSException *exception) {
            caught = [exception retain];
        }
        if (_wakeModalLoop && GSModalWindowIsUp()) {
            GSWakeModalLoop();
        }
    }

    [_condition lock];
    _finished = YES;
    _result = value;
    _exception = caught;
    [_condition broadcast];
    [_condition unlock];
}

- (void) _gsQueue
{
    [self performSelectorOnMainThread:@selector(_gsRun) withObject:nil waitUntilDone:NO modes:GSModes()];
}

// Waits until started (or, with \a finished, finished); returns whether
// that happened within the timeout.
- (BOOL) _gsWaitUntilStarted: (BOOL)finished timeout: (NSTimeInterval)timeout
{
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:timeout];
    BOOL done;

    [_condition lock];
    while (!(done = finished ? _finished : _started)) {
        if (![_condition waitUntilDate:limit]) {
            done = finished ? _finished : _started;
            break;
        }
    }
    [_condition unlock];
    return done;
}

// Cancels the block if it hasn't started; returns whether it had.
- (BOOL) _gsCancelUnlessStarted
{
    BOOL started;

    [_condition lock];
    started = _started;
    if (!started) {
        _cancelled = YES;
    }
    [_condition unlock];
    return started;
}

- (GSXCTestMainThreadActionState) state
{
    return _state;
}

- (BOOL) isFinished
{
    BOOL finished;

    [_condition lock];
    finished = _finished;
    [_condition unlock];
    return finished;
}

- (BOOL) waitUntilFinishedWithTimeout: (NSTimeInterval)timeout
{
    return [self _gsWaitUntilStarted:YES timeout:timeout];
}

- (id) result
{
    id result;

    [_condition lock];
    result = [[_result retain] autorelease];
    [_condition unlock];
    return result;
}

- (NSException *) exception
{
    NSException *exception;

    [_condition lock];
    exception = [[_exception retain] autorelease];
    [_condition unlock];
    return exception;
}

@end

@implementation GSXCTestMainThread

+ (void) initialize
{
    if (self == [GSXCTestMainThread class] && GSActions == nil) {
        GSActions = [[NSMutableArray alloc] init];
    }
}

+ (BOOL) isTestThreadActive
{
    return GSTestThreadActive;
}

+ (NSTimeInterval) defaultTimeout
{
    return GSDefaultTimeout;
}

+ (void) setDefaultTimeout: (NSTimeInterval)timeout
{
    GSDefaultTimeout = timeout > 0 ? timeout : 10;
}

+ (id) performQuery: (id (^)(void))block
            timeout: (NSTimeInterval)timeout
           timedOut: (BOOL *)timedOut
{
    GSXCTestMainThreadAction *query;

    if (timedOut != NULL) {
        *timedOut = NO;
    }
    if ([NSThread isMainThread]) {
        return block();
    }

    query = [[[GSXCTestMainThreadAction alloc] _gsInitWithBlock:block] autorelease];
    [query _gsQueue];
    if (![query _gsWaitUntilStarted:YES timeout:timeout]) {
        [query _gsCancelUnlessStarted];
        if (timedOut != NULL) {
            *timedOut = YES;
        }
        return nil;
    }
    if ([query exception] != nil) {
        [[query exception] raise];
    }
    return [query result];
}

+ (GSXCTestMainThreadAction *) performAction: (id (^)(void))block
                                     timeout: (NSTimeInterval)timeout
{
    GSXCTestMainThreadAction *action = [[[GSXCTestMainThreadAction alloc] _gsInitWithBlock:block] autorelease];
    GSXCTestMainThreadAction *probe;

    action->_wakeModalLoop = YES;
    if ([NSThread isMainThread]) {
        [action _gsRun];
        action->_state = GSXCTestMainThreadActionCompleted;
        return action;
    }

    @synchronized (GSActions) {
        [GSActions addObject:action];
    }
    [action _gsQueue];
    if (![action _gsWaitUntilStarted:NO timeout:timeout] && ![action _gsCancelUnlessStarted]) {
        // Cancelled: it will never run, so nothing waits for it.
        @synchronized (GSActions) {
            [GSActions removeObjectIdenticalTo:action];
        }
        action->_state = GSXCTestMainThreadActionNotStarted;
        return action;
    }

    // Queued only now that the action has started: the main thread may take
    // queued blocks in a batch, and a probe in the action's batch wouldn't
    // run until the action returned. Queued now, it runs either after the
    // action returns or inside the nested loop the action is running.
    probe = [[[GSXCTestMainThreadAction alloc] _gsInitWithBlock:^id (void) {
        return [NSNumber numberWithBool:[action isFinished]];
    }] autorelease];
    [probe _gsQueue];
    if (![probe _gsWaitUntilStarted:YES timeout:timeout]) {
        [probe _gsCancelUnlessStarted];
        action->_state = [action isFinished] ? GSXCTestMainThreadActionCompleted
                                             : GSXCTestMainThreadActionBlocked;
        return action;
    }
    action->_state = [[probe result] boolValue] ? GSXCTestMainThreadActionCompleted
                                                : GSXCTestMainThreadActionInNestedLoop;
    return action;
}

+ (BOOL) waitForIdleWithTimeout: (NSTimeInterval)timeout
{
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:timeout];
    NSArray *actions;

    @synchronized (GSActions) {
        actions = [[GSActions copy] autorelease];
    }
    for (GSXCTestMainThreadAction *action in actions) {
        if (![action waitUntilFinishedWithTimeout:MAX([limit timeIntervalSinceNow], 0)]) {
            return NO;
        }
    }
    return YES;
}

@end

@implementation XCTestCase (GSXCTestMainThread)

+ (BOOL) runsOnUITestThread
{
    return NO;
}

@end

void _GSXCTMainThreadSetTestThreadActive(BOOL active)
{
    GSTestThreadActive = active;
}

BOOL _GSXCTMainThreadIsWedged(void)
{
    return GSWedged;
}

BOOL _GSXCTClassRunsOnTestThread(Class testCaseClass)
{
    return GSTestThreadActive && [testCaseClass respondsToSelector:@selector(runsOnUITestThread)]
        && [testCaseClass runsOnUITestThread];
}

BOOL _GSXCTAnyTestClassRunsOnTestThread(void)
{
    Class testCaseClass = [XCTestCase class];
    int count = objc_getClassList(NULL, 0);
    Class *classes;
    BOOL found = NO;

    if (count <= 0) {
        return NO;
    }
    classes = malloc(sizeof(Class) * count);
    count = objc_getClassList(classes, count);
    for (int i = 0; i < count && !found; i++) {
        Class superclass = classes[i];

        while (superclass != Nil && superclass != testCaseClass) {
            superclass = class_getSuperclass(superclass);
        }
        if (superclass == testCaseClass && classes[i] != testCaseClass
            && [classes[i] runsOnUITestThread]) {
            found = YES;
        }
    }
    free(classes);
    return found;
}

// Records a failure without letting continueAfterFailure = NO interrupt
// the caller.
static void GSRecordFailure(XCTestCase *testCase, NSString *description)
{
    @try {
        [testCase recordFailureWithDescription:description inFile:nil atLine:0 expected:NO];
    }
    @catch (NSException *exception) {
    }
}

static void GSBecomeWedged(XCTestCase *testCase, NSString *during)
{
    GSWedged = YES;
    GSRecordFailure(testCase, [NSString stringWithFormat:
        @"the application stopped responding %@ (its main thread didn't answer within %g s); "
        @"later tests on the UI test thread won't run", during, GSDefaultTimeout]);
}

// After an opted-in test, on the test thread: fail it if it left actions
// running or a modal session up, then end those, so the next test starts
// clean. If the main thread doesn't answer, the application is wedged.
void _GSXCTMainThreadTestDidFinish(XCTestCase *testCase)
{
    NSArray *actions;
    NSUInteger running = 0;
    NSUInteger sessions = 0;
    BOOL modalUp = NO;
    BOOL timedOut = NO;

    if (!GSTestThreadActive || GSWedged || [NSThread isMainThread]) {
        return;
    }

    @synchronized (GSActions) {
        actions = [[GSActions copy] autorelease];
        [GSActions removeAllObjects];
    }
    for (GSXCTestMainThreadAction *action in actions) {
        if (![action isFinished]) {
            running++;
        }
    }

    modalUp = [[GSXCTestMainThread performQuery:^id (void) {
        return [NSNumber numberWithBool:GSModalWindowIsUp()];
    } timeout:GSDefaultTimeout timedOut:&timedOut] boolValue];
    if (timedOut) {
        GSBecomeWedged(testCase, @"after the test");
        return;
    }
    if (running > 0 || modalUp) {
        GSRecordFailure(testCase, [NSString stringWithFormat:
            @"the test ended with %lu action(s) still running%@; they were ended",
            (unsigned long)running, modalUp ? @" and a modal session open" : @""]);
    }

    while (modalUp && sessions < GSXCT_MAX_MODAL_SESSIONS) {
        sessions++;
        [GSXCTestMainThread performQuery:^id (void) {
            id application = GSApplication();

            if ([application respondsToSelector:@selector(abortModal)]) {
                [application performSelector:@selector(abortModal)];
            }
            GSWakeModalLoop();
            return nil;
        } timeout:GSDefaultTimeout timedOut:&timedOut];
        if (!timedOut) {
            // Let the aborted session unwind before looking again.
            [GSXCTestMainThread performQuery:^id (void) { return nil; }
                                     timeout:GSDefaultTimeout timedOut:&timedOut];
        }
        if (!timedOut) {
            modalUp = [[GSXCTestMainThread performQuery:^id (void) {
                return [NSNumber numberWithBool:GSModalWindowIsUp()];
            } timeout:GSDefaultTimeout timedOut:&timedOut] boolValue];
        }
        if (timedOut) {
            GSBecomeWedged(testCase, @"while ending a modal session after the test");
            return;
        }
    }
    if (modalUp) {
        GSRecordFailure(testCase, [NSString stringWithFormat:
            @"a modal session was still open after ending %d; the application may be left modal",
            GSXCT_MAX_MODAL_SESSIONS]);
    }

    for (GSXCTestMainThreadAction *action in actions) {
        if (![action waitUntilFinishedWithTimeout:GSDefaultTimeout]) {
            GSBecomeWedged(testCase, @"while waiting for the test's actions to finish");
            return;
        }
        if ([action exception] != nil && !action->_exceptionReported) {
            action->_exceptionReported = YES;
            GSRecordFailure(testCase, [NSString stringWithFormat:@"an action on the main thread threw %@",
                                          _GSXCTDescribeException([action exception])]);
        }
    }
}
