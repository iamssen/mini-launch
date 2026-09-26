#import "LauncherController.h"
#import "AppCatalog.h"
#import "DockLocator.h"
#import "LauncherAppearance.h"

static const CGFloat CellWidth = 128;
static const CGFloat CellHeight = 128;
static const CGFloat SideInset = 16;
static const CGFloat GroupGap = 20;

@interface LauncherPanel : NSPanel
@end
@implementation LauncherPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }
@end
@interface FlippedView : NSView
@end
@implementation FlippedView
- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return NO; }
@end

@interface LauncherController () <NSWindowDelegate>
@property LauncherPanel *panel;
@property LauncherBackdrop *backdrop;
@property NSURL *root;
@property NSMutableArray<NSURL *> *path;
@property NSArray<MLItem *> *items;
@property NSArray<NSArray<MLItem *> *> *groups;
@property NSMutableArray<LauncherIconButton *> *buttons;
@property NSTextField *titleLabel;
@property NSTextField *statusLabel;
@property NSButton *back;
@property NSScrollView *scroll;
@property FlippedView *grid;
@property NSInteger selected;
@property NSInteger columns;
@property NSRect availableFrame;
@property NSRect dockIcon;
@property BOOL dockPresentation;
@property BOOL bottomDock;
@property id keyMonitor;
@property id clickMonitor;
@end

