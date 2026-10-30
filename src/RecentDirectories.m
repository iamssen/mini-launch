#import "RecentDirectories.h"
#import <sqlite3.h>

@implementation RecentDirectories {
    NSURL *_databaseURL;
    dispatch_queue_t _queue;
    BOOL _refreshing;
}
- (instancetype)initWithDatabaseURL:(NSURL *)url {
    if (!(self = [super init])) return nil;
    _databaseURL = url;
    _directories = @[];
    _queue = dispatch_queue_create("local.minilaunch.recent-directories", DISPATCH_QUEUE_SERIAL);
    return self;
}
+ (NSArray<NSURL *> *)directoriesAtDatabaseURL:(NSURL *)url error:(NSError **)error {
    sqlite3 *db = NULL;
    sqlite3_stmt *statement = NULL;
    NSData *data = nil;
    int result = sqlite3_open_v2(url.fileSystemRepresentation, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, NULL);
    if (result == SQLITE_OK) {
        // 쓰기 작업과 경합해도 오래 기다리지 않습니다. 실패 시 기존 캐시를 유지합니다.
        sqlite3_busy_timeout(db, 50);
        result = sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key = 'history.recentlyOpenedPathsList'", -1, &statement, NULL);
        if (result == SQLITE_OK) {
            result = sqlite3_step(statement);
            if (result == SQLITE_ROW) {
                data = [NSData dataWithBytes:sqlite3_column_blob(statement, 0) length:sqlite3_column_bytes(statement, 0)];
            }
        }
    }
    NSString *message = db ? [NSString stringWithUTF8String:sqlite3_errmsg(db)] : @"저장소를 열 수 없습니다.";
    sqlite3_finalize(statement);
    if (db) sqlite3_close(db);
    if (result == SQLITE_DONE) return @[];
    if (!data) {
        if (error) *error = [NSError errorWithDomain:@"MiniLaunch.RecentDirectories" code:result
            userInfo:@{NSLocalizedDescriptionKey: message}];
        return nil;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (!json) return nil;
    if (![json isKindOfClass:NSDictionary.class] || ![json[@"entries"] isKindOfClass:NSArray.class]) {
        if (error) *error = [NSError errorWithDomain:@"MiniLaunch.RecentDirectories" code:-1
            userInfo:@{NSLocalizedDescriptionKey: @"Cursor 최근 목록의 형식이 변경되었습니다."}];
        return nil;
    }
    NSMutableArray<NSURL *> *directories = [NSMutableArray array];
    NSMutableSet<NSURL *> *seen = [NSMutableSet set];
    for (id entry in json[@"entries"]) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        id value = entry[@"folderUri"];
        if (![value isKindOfClass:NSString.class]) continue;
        NSURL *folder = [NSURL URLWithString:value];
        // 원격 항목과 파일은 제외하고 DB의 최근 순서를 유지합니다.
        if (!folder.isFileURL || (folder.host.length && ![folder.host isEqualToString:@"localhost"])) continue;
        folder = [NSURL fileURLWithPath:folder.path.stringByStandardizingPath isDirectory:YES];
        if ([seen containsObject:folder]) continue;
        BOOL directory = NO;
        if (![NSFileManager.defaultManager fileExistsAtPath:folder.path isDirectory:&directory] || !directory) continue;
        [seen addObject:folder];
        [directories addObject:folder];
    }
    return directories;
}
- (BOOL)refreshing { return _refreshing; }
- (void)refresh {
    NSAssert(NSThread.isMainThread, @"최근 목록 갱신은 메인 스레드에서 요청합니다.");
    if (_refreshing) return;
    _refreshing = YES;
    NSURL *url = _databaseURL;
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        @autoreleasepool {
            NSArray<NSURL *> *directories = [RecentDirectories directoriesAtDatabaseURL:url error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                RecentDirectories *s = weakSelf;
                if (!s) return;
                s->_refreshing = NO;
                if (!directories || [s.directories isEqualToArray:directories]) return;
                s->_directories = [directories copy];
                if (s.didRefresh) s.didRefresh();
            });
        }
    });
}
@end
