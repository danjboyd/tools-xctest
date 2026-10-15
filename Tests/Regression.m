#import <XCTest/XCTest.h>
#import <XCTest/GSXCTestRunner.h>
#import <XCTest/GSXCTestReporting.h>
#import <XCTest/GSXCTStatistics.h>
#include <limits.h>
#include <math.h>
#include <stdlib.h>

static int checks, errors;
#define CHECK(condition) do { checks++; if (!(condition)) { errors++; NSLog(@"CHECK FAILED %s:%d: %s", __FILE__, __LINE__, #condition); } } while (0)
static void Throw(void) { [NSException raise:@"Example" format:@"example reason"]; }
static int ThrowInt(void) { Throw(); return 0; }
static void ThrowObject(void) { @throw @"not an NSException"; }

@interface Probe : XCTestCase { @public NSMutableArray *messages; NSUInteger unexpected; }
@end
@implementation Probe
- (id)init { if ((self = [super init])) messages = [NSMutableArray new]; return self; }
- (void)dealloc { [messages release]; [super dealloc]; }
- (void)recordFailureWithDescription:(NSString *)description inFile:(NSString *)file atLine:(NSUInteger)line expected:(BOOL)expected
{
    CHECK([file hasSuffix:@"Regression.m"]);
    CHECK(line > 0);
    if (!expected) unexpected++;
    [messages addObject:description];
}
- (void)checkAssertions
{
    int sideEffects = 0;
    XCTAssertEqual(++sideEffects, 1);
    CHECK(sideEffects == 1);
    XCTAssertTrue(YES); XCTAssert(1); XCTAssertFalse(NO);
    XCTAssertNil(nil); XCTAssertNotNil(@"x");
    XCTAssertEqualObjects(nil, nil); XCTAssertEqualObjects(@"x", ([NSString stringWithFormat:@"%@", @"x"]));
    XCTAssertNotEqualObjects(nil, @"x");
    XCTAssertNotEqual(1, 2);
    XCTAssertGreaterThan(2, 1); XCTAssertGreaterThanOrEqual(1, 1);
    XCTAssertLessThan(1, 2); XCTAssertLessThanOrEqual(1, 1);
    XCTAssertEqualWithAccuracy(3, 4, 1);
    XCTAssertEqualWithAccuracy(INFINITY, INFINITY, 0);
    XCTAssertNotEqualWithAccuracy(INT_MIN, INT_MAX, 1);
    XCTAssertNotEqualWithAccuracy(NAN, 1, 0);
    XCTAssertThrows(Throw()); XCTAssertThrows(ThrowObject());
    XCTAssertThrowsSpecific(Throw(), NSException);
    XCTAssertThrowsSpecificNamed(Throw(), NSException, @"Example");
    XCTAssertNoThrow((void)0);
    XCTAssertNoThrowSpecific((void)0, NSException);
    XCTAssertNoThrowSpecificNamed(Throw(), NSException, @"Other");
    CHECK([messages count] == 0);

    XCTFail(); XCTAssertNil(@"value"); XCTAssertNotNil(nil);
    XCTAssertFalse(YES); XCTAssertTrue(NO); XCTAssert(NO);
    XCTAssertEqualObjects(@"a", @"b"); XCTAssertNotEqualObjects(nil, nil);
    NSString *format = @"detail %d";
    XCTAssertEqual(17, 23, format, 42);
    CHECK([[messages lastObject] rangeOfString:@"(\"17\") is not equal to (\"23\")"].location != NSNotFound);
    CHECK([[messages lastObject] rangeOfString:@"detail 42"].location != NSNotFound);
    XCTAssertNotEqual(2, 2);
    XCTAssertGreaterThan(NAN, 1.0); XCTAssertGreaterThanOrEqual(NAN, 1.0);
    XCTAssertLessThan(NAN, 1.0); XCTAssertLessThanOrEqual(NAN, 1.0);
    XCTAssertEqualWithAccuracy(NAN, 1, 1);
    XCTAssertEqualWithAccuracy(1, 1, NAN);
    XCTAssertEqualWithAccuracy(1, 1, -1);
    XCTAssertNotEqualWithAccuracy(INFINITY, INFINITY, 0);
    XCTAssertThrows((void)0);
    XCTAssertThrowsSpecific((void)0, NSException);
    XCTAssertThrowsSpecificNamed(Throw(), NSException, @"Other");
    XCTAssertNoThrow(Throw());
    XCTAssertNoThrowSpecific(Throw(), NSException);
    XCTAssertNoThrowSpecificNamed(Throw(), NSException, @"Example");
    CHECK(unexpected == 0);
    /* An exception from an assertion's arguments is an unexpected failure. */
    XCTAssertEqual(ThrowInt(), 1);
    CHECK(unexpected == 1);
    CHECK([[messages lastObject] rangeOfString:@"example reason"].location != NSNotFound);
    CHECK([messages count] == 25);
}
@end

