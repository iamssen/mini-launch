#import <Cocoa/Cocoa.h>

// 효과 뷰 자체에 마스크를 적용해 창 모서리 바깥의 불투명 영역을 없앱니다.
@interface LauncherBackdrop : NSView
@property (readonly) NSView *effect;
@property BOOL showsTail;
@property CGFloat tailX;
- (void)updateShape;
@end

// 오른클릭과 Control-클릭은 기본 실행 대신 항목 메뉴를 엽니다.
@interface LauncherActionButton : NSButton
@property (nonatomic) BOOL selected;
@end

@interface LauncherDirectoryButton : LauncherActionButton
@end

// 기본 NSButtonCell의 이미지/제목 배치 대신 일정한 크기로 직접 그립니다.
@interface LauncherIconButton : LauncherActionButton
@end
