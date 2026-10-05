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

@class XCTestSuite;
@class XCTestCase;
@class XCTIssue;

/*!
 * Observers registered with XCTestObservationCenter receive these as tests
 * run. A test bundle can register observers from the -init of its
 * principal class (NSPrincipalClass in its Info.plist), which xctest
 * creates before running any tests.
 */
@protocol XCTestObservation <NSObject>
@optional
- (void) testBundleWillStart: (NSBundle *)testBundle;
- (void) testBundleDidFinish: (NSBundle *)testBundle;
- (void) testSuiteWillStart: (XCTestSuite *)testSuite;
/*! An issue recorded on the suite itself, e.g. in a class's +setUp. */
- (void) testSuite: (XCTestSuite *)testSuite didRecordIssue: (XCTIssue *)issue;
/*! Superseded by testSuite:didRecordIssue:; both are sent. */
- (void) testSuite: (XCTestSuite *)testSuite
didFailWithDescription: (NSString *)description
            inFile: (NSString *)filePath
            atLine: (NSUInteger)lineNumber;
- (void) testSuiteDidFinish: (XCTestSuite *)testSuite;
- (void) testCaseWillStart: (XCTestCase *)testCase;
/*! An issue that fails the test (not one absorbed by XCTExpectFailure). */
- (void) testCase: (XCTestCase *)testCase didRecordIssue: (XCTIssue *)issue;
/*! Superseded by testCase:didRecordIssue:; both are sent. */
- (void) testCase: (XCTestCase *)testCase
didFailWithDescription: (NSString *)description
           inFile: (NSString *)filePath
           atLine: (NSUInteger)lineNumber;
- (void) testCaseDidFinish: (XCTestCase *)testCase;
@end