static int setups, teardowns, bodies, classSetups, classTeardowns;
@interface Lifecycle : XCTestCase @end
@implementation Lifecycle
+ (void)setUp { classSetups++; }
+ (void)tearDown { classTeardowns++; }
- (void)setUp { setups++; }
- (void)tearDown { teardowns++; }
- (void)testPass { bodies++; }
- (void)testThrow { Throw(); }
- (void)testStop { self.continueAfterFailure = NO; XCTAssertTrue(NO); bodies++; }
- (void)testContinue { XCTFail(); bodies++; XCTFail(); }
- (void)testNestedStop { self.continueAfterFailure = NO; XCTAssertThrows(({ XCTFail(); })); bodies++; }
- (int)testInvalidReturn { abort(); return 1; }
- (void)testInvalidArgument:(id)arg { abort(); }
@end
@interface Inherited : Lifecycle @end
@implementation Inherited
- (void)testPass { bodies += 10; }
@end
@interface SetupFailure : Lifecycle @end
@implementation SetupFailure
- (void)setUp { Throw(); }
@end
@interface TeardownFailure : Lifecycle @end
@implementation TeardownFailure
- (void)tearDown { teardowns++; Throw(); }
@end
@interface ClassFailure : Lifecycle @end
@implementation ClassFailure
+ (void)setUp { Throw(); }
@end

