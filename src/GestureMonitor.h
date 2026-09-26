#import <Foundation/Foundation.h>
@interface GestureMonitor : NSObject
@property (copy) void (^onGesture)(NSInteger direction);
@property (readonly) NSString *status;
- (void)start;
- (void)stop;
@end
