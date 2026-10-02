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

typedef enum {
    XCTIssueTypeAssertionFailure = 0,
    XCTIssueTypeThrownError = 1,
    XCTIssueTypeUncaughtException = 2,
    XCTIssueTypePerformanceRegression = 3,
    XCTIssueTypeSystem = 4,
    XCTIssueTypeUnmatchedExpectedFailure = 5,
} XCTIssueType;

/*!
 * A problem recorded during a test. Passed to the issueMatcher of
 * XCTExpectedFailureOptions. (A subset of Apple's XCTIssue.)
 */
@interface XCTIssue : NSObject <NSCopying> {
    XCTIssueType _type;
    NSString *_compactDescription;
    NSString *_detailedDescription;
}

- (id) initWithType: (XCTIssueType)type compactDescription: (NSString *)compactDescription;
- (id) initWithType: (XCTIssueType)type
 compactDescription: (NSString *)compactDescription
detailedDescription: (NSString *)detailedDescription;

@property (readonly) XCTIssueType type;
@property (readonly, copy) NSString *compactDescription;
@property (readonly, copy) NSString *detailedDescription;

@end