@interface Async : XCTestCase @end
@implementation Async
- (void)testPredicateSuccess
{
    NSMutableDictionary *state = [NSMutableDictionary dictionaryWithObject:@NO forKey:@"ready"];
    [self expectationForPredicate:[NSPredicate predicateWithFormat:@"ready == YES"] evaluatedWithObject:state handler:nil];
    [state setObject:@YES forKey:@"ready"];
    [self waitForExpectationsWithTimeout:0.1 handler:nil];
}
- (void)testPredicateHandler
{
    __block NSUInteger calls = 0;
    [self expectationForPredicate:[NSPredicate predicateWithValue:YES] evaluatedWithObject:nil handler:^BOOL {
        return ++calls == 2;
    }];
    [self waitForExpectationsWithTimeout:0.2 handler:nil];
    CHECK(calls == 2);
}
- (void)testPredicateTimeout
{
    __block BOOL called = NO;
    [self expectationForPredicate:[NSPredicate predicateWithValue:NO] evaluatedWithObject:nil handler:^BOOL {
        called = YES; return YES;
    }];
    [self waitForExpectationsWithTimeout:0.01 handler:nil];
    CHECK(!called);
}
- (void)testPredicateInverted
{
    XCTestExpectation *expectation = [self expectationForPredicate:[NSPredicate predicateWithValue:YES] evaluatedWithObject:nil handler:nil];
    expectation.inverted = YES;
    [self waitForExpectationsWithTimeout:0.1 handler:nil];
}
- (void)testSuccess
{
    XCTestExpectation *e = [self expectationWithDescription:@"timer"];
    e.expectedFulfillmentCount = 2;
    [e fulfill];
    [e performSelector:@selector(fulfill) withObject:nil afterDelay:0.001];
    __block BOOL called = NO;
    [self waitForExpectationsWithTimeout:0.2 handler:^(NSError *error) { called = YES; CHECK(error == nil); }];
    CHECK(called);
}
- (void)fulfillInBackground:(XCTestExpectation *)expectation
{
    @autoreleasepool { [expectation fulfill]; }
}
- (void)testBackground
{
    XCTestExpectation *e = [self expectationWithDescription:@"background"];
    [NSThread detachNewThreadSelector:@selector(fulfillInBackground:) toTarget:self withObject:e];
    [self waitForExpectationsWithTimeout:1 handler:nil];
}
- (void)testSequential
{
    for (int i = 0; i < 2; i++) {
        XCTestExpectation *e = [self expectationWithDescription:@"sequence"];
        [e fulfill];
        [self waitForExpectationsWithTimeout:0 handler:nil];
    }
}
- (void)testStoppedTimeout
{
    self.continueAfterFailure = NO;
    [self expectationWithDescription:@"missing"];
    [self waitForExpectationsWithTimeout:0 handler:^(NSError *error) { CHECK(error != nil); }];
    CHECK(NO);
}
- (void)testTimeout
{
    [self expectationWithDescription:@"missing callback"];
    __block BOOL called = NO;
    [self waitForExpectationsWithTimeout:0 handler:^(NSError *error) {
        called = YES;
        CHECK([[error domain] isEqual:XCTestErrorDomain]);
        CHECK([error code] == XCTestErrorCodeTimeoutWhileWaiting);
        CHECK([[error localizedDescription] rangeOfString:@"missing callback"].location != NSNotFound);
    }];
    CHECK(called);
}
- (void)testInvertedSuccess
{
    XCTestExpectation *e = [self expectationWithDescription:@"forbidden"];
    e.inverted = YES;
    [self waitForExpectationsWithTimeout:0.001 handler:nil];
}
- (void)testInvertedFailure
{
    XCTestExpectation *e = [self expectationWithDescription:@"forbidden"];
    e.inverted = YES;
    [e fulfill];
    [self waitForExpectationsWithTimeout:0 handler:nil];
}
- (void)testOverFulfill
{
    XCTestExpectation *e = [self expectationWithDescription:@"once"];
    e.assertForOverFulfill = YES;
    [e fulfill]; [e fulfill];
    [self waitForExpectationsWithTimeout:0 handler:nil];
}
- (void)testUnwaited { [self expectationWithDescription:@"unused"]; }
- (void)testExplicit
{
    XCTestExpectation *e = [[[XCTestExpectation alloc] initWithDescription:@"external"] autorelease];
    [e fulfill];
    [self waitForExpectations:[NSArray arrayWithObject:e] timeout:0];
}
@end

/* gnustep/tools-xctest#10: failures recorded around -invokeTest. */
static BOOL invokeTestB;
@interface FailureBeforeSuper : XCTestCase @end
@implementation FailureBeforeSuper
- (void)invokeTest { XCTFail(@"before super"); [super invokeTest]; }
- (void)testBody {}
@end
@interface ThrowFromInvokeTest : XCTestCase @end
@implementation ThrowFromInvokeTest
- (void)invokeTest
{
    if ([NSStringFromSelector([[self invocation] selector]) isEqual:@"testA"]) Throw();
    [super invokeTest];
}
- (void)testA {}
- (void)testB { invokeTestB = YES; }
@end

