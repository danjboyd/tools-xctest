#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

// Logs observation events for the Observed* classes. Registered by the
// bundle's principal class, which xctest creates before running tests.
@interface FixtureObserver : NSObject <XCTestObservation>
@end

@implementation FixtureObserver

- (BOOL)isObserved:(NSString *)name
{
    return [name rangeOfString:@"Observed"].location != NSNotFound;
}

- (void)testBundleWillStart:(NSBundle *)testBundle
{
    NSLog(@"observer: bundle will start %@", [[testBundle bundlePath] lastPathComponent]);
}

- (void)testBundleDidFinish:(NSBundle *)testBundle
{
    NSLog(@"observer: bundle did finish %@", [[testBundle bundlePath] lastPathComponent]);
}

- (void)testSuiteWillStart:(XCTestSuite *)testSuite
{
    if ([self isObserved:[testSuite name]]) {
        NSLog(@"observer: suite will start %@ (%lu tests)", [testSuite name], (unsigned long)[testSuite testCaseCount]);
    }
}

- (void)testSuiteDidFinish:(XCTestSuite *)testSuite
{
    if ([self isObserved:[testSuite name]]) {
        XCTestRun *run = [testSuite testRun];
        NSLog(@"observer: suite did finish %@ executed=%lu failures=%lu unexpected=%lu skipped=%lu succeeded=%d",
              [testSuite name], (unsigned long)[run executionCount], (unsigned long)[run failureCount],
              (unsigned long)[run unexpectedExceptionCount], (unsigned long)[run skipCount], [run hasSucceeded]);
    }
}

- (void)testCaseWillStart:(XCTestCase *)testCase
{
    if ([self isObserved:[testCase name]]) {
        NSLog(@"observer: case will start %@", [testCase name]);
    }
}

- (void)testCase:(XCTestCase *)testCase didFailWithDescription:(NSString *)description inFile:(NSString *)filePath atLine:(NSUInteger)lineNumber
{
    if ([self isObserved:[testCase name]]) {
        NSLog(@"observer: case failed %@: %@", [testCase name], description);
    }
}

- (void)testCaseDidFinish:(XCTestCase *)testCase
{
    if ([self isObserved:[testCase name]]) {
        NSLog(@"observer: case did finish %@ succeeded=%d skipped=%d",
              [testCase name], [[testCase testRun] hasSucceeded], [[testCase testRun] hasBeenSkipped]);
    }
}

@end

@interface FixtureObserverRegistrar : NSObject
@end

@implementation FixtureObserverRegistrar

- (id)init
{
    self = [super init];
    if (self) {
        FixtureObserver *observer = [[[FixtureObserver alloc] init] autorelease];
        [[XCTestObservationCenter sharedTestObservationCenter] addTestObserver:observer];
        NSLog(@"fixture: principal class created");
    }
    return self;
}

@end

@interface ObservedTests : XCTestCase
@end

@implementation ObservedTests

- (void)testFails { XCTFail(@"observed failure"); }
- (void)testPasses { }
- (void)testSkips { XCTSkip(@"observed skip"); }
- (void)testThrows { [NSException raise:NSInternalInconsistencyException format:@"observed exception"]; }

@end

// An abstract base: its tests only run in subclasses.
@interface AbstractBaseTests : XCTestCase
@end

@implementation AbstractBaseTests

+ (XCTestSuite *)defaultTestSuite
{
    if (self == [AbstractBaseTests class]) {
        return [XCTestSuite testSuiteWithName:NSStringFromClass(self)];
    }
    return [super defaultTestSuite];
}

- (void)testShared { NSLog(@"fixture: %@ testShared", NSStringFromClass([self class])); }

@end

@interface ConcreteTests : AbstractBaseTests
@end

@implementation ConcreteTests
@end

// Changes which methods are tests.
@interface CustomInvocationTests : XCTestCase
@end

@implementation CustomInvocationTests

