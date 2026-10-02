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

#include <stdio.h>

#import <Foundation/Foundation.h>
#import <XCTest/GSXCTestRunner.h>

static void PrintUsage(FILE *stream)
{
    fprintf(stream, "Usage: xctest [options] <test bundle path>\n");
    fprintf(stream, "\n");
    fprintf(stream, "Options:\n");
    fprintf(stream, "  -only-testing:<identifier>  Run only tests matching TestTarget[/TestClass[/TestMethod]]\n");
    fprintf(stream, "  -skip-testing:<identifier>  Skip tests matching TestTarget[/TestClass[/TestMethod]]\n");
    fprintf(stream, "  -h, --help                  Show this help message\n");
}

static NSString *TargetNameForBundlePath(NSString *testBundlePath)
{
    NSString *bundleName = [[testBundlePath lastPathComponent] stringByDeletingPathExtension];
    return [bundleName length] > 0 ? bundleName : nil;
}

int main(int argc, char *argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int exitCode = 1;
    NSMutableArray *onlyTestIdentifiers = [NSMutableArray array];
    NSMutableArray *skipTestIdentifiers = [NSMutableArray array];
    NSString *testBundlePath = nil;

    if (argc == 1) {
        PrintUsage(stderr);
        goto cleanup;
    }

    for (int i = 1; i < argc; i++) {
        NSString *argument = [NSString stringWithUTF8String:argv[i]];

        if ([argument isEqualToString:@"-h"] ||
            [argument isEqualToString:@"--help"] ||
            [argument isEqualToString:@"-help"])
        {
            PrintUsage(stdout);
            exitCode = 0;
            goto cleanup;
        }

        if ([argument hasPrefix:@"-only-testing:"]) {
            NSString *identifier = [argument substringFromIndex:[@"-only-testing:" length]];
            if ([identifier length] == 0) {
                fprintf(stderr, "xctest: missing value for -only-testing\n");
                PrintUsage(stderr);
                goto cleanup;
            }

            [onlyTestIdentifiers addObject:identifier];
            continue;
        }

        if ([argument hasPrefix:@"-skip-testing:"]) {
            NSString *identifier = [argument substringFromIndex:[@"-skip-testing:" length]];
            if ([identifier length] == 0) {
                fprintf(stderr, "xctest: missing value for -skip-testing\n");
                PrintUsage(stderr);
                goto cleanup;
            }

            [skipTestIdentifiers addObject:identifier];
            continue;
        }

        if ([argument hasPrefix:@"-"]) {
            fprintf(stderr, "xctest: unknown option '%s'\n", argv[i]);
            PrintUsage(stderr);
            goto cleanup;
        }

        if (testBundlePath != nil) {
            fprintf(stderr, "xctest: only one test bundle path may be provided\n");
            PrintUsage(stderr);
            goto cleanup;
        }

        testBundlePath = argument;
    }

    if (testBundlePath == nil) {
        fprintf(stderr, "xctest: missing test bundle path\n");
        PrintUsage(stderr);
        goto cleanup;
    }

    NSURL *testBundleUrl = [NSURL fileURLWithPath: testBundlePath];
    NSBundle *testBundle = [NSBundle bundleWithURL: testBundleUrl];
    if (testBundle == nil) {
        fprintf(stderr, "xctest: could not create bundle for path '%s'\n", [testBundlePath UTF8String]);
        goto cleanup;
    }

    if (![testBundle load]) {
        fprintf(stderr, "xctest: failed to load bundle '%s'\n", [testBundlePath UTF8String]);
        goto cleanup;
    }

    NSString *targetName = TargetNameForBundlePath(testBundlePath);
    BOOL result = [[GSXCTestRunner sharedRunner] runTestsForTargetName:targetName
                                                   onlyTestIdentifiers:onlyTestIdentifiers
                                                   skipTestIdentifiers:skipTestIdentifiers];
    exitCode = result == YES ? 0 : 1;

cleanup:
    [pool release];
    return exitCode;
}
