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

#import <XCTest/XCTestCase.h>

@interface XCTestCase (GSXCTestRunnerPrivate)
- (void (^)(void)) _gsPopTeardownBlock;
@end

@implementation XCTestCase

@synthesize continueAfterFailure = _continueAfterFailure;

+ (void) setUp
{
}

+ (void) tearDown
{
}

- (id) init
{
    self = [super init];
    if (self) {
        _continueAfterFailure = YES;
    }

    return self;
}

- (void) dealloc
{
    [_teardownBlocks release];
    [super dealloc];
}

- (BOOL) setUpWithError: (NSError **)error
{
    return YES;
}

- (void) setUp
{
    
}

- (void) tearDown
{
    
}

- (BOOL) tearDownWithError: (NSError **)error
{
    return YES;
}

- (void) addTeardownBlock: (void (^)(void))block
{
    if (block == nil) {
        return;
    }

    @synchronized (self) {
        if (_teardownBlocks == nil) {
            _teardownBlocks = [[NSMutableArray alloc] init];
        }
        void (^copiedBlock)(void) = [block copy];
        [_teardownBlocks addObject:copiedBlock];
        [copiedBlock release];
    }
}

@end

@implementation XCTestCase (GSXCTestRunnerPrivate)

- (void (^)(void)) _gsPopTeardownBlock
{
    void (^block)(void) = nil;

    @synchronized (self) {
        block = [[[_teardownBlocks lastObject] retain] autorelease];
        if (block != nil) {
            [_teardownBlocks removeLastObject];
        }
    }

    return block;
}

@end
