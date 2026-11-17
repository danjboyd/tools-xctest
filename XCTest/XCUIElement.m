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

#import <AppKit/AppKit.h>
#import "XCUI.h"
#import "GSXCTestMainThread.h"
#import "XCTestAssertionsImpl.h"

// An element bound to the query's only match, or to its first.
#define GSXCUIUnique (-1)
#define GSXCUIFirst (-2)

// How long an action that entered a nested run loop is given to finish
// before it's taken to be a modal loop.
#define GSXCUINestedLoopGrace 0.5

static NSString *GSXCUITypeName(XCUIElementType type)
{
    switch (type) {
    case XCUIElementTypeAny: return @"element";
    case XCUIElementTypeOther: return @"other element";
    case XCUIElementTypeApplication: return @"application";
    case XCUIElementTypeWindow: return @"window";
    case XCUIElementTypeButton: return @"button";
    case XCUIElementTypeRadioButton: return @"radio button";
    case XCUIElementTypeCheckBox: return @"check box";
    case XCUIElementTypePopUpButton: return @"pop-up button";
    case XCUIElementTypeStaticText: return @"static text";
    case XCUIElementTypeTextField: return @"text field";
    case XCUIElementTypeSecureTextField: return @"secure text field";
    case XCUIElementTypeTextView: return @"text view";
    case XCUIElementTypeMenuItem: return @"menu item";
    case XCUIElementTypeMenuBarItem: return @"menu bar item";
    }
    return [NSString stringWithFormat:@"element of type %lu", (unsigned long)type];
}

static void GSXCUIFail(NSString *message)
{
    _XCTPreformattedFailureHandler(nil, YES, nil, 0, message, @"");
}

// Runs \a block on the main thread (directly, when that's where we are)
// and returns its result. Fails the test and returns nil when the main
// thread doesn't respond.
static id GSXCUIOnMainThread(id (^block)(void))
{
    BOOL timedOut = NO;
    id result;

    if ([NSThread isMainThread]) {
        return block();
    }
    result = [GSXCTestMainThread performQuery:block
                                      timeout:[GSXCTestMainThread defaultTimeout]
                                     timedOut:&timedOut];
    if (timedOut) {
        GSXCUIFail(@"the application's main thread didn't respond");
        return nil;
    }
    return result;
}

// Lets the run loop turn over, so that the UI has caught up.
static void GSXCUISettle(NSTimeInterval interval)
{
    if ([NSThread isMainThread]) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:interval]];
    } else {
        [NSThread sleepForTimeInterval:interval];
    }
}

#pragma mark - The UI tree (main thread only)

// Windows that aren't the application's own machinery: menus and icons.
static BOOL GSXCUIIsUserWindow(NSWindow *window)
{
    NSString *name = NSStringFromClass([window class]);

    return [window isVisible]
        && [name rangeOfString:@"Menu"].location == NSNotFound
        && [name rangeOfString:@"Icon"].location == NSNotFound;
}

static BOOL GSXCUIIsFieldEditor(NSView *view)
{
    return [view isKindOfClass:[NSText class]] && [(NSText *)view isFieldEditor];
}

static NSArray *GSXCUIChildren(id object)
{
    NSMutableArray *children = [NSMutableArray array];

    if ([object isKindOfClass:[NSApplication class]]) {
        NSMenu *mainMenu = [object mainMenu];

        for (NSWindow *window in [object windows]) {
            if (GSXCUIIsUserWindow(window)) {
                [children addObject:window];
            }
        }
        for (NSMenuItem *item in [mainMenu itemArray]) {
            if (![item isSeparatorItem]) {
                [children addObject:item];
            }
        }
    } else if ([object isKindOfClass:[NSWindow class]]) {
        NSView *content = [object contentView];

        if (content != nil) {
            for (NSView *view in [content subviews]) {
                if (!GSXCUIIsFieldEditor(view)) {
                    [children addObject:view];
                }
            }
        }
    } else if ([object isKindOfClass:[NSMenuItem class]]) {
        for (NSMenuItem *item in [[object submenu] itemArray]) {
            if (![item isSeparatorItem]) {
                [children addObject:item];
            }
        }
    } else if ([object isKindOfClass:[NSView class]]) {
        // A control's subviews are its own business (the field editor
        // while it's being edited, for instance).
        if (![object isKindOfClass:[NSControl class]]) {
            for (NSView *view in [object subviews]) {
                if (!GSXCUIIsFieldEditor(view)) {
                    [children addObject:view];
                }
            }
        }
    }
    return children;
}

