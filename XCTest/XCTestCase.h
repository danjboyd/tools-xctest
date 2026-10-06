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
#import <XCTest/XCTestExpectation.h>

typedef BOOL (^XCPredicateExpectationHandler)(void);

@interface XCTestCase : NSObject
{
    NSInvocation *_invocation;
    BOOL _continueAfterFailure;
    NSUInteger _failureCount;
    NSMutableArray *_expectations;
    BOOL _waiting;
}

+ (void)setUp;
+ (void)tearDown;
+ (NSArray *)testInvocations;
+ (instancetype)testCaseWithSelector:(SEL)selector;
+ (instancetype)testCaseWithInvocation:(NSInvocation *)invocation;
- (instancetype)initWithSelector:(SEL)selector;
- (instancetype)initWithInvocation:(NSInvocation *)invocation;
@property (retain) NSInvocation *invocation;
@property BOOL continueAfterFailure;
@property (readonly, copy) NSString *name;
/* GNUstep extension: failures recorded during the most recent invocation. */
@property (readonly) NSUInteger failureCount;
- (void)setUp;
- (void)tearDown;
- (void)invokeTest;
- (XCTestExpectation *)expectationForPredicate:(NSPredicate *)predicate evaluatedWithObject:(id)object handler:(XCPredicateExpectationHandler)handler;
- (XCTestExpectation *)expectationWithDescription:(NSString *)description;
- (void)waitForExpectationsWithTimeout:(NSTimeInterval)timeout handler:(XCWaitCompletionHandler)handler;
- (void)waitForExpectations:(NSArray *)expectations timeout:(NSTimeInterval)timeout;
- (void)recordFailureWithDescription:(NSString *)description
                            inFile:(NSString *)filePath
                            atLine:(NSUInteger)lineNumber
                          expected:(BOOL)expected;
@end
