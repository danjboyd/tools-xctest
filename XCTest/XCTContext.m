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

#import <XCTest/XCTContext.h>
#import <XCTest/XCTestPrivate.h>

static NSString *const GSActivityStackKey = @"GSXCTActivityStack";

// The activities running on this thread, outermost first.
static NSMutableArray *GSActivityStack(void)
{
    NSMutableDictionary *threadDictionary = [[NSThread currentThread] threadDictionary];
    NSMutableArray *stack = [threadDictionary objectForKey:GSActivityStackKey];

    if (stack == nil) {
        stack = [NSMutableArray array];
        [threadDictionary setObject:stack forKey:GSActivityStackKey];
    }
    return stack;
}

NSArray *_GSXCTCurrentActivityPath(void)
{
    NSArray *stack = [[[NSThread currentThread] threadDictionary] objectForKey:GSActivityStackKey];

    return [stack count] > 0 ? [(GSXCTActivity *)[stack lastObject] path] : nil;
}

@implementation GSXCTActivity

- (id) initWithName: (NSString *)name parent: (GSXCTActivity *)parent testCase: (XCTestCase *)testCase
{
    self = [super init];
    if (self) {
        _name = [name copy];
        _path = [(parent ? [[parent path] arrayByAddingObject:_name] : [NSArray arrayWithObject:_name]) retain];
        _startDate = [[NSDate alloc] init];
        _testCase = testCase;
    }

    return self;
}

- (void) dealloc
{
    [_name release];
    [_path release];
    [_startDate release];
    [super dealloc];
}

- (NSString *) name
{
    return _name;
}

- (NSArray *) path
{
    return _path;
}

- (NSDate *) startDate
{
    return _startDate;
}

- (XCTestCase *) testCase
{
    return _testCase;
}

- (void) addAttachment: (XCTAttachment *)attachment
{
    _GSXCTAddAttachment(_testCase, attachment, _path);
}

- (NSString *) description
{
    return [_path componentsJoinedByString:@" > "];
}

@end

@implementation XCTContext

+ (void) runActivityNamed: (NSString *)name block: (void (^)(id<XCTActivity> activity))block
{
    NSMutableArray *stack = GSActivityStack();
    XCTestCase *testCase = [XCTestCase _gsCurrentTestCase];
    GSXCTActivity *activity = [[[GSXCTActivity alloc] initWithName:(name ? name : @"")
                                                            parent:[stack lastObject]
                                                          testCase:testCase] autorelease];

    [stack addObject:activity];
    if (testCase != nil) {
        [[XCTestObservationCenter sharedTestObservationCenter] _gsNotifyObservers:^(id observer) {
            if ([observer respondsToSelector:@selector(_gsTestCase:activityDidStart:)]) {
                [observer _gsTestCase:testCase activityDidStart:activity];
            }
        }];
    }

    @try {
        if (block != nil) {
            block(activity);
        }
    }
    @finally {
        [stack removeObjectIdenticalTo:activity];
    }
}

@end