/* gnustep/tools-xctest#11: expectations as Apple documents them. */
@interface Expectations : XCTestCase { XCTestExpectation *outer; } @end
@implementation Expectations
- (void)testDefaultOverFulfill
{
    XCTestExpectation *e = [self expectationWithDescription:@"default"];
    CHECK([e assertForOverFulfill]);
    CHECK(![[[[XCTestExpectation alloc] initWithDescription:@"manual"] autorelease] assertForOverFulfill]);
    [e fulfill];
    [self waitForExpectationsWithTimeout:0 handler:nil];
}
- (void)testFulfillTwice
{
    XCTestExpectation *e = [self expectationWithDescription:@"twice"];
    [e fulfill]; [e fulfill];
    [self waitForExpectationsWithTimeout:0 handler:nil];
}
- (void)testFulfillAfterWait
{
    XCTestExpectation *e = [self expectationWithDescription:@"after"];
    [e fulfill];
    [self waitForExpectationsWithTimeout:0 handler:nil];
    [e fulfill];
}
- (void)testSetDescription
{
    XCTestExpectation *e = [[[XCTestExpectation alloc] initWithDescription:@"before"] autorelease];
    [e setExpectationDescription:@"after"];
    CHECK([[e expectationDescription] isEqual:@"after"]);
}
- (void)innerWait:(id)unused
{
    XCTestExpectation *inner = [[[XCTestExpectation alloc] initWithDescription:@"inner"] autorelease];
    [inner fulfill];
    [self waitForExpectations:[NSArray arrayWithObject:inner] timeout:1];
    [outer fulfill];
}
- (void)testWaitInsideCallback
{
    outer = [[[XCTestExpectation alloc] initWithDescription:@"outer"] autorelease];
    [self performSelector:@selector(innerWait:) withObject:nil afterDelay:0.01];
    [self waitForExpectations:[NSArray arrayWithObject:outer] timeout:1];
}
@end

#define NEAR(a, b) (fabs((a) - (b)) < 1e-6)

static GSXCTMeasurement *Judged(NSArray *values, double baseline, NSNumber *stddev, NSUInteger count, int polarity)
{
    GSXCTMeasurement *m = [[[GSXCTMeasurement alloc] init] autorelease];
    [m setValues:values]; [m setPolarity:polarity];
    [m setBaselineAverage:[NSNumber numberWithDouble:baseline]]; [m setMaxPercentRegression:10];
    [m setBaselineStandardDeviation:stddev]; [m setBaselineCount:count];
    [m judge];
    return m;
}

