#import <Foundation/Foundation.h>

@interface CommandStore : NSObject
@property (nonatomic, readonly) NSArray<NSDictionary<NSString *, NSString *> *> *commands;
@property (nonatomic, readonly) NSArray<NSDictionary<NSString *, NSString *> *> *websites;
@property (nonatomic, readonly) NSError *error;
@property (nonatomic, readonly) BOOL refreshing;
@property (nonatomic, copy) void (^didRefresh)(void);
- (instancetype)initWithURL:(NSURL *)url;
- (void)refresh;
// 설정 열기 메뉴에서만 호출하며 기존 파일은 덮어쓰지 않습니다.
+ (BOOL)ensureConfigurationAtURL:(NSURL *)url error:(NSError **)error;
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)commandsAtURL:(NSURL *)url error:(NSError **)error;
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)websitesAtURL:(NSURL *)url error:(NSError **)error;
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)appIconsAtURL:(NSURL *)url error:(NSError **)error;
@end
