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

#import <XCTest/XCTestObservationCenter.h>
#import <XCTest/XCTestPrivate.h>

@implementation XCTestObservationCenter

+ (XCTestObservationCenter *) sharedTestObservationCenter
{
    static XCTestObservationCenter *center = nil;

    @synchronized (self) {
        if (center == nil) {
            center = [[XCTestObservationCenter alloc] init];
        }
    }

    return center;
}

- (id) init
{
    self = [super init];
    if (self) {
        _observers = [[NSMutableArray alloc] init];
    }

    return self;
}

- (void) dealloc
{
    [_observers release];
    [super dealloc];
}

- (void) addTestObserver: (id<XCTestObservation>)testObserver
{
    @synchronized (self) {
        if (testObserver != nil && [_observers indexOfObjectIdenticalTo:testObserver] == NSNotFound) {
            [_observers addObject:testObserver];
        }
    }
}

- (void) _gsAddTestObserverFirst: (id<XCTestObservation>)testObserver
{
    @synchronized (self) {
        if (testObserver != nil && [_observers indexOfObjectIdenticalTo:testObserver] == NSNotFound) {
            [_observers insertObject:testObserver atIndex:0];
        }
    }
}

- (void) removeTestObserver: (id<XCTestObservation>)testObserver
{
    @synchronized (self) {
        [_observers removeObjectIdenticalTo:testObserver];
    }
}

- (void) _gsNotifyObservers: (void (^)(id observer))block
{
    NSArray *observers = nil;

    // Copied so observers can add or remove observers while being notified.
    @synchronized (self) {
        observers = [[_observers copy] autorelease];
    }

    for (id observer in observers) {
        block(observer);
    }
}

@end
