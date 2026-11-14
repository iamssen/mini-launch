#import "LauncherController.h"
#import "AppCatalog.h"
#import "DockLocator.h"
#import "LauncherAppearance.h"
#import "RecentDirectories.h"
#import "FolderIcon.h"
#import "ConfigStore.h"
#import "LauncherShortcut.h"
#import "ExternalApps.h"
#import "TerminalCommand.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>

static const CGFloat CellWidth = 128;
static const CGFloat CellHeight = 128;
static const CGFloat SideInset = 16;
static const CGFloat GroupGap = 20;

@interface LauncherPanel : NSPanel
@end
@implementation LauncherPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
@end
@interface FlippedView : NSView
@end
@implementation FlippedView
- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return NO; }
@end

@interface LauncherController () <NSWindowDelegate, NSMenuDelegate>
@property LauncherPanel *panel;
@property LauncherBackdrop *backdrop;
@property NSURL *root;
@property NSMutableArray<NSURL *> *path;
@property NSArray<MLItem *> *items;
@property NSArray<NSArray<MLItem *> *> *groups;
@property NSMutableArray<LauncherActionButton *> *buttons;
@property RecentDirectories *recentDirectories;
@property ConfigStore *configStore;
@property NSArray<MLShortcut *> *shortcuts;
@property BOOL commandRunning;
@property NSURL *appsURL;
@property FlippedView *shortcutList;
@property NSString *catalogError;
@property BOOL entering;
@property BOOL trackingMenu;
@property NSTextField *titleLabel;
@property NSTextField *statusLabel;
@property NSButton *back;
@property NSScrollView *scroll;
@property FlippedView *grid;
@property NSInteger selected;
@property NSInteger columns;
@property NSRect availableFrame;
@property NSRect dockIcon;
@property NSRect menuBarAnchor;
@property BOOL dockPresentation;
@property BOOL bottomDock;
@property BOOL hiding;
@property NSUInteger transitionGeneration;
@property id keyMonitor;
@property id clickMonitor;
@end

