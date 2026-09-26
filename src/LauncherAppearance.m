#import "LauncherAppearance.h"
#import <QuartzCore/QuartzCore.h>

@implementation LauncherBackdrop {
    NSView *_surface;
    NSView *_content;
}
- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.wantsLayer = YES;
    self.layer.backgroundColor = NSColor.clearColor.CGColor;
    self.layer.opaque = NO;
    if (@available(macOS 26.0, *)) {
        NSGlassEffectView *glass = [[NSGlassEffectView alloc] initWithFrame:self.bounds];
        // Clear의 투명감을 유지하면서 검정 틴트로 밝기를 낮춥니다.
        glass.style = NSGlassEffectViewStyleClear;
        glass.tintColor = [NSColor colorWithWhite:0 alpha:0.50];
        glass.cornerRadius = 26;
        glass.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        _content = [[NSView alloc] initWithFrame:self.bounds];
        glass.contentView = _content;
        _surface = glass;
    } else {
        NSVisualEffectView *blur = [[NSVisualEffectView alloc] initWithFrame:self.bounds];
        blur.material = NSVisualEffectMaterialHUDWindow;
        blur.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        blur.state = NSVisualEffectStateActive;
        blur.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
        _surface = blur;
        _content = blur;
    }
    [self addSubview:_surface];
    return self;
}
- (NSView *)effect { return _content; }
- (BOOL)isOpaque { return NO; }
- (void)updateShape {
    _surface.frame = self.bounds;
    _content.frame = self.bounds;
    CGFloat w = NSWidth(self.bounds), h = NSHeight(self.bounds);
    CGFloat bottom = self.showsTail ? 12 : 0;
    CGFloat r = 26;
    CGFloat x = MAX(r + 16, MIN(self.tailX, w - r - 16));
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(r, bottom)];
    if (self.showsTail) {
        [path lineToPoint:NSMakePoint(x - 14, bottom)];
        [path curveToPoint:NSMakePoint(x - 6, 5) controlPoint1:NSMakePoint(x - 10, bottom) controlPoint2:NSMakePoint(x - 9, 8)];
        [path curveToPoint:NSMakePoint(x + 6, 5) controlPoint1:NSMakePoint(x, -1) controlPoint2:NSMakePoint(x, -1)];
        [path curveToPoint:NSMakePoint(x + 14, bottom) controlPoint1:NSMakePoint(x + 9, 8) controlPoint2:NSMakePoint(x + 10, bottom)];
    }
    [path lineToPoint:NSMakePoint(w - r, bottom)];
    [path curveToPoint:NSMakePoint(w, bottom + r) controlPoint1:NSMakePoint(w - r * 0.448, bottom) controlPoint2:NSMakePoint(w, bottom + r * 0.448)];
    [path lineToPoint:NSMakePoint(w, h - r)];
    [path curveToPoint:NSMakePoint(w - r, h) controlPoint1:NSMakePoint(w, h - r * 0.448) controlPoint2:NSMakePoint(w - r * 0.448, h)];
    [path lineToPoint:NSMakePoint(r, h)];
    [path curveToPoint:NSMakePoint(0, h - r) controlPoint1:NSMakePoint(r * 0.448, h) controlPoint2:NSMakePoint(0, h - r * 0.448)];
    [path lineToPoint:NSMakePoint(0, bottom + r)];
    [path curveToPoint:NSMakePoint(r, bottom) controlPoint1:NSMakePoint(0, bottom + r * 0.448) controlPoint2:NSMakePoint(r * 0.448, bottom)];
    [path closePath];
    NSImage *mask = [NSImage imageWithSize:self.bounds.size flipped:NO drawingHandler:^BOOL(NSRect rect) {
        (void)rect;
        [NSColor.blackColor setFill];
        [path fill];
        return YES;
    }];
    if (@available(macOS 26.0, *)) {
        // 표준 유리 효과를 기존 말풍선 외곽 안에 표시합니다.
        CAShapeLayer *shape = [CAShapeLayer layer];
        shape.frame = self.bounds;
        shape.path = path.CGPath;
        self.layer.mask = shape;
    } else {
        ((NSVisualEffectView *)_surface).maskImage = mask;
    }
    [self.window invalidateShadow];
}
@end

@implementation LauncherIconButton
- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.bordered = NO;
    self.focusRingType = NSFocusRingTypeNone;
    return self;
}
- (void)setSelected:(BOOL)selected {
    _selected = selected;
    self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    CGFloat w = NSWidth(self.bounds);
    if (self.selected || self.highlighted) {
        [[[NSColor whiteColor] colorWithAlphaComponent:self.highlighted ? 0.22 : 0.13] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 3, 2) xRadius:15 yRadius:15] fill];
    }
    // 96pt 이미지 안의 기본 아이콘 여백을 포함하면 실제 아이콘은 약 80pt입니다.
    [self.image drawInRect:NSMakeRect((w - 96) / 2, 0, 96, 96)
        fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1
        respectFlipped:YES hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.alignment = NSTextAlignmentCenter;
    paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
    NSShadow *labelShadow = [NSShadow new];
    labelShadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.55];
    labelShadow.shadowBlurRadius = 3;
    labelShadow.shadowOffset = NSMakeSize(0, -1);
    NSDictionary *attributes = @{
        NSShadowAttributeName: labelShadow,
        NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: NSColor.whiteColor,
        NSParagraphStyleAttributeName: paragraph
    };
    [self.title drawInRect:NSMakeRect(0, 99, w, 19) withAttributes:attributes];
}
- (BOOL)isFlipped { return YES; }
@end
