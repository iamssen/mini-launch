#import <Cocoa/Cocoa.h>
#import "AppCatalog.h"
#import "RecentDirectories.h"
#import "ConfigStore.h"
#import "LauncherShortcut.h"
#import "AppIconUpdater.h"
#import <sqlite3.h>
#import "GestureRecognizer.h"
#import "SleepController.h"
#import "EventLog.h"
#import <IOKit/pwr_mgt/IOPMLib.h>
static void check(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"실패: %@", message); exit(1); }
}
static void setRecentValue(sqlite3 *db, NSString *value) {
    sqlite3_stmt *statement = NULL;
    check(sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO ItemTable VALUES ('history.recentlyOpenedPathsList', ?)", -1, &statement, NULL) == SQLITE_OK,
          @"최근 목록 저장문을 준비합니다.");
    sqlite3_bind_text(statement, 1, value.UTF8String, -1, SQLITE_TRANSIENT);
    check(sqlite3_step(statement) == SQLITE_DONE, @"검증용 최근 목록을 저장합니다.");
    sqlite3_finalize(statement);
}
static void waitForRecent(RecentDirectories *store) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (store.refreshing && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    check(!store.refreshing, @"최근 폴더 비동기 조회가 완료됩니다.");
}
static void recentDirectoryTests(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *root = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    NSURL *first = [root URLByAppendingPathComponent:@"한글 폴더 '첫째'" isDirectory:YES];
    NSURL *second = [root URLByAppendingPathComponent:@"둘째" isDirectory:YES];
    [fm createDirectoryAtURL:first withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtURL:second withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *file = [root URLByAppendingPathComponent:@"메모.txt"];
    [NSData.data writeToURL:file atomically:YES];
    NSURL *database = [root URLByAppendingPathComponent:@"state.vscdb"];
    sqlite3 *db = NULL;
    check(sqlite3_open(database.fileSystemRepresentation, &db) == SQLITE_OK, @"검증용 SQLite 저장소를 엽니다.");
    check(sqlite3_exec(db, "PRAGMA journal_mode=WAL; CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value BLOB)", NULL, NULL, NULL) == SQLITE_OK,
          @"Cursor와 같은 WAL 저장소를 만듭니다.");
    NSArray *entries = @[@{@"folderUri": first.absoluteString}, @{@"folderUri": @"vscode-remote://ssh-remote+test/home/project"},
        @{@"fileUri": file.absoluteString}, @{@"folderUri": file.absoluteString},
        @{@"folderUri": [root URLByAppendingPathComponent:@"없는 폴더"].absoluteString},
        @{@"folderUri": first.absoluteString}, @{@"folderUri": second.absoluteString},
        @{@"folderUri": @123}, NSNull.null];
    NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"entries": entries} options:0 error:nil];
    setRecentValue(db, [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]);
    NSError *error = nil;
    NSArray *directories = [RecentDirectories directoriesAtDatabaseURL:database error:&error];
    check(!error && [directories isEqualToArray:@[first, second]], @"WAL의 최근 순서와 한글·공백을 보존하고 파일·원격·중복·잘못된 항목을 제외합니다.");
    RecentDirectories *store = [[RecentDirectories alloc] initWithDatabaseURL:database];
    __block NSUInteger notifications = 0;
    store.didRefresh = ^{ check(NSThread.isMainThread, @"갱신 알림은 메인 스레드로 전달합니다."); notifications++; };
    [store refresh]; [store refresh];
    check(store.refreshing && store.directories.count == 0, @"갱신 요청은 캐시를 즉시 반환하고 중복 조회를 합칩니다.");
    waitForRecent(store);
    check([store.directories isEqualToArray:directories] && notifications == 1, @"비동기 조회 후 캐시를 교체합니다.");
    [store refresh]; waitForRecent(store);
    check(notifications == 1, @"같은 목록은 화면 갱신을 요청하지 않습니다.");
    setRecentValue(db, @"{잘못된 JSON");
    [store refresh]; waitForRecent(store);
    check([store.directories isEqualToArray:directories] && notifications == 1, @"조회 결과 해석 실패 시 기존 캐시를 유지합니다.");
    setRecentValue(db, @"{\"entries\": {}}");
    error = nil;
    check(![RecentDirectories directoriesAtDatabaseURL:database error:&error] && error, @"저장 형식 변경과 빈 목록을 구별합니다.");
    setRecentValue(db, @"{\"entries\": []}");
    [store refresh]; waitForRecent(store);
    check(store.directories.count == 0 && notifications == 2, @"정상 조회한 빈 목록은 캐시도 비웁니다.");
    sqlite3_close(db);
    NSURL *missing = [root URLByAppendingPathComponent:@"없는 저장소"];
    error = nil;
    check(![RecentDirectories directoriesAtDatabaseURL:missing error:&error] && error, @"저장소 부재를 오류로 구분합니다.");
    check(![fm fileExistsAtPath:missing.path], @"읽기 전용 조회는 없는 저장소를 만들지 않습니다.");
    [fm removeItemAtURL:root error:nil];
}
static void waitForCommands(ConfigStore *store) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (store.refreshing && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    check(!store.refreshing, @"명령 설정 비동기 조회가 완료됩니다.");
}
static void appIconTests(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *root = [fm.temporaryDirectory URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
    NSURL *app = [root URLByAppendingPathComponent:@"아이콘 테스트.app" isDirectory:YES];
    [fm createDirectoryAtURL:app withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *configuration = [root URLByAppendingPathComponent:@"config.yml"];
    [@"commands: {}\napp_icons:\n  아이콘 테스트.app: icon.png\n" writeToURL:configuration
        atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:32 pixelsHigh:32
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    memset(bitmap.bitmapData, 255, bitmap.bytesPerRow * bitmap.pixelsHigh);
    NSURL *png = [root URLByAppendingPathComponent:@"icon.png"];
    [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToURL:png atomically:YES];
    NSURL *logs = [root URLByAppendingPathComponent:@"logs"];
    EventLog *log = [[EventLog alloc] initWithDirectoryURL:logs filePrefix:@"apply-app-icons"];
    NSString *first = MLApplyAppIcons(configuration, log);
    check([first containsString:@"아이콘을 변경했습니다."], first);
    NSString *second = MLApplyAppIcons(configuration, log);
    check(second == nil, @"일치하면 알림을 생략합니다.");
    NSString *mixed = @"app_icons:\n  아이콘 테스트.app: icon.png\n  없는.app: icon.png\n";
    [mixed writeToURL:configuration atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSString *notice = MLApplyAppIcons(configuration, log);
    check([notice containsString:@"없는.app"] && ![notice containsString:@"아이콘 테스트.app"], @"혼합 결과에서는 실패만 알립니다.");
    NSURL *file = [fm contentsOfDirectoryAtURL:logs includingPropertiesForKeys:nil options:0 error:nil].firstObject;
    NSString *records = [NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:nil];
    for (NSString *event in @[@"changed", @"matched", @"failed"]) {
        check([records containsString:[NSString stringWithFormat:@"\"event\":\"%@\"", event]], @"일치·변경·실패를 파일에 기록합니다.");
    }
    [@"app_icons: {아이콘 테스트.app: icon.png}" writeToURL:configuration atomically:YES encoding:NSUTF8StringEncoding error:nil];
    // 같은 흰색 그림을 다른 원본 해상도로 Finder 커스텀 아이콘에 설정합니다.
    NSImage *other = [NSImage imageWithSize:NSMakeSize(512, 512) flipped:NO drawingHandler:^BOOL(NSRect bounds) {
        [NSColor.whiteColor setFill];
        NSRectFill(bounds);
        return YES;
    }];
    check([NSWorkspace.sharedWorkspace setIcon:other forFile:app.path options:0], @"다른 방식으로 아이콘을 설정합니다.");
    check(MLApplyAppIcons(configuration, log) == nil, @"같은 그림을 다시 적용하지 않습니다.");
    NSUInteger blackPixel[] = {0, 0, 0, 255};
    [bitmap setPixel:blackPixel atX:16 y:16];
    [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToURL:png atomically:YES];
    check([MLApplyAppIcons(configuration, log) containsString:@"아이콘을 변경했습니다."], @"한 픽셀이라도 그림이 바뀌면 적용합니다.");
    [NSWorkspace.sharedWorkspace setIcon:nil forFile:app.path options:0];
    check([MLApplyAppIcons(configuration, log) containsString:@"아이콘을 변경했습니다."], @"커스텀 아이콘이 사라지면 다시 적용합니다.");
    [fm removeItemAtURL:root error:nil];
}
static void commandTests(void) {
    NSURL *root = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *url = [root URLByAppendingPathComponent:@"config.yml"];
    NSError *error = nil;
    check([ConfigStore commandsAtURL:url error:&error].count == 0 && !error, @"없는 설정 파일은 명령 없는 정상 상태입니다.");
    check([ConfigStore ensureConfigurationAtURL:url error:&error] && !error, @"메뉴에서 없는 설정 파일을 생성합니다.");
    NSString *initial = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
    check([initial containsString:@"websites: {}\n"] && [initial containsString:@"commands: {}\n"] && [initial containsString:@"# 한 줄 명령 예시:"] &&
        [initial containsString:@"# 여러 줄 명령"], @"기본 설정과 한국어 주석 안내를 포함합니다.");
    check([ConfigStore commandsAtURL:url error:&error].count == 0 && !error, @"생성한 기본 설정은 유효한 빈 명령 목록입니다.");
    check([ConfigStore websitesAtURL:url error:&error].count == 0 && !error, @"생성한 기본 설정은 유효한 빈 웹사이트 목록입니다.");
    [@"" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
    check([ConfigStore commandsAtURL:url error:&error].count == 0 && !error, @"빈 설정 파일은 빈 목록입니다.");
    NSString *yaml = @"commands:\n  \"server:ssh\": ssh -t user@host \"echo test\" # 주석\n  여러줄: |\n    cd Workspace\n    ls -al\n";
    [yaml writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
    check([ConfigStore ensureConfigurationAtURL:url error:&error] &&
        [[NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil] isEqualToString:yaml],
        @"설정 열기는 기존 파일의 명령과 주석을 덮어쓰지 않습니다.");
    NSArray<MLConfigEntry *> *commands = [ConfigStore commandsAtURL:url error:&error];
    CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
    for (NSUInteger i = 0; i < 1000; i++) {
        @autoreleasepool { [ConfigStore commandsAtURL:url error:nil]; }
    }
    NSLog(@"설정 읽기와 YAML 해석 평균: %.3fms (소규모 로컬 설정, 반복 조회)",
          (CFAbsoluteTimeGetCurrent() - started) * 1000 / 1000);
    check(commands.count == 2 && [commands[0].name isEqualToString:@"server:ssh"] &&
          [commands[0].value isEqualToString:@"ssh -t user@host \"echo test\""] &&
          [commands[1].value isEqualToString:@"cd Workspace\nls -al\n"], @"명령 작성 순서와 따옴표·여러 줄을 보존하고 YAML 주석을 해석합니다.");
    ConfigStore *store = [[ConfigStore alloc] initWithURL:url];
    __block NSUInteger notifications = 0;
    store.didRefresh = ^{ check(NSThread.isMainThread, @"설정 갱신은 메인 스레드에 전달됩니다."); notifications++; };
    [store refresh]; [store refresh];
    check(store.refreshing && store.commands.count == 0, @"설정 조회를 비동기로 시작하고 중복 요청을 합칩니다.");
    waitForCommands(store);
    check([store.commands isEqualToArray:commands] && notifications == 1, @"정상 설정을 캐시합니다.");
    [store refresh]; waitForCommands(store);
    check(notifications == 1, @"같은 명령은 화면 갱신을 요청하지 않습니다.");
    NSArray *invalid = @[@"commands: [x]", @"commands: {x: one, x: two}", @"commands: {x: 123}",
        @"commands: {x: []}", @"commands: {x: ''}", @"commands: {'': ls}", @"commands: {x: null}",
        @"commands: [", @"commands: {}\n---\ncommands: {}", @"commands: {}\ncommands: {}"];
    for (NSString *text in invalid) {
        [text writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
        error = nil;
        check(![ConfigStore commandsAtURL:url error:&error] && error, @"잘못된 형식·중복·비문자열·빈 명령·복수 문서를 거부합니다.");
    }
    NSMutableString *deep = [NSMutableString stringWithString:@"commands: "];
    for (NSUInteger i = 0; i < 1100; i++) [deep appendString:@"["];
    for (NSUInteger i = 0; i < 1100; i++) [deep appendString:@"]"];
    [deep writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
    error = nil;
    check(![ConfigStore commandsAtURL:url error:&error] && error, @"과도한 YAML 중첩은 파서 오류로 반환합니다.");
    [store refresh]; waitForCommands(store);
    check(store.error && [store.commands isEqualToArray:commands], @"잘못된 설정은 오류를 알리고 마지막 정상 캐시를 유지합니다.");
    [@"commands: {}" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [store refresh]; waitForCommands(store);
    check(!store.error && store.commands.count == 0, @"수정된 빈 설정은 오류와 명령을 지웁니다.");
    [yaml writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [store refresh]; waitForCommands(store);
    [fm removeItemAtURL:url error:nil];
    [store refresh]; waitForCommands(store);
    check(!store.error && store.commands.count == 0, @"파일 삭제는 캐시를 비웁니다.");
    [fm createDirectoryAtURL:url withIntermediateDirectories:NO attributes:nil error:nil];
    error = nil;
    check(![ConfigStore ensureConfigurationAtURL:url error:&error] && error, @"설정 경로가 폴더이면 생성 실패를 알립니다.");
    [fm removeItemAtURL:root error:nil];
}
static void websiteTests(void) {
    NSURL *root = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *url = [root URLByAppendingPathComponent:@"config.yml"];
    NSError *error = nil;
    check([ConfigStore websitesAtURL:url error:&error].count == 0 && !error, @"없는 설정 파일은 웹사이트 없는 정상 상태입니다.");
    [@"" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
    check([ConfigStore websitesAtURL:url error:&error].count == 0 && !error, @"빈 설정 파일은 웹사이트 없는 정상 상태입니다.");
    NSString *yaml = @"commands: {명령: pwd}\nwebsites:\n  'dagu:local': 'http://localhost:8480'\n  검색: 'https://example.com/search?q=hello&lang=ko#결과'\napp_icons: {}\n";
    [yaml writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSArray *websites = [ConfigStore websitesAtURL:url error:&error];
    check(!error && [websites isEqualToArray:@[
        [MLConfigEntry entryWithName:@"dagu:local" value:@"http://localhost:8480"],
        [MLConfigEntry entryWithName:@"검색" value:@"https://example.com/search?q=hello&lang=ko#결과"]]],
        @"웹사이트 작성 순서와 이름·포트·쿼리·앵커를 보존합니다.");
    ConfigStore *store = [[ConfigStore alloc] initWithURL:url];
    __block NSUInteger notifications = 0;
    store.didRefresh = ^{ check(NSThread.isMainThread, @"웹사이트 갱신은 메인 스레드에 전달됩니다."); notifications++; };
    [store refresh]; [store refresh];
    check(store.refreshing && !store.websites.count, @"웹사이트도 비동기로 조회하며 중복 요청을 합칩니다.");
    waitForCommands(store);
    NSArray *commands = store.commands;
    check([store.websites isEqualToArray:websites] && commands.count == 1 && notifications == 1,
        @"한 설정의 웹사이트와 명령을 함께 캐시합니다.");
    [store refresh]; waitForCommands(store);
    check(notifications == 1, @"같은 웹사이트와 명령은 화면 갱신을 요청하지 않습니다.");
    NSString *changed = [yaml stringByReplacingOccurrencesOfString:@"localhost:8480" withString:@"localhost:8481"];
    [changed writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [store refresh]; waitForCommands(store);
    websites = [ConfigStore websitesAtURL:url error:&error];
    check([store.websites isEqualToArray:websites] && [store.commands isEqualToArray:commands] && notifications == 2,
        @"명령이 같아도 웹사이트 URL 변경을 알립니다.");
    NSArray *invalid = @[@"websites: [x]", @"websites: {x: 'https://example.com', x: 'https://example.org'}",
        @"websites: {x: 123}", @"websites: {x: true}", @"websites: {x: []}", @"websites: {x: ''}",
        @"websites: {'': 'https://example.com'}", @"websites: {x: null}", @"websites: {x: 'example.com'}",
        @"websites: {x: 'https:///path'}", @"websites: {x: 'file:///tmp/example.html'}",
        @"websites: {x: 'javascript:alert(1)'}", @"websites: {x: 'ftp://example.com'}",
        @"websites: {}\nwebsites: {}"];
    for (NSString *text in invalid) {
        [[@"commands: {변경: ls}\n" stringByAppendingString:text] writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
        error = nil;
        check(![ConfigStore websitesAtURL:url error:&error] && error,
            @"웹사이트의 잘못된 형식·중복·빈 값·호스트 없는 주소·HTTP 이외의 스킴을 거부합니다.");
    }
    [store refresh]; waitForCommands(store);
    check(store.error && [store.websites isEqualToArray:websites] && [store.commands isEqualToArray:commands],
        @"웹사이트 설정에 오류가 있으면 웹사이트와 명령 모두 마지막 정상 캐시를 유지합니다.");
    [@"commands: {명령: pwd}" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [store refresh]; waitForCommands(store);
    check(!store.error && !store.websites.count && [store.commands isEqualToArray:commands],
        @"websites 항목을 지우면 웹사이트만 비웁니다.");
    [@"websites: {로컬: 'http://127.0.0.1:8480'}" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [store refresh]; waitForCommands(store);
    check(!store.error && store.websites.count == 1 && !store.commands.count, @"명령 없이 웹사이트만 설정할 수 있습니다.");
    [fm removeItemAtURL:url error:nil];
    [store refresh]; waitForCommands(store);
    check(!store.error && !store.websites.count && !store.commands.count, @"설정 파일 삭제는 웹사이트와 명령을 비웁니다.");
    [fm removeItemAtURL:root error:nil];
}
static void shortcutTests(void) {
    NSURL *first = [NSURL fileURLWithPath:@"/tmp/프로젝트 하나" isDirectory:YES];
    NSURL *second = [NSURL fileURLWithPath:@"/tmp/둘째" isDirectory:YES];
    NSURL *apps = [NSURL fileURLWithPath:@"/System/Applications/Apps.app" isDirectory:YES];
    NSArray *websites = @[[MLConfigEntry entryWithName:@"검색" value:@"https://example.com/search?q=hello"]];
    NSArray *commands = @[[MLConfigEntry entryWithName:@"목록" value:@"cd Workspace\nls -al\n"]];
    NSArray<MLShortcut *> *shortcuts = [MLShortcut shortcutsWithDirectories:@[first, second]
        websites:websites commands:commands appsURL:apps];
    check(shortcuts.count == 5, @"최근 폴더·웹사이트·명령·Apps를 하나의 목록으로 만듭니다.");
    NSArray *kinds = @[@(MLShortcutKindDirectory), @(MLShortcutKindDirectory), @(MLShortcutKindWebsite),
                       @(MLShortcutKindCommand), @(MLShortcutKindApps)];
    NSArray *titles = @[@"프로젝트 하나", @"둘째", @"검색", @"목록", @"Apps…"];
    for (NSUInteger i = 0; i < shortcuts.count; i++) {
        check(shortcuts[i].kind == [kinds[i] integerValue] && [shortcuts[i].title isEqualToString:titles[i]],
              @"하단 항목은 최근 폴더 → 웹사이트 → 명령 → Apps 순서와 표시 이름을 유지합니다.");
    }
    check([shortcuts[0].url isEqual:first] && [shortcuts[0].toolTip isEqualToString:first.path] && !shortcuts[0].command,
          @"폴더 항목은 대상 URL과 전체 경로 툴팁을 가집니다.");
    check([shortcuts[2].url.host isEqualToString:@"example.com"] &&
          [shortcuts[2].toolTip isEqualToString:@"https://example.com/search?q=hello"], @"웹사이트 항목은 URL과 설정 원문 툴팁을 가집니다.");
    check(!shortcuts[3].url && [shortcuts[3].command isEqualToString:@"cd Workspace\nls -al\n"] &&
          [shortcuts[3].toolTip isEqualToString:shortcuts[3].command], @"명령 항목은 본문을 그대로 보존합니다.");
    check([shortcuts[4].url isEqual:apps], @"Apps 항목은 시스템 앱 탐색기를 가리킵니다.");
    check([shortcuts[0].accessibilityLabel containsString:@"Cursor"] && [shortcuts[2].accessibilityLabel containsString:@"브라우저"] &&
          [shortcuts[3].accessibilityLabel containsString:@"명령 실행"], @"종류별 손쉬운 사용 설명을 제공합니다.");
    NSArray *again = [MLShortcut shortcutsWithDirectories:@[first, second] websites:websites commands:commands appsURL:apps];
    check([shortcuts isEqualToArray:again], @"내용이 같은 목록은 같다고 판단하여 화면을 다시 그리지 않습니다.");
    NSArray *changed = [MLShortcut shortcutsWithDirectories:@[first, second]
        websites:@[[MLConfigEntry entryWithName:@"검색" value:@"https://example.org/"]] commands:commands appsURL:apps];
    check(![shortcuts isEqualToArray:changed], @"이름이 같아도 URL이 바뀌면 다른 목록입니다.");
    NSArray *reordered = [MLShortcut shortcutsWithDirectories:@[second, first] websites:websites commands:commands appsURL:apps];
    check(![shortcuts isEqualToArray:reordered], @"최근 순서가 바뀌면 다른 목록입니다.");
    check([MLShortcut shortcutsWithDirectories:@[] websites:@[] commands:@[] appsURL:nil].count == 0,
          @"Apps가 없는 시스템에서 입력이 비면 하단 항목을 만들지 않습니다.");
}
static void gestureTests(void) {
    for (int count = 4; count <= 5; count++) {
        MLGestureState s = {0};
        check(MLRecognize(&s, count, 0.3, 1) == 0, @"첫 프레임은 기준만 저장합니다.");
        check(MLRecognize(&s, count, 0.2, 1.04) == 0, @"너무 빠른 변화는 무시합니다.");
        check(MLRecognize(&s, count, 0.2, 1.1) == -1, @"네 손가락과 다섯 손가락 모으기를 감지합니다.");
        check(MLRecognize(&s, count, 0.15, 1.2) == 0, @"계속 모아도 중복 실행하지 않습니다.");
        check(MLRecognize(&s, count, 0.17, 1.3) == 0, @"작은 역방향 떨림은 무시합니다.");
        check(MLRecognize(&s, count, 0.21, 1.4) == 1, @"손을 떼지 않고 펼쳐 닫습니다.");
        check(MLRecognize(&s, count, 0.3, 1.5) == 0, @"계속 펼쳐도 중복 실행하지 않습니다.");
        check(MLRecognize(&s, count, 0.2, 1.6) == -1, @"다시 모으면 열 수 있습니다.");
        MLRecognize(&s, 0, 0, 1.7);
        MLRecognize(&s, count, 0.2, 2);
        check(MLRecognize(&s, count, 0.28, 2.1) == 1, @"새 접촉에서 펼치기로 시작할 수 있습니다.");
    }
    MLGestureState s = {0};
    MLRecognize(&s, 4, 0.3, 1);
    MLRecognize(&s, 4, 0.25, 1.1);
    check(MLRecognize(&s, 5, 0.5, 1.2) == 0, @"손가락 추가에 따른 거리 증가는 펼치기가 아닙니다.");
    check(MLRecognize(&s, 5, 0.41, 1.3) == -1, @"손가락이 추가되어도 이전 모으기 진행량을 보존합니다.");
    check(MLRecognize(&s, 4, 0.2, 1.4) == 0, @"손가락 제거에 따른 거리 감소는 동작이 아닙니다.");
    check(MLRecognize(&s, 4, 0.2, 1.5) == 0, @"접촉 수 변화 후 정지하면 실행하지 않습니다.");
    check(MLRecognize(&s, 4, 0.27, 1.6) == 1, @"접촉 수 변화 후에도 반대 방향을 인식합니다.");
    s = (MLGestureState){0};
    MLRecognize(&s, 4, 0.3, 2);
    MLRecognize(&s, 4, 0.25, 2.1);
    check(MLRecognize(&s, 3, 0.1, 2.12) == 0, @"세 손가락 프레임은 실행하지 않습니다.");
    check(MLRecognize(&s, 4, 0.2, 2.18) == 0, @"짧은 누락 중 거리 변화는 실행하지 않습니다.");
    check(MLRecognize(&s, 4, 0.17, 2.28) == -1, @"짧은 누락 이전의 진행량을 보존합니다.");
    MLRecognize(&s, 3, 0.1, 2.3);
    check(MLRecognize(&s, 4, 0.4, 2.5) == 0, @"긴 누락 뒤에는 새 기준을 잡습니다.");
    check(MLRecognize(&s, 4, 0.2, 3) == 0, @"끊긴 프레임을 새 접촉으로 처리합니다.");
    check(MLRecognize(&s, 4, NAN, 3.1) == 0, @"유효하지 않은 좌표를 무시합니다.");
    MLRecognize(&s, 3, 0.3, 4);
    check(MLRecognize(&s, 3, 0.1, 4.1) == 0, @"세 손가락만으로는 실행하지 않습니다.");
    MLRecognize(&s, 4, 0.3, 5);
    check(MLRecognize(&s, 4, 0.1, 4.9) == 0, @"시간이 역행하면 새 기준을 잡습니다.");
}
static void catalogTests(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *root = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    [fm createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *group = [root URLByAppendingPathComponent:@"도구"];
    [fm createDirectoryAtURL:group withIntermediateDirectories:NO attributes:nil error:nil];
    [@"제외" writeToURL:[root URLByAppendingPathComponent:@"memo.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [fm createDirectoryAtURL:[root URLByAppendingPathComponent:@".숨김"] withIntermediateDirectories:NO attributes:nil error:nil];
    NSURL *target = [root URLByAppendingPathComponent:@"원본.app"];
    [fm createDirectoryAtURL:target withIntermediateDirectories:NO attributes:nil error:nil];
    NSURL *alias = [root URLByAppendingPathComponent:@"별칭"];
    NSError *error = nil;
    NSData *bookmark = [target bookmarkDataWithOptions:NSURLBookmarkCreationSuitableForBookmarkFile includingResourceValuesForKeys:nil relativeToURL:nil error:&error];
    check(bookmark != nil, @"Finder alias 북마크를 생성합니다.");
    check([NSURL writeBookmarkData:bookmark toURL:alias options:0 error:&error], @"Finder alias 파일을 저장합니다.");
    check([fm createSymbolicLinkAtURL:[root URLByAppendingPathComponent:@"심볼릭"] withDestinationURL:target error:&error], @"심볼릭 링크를 생성합니다.");
    check([alias setResourceValue:@[@"Development"] forKey:NSURLTagNamesKey error:&error], @"alias에 Tag를 지정합니다.");
    check([target setResourceValue:@[@"System"] forKey:NSURLTagNamesKey error:&error], @"대상 앱에 별도 Tag를 지정합니다.");
    NSArray<MLItem *> *items = [AppCatalog itemsAtURL:root error:&error];
    check(!error && items.count == 4, @"앱, alias, 심볼릭 링크, 폴더만 표시합니다.");
    for (MLItem *item in items) {
        if ([item.name isEqualToString:@"도구"]) check(item.folder, @"실제 폴더는 탐색 항목입니다.");
        else check(!item.folder && !item.problem, [NSString stringWithFormat:@"앱 번들과 앱 alias는 실행 항목입니다: %@ / %@ / %@", item.name, item.targetURL, item.problem]);
        if ([item.name isEqualToString:@"별칭"]) check([item.targetURL.URLByResolvingSymlinksInPath.path.precomposedStringWithCanonicalMapping isEqualToString:target.URLByResolvingSymlinksInPath.path.precomposedStringWithCanonicalMapping], @"alias 대상을 해석합니다.");
    }
    MLItem *taggedAlias = nil;
    for (MLItem *item in items) if ([item.name isEqualToString:@"별칭"]) taggedAlias = item;
    check([taggedAlias.tags isEqualToArray:@[@"Development"]], @"대상 앱의 Tag 대신 alias 자체의 Tag를 사용합니다.");
    [fm removeItemAtURL:target error:nil];
    items = [AppCatalog itemsAtURL:root error:nil];
    MLItem *broken = nil;
    for (MLItem *item in items) if ([item.name isEqualToString:@"별칭"]) broken = item;
    check(broken.problem.length > 0, @"깨진 alias의 오류를 보존합니다.");
    error = nil;
    [AppCatalog itemsAtURL:[root URLByAppendingPathComponent:@"없음"] error:&error];
    check(error != nil, @"읽기 실패와 빈 폴더를 구별합니다.");
    [fm removeItemAtURL:root error:nil];
}
static void protectedApplicationTests(void) {
    for (NSString *path in @[@"/System/Applications/Utilities/Activity Monitor.app",
                             @"/System/Library/CoreServices/Finder.app",
                             @"/System/Cryptexes/App/System/Applications/Safari.app",
                             @"/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"]) {
        check([AppCatalog isProtectedApplicationAtURL:[NSURL fileURLWithPath:path]], @"시스템 앱과 Cryptex 영역의 앱을 제외합니다.");
    }
    check(![AppCatalog isProtectedApplicationAtURL:[NSURL fileURLWithPath:@"/System/Applications-Custom/일반.app"]],
          @"이름의 접두사만 같은 경로를 시스템 영역으로 잘못 분류하지 않습니다.");
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *root = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    [fm createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *regular = [root URLByAppendingPathComponent:@"일반.app" isDirectory:YES];
    [fm createDirectoryAtURL:regular withIntermediateDirectories:NO attributes:nil error:nil];
    check(![AppCatalog isProtectedApplicationAtURL:regular], @"일반 설치 앱에는 제거 메뉴를 허용합니다.");
    NSURL *link = [root URLByAppendingPathComponent:@"시스템 앱 링크.app"];
    NSURL *system = [NSURL fileURLWithPath:@"/System/Applications/Utilities/Activity Monitor.app"];
    if ([fm fileExistsAtPath:system.path]) {
        check([fm createSymbolicLinkAtURL:link withDestinationURL:system error:nil], @"시스템 앱의 검증용 링크를 만듭니다.");
        check([AppCatalog isProtectedApplicationAtURL:link], @"일반 위치의 링크도 시스템 앱 실체를 판별합니다.");
    }
    NSURL *xcode = [NSURL fileURLWithPath:@"/Applications/Xcode.app"];
    if ([fm fileExistsAtPath:xcode.path])
        check(![AppCatalog isProtectedApplicationAtURL:xcode], @"별도로 설치한 Apple 앱인 Xcode를 시스템 앱으로 취급하지 않습니다.");
    [fm removeItemAtURL:root error:nil];
}
static MLItem *taggedItem(NSString *name, NSArray *tags) {
    MLItem *item = [MLItem new]; item.name = name; item.tags = tags; return item;
}
static void groupingTests(void) {
    MLItem *devB = taggedItem(@"Beta", @[@"Development"]);
    MLItem *devA = taggedItem(@"Alpha", @[@"Development", @"System"]);
    MLItem *system = taggedItem(@"Settings", @[@"System"]);
    MLItem *other = taggedItem(@"Other", @[]);
    NSArray *groups = [AppCatalog groupsForItems:@[system, other, devB, devA]];
    check(groups.count == 3, @"Tag 그룹 뒤에 미분류 그룹을 배치합니다.");
    check([groups[0] isEqualToArray:@[devA, devB]], @"Development 그룹 안에서 이름순으로 정렬합니다.");
    check([groups[1] isEqualToArray:@[devA, system]], @"여러 Tag는 각 그룹에 표시합니다.");
    check([groups[2] isEqualToArray:@[other]], @"Tag 없는 항목은 마지막에 표시합니다.");
    check([AppCatalog groupsForItems:@[]].count == 0, @"빈 목록에는 그룹을 만들지 않습니다.");
    check([AppCatalog groupsForItems:@[other]].count == 1, @"Tag가 없으면 단일 그룹을 유지합니다.");
}
static void checkSleepAssertions(MLSleepMode mode) {
    CFDictionaryRef result = NULL;
    check(IOPMCopyAssertionsByProcess(&result) == kIOReturnSuccess, @"프로세스별 전원 요청을 조회합니다.");
    NSDictionary *processes = CFBridgingRelease(result);
    NSArray *entries = processes[@(NSProcessInfo.processInfo.processIdentifier)];
    NSMutableSet *types = [NSMutableSet new];
    NSUInteger count = 0;
    for (NSDictionary *entry in entries) {
        if (![entry[(__bridge NSString *)kIOPMAssertionNameKey] isEqualToString:@"MiniLaunch Caffein"]) continue;
        count++;
        [types addObject:entry[(__bridge NSString *)kIOPMAssertionTypeKey]];
        check([entry[(__bridge NSString *)kIOPMAssertionLevelKey] intValue] == kIOPMAssertionLevelOn,
              @"잠자기 방지 요청이 활성 상태입니다.");
    }
    NSMutableSet *wanted = [NSMutableSet new];
    if (mode != MLSleepModeOff) [wanted addObject:(__bridge NSString *)kIOPMAssertionTypePreventUserIdleSystemSleep];
    if (mode == MLSleepModeDisplayAndSystem) [wanted addObject:(__bridge NSString *)kIOPMAssertionTypePreventUserIdleDisplaySleep];
    check(count == wanted.count && [types isEqualToSet:wanted], @"실제 IOKit 요청의 종류와 개수가 선택 모드에 일치합니다.");
}
static void sleepTests(void) {
    SleepController *controller = [SleepController new];
    check(controller.mode == MLSleepModeOff, @"시작 시 잠자기 방지는 꺼져 있습니다.");
    checkSleepAssertions(MLSleepModeOff);
    for (NSNumber *value in @[@(MLSleepModeSystem), @(MLSleepModeSystem), @(MLSleepModeDisplayAndSystem),
                             @(MLSleepModeDisplayAndSystem), @(MLSleepModeSystem), @(MLSleepModeOff),
                             @(MLSleepModeOff), @(MLSleepModeDisplayAndSystem)]) {
        MLSleepMode mode = value.integerValue;
        NSError *error = nil;
        check([controller setMode:mode error:&error], [NSString stringWithFormat:@"잠자기 방지 모드를 전환합니다: %@", error]);
        check(controller.mode == mode, @"전환한 모드를 반환합니다.");
        checkSleepAssertions(mode);
        check([controller.diagnosticState[@"matches"] boolValue], @"진단 조회가 실제 요청과 보유 요청의 일치를 확인합니다.");
    }
    NSDictionary *owned = controller.diagnosticState[@"owned_assertions"];
    NSNumber *identifier = owned[(__bridge NSString *)kIOPMAssertionTypePreventUserIdleDisplaySleep];
    check(IOPMAssertionSetProperty(identifier.unsignedIntValue, kIOPMAssertionLevelKey, (__bridge CFNumberRef)@0) == kIOReturnSuccess,
          @"요청을 비활성화하여 상태 불일치를 재현합니다.");
    check(![controller.diagnosticState[@"matches"] boolValue], @"실제 요청이 비활성화되면 불일치를 감지합니다.");
    controller = nil;
    checkSleepAssertions(MLSleepModeOff);
}
static void sleepLogTests(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *root = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    [fm createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.calendar = calendar;
    formatter.timeZone = calendar.timeZone;
    formatter.dateFormat = @"yyyy-MM-dd";
    NSMutableArray<NSURL *> *files = [NSMutableArray new];
    for (NSNumber *days in @[@0, @-6, @-7, @-30]) {
        NSDate *date = [calendar dateByAddingUnit:NSCalendarUnitDay value:days.integerValue toDate:NSDate.date options:0];
        NSURL *file = [root URLByAppendingPathComponent:[NSString stringWithFormat:@"caffein-%@.jsonl", [formatter stringFromDate:date]]];
        [NSData.data writeToURL:file atomically:YES];
        [files addObject:file];
    }
    NSURL *other = [root URLByAppendingPathComponent:@"notes.txt"];
    [NSData.data writeToURL:other atomically:YES];
    EventLog *log = [[EventLog alloc] initWithDirectoryURL:root filePrefix:@"caffein"];
    SleepController *controller = [SleepController new];
    controller.log = log;
    check([controller setMode:MLSleepModeSystem error:nil], @"로그를 남기면서 잠자기를 방지합니다.");
    check([controller setMode:MLSleepModeOff error:nil], @"로그를 남기면서 요청을 해제합니다.");
    for (NSUInteger i = 0; i < files.count; i++) {
        check([fm fileExistsAtPath:files[i].path] == (i < 2), @"오늘과 이전 6일의 로그만 보관합니다.");
    }
    check([fm fileExistsAtPath:other.path], @"관계없는 파일은 보존합니다.");
    NSString *text = [NSString stringWithContentsOfURL:files[0] encoding:NSUTF8StringEncoding error:nil];
    NSMutableArray *events = [NSMutableArray new];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if (!line.length) continue;
        NSDictionary *entry = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        check(entry[@"timestamp"] && entry[@"pid"], @"각 JSON 행에 시각과 프로세스 번호를 남깁니다.");
        [events addObject:entry[@"event"]];
        if ([entry[@"event"] isEqual:@"mode_applied"]) check([entry[@"matches"] boolValue], @"적용 결과에 실제 요청 검증을 기록합니다.");
    }
    check([events isEqualToArray:@[@"mode_requested", @"assertion_create", @"mode_applied", @"mode_requested", @"assertion_release", @"mode_applied"]],
          @"모드 선택과 요청 생성·해제 및 적용 결과를 순서대로 기록합니다.");
    [fm removeItemAtURL:root error:nil];
}
int main(void) {
    @autoreleasepool {
        appIconTests(); commandTests(); websiteTests(); shortcutTests(); recentDirectoryTests(); gestureTests(); catalogTests(); protectedApplicationTests(); groupingTests(); sleepTests(); sleepLogTests();
        puts("통과: YAML 웹사이트·명령 설정과 비동기 캐시, 하단 항목 목록, Cursor 최근 폴더와 비동기 캐시, 제스처 인식, Finder alias/폴더, Tag 그룹, 잠자기 방지 요청 및 로그 테스트");
    }
    return 0;
}
