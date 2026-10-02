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
#import <XCTest/XCAbstractTest.h>

@class XCTestSuite;

/*!
 * One test: an instance of a test class bound to one test method (its
 * invocation). xctest builds a test case for each method returned by
 * +testInvocations, groups them with +defaultTestSuite, and runs them.
 */
@interface XCTestCase : XCTest {
    BOOL _continueAfterFailure;
    NSMutableArray *_teardownBlocks;
    NSMutableArray *_expectations;
    NSInvocation *_invocation;
}

+ (id) testCaseWithInvocation: (NSInvocation *)invocation;
- (id) initWithInvocation: (NSInvocation *)invocation;
+ (id) testCaseWithSelector: (SEL)selector;
- (id) initWithSelector: (SEL)selector;

/*! The test method to run. */
@property (retain) NSInvocation *invocation;

/*!
 * One invocation per test method: instance methods named test..., taking
 * no arguments, including inherited ones, sorted by name. Override to add
 * or remove tests.
 */
+ (NSArray *) testInvocations;

/*!
 * The tests to run for this class: by default a suite with a test case for
 * each of +testInvocations. Override to change it, e.g. return an empty
 * suite from an abstract base class so its tests only run in subclasses.
 */
+ (XCTestSuite *) defaultTestSuite;

/*!
 * Runs set up, the test method and teardown, recording any failures. Can
 * be overridden to wrap the whole test; call super.
 */
- (void) invokeTest;

/*!
 * Records a failure in the current test. The assertion macros call this,
 * so it can be overridden to observe or filter failures. With
 * continueAfterFailure NO, it stops the test (on the main thread).
 */
- (void) recordFailureWithDescription: (NSString *)description
                               inFile: (NSString *)filePath
                               atLine: (NSUInteger)lineNumber
                             expected: (BOOL)expected;

/*!
 * Whether a test keeps running after an assertion fails. Defaults to YES.
 * When NO, the first failure stops the current test; teardown still runs.
 */
@property BOOL continueAfterFailure;

/*!
 * Called once before the first test of the class runs, and once after the
 * last one finishes.
 */
+ (void) setUp;
+ (void) tearDown;

/*
 * The instance methods -setUpWithError:, -setUp, -tearDown and
 * -tearDownWithError: (declared by XCTest) are called around each test
 * method by -invokeTest, in the order setUpWithError:, setUp, the test,
 * teardown blocks (last added runs first), tearDown, tearDownWithError:.
 * Teardown always runs, even if set up or the test failed.
 */

/*!
 * Registers a block to run after the current test method, before tearDown.
 */
- (void) addTeardownBlock: (void (^)(void))block;

@end
