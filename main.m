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

#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>

#import <Foundation/Foundation.h>
#import <XCTest/GSXCTestRunner.h>
#import <XCTest/XCTestAssertionsImpl.h>

static void PrintUsage(FILE *stream)
{
    fprintf(stream, "Usage: xctest [options] <test bundle path>\n");
    fprintf(stream, "\n");
    fprintf(stream, "Options:\n");
    fprintf(stream, "  -only-testing:<identifier>  Run only tests matching TestTarget[/TestClass[/TestMethod]]\n");
    fprintf(stream, "  -skip-testing:<identifier>  Skip tests matching TestTarget[/TestClass[/TestMethod]]\n");
    fprintf(stream, "  -output-format <format>     Console output: 'classic' (default) or 'apple'\n");
    fprintf(stream, "  -junit-report <path>        Also write results to <path> as JUnit XML\n");
    fprintf(stream, "  -list-tests                 List the selected tests, one identifier per line, without running them\n");
    fprintf(stream, "  -list-tests-json            List the selected tests as JSON, without running them\n");
    fprintf(stream, "  -host <app>                 Run the tests inside a running application (.app or executable)\n");
    fprintf(stream, "  -performance-baselines <path>  Fail measured tests that regress against these baselines (JSON)\n");
    fprintf(stream, "  -update-performance-baselines  Record measured averages into the -performance-baselines file\n");
    fprintf(stream, "  -test-iterations <n>        Run each test n times (the maximum, with the two options below)\n");
    fprintf(stream, "  -run-tests-until-failure    Repeat each test until it fails (at most 100 times by default)\n");
    fprintf(stream, "  -retry-tests-on-failure     Retry a failing test until it passes (at most 3 times by default)\n");
    fprintf(stream, "  -h, --help                  Show this help message\n");
}

static NSString *TargetNameForBundlePath(NSString *testBundlePath)
{
    NSString *bundleName = [[testBundlePath lastPathComponent] stringByDeletingPathExtension];
    return [bundleName length] > 0 ? bundleName : nil;
}

// libXCTestHost sits next to libXCTest; XCTEST_HOST_LIBRARY overrides it.
static NSString *HostLibraryPath(void)
{
    const char *override = getenv("XCTEST_HOST_LIBRARY");
    Dl_info info;

    if (override != NULL && *override != '\0') {
        return [NSString stringWithUTF8String:override];
    }

    if (dladdr((void *)_XCTFailureHandler, &info) == 0 || info.dli_fname == NULL) {
        return nil;
    }

    return [[[NSString stringWithUTF8String:info.dli_fname] stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:@"libXCTestHost.so"];
}

// Launches the host application with libXCTestHost preloaded, which runs
// the tests once the application has finished launching. Returns the exit
// code for xctest.
static int RunTestsInHost(NSString *hostPath, NSString *testBundlePath, NSString *targetName,
                          NSArray *onlyTestIdentifiers, NSArray *skipTestIdentifiers,
                          GSXCTestOutputFormat outputFormat, NSString *junitReportPath,
                          NSString *performanceBaselinesPath, BOOL updatePerformanceBaselines,
                          GSXCTestRepetitionMode repetitionMode, NSInteger testIterations)
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *executable = hostPath;
    NSString *hostLibrary = HostLibraryPath();
    NSString *statusFile = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"xctest-host-%d-%@", getpid(), [[NSProcessInfo processInfo] globallyUniqueString]]];
    BOOL isDirectory = NO;

    if (![fileManager fileExistsAtPath:hostPath isDirectory:&isDirectory]) {
        fprintf(stderr, "xctest: could not find host application '%s'\n", [hostPath UTF8String]);
        return 1;
    }
    if (isDirectory) {
        executable = [[NSBundle bundleWithPath:hostPath] executablePath];
    }
    if (executable == nil || ![fileManager isExecutableFileAtPath:executable]) {
        fprintf(stderr, "xctest: host application '%s' has no executable\n", [hostPath UTF8String]);
        return 1;
    }
    if (hostLibrary == nil || ![fileManager fileExistsAtPath:hostLibrary]) {
        fprintf(stderr, "xctest: could not find libXCTestHost (set XCTEST_HOST_LIBRARY)\n");
        return 1;
    }

    NSMutableDictionary *config = [NSMutableDictionary dictionary];
    [config setObject:[[testBundlePath stringByStandardizingPath] stringByResolvingSymlinksInPath] forKey:@"bundlePath"];
    [config setObject:[testBundlePath lastPathComponent] forKey:@"bundleName"];
    [config setObject:(targetName ? targetName : @"") forKey:@"targetName"];
    [config setObject:onlyTestIdentifiers forKey:@"only"];
    [config setObject:skipTestIdentifiers forKey:@"skip"];
    [config setObject:(outputFormat == GSXCTestOutputFormatApple ? @"apple" : @"classic") forKey:@"outputFormat"];
    [config setObject:statusFile forKey:@"statusFile"];
    [config setObject:[NSNumber numberWithInt:repetitionMode] forKey:@"repetitionMode"];
    [config setObject:[NSNumber numberWithInteger:testIterations] forKey:@"testIterations"];
    if (performanceBaselinesPath != nil) {
        [config setObject:([performanceBaselinesPath isAbsolutePath] ? performanceBaselinesPath
                           : [[fileManager currentDirectoryPath] stringByAppendingPathComponent:performanceBaselinesPath])
                   forKey:@"performanceBaselines"];
        [config setObject:[NSNumber numberWithBool:updatePerformanceBaselines] forKey:@"updatePerformanceBaselines"];
    }
    if (junitReportPath != nil) {
        NSString *absoluteReport = [junitReportPath isAbsolutePath] ? junitReportPath
            : [[fileManager currentDirectoryPath] stringByAppendingPathComponent:junitReportPath];
        [config setObject:absoluteReport forKey:@"junitReport"];
    }

    NSData *configJSON = [NSJSONSerialization dataWithJSONObject:config options:0 error:NULL];
    NSMutableDictionary *environment = [[[[NSProcessInfo processInfo] environment] mutableCopy] autorelease];
    NSString *originalPreload = [environment objectForKey:@"LD_PRELOAD"];

    [environment setObject:[[[NSString alloc] initWithData:configJSON encoding:NSUTF8StringEncoding] autorelease]
                    forKey:@"XCTEST_HOST_CONFIG"];
    [environment setObject:(originalPreload ? originalPreload : @"") forKey:@"XCTEST_HOST_ORIGINAL_LD_PRELOAD"];
    [environment setObject:([originalPreload length] > 0
                            ? [NSString stringWithFormat:@"%@:%@", hostLibrary, originalPreload]
                            : hostLibrary)
                    forKey:@"LD_PRELOAD"];

    NSTask *task = [[[NSTask alloc] init] autorelease];
    [task setLaunchPath:executable];
    [task setArguments:[NSArray array]];
    [task setEnvironment:environment];
    [task launch];
    [task waitUntilExit];

    BOOL testsRan = [fileManager fileExistsAtPath:statusFile];
    [fileManager removeItemAtPath:statusFile error:NULL];

    if ([task terminationReason] == NSTaskTerminationReasonUncaughtSignal) {
        fprintf(stderr, "xctest: host application crashed (signal %d)\n", [task terminationStatus]);
        return 1;
    }
    if (!testsRan) {
        fprintf(stderr, "xctest: host application exited (status %d) before running the tests\n",
            [task terminationStatus]);
        return 1;
    }

    return [task terminationStatus] == 0 ? 0 : 1;
}