@implementation LauncherController
- (instancetype)initWithRoot:(NSURL *)root {
    if (!(self = [super init])) return nil;
    _root = root;
    _shortcuts = @[];
    NSURL *appsURL = [NSURL fileURLWithPath:@"/System/Applications/Apps.app" isDirectory:YES];
    if ([NSWorkspace.sharedWorkspace isFilePackageAtPath:appsURL.path]) _appsURL = appsURL;
    _configStore = [[ConfigStore alloc] initWithURL:[ConfigStore configurationURLInDirectory:root]];
    NSURL *database = [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:
        @"Library/Application Support/Cursor/User/globalStorage/state.vscdb"]];
    _recentDirectories = [[RecentDirectories alloc] initWithDatabaseURL:database];
    _path = [NSMutableArray arrayWithObject:root];
    _panel = [[LauncherPanel alloc] initWithContentRect:NSMakeRect(0, 0, 800, 442)
        styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
        backing:NSBackingStoreBuffered defer:NO];
    _panel.delegate = self;
    _panel.opaque = NO;
    _panel.backgroundColor = NSColor.clearColor;
    _panel.hasShadow = YES;
    _panel.level = NSFloatingWindowLevel;
    _panel.hidesOnDeactivate = NO;
    // 앱 활성화로 Space를 옮기지 않고 현재 전체 화면 앱 위에서 입력을 받습니다.
    _panel.becomesKeyOnlyIfNeeded = NO;
    _panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    if (@available(macOS 13.0, *)) {
        _panel.collectionBehavior |= NSWindowCollectionBehaviorCanJoinAllApplications;
    }
    _panel.accessibilityLabel = @"MiniLaunch 앱 실행기";
    _backdrop = [[LauncherBackdrop alloc] initWithFrame:_panel.contentView.bounds];
    _panel.contentView = _backdrop;
    _back = [NSButton buttonWithTitle:@"‹" target:self action:@selector(goBack:)];
    _back.bordered = NO;
    _back.font = [NSFont systemFontOfSize:23 weight:NSFontWeightLight];
    _back.contentTintColor = NSColor.whiteColor;
    _back.toolTip = @"상위 폴더 (⌘↑)";
    [_backdrop.effect addSubview:_back];
    _titleLabel = [NSTextField labelWithString:@""];
    _titleLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightRegular];
    _titleLabel.textColor = NSColor.whiteColor;
    _titleLabel.alignment = NSTextAlignmentCenter;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [_backdrop.effect addSubview:_titleLabel];
    _scroll = [NSScrollView new];
    _scroll.drawsBackground = NO;
    _scroll.contentView.drawsBackground = NO;
    _scroll.borderType = NSNoBorder;
    _scroll.hasVerticalScroller = YES;
    _scroll.scrollerStyle = NSScrollerStyleOverlay;
    _scroll.autohidesScrollers = YES;
    _grid = [FlippedView new];
    _scroll.documentView = _grid;
    [_backdrop.effect addSubview:_scroll];
    _shortcutList = [FlippedView new];
    [_backdrop.effect addSubview:_shortcutList];
    _statusLabel = [NSTextField labelWithString:@""];
    _statusLabel.font = [NSFont systemFontOfSize:11];
    _statusLabel.textColor = NSColor.whiteColor;
    _statusLabel.alignment = NSTextAlignmentCenter;
    _statusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _statusLabel.hidden = YES;
    [_backdrop.effect addSubview:_statusLabel];
    __weak typeof(self) weakSelf = self;
    _keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *e) {
        LauncherController *s = weakSelf;
        return s.visible && e.window == s.panel && [s handleKey:e] ? nil : e;
    }];
    _clickMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown handler:^(NSEvent *e) {
        (void)e;
        if (!weakSelf.trackingMenu) [weakSelf hide];
    }];
    _recentDirectories.didRefresh = ^{ [weakSelf applyCachedShortcuts]; };
    _configStore.didRefresh = ^{ [weakSelf applyCachedShortcuts]; };
    [_configStore refresh];
    [_recentDirectories refresh];
    return self;
}
- (BOOL)visible { return self.panel.isVisible && !self.hiding; }
- (void)showFromDock:(BOOL)fromDock {
    [self showFromDock:fromDock menuBarRect:NSZeroRect];
}
- (void)showFromMenuBarRect:(NSRect)rect {
    [self showFromDock:NO menuBarRect:rect];
}
- (void)showFromDock:(BOOL)fromDock menuBarRect:(NSRect)rect {
    self.menuBarAnchor = rect;
    BOOL alreadyVisible = self.visible;
    self.transitionGeneration++;
    self.hiding = NO;
    [self.backdrop.layer removeAnimationForKey:@"launcherTransition"];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self.backdrop.effect.layer removeAnimationForKey:@"launcherBlur"];
    self.backdrop.effect.layer.filters = nil;
    self.backdrop.layer.opacity = 1;
    self.backdrop.layer.transform = CATransform3DIdentity;
    [CATransaction commit];
    self.dockPresentation = fromDock;
    self.dockIcon = fromDock ? DockLocator.iconRect : NSZeroRect;
    NSPoint mouse = NSEvent.mouseLocation;
    NSPoint point = NSIsEmptyRect(self.dockIcon) ? mouse : NSMakePoint(NSMidX(self.dockIcon), NSMidY(self.dockIcon));
    if (!NSIsEmptyRect(rect)) point = NSMakePoint(NSMidX(rect), NSMidY(rect));
    NSScreen *screen = NSScreen.mainScreen ?: NSScreen.screens.firstObject;
    for (NSScreen *candidate in NSScreen.screens)
        if (NSPointInRect(point, candidate.frame)) { screen = candidate; break; }
    self.availableFrame = NSInsetRect(screen.visibleFrame, 8, 8);
    self.bottomDock = !NSIsEmptyRect(self.dockIcon) &&
        NSMidY(self.dockIcon) < NSMinY(screen.visibleFrame) + 8;

    // 권한이 없으면 Dock이 차지한 영역 안의 클릭만 위치 기준으로 사용합니다.
    // 일반 화면 안의 포인터는 Dock 위치로 간주하지 않습니다.
    if (fromDock && NSIsEmptyRect(self.dockIcon) &&
        mouse.y < NSMinY(screen.visibleFrame) &&
        mouse.y >= NSMinY(screen.frame)) {
        self.dockIcon = NSMakeRect(mouse.x - 1, mouse.y, 2, MAX(1, NSMinY(screen.visibleFrame) - mouse.y));
        self.bottomDock = YES;
    }
    self.path = [NSMutableArray arrayWithObject:self.root];
    [self reload];
    [self.panel makeKeyAndOrderFront:nil];
    [self.panel makeFirstResponder:self.panel];
    [self.panel invalidateShadow];
    if (!alreadyVisible) {
        self.entering = YES;
        [self animateEntrance];
        NSUInteger generation = self.transitionGeneration;
        NSTimeInterval duration = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion ? 0.07 : 0.14;
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weakSelf.transitionGeneration != generation) return;
            weakSelf.entering = NO;
            [weakSelf applyCachedShortcuts];
        });
    } else {
        self.entering = NO;
    }
    [self.recentDirectories refresh];
    [self.configStore refresh];
}
- (CGFloat)gridHeight {
    CGFloat height = 0;
    for (NSArray *group in self.groups)
        height += ceil((double)group.count / self.columns) * CellHeight;
    return MAX(CellHeight, height + MAX(0, (NSInteger)self.groups.count - 1) * GroupGap);
}
- (NSArray<NSValue *> *)shortcutFramesForWidth:(CGFloat)width {
    if (self.path.count != 1) return @[];
    NSMutableArray *frames = [NSMutableArray array];
    CGFloat x = 0, y = 0;
    for (MLShortcut *shortcut in self.shortcuts) {
        NSString *name = shortcut.title;
        CGFloat textWidth = [name sizeWithAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:13]}].width;
        CGFloat itemWidth = MIN(width, ceil(textWidth) + 36);
        if (x > 0 && x + itemWidth > width) { x = 0; y += 32; }
        [frames addObject:[NSValue valueWithRect:NSMakeRect(x, y, itemWidth, 28)]];
        x += itemWidth + 8;
    }
    // 마지막 줄을 포함해 각 줄의 아이콘·이름 묶음을 가운데 배치합니다.
    for (NSUInteger start = 0; start < frames.count;) {
        NSUInteger end = start + 1;
        CGFloat rowY = [frames[start] rectValue].origin.y;
        while (end < frames.count && [frames[end] rectValue].origin.y == rowY) end++;
        CGFloat offset = floor((width - NSMaxX([frames[end - 1] rectValue])) / 2);
        for (NSUInteger i = start; i < end; i++)
            frames[i] = [NSValue valueWithRect:NSOffsetRect([frames[i] rectValue], offset, 0)];
        start = end;
    }
    return frames;
}
- (CGFloat)shortcutHeightForWidth:(CGFloat)width {
    NSArray<NSValue *> *frames = [self shortcutFramesForWidth:width];
    return frames.count ? NSMaxY(frames.lastObject.rectValue) + 16 : 0;
}
- (NSArray<MLShortcut *> *)cachedShortcuts {
    return [MLShortcut shortcutsWithDirectories:self.recentDirectories.directories
        websites:self.configStore.websites commands:self.configStore.commands appsURL:self.appsURL];
}
// 폴더 읽기 오류를 설정 오류보다 먼저 보여 주며, 비동기 캐시 갱신이 이를 지우지 않습니다.
- (void)refreshStatus {
    NSString *message = self.catalogError ?: self.configStore.error.localizedDescription;
    if (message) [self showError:message];
    else self.statusLabel.hidden = YES;
}
- (void)applyCachedShortcuts {
    // 조작 중에는 항목 이동을 피하고 다음 열기에서 최신 캐시를 사용합니다.
    if (!self.visible || self.entering || self.trackingMenu || self.selected >= 0 || self.path.count != 1) return;
    [self refreshStatus];
    NSArray<MLShortcut *> *shortcuts = [self cachedShortcuts];
    if ([self.shortcuts isEqualToArray:shortcuts]) return;
    self.shortcuts = shortcuts;
    [self layout];
    [self renderItems];
}
- (void)layout {
    NSRect area = self.availableFrame;
    NSInteger capacity = MAX(1, MIN(6, (NSInteger)((NSWidth(area) - SideInset * 2) / CellWidth)));
    self.columns = MAX(1, MIN(capacity, (NSInteger)self.items.count));
    if (!self.items.count || (self.path.count == 1 && self.shortcuts.count))
        self.columns = MAX(self.columns, MIN(3, capacity));
    CGFloat width = MIN(NSWidth(area), self.columns * CellWidth + SideInset * 2);
    BOOL tail = self.dockPresentation && self.bottomDock;
    CGFloat bottom = tail ? 12 : 0;
    CGFloat topInset = self.path.count > 1 ? 44 : 16;
    CGFloat shortcutHeight = [self shortcutHeightForWidth:width - SideInset * 2];
    CGFloat height = MIN(NSHeight(area), topInset + [self gridHeight] + shortcutHeight + 10 + bottom);
    NSRect frame = NSMakeRect(NSMidX(area) - width / 2, NSMidY(area) - height / 2, width, height);
    if (self.dockPresentation && !NSIsEmptyRect(self.dockIcon)) {
        if (tail) {
            frame.origin.x = NSMidX(self.dockIcon) - width / 2;
            frame.origin.y = NSMaxY(self.dockIcon) + 4;
        } else {
            BOOL left = NSMidX(self.dockIcon) < NSMidX(area);
            frame.origin.x = left ? NSMaxX(self.dockIcon) + 8 : NSMinX(self.dockIcon) - width - 8;
            frame.origin.y = NSMidY(self.dockIcon) - height / 2;
        }
    }
    if (!NSIsEmptyRect(self.menuBarAnchor)) {
        frame.origin.x = NSMidX(self.menuBarAnchor) - width / 2;
        frame.origin.y = MIN(NSMaxY(area), NSMinY(self.menuBarAnchor) - 8) - height;
    }
    frame.origin.x = MAX(NSMinX(area), MIN(frame.origin.x, NSMaxX(area) - width));
    frame.origin.y = MAX(NSMinY(area), MIN(frame.origin.y, NSMaxY(area) - height));
    [self.panel setFrame:frame display:NO];
    self.backdrop.frame = NSMakeRect(0, 0, width, height);
    self.backdrop.showsTail = tail;
    self.backdrop.tailX = NSMidX(self.dockIcon) - NSMinX(frame);
    [self.backdrop updateShape];
    self.titleLabel.frame = NSMakeRect(52, height - 30, width - 104, 20);
    self.back.frame = NSMakeRect(17, height - 35, 28, 28);
    self.shortcutList.frame = NSMakeRect(SideInset, bottom + 10, width - SideInset * 2, shortcutHeight);
    self.scroll.frame = NSMakeRect(SideInset, bottom + 10 + shortcutHeight, width - SideInset * 2,
        MAX(0, height - topInset - 10 - bottom - shortcutHeight));
    self.statusLabel.frame = NSMakeRect(24, bottom + 2, width - 48, 16);
}
// 메뉴 막대 또는 Dock 위치를 확대·축소의 기준으로 삼습니다.
- (CATransform3D)transitionTransform:(CGFloat)scale {
    CALayer *layer = self.backdrop.layer;
    CGFloat w = NSWidth(self.backdrop.bounds), h = NSHeight(self.backdrop.bounds);
    NSPoint pivot = NSMakePoint(w / 2, h / 2);
    if (self.dockPresentation && !NSIsEmptyRect(self.dockIcon)) {
        if (self.bottomDock) pivot = NSMakePoint(MAX(0, MIN(w, self.backdrop.tailX)), 0);
        else pivot = NSMakePoint(NSMidX(self.dockIcon) < NSMidX(self.panel.frame) ? 0 : w, h / 2);
    }
    if (!NSIsEmptyRect(self.menuBarAnchor)) {
        pivot = NSMakePoint(MAX(0, MIN(w, NSMidX(self.menuBarAnchor) - NSMinX(self.panel.frame))), h);
    }
    CGFloat x = pivot.x - layer.anchorPoint.x * w;
    CGFloat y = pivot.y - layer.anchorPoint.y * h;
    CATransform3D transform = CATransform3DMakeTranslation(x * (1 - scale), y * (1 - scale), 0);
    return CATransform3DScale(transform, scale, scale, 1);
}
// 유리 재질은 그대로 두고 콘텐츠에만 전환 중 블러를 적용합니다.
- (void)animateBlurFrom:(CGFloat)start to:(CGFloat)end duration:(CFTimeInterval)duration {
    NSView *content = self.backdrop.effect;
    content.wantsLayer = YES;
    content.layerUsesCoreImageFilters = YES;
    CIFilter *filter = [CIFilter filterWithName:@"CIGaussianBlur"];
    if (!filter) return;
    filter.name = @"transitionBlur";
    [filter setValue:@(end) forKey:kCIInputRadiusKey];
    NSUInteger generation = self.transitionGeneration;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    __weak typeof(self) weakSelf = self;
    [CATransaction setCompletionBlock:^{
        if (weakSelf.transitionGeneration == generation) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            weakSelf.backdrop.effect.layer.filters = nil;
            [CATransaction commit];
        }
    }];
    [content.layer removeAnimationForKey:@"launcherBlur"];
    content.layer.filters = @[filter];
    CABasicAnimation *blur = [CABasicAnimation animationWithKeyPath:@"filters.transitionBlur.inputRadius"];
    blur.fromValue = @(start);
    blur.toValue = @(end);
    blur.duration = duration;
    blur.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [content.layer addAnimation:blur forKey:@"launcherBlur"];
    [CATransaction commit];
}
- (void)animateEntrance {
    BOOL reduced = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.duration = reduced ? 0.07 : 0.14;
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @0; fade.toValue = @1;
    fade.duration = group.duration;
    fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    NSMutableArray *animations = [NSMutableArray arrayWithObject:fade];
    if (!reduced) {
        CAKeyframeAnimation *pop = [CAKeyframeAnimation animationWithKeyPath:@"transform"];
        pop.values = @[[NSValue valueWithCATransform3D:[self transitionTransform:0.90]],
                      [NSValue valueWithCATransform3D:CATransform3DIdentity],
                      [NSValue valueWithCATransform3D:[self transitionTransform:0.995]],
                      [NSValue valueWithCATransform3D:CATransform3DIdentity]];
        pop.keyTimes = @[@0, @0.72, @0.88, @1];
        pop.duration = group.duration;
        pop.timingFunctions = @[[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut],
                                [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
                                [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
        [animations addObject:pop];
    }
    group.animations = animations;
    [self.backdrop.layer addAnimation:group forKey:@"launcherTransition"];
    if (!reduced) [self animateBlurFrom:5 to:0 duration:group.duration];
}
- (void)hide {
    if (!self.panel.isVisible || self.hiding) return;
    self.hiding = YES;
    self.entering = NO;
    NSUInteger generation = ++self.transitionGeneration;
    CALayer *layer = self.backdrop.layer;
    CALayer *presented = layer.presentationLayer ?: layer;
    CATransform3D currentTransform = presented.transform;
    float currentOpacity = presented.opacity;
    BOOL reduced = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    CALayer *contentLayer = self.backdrop.effect.layer;
    CIFilter *presentedFilter = contentLayer.presentationLayer.filters.firstObject;
    NSNumber *radius = [presentedFilter valueForKey:kCIInputRadiusKey];
    CGFloat currentBlur = radius.doubleValue;
    [layer removeAnimationForKey:@"launcherTransition"];
    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.duration = reduced ? 0.06 : 0.09;
    group.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @(currentOpacity); fade.toValue = @0;
    fade.duration = group.duration;
    NSMutableArray *animations = [NSMutableArray arrayWithObject:fade];
    if (!reduced) {
        CABasicAnimation *shrink = [CABasicAnimation animationWithKeyPath:@"transform"];
        shrink.duration = group.duration;
        shrink.fromValue = [NSValue valueWithCATransform3D:currentTransform];
        shrink.toValue = [NSValue valueWithCATransform3D:[self transitionTransform:0.94]];
        [animations addObject:shrink];
    }
    group.animations = animations;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    __weak typeof(self) weakSelf = self;
    [CATransaction setCompletionBlock:^{
        // 다시 연 창을 이전 퇴장 애니메이션이 닫지 않도록 합니다.
        if (weakSelf.transitionGeneration == generation && weakSelf.hiding) {
            [weakSelf.panel orderOut:nil];
            weakSelf.hiding = NO;
        }
    }];
    layer.opacity = 0;
    [layer addAnimation:group forKey:@"launcherTransition"];
    [CATransaction commit];
    if (!reduced) [self animateBlurFrom:currentBlur to:6 duration:group.duration];
}
- (void)windowDidResignKey:(NSNotification *)notification {
    (void)notification;
    if (!self.trackingMenu) [self hide];
}
- (void)showError:(NSString *)message {
    self.statusLabel.stringValue = message;
    self.statusLabel.hidden = NO;
}
- (void)reload {
    self.shortcuts = [self cachedShortcuts];
    NSError *error = nil;
    NSArray *catalog = [AppCatalog itemsAtURL:self.path.lastObject error:&error];
    self.catalogError = error ? [NSString stringWithFormat:@"폴더를 읽을 수 없습니다: %@", error.localizedDescription] : nil;
    self.groups = [AppCatalog groupsForItems:catalog];
    NSMutableArray *flattened = [NSMutableArray array];
    for (NSArray *group in self.groups) [flattened addObjectsFromArray:group];
    self.items = flattened;
    self.titleLabel.hidden = self.path.count == 1;
    self.titleLabel.stringValue = self.path.count == 1 ? @"" : self.path.lastObject.lastPathComponent;
    self.back.hidden = self.path.count <= 1;
    self.selected = -1;
    [self layout];
    [self renderItems];
    [self refreshStatus];
}
- (void)renderItems {
    for (NSView *view in self.grid.subviews.copy) [view removeFromSuperview];
    for (NSView *view in self.shortcutList.subviews.copy) [view removeFromSuperview];
    self.buttons = [NSMutableArray array];
    [self renderGrid];
    [self renderShortcuts];
    [self.grid scrollPoint:NSZeroPoint];
}
// 버튼의 tag는 방향키 선택에 쓰는 전체 버튼 순서이고, 실행 대상은 representedEntry입니다.
- (void)addButton:(LauncherActionButton *)button entry:(id)entry toView:(NSView *)view {
    button.representedEntry = entry;
    button.target = self;
    button.action = @selector(choose:);
    button.tag = (NSInteger)self.buttons.count;
    [view addSubview:button];
    [self.buttons addObject:button];
}
- (void)renderGrid {
    CGFloat width = self.scroll.contentSize.width;
    CGFloat cell = width / self.columns;
    CGFloat height = MAX(self.scroll.contentSize.height, [self gridHeight]);
    self.grid.frame = NSMakeRect(0, 0, width, height);
    CGFloat groupY = 0;
    for (NSArray<MLItem *> *group in self.groups) {
        if (groupY > 0) {
            NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(8, groupY + GroupGap / 2, width - 16, 1)];
            separator.boxType = NSBoxSeparator;
            [self.grid addSubview:separator];
            groupY += GroupGap;
        }
        for (NSUInteger idx = 0; idx < group.count; idx++) {
            MLItem *item = group[idx];
            LauncherIconButton *button = [[LauncherIconButton alloc] initWithFrame:NSMakeRect(
                (idx % self.columns) * cell + 3, groupY + (idx / self.columns) * CellHeight, cell - 6, 122)];
            button.title = item.name;
            button.image = [NSWorkspace.sharedWorkspace iconForFile:(item.targetURL ?: item.sourceURL).path];
            __weak LauncherIconButton *weakButton = button;
            MLLoadFolderIcon(item.targetURL ?: item.sourceURL, 96, self.panel.backingScaleFactor, ^(NSImage *image) {
                LauncherIconButton *currentButton = weakButton;
                currentButton.image = image;
                currentButton.needsDisplay = YES;
            });
            button.menu = [self menuForURL:item.targetURL directory:item.folder valid:!item.problem];
            button.toolTip = item.problem ?: item.targetURL.path;
            button.accessibilityLabel = item.name;
            if (item.problem) button.alphaValue = 0.45;
            [self addButton:button entry:item toView:self.grid];
        }
        groupY += ceil((double)group.count / self.columns) * CellHeight;
    }
    if (!self.items.count) {
        NSTextField *empty = [NSTextField wrappingLabelWithString:@"이 폴더에 앱의 Finder alias를 넣어 주세요.\n하위 폴더로 앱을 분류할 수 있습니다."];
        empty.alignment = NSTextAlignmentCenter;
        empty.textColor = NSColor.whiteColor;
        empty.frame = NSMakeRect(16, 34, width - 32, 64);
        [self.grid addSubview:empty];
    }
}
- (void)renderShortcuts {
    // 하위 폴더에서는 배치 결과가 비어 하단 항목을 그리지 않습니다.
    NSArray<NSValue *> *frames = [self shortcutFramesForWidth:NSWidth(self.shortcutList.bounds)];
    if (frames.count) {
        NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(8, 4, NSWidth(self.shortcutList.bounds) - 16, 1)];
        separator.boxType = NSBoxSeparator;
        [self.shortcutList addSubview:separator];
    }
    NSString *safariPath = nil;
    for (NSUInteger i = 0; i < frames.count; i++) {
        MLShortcut *shortcut = self.shortcuts[i];
        BOOL isDirectory = shortcut.kind == MLShortcutKindDirectory;
        LauncherDirectoryButton *button = [[LauncherDirectoryButton alloc] initWithFrame:NSOffsetRect(frames[i].rectValue, 0, 16)];
        button.bordered = NO;
        button.focusRingType = NSFocusRingTypeNone;
        button.title = shortcut.title;
        // 정사각형 앱 아이콘의 보이는 높이를 가로로 긴 폴더 아이콘에 맞춥니다.
        button.iconPointSize = isDirectory ? 16 : 15;
        button.iconOffsetY = isDirectory ? 0 : 1;
        NSString *iconPath = shortcut.url.path;
        if (shortcut.kind == MLShortcutKindCommand) iconPath = @"/System/Applications/Utilities/Terminal.app";
        if (shortcut.kind == MLShortcutKindWebsite) {
            // 웹사이트가 여러 개여도 Safari 위치는 한 번만 조회합니다.
            if (!safariPath) safariPath = [NSWorkspace.sharedWorkspace
                URLForApplicationWithBundleIdentifier:MLSafariBundleIdentifier].path ?: @"/Applications/Safari.app";
            iconPath = safariPath;
        }
        button.image = [NSWorkspace.sharedWorkspace iconForFile:iconPath];
        __weak LauncherDirectoryButton *weakButton = button;
        if (isDirectory) MLLoadFolderIcon(shortcut.url, 16, self.panel.backingScaleFactor, ^(NSImage *image) {
            LauncherDirectoryButton *currentButton = weakButton;
            currentButton.image = image;
            currentButton.needsDisplay = YES;
        });
        button.toolTip = shortcut.toolTip;
        button.accessibilityLabel = shortcut.accessibilityLabel;
        if (isDirectory) button.menu = [self menuForURL:shortcut.url directory:YES valid:YES];
        [self addButton:button entry:shortcut toView:self.shortcutList];
    }
}
- (void)updateSelection {
    [self.buttons enumerateObjectsUsingBlock:^(LauncherActionButton *button, NSUInteger idx, BOOL *stop) {
        (void)stop;
        button.selected = (NSInteger)idx == self.selected;
    }];
    if (self.selected < 0) return;
    LauncherActionButton *button = self.buttons[self.selected];
    if (button.superview == self.grid) [self.grid scrollRectToVisible:button.frame];
}
- (void)choose:(NSButton *)sender { self.selected = sender.tag; [self activateSelection]; }
- (void)activateSelection {
    if (self.selected < 0 || self.selected >= (NSInteger)self.buttons.count) return;
    id entry = self.buttons[self.selected].representedEntry;
    if ([entry isKindOfClass:MLShortcut.class]) [self activateShortcut:entry];
    else [self activateItem:entry];
}
- (void)activateItem:(MLItem *)item {
    if (item.problem) { [self showError:item.problem]; NSBeep(); return; }
    if (item.folder) {
        [self.path addObject:item.targetURL]; [self reload]; return;
    }
    NSNumber *application = nil;
    [item.targetURL getResourceValue:&application forKey:NSURLIsApplicationKey error:nil];
    if (!application.boolValue) {
        if ([NSWorkspace.sharedWorkspace openURL:item.targetURL]) [self hide];
        else { [self showError:@"앱을 열지 못했습니다. Finder에서 대상을 확인해 주세요."]; NSBeep(); }
        return;
    }
    // openURL:로 앱을 열면 macOS가 대상 앱 번들 수정 여부를 검사해 '앱 관리' 차단 알림을 띄웁니다.
    // openApplicationAtURL:은 이 검사를 일으키지 않습니다(2026-11-14 Nibbles.app으로 실기 확인).
    __weak typeof(self) weakSelf = self;
    [NSWorkspace.sharedWorkspace openApplicationAtURL:item.targetURL
        configuration:[NSWorkspaceOpenConfiguration configuration]
        completionHandler:^(NSRunningApplication *app, NSError *error) {
            (void)app;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!error) { [weakSelf hide]; return; }
                [weakSelf showError:[NSString stringWithFormat:@"앱을 열지 못했습니다: %@", error.localizedDescription]];
                NSBeep();
            });
        }];
}
- (void)activateShortcut:(MLShortcut *)shortcut {
    switch (shortcut.kind) {
        case MLShortcutKindDirectory:
            [self openURL:shortcut.url withApplicationIdentifier:MLCursorBundleIdentifier];
            break;
        case MLShortcutKindWebsite:
            if (shortcut.url && [NSWorkspace.sharedWorkspace openURL:shortcut.url]) [self hide];
            else { [self showError:@"웹사이트를 열지 못했습니다. 기본 브라우저 설정을 확인해 주세요."]; NSBeep(); }
            break;
        case MLShortcutKindCommand: [self runCommand:shortcut.command]; break;
        case MLShortcutKindApps: [self openApps]; break;
    }
}
- (void)openApps {
    [self hide];
    [NSWorkspace.sharedWorkspace openApplicationAtURL:self.appsURL
        configuration:[NSWorkspaceOpenConfiguration configuration]
        completionHandler:^(NSRunningApplication *app, NSError *error) {
            (void)app;
            if (!error) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                NSAlert *alert = [NSAlert new];
                alert.messageText = @"Apps를 열지 못했습니다.";
                alert.informativeText = error.localizedDescription;
                [alert runModal];
            });
        }];
}
- (void)runCommand:(NSString *)command {
    if (self.commandRunning) return;
    self.commandRunning = YES;
    __weak typeof(self) weakSelf = self;
    [TerminalCommand run:command completion:^(NSString *error) {
        weakSelf.commandRunning = NO;
        if (error) {
            // 권한 창 등으로 런처가 닫혀도 실행 실패는 별도 안내합니다.
            NSAlert *alert = [NSAlert new];
            alert.messageText = @"명령을 실행하지 못했습니다.";
            alert.informativeText = error;
            [alert runModal];
        } else [weakSelf hide];
    }];
}
- (NSRect)navigationRectForButton:(NSView *)button {
    // 앱 Grid의 스크롤 위치에 관계없이 논리적인 행 순서로 탐색합니다.
    return button.superview == self.grid ? button.frame : NSOffsetRect(button.frame, 0, [self gridHeight]);
}
- (NSMenu *)menuForURL:(NSURL *)url directory:(BOOL)directory valid:(BOOL)valid {
    NSMenu *menu = [NSMenu new];
    menu.autoenablesItems = NO;
    menu.delegate = self;
    NSMenuItem *reveal = [menu addItemWithTitle:@"Reveal in Finder" action:@selector(revealItem:) keyEquivalent:@""];
    reveal.target = self;
    reveal.representedObject = url;
    reveal.enabled = valid && url != nil;
    if (directory) {
        NSMenuItem *open = [menu addItemWithTitle:@"Open in Finder" action:@selector(openFolder:) keyEquivalent:@""];
        open.target = self;
        open.representedObject = url;
        open.enabled = valid && url != nil;
    }
    if (!directory && [AppCatalog isProtectedApplicationAtURL:url]) return menu;
    NSString *identifier = directory ? MLITermBundleIdentifier : MLAppCleanerBundleIdentifier;
    NSMenuItem *external = [menu addItemWithTitle:directory ? @"Open in iTerm" : @"Uninstall with AppCleaner…"
        action:@selector(openExternalItem:) keyEquivalent:@""];
    external.target = self;
    external.representedObject = valid && url ? @{@"url": url, @"application": identifier} : nil;
    external.enabled = external.representedObject != nil;
    return menu;
}
- (void)menuWillOpen:(NSMenu *)menu {
    self.trackingMenu = YES;
    // 표시 경로에서는 LaunchServices 조회를 하지 않고 메뉴를 열 때 확인합니다.
    for (NSMenuItem *item in menu.itemArray) {
        if ([item.representedObject isKindOfClass:NSDictionary.class]) {
            NSString *identifier = item.representedObject[@"application"];
            item.enabled = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:identifier] != nil;
        }
    }
}
- (void)menuDidClose:(NSMenu *)menu {
    (void)menu;
    self.trackingMenu = NO;
    // 메뉴 닫힘 뒤의 실행 액션이 먼저 처리되도록 다음 메인 큐 순서로 미룹니다.
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf applyCachedShortcuts]; });
}
- (void)revealItem:(NSMenuItem *)sender {
    [self hide];
    [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[sender.representedObject]];
}
- (void)openFolder:(NSMenuItem *)sender {
    [self openURL:sender.representedObject withApplicationIdentifier:MLFinderBundleIdentifier];
}
- (void)openExternalItem:(NSMenuItem *)sender {
    if ([sender.representedObject[@"application"] isEqualToString:MLAppCleanerBundleIdentifier] &&
        [AppCatalog isProtectedApplicationAtURL:sender.representedObject[@"url"]]) return;
    [self openURL:sender.representedObject[@"url"] withApplicationIdentifier:sender.representedObject[@"application"]];
}
- (void)openURL:(NSURL *)url withApplicationIdentifier:(NSString *)identifier {
    NSURL *application = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:identifier];
    if (!application) { [self showError:@"대상 앱이 설치되어 있지 않습니다." ]; NSBeep(); return; }
    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    __weak typeof(self) weakSelf = self;
    [NSWorkspace.sharedWorkspace openURLs:@[url] withApplicationAtURL:application configuration:configuration
        completionHandler:^(NSRunningApplication *app, NSError *error) {
            (void)app;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error) [weakSelf showError:[NSString stringWithFormat:@"폴더 또는 앱을 열지 못했습니다: %@", error.localizedDescription]];
                else [weakSelf hide];
            });
        }];
}
- (void)goBack:(id)sender {
    if (self.path.count <= 1) return;
    [self.path removeLastObject]; [self reload];
}
- (BOOL)handleKey:(NSEvent *)event {
    BOOL command = (event.modifierFlags & NSEventModifierFlagCommand) != 0;
    if (command && event.keyCode == 126) { [self goBack:nil]; return YES; }
    if (command && [event.charactersIgnoringModifiers.lowercaseString isEqualToString:@"r"]) {
        [self reload];
        [self.recentDirectories refresh];
        [self.configStore refresh];
        return YES;
    }
    if (command) return NO;
    if (event.keyCode == 53) { [self hide]; return YES; }
    if (event.keyCode == 36 || event.keyCode == 76) {
        if (self.selected < 0 && self.buttons.count) self.selected = 0;
        [self activateSelection]; return YES;
    }
    NSInteger delta = 0;
    switch (event.keyCode) {
        case 123: delta = -1; break; case 124: delta = 1; break;
        case 125: delta = self.columns; break; case 126: delta = -self.columns; break;
        default: return NO;
    }
    if (self.buttons.count) {
        if (self.selected < 0) self.selected = 0;
        else if (event.keyCode == 125 || event.keyCode == 126) {
            // 그룹의 마지막 줄이 짧아도 바로 위/아래 줄의 가까운 열로 이동합니다.
            NSRect current = [self navigationRectForButton:self.buttons[self.selected]];
            CGFloat bestY = CGFLOAT_MAX, bestX = CGFLOAT_MAX;
            NSInteger next = self.selected;
            for (NSUInteger i = 0; i < self.buttons.count; i++) {
                NSRect candidate = [self navigationRectForButton:self.buttons[i]];
                CGFloat dy = (NSMinY(candidate) - NSMinY(current)) * (event.keyCode == 125 ? 1 : -1);
                CGFloat dx = fabs(NSMidX(candidate) - NSMidX(current));
                if (dy > 0 && (dy < bestY || (dy == bestY && dx < bestX))) {
                    bestY = dy; bestX = dx; next = i;
                }
            }
            self.selected = next;
        } else self.selected = MAX(0, MIN((NSInteger)self.buttons.count - 1, self.selected + delta));
        [self updateSelection];
    }
    return YES;
}
- (void)dealloc {
    if (_keyMonitor) [NSEvent removeMonitor:_keyMonitor];
    if (_clickMonitor) [NSEvent removeMonitor:_clickMonitor];
}
@end
