#import <Foundation/Foundation.h>
@class EventLog;

typedef NS_ENUM(NSInteger, MLSleepMode) {
    MLSleepModeOff,
    MLSleepModeSystem,
    MLSleepModeDisplayAndSystem,
};

@interface SleepController : NSObject
@property (readonly) MLSleepMode mode;
@property EventLog *log;
- (NSDictionary *)diagnosticState;
- (BOOL)setMode:(MLSleepMode)mode error:(NSError **)error;
@end