static void GSXCUIAddDescendants(id object, NSMutableArray *found)
{
    for (id child in GSXCUIChildren(object)) {
        [found addObject:child];
        GSXCUIAddDescendants(child, found);
    }
}

// Whether a button shows a check box or a radio button: GNUstep's
// NSButtonCell keeps no button type, but -setButtonType: gives those two
// their own images.
static XCUIElementType GSXCUIButtonType(NSButton *button)
{
    NSString *image = [[button image] name];

    if (image == nil) {
        return XCUIElementTypeButton;
    }
    if ([image rangeOfString:@"Radio"].location != NSNotFound) {
        return XCUIElementTypeRadioButton;
    }
    if ([image rangeOfString:@"Switch"].location != NSNotFound) {
        return XCUIElementTypeCheckBox;
    }
    return XCUIElementTypeButton;
}

static XCUIElementType GSXCUITypeOf(id object)
{
    if ([object isKindOfClass:[NSApplication class]]) {
        return XCUIElementTypeApplication;
    }
    if ([object isKindOfClass:[NSWindow class]]) {
        return XCUIElementTypeWindow;
    }
    if ([object isKindOfClass:[NSMenuItem class]]) {
        return [object menu] == [NSApp mainMenu] ? XCUIElementTypeMenuBarItem : XCUIElementTypeMenuItem;
    }
    if ([object isKindOfClass:[NSPopUpButton class]]) {
        return XCUIElementTypePopUpButton;
    }
    if ([object isKindOfClass:[NSButton class]]) {
        return GSXCUIButtonType(object);
    }
    if ([object isKindOfClass:[NSSecureTextField class]]) {
        return XCUIElementTypeSecureTextField;
    }
    if ([object isKindOfClass:[NSTextField class]]) {
        return [object isEditable] ? XCUIElementTypeTextField : XCUIElementTypeStaticText;
    }
    if ([object isKindOfClass:[NSTextView class]]) {
        return XCUIElementTypeTextView;
    }
    return XCUIElementTypeOther;
}

static NSWindow *GSXCUIWindowOf(id object)
{
    if ([object isKindOfClass:[NSWindow class]]) {
        return object;
    }
    if ([object isKindOfClass:[NSView class]]) {
        return [object window];
    }
    return nil;
}

// Whether \a object is, or is being edited through, its window's first
// responder.
static BOOL GSXCUIHasFocus(id object)
{
    NSWindow *window = GSXCUIWindowOf(object);
    NSResponder *responder = [window firstResponder];

    if (window == nil || ![object isKindOfClass:[NSView class]]) {
        return NO;
    }
    if (responder == object) {
        return YES;
    }
    return GSXCUIIsFieldEditor((NSView *)responder)
        && [object isKindOfClass:[NSControl class]]
        && [(NSText *)responder delegate] == object;
}

static BOOL GSXCUIIsEnabled(id object)
{
    if ([object isKindOfClass:[NSMenuItem class]]) {
        [[object menu] update];
        return [object isEnabled];
    }
    if ([object isKindOfClass:[NSControl class]]) {
        return [object isEnabled];
    }
    return YES;
}

static NSRect GSXCUIFrame(id object)
{
    if ([object isKindOfClass:[NSWindow class]]) {
        return [object frame];
    }
    if ([object isKindOfClass:[NSView class]] && [object window] != nil) {
        NSRect inWindow = [object convertRect:[object bounds] toView:nil];

        inWindow.origin = [[object window] convertBaseToScreen:inWindow.origin];
        return inWindow;
    }
    return NSZeroRect;
}

static BOOL GSXCUIIsHittable(id object)
{
    if (!GSXCUIIsEnabled(object)) {
        return NO;
    }
    if ([object isKindOfClass:[NSMenuItem class]]) {
        // GNUstep's NSMenuItem has no -isHidden yet.
        return ![object respondsToSelector:@selector(isHidden)] || ![object isHidden];
    }
    if ([object isKindOfClass:[NSWindow class]]) {
        return [object isVisible];
    }
    if ([object isKindOfClass:[NSView class]]) {
        NSWindow *window = [object window];
        NSView *content = [window contentView];
        NSRect frame;

        if (window == nil || ![window isVisible] || [object isHiddenOrHasHiddenAncestor]) {
            return NO;
        }
        frame = [object convertRect:[object visibleRect] toView:content];
        return !NSIsEmptyRect(frame) && NSContainsRect([content bounds], frame);
    }
    return NO;
}

