#import <Foundation/Foundation.h>

// 메인 스레드에서 호출합니다.
@interface SleepLog : NSObject
@property (readonly) NSURL *directoryURL;
- (instancetype)initWithDirectoryURL:(NSURL *)directoryURL;
- (void)recordEvent:(NSString *)event fields:(NSDictionary *)fields;
@end
