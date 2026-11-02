#import <Cocoa/Cocoa.h>

@interface TerminalCommand : NSObject
+ (void)run:(NSString *)command completion:(void (^)(NSString *error))completion;
@end