#pragma mark - Attributes

/// An element's attributes, read on the main thread.
@interface GSXCUISnapshot : NSObject <XCUIElementAttributes>
{
@public
    NSString *_identifier;
    NSString *_title;
    NSString *_label;
    id _value;
    NSString *_placeholderValue;
    XCUIElementType _elementType;
    BOOL _enabled;
    BOOL _selected;
    BOOL _hasFocus;
    BOOL _hittable;
    NSRect _frame;
}
+ (GSXCUISnapshot *) snapshotOf: (id)object;
@end

@implementation GSXCUISnapshot

+ (GSXCUISnapshot *) snapshotOf: (id)object
{
    GSXCUISnapshot *snapshot = [[[self alloc] init] autorelease];
    NSString *title = @"";
    NSString *label = nil;
    id value = nil;
    NSString *placeholder = nil;
    NSString *identifier = nil;
    XCUIElementType type = GSXCUITypeOf(object);

    if ([object isKindOfClass:[NSWindow class]] || [object isKindOfClass:[NSMenuItem class]]) {
        title = [object title];
    } else if ([object isKindOfClass:[NSButton class]] && ![object isKindOfClass:[NSPopUpButton class]]) {
        title = [object title];
    }
    if ([object respondsToSelector:@selector(identifier)]) {
        identifier = [object identifier];
    }

    switch (type) {
    case XCUIElementTypeCheckBox:
    case XCUIElementTypeRadioButton:
        value = [NSNumber numberWithInteger:[(NSCell *)[(NSButton *)object cell] state] == NSOnState ? 1 : 0];
        break;
    case XCUIElementTypePopUpButton:
        value = [object titleOfSelectedItem];
        break;
    case XCUIElementTypeStaticText:
    case XCUIElementTypeTextField:
    case XCUIElementTypeSecureTextField:
        value = [object stringValue];
        placeholder = [[object cell] placeholderString];
        break;
    case XCUIElementTypeTextView:
        value = [[[object string] copy] autorelease];
        break;
    default:
        break;
    }

    if ([title length] > 0) {
        label = title;
    } else if ([object respondsToSelector:@selector(accessibilityLabel)]
               && [[object accessibilityLabel] length] > 0) {
        label = [object accessibilityLabel];
    } else if (type == XCUIElementTypeStaticText) {
        label = value;
    }

    snapshot->_identifier = [(identifier ? identifier : @"") copy];
    snapshot->_title = [(title ? title : @"") copy];
    snapshot->_label = [(label ? label : @"") copy];
    snapshot->_value = [value retain];
    snapshot->_placeholderValue = [placeholder copy];
    snapshot->_elementType = type;
    snapshot->_enabled = GSXCUIIsEnabled(object);
    snapshot->_selected = [object isKindOfClass:[NSButton class]] && ![object isKindOfClass:[NSPopUpButton class]]
        ? [(NSCell *)[(NSButton *)object cell] state] == NSOnState
        : ([object isKindOfClass:[NSMenuItem class]] && [(NSMenuItem *)object state] == NSOnState);
    snapshot->_hasFocus = GSXCUIHasFocus(object);
    snapshot->_hittable = GSXCUIIsHittable(object);
    snapshot->_frame = GSXCUIFrame(object);
    return snapshot;
}

- (void) dealloc
{
    [_identifier release];
    [_title release];
    [_label release];
    [_value release];
    [_placeholderValue release];
    [super dealloc];
}

- (NSString *) identifier { return _identifier; }
- (NSString *) title { return _title; }
- (NSString *) label { return _label; }
- (id) value { return _value; }
- (NSString *) placeholderValue { return _placeholderValue; }
- (XCUIElementType) elementType { return _elementType; }
- (BOOL) isEnabled { return _enabled; }
- (BOOL) isSelected { return _selected; }
- (BOOL) hasFocus { return _hasFocus; }
- (NSRect) frame { return _frame; }

