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
#include <stdarg.h>
#include <string.h>

@implementation _XCTestCaseInterruptionException
@end

void _XCTFailureHandler(XCTestCase *test, BOOL expected, const char *filePath,
    NSUInteger lineNumber, NSString *condition, NSString *format, ...)
{
    NSString *message = nil;
    if ([format length] > 0) {
        va_list args;
        va_start(args, format);
        message = [[[NSString alloc] initWithFormat:format arguments:args] autorelease];
        va_end(args);
    }
    _XCTPreformattedFailureHandler(test, expected,
        filePath ? [NSString stringWithUTF8String:filePath] : nil, lineNumber, condition, message);
}

void _XCTPreformattedFailureHandler(XCTestCase *test, BOOL expected, NSString *filePath,
    NSUInteger lineNumber, NSString *condition, NSString *message)
{
    NSString *description = [message length] ?
        [NSString stringWithFormat:@"%@: %@", condition, message] : condition;
    [test recordFailureWithDescription:description inFile:filePath atLine:lineNumber expected:expected];
}

NSString *_XCTFailureFormat(_XCTAssertionType type, NSUInteger index)
{
    static NSString *formats[][4] = {
        {@"failed", nil, nil, nil},
        {@"%@ is %@; expected nil", @"%@ threw %@", @"%@ threw an unknown exception", nil},
        {@"%@ is nil; expected non-nil", @"%@ threw %@", @"%@ threw an unknown exception", nil},
        {@"%@ and %@ are not equal (%@ and %@)", @"%@ or %@ threw %@", @"%@ or %@ threw an unknown exception", nil},
        {@"%@ and %@ are equal (%@ and %@)", @"%@ or %@ threw %@", @"%@ or %@ threw an unknown exception", nil},
        {@"%@ and %@ are not equal (%@ and %@)", @"%@ or %@ threw %@", @"%@ or %@ threw an unknown exception", nil},
        {@"%@ and %@ are equal (%@ and %@)", @"%@ or %@ threw %@", @"%@ or %@ threw an unknown exception", nil},
        {@"%@ and %@ differ by more than %@ (%@ and %@, accuracy %@)", @"%@, %@ or %@ threw %@", @"%@, %@ or %@ threw an unknown exception", nil},
        {@"%@ and %@ are equal within %@ (%@ and %@, accuracy %@)", @"%@, %@ or %@ threw %@", @"%@, %@ or %@ threw an unknown exception", nil},
        {@"%@ is not greater than %@ (%@ and %@)", @"%@ or %@ threw %@", @"%@ or %@ threw an unknown exception", nil},
        {@"%@ is not greater than or equal to %@ (%@ and %@)", @"%@ or %@ threw %@", @"%@ or %@ threw an unknown exception", nil},
        {@"%@ is not less than %@ (%@ and %@)", @"%@ or %@ threw %@", @"%@ or %@ threw an unknown exception", nil},
        {@"%@ is not less than or equal to %@ (%@ and %@)", @"%@ or %@ threw %@", @"%@ or %@ threw an unknown exception", nil},
        {@"%@ is false; expected true", @"%@ threw %@", @"%@ threw an unknown exception", nil},
        {@"%@ is true; expected false", @"%@ threw %@", @"%@ threw an unknown exception", nil},
        {@"%@ did not throw an exception", nil, nil, nil},
        {@"%@ expected %@ but threw %@ (%@)", @"%@ expected %@ but threw an unknown exception", @"%@ did not throw %@", nil},
        {@"%@ expected %@ named %@ but threw %@ named %@ (%@)", @"%@ expected %@ named %@ but threw %@ named %@ (%@)", @"%@ expected %@ named %@ but threw an unknown exception", @"%@ did not throw %@ named %@"},
        {@"%@ threw %@", @"%@ threw an unknown exception", nil, nil},
        {@"%@ must not throw %@ but threw %@ (%@)", nil, nil, nil},
        {@"%@ must not throw %@ named %@ but threw %@ named %@ (%@)", nil, nil, nil}
    };
    if ((NSUInteger)type >= sizeof(formats) / sizeof(formats[0]) || index >= 4 || !formats[type][index])
        return @"assertion failed";
    return formats[type][index];
}

NSString *_XCTDescriptionForValue(NSValue *value)
{
    const char *type = [value objCType];
    while (*type && strchr("rnNoORV", *type)) type++;
#define DESCRIBE(code, ctype, format, cast) \
    case code: { ctype number; [value getValue:&number]; return [NSString stringWithFormat:format, (cast)number]; }
    switch (*type) {
        DESCRIBE('c', signed char, @"%lld", long long)
        DESCRIBE('s', short, @"%lld", long long)
        DESCRIBE('i', int, @"%lld", long long)
        DESCRIBE('l', long, @"%lld", long long)
        DESCRIBE('q', long long, @"%lld", long long)
        DESCRIBE('C', unsigned char, @"%llu", unsigned long long)
        DESCRIBE('S', unsigned short, @"%llu", unsigned long long)
        DESCRIBE('I', unsigned int, @"%llu", unsigned long long)
        DESCRIBE('L', unsigned long, @"%llu", unsigned long long)
        DESCRIBE('Q', unsigned long long, @"%llu", unsigned long long)
        DESCRIBE('B', _Bool, @"%d", int)
        DESCRIBE('f', float, @"%.9g", double)
        DESCRIBE('d', double, @"%.17g", double)
        DESCRIBE('D', long double, @"%.21Lg", long double)
        default: return [value description];
    }
#undef DESCRIBE
}
