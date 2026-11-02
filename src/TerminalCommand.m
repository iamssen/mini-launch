#import "TerminalCommand.h"

@implementation TerminalCommand
+ (void)run:(NSString *)command completion:(void (^)(NSString *error))completion {
    BOOL iterm = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.googlecode.iterm2"] != nil;
    NSString *script = [NSBundle.mainBundle pathForResource:iterm ? @"iTermCommand" : @"TerminalCommand" ofType:@"applescript"];
    if (!script) { completion(@"터미널 실행 리소스를 찾을 수 없습니다."); return; }
    // argv로 본문을 전달하여 AppleScript 코드와 명령 데이터를 분리합니다.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSTask *task = [NSTask new];
            task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/osascript"];
            task.arguments = @[script, command];
            NSPipe *errors = [NSPipe pipe];
            task.standardError = errors;
            task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
            NSError *error = nil;
            NSString *message = nil;
            if (![task launchAndReturnError:&error]) message = error.localizedDescription;
            else {
                NSData *data = [errors.fileHandleForReading readDataToEndOfFile];
                [task waitUntilExit];
                if (task.terminationStatus != 0) {
                    NSString *detail = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    message = [NSString stringWithFormat:@"명령을 실행하지 못했습니다: %@", detail ?: @"알 수 없는 오류"];
                    if ([detail containsString:@"-1743"]) message = @"시스템 설정 → 개인정보 보호 및 보안 → 자동화에서 MiniLaunch의 터미널 제어를 허용해 주세요.";
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{ completion(message); });
        }
    });
}
@end