// For predicates: "enabled" and "selected" as well as "isEnabled".
- (id) valueForUndefinedKey: (NSString *)key
{
    if ([key isEqual:@"enabled"]) {
        return [NSNumber numberWithBool:_enabled];
    }
    if ([key isEqual:@"selected"]) {
        return [NSNumber numberWithBool:_selected];
    }
    return [super valueForUndefinedKey:key];
}

@end

#pragma mark - Queries

@interface XCUIElementQuery (GSXCUIPrivate)
- (id) _gsInitWithSource: (id)source
                    type: (XCUIElementType)type
            childrenOnly: (BOOL)childrenOnly
               predicate: (NSPredicate *)predicate
             description: (NSString *)description;
- (NSArray *) _gsMatches;
@end

@interface XCUIElement (GSXCUIPrivate)
- (id) _gsInitWithQuery: (XCUIElementQuery *)query index: (NSInteger)index;
- (id) _gsResolve: (NSString **)problem;
@end

// Matches identifier, title or label.
static NSPredicate *GSXCUIKeyPredicate(NSString *key)
{
    return [NSPredicate predicateWithFormat:@"identifier == %@ OR title == %@ OR label == %@", key, key, key];
}

@implementation XCUIElementQuery

- (id) _gsInitWithSource: (id)source
                    type: (XCUIElementType)type
            childrenOnly: (BOOL)childrenOnly
               predicate: (NSPredicate *)predicate
             description: (NSString *)description
{
    if ((self = [super init]) != nil) {
        _source = [source retain];
        _type = type;
        _childrenOnly = childrenOnly;
        _predicate = [predicate retain];
        _predicateDescription = [description copy];
    }
    return self;
}

- (void) dealloc
{
    [_source release];
    [_predicate release];
    [_predicateDescription release];
    [super dealloc];
}

// Main thread only.
- (NSArray *) _gsMatches
{
    NSMutableArray *sources = [NSMutableArray array];
    NSMutableArray *matches = [NSMutableArray array];

    if ([_source isKindOfClass:[XCUIElementQuery class]]) {
        [sources addObjectsFromArray:[_source _gsMatches]];
    } else {
        id object = [_source _gsResolve:NULL];

        if (object != nil) {
            [sources addObject:object];
        }
    }

    for (id source in sources) {
        NSMutableArray *candidates = [NSMutableArray array];

        if (_childrenOnly) {
            [candidates addObjectsFromArray:GSXCUIChildren(source)];
        } else {
            GSXCUIAddDescendants(source, candidates);
        }
        for (id candidate in candidates) {
            if (_type != XCUIElementTypeAny && GSXCUITypeOf(candidate) != _type) {
                continue;
            }
            if (_predicate != nil && ![_predicate evaluateWithObject:[GSXCUISnapshot snapshotOf:candidate]]) {
                continue;
            }
            if (![matches containsObject:candidate]) {
                [matches addObject:candidate];
            }
        }
    }
    return matches;
}

- (NSString *) description
{
    NSString *what = [NSString stringWithFormat:@"%@s", GSXCUITypeName(_type)];

    if (_predicateDescription != nil) {
        what = [what stringByAppendingFormat:@" %@", _predicateDescription];
    }
    if ([_source isKindOfClass:[XCUIApplication class]]) {
        return what;
    }
    return [NSString stringWithFormat:@"%@ %@ %@", what, _childrenOnly ? @"in" : @"under", [_source description]];
}

- (NSUInteger) count
{
    NSNumber *count = GSXCUIOnMainThread(^id (void) {
        return [NSNumber numberWithUnsignedInteger:[[self _gsMatches] count]];
    });

    return [count unsignedIntegerValue];
}

- (XCUIElement *) element
{
    return [[[XCUIElement alloc] _gsInitWithQuery:self index:GSXCUIUnique] autorelease];
}

- (XCUIElement *) firstMatch
{
    return [[[XCUIElement alloc] _gsInitWithQuery:self index:GSXCUIFirst] autorelease];
}

- (XCUIElement *) elementBoundByIndex: (NSUInteger)index
{
    return [[[XCUIElement alloc] _gsInitWithQuery:self index:(NSInteger)index] autorelease];
}

