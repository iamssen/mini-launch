#import "DockLocator.h"
#import <ApplicationServices/ApplicationServices.h>
static id attribute(AXUIElementRef element, CFStringRef name) {
    CFTypeRef result = NULL;
    if (AXUIElementCopyAttributeValue(element, name, &result) != kAXErrorSuccess) return nil;
    return CFBridgingRelease(result);
}
static NSRect findIcon(AXUIElementRef element, NSString *path, int depth) {
    if (depth > 5) return NSZeroRect;
    id url = attribute(element, kAXURLAttribute);
    if ([url isKindOfClass:NSURL.class] && [[url path] isEqualToString:path]) {
        id position = attribute(element, kAXPositionAttribute);
        id size = attribute(element, kAXSizeAttribute);
        CGPoint p; CGSize s;
        if (position && size && CFGetTypeID((__bridge CFTypeRef)position) == AXValueGetTypeID() &&
            CFGetTypeID((__bridge CFTypeRef)size) == AXValueGetTypeID() &&
            AXValueGetValue((__bridge AXValueRef)position, kAXValueCGPointType, &p) &&
            AXValueGetValue((__bridge AXValueRef)size, kAXValueCGSizeType, &s)) {
            CGFloat top = NSMaxY(NSScreen.screens.firstObject.frame);
            return NSMakeRect(p.x, top - p.y - s.height, s.width, s.height);
        }
    }
    NSArray *children = attribute(element, kAXChildrenAttribute);
    if (![children isKindOfClass:NSArray.class]) return NSZeroRect;
    for (id child in children) {
        NSRect rect = findIcon((__bridge AXUIElementRef)child, path, depth + 1);
        if (!NSIsEmptyRect(rect)) return rect;
    }
    return NSZeroRect;
}
@implementation DockLocator
+ (NSRect)iconRect {
    if (!AXIsProcessTrusted()) return NSZeroRect;
    NSRunningApplication *dock = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.dock"].firstObject;
    if (!dock) return NSZeroRect;
    AXUIElementRef root = AXUIElementCreateApplication(dock.processIdentifier);
    AXUIElementSetMessagingTimeout(root, 0.15);
    NSRect rect = findIcon(root, NSBundle.mainBundle.bundlePath, 0);
    CFRelease(root);
    return rect;
}
@end
