#import <Foundation/Foundation.h>

@class EventLog;

// 작업 큐에서 호출합니다. 모두 일치하면 알림 본문 대신 nil을 반환합니다.
NSString * _Nullable MLApplyAppIcons(NSURL * _Nonnull configuration, EventLog * _Nonnull log);
