#import <Cocoa/Cocoa.h>
@interface LauncherController : NSObject
@property (readonly) BOOL visible;
- (instancetype)initWithRoot:(NSURL *)root;
- (void)showFromDock:(BOOL)fromDock;
- (void)hide;
@end
