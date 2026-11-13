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
// 실행 대상(MLItem 또는 MLShortcut)입니다. 버튼 순서로 대상을 다시 계산하지 않습니다.
@property (nonatomic) id representedEntry;
@end

@interface LauncherDirectoryButton : LauncherActionButton
// 0이면 기본 16pt를 사용하며 지정한 크기는 같은 아이콘 영역의 중앙에 그립니다.
@property (nonatomic) CGFloat iconPointSize;
// 뒤집힌 좌표계에서 양수는 아래쪽으로 이동합니다.
@property (nonatomic) CGFloat iconOffsetY;
@end

// 기본 NSButtonCell의 이미지/제목 배치 대신 일정한 크기로 직접 그립니다.
@interface LauncherIconButton : LauncherActionButton
@end
