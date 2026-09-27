#import <Foundation/Foundation.h>
@interface GestureMonitor : NSObject
@property (copy) void (^onGesture)(NSInteger direction);
@property (readonly) NSString *status;
@property (readonly) BOOL connected;
- (void)start;
- (void)stop;
@end