@implementation LauncherController
- (instancetype)initWithRoot:(NSURL *)root {
    if (!(self = [super init])) return nil;
    _root = root;
    _path = [NSMutableArray arrayWithObject:root];
    _panel = [[LauncherPanel alloc] initWithContentRect:NSMakeRect(0, 0, 800, 442)
        styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    _panel.delegate = self;
    _panel.opaque = NO;
    _panel.backgroundColor = NSColor.clearColor;
    _panel.hasShadow = YES;
    _panel.level = NSFloatingWindowLevel;
    _panel.hidesOnDeactivate = NO;
    _panel.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace | NSWindowCollectionBehaviorFullScreenAuxiliary;
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
        [weakSelf hide];
    }];
    return self;
}
- (BOOL)visible { return self.panel.isVisible; }
- (void)showFromDock:(BOOL)fromDock {
    self.dockPresentation = fromDock;
    self.dockIcon = fromDock ? DockLocator.iconRect : NSZeroRect;
    NSPoint mouse = NSEvent.mouseLocation;
    NSPoint point = NSIsEmptyRect(self.dockIcon) ? mouse : NSMakePoint(NSMidX(self.dockIcon), NSMidY(self.dockIcon));
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
    [NSApp activateIgnoringOtherApps:YES];
    [self.panel makeKeyAndOrderFront:nil];
    [self.panel makeFirstResponder:self.panel];
    [self.panel invalidateShadow];
}
- (CGFloat)gridHeight {
    CGFloat height = 0;
    for (NSArray *group in self.groups)
        height += ceil((double)group.count / self.columns) * CellHeight;
    return MAX(CellHeight, height + MAX(0, (NSInteger)self.groups.count - 1) * GroupGap);
}
- (void)layout {
    NSRect area = self.availableFrame;
    NSInteger capacity = MAX(1, MIN(6, (NSInteger)((NSWidth(area) - SideInset * 2) / CellWidth)));
    self.columns = MAX(1, MIN(capacity, (NSInteger)self.items.count));
    if (!self.items.count) self.columns = MIN(3, capacity);
    CGFloat width = MIN(NSWidth(area), self.columns * CellWidth + SideInset * 2);
    BOOL tail = self.dockPresentation && self.bottomDock;
    CGFloat bottom = tail ? 12 : 0;
    CGFloat topInset = self.path.count > 1 ? 44 : 16;
    CGFloat height = MIN(NSHeight(area), topInset + [self gridHeight] + 10 + bottom);
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
    frame.origin.x = MAX(NSMinX(area), MIN(frame.origin.x, NSMaxX(area) - width));
    frame.origin.y = MAX(NSMinY(area), MIN(frame.origin.y, NSMaxY(area) - height));
    [self.panel setFrame:frame display:NO];
    self.backdrop.frame = NSMakeRect(0, 0, width, height);
    self.backdrop.showsTail = tail;
    self.backdrop.tailX = NSMidX(self.dockIcon) - NSMinX(frame);
    [self.backdrop updateShape];
    self.titleLabel.frame = NSMakeRect(52, height - 30, width - 104, 20);
    self.back.frame = NSMakeRect(17, height - 35, 28, 28);
    self.scroll.frame = NSMakeRect(SideInset, bottom + 10, width - SideInset * 2, height - topInset - 10 - bottom);
    self.statusLabel.frame = NSMakeRect(24, bottom + 2, width - 48, 16);
}
- (void)hide { [self.panel orderOut:nil]; }
- (void)windowDidResignKey:(NSNotification *)notification { [self hide]; }
- (void)showError:(NSString *)message {
    self.statusLabel.stringValue = message;
    self.statusLabel.hidden = NO;
}
- (void)reload {
    NSError *error = nil;
    NSArray *catalog = [AppCatalog itemsAtURL:self.path.lastObject error:&error];
    self.groups = [AppCatalog groupsForItems:catalog];
    NSMutableArray *flattened = [NSMutableArray array];
    for (NSArray *group in self.groups) [flattened addObjectsFromArray:group];
    self.items = flattened;
    self.titleLabel.hidden = self.path.count == 1;
    self.titleLabel.stringValue = self.path.count == 1 ? @"" : self.path.lastObject.lastPathComponent;
    self.back.hidden = self.path.count <= 1;
    self.statusLabel.hidden = YES;
    self.selected = -1;
    [self layout];
    [self renderItems];
    if (error) [self showError:[NSString stringWithFormat:@"폴더를 읽을 수 없습니다: %@", error.localizedDescription]];
}
- (void)renderItems {
    for (NSView *view in self.grid.subviews.copy) [view removeFromSuperview];
    self.buttons = [NSMutableArray array];
    CGFloat width = self.scroll.contentSize.width;
    CGFloat cell = width / self.columns;
    CGFloat height = MAX(self.scroll.contentSize.height, [self gridHeight]);
    self.grid.frame = NSMakeRect(0, 0, width, height);
    CGFloat groupY = 0;
    NSInteger index = 0;
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
        button.target = self;
        button.action = @selector(choose:);
        button.tag = index++;
        button.toolTip = item.problem ?: item.targetURL.path;
        button.accessibilityLabel = item.name;
        if (item.problem) button.alphaValue = 0.45;
        [self.grid addSubview:button];
        [self.buttons addObject:button];
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
    [self.grid scrollPoint:NSZeroPoint];
}
- (void)updateSelection {
    [self.buttons enumerateObjectsUsingBlock:^(LauncherIconButton *button, NSUInteger idx, BOOL *stop) {
        (void)stop;
        button.selected = (NSInteger)idx == self.selected;
    }];
    if (self.selected >= 0 && self.selected < (NSInteger)self.buttons.count)
        [self.grid scrollRectToVisible:self.buttons[self.selected].frame];
}
- (void)choose:(NSButton *)sender { self.selected = sender.tag; [self activateSelection]; }
- (void)activateSelection {
    if (self.selected < 0 || self.selected >= (NSInteger)self.items.count) return;
    MLItem *item = self.items[self.selected];
    if (item.problem) { [self showError:item.problem]; NSBeep(); return; }
    if (item.folder) {
        [self.path addObject:item.targetURL]; [self reload]; return;
    }
    if ([NSWorkspace.sharedWorkspace openURL:item.targetURL]) [self hide];
    else { [self showError:@"앱을 열지 못했습니다. Finder에서 대상을 확인해 주세요."]; NSBeep(); }
}
- (void)goBack:(id)sender {
    if (self.path.count <= 1) return;
    [self.path removeLastObject]; [self reload];
}
- (BOOL)handleKey:(NSEvent *)event {
    BOOL command = (event.modifierFlags & NSEventModifierFlagCommand) != 0;
    if (command && event.keyCode == 126) { [self goBack:nil]; return YES; }
    if (command && [event.charactersIgnoringModifiers.lowercaseString isEqualToString:@"r"]) { [self reload]; return YES; }
    if (command) return NO;
    if (event.keyCode == 53) { [self hide]; return YES; }
    if (event.keyCode == 36 || event.keyCode == 76) {
        if (self.selected < 0 && self.items.count) self.selected = 0;
        [self activateSelection]; return YES;
    }
    NSInteger delta = 0;
    switch (event.keyCode) {
        case 123: delta = -1; break; case 124: delta = 1; break;
        case 125: delta = self.columns; break; case 126: delta = -self.columns; break;
        default: return NO;
    }
    if (self.items.count) {
        if (self.selected < 0) self.selected = 0;
        else if (event.keyCode == 125 || event.keyCode == 126) {
            // 그룹의 마지막 줄이 짧아도 바로 위/아래 줄의 가까운 열로 이동합니다.
            NSRect current = self.buttons[self.selected].frame;
            CGFloat bestY = CGFLOAT_MAX, bestX = CGFLOAT_MAX;
            NSInteger next = self.selected;
            for (NSUInteger i = 0; i < self.buttons.count; i++) {
                NSRect candidate = self.buttons[i].frame;
                CGFloat dy = (NSMinY(candidate) - NSMinY(current)) * (event.keyCode == 125 ? 1 : -1);
                CGFloat dx = fabs(NSMidX(candidate) - NSMidX(current));
                if (dy > 0 && (dy < bestY || (dy == bestY && dx < bestX))) {
                    bestY = dy; bestX = dx; next = i;
                }
            }
            self.selected = next;
        } else self.selected = MAX(0, MIN((NSInteger)self.items.count - 1, self.selected + delta));
        [self updateSelection];
    }
    return YES;
}
- (void)dealloc {
    if (_keyMonitor) [NSEvent removeMonitor:_keyMonitor];
    if (_clickMonitor) [NSEvent removeMonitor:_clickMonitor];
}
@end
