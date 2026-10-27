#import <Cocoa/Cocoa.h>
#import "AppCatalog.h"
#import "GestureRecognizer.h"
#import "SleepController.h"
#import "SleepLog.h"
#import <IOKit/pwr_mgt/IOPMLib.h>
static void check(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"실패: %@", message); exit(1); }
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
    SleepLog *log = [[SleepLog alloc] initWithDirectoryURL:root];
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
        gestureTests(); catalogTests(); groupingTests(); sleepTests(); sleepLogTests();
        puts("통과: 제스처 인식, Finder alias/폴더, Tag 그룹, 잠자기 방지 요청 및 로그 테스트");
    }
    return 0;
}
