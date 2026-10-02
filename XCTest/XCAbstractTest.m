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
#import <XCTest/XCTestPrivate.h>

@implementation XCTest

- (void) dealloc
{
    [_testRun release];
    [super dealloc];
}

- (NSUInteger) testCaseCount
{
    return 0;
}

- (NSString *) name
{
    return NSStringFromClass([self class]);
}

- (Class) testRunClass
{
    return [XCTestRun class];
}

- (XCTestRun *) testRun
{
    return _testRun;
}

- (void) _gsSetTestRun: (XCTestRun *)run
{
    if (run != _testRun) {
        [_testRun release];
        _testRun = [run retain];
    }
}

- (void) performTest: (XCTestRun *)run
{
    [self _gsSetTestRun:run];
    [run start];
    [run stop];
}

- (void) runTest
{
    XCTestRun *run = [[[self testRunClass] alloc] initWithTest:self];

    [self performTest:run];
    [run release];
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

- (NSString *) description
{
    return [self name];
}

@end
