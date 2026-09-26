#import <Cocoa/Cocoa.h>
#import "AppCatalog.h"
#import "GestureRecognizer.h"
static void check(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"실패: %@", message); exit(1); }
}
static void gestureTests(void) {
    MLGestureState s = {0};
    check(MLRecognize(&s, 5, 0.3, 1) == 0, @"첫 프레임은 기준만 저장합니다.");
    check(MLRecognize(&s, 5, 0.2, 1.04) == 0, @"너무 빠른 변화는 무시합니다.");
    check(MLRecognize(&s, 5, 0.2, 1.1) == -1, @"다섯 손가락 모으기를 감지합니다.");
    check(MLRecognize(&s, 5, 0.4, 1.2) == 0, @"한 번의 접촉에서는 중복 실행하지 않습니다.");
    MLRecognize(&s, 4, 0.3, 1.3);
    check(MLRecognize(&s, 5, 0.2, 1.4) == 0, @"손가락 수가 흔들려도 중복 실행하지 않습니다.");
    MLRecognize(&s, 0, 0, 1.5);
    MLRecognize(&s, 5, 0.2, 2);
    check(MLRecognize(&s, 5, 0.28, 2.1) == 1, @"다시 접촉한 뒤 펼치기를 감지합니다.");
    MLRecognize(&s, 0, 0, 3);
    MLRecognize(&s, 4, 0.3, 3.1);
    check(MLRecognize(&s, 4, 0.1, 3.2) == 0, @"네 손가락은 실행하지 않습니다.");
    MLRecognize(&s, 5, 0.3, 4);
    check(MLRecognize(&s, 5, 0.1, 5) == 0, @"끊긴 프레임을 새 접촉으로 처리합니다.");
    check(MLRecognize(&s, 5, NAN, 5.1) == 0, @"유효하지 않은 좌표를 무시합니다.");
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
int main(void) {
    @autoreleasepool {
        gestureTests(); catalogTests(); groupingTests();
        puts("통과: 제스처 인식, Finder alias/폴더 및 Tag 그룹 테스트");
    }
    return 0;
}
