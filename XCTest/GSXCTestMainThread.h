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

#ifndef GSXCTestMainThread_h
#define GSXCTestMainThread_h

// A GNUstep extension (not in Apple's XCTest): running work on a host
// application's main thread from tests that run on a test thread.
//
// In a run with `xctest -host`, a test class whose +runsOnUITestThread
// returns YES runs on a separate test thread, while the main thread keeps
// running the application. Other classes still run on the main thread, in
// their usual order. Tests on the test thread reach the application only
// through this class: queries and actions are blocks run on the main
// thread, in the default, modal-panel and event-tracking run-loop modes,
// so they are also serviced while a modal window is up.
//
// Outside that mode (no -host, or no class opts in), or when called on the
// main thread, blocks simply run on the calling thread.
//
// Not supported yet: sheets, menu tracking, typing, and modal sessions
// nested more than three deep. See issue #26.

#import <Foundation/Foundation.h>
#import <XCTest/XCTestCase.h>

/// What an action was doing when it was dispatched.
typedef NS_ENUM(NSInteger, GSXCTestMainThreadActionState) {
    /// The block returned.
    GSXCTestMainThreadActionCompleted = 0,
    /// The block is still running a nested run loop (a modal session, or a
    /// short loop such as a button's highlight). The main thread services
    /// further queries and actions; the block finishes later.
    GSXCTestMainThreadActionInNestedLoop,
    /// The main thread didn't start the block within the timeout, and it
    /// was cancelled: it will never run.
    GSXCTestMainThreadActionNotStarted,
    /// The block started but the main thread isn't servicing its run loop
    /// (it's busy, or waiting outside a run loop). The block may finish
    /// later.
    GSXCTestMainThreadActionBlocked,
};

/// An action dispatched to the main thread.
@interface GSXCTestMainThreadAction : NSObject
/// The state when it was dispatched.
- (GSXCTestMainThreadActionState) state;
/// Whether the block has returned (or raised).
- (BOOL) isFinished;
/// Waits up to \a timeout seconds for the block to return; returns whether
/// it did.
- (BOOL) waitUntilFinishedWithTimeout: (NSTimeInterval)timeout;
/// What the block returned, once it has finished.
- (id) result;
/// The exception the block raised, if any, once it has finished.
- (NSException *) exception;
@end

@interface GSXCTestMainThread : NSObject

/// Whether opted-in test classes are running on a test thread.
+ (BOOL) isTestThreadActive;

/// The timeout used when none is given. Defaults to 10 seconds.
+ (NSTimeInterval) defaultTimeout;
+ (void) setDefaultTimeout: (NSTimeInterval)timeout;

/// Runs \a block on the main thread and returns its result, waiting up to
/// \a timeout seconds. If it didn't run in time, it's cancelled, nil is
/// returned and \a timedOut (if given) is set to YES. An exception the
/// block raises is raised again on the calling thread.
+ (id) performQuery: (id (^)(void))block
            timeout: (NSTimeInterval)timeout
           timedOut: (BOOL *)timedOut;

/// Dispatches \a block to the main thread without waiting for it to return,
/// then reports whether it completed or is running a nested loop (see
/// GSXCTestMainThreadActionState), waiting up to \a timeout seconds to find
/// out. Wakes a modal loop afterwards, so a stopModal or abortModal the
/// block calls takes effect.
/// An exception the block raises is kept (-exception) and fails the test
/// when it ends.
///
/// An action still running when its test ends fails the test. Before the
/// test ends, modal sessions are ended (abortModal, up to three) and the
/// test's actions are waited for. If the main thread doesn't respond, the
/// application is treated as stopped: later tests on the test thread fail
/// without running, and the run ends once results are written.
+ (GSXCTestMainThreadAction *) performAction: (id (^)(void))block
                                     timeout: (NSTimeInterval)timeout;

/// Waits up to \a timeout seconds for every action dispatched by the
/// current test to finish; returns whether they did.
+ (BOOL) waitForIdleWithTimeout: (NSTimeInterval)timeout;

@end

@interface XCTestCase (GSXCTestMainThread)
/// YES to run this class's tests on the test thread when hosted (see
/// above). Defaults to NO. Subclasses inherit the answer.
+ (BOOL) runsOnUITestThread;
@end

#endif
