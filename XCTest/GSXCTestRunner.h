//
//  GSXCTestRunner.h
//  Eggplant
//
//  Created by Adam Fox on 9/17/18.
//  Copyright © 2018 TestPlant, Inc. All rights reserved.
//
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

#import <Foundation/Foundation.h>

typedef enum {
    /*! "XCTest: ..." log lines (the default). */
    GSXCTestOutputFormatClassic,
    /*! The format of Apple's xctest, with per-test timings, on stdout. */
    GSXCTestOutputFormatApple,
} GSXCTestOutputFormat;

@interface GSXCTestRunner : NSObject {
    NSLock *runLock;
    NSArray *reporters;
    id currentTestResult;
    id currentSuiteResult;
    NSString *currentClassContext;
    GSXCTestOutputFormat outputFormat;
    NSString *bundleName;
    NSString *junitReportPath;
}

@property GSXCTestOutputFormat outputFormat;

/*! The test bundle's file name, used to name its suite in reports. */
@property (copy) NSString *bundleName;

/*! If set, a JUnit XML report is written here after each run. A run that
 * cannot write its report counts as failed. */
@property (copy) NSString *junitReportPath;

- (BOOL)runAll;
- (BOOL)runTestsNamed:(NSArray *)testNames; // nil for all tests
- (BOOL)runTestsForTargetName:(NSString *)targetName
          onlyTestIdentifiers:(NSArray *)onlyTestIdentifiers
          skipTestIdentifiers:(NSArray *)skipTestIdentifiers;

- (void)waitForCompletion;

+ (GSXCTestRunner *)sharedRunner;

@end