- (NSArray *) allElementsBoundByIndex
{
    NSUInteger count = [self count];
    NSMutableArray *elements = [NSMutableArray arrayWithCapacity:count];
    NSUInteger index;

    for (index = 0; index < count; index++) {
        [elements addObject:[self elementBoundByIndex:index]];
    }
    return elements;
}

- (XCUIElementQuery *) _gsFiltered: (NSPredicate *)predicate description: (NSString *)description
{
    NSPredicate *combined = predicate;
    NSString *combinedDescription = description;

    if (_predicate != nil) {
        combined = [NSCompoundPredicate andPredicateWithSubpredicates:
                       [NSArray arrayWithObjects:_predicate, predicate, nil]];
        combinedDescription = [NSString stringWithFormat:@"%@, %@", _predicateDescription, description];
    }
    return [[[XCUIElementQuery alloc] _gsInitWithSource:_source
                                                   type:_type
                                           childrenOnly:_childrenOnly
                                              predicate:combined
                                            description:combinedDescription] autorelease];
}

- (XCUIElement *) objectForKeyedSubscript: (NSString *)key
{
    return [[self _gsFiltered:GSXCUIKeyPredicate(key)
                  description:[NSString stringWithFormat:@"\"%@\"", key]] element];
}

- (XCUIElementQuery *) matchingIdentifier: (NSString *)identifier
{
    return [self _gsFiltered:[NSPredicate predicateWithFormat:@"identifier == %@", identifier]
                 description:[NSString stringWithFormat:@"with identifier \"%@\"", identifier]];
}

- (XCUIElementQuery *) matchingPredicate: (NSPredicate *)predicate
{
    return [self _gsFiltered:predicate
                 description:[NSString stringWithFormat:@"matching %@", [predicate predicateFormat]]];
}

- (XCUIElementQuery *) matchingType: (XCUIElementType)type identifier: (NSString *)identifier
{
    NSPredicate *predicate = GSXCUIKeyPredicate(identifier);

    if (type != XCUIElementTypeAny) {
        predicate = [NSCompoundPredicate andPredicateWithSubpredicates:[NSArray arrayWithObjects:
            [NSPredicate predicateWithFormat:@"elementType == %@", [NSNumber numberWithUnsignedInteger:type]], predicate, nil]];
    }
    return [self _gsFiltered:predicate
                 description:[NSString stringWithFormat:@"(%@ \"%@\")", GSXCUITypeName(type), identifier]];
}

- (XCUIElement *) elementMatchingType: (XCUIElementType)type identifier: (NSString *)identifier
{
    return [[self matchingType:type identifier:identifier] element];
}

- (XCUIElementQuery *) descendantsMatchingType: (XCUIElementType)type
{
    return [[[XCUIElementQuery alloc] _gsInitWithSource:self type:type childrenOnly:NO
                                              predicate:nil description:nil] autorelease];
}

- (XCUIElementQuery *) childrenMatchingType: (XCUIElementType)type
{
    return [[[XCUIElementQuery alloc] _gsInitWithSource:self type:type childrenOnly:YES
                                              predicate:nil description:nil] autorelease];
}

- (XCUIElementQuery *) windows { return [self descendantsMatchingType:XCUIElementTypeWindow]; }
- (XCUIElementQuery *) buttons { return [self descendantsMatchingType:XCUIElementTypeButton]; }
- (XCUIElementQuery *) radioButtons { return [self descendantsMatchingType:XCUIElementTypeRadioButton]; }
- (XCUIElementQuery *) checkBoxes { return [self descendantsMatchingType:XCUIElementTypeCheckBox]; }
- (XCUIElementQuery *) popUpButtons { return [self descendantsMatchingType:XCUIElementTypePopUpButton]; }
- (XCUIElementQuery *) staticTexts { return [self descendantsMatchingType:XCUIElementTypeStaticText]; }
- (XCUIElementQuery *) textFields { return [self descendantsMatchingType:XCUIElementTypeTextField]; }
- (XCUIElementQuery *) secureTextFields { return [self descendantsMatchingType:XCUIElementTypeSecureTextField]; }
- (XCUIElementQuery *) textViews { return [self descendantsMatchingType:XCUIElementTypeTextView]; }
- (XCUIElementQuery *) menuItems { return [self descendantsMatchingType:XCUIElementTypeMenuItem]; }
- (XCUIElementQuery *) menuBarItems { return [self descendantsMatchingType:XCUIElementTypeMenuBarItem]; }
- (XCUIElementQuery *) otherElements { return [self descendantsMatchingType:XCUIElementTypeOther]; }

