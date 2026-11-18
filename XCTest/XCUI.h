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

#ifndef XCUI_h
#define XCUI_h

// UI testing for hosted tests (`xctest -host`): finding an application's
// windows, controls and menu items, acting on them, and waiting for the
// UI to change. It's in libXCTestUI, which needs gnustep-gui; XCTest.h
// doesn't include it, so tests without a UI never need AppKit.
//
// The names follow Apple's XCUITest where the behaviour matches, but this
// isn't XCUITest: the tests run inside the application (xctest -host
// launches it), and elements are found by walking AppKit's windows, views
// and menus, not through accessibility. There's no -launch or -terminate,
// and no other application can be queried.
//
// An element is a query, resolved again every time it's used, so it stays
// valid when the window behind it is rebuilt. Elements and queries may be
// used from a test on the main thread or, in a class whose
// +runsOnUITestThread returns YES, from the test thread: AppKit is only
// ever touched on the main thread (through GSXCTestMainThread). Actions
// that a user couldn't perform (the element doesn't exist, is disabled,
// hidden, or outside its window) fail the test instead of acting.
//
// Not supported yet: tables, key presses other than typing text, double
// clicks, and occlusion by other windows. See issue #26.

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

@class XCUIElementQuery;
@class NSImage;

/// An image of part of the application's UI.
@interface XCUIScreenshot : NSObject
{
    NSImage *_image;
}
- (NSImage *) image;
/// The image as PNG data.
- (NSData *) PNGRepresentation;
@end

/// Something that can be pictured.
@protocol XCUIScreenshotProviding
/// An image of it as it's drawn now. Fails the test, and returns nil, if
/// it can't be found or isn't drawn in a window (a menu item, say).
- (XCUIScreenshot *) screenshot;
@end

/// The kinds of element. The values are Apple's; only these are found.
typedef NS_ENUM(NSUInteger, XCUIElementType) {
    /// In a query: any kind.
    XCUIElementTypeAny = 0,
    /// A view that isn't one of the kinds below.
    XCUIElementTypeOther = 1,
    XCUIElementTypeApplication = 2,
    XCUIElementTypeWindow = 4,
    /// A window attached to another as a sheet; it's found as a child of
    /// that window, not of the application.
    XCUIElementTypeSheet = 5,
    XCUIElementTypeButton = 9,
    XCUIElementTypeRadioButton = 10,
    XCUIElementTypeCheckBox = 12,
    XCUIElementTypePopUpButton = 14,
    XCUIElementTypeStaticText = 48,
    XCUIElementTypeTextField = 49,
    XCUIElementTypeSecureTextField = 50,
    XCUIElementTypeTextView = 52,
    XCUIElementTypeMenuItem = 54,
    /// A top-level item of the application's main menu.
    XCUIElementTypeMenuBarItem = 56,
};

/// What an element's attributes are, as a predicate in a query sees them
/// (keys: identifier, title, label, value, placeholderValue, elementType,
/// enabled, selected, hasFocus, frame).
@protocol XCUIElementAttributes
/// The view's or menu item's -identifier, or "".
- (NSString *) identifier;
/// A window's, button's or menu item's title, or "".
- (NSString *) title;
/// What a user reads as its name: the title if there is one, else its
/// accessibility label, else a static text's text.
- (NSString *) label;
/// A text's string, a check box's or radio button's state (an NSNumber,
/// 0 or 1), or a pop-up button's selected title; else nil.
- (id) value;
/// A text field's placeholder, or nil.
- (NSString *) placeholderValue;
- (XCUIElementType) elementType;
- (BOOL) isEnabled;
/// A button that is on, or a selected menu item.
- (BOOL) isSelected;
/// Whether it's its window's first responder (a text field being edited
/// counts).
- (BOOL) hasFocus;
/// In screen coordinates (GNUstep's: the origin is at the bottom left).
- (NSRect) frame;
@end

/// Elements found by a query.
@protocol XCUIElementTypeQueryProvider
- (XCUIElementQuery *) windows;
- (XCUIElementQuery *) sheets;
- (XCUIElementQuery *) buttons;
- (XCUIElementQuery *) radioButtons;
- (XCUIElementQuery *) checkBoxes;
- (XCUIElementQuery *) popUpButtons;
- (XCUIElementQuery *) staticTexts;
- (XCUIElementQuery *) textFields;
- (XCUIElementQuery *) secureTextFields;
- (XCUIElementQuery *) textViews;
- (XCUIElementQuery *) menuItems;
- (XCUIElementQuery *) menuBarItems;
- (XCUIElementQuery *) otherElements;
@end

