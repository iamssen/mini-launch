#import "LauncherShortcut.h"
#import "ConfigStore.h"

static BOOL Same(id a, id b) { return a == b || [a isEqual:b]; }

@implementation MLShortcut
+ (instancetype)shortcutWithKind:(MLShortcutKind)kind title:(NSString *)title url:(NSURL *)url
                         command:(NSString *)command toolTip:(NSString *)toolTip {
    MLShortcut *shortcut = [self new];
    shortcut->_kind = kind;
    shortcut->_title = [title copy];
    shortcut->_url = url;
    shortcut->_command = [command copy];
    shortcut->_toolTip = [toolTip copy];
    return shortcut;
}
+ (NSArray<MLShortcut *> *)shortcutsWithDirectories:(NSArray<NSURL *> *)directories
                                           websites:(NSArray<MLConfigEntry *> *)websites
                                           commands:(NSArray<MLConfigEntry *> *)commands
                                            appsURL:(NSURL *)appsURL {
    NSMutableArray<MLShortcut *> *shortcuts = [NSMutableArray array];
    for (NSURL *directory in directories) {
        // 파일 URL의 이름은 분해형으로 올 수 있어 앱 Grid의 이름과 같이 조합형으로 맞춥니다.
        NSString *name = directory.lastPathComponent.precomposedStringWithCanonicalMapping;
        [shortcuts addObject:[self shortcutWithKind:MLShortcutKindDirectory title:name
            url:directory command:nil toolTip:directory.path]];
    }
    for (MLConfigEntry *website in websites) {
        // 툴팁에는 인코딩하지 않은 설정 원문을 그대로 보여 줍니다.
        [shortcuts addObject:[self shortcutWithKind:MLShortcutKindWebsite title:website.name
            url:[NSURL URLWithString:website.value] command:nil toolTip:website.value]];
    }
    for (MLConfigEntry *command in commands) {
        [shortcuts addObject:[self shortcutWithKind:MLShortcutKindCommand title:command.name
            url:nil command:command.value toolTip:command.value]];
    }
    if (appsURL) {
        [shortcuts addObject:[self shortcutWithKind:MLShortcutKindApps title:@"Apps…"
            url:appsURL command:nil toolTip:@"모든 앱 탐색"]];
    }
    return shortcuts;
}
- (NSString *)accessibilityLabel {
    switch (self.kind) {
        case MLShortcutKindDirectory: return [NSString stringWithFormat:@"Cursor로 열기: %@", self.title];
        case MLShortcutKindWebsite: return [NSString stringWithFormat:@"기본 브라우저로 열기: %@", self.title];
        case MLShortcutKindCommand: return [NSString stringWithFormat:@"명령 실행: %@", self.title];
        case MLShortcutKindApps: return @"Apps에서 모든 앱 탐색";
    }
    return self.title;
}
// 캐시가 바뀌었을 때만 화면을 다시 그리도록 내용으로 비교합니다.
- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:MLShortcut.class]) return NO;
    MLShortcut *other = object;
    return _kind == other->_kind && Same(_title, other->_title) && Same(_url, other->_url) &&
           Same(_command, other->_command) && Same(_toolTip, other->_toolTip);
}
- (NSUInteger)hash { return (NSUInteger)_kind ^ _title.hash ^ _toolTip.hash; }
@end
