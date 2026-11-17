// Run by Tests/run-ui-tests.sh in Tests/UIHostApp (xctest -host).
// UIElementTests and UIActionTests run on the main thread, UIAlertTests on
// the UI test thread. UIFailureTests is run on its own: each of its tests
// is meant to fail, with the message the script checks.

#import <AppKit/AppKit.h>
#import <XCTest/XCTest.h>
#import <XCTest/XCUI.h>

// Every test starts from the state at launch.
@interface UIFixtureCase : XCTestCase
@end

@implementation UIFixtureCase

- (void) setUp
{
    XCUIApplication *app = [XCUIApplication currentApplication];

    [super setUp];
    [app.menuItems[@"Reset"] click];
}

@end

@interface UIElementTests : UIFixtureCase
@end

@implementation UIElementTests

- (void) testFindsTheWindow
{
    XCUIApplication *app = [XCUIApplication currentApplication];

    XCTAssertTrue([app exists]);
    XCTAssertEqual([app elementType], XCUIElementTypeApplication);
    XCTAssertEqual([app.windows count], (NSUInteger)1);
    XCTAssertTrue([app.windows[@"Main"] exists]);
    XCTAssertEqualObjects([app.windows[@"Main"] title], @"Main");
    XCTAssertFalse([app.windows[@"Second"] exists]);
}

- (void) testFindsControlsByTitleAndIdentifier
{
    XCUIApplication *app = [XCUIApplication currentApplication];
    XCUIElement *window = app.windows[@"Main"];

    XCTAssertTrue([window.buttons[@"Increment"] exists]);
    XCTAssertTrue([window.buttons[@"incrementButton"] exists]);
    XCTAssertEqualObjects([[[app.buttons matchingIdentifier:@"incrementButton"] element] label], @"Increment");
    XCTAssertEqual([[app.buttons matchingIdentifier:@"nope"] count], (NSUInteger)0);
    XCTAssertEqual([[app.buttons matchingPredicate:[NSPredicate predicateWithFormat:@"title BEGINSWITH 'Incr'"]] count],
                   (NSUInteger)1);
    XCTAssertEqual([[app.buttons matchingPredicate:[NSPredicate predicateWithFormat:@"title == 'Twin'"]] count],
                   (NSUInteger)2);
    XCTAssertEqualObjects([[[app.buttons matchingIdentifier:@"twinB"] firstMatch] identifier], @"twinB");
    XCTAssertEqualObjects([[app.buttons elementBoundByIndex:0] title], @"Increment");
    XCTAssertTrue([[[app descendantsMatchingType:XCUIElementTypeAny] elementMatchingType:XCUIElementTypeStaticText identifier:@"countLabel"] exists]);
}

- (void) testElementTypes
{
    XCUIApplication *app = [XCUIApplication currentApplication];

    XCTAssertEqual([app.buttons[@"Increment"] elementType], XCUIElementTypeButton);
    XCTAssertEqual([app.checkBoxes[@"Remember me"] elementType], XCUIElementTypeCheckBox);
    XCTAssertEqual([app.radioButtons[@"Small"] elementType], XCUIElementTypeRadioButton);
    XCTAssertEqual([app.popUpButtons[@"colourPopUp"] elementType], XCUIElementTypePopUpButton);
    XCTAssertEqual([app.textFields[@"nameField"] elementType], XCUIElementTypeTextField);
    XCTAssertEqual([app.secureTextFields[@"passwordField"] elementType], XCUIElementTypeSecureTextField);
    XCTAssertEqual([app.staticTexts[@"countLabel"] elementType], XCUIElementTypeStaticText);
    XCTAssertEqual([app.menuBarItems[@"Actions"] elementType], XCUIElementTypeMenuBarItem);
    XCTAssertEqual([app.menuItems[@"Reset"] elementType], XCUIElementTypeMenuItem);
    XCTAssertEqual([app.textFields count], (NSUInteger)1);
    XCTAssertEqual([[app.windows[@"Main"] childrenMatchingType:XCUIElementTypeButton] count], (NSUInteger)8);
}

- (void) testValues
{
    XCUIApplication *app = [XCUIApplication currentApplication];

    XCTAssertEqualObjects([app.staticTexts[@"countLabel"] value], @"Count: 0");
    XCTAssertEqualObjects([app.staticTexts[@"countLabel"] label], @"Count: 0");
    XCTAssertTrue([app.staticTexts[@"Count: 0"] exists]);
    XCTAssertEqualObjects([app.checkBoxes[@"Remember me"] value], [NSNumber numberWithInt:0]);
    XCTAssertEqualObjects([app.popUpButtons[@"colourPopUp"] value], @"Red");
    XCTAssertEqualObjects([app.textFields[@"nameField"] placeholderValue], @"Name");
    XCTAssertEqualObjects([app.textFields[@"nameField"] value], @"");
}

