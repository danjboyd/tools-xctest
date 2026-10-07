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
#if defined(_WIN32)
#include <fcntl.h>
#include <io.h>
#else
#include <dlfcn.h>
#include <signal.h>
#endif
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
    fprintf(stream, "  -XCTest <tests>             Apple's xctest selection: All, or Class[/method],... (comma-separated)\n");
    fprintf(stream, "  -output-format <format>     Console output: 'classic' (default) or 'apple'\n");
    fprintf(stream, "  -junit-report <path>        Also write results to <path> as JUnit XML\n");
    fprintf(stream, "  -attachments-path <dir>     Save test attachments under <dir> (default: next to the\n");
    fprintf(stream, "                              -junit-report, as <report>-attachments)\n");
    fprintf(stream, "  -list-tests                 List the selected tests, one identifier per line, without running them\n");
    fprintf(stream, "  -list-tests-json            List the selected tests as JSON, without running them\n");
    fprintf(stream, "  -host <app>                 Run the tests inside a running application (.app or executable)\n");
    fprintf(stream, "  -host-launch-timeout <s>    Give up if the host hasn't started the tests after <s> seconds\n");
    fprintf(stream, "                              (default 60; 0 waits forever; test time doesn't count)\n");
    fprintf(stream, "  -performance-baselines <path>  Fail measured tests that regress against these baselines (JSON)\n");
    fprintf(stream, "  -update-performance-baselines  Record measured averages into the -performance-baselines file\n");
    fprintf(stream, "  -test-iterations <n>        Run each test n times (the maximum, with the two options below)\n");
    fprintf(stream, "  -run-tests-until-failure    Repeat each test until it fails (at most 100 times by default)\n");
    fprintf(stream, "  -retry-tests-on-failure     Retry a failing test until it passes (at most 3 times by default)\n");
    fprintf(stream, "  -test-execution-order <order>  'alphabetical' (default) or 'random' (classes, and tests\n");
    fprintf(stream, "                              within each class, shuffled; the seed is logged)\n");
    fprintf(stream, "  -test-execution-order-seed <n>  Repeat a random order (implies -test-execution-order random)\n");
    fprintf(stream, "  -parallel-testing-enabled YES|NO  Run test classes in parallel worker processes (default NO)\n");
    fprintf(stream, "  -parallel-testing-worker-count <n>  How many at once (default: one per CPU;\n");
    fprintf(stream, "                              implies -parallel-testing-enabled YES)\n");
    fprintf(stream, "  -test-timeouts-enabled YES|NO  Fail a test that runs longer than its execution time allowance,\n");
    fprintf(stream, "                              then stop the run (default NO)\n");
    fprintf(stream, "  -default-test-execution-time-allowance <s>  Each test's allowance unless it sets its own\n");
    fprintf(stream, "                              (default 600; implies -test-timeouts-enabled YES)\n");
    fprintf(stream, "  -maximum-test-execution-time-allowance <s>  Cap on any test's allowance\n");
    fprintf(stream, "                              (implies -test-timeouts-enabled YES)\n");
    fprintf(stream, "  -h, --help                  Show this help message\n");
}

// Parses a number of seconds greater than 0 from argv[i + 1]; returns -1
// if there is none or it isn't valid.
static NSTimeInterval ParseSeconds(int argc, char *argv[], int i)
{
    char *end = NULL;
    double seconds = (i + 1 < argc) ? strtod(argv[i + 1], &end) : -1;

    if (end == NULL || end == argv[i + 1] || *end != '\0' || seconds <= 0) {
        return -1;
    }
    return seconds;
}

static NSString *TargetNameForBundlePath(NSString *testBundlePath)
{
    NSString *bundleName = [[testBundlePath lastPathComponent] stringByDeletingPathExtension];
    return [bundleName length] > 0 ? bundleName : nil;
}