@end

#pragma mark - Elements

@implementation XCUIElement

- (id) _gsInitWithQuery: (XCUIElementQuery *)query index: (NSInteger)index
{
    if ((self = [super init]) != nil) {
        _query = [query retain];
        _index = index;
    }
    return self;
}

- (void) dealloc
{
    [_query release];
    [super dealloc];
}

// The object behind the element, or nil with a reason in \a problem.
// Main thread only.
- (id) _gsResolve: (NSString **)problem
{
    NSArray *matches;

    if (_query == nil) {
        return NSApp;
    }
    matches = [_query _gsMatches];
    if (_index >= 0) {
        if ((NSUInteger)_index < [matches count]) {
            return [matches objectAtIndex:(NSUInteger)_index];
        }
        if (problem != NULL) {
            *problem = [NSString stringWithFormat:@"no match at index %ld for %@ (%lu found)",
                (long)_index, [_query description], (unsigned long)[matches count]];
        }
        return nil;
    }
    if ([matches count] == 1 || ([matches count] > 1 && _index == GSXCUIFirst)) {
        return [matches objectAtIndex:0];
    }
    if (problem != NULL) {
        if ([matches count] == 0) {
            *problem = [NSString stringWithFormat:@"no matches found for %@", [_query description]];
        } else {
            NSMutableArray *names = [NSMutableArray array];

            for (id match in matches) {
                [names addObject:[NSString stringWithFormat:@"%@ \"%@\"", GSXCUITypeName(GSXCUITypeOf(match)),
                    [[GSXCUISnapshot snapshotOf:match] label]]];
            }
            *problem = [NSString stringWithFormat:@"%lu matches found for %@: %@",
                (unsigned long)[matches count], [_query description], [names componentsJoinedByString:@", "]];
        }
    }
    return nil;
}

- (NSString *) description
{
    if (_query == nil) {
        return @"the application";
    }
    if (_index >= 0) {
        return [NSString stringWithFormat:@"%@ [%ld]", [_query description], (long)_index];
    }
    return [_query description];
}

// The element's attributes, or nil (having failed the test) when it can't
// be found.
- (GSXCUISnapshot *) _gsSnapshot
{
    NSArray *result = GSXCUIOnMainThread(^id (void) {
        NSString *problem = nil;
        id object = [self _gsResolve:&problem];

        if (object == nil) {
            return [NSArray arrayWithObject:problem];
        }
        return [NSArray arrayWithObjects:problem ? problem : @"", [GSXCUISnapshot snapshotOf:object], nil];
    });

    if ([result count] == 1) {
        GSXCUIFail([result objectAtIndex:0]);
        return nil;
    }
    return [result count] > 1 ? [result objectAtIndex:1] : nil;
}

- (BOOL) exists
{
    NSNumber *exists = GSXCUIOnMainThread(^id (void) {
        return [NSNumber numberWithBool:[self _gsResolve:NULL] != nil];
    });

    return [exists boolValue];
}

- (BOOL) isHittable
{
    GSXCUISnapshot *snapshot = [self _gsSnapshot];

    return snapshot != nil && snapshot->_hittable;
}

- (NSString *) identifier { return [[self _gsSnapshot] identifier]; }
- (NSString *) title { return [[self _gsSnapshot] title]; }
- (NSString *) label { return [[self _gsSnapshot] label]; }
- (id) value { return [[self _gsSnapshot] value]; }
- (NSString *) placeholderValue { return [[self _gsSnapshot] placeholderValue]; }
- (XCUIElementType) elementType
{
    return _query == nil ? XCUIElementTypeApplication : [[self _gsSnapshot] elementType];
}
- (BOOL) isEnabled { return [[self _gsSnapshot] isEnabled]; }
- (BOOL) isSelected { return [[self _gsSnapshot] isSelected]; }
- (BOOL) hasFocus { return [[self _gsSnapshot] hasFocus]; }
- (NSRect) frame
{
    GSXCUISnapshot *snapshot = [self _gsSnapshot];

    return snapshot != nil ? [snapshot frame] : NSZeroRect;
}

