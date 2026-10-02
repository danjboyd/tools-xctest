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

#import <XCTest/XCTestAssertions.h>
#import <GSXCTestRunner.h>

@implementation _XCTestCaseInterruptionException
@end

@implementation _XCTSkipFailureException
@end

@interface GSXCTestRunner (GSPrivate)
- (void)registerAssertionFailed;
@end

void _XCTFailureHandler(XCTestCase *test, BOOL expected, const char *filePath, NSUInteger lineNumber, NSString *condition, NSString *format, ...)
{
    NSString *message = nil;
    
    if ([format length] > 0) {
        va_list args;
        va_start(args, format);
        message = [[[NSString alloc] initWithFormat:format arguments:args] autorelease];
        va_end(args);
    }
    
    _XCTPreformattedFailureHandler(test, expected, [NSString stringWithUTF8String:filePath], lineNumber, condition, message);
}

void _XCTPreformattedFailureHandler(XCTestCase *test, BOOL expected, NSString *filePath, NSUInteger lineNumber, NSString *condition, NSString *message)
{
    NSLog(@"XCTest:     Assertion FAILED at %@:%lu, %@%@", 
        filePath, 
        (unsigned long)lineNumber, 
        condition, 
        ([message length] > 0 ? [NSString stringWithFormat:@": %@", message] : @""));
    
    [[GSXCTestRunner sharedRunner] registerAssertionFailed];

    if ([test isKindOfClass:[XCTestCase class]] && ![test continueAfterFailure]) {
        [[_XCTestCaseInterruptionException exceptionWithName:@"_XCTestCaseInterruptionException"
                                                      reason:@"Test stopped after failure (continueAfterFailure is NO)"
                                                    userInfo:nil] raise];
    }
}

void _XCTSkipHandler(XCTestCase *test, const char *filePath, NSUInteger lineNumber, NSString *condition, NSString *format, ...)
{
    NSString *message = nil;
    NSString *reason = nil;

    if ([format length] > 0) {
        va_list args;
        va_start(args, format);
        message = [[[NSString alloc] initWithFormat:format arguments:args] autorelease];
        va_end(args);
    }

    // The runner logs the reason as "SKIPPED <reason>".
    reason = [NSString stringWithFormat:@"at %s:%lu", filePath, (unsigned long)lineNumber];
    if ([condition length] > 0) {
        reason = [reason stringByAppendingFormat:@", %@", condition];
    }
    if ([message length] > 0) {
        reason = [reason stringByAppendingFormat:@": %@", message];
    }

    [[_XCTSkipFailureException exceptionWithName:@"_XCTSkipFailureException"
                                          reason:reason
                                        userInfo:nil] raise];
}

// Failure messages, indexed by assertion type and the format index passed by
// the macros in XCTestAssertionsImpl.h. Each format consumes the macro's
// arguments in order. Index 0 is the plain failure; the others are for an
// exception thrown while evaluating the expressions.
#define _XCT_THROWING @" failed: throwing \"%@\""
#define _XCT_THROWING_UNKNOWN @" failed: throwing unknown exception"

