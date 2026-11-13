#import <Foundation/Foundation.h>

@class MLConfigEntry;

typedef NS_ENUM(NSInteger, MLShortcutKind) {
    MLShortcutKindDirectory, // Cursor 최근 폴더
    MLShortcutKindWebsite,
    MLShortcutKindCommand,
    MLShortcutKindApps,      // 시스템의 전체 앱 탐색
};

// 첫 화면 하단에 표시하는 항목입니다. 버튼이 항목을 직접 보관하므로 종류를 인덱스로 계산하지 않습니다.
@interface MLShortcut : NSObject
@property (nonatomic, readonly) MLShortcutKind kind;
@property (nonatomic, readonly, copy) NSString *title;
// 폴더와 Apps는 파일 URL, 웹사이트는 http(s) URL이며 명령은 nil입니다.
@property (nonatomic, readonly) NSURL *url;
// 명령 항목의 본문이며 다른 종류는 nil입니다.
@property (nonatomic, readonly, copy) NSString *command;
@property (nonatomic, readonly, copy) NSString *toolTip;
@property (nonatomic, readonly) NSString *accessibilityLabel;
// 최근 폴더 → 웹사이트 → 명령 → Apps 순서로 만듭니다. appsURL이 nil이면 Apps를 생략합니다.
+ (NSArray<MLShortcut *> *)shortcutsWithDirectories:(NSArray<NSURL *> *)directories
                                           websites:(NSArray<MLConfigEntry *> *)websites
                                           commands:(NSArray<MLConfigEntry *> *)commands
                                            appsURL:(NSURL *)appsURL;
@end
