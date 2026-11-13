#import <Foundation/Foundation.h>

// config.yml 매핑의 한 항목입니다. 섹션에 따라 이름·명령, 이름·URL, 앱 경로·PNG 경로를 뜻합니다.
@interface MLConfigEntry : NSObject
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *value;
+ (instancetype)entryWithName:(NSString *)name value:(NSString *)value;
@end

// 설정 파일을 해석하고 웹사이트·명령을 비동기 메모리 캐시로 제공합니다.
@interface ConfigStore : NSObject
@property (nonatomic, readonly) NSArray<MLConfigEntry *> *commands;
@property (nonatomic, readonly) NSArray<MLConfigEntry *> *websites;
@property (nonatomic, readonly) NSError *error;
@property (nonatomic, readonly) BOOL refreshing;
@property (nonatomic, copy) void (^didRefresh)(void);
// 앱 폴더 안의 설정 파일 위치입니다. 파일 이름은 이곳에서만 정합니다.
+ (NSURL *)configurationURLInDirectory:(NSURL *)directory;
- (instancetype)initWithURL:(NSURL *)url;
- (void)refresh;
// 설정 열기 메뉴에서만 호출하며 기존 파일은 덮어쓰지 않습니다.
+ (BOOL)ensureConfigurationAtURL:(NSURL *)url error:(NSError **)error;
+ (NSArray<MLConfigEntry *> *)commandsAtURL:(NSURL *)url error:(NSError **)error;
+ (NSArray<MLConfigEntry *> *)websitesAtURL:(NSURL *)url error:(NSError **)error;
+ (NSArray<MLConfigEntry *> *)appIconsAtURL:(NSURL *)url error:(NSError **)error;
@end
