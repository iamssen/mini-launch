#import "SleepLog.h"
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>

@implementation SleepLog
- (instancetype)initWithDirectoryURL:(NSURL *)directoryURL {
    if ((self = [super init])) _directoryURL = directoryURL;
    return self;
}
- (void)recordEvent:(NSString *)event fields:(NSDictionary *)fields {
    NSDate *now = NSDate.date;
    NSISO8601DateFormatter *formatter = [NSISO8601DateFormatter new];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    NSString *timestamp = [formatter stringFromDate:now];
    NSString *day = [timestamp substringToIndex:10];
    NSMutableDictionary *record = [fields mutableCopy];
    record[@"timestamp"] = timestamp;
    record[@"event"] = event;
    record[@"pid"] = @(NSProcessInfo.processInfo.processIdentifier);
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingSortedKeys error:&error];
    NSFileManager *fm = NSFileManager.defaultManager;
    if (!data || ![fm createDirectoryAtURL:self.directoryURL withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"Caffein 로그 기록 실패: %@", error);
        return;
    }
    NSURL *file = [self.directoryURL URLByAppendingPathComponent:[NSString stringWithFormat:@"caffein-%@.jsonl", day]];
    int descriptor = open(file.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0600);
    if (descriptor < 0) { NSLog(@"Caffein 로그 열기 실패: %d", errno); return; }
    NSMutableData *line = [data mutableCopy];
    [line appendBytes:"\n" length:1];
    NSUInteger offset = 0;
    while (offset < line.length) {
        ssize_t written = write(descriptor, (const char *)line.bytes + offset, line.length - offset);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) { NSLog(@"Caffein 로그 쓰기 실패: %d", errno); break; }
        offset += (NSUInteger)written;
    }
    close(descriptor);
    // UTC 기준으로 오늘과 이전 6일만 보관하며 다른 파일은 건드리지 않습니다.
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    NSDate *cutoff = [calendar dateByAddingUnit:NSCalendarUnitDay value:-6 toDate:[calendar startOfDayForDate:now] options:0];
    NSDateFormatter *dateFormatter = [NSDateFormatter new];
    dateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    dateFormatter.calendar = calendar;
    dateFormatter.timeZone = calendar.timeZone;
    dateFormatter.dateFormat = @"yyyy-MM-dd";
    for (NSURL *candidate in [fm contentsOfDirectoryAtURL:self.directoryURL includingPropertiesForKeys:nil options:0 error:&error]) {
        NSString *name = candidate.lastPathComponent;
        if (name.length != 24 || ![name hasPrefix:@"caffein-"] || ![name hasSuffix:@".jsonl"]) continue;
        NSNumber *regular = nil;
        [candidate getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
        if (!regular.boolValue) continue;
        NSString *dateString = [name substringWithRange:NSMakeRange(8, 10)];
        NSDate *date = [dateFormatter dateFromString:dateString];
        if (date && [[dateFormatter stringFromDate:date] isEqualToString:dateString] && [date compare:cutoff] == NSOrderedAscending) {
            if (![fm removeItemAtURL:candidate error:&error]) NSLog(@"Caffein 이전 로그 삭제 실패: %@", error);
        }
    }
    if (error) NSLog(@"Caffein 로그 폴더 처리 실패: %@", error);
}
@end
