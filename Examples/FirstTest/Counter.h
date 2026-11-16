#import <Foundation/Foundation.h>

@interface Counter : NSObject
@property (nonatomic, readonly) NSInteger value;
- (void) increment;
- (void) reset;
@end