- (BOOL) _gsWaitForExistence: (BOOL)existence timeout: (NSTimeInterval)timeout
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];

    for (;;) {
        if ([self exists] == existence) {
            return YES;
        }
        if ([deadline timeIntervalSinceNow] <= 0) {
            return NO;
        }
        GSXCUISettle(0.05);
    }
}

- (BOOL) waitForExistenceWithTimeout: (NSTimeInterval)timeout
{
    return [self _gsWaitForExistence:YES timeout:timeout];
}

- (BOOL) waitForNonExistenceWithTimeout: (NSTimeInterval)timeout
{
    return [self _gsWaitForExistence:NO timeout:timeout];
}

// Runs \a act on the element's object on the main thread, once it's found
// and hittable. \a verb names the action in failures. An action that opens
// a modal loop returns while the loop runs (on the test thread); its block
// finishes when the loop ends.
- (void) _gsPerform: (NSString *)verb action: (void (^)(id object))act
{
    GSXCTestMainThreadAction *action;
    id result;

    action = [GSXCTestMainThread performAction:^id (void) {
        NSString *problem = nil;
        id object = [self _gsResolve:&problem];

        if (object == nil) {
            return [NSString stringWithFormat:@"couldn't %@ %@: %@", verb, [self description], problem];
        }
        if (!GSXCUIIsHittable(object)) {
            return [NSString stringWithFormat:@"couldn't %@ %@: it isn't hittable (%@)", verb, [self description],
                !GSXCUIIsEnabled(object) ? @"it's disabled" : @"it's hidden, off screen or outside its window"];
        }
        act(object);
        return nil;
    } timeout:[GSXCTestMainThread defaultTimeout]];

    switch ([action state]) {
    case GSXCTestMainThreadActionCompleted:
        result = [action result];
        if ([result isKindOfClass:[NSString class]]) {
            GSXCUIFail(result);
        } else if ([action exception] != nil) {
            GSXCUIFail([NSString stringWithFormat:@"couldn't %@ %@: %@", verb, [self description],
                [[action exception] reason]]);
        }
        break;
    case GSXCTestMainThreadActionInNestedLoop:
        // A short loop (GNUstep highlights a clicked button for 0.1 s)
        // finishes here; a modal loop keeps running, and the test drives
        // it from here.
        if ([action waitUntilFinishedWithTimeout:GSXCUINestedLoopGrace]) {
            result = [action result];
            if ([result isKindOfClass:[NSString class]]) {
                GSXCUIFail(result);
            }
        }
        break;
    case GSXCTestMainThreadActionNotStarted:
    case GSXCTestMainThreadActionBlocked:
        GSXCUIFail([NSString stringWithFormat:@"couldn't %@ %@: the application's main thread didn't respond",
            verb, [self description]]);
        break;
    }
    if ([NSThread isMainThread]) {
        GSXCUISettle(0.01);
    }
}

static void GSXCUIMakeKey(NSWindow *window)
{
    if (window != nil && ![window isKeyWindow]) {
        [window makeKeyWindow];
    }
}

static void GSXCUIClickObject(id object)
{
    NSWindow *window = GSXCUIWindowOf(object);

    if ([object isKindOfClass:[NSMenuItem class]]) {
        NSMenu *menu = [object menu];

        if ([object hasSubmenu]) {
            return;
        }
        [menu performActionForItemAtIndex:[menu indexOfItem:object]];
    } else if ([object isKindOfClass:[NSWindow class]]) {
        [object makeKeyAndOrderFront:nil];
    } else if ([object isKindOfClass:[NSTextField class]] || [object isKindOfClass:[NSTextView class]]) {
        GSXCUIMakeKey(window);
        [window makeFirstResponder:object];
    } else if ([object isKindOfClass:[NSControl class]]) {
        GSXCUIMakeKey(window);
        [object performClick:nil];
    } else {
        // A mouse-down and mouse-up at its centre. The mouse-up is queued
        // first, so a view that tracks the mouse after mouse-down finds it.
        NSRect bounds = [object bounds];
        NSPoint centre = [object convertPoint:NSMakePoint(NSMidX(bounds), NSMidY(bounds)) toView:nil];
        NSEvent *down = [NSEvent mouseEventWithType:NSLeftMouseDown location:centre modifierFlags:0
                                          timestamp:0 windowNumber:[window windowNumber] context:nil
                                        eventNumber:0 clickCount:1 pressure:1.0];
        NSEvent *up = [NSEvent mouseEventWithType:NSLeftMouseUp location:centre modifierFlags:0
                                        timestamp:0 windowNumber:[window windowNumber] context:nil
                                      eventNumber:0 clickCount:1 pressure:0.0];

        GSXCUIMakeKey(window);
        [NSApp postEvent:up atStart:NO];
        [window sendEvent:down];
    }
}

