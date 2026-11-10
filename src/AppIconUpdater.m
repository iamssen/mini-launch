#import <Cocoa/Cocoa.h>
#import <CoreServices/CoreServices.h>
#import <sys/xattr.h>
#import "AppIconUpdater.h"
#import "CommandStore.h"
#import "EventLog.h"

static NSURL *ResolvePath(NSString *path, NSURL *directory) {
    return [NSURL fileURLWithPath:path.stringByExpandingTildeInPath relativeToURL:directory]
        .absoluteURL.URLByStandardizingPath.URLByResolvingSymlinksInPath;
}

// Finder의 사용자 아이콘 플래그와 실제 icns 리소스를 함께 확인합니다.
static NSData *CustomIcon(NSURL *folder, NSError **error) {
    unsigned char info[32];
    ssize_t size = getxattr(folder.fileSystemRepresentation, "com.apple.FinderInfo", info, sizeof(info), 0, 0);
    if (size < 0) {
        if (errno != ENOATTR) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        return nil;
    }
    if (size < 10 || !(info[8] & 4)) return nil;
    NSURL *file = [folder URLByAppendingPathComponent:@"Icon\r"];
    // 리소스 맵의 다른 항목이나 헤더가 달라도 사용자 아이콘 데이터만 비교합니다.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    FSRef ref;
    OSStatus status = FSPathMakeRef((const UInt8 *)file.fileSystemRepresentation, &ref, NULL);
    NSData *data = nil;
    if (status == noErr) {
        ResFileRefNum previous = CurResFile();
        ResFileRefNum fork = FSOpenResFile(&ref, fsRdPerm);
        status = ResError();
        if (status == noErr) {
            Handle icon = Get1Resource(kIconFamilyType, kCustomIconResource);
            status = ResError();
            if (icon) {
                HLock(icon);
                data = [NSData dataWithBytes:*icon length:GetHandleSize(icon)];
                ReleaseResource(icon);
            }
            CloseResFile(fork);
            UseResFile(previous);
        }
    }
#pragma clang diagnostic pop
    if (!data && status != fnfErr && status != resNotFound && status != eofErr)
        *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
    return data;
}

// 인코딩과 색상 프로파일 차이를 제거하고 투명도를 포함한 sRGB 픽셀을 비교합니다.
static NSData *IconPixels(NSImage *image, size_t side) {
    NSRect rect = NSMakeRect(0, 0, side, side);
    CGImageRef source = [image CGImageForProposedRect:&rect context:nil hints:nil];
    if (!source) return nil;
    NSMutableData *pixels = [NSMutableData dataWithLength:side * side * 4];
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes, side, side, 8, side * 4,
        space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) return nil;
    CGContextDrawImage(context, CGRectMake(0, 0, side, side), source);
    CGContextRelease(context);
    return pixels;
}

static BOOL IconsMatch(NSData *expected, NSData *current, NSImage *displayed) {
    if ([expected isEqual:current]) return YES;
    NSImage *actual = current ? [[NSImage alloc] initWithData:current] : displayed;
    NSImage *target = [[NSImage alloc] initWithData:expected];
    if (!actual || !target) return NO;
    for (NSNumber *size in @[@32, @1024]) {
        size_t side = size.unsignedIntegerValue;
        if (![IconPixels(target, side) isEqual:IconPixels(actual, side)]) return NO;
    }
    return YES;
}

static NSArray<NSRunningApplication *> *RunningAt(NSURL *app) {
    NSMutableArray *matches = [NSMutableArray array];
    for (NSRunningApplication *running in NSWorkspace.sharedWorkspace.runningApplications) {
        if ([running.bundleURL.URLByStandardizingPath.URLByResolvingSymlinksInPath.path isEqual:app.path])
            [matches addObject:running];
    }
    return matches;
}

