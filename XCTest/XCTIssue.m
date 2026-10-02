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

@implementation XCTIssue

- (id) initWithType: (XCTIssueType)type compactDescription: (NSString *)compactDescription
{
    return [self initWithType:type compactDescription:compactDescription detailedDescription:nil];
}

- (id) initWithType: (XCTIssueType)type
 compactDescription: (NSString *)compactDescription
detailedDescription: (NSString *)detailedDescription
{
    self = [super init];
    if (self) {
        _type = type;
        _compactDescription = [compactDescription copy];
        _detailedDescription = [detailedDescription copy];
    }

    return self;
}

- (void) dealloc
{
    [_compactDescription release];
    [_detailedDescription release];
    [super dealloc];
}

- (id) copyWithZone: (NSZone *)zone
{
    return [self retain];
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

- (NSString *) description
{
    return [self compactDescription];
}

@end