static void CheckStatistics(void)
{
    NSArray *steady = [NSArray arrayWithObjects:@110, @112, @111, @113, @109, nil];
    NSArray *noisy = [NSArray arrayWithObjects:@80, @140, @100, @150, @90, nil];
    NSNumber *one = [NSNumber numberWithInt:1];
    GSXCTSummary summary = GSXCTSummarize([NSArray arrayWithObjects:@3, @1, @2, @10, nil]);
    CHECK(summary.count == 4 && NEAR(summary.mean, 4) && NEAR(summary.median, 2.5));
    CHECK(NEAR(summary.minimum, 1) && NEAR(summary.maximum, 10) && NEAR(summary.standardDeviation, sqrt(50.0 / 3)));
    summary = GSXCTSummarize([NSArray arrayWithObject:@7]);
    CHECK(NEAR(summary.median, 7) && summary.standardDeviation == 0);
    CHECK(GSXCTSummarize([NSArray array]).count == 0);
    CHECK(NEAR(GSXCTStudentTCDF(2, 10), 0.963306) && NEAR(GSXCTStudentTCDF(-2, 10), 0.036694));
    CHECK(NEAR(GSXCTStudentTCDF(0, 5), 0.5) && NEAR(GSXCTStudentTCDF(1, 1), 0.75));
    CHECK(NEAR(GSXCTStudentTCDF(3.5, 2), 0.5 + 3.5 / (2 * sqrt(2 + 3.5 * 3.5))));
    CHECK(NEAR(GSXCTWelchPValue(10.5, 1, 10, 10, 1, 10), 0.139126));
    CHECK(isnan(GSXCTWelchPValue(1, 1, 1, 0, 1, 10)));
    CHECK(GSXCTWelchPValue(2, 0, 5, 1, 0, 5) == 0 && GSXCTWelchPValue(1, 0, 5, 1, 0, 5) == 1);

    // Without the baseline's stddev and count, past the threshold regresses.
    GSXCTMeasurement *m = Judged(steady, 100, nil, 0, -1);
    CHECK([m verdict] == GSXCTMeasurementVerdictRegressed && NEAR([m percentWorse], 11) && isnan([m pValue]));
    CHECK([[m verdictDescription] hasSuffix:@"(max allowed regression 10.0%)"]);
    m = Judged(noisy, 100, nil, 0, -1);
    CHECK([m verdict] == GSXCTMeasurementVerdictRegressed);
    // With them, it must also be significant.
    m = Judged(steady, 100, one, 5, -1);
    CHECK([m verdict] == GSXCTMeasurementVerdictRegressed && [m pValue] < 0.001);
    m = Judged(noisy, 100, one, 5, -1);
    CHECK([m verdict] == GSXCTMeasurementVerdictInconclusive && [m pValue] > 0.05);
    CHECK([[m verdictDescription] rangeOfString:@"but not significantly"].location != NSNotFound);
    CHECK([[m verdictName] isEqual:@"inconclusive"]);
    // Better, larger-is-better, unknown polarity and zero baselines.
    CHECK([Judged(steady, 120, one, 5, -1) verdict] == GSXCTMeasurementVerdictPassed);
    m = Judged(steady, 100, one, 5, 1);
    CHECK([m verdict] == GSXCTMeasurementVerdictPassed && NEAR([m percentWorse], -11) && [m pValue] > 0.99);
    CHECK([Judged(steady, 125, one, 5, 1) verdict] == GSXCTMeasurementVerdictRegressed);
    CHECK([Judged(steady, 100, one, 5, 0) verdict] == GSXCTMeasurementVerdictNone);
    CHECK([Judged(steady, 0, nil, 0, -1) verdict] == GSXCTMeasurementVerdictPassed);
    // Too noisy for the baseline's maximum relative standard deviation.
    m = [[[GSXCTMeasurement alloc] init] autorelease];
    [m setValues:noisy]; [m setPolarity:-1]; [m setMaxPercentRegression:50];
    [m setBaselineAverage:[NSNumber numberWithInt:100]];
    [m setMaxPercentRelativeStandardDeviation:[NSNumber numberWithInt:5]];
    [m judge];
    CHECK([m verdict] == GSXCTMeasurementVerdictInconclusive);
    CHECK([[m verdictDescription] rangeOfString:@"above the baseline's maximum of 5.0%"].location != NSNotFound);
    CHECK([Judged(steady, 100, nil, 0, -1) verdictName] != nil && [[[GSXCTMeasurement new] autorelease] verdictName] == nil);
}

static NSUInteger Run(Class cls, SEL selector)
{
    XCTestCase *test = [cls testCaseWithSelector:selector];
    [test invokeTest];
    return [test failureCount];
}