#if defined(_WIN32)
// -host preloads libXCTestHost into the application with LD_PRELOAD, which
// Windows has no equivalent of.
static int RunTestsInHost(NSString *hostPath, NSString *testBundlePath, NSString *targetName,
                          NSArray *onlyTestIdentifiers, NSArray *skipTestIdentifiers,
                          GSXCTestOutputFormat outputFormat, NSString *junitReportPath,
                          NSString *attachmentsPath,
                          NSString *performanceBaselinesPath, BOOL updatePerformanceBaselines,
                          GSXCTestRepetitionMode repetitionMode, NSInteger testIterations,
                          BOOL randomOrder, unsigned long long orderSeed,
                          BOOL testTimeoutsEnabled, NSTimeInterval defaultAllowance,
                          NSTimeInterval maximumAllowance, NSTimeInterval launchTimeout)
{
    fprintf(stderr, "xctest: -host is not supported on Windows\n");
    return 1;
}
#else
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
                          NSString *attachmentsPath,
                          NSString *performanceBaselinesPath, BOOL updatePerformanceBaselines,
                          GSXCTestRepetitionMode repetitionMode, NSInteger testIterations,
                          BOOL randomOrder, unsigned long long orderSeed,
                          BOOL testTimeoutsEnabled, NSTimeInterval defaultAllowance,
                          NSTimeInterval maximumAllowance, NSTimeInterval launchTimeout)
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *executable = hostPath;
    NSString *hostLibrary = HostLibraryPath();
    NSString *statusFile = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"xctest-host-%d-%@", getpid(), [[NSProcessInfo processInfo] globallyUniqueString]]];
    BOOL isDirectory = NO;

    // NSBundle needs an absolute path.
    if (![hostPath isAbsolutePath]) {
        hostPath = [[fileManager currentDirectoryPath] stringByAppendingPathComponent:hostPath];
    }
    hostPath = [hostPath stringByStandardizingPath];
    executable = hostPath;

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
    [config setObject:[NSNumber numberWithBool:randomOrder] forKey:@"randomizeExecutionOrder"];
    [config setObject:[NSNumber numberWithUnsignedLongLong:orderSeed] forKey:@"executionOrderSeed"];
    [config setObject:[NSNumber numberWithBool:testTimeoutsEnabled] forKey:@"testTimeoutsEnabled"];
    [config setObject:[NSNumber numberWithDouble:defaultAllowance] forKey:@"defaultExecutionTimeAllowance"];
    [config setObject:[NSNumber numberWithDouble:maximumAllowance] forKey:@"maximumExecutionTimeAllowance"];
    if (performanceBaselinesPath != nil) {
        [config setObject:([performanceBaselinesPath isAbsolutePath] ? performanceBaselinesPath
                           : [[fileManager currentDirectoryPath] stringByAppendingPathComponent:performanceBaselinesPath])
                   forKey:@"performanceBaselines"];
        [config setObject:[NSNumber numberWithBool:updatePerformanceBaselines] forKey:@"updatePerformanceBaselines"];
    }
    if (attachmentsPath != nil) {
        [config setObject:([attachmentsPath isAbsolutePath] ? attachmentsPath
                           : [[fileManager currentDirectoryPath] stringByAppendingPathComponent:attachmentsPath])
                   forKey:@"attachmentsPath"];
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
    NSString *startedFile = [statusFile stringByAppendingString:@".started"];
    NSDate *launchDeadline = [NSDate dateWithTimeIntervalSinceNow:launchTimeout];
    BOOL testsStarted = NO;
    BOOL timedOut = NO;

    [task launch];

    // Until the tests start, the app only gets launchTimeout seconds; after
    // that it can take as long as the tests need.
    while ([task isRunning]) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        if (!testsStarted) {
            testsStarted = [fileManager fileExistsAtPath:startedFile];
        }
        if (!testsStarted && launchTimeout > 0 && [launchDeadline timeIntervalSinceNow] <= 0 && [task isRunning]) {
            timedOut = YES;
            [task terminate];
            NSDate *killDeadline = [NSDate dateWithTimeIntervalSinceNow:5];
            while ([task isRunning] && [killDeadline timeIntervalSinceNow] > 0) {
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
            }
            if ([task isRunning]) {
                kill([task processIdentifier], SIGKILL);
            }
            break;
        }
    }
    [task waitUntilExit];

    BOOL testsRan = [fileManager fileExistsAtPath:statusFile];
    [fileManager removeItemAtPath:statusFile error:NULL];
    [fileManager removeItemAtPath:startedFile error:NULL];

    if (timedOut) {
        fprintf(stderr, "xctest: host application didn't start the tests within %g seconds "
                "(see -host-launch-timeout); stopped it\n", launchTimeout);
        return 1;
    }

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
#endif

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

    // targetName can be nil; it must not end the argument list early.
    NSDictionary *listing = [NSDictionary dictionaryWithObjectsAndKeys:
        [testBundlePath lastPathComponent], @"bundle",
        (targetName ? targetName : @""), @"target",
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
#if defined(_WIN32)
    // "\n" stays "\n", as on other systems: test lists and JSON are read by
    // scripts, and Windows consoles show it as a line break.
    _setmode(_fileno(stdout), _O_BINARY);
    _setmode(_fileno(stderr), _O_BINARY);
#endif
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int exitCode = 1;
    NSMutableArray *onlyTestIdentifiers = [NSMutableArray array];
    NSMutableArray *skipTestIdentifiers = [NSMutableArray array];
    NSMutableArray *appleSelections = nil;
    NSString *testBundlePath = nil;
    GSXCTestOutputFormat outputFormat = GSXCTestOutputFormatClassic;
    NSString *junitReportPath = nil;
    NSString *attachmentsPath = nil;
    BOOL listTests = NO;
    BOOL listTestsAsJSON = NO;
    NSString *hostPath = nil;
    NSTimeInterval hostLaunchTimeout = 60;
    NSString *performanceBaselinesPath = nil;
    BOOL updatePerformanceBaselines = NO;
    NSInteger testIterations = 0;
    BOOL runUntilFailure = NO;
    BOOL retryOnFailure = NO;
    GSXCTestRepetitionMode repetitionMode = GSXCTestRepetitionNone;
    BOOL randomOrder = NO;
    BOOL parallel = NO;
    BOOL parallelOptionGiven = NO;
    NSInteger workerCount = 0;
    NSString *workerResultsPath = nil;
    unsigned long long orderSeed = 0;
    BOOL testTimeoutsEnabled = NO;
    BOOL testTimeoutsOptionGiven = NO;
    NSTimeInterval defaultAllowance = 0;
    NSTimeInterval maximumAllowance = 0;

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

        // Apple's `xctest -XCTest Class/method,Class2 Bundle.xctest`, as
        // Xcode runs it; the bundle's name is the target.
        if ([argument isEqualToString:@"-XCTest"]) {
            NSString *selection = (i + 1 < argc) ? [NSString stringWithUTF8String:argv[++i]] : nil;
            if ([selection length] == 0) {
                fprintf(stderr, "xctest: missing tests for -XCTest\n");
                PrintUsage(stderr);
                goto cleanup;
            }
            if (![selection isEqualToString:@"All"]) {
                if (appleSelections == nil) {
                    appleSelections = [NSMutableArray array];
                }
                for (NSString *test in [selection componentsSeparatedByString:@","]) {
                    if ([test length] > 0) {
                        [appleSelections addObject:test];
                    }
                }
            }
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

        if ([argument isEqualToString:@"-parallel-testing-enabled"]) {
            NSString *value = (i + 1 < argc) ? [NSString stringWithUTF8String:argv[++i]] : nil;
            if ([value caseInsensitiveCompare:@"YES"] == NSOrderedSame) {
                parallel = YES;
            } else if ([value caseInsensitiveCompare:@"NO"] == NSOrderedSame) {
                parallel = NO;
            } else {
                fprintf(stderr, "xctest: -parallel-testing-enabled must be YES or NO\n");
                PrintUsage(stderr);
                goto cleanup;
            }
            parallelOptionGiven = YES;
            continue;
        }

        if ([argument isEqualToString:@"-parallel-testing-worker-count"]) {
            workerCount = (i + 1 < argc) ? atoi(argv[++i]) : 0;
            if (workerCount < 1) {
                fprintf(stderr, "xctest: -parallel-testing-worker-count needs a number of at least 1\n");
                PrintUsage(stderr);
                goto cleanup;
            }
            continue;
        }

        // Internal: run as a parallel run's worker (see GSXCTestRunner).
        if ([argument isEqualToString:@"-gs-parallel-worker-results"]) {
            if (i + 1 >= argc) {
                fprintf(stderr, "xctest: missing path for -gs-parallel-worker-results\n");
                goto cleanup;
            }
            workerResultsPath = [NSString stringWithUTF8String:argv[++i]];
            continue;
        }

        if ([argument isEqualToString:@"-test-execution-order"]) {
            NSString *order = (i + 1 < argc) ? [NSString stringWithUTF8String:argv[++i]] : nil;
            if ([order isEqualToString:@"random"]) {
                randomOrder = YES;
            } else if ([order isEqualToString:@"alphabetical"]) {
                randomOrder = NO;
            } else {
                fprintf(stderr, "xctest: -test-execution-order must be 'alphabetical' or 'random'\n");
                PrintUsage(stderr);
                goto cleanup;
            }
            continue;
        }

        if ([argument isEqualToString:@"-test-execution-order-seed"]) {
            char *end = NULL;
            const char *value = (i + 1 < argc) ? argv[++i] : "";
            orderSeed = strtoull(value, &end, 10);
            if (*value == '\0' || *value == '-' || end == NULL || *end != '\0' || orderSeed == 0) {
                fprintf(stderr, "xctest: -test-execution-order-seed needs a whole number greater than 0\n");
                PrintUsage(stderr);
                goto cleanup;
            }
            randomOrder = YES;
            continue;
        }

        if ([argument isEqualToString:@"-test-timeouts-enabled"]) {
            NSString *value = (i + 1 < argc) ? [NSString stringWithUTF8String:argv[++i]] : nil;
            if ([value caseInsensitiveCompare:@"YES"] == NSOrderedSame) {
                testTimeoutsEnabled = YES;
            } else if ([value caseInsensitiveCompare:@"NO"] == NSOrderedSame) {
                testTimeoutsEnabled = NO;
            } else {
                fprintf(stderr, "xctest: -test-timeouts-enabled must be YES or NO\n");
                PrintUsage(stderr);
                goto cleanup;
            }
            testTimeoutsOptionGiven = YES;
            continue;
        }

        if ([argument isEqualToString:@"-default-test-execution-time-allowance"]
            || [argument isEqualToString:@"-maximum-test-execution-time-allowance"]) {
            NSTimeInterval seconds = ParseSeconds(argc, argv, i++);
            if (seconds < 0) {
                fprintf(stderr, "xctest: %s needs a number of seconds greater than 0\n", argv[i - 1]);
                PrintUsage(stderr);
                goto cleanup;
            }
            if ([argument hasPrefix:@"-default"]) {
                defaultAllowance = seconds;
            } else {
                maximumAllowance = seconds;
            }
            continue;
        }

        if ([argument isEqualToString:@"-update-performance-baselines"]) {
            updatePerformanceBaselines = YES;
            continue;
        }

        if ([argument isEqualToString:@"-host-launch-timeout"]) {
            char *end = NULL;
            hostLaunchTimeout = (i + 1 < argc) ? strtod(argv[++i], &end) : -1;
            if (end == NULL || *end != '\0' || hostLaunchTimeout < 0) {
                fprintf(stderr, "xctest: -host-launch-timeout needs a number of seconds (0 for none)\n");
                PrintUsage(stderr);
                goto cleanup;
            }
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

        if ([argument isEqualToString:@"-attachments-path"]) {
            if (i + 1 >= argc) {
                fprintf(stderr, "xctest: missing directory for -attachments-path\n");
                PrintUsage(stderr);
                goto cleanup;
            }
            attachmentsPath = [NSString stringWithUTF8String:argv[++i]];
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

    if (!parallelOptionGiven && workerCount > 0) {
        parallel = YES;
    }
    if (parallel && hostPath != nil && !listTests) {
        fprintf(stderr, "xctest: -parallel-testing-enabled can't be used with -host\n");
        goto cleanup;
    }
    if (parallel && updatePerformanceBaselines) {
        fprintf(stderr, "xctest: -update-performance-baselines can't be used with -parallel-testing-enabled\n");
        goto cleanup;
    }

    // Giving an allowance turns time limits on, unless they were turned off.
    if (!testTimeoutsOptionGiven && (defaultAllowance > 0 || maximumAllowance > 0)) {
        testTimeoutsEnabled = YES;
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

    // -XCTest selections are TestTarget/... identifiers for this bundle.
    for (NSString *test in appleSelections) {
        NSString *target = TargetNameForBundlePath(testBundlePath);

        // Class.method is accepted as well as Apple's Class/method.
        if ([test rangeOfString:@"/"].location == NSNotFound) {
            test = [test stringByReplacingOccurrencesOfString:@"." withString:@"/"];
        }
        [onlyTestIdentifiers addObject:[NSString stringWithFormat:@"%@/%@", target ? target : @"", test]];
    }

    // In a host application the bundle is loaded there, not here.
    if (hostPath != nil && !listTests) {
        exitCode = RunTestsInHost(hostPath, testBundlePath, TargetNameForBundlePath(testBundlePath),
                                  onlyTestIdentifiers, skipTestIdentifiers, outputFormat, junitReportPath,
                                  attachmentsPath,
                                  performanceBaselinesPath, updatePerformanceBaselines,
                                  repetitionMode, testIterations, randomOrder, orderSeed,
                                  testTimeoutsEnabled,
                                  defaultAllowance, maximumAllowance, hostLaunchTimeout);
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

    [runner setRandomizeExecutionOrder:randomOrder];
    [runner setExecutionOrderSeed:orderSeed];

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
    [runner setAttachmentsPath:attachmentsPath];
    [runner setTestTimeoutsEnabled:testTimeoutsEnabled];
    [runner setDefaultExecutionTimeAllowance:defaultAllowance];
    [runner setMaximumExecutionTimeAllowance:maximumAllowance];
    [runner setWorkerResultsPath:workerResultsPath];
    if (parallel && workerResultsPath == nil) {
        exitCode = [runner runTestsInParallelForTargetName:targetName
                                       onlyTestIdentifiers:onlyTestIdentifiers
                                       skipTestIdentifiers:skipTestIdentifiers
                                               workerCount:(NSUInteger)workerCount] ? 0 : 1;
        goto cleanup;
    }
    BOOL result = [runner runTestsForTargetName:targetName
                            onlyTestIdentifiers:onlyTestIdentifiers
                            skipTestIdentifiers:skipTestIdentifiers];
    exitCode = result == YES ? 0 : 1;

cleanup:
    [pool release];
    return exitCode;
}
