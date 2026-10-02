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

#import <XCTest/XCTestSuite.h>
#import <XCTest/XCTestPrivate.h>
#import <XCTest/XCTestAssertionsImpl.h>

#import <objc/runtime.h>

NSArray *_GSXCTestCaseSubclasses(void)
{
    int numClasses = objc_getClassList(NULL, 0);
    Class *classes = malloc(sizeof(Class) * numClasses);
    NSMutableArray *result = [NSMutableArray array];

    numClasses = objc_getClassList(classes, numClasses);
    for (int i = 0; i < numClasses; i++) {
        Class superClass = classes[i];

        do {
            superClass = class_getSuperclass(superClass);
        } while (superClass && superClass != [XCTestCase class]);

        if (superClass != Nil) {
            [result addObject:classes[i]];
        }
    }
    free(classes);

    return [result sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        return [NSStringFromClass(a) compare:NSStringFromClass(b)];
    }];
}

@implementation XCTestSuite

+ (id) defaultTestSuite
{
    XCTestSuite *suite = [self testSuiteWithName:@"All tests"];

    for (Class testCaseClass in _GSXCTestCaseSubclasses()) {
        [suite addTest:[testCaseClass defaultTestSuite]];
    }

    return suite;
}

+ (id) testSuiteForBundlePath: (NSString *)bundlePath
{
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    XCTestSuite *suite = [self testSuiteWithName:[bundlePath lastPathComponent]];

    if (![bundle load]) {
        return suite;
    }

    for (Class testCaseClass in _GSXCTestCaseSubclasses()) {
        if ([NSBundle bundleForClass:testCaseClass] == bundle) {
            [suite addTest:[testCaseClass defaultTestSuite]];
        }
    }

    return suite;
}

+ (id) testSuiteForTestCaseWithName: (NSString *)name
{
    NSArray *components = [name componentsSeparatedByString:@"/"];
    Class testCaseClass = NSClassFromString([components objectAtIndex:0]);
    XCTestSuite *suite = [self testSuiteWithName:name];

    if (testCaseClass == Nil || ![testCaseClass isSubclassOfClass:[XCTestCase class]]) {
        return suite;
    }

    if ([components count] == 1) {
        return [testCaseClass defaultTestSuite];
    }

    [suite addTest:[testCaseClass testCaseWithSelector:NSSelectorFromString([components objectAtIndex:1])]];
    return suite;
}

+ (id) testSuiteForTestCaseClass: (Class)testCaseClass
{
    return [testCaseClass defaultTestSuite];
}

+ (id) testSuiteWithName: (NSString *)name
{
    return [[[self alloc] initWithName:name] autorelease];
}

- (id) init
{
    return [self initWithName:@""];
}

- (id) initWithName: (NSString *)name
{
    self = [super init];
    if (self) {
        _name = [name copy];
        _tests = [[NSMutableArray alloc] init];
    }

    return self;
}

- (void) dealloc
{
    [_name release];
    [_tests release];
    [super dealloc];
}

- (NSString *) name
{
    return _name;
}

- (void) addTest: (XCTest *)test
{
    if (test != nil) {
        [_tests addObject:test];
    }
}

- (NSArray *) tests
{
    return [[_tests copy] autorelease];
}

- (NSUInteger) testCaseCount
{
    NSUInteger count = 0;

    for (XCTest *test in _tests) {
        count += [test testCaseCount];
    }

    return count;
}

- (Class) testRunClass
{
    return [XCTestSuiteRun class];
}

- (void) performTest: (XCTestRun *)run
{
    [self _gsSetTestRun:run];
    [run start];
    [self setUp];
    for (XCTest *test in _tests) {
        @autoreleasepool {
            [test runTest];
            [(XCTestSuiteRun *)run addTestRun:[test testRun]];
        }
    }
    [self tearDown];
    [run stop];
}

@end

// The class suite whose tests are running. Not retained.
static GSXCTestCaseSuite *GSCurrentClassSuite = nil;

static GSXCTestRepetitionMode GSRepetitionMode = GSXCTestRepetitionNone;
static NSUInteger GSRepetitionIterations = 1;

@implementation GSXCTestCaseSuite

@synthesize testCaseClass = _testCaseClass;

+ (GSXCTestCaseSuite *) suiteForTestCaseClass: (Class)testCaseClass
{
    GSXCTestCaseSuite *suite = [[[self alloc] initWithName:NSStringFromClass(testCaseClass)] autorelease];

    suite->_testCaseClass = testCaseClass;
    return suite;
}

+ (GSXCTestCaseSuite *) _gsCurrentClassSuite
{
    return GSCurrentClassSuite;
}

+ (void) _gsSetRepetitionMode: (GSXCTestRepetitionMode)mode iterations: (NSUInteger)iterations
{
    GSRepetitionMode = mode;
    GSRepetitionIterations = iterations > 0 ? iterations : 1;
}

