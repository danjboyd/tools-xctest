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
    XCTAssertEqual([[app.windows[@"Main"] childrenMatchingType:XCUIElementTypeButton] count], (NSUInteger)9);
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

@interface UIScreenshotTests : UIFixtureCase
@end

@implementation UIScreenshotTests

static BOOL UIIsPNG(NSData *data)
{
    static const unsigned char magic[8] = { 0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n' };

    return [data length] > 8 && memcmp([data bytes], magic, 8) == 0;
}

- (void) testAnElementsScreenshotIsItsSize
{
    XCUIApplication *app = [XCUIApplication currentApplication];
    XCUIScreenshot *shot = [app.buttons[@"Increment"] screenshot];
    XCTAttachment *attachment;

    XCTAssertNotNil(shot);
    XCTAssertEqual([[shot image] size].width, 100.0);
    XCTAssertEqual([[shot image] size].height, 24.0);
    XCTAssertTrue(UIIsPNG([shot PNGRepresentation]));
    attachment = [XCTAttachment attachmentWithScreenshot:shot];
    [attachment setName:@"increment"];
    [attachment setLifetime:XCTAttachmentLifetimeKeepAlways];
    [self addAttachment:attachment];
}

- (void) testAWindowsScreenshotCoversItsContent
{
    XCUIApplication *app = [XCUIApplication currentApplication];
    XCUIScreenshot *shot = [app.windows[@"Main"] screenshot];

    XCTAssertNotNil(shot);
    XCTAssertGreaterThanOrEqual([[shot image] size].width, 400.0);
    XCTAssertGreaterThanOrEqual([[shot image] size].height, 330.0);
    XCTAssertTrue(UIIsPNG([shot PNGRepresentation]));
}

// A screenshot is of what's drawn now: the same state gives the same
// image, and a change shows.
- (void) testAScreenshotShowsTheCurrentState
{
    XCUIApplication *app = [XCUIApplication currentApplication];
    XCUIElement *label = app.staticTexts[@"countLabel"];
    NSData *before = [[label screenshot] PNGRepresentation];
    NSData *again = [[label screenshot] PNGRepresentation];
    NSData *after;

    XCTAssertNotNil(before);
    XCTAssertEqualObjects(before, again);
    [app.buttons[@"Increment"] click];
    XCTAssertEqualObjects([label value], @"Count: 1");
    after = [[label screenshot] PNGRepresentation];
    XCTAssertNotNil(after);
    XCTAssertNotEqualObjects(before, after);
}

- (void) testTheApplicationsScreenshotIsOfItsWindow
{
    XCUIScreenshot *shot = [[XCUIApplication currentApplication] screenshot];

    XCTAssertNotNil(shot);
    XCTAssertGreaterThanOrEqual([[shot image] size].width, 400.0);
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

- (void) testClickingADisabledMenuItemFails
{
    XCUIApplication *app = [XCUIApplication currentApplication];

    [app.menuItems[@"Unavailable"] click];
    XCTAssertNotEqualObjects([app.staticTexts[@"alertLabel"] value], @"Unavailable ran",
                             @"the disabled menu item's action ran");
}

- (void) testAMenuItemHasNoScreenshot
{
    XCTAssertNil([[XCUIApplication currentApplication].menuItems[@"Reset"] screenshot]);
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

// Waiting from the test thread lets the main thread run the delayed
// action, rather than the wait spinning the main run loop itself.
- (void) testWaitingForAWindowFromTheTestThread
{
    XCUIApplication *app = [XCUIApplication currentApplication];

    [app.buttons[@"Open Later"] click];
    XCTAssertTrue([app.windows[@"Second"] waitForExistenceWithTimeout:5]);
    [app.menuItems[@"Reset"] click];
    XCTAssertTrue([app.windows[@"Second"] waitForNonExistenceWithTimeout:5]);
}

- (void) testQueriesFromTheTestThread
{
    XCUIApplication *app = [XCUIApplication currentApplication];

    [app.buttons[@"Increment"] click];
    XCTAssertEqualObjects([app.staticTexts[@"countLabel"] value], @"Count: 1");
}

@end

// A sheet runs as a modal session, so it's answered from the UI test thread.
@interface UISheetTests : UIFixtureCase
@end

@implementation UISheetTests

+ (BOOL) runsOnUITestThread
{
    return YES;
}

- (void) testAnsweringASheet
{
    XCUIApplication *app = [XCUIApplication currentApplication];
    XCUIElement *sheet = [app.windows[@"Main"].sheets firstMatch];

    XCTAssertFalse([sheet exists]);
    [app.buttons[@"Show Sheet"] click];
    XCTAssertTrue([sheet waitForExistenceWithTimeout:5]);
    XCTAssertEqual([sheet elementType], XCUIElementTypeSheet);
    XCTAssertEqualObjects([sheet title], @"Changes");
    XCTAssertTrue([sheet.staticTexts[@"Save changes?"] exists]);
    // It's a child of its window, not one of the application's windows.
    XCTAssertEqual([app.windows count], (NSUInteger)1);
    XCTAssertEqual([app.sheets count], (NSUInteger)1);
    XCTAssertEqual([[app.windows[@"Main"] childrenMatchingType:XCUIElementTypeSheet] count], (NSUInteger)1);
    [sheet.buttons[@"Done"] click];
    XCTAssertTrue([sheet waitForNonExistenceWithTimeout:5]);
    XCTAssertTrue([app.staticTexts[@"Sheet: Done"] waitForExistenceWithTimeout:5]);
}

- (void) testDismissingASheetWithItsOtherButton
{
    XCUIApplication *app = [XCUIApplication currentApplication];

    [app.buttons[@"Show Sheet"] click];
    XCTAssertTrue([app.sheets[@"Changes"] waitForExistenceWithTimeout:5]);
    [app.sheets[@"Changes"].buttons[@"Discard"] click];
    XCTAssertTrue([app.sheets[@"Changes"] waitForNonExistenceWithTimeout:5]);
    XCTAssertTrue([app.staticTexts[@"Sheet: Discard"] waitForExistenceWithTimeout:5]);
}

@end