+ (NSArray *)testInvocations
{
    NSMutableArray *invocations = [NSMutableArray array];

    for (NSInvocation *invocation in [super testInvocations]) {
        if ([invocation selector] != @selector(testDisabled)) {
            [invocations addObject:invocation];
        }
    }

    SEL extra = @selector(verifyExtra);
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[self instanceMethodSignatureForSelector:extra]];
    [invocation setSelector:extra];
    [invocations addObject:invocation];
    return invocations;
}

- (void)testDisabled { NSLog(@"fixture: CustomInvocationTests testDisabled ran"); }
- (void)testEnabled { NSLog(@"fixture: CustomInvocationTests testEnabled ran"); }
- (void)verifyExtra { NSLog(@"fixture: CustomInvocationTests verifyExtra ran"); }

@end

// Sees every failure through -recordFailureWithDescription:..., and drops
// the ones marked as ignorable.
@interface RecordFailureOverrideTests : XCTestCase
@end

@implementation RecordFailureOverrideTests

- (void)recordFailureWithDescription:(NSString *)description inFile:(NSString *)filePath atLine:(NSUInteger)lineNumber expected:(BOOL)expected
{
    NSLog(@"fixture: recordFailure saw '%@' expected=%d", description, expected);
    if ([description rangeOfString:@"ignorable"].location != NSNotFound) {
        return;
    }
    [super recordFailureWithDescription:description inFile:filePath atLine:lineNumber expected:expected];
}

- (void)testIgnoredFailure { XCTFail(@"ignorable"); }
- (void)testRecordedFailure { XCTFail(@"real failure"); }

@end

// Not run by xctest (empty default suite); run by ProgrammaticTests.
@interface InnerTests : XCTestCase
@end

@implementation InnerTests

+ (XCTestSuite *)defaultTestSuite
{
    return [XCTestSuite testSuiteWithName:NSStringFromClass(self)];
}

- (void)testInnerPasses { NSLog(@"fixture: InnerTests testInnerPasses ran"); }
- (void)testInnerSkips { XCTSkip(); }

@end

@interface ProgrammaticTests : XCTestCase
@end

@implementation ProgrammaticTests

- (void)testNameAndRun
{
    XCTAssertEqualObjects([self name], @"-[ProgrammaticTests testNameAndRun]");
    XCTAssertEqual([self testCaseCount], (NSUInteger)1);
    XCTAssertNotNil([self testRun]);
    XCTAssertTrue([[self testRun] isKindOfClass:[XCTestCaseRun class]]);
    XCTAssertNotNil([[self testRun] startDate]);
    XCTAssertEqualObjects(NSStringFromSelector([[self invocation] selector]), @"testNameAndRun");
}

- (void)testDefaultTestSuite
{
    XCTestSuite *suite = [ProgrammaticTests defaultTestSuite];
    XCTAssertEqualObjects([suite name], @"ProgrammaticTests");
    XCTAssertEqual([suite testCaseCount], (NSUInteger)3);
    XCTAssertEqual([[ProgrammaticTests testInvocations] count], (NSUInteger)3);
    XCTAssertEqual([[AbstractBaseTests defaultTestSuite] testCaseCount], (NSUInteger)0);
    XCTAssertEqual([[ConcreteTests defaultTestSuite] testCaseCount], (NSUInteger)1);
    XCTAssertEqual([[XCTestSuite testSuiteForTestCaseWithName:@"InnerTests/testInnerPasses"] testCaseCount], (NSUInteger)1);
}

- (void)testRunSuiteProgrammatically
{
    XCTestSuite *suite = [XCTestSuite testSuiteWithName:@"inner"];
    [suite addTest:[InnerTests testCaseWithSelector:@selector(testInnerPasses)]];
    [suite addTest:[InnerTests testCaseWithSelector:@selector(testInnerSkips)]];

    [suite runTest];

    XCTestSuiteRun *run = (XCTestSuiteRun *)[suite testRun];
    XCTAssertEqual([run testCaseCount], (NSUInteger)2);
    XCTAssertEqual([run executionCount], (NSUInteger)2);
    XCTAssertEqual([run skipCount], (NSUInteger)1);
    XCTAssertEqual([run totalFailureCount], (NSUInteger)0);
    XCTAssertTrue([run hasSucceeded]);
    XCTAssertEqual([[run testRuns] count], (NSUInteger)2);
    XCTAssertGreaterThanOrEqual([run totalDuration], [run testDuration]);

    // This test is still the current one after running others.
    XCTAssertEqualObjects([self name], @"-[ProgrammaticTests testRunSuiteProgrammatically]");
}