static NSString * const _XCTFailureFormats[][4] = {
    [_XCTAssertion_Fail] = {
        @"failed" },
    [_XCTAssertion_Nil] = {
        @"((%@) == nil) failed: \"%@\"",
        @"((%@) == nil)" _XCT_THROWING,
        @"((%@) == nil)" _XCT_THROWING_UNKNOWN },
    [_XCTAssertion_NotNil] = {
        @"((%@) != nil) failed",
        @"((%@) != nil)" _XCT_THROWING,
        @"((%@) != nil)" _XCT_THROWING_UNKNOWN },
    [_XCTAssertion_EqualObjects] = {
        @"((%@) equal to (%@)) failed: (\"%@\") is not equal to (\"%@\")",
        @"((%@) equal to (%@))" _XCT_THROWING,
        @"((%@) equal to (%@))" _XCT_THROWING_UNKNOWN },
    [_XCTAssertion_NotEqualObjects] = {
        @"((%@) not equal to (%@)) failed: (\"%@\") is equal to (\"%@\")",
        @"((%@) not equal to (%@))" _XCT_THROWING,
        @"((%@) not equal to (%@))" _XCT_THROWING_UNKNOWN },
    [_XCTAssertion_Equal] = {
        @"((%@) equal to (%@)) failed: (\"%@\") is not equal to (\"%@\")",
        @"((%@) equal to (%@))" _XCT_THROWING,
        @"((%@) equal to (%@))" _XCT_THROWING_UNKNOWN },
    [_XCTAssertion_NotEqual] = {
        @"((%@) not equal to (%@)) failed: (\"%@\") is equal to (\"%@\")",
        @"((%@) not equal to (%@))" _XCT_THROWING,
        @"((%@) not equal to (%@))" _XCT_THROWING_UNKNOWN },
    [_XCTAssertion_EqualWithAccuracy] = {
        @"((%@) equal to (%@) +/- (%@)) failed: (\"%@\") is not equal to (\"%@\") +/- (\"%@\")",
        @"((%@) equal to (%@) +/- (%@))" _XCT_THROWING,
        @"((%@) equal to (%@) +/- (%@))" _XCT_THROWING_UNKNOWN },
    [_XCTAssertion_NotEqualWithAccuracy] = {
        @"((%@) not equal to (%@) +/- (%@)) failed: (\"%@\") is equal to (\"%@\") +/- (\"%@\")",
        @"((%@) not equal to (%@) +/- (%@))" _XCT_THROWING,
        @"((%@) not equal to (%@) +/- (%@))" _XCT_THROWING_UNKNOWN },
    [_XCTAssertion_GreaterThan] = {
        @"((%@) greater than (%@)) failed: (\"%@\") is less than or equal to (\"%@\")",
        @"((%@) greater than (%@))" _XCT_THROWING,
        @"((%@) greater than (%@))" _XCT_THROWING_UNKNOWN },
    [_XCTAssertion_GreaterThanOrEqual] = {
        @"((%@) greater than or equal to (%@)) failed: (\"%@\") is less than (\"%@\")",
        @"((%@) greater than or equal to (%@))" _XCT_THROWING,
        @"((%@) greater than or equal to (%@))" _XCT_THROWING_UNKNOWN },
    [_XCTAssertion_LessThan] = {
        @"((%@) less than (%@)) failed: (\"%@\") is greater than or equal to (\"%@\")",
        @"((%@) less than (%@))" _XCT_THROWING,
        @"((%@) less than (%@))" _XCT_THROWING_UNKNOWN },
    [_XCTAssertion_LessThanOrEqual] = {
        @"((%@) less than or equal to (%@)) failed: (\"%@\") is greater than (\"%@\")",
        @"((%@) less than or equal to (%@))" _XCT_THROWING,
        @"((%@) less than or equal to (%@))" _XCT_THROWING_UNKNOWN },
    [_XCTAssertion_True] = {
        @"((%@) is true) failed",
        @"((%@) is true)" _XCT_THROWING,
        @"((%@) is true)" _XCT_THROWING_UNKNOWN },
    [_XCTAssertion_False] = {
        @"((%@) is false) failed",
        @"((%@) is false)" _XCT_THROWING,
        @"((%@) is false)" _XCT_THROWING_UNKNOWN },
    [_XCTAssertion_Throws] = {
        @"((%@) throws) failed: no exception thrown" },
    [_XCTAssertion_ThrowsSpecific] = {
        @"((%@) throws <%@>) failed: threw <%@> \"%@\"",
        @"((%@) throws <%@>)" _XCT_THROWING_UNKNOWN,
        @"((%@) throws <%@>) failed: no exception thrown" },
    [_XCTAssertion_ThrowsSpecificNamed] = {
        @"((%@) throws <%@, \"%@\">) failed: threw <%@, \"%@\"> \"%@\"",
        @"((%@) throws <%@, \"%@\">) failed: threw <%@, \"%@\"> \"%@\"",
        @"((%@) throws <%@, \"%@\">)" _XCT_THROWING_UNKNOWN,
        @"((%@) throws <%@, \"%@\">) failed: no exception thrown" },
    [_XCTAssertion_NoThrow] = {
        @"((%@) does not throw) failed: threw \"%@\"",
        @"((%@) does not throw)" _XCT_THROWING_UNKNOWN },
    [_XCTAssertion_NoThrowSpecific] = {
        @"((%@) does not throw <%@>) failed: threw <%@> \"%@\"" },
    [_XCTAssertion_NoThrowSpecificNamed] = {
        @"((%@) does not throw <%@, \"%@\">) failed: threw <%@, \"%@\"> \"%@\"" },
};

NSString * _XCTFailureFormat (_XCTAssertionType assertionType, NSUInteger formatIndex)
{
    NSString *format = nil;

    if (assertionType < sizeof(_XCTFailureFormats) / sizeof(_XCTFailureFormats[0])
        && formatIndex < 4) {
        format = _XCTFailureFormats[assertionType][formatIndex];
    }

    return format ? format : @"failed";
}

// Shortest decimal form that reads back as the same double.
static NSString *_XCTDescriptionForDouble (double value)
{
    NSString *description = [NSString stringWithFormat:@"%.15g", value];

    if ([description doubleValue] != value) {
        description = [NSString stringWithFormat:@"%.17g", value];
    }

    return description;
}

NSString * _XCTDescriptionForValue (NSValue *value)
{
    const char *type = [value objCType];

    // Skip type qualifiers such as const ('r').
    while (*type != '\0' && strchr("rnNoORV", *type) != NULL) {
        type++;
    }

#define _XCT_DESCRIBE(ctype, format) \
    { ctype v; [value getValue:&v]; return [NSString stringWithFormat:format, v]; }

    switch (*type) {
        case 'c': _XCT_DESCRIBE(signed char, @"%d")
        case 'C': _XCT_DESCRIBE(unsigned char, @"%u")
        case 's': _XCT_DESCRIBE(short, @"%hd")
        case 'S': _XCT_DESCRIBE(unsigned short, @"%hu")
        case 'i': _XCT_DESCRIBE(int, @"%d")
        case 'I': _XCT_DESCRIBE(unsigned int, @"%u")
        case 'l': _XCT_DESCRIBE(long, @"%ld")
        case 'L': _XCT_DESCRIBE(unsigned long, @"%lu")
        case 'q': _XCT_DESCRIBE(long long, @"%lld")
        case 'Q': _XCT_DESCRIBE(unsigned long long, @"%llu")
        case 'B': { bool v; [value getValue:&v]; return v ? @"true" : @"false"; }
        case 'f': { float v; [value getValue:&v]; return _XCTDescriptionForDouble(v); }
        case 'd': { double v; [value getValue:&v]; return _XCTDescriptionForDouble(v); }
        case '*': { char *v; [value getValue:&v]; return v ? [NSString stringWithUTF8String:v] : @"NULL"; }
        case '@':
        case '#': { id v; [value getValue:&v]; return v ? [v description] : @"nil"; }
        case ':': { SEL v; [value getValue:&v]; return v ? NSStringFromSelector(v) : @"NULL"; }
        case '^': { void *v; [value getValue:&v]; return [NSString stringWithFormat:@"%p", v]; }
        default:
            return [value description];
    }

#undef _XCT_DESCRIBE
}
