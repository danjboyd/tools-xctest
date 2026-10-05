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

// libXCTestHost: preloaded into a host application by `xctest -host`.
// When the application finishes launching, it loads the test bundle, runs
// the tests on the main thread inside the running application, and exits
// with the result. It does nothing unless XCTEST_HOST_CONFIG is set, and
// does not link AppKit: it only listens for the launch notification.

#import <Foundation/Foundation.h>
#import <XCTest/GSXCTestRunner.h>

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

// Settings from xctest, as JSON: bundlePath, targetName, bundleName, only,
// skip, outputFormat, junitReport, attachmentsPath, performanceBaselines,
// updatePerformanceBaselines, repetitionMode, testIterations,
// testTimeoutsEnabled, defaultExecutionTimeAllowance,
// maximumExecutionTimeAllowance, statusFile.
// "<statusFile>.started" is created when the tests start, so xctest can
// tell a slow test run from an app that never finished launching.
static NSDictionary *GSHostConfig = nil;

@interface GSXCTestHostLoader : NSObject
@end

@implementation GSXCTestHostLoader

+ (void) load
{
    const char *config = getenv("XCTEST_HOST_CONFIG");
    const char *originalPreload = getenv("XCTEST_HOST_ORIGINAL_LD_PRELOAD");

    if (config == NULL) {
        return;
    }

    @autoreleasepool {
        NSData *data = [NSData dataWithBytes:config length:strlen(config)];

        GSHostConfig = [[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] retain];

        // Processes the application starts must not run the tests again.
        unsetenv("XCTEST_HOST_CONFIG");
        if (originalPreload != NULL && *originalPreload != '\0') {
            setenv("LD_PRELOAD", originalPreload, 1);
        } else {
            unsetenv("LD_PRELOAD");
        }
        unsetenv("XCTEST_HOST_ORIGINAL_LD_PRELOAD");

        if (![GSHostConfig isKindOfClass:[NSDictionary class]]) {
            fprintf(stderr, "xctest: invalid XCTEST_HOST_CONFIG\n");
            return;
        }

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidFinishLaunching:)
                                                     name:@"NSApplicationDidFinishLaunchingNotification"
                                                   object:nil];
    }
}

+ (void) applicationDidFinishLaunching: (NSNotification *)notification
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    // Let the application's own launch handlers run first.
    [self performSelector:@selector(runTests) withObject:nil afterDelay:0];
}

// Tells xctest the tests ran, so it can tell this exit apart from the
// application quitting on its own.
static void GSWriteStatusFile(int exitCode)
{
    NSString *statusFile = [GSHostConfig objectForKey:@"statusFile"];

    if ([statusFile isKindOfClass:[NSString class]]) {
        [[NSString stringWithFormat:@"%d\n", exitCode] writeToFile:statusFile
                                                         atomically:YES
                                                           encoding:NSUTF8StringEncoding
                                                              error:NULL];
    }
}

+ (void) runTests
{
    int exitCode = 1;

    @autoreleasepool {
        NSString *bundlePath = [GSHostConfig objectForKey:@"bundlePath"];
        NSString *junitReport = [GSHostConfig objectForKey:@"junitReport"];
        NSString *statusFile = [GSHostConfig objectForKey:@"statusFile"];
        NSBundle *bundle = nil;

        if ([statusFile isKindOfClass:[NSString class]]) {
            [@"" writeToFile:[statusFile stringByAppendingString:@".started"]
                  atomically:NO
                    encoding:NSUTF8StringEncoding
                       error:NULL];
        }

        bundle = [NSBundle bundleWithPath:bundlePath];

        if (bundle == nil || ![bundle load]) {
            fprintf(stderr, "xctest: host could not load test bundle '%s'\n", [bundlePath UTF8String]);
        } else {
            GSXCTestRunner *runner = [GSXCTestRunner sharedRunner];

            [runner setTestBundle:bundle];
            [runner setBundleName:[GSHostConfig objectForKey:@"bundleName"]];
            [runner setOutputFormat:[[GSHostConfig objectForKey:@"outputFormat"] isEqual:@"apple"]
                ? GSXCTestOutputFormatApple : GSXCTestOutputFormatClassic];
            if ([junitReport isKindOfClass:[NSString class]]) {
                [runner setJunitReportPath:junitReport];
            }
            if ([[GSHostConfig objectForKey:@"attachmentsPath"] isKindOfClass:[NSString class]]) {
                [runner setAttachmentsPath:[GSHostConfig objectForKey:@"attachmentsPath"]];
            }
            [runner setRepetitionMode:(GSXCTestRepetitionMode)[[GSHostConfig objectForKey:@"repetitionMode"] intValue]];
            [runner setTestIterations:[[GSHostConfig objectForKey:@"testIterations"] unsignedIntegerValue]];
            [runner setTestTimeoutsEnabled:[[GSHostConfig objectForKey:@"testTimeoutsEnabled"] boolValue]];
            [runner setDefaultExecutionTimeAllowance:[[GSHostConfig objectForKey:@"defaultExecutionTimeAllowance"] doubleValue]];
            [runner setMaximumExecutionTimeAllowance:[[GSHostConfig objectForKey:@"maximumExecutionTimeAllowance"] doubleValue]];
            // A test that runs out of time ends the application early.
            [runner setTerminationHandler:^(int code) {
                GSWriteStatusFile(code);
                fflush(stdout);
                fflush(stderr);
                _exit(code);
            }];
            if ([[GSHostConfig objectForKey:@"performanceBaselines"] isKindOfClass:[NSString class]]) {
                [runner setPerformanceBaselinesPath:[GSHostConfig objectForKey:@"performanceBaselines"]];
                [runner setUpdatePerformanceBaselines:[[GSHostConfig objectForKey:@"updatePerformanceBaselines"] boolValue]];
            }

            exitCode = [runner runTestsForTargetName:[GSHostConfig objectForKey:@"targetName"]
                                 onlyTestIdentifiers:[GSHostConfig objectForKey:@"only"]
                                 skipTestIdentifiers:[GSHostConfig objectForKey:@"skip"]] ? 0 : 1;
        }

        GSWriteStatusFile(exitCode);
    }

    fflush(stdout);
    fflush(stderr);
    exit(exitCode);
}

@end
