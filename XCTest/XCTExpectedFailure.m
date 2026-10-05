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

#import <XCTest/XCTExpectedFailure.h>
#import <XCTest/XCTestPrivate.h>
#import <XCTest/XCTestAssertionsImpl.h>

@implementation XCTExpectedFailureOptions

+ (id) nonStrictOptions
{
    XCTExpectedFailureOptions *options = [[[self alloc] init] autorelease];

    [options setStrict:NO];
    return options;
}

- (id) init
{
    self = [super init];
    if (self) {
        _enabled = YES;
        _strict = YES;
    }

    return self;
}

- (void) dealloc
{
    [_issueMatcher release];
    [super dealloc];
}

- (BOOL (^)(XCTIssue *)) issueMatcher
{
    return [[_issueMatcher retain] autorelease];
}

- (void) setIssueMatcher: (BOOL (^)(XCTIssue *))issueMatcher
{
    BOOL (^old)(XCTIssue *) = _issueMatcher;

    _issueMatcher = [issueMatcher copy];
    [old release];
}

- (BOOL) isEnabled
{
    return _enabled;
}

- (void) setEnabled: (BOOL)enabled
{
    _enabled = enabled;
}

- (BOOL) isStrict
{
    return _strict;
}

- (void) setStrict: (BOOL)strict
{
    _strict = strict;
}

@end

/*! One XCTExpectFailure call: its reason, options and how many failures it
 * has absorbed. */
@interface GSXCTExpectedFailureScope : NSObject {
@public
    NSString *reason;
    XCTExpectedFailureOptions *options;
    NSUInteger matchCount;
}
@end

@implementation GSXCTExpectedFailureScope

- (void) dealloc
{
    [reason release];
    [options release];
    [super dealloc];
}

@end

static GSXCTExpectedFailureScope *GSPushScope(XCTestCase *testCase, NSString *reason,
                                              XCTExpectedFailureOptions *options)
{
    GSXCTExpectedFailureScope *scope = [[[GSXCTExpectedFailureScope alloc] init] autorelease];

    scope->reason = [reason copy];
    scope->options = [(options ? options : [[[XCTExpectedFailureOptions alloc] init] autorelease]) retain];
    [[testCase _gsExpectedFailureScopes] addObject:scope];
    return scope;
}

// Records a failure for a strict scope that absorbed nothing.
static void GSCheckScopeMatched(XCTestCase *testCase, GSXCTExpectedFailureScope *scope)
{
    if ([scope->options isEnabled] && [scope->options isStrict] && scope->matchCount == 0) {
        [testCase _gsRecordUnmatchedExpectedFailure:scope->reason];
    }
}

void XCTExpectFailure(NSString *failureReason)
{
    XCTExpectFailureWithOptions(failureReason, nil);
}

void XCTExpectFailureWithOptions(NSString *failureReason, XCTExpectedFailureOptions *options)
{
    XCTestCase *testCase = [XCTestCase _gsCurrentTestCase];

    if (testCase == nil) {
        NSLog(@"XCTest: XCTExpectFailure called outside of a test; ignored.");
        return;
    }

    GSPushScope(testCase, failureReason, options);
}

void XCTExpectFailureInBlock(NSString *failureReason, void (^failingBlock)(void))
{
    XCTExpectFailureWithOptionsInBlock(failureReason, nil, failingBlock);
}

void XCTExpectFailureWithOptionsInBlock(NSString *failureReason, XCTExpectedFailureOptions *options,
                                        void (^failingBlock)(void))
{
    XCTestCase *testCase = [XCTestCase _gsCurrentTestCase];
    GSXCTExpectedFailureScope *scope = nil;

    if (testCase == nil) {
        NSLog(@"XCTest: XCTExpectFailureInBlock called outside of a test; running the block anyway.");
        failingBlock();
        return;
    }

    scope = [[GSPushScope(testCase, failureReason, options) retain] autorelease];
    @try {
        failingBlock();
    }
    @finally {
        [[testCase _gsExpectedFailureScopes] removeObjectIdenticalTo:scope];
    }

    GSCheckScopeMatched(testCase, scope);
}

@implementation XCTestCase (GSExpectedFailures)

- (NSMutableArray *) _gsExpectedFailureScopes
{
    if (_expectedFailureScopes == nil) {
        _expectedFailureScopes = [[NSMutableArray alloc] init];
    }

    return _expectedFailureScopes;
}

- (BOOL) _gsAbsorbExpectedFailure: (GSXCTestIssue *)failure
{
    XCTIssue *issue = nil;

    if (_gsRecordingUnmatched || [_expectedFailureScopes count] == 0) {
        return NO;
    }

    issue = [failure xctIssue];

    // The innermost enabled scope whose matcher accepts the issue wins.
    for (GSXCTExpectedFailureScope *scope in [[_expectedFailureScopes reverseObjectEnumerator] allObjects]) {
        BOOL (^matcher)(XCTIssue *) = [scope->options issueMatcher];

        if (![scope->options isEnabled] || (matcher != nil && !matcher(issue))) {
            continue;
        }

        scope->matchCount++;
        [failure setContext:scope->reason];
        [[XCTestObservationCenter sharedTestObservationCenter] _gsNotifyObservers:^(id observer) {
            if ([observer respondsToSelector:@selector(_gsTestCase:didRecordExpectedFailure:)]) {
                [observer _gsTestCase:self didRecordExpectedFailure:failure];
            }
        }];
        return YES;
    }

    return NO;
}

- (void) _gsRecordUnmatchedExpectedFailure: (NSString *)reason
{
    _gsRecordingUnmatched = YES;
    @try {
        [self recordIssue:_GSXCTMakeIssue(XCTIssueTypeUnmatchedExpectedFailure,
                                          [NSString stringWithFormat:@"Failed due to unmatched expected failure: %@", reason],
                                          nil, 0, nil)];
    }
    @catch (_XCTestCaseInterruptionException *interruption) {
    }
    @finally {
        _gsRecordingUnmatched = NO;
    }
}

- (void) _gsFinishExpectedFailures
{
    NSArray *scopes = [[_expectedFailureScopes copy] autorelease];

    [_expectedFailureScopes removeAllObjects];
    if ([[self testRun] hasBeenSkipped]) {
        return;
    }

    for (GSXCTExpectedFailureScope *scope in scopes) {
        GSCheckScopeMatched(self, scope);
    }
}

@end
