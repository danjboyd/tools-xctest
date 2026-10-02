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

#import <XCTest/XCAbstractTest.h>

/*!
 * A collection of tests run in order. +[XCTestCase defaultTestSuite]
 * returns a suite for one test class; running it calls the class's
 * +setUp and +tearDown around its tests.
 */
@interface XCTestSuite : XCTest {
    NSString *_name;
    NSMutableArray *_tests;
}

/*! A suite of every XCTestCase subclass's default test suite. */
+ (id) defaultTestSuite;

/*! The tests of the XCTestCase subclasses defined in a bundle. */
+ (id) testSuiteForBundlePath: (NSString *)bundlePath;

/*! "TestClass" or "TestClass/testMethod". */
+ (id) testSuiteForTestCaseWithName: (NSString *)name;

+ (id) testSuiteForTestCaseClass: (Class)testCaseClass;

+ (id) testSuiteWithName: (NSString *)name;
- (id) initWithName: (NSString *)name;

- (void) addTest: (XCTest *)test;

@property (readonly, copy) NSArray *tests;

@end
