#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

// "IssueFixture.m:42" for an issue's location, or "-" if it has none.
static NSString *FixtureLocation(XCTIssue *issue)
{
    XCTSourceCodeLocation *location = [[issue sourceCodeContext] location];

    if (location == nil) {
        return @"-";
    }
    return [NSString stringWithFormat:@"%@:%ld", [[location fileURL] lastPathComponent], (long)[location lineNumber]];
}

// Logs the issues observers are told about.
@interface IssueObserver : NSObject <XCTestObservation>
@end

@implementation IssueObserver

- (void)testCase:(XCTestCase *)testCase didRecordIssue:(XCTIssue *)issue
{
    NSLog(@"observer: %@ issue type=%d '%@'", [testCase name], (int)[issue type], [issue compactDescription]);
}

- (void)testSuite:(XCTestSuite *)testSuite didRecordIssue:(XCTIssue *)issue
{
    NSLog(@"observer: suite %@ issue type=%d '%@'", [testSuite name], (int)[issue type], [issue compactDescription]);
}

@end

@interface IssueObserverRegistrar : NSObject
@end

@implementation IssueObserverRegistrar

- (id)init
{
    self = [super init];
    if (self) {
        [[XCTestObservationCenter sharedTestObservationCenter]
            addTestObserver:[[[IssueObserver alloc] init] autorelease]];
    }
    return self;
}

@end

// -recordIssue: sees every kind of issue, and can drop or change them.
@interface RecordIssueOverrideTests : XCTestCase
@end

@implementation RecordIssueOverrideTests

- (void)recordIssue:(XCTIssue *)issue
{
    NSLog(@"fixture: recordIssue %@ type=%d at %@ '%@'", [self name], (int)[issue type],
          FixtureLocation(issue), [issue compactDescription]);

    if ([[issue compactDescription] rangeOfString:@"ignorable"].location != NSNotFound) {
        return;
    }
    if ([[issue compactDescription] rangeOfString:@"rewrite me"].location != NSNotFound) {
        XCTMutableIssue *changed = [[issue mutableCopy] autorelease];
        [changed setCompactDescription:@"rewritten by recordIssue:"];
        issue = changed;
    }
    [super recordIssue:issue];
}

- (void)testAssertionFails { XCTAssertEqual(1, 2); }
- (void)testThrows { [NSException raise:NSInternalInconsistencyException format:@"fixture exception"]; }
- (void)testIgnoredFailure { XCTFail(@"ignorable"); }
- (void)testRewrittenFailure { XCTFail(@"rewrite me"); }

- (void)testRecordsIssueDirectly
{
    XCTSourceCodeLocation *location = [[[XCTSourceCodeLocation alloc] initWithFilePath:@"Custom.m" lineNumber:7] autorelease];
    XCTSourceCodeContext *context = [[[XCTSourceCodeContext alloc] initWithLocation:location] autorelease];
    XCTIssue *issue = [[[XCTIssue alloc] initWithType:XCTIssueTypeSystem
                                   compactDescription:@"recorded directly"
                                  detailedDescription:@"recorded directly, in detail"
                                    sourceCodeContext:context
                                      associatedError:nil] autorelease];
    [self recordIssue:issue];
}

@end

// A failing -setUpWithError: is a thrown-error issue carrying the error.
@interface SetUpErrorTests : XCTestCase
@end

@implementation SetUpErrorTests

- (BOOL)setUpWithError:(NSError **)error
{
    *error = [NSError errorWithDomain:@"FixtureDomain" code:42
                             userInfo:[NSDictionary dictionaryWithObject:@"set up broke"
                                                                  forKey:NSLocalizedDescriptionKey]];
    return NO;
}

- (void)recordIssue:(XCTIssue *)issue
{
    NSLog(@"fixture: setUpWithError issue type=%d error=%@/%ld", (int)[issue type],
          [[issue associatedError] domain], (long)[[issue associatedError] code]);
    [super recordIssue:issue];
}

- (void)testNeverRuns { NSLog(@"fixture: SetUpErrorTests body ran"); }

@end

// Overriding both methods: each sees an issue once.
@interface BothOverridesTests : XCTestCase
@end

@implementation BothOverridesTests

- (void)recordIssue:(XCTIssue *)issue
{
    NSLog(@"fixture: both recordIssue '%@'", [issue compactDescription]);
    [super recordIssue:issue];
}

- (void)recordFailureWithDescription:(NSString *)description inFile:(NSString *)filePath atLine:(NSUInteger)lineNumber expected:(BOOL)expected
{
    NSLog(@"fixture: both recordFailure '%@'", description);
    [super recordFailureWithDescription:[description stringByAppendingString:@" (legacy edit)"]
                                 inFile:filePath atLine:lineNumber expected:expected];
}

- (void)testAssertion { XCTFail(@"from assertion"); }

- (void)testDirectLegacyCall
{
    [self recordFailureWithDescription:@"from legacy call" inFile:@"Legacy.m" atLine:3 expected:YES];
}

@end

// XCTExpectFailure matchers get the issue's type and location.
@interface IssueMatcherTests : XCTestCase
@end

@implementation IssueMatcherTests

- (void)testMatcherSeesTypeAndLocation
{
    XCTExpectedFailureOptions *options = [[[XCTExpectedFailureOptions alloc] init] autorelease];
    [options setIssueMatcher:^BOOL(XCTIssue *issue) {
        NSLog(@"fixture: matcher type=%d at %@", (int)[issue type], FixtureLocation(issue));
        return [issue type] == XCTIssueTypeAssertionFailure && [[issue sourceCodeContext] location] != nil;
    }];
    XCTExpectFailureWithOptions(@"known bug", options);
    XCTFail(@"expected one");
}

- (void)testUnmatchedExpectedFailureType
{
    XCTExpectFailure(@"never fails");
}

- (void)recordIssue:(XCTIssue *)issue
{
    NSLog(@"fixture: matcher-test recordIssue type=%d '%@'", (int)[issue type], [issue compactDescription]);
    [super recordIssue:issue];
}

@end

// Copying: XCTIssue copies are immutable, mutable copies are XCTMutableIssue.
@interface IssueCopyingTests : XCTestCase
@end

@implementation IssueCopyingTests

- (void)testCopies
{
    XCTIssue *issue = [[[XCTIssue alloc] initWithType:XCTIssueTypeAssertionFailure compactDescription:@"a"] autorelease];
    XCTMutableIssue *mutable = [[issue mutableCopy] autorelease];

    XCTAssertTrue([mutable isKindOfClass:[XCTMutableIssue class]]);
    [mutable setCompactDescription:@"b"];
    [mutable setType:XCTIssueTypeSystem];
    XCTAssertEqualObjects([issue compactDescription], @"a");
    XCTAssertEqualObjects([issue detailedDescription], @"a");
    XCTAssertNotNil([issue sourceCodeContext]);
    XCTAssertNil([[issue sourceCodeContext] location]);

    XCTIssue *copy = [[mutable copy] autorelease];
    XCTAssertFalse([copy isKindOfClass:[XCTMutableIssue class]]);
    XCTAssertEqualObjects([copy compactDescription], @"b");
    XCTAssertEqual([copy type], XCTIssueTypeSystem);
}

@end
