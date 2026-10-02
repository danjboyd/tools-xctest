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

@interface XCTestCase : NSObject {
    BOOL _continueAfterFailure;
    NSMutableArray *_teardownBlocks;
}

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

/*!
 * Called before and after each test method. The order is setUpWithError:,
 * setUp, the test, teardown blocks (last added runs first), tearDown,
 * tearDownWithError:. Teardown always runs, even if set up or the test
 * failed.
 */
- (BOOL) setUpWithError: (NSError **)error;
- (void) setUp;
- (void) tearDown;
- (BOOL) tearDownWithError: (NSError **)error;

/*!
 * Registers a block to run after the current test method, before tearDown.
 */
- (void) addTeardownBlock: (void (^)(void))block;

@end
