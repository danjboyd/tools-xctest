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

#import <XCTest/XCTestExpectation.h>
#import <XCTest/XCTestPrivate.h>

static NSUInteger GSLastFulfillmentToken = 0;

static NSUInteger GSNextFulfillmentToken(void)
{
    NSUInteger token;

    @synchronized ([XCTestExpectation class]) {
        token = ++GSLastFulfillmentToken;
    }

    return token;
}

static BOOL GSObjectsEqual(id a, id b)
{
    return a == b || [a isEqual:b];
}

@implementation XCTestExpectation

@synthesize expectationDescription = _expectationDescription;
@synthesize inverted = _inverted;
@synthesize assertForOverFulfill = _assertForOverFulfill;

- (instancetype)init
{
    return [self initWithDescription:@"no description provided"];
}

- (NSUInteger)expectedFulfillmentCount
{
    @synchronized (self) { return _expectedFulfillmentCount; }
}

- (void)setExpectedFulfillmentCount:(NSUInteger)count
{
    if (!count) [NSException raise:NSInvalidArgumentException format:@"Expected fulfillment count must be positive"];
    @synchronized (self) { _expectedFulfillmentCount = count; }
}

- (instancetype)initWithDescription:(NSString *)expectationDescription
{
    self = [super init];
    if (self) {
        _expectationDescription = [expectationDescription copy];
        _expectedFulfillmentCount = 1;
    }

    return self;
}

- (void)dealloc
{
    [_expectationDescription release];
    [_gsOwner release];
    [super dealloc];
}

- (void)_gsSetOwner:(XCTestCase *)owner
{
    @synchronized (self) {
        if (owner != _gsOwner) {
            [_gsOwner release];
            _gsOwner = [owner retain];
        }
    }
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p> %@",
        NSStringFromClass([self class]), self, _expectationDescription];
}

- (void)fulfill
{
    BOOL overFulfilled = NO;

    @synchronized (self) {
        if (_fulfillmentCount >= _expectedFulfillmentCount) {
            overFulfilled = YES;
        } else {
            _fulfillmentCount++;
            if (_fulfillmentCount == _expectedFulfillmentCount) {
                _fulfillmentToken = GSNextFulfillmentToken();
            }
        }
    }

    if (overFulfilled && _assertForOverFulfill) {
        XCTestCase *owner = nil;

        @synchronized (self) {
            owner = [[_gsOwner retain] autorelease];
        }
        _XCTRecordFailure(owner ? owner : [XCTestCase _gsCurrentTestCase],
            [NSString stringWithFormat:@"API violation - multiple calls made to -[XCTestExpectation fulfill] for %@.",
                _expectationDescription]);
    }
}

- (BOOL)_gsIsFulfilled
{
    @synchronized (self) {
        return _fulfillmentToken != 0;
    }
}

- (NSUInteger)_gsFulfillmentToken
{
    @synchronized (self) {
        return _fulfillmentToken;
    }
}

- (BOOL)_gsHasBeenWaitedOn
{
    return _hasBeenWaitedOn;
}

- (void)_gsSetHasBeenWaitedOn:(BOOL)waited
{
    _hasBeenWaitedOn = waited;
}

- (void)_gsPoll
{
}

- (void)_gsInvalidate
{
}

@end

@implementation XCTNSNotificationExpectation

@synthesize notificationName = _notificationName;
@synthesize observedObject = _observedObject;
@synthesize notificationCenter = _notificationCenter;

- (id)initWithName:(NSString *)notificationName
{
    return [self initWithName:notificationName object:nil notificationCenter:nil];
}

- (id)initWithName:(NSString *)notificationName object:(id)object
{
    return [self initWithName:notificationName object:object notificationCenter:nil];
}

- (id)initWithName:(NSString *)notificationName
             object:(id)object
 notificationCenter:(NSNotificationCenter *)notificationCenter
{
    NSString *description = [NSString stringWithFormat:@"Expect notification '%@' from %@",
        notificationName, object ? object : @"any object"];

    self = [super initWithDescription:description];
    if (self) {
        _notificationName = [notificationName copy];
        _observedObject = [object retain];
        _notificationCenter = [(notificationCenter ? notificationCenter : [NSNotificationCenter defaultCenter]) retain];
        [_notificationCenter addObserver:self
                                selector:@selector(_gsReceivedNotification:)
                                    name:_notificationName
                                  object:_observedObject];
        _observing = YES;
    }

    return self;
}

- (void)dealloc
{
    [self _gsInvalidate];
    [_notificationName release];
    [_observedObject release];
    [_notificationCenter release];
    [super dealloc];
}

- (XCNotificationExpectationHandler)handler
{
    @synchronized (self) {
        return [[_handler retain] autorelease];
    }
}

