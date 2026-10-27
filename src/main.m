#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import "LauncherController.h"
#import "GestureMonitor.h"
#import "SleepController.h"
#import "SleepLog.h"
@interface AppDelegate : NSObject <NSApplicationDelegate>
@property LauncherController *launcher;
@property GestureMonitor *gestures;
@property NSUInteger gestureReconnectGeneration;
@property NSStatusItem *statusItem;
@property NSMenu *statusMenu;
@property SleepController *sleepController;
@property NSImage *launcherStatusIcon;
@property SleepLog *sleepLog;
@property NSTimer *sleepCheckTimer;
@end
@implementation AppDelegate
- (NSURL *)appsDirectoryURL {
    NSString *root = [NSUserDefaults.standardUserDefaults stringForKey:@"AppsDirectory"] ?: @"~/Apps";
    return [NSURL fileURLWithPath:root.stringByExpandingTildeInPath].URLByStandardizingPath;
}
- (NSString *)openFolderMenuTitle {
    return [@"Open " stringByAppendingString:self.appsDirectoryURL.path.stringByAbbreviatingWithTildeInPath];
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSMenu *menu = [NSMenu new];
    NSMenuItem *appItem = [NSMenuItem new]; [menu addItem:appItem];
    NSMenu *appMenu = [NSMenu new]; appItem.submenu = appMenu;
    NSMenuItem *openFolder = [[NSMenuItem alloc] initWithTitle:self.openFolderMenuTitle action:@selector(openFolder:) keyEquivalent:@""];
    openFolder.target = self;
    [appMenu addItem:openFolder];
    self.sleepController = [SleepController new];
    NSURL *logs = [NSURL fileURLWithPath:[@"~/Library/Logs/MiniLaunch" stringByExpandingTildeInPath] isDirectory:YES];
    self.sleepLog = [[SleepLog alloc] initWithDirectoryURL:logs];
    self.sleepController.log = self.sleepLog;
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    [self.sleepLog recordEvent:@"app_start" fields:@{@"version": info[@"CFBundleShortVersionString"] ?: @"",
        @"build": info[@"CFBundleVersion"] ?: @"", @"os": NSProcessInfo.processInfo.operatingSystemVersionString}];
    [self.sleepLog recordEvent:@"startup_state" fields:self.sleepController.diagnosticState];
    NSNotificationCenter *powerCenter = NSWorkspace.sharedWorkspace.notificationCenter;
    for (NSString *name in @[NSWorkspaceWillSleepNotification, NSWorkspaceDidWakeNotification,
                            NSWorkspaceScreensDidSleepNotification, NSWorkspaceScreensDidWakeNotification]) {
        [powerCenter addObserver:self selector:@selector(recordPowerEvent:) name:name object:nil];
    }
    self.sleepCheckTimer = [NSTimer timerWithTimeInterval:300 target:self selector:@selector(checkSleepState:) userInfo:nil repeats:YES];
    self.sleepCheckTimer.tolerance = 30;
    [NSRunLoop.mainRunLoop addTimer:self.sleepCheckTimer forMode:NSRunLoopCommonModes];
    [appMenu addItem:NSMenuItem.separatorItem];
    NSArray *sleepTitles = @[@"Off", @"Prevent Sleep", @"Prevent Sleep and Display Sleep"];
    for (NSUInteger i = 0; i < sleepTitles.count; i++) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:sleepTitles[i] action:@selector(selectSleepMode:) keyEquivalent:@""];
        item.target = self;
        item.tag = (NSInteger)i;
        [appMenu addItem:item];
    }
    [appMenu addItem:NSMenuItem.separatorItem];
    NSMenuItem *advancedItem = [[NSMenuItem alloc] initWithTitle:@"Advanced" action:nil keyEquivalent:@""];
    NSMenu *advanced = [[NSMenu alloc] initWithTitle:@"Advanced"];
    advancedItem.submenu = advanced;
    [appMenu addItem:advancedItem];
    NSArray *titles = @[@"Allow Dock Position Access…", @"Gesture Status…", @"Reconnect Gesture Devices", @"Open Caffein Logs"];
    NSArray *actions = @[@"requestAccessibility:", @"gestureStatus:", @"restartGestures:", @"openSleepLogs:"];
    for (NSUInteger i = 0; i < titles.count; i++) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:titles[i] action:NSSelectorFromString(actions[i]) keyEquivalent:@""];
        item.target = self;
        [advanced addItem:item];
    }
    [appMenu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit MiniLaunch" action:@selector(terminate:) keyEquivalent:@"q"];
    quit.target = NSApp;
    [appMenu addItem:quit];
    NSMenuItem *editItem = [NSMenuItem new]; [menu addItem:editItem];
    NSMenu *edit = [[NSMenu alloc] initWithTitle:@"Edit"]; editItem.submenu = edit;
    [edit addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [edit addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [edit addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [edit addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    NSApp.mainMenu = menu;
    // 보조 앱에는 앱 메뉴 막대가 없으므로 관리 명령을 상태 메뉴로 제공합니다.
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    // 전체 크기는 유지하면서 박스 사이에 여유를 둡니다.
    NSImage *statusIcon = [NSImage imageWithSize:NSMakeSize(15, 15) flipped:NO drawingHandler:^BOOL(NSRect bounds) {
        CGFloat boxSize = 3.75;
        CGFloat gap = (NSWidth(bounds) - boxSize * 3) / 2;
        [NSColor.blackColor setFill];
        for (NSUInteger row = 0; row < 3; row++) {
            for (NSUInteger column = 0; column < 3; column++) {
                NSRect box = NSMakeRect(column * (boxSize + gap), row * (boxSize + gap), boxSize, boxSize);
                [[NSBezierPath bezierPathWithRoundedRect:box xRadius:0.8 yRadius:0.8] fill];
            }
        }
        return YES;
    }];
    statusIcon.template = YES;
    statusIcon.accessibilityDescription = @"MiniLaunch";
    self.launcherStatusIcon = statusIcon;
    self.statusMenu = [appMenu copy];
    [self updateSleepAppearance];
    self.statusItem.button.target = self;
    self.statusItem.button.action = @selector(statusItemClicked:);
    [self.statusItem.button sendActionOn:NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp];
    self.launcher = [[LauncherController alloc] initWithRoot:self.appsDirectoryURL];
    self.gestures = [GestureMonitor new];
    __weak typeof(self) weakSelf = self;
    self.gestures.onGesture = ^(NSInteger direction) {
        if (direction < 0 && !weakSelf.launcher.visible) [weakSelf.launcher showFromDock:NO];
        if (direction > 0 && weakSelf.launcher.visible) [weakSelf.launcher hide];
    };
    if (![NSUserDefaults.standardUserDefaults boolForKey:@"DisableGestures"]) {
        [self.gestures start];
        NSNotificationCenter *center = NSWorkspace.sharedWorkspace.notificationCenter;
        for (NSString *name in @[NSWorkspaceDidWakeNotification, NSWorkspaceScreensDidWakeNotification,
                                 NSWorkspaceSessionDidBecomeActiveNotification]) {
            [center addObserver:self selector:@selector(scheduleGestureReconnect:) name:name object:nil];
        }
    }
    [self.launcher showFromDock:NO];
}
- (void)selectSleepMode:(NSMenuItem *)sender {
    NSError *error = nil;
    BOOL success = [self.sleepController setMode:(MLSleepMode)sender.tag error:&error];
    [self updateSleepAppearance];
    if (!success) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"잠자기 방지 상태를 변경하지 못했습니다";
        alert.informativeText = error.localizedDescription ?: @"선택한 모드를 적용할 수 없습니다.";
        [alert runModal];
    }
}
- (void)checkSleepState:(NSTimer *)timer {
    if (self.sleepController.mode != MLSleepModeOff) {
        [self.sleepLog recordEvent:@"periodic_check" fields:self.sleepController.diagnosticState];
    }
}
- (void)recordPowerEvent:(NSNotification *)notification {
    NSString *observed = [[NSISO8601DateFormatter new] stringFromDate:NSDate.date];
    // 제스처 활성화 여부와 무관하게 전원 이벤트를 기록합니다.
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableDictionary *fields = [self.sleepController.diagnosticState mutableCopy];
        fields[@"notification"] = notification.name;
        fields[@"observed_at"] = observed;
        [self.sleepLog recordEvent:@"power_event" fields:fields];
    });
}
- (void)openSleepLogs:(id)sender {
    [self.sleepLog recordEvent:@"logs_opened" fields:@{}];
    [NSWorkspace.sharedWorkspace openURL:self.sleepLog.directoryURL];
}
- (void)updateSleepAppearance {
    MLSleepMode mode = self.sleepController.mode;
    // 복사한 상태 메뉴와 앱 메뉴 양쪽에 실제 요청 상태를 반영합니다.
    for (NSMenu *menu in @[NSApp.mainMenu.itemArray.firstObject.submenu, self.statusMenu]) {
        for (NSMenuItem *item in menu.itemArray) {
            if (item.action != @selector(selectSleepMode:)) continue;
            item.state = item.tag == mode ? NSControlStateValueOn : NSControlStateValueOff;
        }
    }
    NSImage *icon = self.launcherStatusIcon;
    BOOL active = mode != MLSleepModeOff;
    if (active) {
        NSImage *launcherIcon = self.launcherStatusIcon;
        NSImage *cup = [NSImage imageWithSystemSymbolName:@"cup.and.saucer.fill" accessibilityDescription:nil];
        icon = [NSImage imageWithSize:NSMakeSize(42, 15) flipped:NO drawingHandler:^BOOL(NSRect bounds) {
            (void)bounds;
            [launcherIcon drawInRect:NSMakeRect(0, 0, 15, 15)];
            [NSColor.blackColor setFill];
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(20, 6.5, 2, 2)] fill];
            [cup drawInRect:NSMakeRect(27, 0, 15, 15)];
            return YES;
        }];
        icon.template = YES;
    }
    self.statusItem.length = active ? NSVariableStatusItemLength : NSSquareStatusItemLength;
    self.statusItem.button.image = icon;
    NSString *state = mode == MLSleepModeOff ? @"Off" :
                      mode == MLSleepModeSystem ? @"Prevent Sleep" : @"Prevent Sleep and Display Sleep";
    NSString *label = [@"MiniLaunch — Caffein: " stringByAppendingString:state];
    self.statusItem.button.toolTip = label;
    [self.statusItem.button setAccessibilityLabel:label];
}
- (void)statusItemClicked:(NSStatusBarButton *)button {
    NSEvent *event = NSApp.currentEvent;
    if (event.type == NSEventTypeRightMouseUp || (event.modifierFlags & NSEventModifierFlagControl)) {
        [self.launcher hide];
        [self.statusMenu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSMinY(button.bounds)) inView:button];
        return;
    }
    if (self.launcher.visible) {
        [self.launcher hide];
        return;
    }
    NSRect rect = [button.window convertRectToScreen:[button convertRect:button.bounds toView:nil]];
    [self.launcher showFromMenuBarRect:rect];
}
- (NSMenu *)applicationDockMenu:(NSApplication *)sender {
    NSMenu *menu = [NSMenu new];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:self.openFolderMenuTitle action:@selector(openFolder:) keyEquivalent:@""];
    item.target = self;
    [menu addItem:item];
    return menu;
}
- (void)openFolder:(id)sender {
    [NSWorkspace.sharedWorkspace openURL:self.appsDirectoryURL];
}
- (void)requestAccessibility:(id)sender {
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES});
}
- (void)gestureStatus:(id)sender {
    NSAlert *alert = [NSAlert new]; alert.messageText = self.gestures.status ?: @"제스처 비활성화";
    alert.informativeText = @"네 손가락 또는 다섯 손가락을 모으면 열리고 펼치면 닫힙니다. 시스템의 Show Desktop 제스처 차단은 지원하지 않습니다.";
    [alert runModal];
}
- (void)scheduleGestureReconnect:(NSNotification *)notification {
    // 복귀 알림이 겹치면 장치가 준비될 시간을 주고 한 번만 다시 연결합니다.
    dispatch_async(dispatch_get_main_queue(), ^{
        NSUInteger generation = ++self.gestureReconnectGeneration;
        NSLog(@"제스처 재연결 예약: %@", notification.name);
        [self reconnectGesturesAfterDelay:1 generation:generation attempts:3];
    });
}
- (void)reconnectGesturesAfterDelay:(NSTimeInterval)delay generation:(NSUInteger)generation attempts:(NSUInteger)attempts {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != self.gestureReconnectGeneration) return;
        [self.gestures stop];
        [self.gestures start];
        if (!self.gestures.connected && attempts > 1) {
            [self reconnectGesturesAfterDelay:2 generation:generation attempts:attempts - 1];
        }
    });
}
- (void)restartGestures:(id)sender {
    ++self.gestureReconnectGeneration;
    [self.gestures stop]; [self.gestures start];
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    [self.launcher showFromDock:YES]; return NO;
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return NO; }
- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.sleepCheckTimer invalidate];
    ++self.gestureReconnectGeneration;
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    [self.gestures stop];
    [self.sleepController setMode:MLSleepModeOff error:nil];
    [self.sleepLog recordEvent:@"app_exit" fields:self.sleepController.diagnosticState];
}
@end
int main(void) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        // Dock 재열기가 일반 앱 활성화와 Space 전환을 유발하지 않게 합니다.
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        AppDelegate *delegate = [AppDelegate new]; app.delegate = delegate;
        [app run];
    }
    return 0;
}