// Prints the tests a run would select. Returns NO if a filter is invalid.
static BOOL ListTests(GSXCTestRunner *runner, NSString *testBundlePath, NSString *targetName,
                      NSArray *onlyTestIdentifiers, NSArray *skipTestIdentifiers, BOOL asJSON)
{
    NSArray *identifiers = [runner testIdentifiersForTargetName:targetName
                                            onlyTestIdentifiers:onlyTestIdentifiers
                                            skipTestIdentifiers:skipTestIdentifiers];

    if (identifiers == nil) {
        return NO;
    }

    if (!asJSON) {
        for (NSString *identifier in identifiers) {
            printf("%s\n", [identifier UTF8String]);
        }
        return YES;
    }

    NSMutableArray *tests = [NSMutableArray arrayWithCapacity:[identifiers count]];
    for (NSString *identifier in identifiers) {
        NSArray *components = [identifier componentsSeparatedByString:@"/"];
        [tests addObject:[NSDictionary dictionaryWithObjectsAndKeys:
            identifier, @"identifier",
            [components objectAtIndex:1], @"class",
            [components objectAtIndex:2], @"method",
            nil]];
    }

    NSDictionary *listing = [NSDictionary dictionaryWithObjectsAndKeys:
        [testBundlePath lastPathComponent], @"bundle",
        targetName, @"target",
        tests, @"tests",
        nil];
    NSError *error = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:listing
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:&error];
    if (json == nil) {
        fprintf(stderr, "xctest: could not encode test list as JSON: %s\n",
            [[error localizedDescription] UTF8String]);
        return NO;
    }

    fwrite([json bytes], 1, [json length], stdout);
    printf("\n");
    return YES;
}

