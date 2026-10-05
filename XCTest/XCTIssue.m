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

#import <XCTest/XCTIssue.h>
#import <XCTest/XCTestPrivate.h>

@implementation XCTSourceCodeLocation

- (id) initWithFileURL: (NSURL *)fileURL lineNumber: (NSInteger)lineNumber
{
    return [self initWithFilePath:[fileURL path] lineNumber:lineNumber];
}

- (id) initWithFilePath: (NSString *)filePath lineNumber: (NSInteger)lineNumber
{
    self = [super init];
    if (self) {
        _filePath = [filePath copy];
        _lineNumber = lineNumber;
    }

    return self;
}

- (void) dealloc
{
    [_filePath release];
    [super dealloc];
}

- (NSURL *) fileURL
{
    return _filePath ? [NSURL fileURLWithPath:_filePath] : nil;
}

- (NSInteger) lineNumber
{
    return _lineNumber;
}

// The path as given (e.g. __FILE__), which fileURL would make absolute.
- (NSString *) _gsFilePath
{
    return _filePath;
}

- (NSString *) description
{
    return [NSString stringWithFormat:@"%@:%ld", _filePath, (long)_lineNumber];
}

@end

@implementation XCTSourceCodeContext

- (id) init
{
    return [self initWithLocation:nil];
}

- (id) initWithLocation: (XCTSourceCodeLocation *)location
{
    self = [super init];
    if (self) {
        _location = [location retain];
    }

    return self;
}

- (void) dealloc
{
    [_location release];
    [super dealloc];
}

- (XCTSourceCodeLocation *) location
{
    return _location;
}

@end

@implementation XCTIssue

- (id) initWithType: (XCTIssueType)type
 compactDescription: (NSString *)compactDescription
detailedDescription: (NSString *)detailedDescription
  sourceCodeContext: (XCTSourceCodeContext *)sourceCodeContext
    associatedError: (NSError *)associatedError
        attachments: (NSArray *)attachments
{
    self = [super init];
    if (self) {
        _type = type;
        _compactDescription = [compactDescription copy];
        _detailedDescription = [detailedDescription copy];
        _sourceCodeContext = sourceCodeContext ? [sourceCodeContext retain] : [[XCTSourceCodeContext alloc] init];
        _associatedError = [associatedError retain];
        _attachments = [(attachments ? attachments : [NSArray array]) copy];
    }

    return self;
}

- (id) initWithType: (XCTIssueType)type compactDescription: (NSString *)compactDescription
{
    return [self initWithType:type compactDescription:compactDescription detailedDescription:nil];
}

- (id) initWithType: (XCTIssueType)type
 compactDescription: (NSString *)compactDescription
detailedDescription: (NSString *)detailedDescription
{
    return [self initWithType:type
           compactDescription:compactDescription
          detailedDescription:detailedDescription
            sourceCodeContext:nil
              associatedError:nil
                  attachments:nil];
}

- (void) dealloc
{
    [_compactDescription release];
    [_detailedDescription release];
    [_sourceCodeContext release];
    [_associatedError release];
    [_attachments release];
    [super dealloc];
}

- (id) _gsCopyAsClass: (Class)cls zone: (NSZone *)zone
{
    return [[cls allocWithZone:zone] initWithType:_type
                               compactDescription:_compactDescription
                              detailedDescription:_detailedDescription
                                sourceCodeContext:_sourceCodeContext
                                  associatedError:_associatedError
                                      attachments:_attachments];
}

- (id) copyWithZone: (NSZone *)zone
{
    return [self retain];
}

- (id) mutableCopyWithZone: (NSZone *)zone
{
    return [self _gsCopyAsClass:[XCTMutableIssue class] zone:zone];
}

- (XCTIssueType) type
{
    return _type;
}

- (NSString *) compactDescription
{
    return _compactDescription;
}

- (NSString *) detailedDescription
{
    return _detailedDescription ? _detailedDescription : _compactDescription;
}

- (XCTSourceCodeContext *) sourceCodeContext
{
    return _sourceCodeContext;
}

- (NSError *) associatedError
{
    return _associatedError;
}

- (NSArray *) attachments
{
    return _attachments;
}

- (NSString *) description
{
    return [self compactDescription];
}

@end

@implementation XCTMutableIssue

@dynamic type;
@dynamic compactDescription;
@dynamic detailedDescription;
@dynamic sourceCodeContext;
@dynamic associatedError;
@dynamic attachments;

- (id) copyWithZone: (NSZone *)zone
{
    return [self _gsCopyAsClass:[XCTIssue class] zone:zone];
}

- (void) setType: (XCTIssueType)type
{
    _type = type;
}

- (void) setCompactDescription: (NSString *)compactDescription
{
    NSString *old = _compactDescription;

    _compactDescription = [compactDescription copy];
    [old release];
}

- (void) setDetailedDescription: (NSString *)detailedDescription
{
    NSString *old = _detailedDescription;

    _detailedDescription = [detailedDescription copy];
    [old release];
}

- (void) setSourceCodeContext: (XCTSourceCodeContext *)sourceCodeContext
{
    XCTSourceCodeContext *old = _sourceCodeContext;

    _sourceCodeContext = sourceCodeContext ? [sourceCodeContext retain] : [[XCTSourceCodeContext alloc] init];
    [old release];
}

- (void) setAttachments: (NSArray *)attachments
{
    NSArray *old = _attachments;

    _attachments = [(attachments ? attachments : [NSArray array]) copy];
    [old release];
}

- (void) addAttachment: (XCTAttachment *)attachment
{
    if (attachment != nil) {
        [self setAttachments:[_attachments arrayByAddingObject:attachment]];
    }
}

- (void) setAssociatedError: (NSError *)associatedError
{
    NSError *old = _associatedError;

    _associatedError = [associatedError retain];
    [old release];
}

@end

XCTIssue *_GSXCTMakeIssue(XCTIssueType type, NSString *description,
                          NSString *filePath, NSUInteger lineNumber, NSError *error)
{
    XCTSourceCodeLocation *location = filePath
        ? [[[XCTSourceCodeLocation alloc] initWithFilePath:filePath lineNumber:lineNumber] autorelease]
        : nil;
    XCTSourceCodeContext *context = [[[XCTSourceCodeContext alloc] initWithLocation:location] autorelease];

    return [[[XCTIssue alloc] initWithType:type
                        compactDescription:description
                       detailedDescription:nil
                         sourceCodeContext:context
                           associatedError:error
                               attachments:nil] autorelease];
}

NSString *_GSXCTIssueFilePath(XCTIssue *issue)
{
    return [[[issue sourceCodeContext] location] _gsFilePath];
}

NSUInteger _GSXCTIssueLineNumber(XCTIssue *issue)
{
    XCTSourceCodeLocation *location = [[issue sourceCodeContext] location];

    return location ? (NSUInteger)[location lineNumber] : 0;
}

BOOL _GSXCTIssueIsUnexpected(XCTIssue *issue)
{
    return [issue type] == XCTIssueTypeUncaughtException;
}
