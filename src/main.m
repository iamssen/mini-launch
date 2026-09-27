#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import "LauncherController.h"
#import "GestureMonitor.h"
@interface AppDelegate : NSObject <NSApplicationDelegate>
@property LauncherController *launcher;
@property GestureMonitor *gestures;
@property NSUInteger gestureReconnectGeneration;
@end
@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSMenu *menu = [NSMenu new];
    NSMenuItem *appItem = [NSMenuItem new]; [menu addItem:appItem];
    NSMenu *appMenu = [NSMenu new]; appItem.submenu = appMenu;
    NSArray *titles = @[@"MiniLaunch 열기", @"앱 폴더 열기", @"Dock 위치 권한 허용…", @"제스처 상태…", @"제스처 장치 다시 연결", @"MiniLaunch 종료"];
    NSArray *actions = @[@"show:", @"openFolder:", @"requestAccessibility:", @"gestureStatus:", @"restartGestures:", @"terminate:"];
    for (NSUInteger i = 0; i < titles.count; i++) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:titles[i] action:NSSelectorFromString(actions[i]) keyEquivalent:i == 5 ? @"q" : @""];
        item.target = i == 5 ? NSApp : self; [appMenu addItem:item];
    }
    NSMenuItem *editItem = [NSMenuItem new]; [menu addItem:editItem];
    NSMenu *edit = [[NSMenu alloc] initWithTitle:@"편집"]; editItem.submenu = edit;
    [edit addItemWithTitle:@"잘라내기" action:@selector(cut:) keyEquivalent:@"x"];
    [edit addItemWithTitle:@"복사" action:@selector(copy:) keyEquivalent:@"c"];
    [edit addItemWithTitle:@"붙여넣기" action:@selector(paste:) keyEquivalent:@"v"];
    [edit addItemWithTitle:@"전체 선택" action:@selector(selectAll:) keyEquivalent:@"a"];
    NSApp.mainMenu = menu;
    NSString *root = [NSUserDefaults.standardUserDefaults stringForKey:@"AppsDirectory"] ?: @"~/Apps";
    self.launcher = [[LauncherController alloc] initWithRoot:[NSURL fileURLWithPath:root.stringByExpandingTildeInPath]];
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
- (void)show:(id)sender { [self.launcher showFromDock:NO]; }
- (NSMenu *)applicationDockMenu:(NSApplication *)sender {
    NSMenu *menu = [NSMenu new];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Open Apps/" action:@selector(openFolder:) keyEquivalent:@""];
    item.target = self;
    [menu addItem:item];
    return menu;
}
- (void)openFolder:(id)sender {
    NSString *root = [NSUserDefaults.standardUserDefaults stringForKey:@"AppsDirectory"] ?: @"~/Apps";
    [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:root.stringByExpandingTildeInPath]];
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
    ++self.gestureReconnectGeneration;
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    [self.gestures stop];
}
@end
int main(void) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        AppDelegate *delegate = [AppDelegate new]; app.delegate = delegate;
        [app run];
    }
    return 0;
}
