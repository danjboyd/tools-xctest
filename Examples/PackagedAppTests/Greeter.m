#import "Greeter.h"

@implementation Greeter

- (NSString *) greetingForName: (NSString *)name
{
  NSString *trimmed = [name stringByTrimmingCharactersInSet:
    [NSCharacterSet whitespaceAndNewlineCharacterSet]];

  if ([trimmed length] == 0)
    {
      return @"Hello, world!";
    }
  return [NSString stringWithFormat: @"Hello, %@!", trimmed];
}

@end
