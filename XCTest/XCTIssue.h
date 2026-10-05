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

@class XCTAttachment;

typedef enum {
    XCTIssueTypeAssertionFailure = 0,
    XCTIssueTypeThrownError = 1,
    XCTIssueTypeUncaughtException = 2,
    XCTIssueTypePerformanceRegression = 3,
    XCTIssueTypeSystem = 4,
    XCTIssueTypeUnmatchedExpectedFailure = 5,
} XCTIssueType;

/*! A file and line in the source code. */
@interface XCTSourceCodeLocation : NSObject {
    NSString *_filePath;
    NSInteger _lineNumber;
}

- (id) initWithFileURL: (NSURL *)fileURL lineNumber: (NSInteger)lineNumber;
- (id) initWithFilePath: (NSString *)filePath lineNumber: (NSInteger)lineNumber;

@property (readonly) NSURL *fileURL;
@property (readonly) NSInteger lineNumber;

@end

/*! Where an issue was recorded. (Call stacks are not captured.) */
@interface XCTSourceCodeContext : NSObject {
    XCTSourceCodeLocation *_location;
}

- (id) initWithLocation: (XCTSourceCodeLocation *)location;

/*! nil when the issue has no source location. */
@property (readonly) XCTSourceCodeLocation *location;

@end

/*!
 * A problem recorded during a test: a failed assertion, a thrown error, an
 * uncaught exception, a performance regression, and so on. Every failure
 * is recorded with -[XCTestCase recordIssue:].
 */
@interface XCTIssue : NSObject <NSCopying, NSMutableCopying> {
    XCTIssueType _type;
    NSString *_compactDescription;
    NSString *_detailedDescription;
    XCTSourceCodeContext *_sourceCodeContext;
    NSError *_associatedError;
    NSArray *_attachments;
}

- (id) initWithType: (XCTIssueType)type
 compactDescription: (NSString *)compactDescription
detailedDescription: (NSString *)detailedDescription
  sourceCodeContext: (XCTSourceCodeContext *)sourceCodeContext
    associatedError: (NSError *)associatedError
        attachments: (NSArray *)attachments;
- (id) initWithType: (XCTIssueType)type compactDescription: (NSString *)compactDescription;
- (id) initWithType: (XCTIssueType)type
 compactDescription: (NSString *)compactDescription
detailedDescription: (NSString *)detailedDescription;

@property (readonly) XCTIssueType type;
/*! A one-line description of the issue. */
@property (readonly, copy) NSString *compactDescription;
/*! A longer description; the compact description when there is none. */
@property (readonly, copy) NSString *detailedDescription;
@property (readonly, retain) XCTSourceCodeContext *sourceCodeContext;
/*! The error behind the issue, e.g. one returned by -setUpWithError:. */
@property (readonly, retain) NSError *associatedError;
/*! XCTAttachments kept with the test's results when the issue is recorded. */
@property (readonly, copy) NSArray *attachments;

@end

/*! An XCTIssue that can be changed, e.g. by an override of -recordIssue:. */
@interface XCTMutableIssue : XCTIssue

@property (readwrite) XCTIssueType type;
@property (readwrite, copy) NSString *compactDescription;
@property (readwrite, copy) NSString *detailedDescription;
@property (readwrite, retain) XCTSourceCodeContext *sourceCodeContext;
@property (readwrite, retain) NSError *associatedError;
@property (readwrite, copy) NSArray *attachments;

- (void) addAttachment: (XCTAttachment *)attachment;

@end