int main(int argc, char *argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int exitCode = 1;
    NSMutableArray *onlyTestIdentifiers = [NSMutableArray array];
    NSMutableArray *skipTestIdentifiers = [NSMutableArray array];
    NSString *testBundlePath = nil;
    GSXCTestOutputFormat outputFormat = GSXCTestOutputFormatClassic;
    NSString *junitReportPath = nil;
    BOOL listTests = NO;
    BOOL listTestsAsJSON = NO;
    NSString *hostPath = nil;
    NSString *performanceBaselinesPath = nil;
    BOOL updatePerformanceBaselines = NO;
    NSInteger testIterations = 0;
    BOOL runUntilFailure = NO;
    BOOL retryOnFailure = NO;
    GSXCTestRepetitionMode repetitionMode = GSXCTestRepetitionNone;

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

        if ([argument isEqualToString:@"-output-format"]) {
            NSString *format = (i + 1 < argc) ? [NSString stringWithUTF8String:argv[++i]] : nil;
            if ([format isEqualToString:@"apple"]) {
                outputFormat = GSXCTestOutputFormatApple;
            } else if ([format isEqualToString:@"classic"]) {
                outputFormat = GSXCTestOutputFormatClassic;
            } else {
                fprintf(stderr, "xctest: -output-format must be 'classic' or 'apple'\n");
                PrintUsage(stderr);
                goto cleanup;
            }
            continue;
        }

        if ([argument isEqualToString:@"-list-tests"]) {
            listTests = YES;
            continue;
        }

        if ([argument isEqualToString:@"-list-tests-json"]) {
            listTests = YES;
            listTestsAsJSON = YES;
            continue;
        }

        if ([argument isEqualToString:@"-performance-baselines"]) {
            if (i + 1 >= argc) {
                fprintf(stderr, "xctest: missing path for -performance-baselines\n");
                PrintUsage(stderr);
                goto cleanup;
            }
            performanceBaselinesPath = [NSString stringWithUTF8String:argv[++i]];
            continue;
        }

        if ([argument isEqualToString:@"-test-iterations"]) {
            testIterations = (i + 1 < argc) ? atoi(argv[++i]) : 0;
            if (testIterations < 1) {
                fprintf(stderr, "xctest: -test-iterations needs a number of at least 1\n");
                PrintUsage(stderr);
                goto cleanup;
            }
            continue;
        }

        if ([argument isEqualToString:@"-run-tests-until-failure"]) {
            runUntilFailure = YES;
            continue;
        }

        if ([argument isEqualToString:@"-retry-tests-on-failure"]) {
            retryOnFailure = YES;
            continue;
        }

        if ([argument isEqualToString:@"-update-performance-baselines"]) {
            updatePerformanceBaselines = YES;
            continue;
        }

        if ([argument isEqualToString:@"-host"]) {
            if (i + 1 >= argc) {
                fprintf(stderr, "xctest: missing application for -host\n");
                PrintUsage(stderr);
                goto cleanup;
            }
            hostPath = [NSString stringWithUTF8String:argv[++i]];
            continue;
        }

        if ([argument isEqualToString:@"-junit-report"]) {
            if (i + 1 >= argc) {
                fprintf(stderr, "xctest: missing path for -junit-report\n");
                PrintUsage(stderr);
                goto cleanup;
            }
            junitReportPath = [NSString stringWithUTF8String:argv[++i]];
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

    if (runUntilFailure && retryOnFailure) {
        fprintf(stderr, "xctest: -run-tests-until-failure and -retry-tests-on-failure can't be combined\n");
        goto cleanup;
    }
    if (runUntilFailure) {
        repetitionMode = GSXCTestRepetitionUntilFailure;
        testIterations = testIterations ? testIterations : 100;
    } else if (retryOnFailure) {
        repetitionMode = GSXCTestRepetitionRetryOnFailure;
        testIterations = testIterations ? testIterations : 3;
    } else if (testIterations > 0) {
        repetitionMode = GSXCTestRepetitionFixed;
    }

    if (updatePerformanceBaselines && performanceBaselinesPath == nil) {
        fprintf(stderr, "xctest: -update-performance-baselines needs -performance-baselines <path>\n");
        goto cleanup;
    }

    if (testBundlePath == nil) {
        fprintf(stderr, "xctest: missing test bundle path\n");
        PrintUsage(stderr);
        goto cleanup;
    }

    // In a host application the bundle is loaded there, not here.
    if (hostPath != nil && !listTests) {
        exitCode = RunTestsInHost(hostPath, testBundlePath, TargetNameForBundlePath(testBundlePath),
                                  onlyTestIdentifiers, skipTestIdentifiers, outputFormat, junitReportPath,
                                  performanceBaselinesPath, updatePerformanceBaselines,
                                  repetitionMode, testIterations);
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
    GSXCTestRunner *runner = [GSXCTestRunner sharedRunner];

    if (listTests) {
        exitCode = ListTests(runner, testBundlePath, targetName,
                             onlyTestIdentifiers, skipTestIdentifiers, listTestsAsJSON) ? 0 : 1;
        goto cleanup;
    }

    [runner setOutputFormat:outputFormat];
    [runner setBundleName:[testBundlePath lastPathComponent]];
    [runner setTestBundle:testBundle];
    [runner setPerformanceBaselinesPath:performanceBaselinesPath];
    [runner setUpdatePerformanceBaselines:updatePerformanceBaselines];
    [runner setRepetitionMode:repetitionMode];
    [runner setTestIterations:(NSUInteger)testIterations];
    [runner setJunitReportPath:junitReportPath];
    BOOL result = [runner runTestsForTargetName:targetName
                            onlyTestIdentifiers:onlyTestIdentifiers
                            skipTestIdentifiers:skipTestIdentifiers];
    exitCode = result == YES ? 0 : 1;

cleanup:
    [pool release];
    return exitCode;
}
