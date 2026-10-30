#import "AppCatalog.h"
#import <sys/stat.h>
@implementation MLItem
@end
@implementation AppCatalog
+ (BOOL)isProtectedApplicationAtURL:(NSURL *)url {
    if (!url.isFileURL) return NO;
    NSURL *target = url.URLByResolvingSymlinksInPath.URLByStandardizingPath;
    NSString *path = target.path;
    // alias는 호출 시점에 해석되어 있습니다. Safari 등의 심볼릭 링크도 실제 경로로 판별합니다.
    for (NSString *root in @[@"/System/Applications", @"/System/Library", @"/System/Cryptexes", @"/System/Volumes/Preboot"]) {
        if ([path isEqualToString:root] || [path hasPrefix:[root stringByAppendingString:@"/"]]) return YES;
    }
    // 설치 위치나 Apple의 번들 식별자만으로 삭제 가능 여부를 추측하지 않습니다.
    struct stat information;
    return stat(target.fileSystemRepresentation, &information) == 0 && (information.st_flags & SF_RESTRICTED) != 0;
}
+ (NSArray<MLItem *> *)itemsAtURL:(NSURL *)url error:(NSError **)error {
    NSArray *urls = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:url
        includingPropertiesForKeys:@[NSURLIsAliasFileKey, NSURLIsDirectoryKey, NSURLIsApplicationKey, NSURLTagNamesKey]
        options:NSDirectoryEnumerationSkipsHiddenFiles error:error];
    if (!urls) return @[];
    NSMutableArray *items = [NSMutableArray array];
    for (NSURL *source in urls) {
        NSNumber *alias = nil;
        [source getResourceValue:&alias forKey:NSURLIsAliasFileKey error:nil];
        NSError *resolveError = nil;
        NSURL *target = alias.boolValue
            ? [NSURL URLByResolvingAliasFileAtURL:source
                options:NSURLBookmarkResolutionWithoutUI | NSURLBookmarkResolutionWithoutMounting error:&resolveError]
            : source.URLByResolvingSymlinksInPath;
        NSNumber *directory = nil, *application = nil;
        [target getResourceValue:&directory forKey:NSURLIsDirectoryKey error:nil];
        [target getResourceValue:&application forKey:NSURLIsApplicationKey error:nil];
        BOOL exists = target && [[NSFileManager defaultManager] fileExistsAtPath:target.path];
        // 일반 파일은 제외하고, 깨진 alias는 오류 상태로 표시합니다.
        if (!alias.boolValue && exists && !directory.boolValue && !application.boolValue) continue;
        if (!alias.boolValue && !exists) continue;
        MLItem *item = [MLItem new];
        item.sourceURL = source;
        // 실행 대상 앱이 아닌, 사용자가 정리한 alias 자체의 Tag를 읽습니다.
        NSArray<NSString *> *tags = nil;
        [source getResourceValue:&tags forKey:NSURLTagNamesKey error:nil];
        NSMutableSet<NSString *> *normalized = [NSMutableSet set];
        for (NSString *tag in tags) {
            if (tag.length) [normalized addObject:tag.precomposedStringWithCanonicalMapping];
        }
        item.tags = [normalized.allObjects sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
        item.targetURL = target;
        item.name = [[NSFileManager.defaultManager displayNameAtPath:source.path] precomposedStringWithCanonicalMapping];
        if ([item.name.pathExtension.lowercaseString isEqualToString:@"app"])
            item.name = item.name.stringByDeletingPathExtension;
        item.folder = directory.boolValue && !application.boolValue && ![target.pathExtension.lowercaseString isEqualToString:@"app"];
        if (!exists) item.problem = resolveError.localizedDescription ?: @"대상을 찾을 수 없습니다.";
        [items addObject:item];
    }
    return [items sortedArrayUsingComparator:^NSComparisonResult(MLItem *a, MLItem *b) {
        return [a.name localizedStandardCompare:b.name];
    }];
}
// 여러 Tag가 있는 항목은 해당하는 각 그룹에 표시합니다.
+ (NSArray<NSArray<MLItem *> *> *)groupsForItems:(NSArray<MLItem *> *)items {
    NSMutableDictionary<NSString *, NSMutableArray<MLItem *> *> *tagged = [NSMutableDictionary dictionary];
    NSMutableArray<MLItem *> *untagged = [NSMutableArray array];
    NSArray *sorted = [items sortedArrayUsingComparator:^NSComparisonResult(MLItem *a, MLItem *b) {
        return [a.name localizedStandardCompare:b.name];
    }];
    for (MLItem *item in sorted) {
        if (!item.tags.count) [untagged addObject:item];
        for (NSString *tag in [NSSet setWithArray:item.tags ?: @[]]) {
            if (!tagged[tag]) tagged[tag] = [NSMutableArray array];
            [tagged[tag] addObject:item];
        }
    }
    NSMutableArray *groups = [NSMutableArray array];
    for (NSString *tag in [tagged.allKeys sortedArrayUsingSelector:@selector(localizedStandardCompare:)])
        [groups addObject:tagged[tag]];
    if (untagged.count) [groups addObject:untagged];
    return groups;
}
@end