// Runs a test once, or repeatedly per the repetition mode, each time with
// a fresh test case, adding the runs that count to \a suiteRun.
- (void) _gsRunTestCase: (XCTestCase *)testCase suiteRun: (XCTestSuiteRun *)suiteRun
{
    NSUInteger iterations = GSRepetitionMode == GSXCTestRepetitionNone ? 1 : GSRepetitionIterations;

    for (NSUInteger iteration = 1; iteration <= iterations; iteration++) {
        @autoreleasepool {
            XCTestCase *attempt = iteration == 1 ? testCase
                : [[[[testCase class] alloc] initWithInvocation:[testCase invocation]] autorelease];
            XCTestRun *attemptRun = nil;
            BOOL failed = NO;

            if (GSRepetitionMode != GSXCTestRepetitionNone) {
                [attempt _gsSetIteration:iteration of:iterations];
            }
            [attempt runTest];
            attemptRun = [attempt testRun];
            failed = [attemptRun totalFailureCount] > 0;

            if (GSRepetitionMode == GSXCTestRepetitionRetryOnFailure && failed && iteration < iterations) {
                [[XCTestObservationCenter sharedTestObservationCenter] _gsNotifyObservers:^(id observer) {
                    if ([observer respondsToSelector:@selector(_gsTestCaseAttemptWasDiscarded:)]) {
                        [observer _gsTestCaseAttemptWasDiscarded:attempt];
                    }
                }];
                continue;
            }

            [suiteRun addTestRun:attemptRun];

            if ([attemptRun hasBeenSkipped]
                || (GSRepetitionMode == GSXCTestRepetitionUntilFailure && failed)
                || (GSRepetitionMode == GSXCTestRepetitionRetryOnFailure && !failed)) {
                break;
            }
        }
    }
}

- (void) _gsRecordClassFailure: (NSString *)description
                        inFile: (NSString *)filePath
                        atLine: (NSUInteger)lineNumber
                      expected: (BOOL)expected
{
    GSXCTestIssue *issue = [GSXCTestIssue issueWithMessage:description
                                                  filePath:filePath
                                                lineNumber:lineNumber
                                                unexpected:!expected];

    [issue setContext:_classContext ? _classContext : @"+setUp"];
    [[self testRun] _gsRecordIssue:issue];
}

// Calls +setUp or +tearDown; returns NO if it recorded any failure. A
// skip is returned through \a skip (and ignored in +tearDown).
- (BOOL) _gsRunClassMethod: (SEL)selector context: (NSString *)context skip: (GSXCTestIssue **)skip
{
    NSUInteger issuesBefore = [[(XCTestSuiteRun *)[self testRun] _gsOwnIssues] count];

    _classContext = context;
    @try {
        [_testCaseClass performSelector:selector];
    }
    @catch (_XCTSkipFailureException *skipException) {
        if (skip != NULL) {
            *skip = _GSXCTIssueForSkip(skipException);
        }
    }
    @catch (NSException *exception) {
        [self _gsRecordClassFailure:[NSString stringWithFormat:@"threw exception: %@",
                                        _GSXCTDescribeException(exception)]
                             inFile:nil
                             atLine:0
                           expected:NO];
    }
    _classContext = nil;

    return [[(XCTestSuiteRun *)[self testRun] _gsOwnIssues] count] == issuesBefore;
}

- (void) performTest: (XCTestRun *)run
{
    GSXCTestCaseSuite *previous = GSCurrentClassSuite;

    [self _gsSetTestRun:run];
    GSCurrentClassSuite = self;
    [run start];

    if ([_tests count] > 0) {
        GSXCTestIssue *classSkip = nil;
        BOOL classSetUpSucceeded = [self _gsRunClassMethod:@selector(setUp) context:@"+setUp" skip:&classSkip];
        GSXCTestIssue *cause = classSetUpSucceeded ? nil
            : [[(XCTestSuiteRun *)run _gsOwnIssues] objectAtIndex:0];
        // A skip in +setUp skips the whole class (unless +setUp also failed).
        BOOL runTests = classSetUpSucceeded && classSkip == nil;

        for (XCTest *test in _tests) {
            @autoreleasepool {
                if (runTests && [test isKindOfClass:[XCTestCase class]]) {
                    [self _gsRunTestCase:(XCTestCase *)test suiteRun:(XCTestSuiteRun *)run];
                    continue;
                }

                if (runTests) {
                    [test runTest];
                } else if (!classSetUpSucceeded) {
                    [(XCTestCase *)test _gsFailWithoutRunning:cause];
                } else {
                    [(XCTestCase *)test _gsSkipWithoutRunning:classSkip];
                }
                [(XCTestSuiteRun *)run addTestRun:[test testRun]];
            }
        }

        if (runTests) {
            [self _gsRunClassMethod:@selector(tearDown) context:@"+tearDown" skip:NULL];
        }
    }

    [run stop];
    GSCurrentClassSuite = previous;
}

@end