@end

// Only void methods are tests (as in Apple's XCTest).
@interface GetterTests : XCTestCase {
    NSString *_testData;
}
@property (copy) NSString *testData;
@end

@implementation GetterTests

@synthesize testData = _testData;

- (void)dealloc { [_testData release]; [super dealloc]; }
- (NSRect)testFrame { return NSMakeRect(1, 2, 3, 4); }
- (BOOL)testReturnsBool { return YES; }
- (oneway void)testOnewayVoid { }
- (void)testReal { }

@end

// Its +setUp fails only when ProgrammaticTests asks it to, and its default
// suite nests another suite.
static BOOL failNestedSetUp = NO;

@interface NestedSuiteTests : XCTestCase
@end

@implementation NestedSuiteTests

+ (XCTestSuite *)defaultTestSuite
{
    XCTestSuite *suite = [super defaultTestSuite];
    XCTestSuite *nested = [XCTestSuite testSuiteWithName:@"nested"];

    [nested addTest:[InnerTests testCaseWithSelector:@selector(testInnerPasses)]];
    [suite addTest:nested];
    return suite;
}

+ (void)setUp
{
    if (failNestedSetUp) {
        [NSException raise:NSInternalInconsistencyException format:@"nested +setUp failure"];
    }
}

- (void)testOwn { }

@end

@interface NestedSuiteRunTests : XCTestCase
@end

@implementation NestedSuiteRunTests

- (void)testSkippedCountsAcrossNestedSuites
{
    XCTestSuite *outer = [XCTestSuite testSuiteWithName:@"outer"];
    XCTestSuite *inner = [XCTestSuite testSuiteWithName:@"inner"];

    // One of two nested test cases skipped: the outer suite isn't skipped.
    [inner addTest:[InnerTests testCaseWithSelector:@selector(testInnerPasses)]];
    [inner addTest:[InnerTests testCaseWithSelector:@selector(testInnerSkips)]];
    [outer addTest:inner];
    [outer runTest];
    XCTAssertFalse([[outer testRun] hasBeenSkipped]);
    XCTAssertEqual([[outer testRun] skipCount], (NSUInteger)1);
    XCTAssertEqual([[outer testRun] executionCount], (NSUInteger)2);

    // Every nested test case skipped: it is.
    XCTestSuite *allSkipped = [XCTestSuite testSuiteWithName:@"all skipped"];
    XCTestSuite *skippedInner = [XCTestSuite testSuiteWithName:@"skipped inner"];
    [skippedInner addTest:[InnerTests testCaseWithSelector:@selector(testInnerSkips)]];
    [skippedInner addTest:[InnerTests testCaseWithSelector:@selector(testInnerSkips)]];
    [allSkipped addTest:skippedInner];
    [allSkipped runTest];
    XCTAssertTrue([[allSkipped testRun] hasBeenSkipped]);
}

- (void)testFailedSetUpWithNestedSuite
{
    XCTestSuite *suite = [NestedSuiteTests defaultTestSuite];

    failNestedSetUp = YES;
    [suite runTest];
    failNestedSetUp = NO;

    // Both test cases (one inside the nested suite) failed without running.
    XCTAssertEqual([[suite testRun] testCaseCount], (NSUInteger)2);
    XCTAssertEqual([[suite testRun] executionCount], (NSUInteger)2);
    XCTAssertEqual([[suite testRun] totalFailureCount], (NSUInteger)3);  // +setUp, and each test
    XCTAssertFalse([[suite testRun] hasSucceeded]);
}

@end