- (void) click
{
    [self _gsPerform:@"click" action:^(id object) {
        GSXCUIClickObject(object);
    }];
}

static void GSXCUISendKey(NSWindow *window, NSString *characters)
{
    NSEventType types[2] = { NSKeyDown, NSKeyUp };
    int i;

    for (i = 0; i < 2; i++) {
        NSEvent *event = [NSEvent keyEventWithType:types[i] location:NSZeroPoint modifierFlags:0
                                         timestamp:0 windowNumber:[window windowNumber] context:nil
                                        characters:characters charactersIgnoringModifiers:characters
                                         isARepeat:NO keyCode:0];

        [window sendEvent:event];
    }
}

- (void) typeText: (NSString *)text
{
    [self _gsPerform:@"type into" action:^(id object) {
        NSWindow *window = GSXCUIWindowOf(object);
        NSUInteger index;

        if (window == nil) {
            window = [NSApp keyWindow];
        } else {
            GSXCUIMakeKey(window);
            if (!GSXCUIHasFocus(object)) {
                [window makeFirstResponder:object];
            }
        }
        for (index = 0; index < [text length]; index++) {
            unichar c = [text characterAtIndex:index];
            NSString *characters = c == '\n'
                ? @"\r"
                : [NSString stringWithCharacters:&c length:1];

            GSXCUISendKey(window, characters);
        }
    }];
}

- (XCUIElementQuery *) descendantsMatchingType: (XCUIElementType)type
{
    return [[[XCUIElementQuery alloc] _gsInitWithSource:self type:type childrenOnly:NO
                                              predicate:nil description:nil] autorelease];
}

- (XCUIElementQuery *) childrenMatchingType: (XCUIElementType)type
{
    return [[[XCUIElementQuery alloc] _gsInitWithSource:self type:type childrenOnly:YES
                                              predicate:nil description:nil] autorelease];
}

- (XCUIElementQuery *) windows { return [self descendantsMatchingType:XCUIElementTypeWindow]; }
- (XCUIElementQuery *) buttons { return [self descendantsMatchingType:XCUIElementTypeButton]; }
- (XCUIElementQuery *) radioButtons { return [self descendantsMatchingType:XCUIElementTypeRadioButton]; }
- (XCUIElementQuery *) checkBoxes { return [self descendantsMatchingType:XCUIElementTypeCheckBox]; }
- (XCUIElementQuery *) popUpButtons { return [self descendantsMatchingType:XCUIElementTypePopUpButton]; }
- (XCUIElementQuery *) staticTexts { return [self descendantsMatchingType:XCUIElementTypeStaticText]; }
- (XCUIElementQuery *) textFields { return [self descendantsMatchingType:XCUIElementTypeTextField]; }
- (XCUIElementQuery *) secureTextFields { return [self descendantsMatchingType:XCUIElementTypeSecureTextField]; }
- (XCUIElementQuery *) textViews { return [self descendantsMatchingType:XCUIElementTypeTextView]; }
- (XCUIElementQuery *) menuItems { return [self descendantsMatchingType:XCUIElementTypeMenuItem]; }
- (XCUIElementQuery *) menuBarItems { return [self descendantsMatchingType:XCUIElementTypeMenuBarItem]; }
- (XCUIElementQuery *) otherElements { return [self descendantsMatchingType:XCUIElementTypeOther]; }

@end

@implementation XCUIApplication

+ (XCUIApplication *) currentApplication
{
    return [[[self alloc] init] autorelease];
}

- (id) init
{
    return [super _gsInitWithQuery:nil index:GSXCUIUnique];
}

- (BOOL) exists
{
    return YES;
}

@end
