#import <Foundation/Foundation.h>

// 날짜별 JSONL 파일에 기록하고 최근 7일을 보관합니다.
@interface EventLog : NSObject
@property (readonly) NSURL *directoryURL;
- (instancetype)initWithDirectoryURL:(NSURL *)directoryURL filePrefix:(NSString *)prefix;
- (void)recordEvent:(NSString *)event fields:(NSDictionary *)fields;
@end
