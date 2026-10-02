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

// Internal interfaces shared between the XCTest library's source files.
// Not installed.

#import <XCTest/XCTestCase.h>
#import <XCTest/XCTestExpectation.h>
#import <XCTest/XCTWaiter.h>

// Records a failure that has no source location (e.g. a failed wait),
// honouring continueAfterFailure like the assertion macros do.
void _XCTRecordFailure(XCTestCase *test, NSString *description);

@interface XCTestCase (GSXCTestRunnerPrivate)
// The test case currently being run, or nil.
+ (XCTestCase *) _gsCurrentTestCase;
+ (void) _gsSetCurrentTestCase: (XCTestCase *)testCase;
- (void (^)(void)) _gsPopTeardownBlock;
@end

@interface XCTestCase (GSAsynchronousTestingPrivate)
// Fails the test for each expectation it created but never waited on.
- (void) _gsRecordUnwaitedExpectations;
// Stops observers and releases the test's expectations.
- (void) _gsInvalidateExpectations;
@end

@interface XCTWaiter (GSPrivate)
// The timeout of the most recent wait.
- (NSTimeInterval) _gsTimeout;
@end

@interface XCTestExpectation (GSPrivate)
- (BOOL) _gsIsFulfilled;
// Increases each time any expectation becomes fulfilled; 0 if unfulfilled.
- (NSUInteger) _gsFulfillmentToken;
- (BOOL) _gsHasBeenWaitedOn;
- (void) _gsSetHasBeenWaitedOn: (BOOL)waited;
// Called repeatedly while a waiter waits, e.g. to re-evaluate predicates.
- (void) _gsPoll;
// Stops observing and drops handlers.
- (void) _gsInvalidate;
@end
