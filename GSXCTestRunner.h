//
//  GSXCTestRunner.h
//  Eggplant
//
//  Created by Adam Fox on 9/17/18.
//  Copyright © 2018 TestPlant, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface GSXCTestRunner : NSObject {
    NSLock *runLock;
}

- (BOOL)runAll;
- (BOOL)runTestsNamed:(NSArray *)testNames; // nil for all tests

- (void)waitForCompletion;

+ (GSXCTestRunner *)sharedRunner;

@end