static NSString *ApplyIcon(NSURL *app, NSURL *png, NSURL *reference, NSString **event) {
    *event = @"failed";
    NSNumber *application = nil;
    [app getResourceValue:&application forKey:NSURLIsApplicationKey error:nil];
    if (!application.boolValue || [app.pathExtension caseInsensitiveCompare:@"app"] != NSOrderedSame)
        return @"대상 앱을 찾을 수 없습니다.";
    if ([app.path isEqual:NSBundle.mainBundle.bundleURL.URLByResolvingSymlinksInPath.path])
        return @"실행 중인 MiniLaunch 자체는 변경할 수 없습니다.";
    NSError *error = nil;
    NSData *bytes = [NSData dataWithContentsOfURL:png options:0 error:&error];
    if (!bytes) return error.localizedDescription;
    const unsigned char signature[] = {137,80,78,71,13,10,26,10};
    if (bytes.length < sizeof(signature) || memcmp(bytes.bytes, signature, sizeof(signature)))
        return @"지정한 파일이 PNG가 아닙니다.";
    NSImage *image = [[NSImage alloc] initWithData:bytes];
    if (!image.isValid) return @"PNG 이미지를 읽지 못했습니다.";
    NSWorkspace *workspace = NSWorkspace.sharedWorkspace;
    if (![workspace setIcon:image forFile:reference.path options:0]) return @"비교용 아이콘을 생성하지 못했습니다.";
    NSData *expected = CustomIcon(reference, &error);
    if (!expected) return error.localizedDescription ?: @"비교용 아이콘을 읽지 못했습니다.";
    NSData *current = CustomIcon(app, &error);
    if (error) return error.localizedDescription;
    NSImage *displayed = current ? nil : [workspace iconForFile:app.path];
    if (IconsMatch(expected, current, displayed)) {
        *event = @"matched";
        return @"이미 일치합니다.";
    }

    NSArray *running = RunningAt(app);
    for (NSRunningApplication *instance in running) {
        if (![instance terminate] && !instance.terminated) return @"앱 종료 요청이 거부되었습니다.";
    }
    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 10;
    while (RunningAt(app).count) {
        if (NSProcessInfo.processInfo.systemUptime >= deadline) return @"앱이 종료되지 않아 변경을 건너뜁니다.";
        [NSThread sleepForTimeInterval:0.1];
    }
    BOOL applied = [workspace setIcon:image forFile:app.path options:0] && IconsMatch(expected, CustomIcon(app, &error), nil);
    NSString *result = applied ? @"아이콘을 변경했습니다." : @"아이콘 변경을 확인하지 못했습니다.";
    if (running.count) {
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        __block NSError *launchError;
        [workspace openApplicationAtURL:app configuration:NSWorkspaceOpenConfiguration.configuration
            completionHandler:^(NSRunningApplication *__unused opened, NSError *failure) {
                launchError = failure;
                dispatch_semaphore_signal(done);
            }];
        dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
        if (launchError) return [result stringByAppendingFormat:@" 재실행 실패: %@", launchError.localizedDescription];
    }
    if (applied) *event = @"changed";
    return result;
}

NSString *MLApplyAppIcons(NSURL *configuration, EventLog *log) {
    NSError *error = nil;
    NSArray *entries = [CommandStore appIconsAtURL:configuration error:&error];
    if (!entries.count) {
        NSString *message = error.localizedDescription ?: @"config.yml의 app_icons에 앱 경로와 PNG 경로를 지정해 주세요.";
        [log recordEvent:@"configuration_error" fields:@{@"config": configuration.path, @"message": message}];
        return message;
    }
    NSURL *directory = configuration.URLByDeletingLastPathComponent;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *reference = [fm.temporaryDirectory URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
    if (![fm createDirectoryAtURL:reference withIntermediateDirectories:NO attributes:nil error:&error]) {
        [log recordEvent:@"preparation_error" fields:@{@"message": error.localizedDescription}];
        return error.localizedDescription;
    }
    NSMutableArray *results = [NSMutableArray array];
    for (NSDictionary *entry in entries) {
        @autoreleasepool {
            NSURL *app = ResolvePath(entry[@"app"], directory);
            NSURL *png = ResolvePath(entry[@"png"], directory);
            NSString *event;
            NSString *result = ApplyIcon(app, png, reference, &event);
            [log recordEvent:event fields:@{@"app": app.path, @"png": png.path, @"message": result}];
            if ([event isEqualToString:@"matched"]) continue;
            [results addObject:[NSString stringWithFormat:@"%@ — %@", app.path.stringByAbbreviatingWithTildeInPath, result]];
        }
    }
    [fm removeItemAtURL:reference error:nil];
    return results.count ? [results componentsJoinedByString:@"\n"] : nil;
}
