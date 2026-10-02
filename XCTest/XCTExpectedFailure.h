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

#import <Foundation/Foundation.h>
#import <XCTest/XCTIssue.h>

/*! Options for XCTExpectFailureWithOptions and friends. */
@interface XCTExpectedFailureOptions : NSObject {
    BOOL (^_issueMatcher)(XCTIssue *issue);
    BOOL _enabled;
    BOOL _strict;
}

/*! Options with strict set to NO. */
+ (id) nonStrictOptions;

/*! Which issues are expected; nil (the default) matches any issue. */
@property (copy) BOOL (^issueMatcher)(XCTIssue *issue);

/*! If NO, failures are not expected. Defaults to YES. */
@property (getter=isEnabled) BOOL enabled;

/*! If YES (the default), the test fails when no failure was expected. */
@property (getter=isStrict) BOOL strict;

@end

/*!
 * Marks failures recorded from here until the end of the current test as
 * expected: they are reported but don't fail the test. Strictly, the test
 * fails if no failure happens. Call it on the thread running the test.
 */
void XCTExpectFailure(NSString *failureReason);
void XCTExpectFailureWithOptions(NSString *failureReason, XCTExpectedFailureOptions *options);

/*! As XCTExpectFailure, but only for failures recorded inside the block. */
void XCTExpectFailureInBlock(NSString *failureReason, void (^failingBlock)(void));
void XCTExpectFailureWithOptionsInBlock(NSString *failureReason, XCTExpectedFailureOptions *options,
                                        void (^failingBlock)(void));
