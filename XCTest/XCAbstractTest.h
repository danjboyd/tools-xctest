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

@class XCTestRun;

/*!
 * The abstract base of tests: XCTestCase (one test method) and XCTestSuite
 * (a collection of tests). -runTest creates a run of -testRunClass and
 * passes it to -performTest:.
 */
@interface XCTest : NSObject {
    XCTestRun *_testRun;
}

/*! The number of test cases this test contains (1 for a test case). */
@property (readonly) NSUInteger testCaseCount;

@property (readonly, copy) NSString *name;

/*! The XCTestRun subclass used to record this test's results. */
@property (readonly) Class testRunClass;

/*! The run from the last -runTest, or nil before the test has run. */
@property (readonly, retain) XCTestRun *testRun;

/*! Runs the test, recording results in \a run. */
- (void) performTest: (XCTestRun *)run;

/*! Creates a run of testRunClass and performs the test with it. */
- (void) runTest;

- (BOOL) setUpWithError: (NSError **)error;
- (void) setUp;
- (void) tearDown;
- (BOOL) tearDownWithError: (NSError **)error;

@end