int main(void)
{
    @autoreleasepool {
        CheckStatistics();
        Probe *probe = [Probe new];
        [probe checkAssertions];
        [probe release];
        CHECK([[Lifecycle testInvocations] count] == 5);
        CHECK([[Inherited testInvocations] count] == 5);
        CHECK([NSStringFromSelector([[[Lifecycle testInvocations] objectAtIndex:0] selector]) isEqual:@"testContinue"]);
        CHECK(Run([Lifecycle class], @selector(testPass)) == 0);
        CHECK(bodies == 1 && setups == 1 && teardowns == 1);
        CHECK(Run([Lifecycle class], @selector(testThrow)) == 1);
        CHECK(teardowns == 2);
        CHECK(Run([Lifecycle class], @selector(testStop)) == 1);
        CHECK(bodies == 1 && teardowns == 3);
        CHECK(Run([Lifecycle class], @selector(testContinue)) == 2);
        CHECK(bodies == 2 && teardowns == 4);
        CHECK(Run([Lifecycle class], @selector(testNestedStop)) == 1);
        CHECK(bodies == 2 && teardowns == 5);
        CHECK(Run([SetupFailure class], @selector(testPass)) == 1);
        CHECK(bodies == 2 && teardowns == 6);
        CHECK(Run([TeardownFailure class], @selector(testThrow)) == 2);
        CHECK(teardowns == 7);
        CHECK(Run([Inherited class], @selector(testPass)) == 0);
        CHECK(bodies == 12);
        XCTestCase *repeat = [Lifecycle testCaseWithSelector:@selector(testPass)];
        [repeat recordFailureWithDescription:@"old failure" inFile:nil atLine:0 expected:YES];
        [repeat invokeTest]; CHECK([repeat failureCount] == 0);
        CHECK(Run([Async class], @selector(testPredicateSuccess)) == 0);
        CHECK(Run([Async class], @selector(testPredicateHandler)) == 0);
        CHECK(Run([Async class], @selector(testPredicateTimeout)) == 1);
        CHECK(Run([Async class], @selector(testPredicateInverted)) == 1);
        CHECK(Run([Async class], @selector(testSuccess)) == 0);
        CHECK(Run([Async class], @selector(testBackground)) == 0);
        CHECK(Run([Async class], @selector(testSequential)) == 0);
        CHECK(Run([Async class], @selector(testStoppedTimeout)) == 1);
        XCTestCase *invalid = [[[XCTestCase alloc] init] autorelease];
        [invalid invokeTest]; CHECK([invalid failureCount] == 1);
        @try {
            [Lifecycle testCaseWithSelector:@selector(testInvalidArgument:)];
            CHECK(NO);
        }
        @catch (NSException *exception) { CHECK([[exception name] isEqual:NSInvalidArgumentException]); }
        @try {
            [[[[XCTestExpectation alloc] initWithDescription:@"zero"] autorelease] setExpectedFulfillmentCount:0];
            CHECK(NO);
        }
        @catch (NSException *exception) { CHECK([[exception name] isEqual:NSInvalidArgumentException]); }
        CHECK([GSXCTestRunner sharedRunner] == [GSXCTestRunner sharedRunner]);
        CHECK(Run([Async class], @selector(testTimeout)) == 1);
        CHECK(Run([Async class], @selector(testInvertedSuccess)) == 0);
        CHECK(Run([Async class], @selector(testInvertedFailure)) == 1);
        CHECK(Run([Async class], @selector(testOverFulfill)) == 1);
        CHECK(Run([Async class], @selector(testUnwaited)) == 1);
        CHECK(Run([Async class], @selector(testExplicit)) == 0);

        CHECK(Run([Expectations class], @selector(testDefaultOverFulfill)) == 0);
        CHECK(Run([Expectations class], @selector(testFulfillTwice)) == 1);
        CHECK(Run([Expectations class], @selector(testFulfillAfterWait)) == 1);
        CHECK(Run([Expectations class], @selector(testSetDescription)) == 0);
        CHECK(Run([Expectations class], @selector(testWaitInsideCallback)) == 0);
        CHECK(Run([FailureBeforeSuper class], @selector(testBody)) == 1);

        GSXCTestRunner *runner = [GSXCTestRunner new];
        CHECK(![runner runTestsNamed:[NSArray arrayWithObject:@"ThrowFromInvokeTest"]]);
        CHECK(invokeTestB);
        CHECK([runner runTestsNamed:[NSArray arrayWithObject:@"Inherited.testPass"]]);
        CHECK(classSetups == 1 && classTeardowns == 1);
        CHECK(![runner runTestsNamed:[NSArray arrayWithObject:@"Lifecycle.testStop"]]);
        CHECK(![runner runTestsNamed:[NSArray arrayWithObject:@"Missing"]]);
        CHECK(![runner runTestsNamed:[NSArray array]]);
        CHECK(![runner runTestsNamed:[NSArray arrayWithObject:@"ClassFailure.testPass"]]);
        CHECK(classTeardowns == 3);
        CHECK([runner runTestsNamed:[NSArray arrayWithObject:@"Lifecycle.testPass"]]);
        [runner waitForCompletion];
        [runner release];
        NSLog(@"Regression: %d checks, %d errors", checks, errors);
    }
    return errors ? 1 : 0;
}