- (void) testHittability
{
    XCUIApplication *app = [XCUIApplication currentApplication];

    XCTAssertTrue([app.buttons[@"Increment"] isHittable]);
    XCTAssertTrue([app.buttons[@"Disabled"] exists]);
    XCTAssertFalse([app.buttons[@"Disabled"] isEnabled]);
    XCTAssertFalse([app.buttons[@"Disabled"] isHittable]);
    XCTAssertTrue([app.buttons[@"Hidden"] exists]);
    XCTAssertFalse([app.buttons[@"Hidden"] isHittable]);
    XCTAssertTrue([app.buttons[@"Outside"] exists]);
    XCTAssertFalse([app.buttons[@"Outside"] isHittable]);
    XCTAssertTrue([app.menuItems[@"Reset"] isHittable]);
    XCTAssertFalse([app.menuItems[@"Unavailable"] isEnabled]);
}

- (void) testMenuBarItemsHoldTheirMenus
{
    XCUIApplication *app = [XCUIApplication currentApplication];

    XCTAssertEqual([app.menuBarItems count], (NSUInteger)1);
    XCTAssertEqual([app.menuBarItems[@"Actions"].menuItems count], (NSUInteger)2);
}

@end

@interface UIActionTests : UIFixtureCase
@end

@implementation UIActionTests

- (void) testClickSendsTheAction
{
    XCUIApplication *app = [XCUIApplication currentApplication];

    [app.buttons[@"Increment"] click];
    [app.buttons[@"Increment"] click];
    XCTAssertEqualObjects([app.staticTexts[@"countLabel"] value], @"Count: 2");
}

- (void) testClickTogglesACheckBox
{
    XCUIApplication *app = [XCUIApplication currentApplication];

    [app.checkBoxes[@"Remember me"] click];
    XCTAssertEqualObjects([app.checkBoxes[@"Remember me"] value], [NSNumber numberWithInt:1]);
    XCTAssertTrue([app.checkBoxes[@"Remember me"] isSelected]);
}

- (void) testMenuItemClickPerformsItsAction
{
    XCUIApplication *app = [XCUIApplication currentApplication];

    [app.buttons[@"Increment"] click];
    XCTAssertEqualObjects([app.staticTexts[@"countLabel"] value], @"Count: 1");
    [app.menuItems[@"Reset"] click];
    XCTAssertEqualObjects([app.staticTexts[@"countLabel"] value], @"Count: 0");
}

- (void) testTypingIntoATextField
{
    XCUIApplication *app = [XCUIApplication currentApplication];
    XCUIElement *name = app.textFields[@"nameField"];

    [name click];
    XCTAssertTrue([name hasFocus]);
    [name typeText:@"Ada"];
    XCTAssertEqualObjects([name value], @"Ada");
    [name typeText:@"\n"];
    XCTAssertEqualObjects([app.staticTexts[@"greetingLabel"] value], @"Hello, Ada");
}

- (void) testWaitingForAWindow
{
    XCUIApplication *app = [XCUIApplication currentApplication];

    [app.buttons[@"Open Later"] click];
    XCTAssertFalse([app.windows[@"Second"] exists]);
    XCTAssertTrue([app.windows[@"Second"] waitForExistenceWithTimeout:5]);
    XCTAssertEqual([app.windows count], (NSUInteger)2);
    [app.menuItems[@"Reset"] click];
    XCTAssertTrue([app.windows[@"Second"] waitForNonExistenceWithTimeout:5]);
    XCTAssertFalse([app.buttons[@"Nope"] waitForExistenceWithTimeout:0.2]);
}

@end

// Each test fails, with the message the script checks.
@interface UIFailureTests : UIFixtureCase
@end

@implementation UIFailureTests

- (void) testClickingADisabledButtonFails
{
    [[XCUIApplication currentApplication].buttons[@"Disabled"] click];
}

- (void) testClickingAHiddenButtonFails
{
    [[XCUIApplication currentApplication].buttons[@"Hidden"] click];
}

- (void) testAMissingElementFails
{
    (void)[[XCUIApplication currentApplication].buttons[@"Nope"] label];
}

- (void) testAnAmbiguousQueryFails
{
    [[XCUIApplication currentApplication].buttons[@"Twin"] click];
}

@end

// On the UI test thread, a click that opens an alert returns while the
// alert's modal loop runs, and the test answers it.
@interface UIAlertTests : UIFixtureCase
@end

@implementation UIAlertTests

+ (BOOL) runsOnUITestThread
{
    return YES;
}

- (void) testAnsweringAnAlert
{
    XCUIApplication *app = [XCUIApplication currentApplication];

    XCTAssertFalse([NSThread isMainThread]);
    [app.buttons[@"Show Alert"] click];
    XCTAssertTrue([app.buttons[@"OK"] waitForExistenceWithTimeout:5]);
    XCTAssertTrue([app.staticTexts[@"Are you sure?"] exists]);
    [app.buttons[@"Cancel"] click];
    XCTAssertTrue([app.staticTexts[@"Alert: Cancel"] waitForExistenceWithTimeout:5]);
    XCTAssertFalse([app.buttons[@"OK"] exists]);
}

- (void) testQueriesFromTheTestThread
{
    XCUIApplication *app = [XCUIApplication currentApplication];

    [app.buttons[@"Increment"] click];
    XCTAssertEqualObjects([app.staticTexts[@"countLabel"] value], @"Count: 1");
}

@end
