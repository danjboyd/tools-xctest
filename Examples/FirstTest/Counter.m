#import "Counter.h"

@implementation Counter
@synthesize value = _value;

- (void) increment
{
  _value++;
}

- (void) reset
{
  _value = 0;
}
@end