- (void)setHandler:(XCNotificationExpectationHandler)handler
{
    @synchronized (self) {
        XCNotificationExpectationHandler old = _handler;
        _handler = [handler copy];
        [old release];
    }
}

- (void)_gsReceivedNotification:(NSNotification *)notification
{
    XCNotificationExpectationHandler handler = [self handler];

    if (![self _gsIsFulfilled] && (handler == nil || handler(notification))) {
        [self fulfill];
    }
}

- (void)_gsInvalidate
{
    if (_observing) {
        [_notificationCenter removeObserver:self name:_notificationName object:_observedObject];
        _observing = NO;
    }
    [self setHandler:nil];
}

@end

static char GSKVOExpectationContext;

@implementation XCTKVOExpectation

@synthesize keyPath = _keyPath;
@synthesize observedObject = _observedObject;
@synthesize expectedValue = _expectedValue;

- (id)initWithKeyPath:(NSString *)keyPath object:(id)object
{
    return [self initWithKeyPath:keyPath object:object expectedValue:nil];
}

- (id)initWithKeyPath:(NSString *)keyPath
                object:(id)object
         expectedValue:(id)expectedValue
{
    NSString *description = expectedValue
        ? [NSString stringWithFormat:@"Expect value of '%@' of %@ to be '%@'", keyPath, object, expectedValue]
        : [NSString stringWithFormat:@"Expect change of '%@' of %@", keyPath, object];

    self = [super initWithDescription:description];
    if (self) {
        _keyPath = [keyPath copy];
        _observedObject = [object retain];
        _expectedValue = [expectedValue retain];
        [_observedObject addObserver:self
                          forKeyPath:_keyPath
                             options:NSKeyValueObservingOptionNew
                             context:&GSKVOExpectationContext];
        _observing = YES;

        // Already at the expected value counts as fulfilled.
        if (_expectedValue != nil
            && GSObjectsEqual([_observedObject valueForKeyPath:_keyPath], _expectedValue)) {
            [self fulfill];
        }
    }

    return self;
}

- (void)dealloc
{
    [self _gsInvalidate];
    [_keyPath release];
    [_observedObject release];
    [_expectedValue release];
    [super dealloc];
}

- (XCKVOExpectationHandler)handler
{
    @synchronized (self) {
        return [[_handler retain] autorelease];
    }
}

- (void)setHandler:(XCKVOExpectationHandler)handler
{
    @synchronized (self) {
        XCKVOExpectationHandler old = _handler;
        _handler = [handler copy];
        [old release];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                       ofObject:(id)object
                         change:(NSDictionary *)change
                        context:(void *)context
{
    XCKVOExpectationHandler handler = nil;
    BOOL matches = NO;

    if (context != &GSKVOExpectationContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }

    if ([self _gsIsFulfilled]) {
        return;
    }

    handler = [self handler];
    if (handler != nil) {
        matches = handler(object, change);
    } else if (_expectedValue != nil) {
        matches = GSObjectsEqual([object valueForKeyPath:_keyPath], _expectedValue);
    } else {
        matches = YES;
    }

    if (matches) {
        [self fulfill];
    }
}

- (void)_gsInvalidate
{
    if (_observing) {
        [_observedObject removeObserver:self forKeyPath:_keyPath];
        _observing = NO;
    }
    [self setHandler:nil];
}

@end

@implementation XCTNSPredicateExpectation

@synthesize predicate = _predicate;
@synthesize object = _object;

- (id)initWithPredicate:(NSPredicate *)predicate object:(id)object
{
    NSString *description = [NSString stringWithFormat:@"Expect predicate `%@` for object %@",
        predicate, object];

    self = [super initWithDescription:description];
    if (self) {
        _predicate = [predicate copy];
        _object = [object retain];
    }

    return self;
}

- (void)dealloc
{
    [_predicate release];
    [_object release];
    [_handler release];
    [super dealloc];
}

- (XCPredicateExpectationHandler)handler
{
    @synchronized (self) {
        return [[_handler retain] autorelease];
    }
}

- (void)setHandler:(XCPredicateExpectationHandler)handler
{
    @synchronized (self) {
        XCPredicateExpectationHandler old = _handler;
        _handler = [handler copy];
        [old release];
    }
}

- (void)_gsPoll
{
    XCPredicateExpectationHandler handler = nil;

    if ([self _gsIsFulfilled] || ![_predicate evaluateWithObject:_object]) {
        return;
    }

    handler = [self handler];
    if (handler == nil || handler()) {
        [self fulfill];
    }
}

- (void)_gsInvalidate
{
    [self setHandler:nil];
}

@end
