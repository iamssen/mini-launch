#import <Foundation/Foundation.h>

// Cursor의 저장소는 읽기만 하며 캐시 접근과 완료 알림은 메인 스레드에서 처리합니다.
@interface RecentDirectories : NSObject
@property (nonatomic, readonly) BOOL refreshing;
@property (nonatomic, readonly) NSArray<NSURL *> *directories;
@property (nonatomic, copy) void (^didRefresh)(void);
- (instancetype)initWithDatabaseURL:(NSURL *)url;
- (void)refresh;
// nil은 읽기 실패이고 빈 배열은 정상 조회한 빈 목록입니다.
+ (NSArray<NSURL *> *)directoriesAtDatabaseURL:(NSURL *)url error:(NSError **)error;
@end