/// An element of the application's UI: a lazy query for exactly one.
@interface XCUIElement : NSObject <XCUIElementAttributes, XCUIElementTypeQueryProvider, XCUIScreenshotProviding>
{
    XCUIElementQuery *_query;
    NSInteger _index;
}

/// Whether it can be found now.
- (BOOL) exists;
/// Whether a user could act on it: it exists and is enabled, it and its
/// ancestors aren't hidden, its window is on screen, and its frame lies in
/// its window's content. (Other windows covering it aren't checked yet.)
- (BOOL) isHittable;

/// Waits up to \a timeout seconds for it to exist; returns whether it did.
- (BOOL) waitForExistenceWithTimeout: (NSTimeInterval)timeout;
/// Waits up to \a timeout seconds for it to stop existing; returns whether
/// it did.
- (BOOL) waitForNonExistenceWithTimeout: (NSTimeInterval)timeout;

/// Clicks it: a control's action is sent (-performClick:), a text field or
/// text view becomes first responder, a menu item's action is performed
/// and a window is made key. Anything else gets a mouse-down and mouse-up
/// at its centre. Fails the test if it isn't hittable.
- (void) click;
/// Makes it first responder and types \a text into it as key events, so
/// that field editors, formatters and delegates see them. "\n" is Return
/// and "\t" is Tab. Fails the test if it isn't hittable.
- (void) typeText: (NSString *)text;

/// Its descendants of \a type.
- (XCUIElementQuery *) descendantsMatchingType: (XCUIElementType)type;
/// Its direct children of \a type.
- (XCUIElementQuery *) childrenMatchingType: (XCUIElementType)type;

/// What it was found by, for messages.
- (NSString *) description;
@end

/// The application the tests are running in.
@interface XCUIApplication : XCUIElement
/// The host application (NSApp). Unlike Apple's, there's no -launch or
/// -terminate: `xctest -host` owns its lifetime.
+ (XCUIApplication *) currentApplication;
/// The same as +currentApplication.
- (id) init;
// Its -screenshot is of its key window, or else its main window, or else
// its frontmost one.
@end

/// Screenshots as attachments (PNG, or JPEG for lower qualities).
@interface XCTAttachment (XCUIScreenshot)
+ (instancetype) attachmentWithScreenshot: (XCUIScreenshot *)screenshot;
+ (instancetype) attachmentWithScreenshot: (XCUIScreenshot *)screenshot quality: (XCTImageQuality)quality;
@end

/// A search for elements, below an element, by kind and attributes.
@interface XCUIElementQuery : NSObject <XCUIElementTypeQueryProvider>
{
    // An XCUIElement, or an XCUIElementQuery whose matches are searched.
    id _source;
    XCUIElementType _type;
    BOOL _childrenOnly;
    NSPredicate *_predicate;
    NSString *_predicateDescription;
}

/// How many elements match now.
- (NSUInteger) count;
/// The one element that matches. Using it fails the test if none or
/// several match.
- (XCUIElement *) element;
/// The first match, without checking that it's the only one.
- (XCUIElement *) firstMatch;
/// The match at \a index, in the order the query finds them (windows in
/// NSApp's order, views depth first, menu items in menu order).
- (XCUIElement *) elementBoundByIndex: (NSUInteger)index;
/// Every match, each bound by its index.
- (NSArray *) allElementsBoundByIndex;

/// The one element whose identifier, title or label is \a key:
/// `[[app buttons] objectForKeyedSubscript:@"OK"]`, or `app.buttons[@"OK"]`.
- (XCUIElement *) objectForKeyedSubscript: (NSString *)key;
/// The matches whose identifier is \a identifier.
- (XCUIElementQuery *) matchingIdentifier: (NSString *)identifier;
/// The matches for which \a predicate (over XCUIElementAttributes) is true.
- (XCUIElementQuery *) matchingPredicate: (NSPredicate *)predicate;
/// The matches of \a type whose identifier, title or label is \a identifier.
- (XCUIElementQuery *) matchingType: (XCUIElementType)type identifier: (NSString *)identifier;
/// The one element of \a type whose identifier, title or label is
/// \a identifier.
- (XCUIElement *) elementMatchingType: (XCUIElementType)type identifier: (NSString *)identifier;

/// The descendants of the matches, of \a type.
- (XCUIElementQuery *) descendantsMatchingType: (XCUIElementType)type;
/// The direct children of the matches, of \a type.
- (XCUIElementQuery *) childrenMatchingType: (XCUIElementType)type;

/// What it searches for, for messages.
- (NSString *) description;
@end

#endif
