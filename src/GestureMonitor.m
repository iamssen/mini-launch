#import "GestureMonitor.h"
#import "GestureRecognizer.h"
#import <dlfcn.h>
#import <math.h>
#import <stdatomic.h>

// 비공개 ABI입니다. OS 업데이트에 따라 구조 및 함수가 바뀔 수 있습니다.
typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint position, velocity; } MTVector;
typedef struct {
    int32_t frame; double timestamp;
    int32_t path, state, finger, hand;
    MTVector normalized;
    float size; int32_t unknown;
    float angle, major, minor;
    MTVector absolute;
    int32_t unknown2, unknown3; float density;
} MTContact;
typedef void (*MTCallback)(void *, MTContact *, size_t, double, size_t);
static __weak GestureMonitor *activeMonitor;
static atomic_uint_fast64_t connectionGeneration;

@interface GestureMonitor ()
@property NSString *status;
@property NSMutableDictionary<NSValue *, NSValue *> *states;
@property BOOL running;
@property BOOL receivedFrame;
- (void)consumeDevice:(void *)device count:(int)count radius:(double)radius time:(double)time;
@end
static void contacts(void *device, MTContact *touches, size_t count, double time, size_t frame) {
    (void)frame;
    uint_fast64_t generation = atomic_load(&connectionGeneration);
    if (count > 16) return;
    double x = 0, y = 0; int n = 0;
    for (size_t i = 0; i < count; i++) {
        if (touches[i].state != 3 && touches[i].state != 4) continue;
        MTPoint p = touches[i].normalized.position;
        if (!isfinite(p.x) || !isfinite(p.y) || p.x < 0 || p.x > 1 || p.y < 0 || p.y > 1) return;
        x += p.x; y += p.y; n++;
    }
    double radius = 0;
    if (n) {
        x /= n; y /= n;
        for (size_t i = 0; i < count; i++) {
            if (touches[i].state != 3 && touches[i].state != 4) continue;
            MTPoint p = touches[i].normalized.position;
            radius += hypot(p.x - x, p.y - y);
        }
        radius /= n;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        // 재연결 전에 대기열에 들어온 프레임은 새 인식 상태에 섞지 않습니다.
        if (generation != atomic_load(&connectionGeneration)) return;
        [activeMonitor consumeDevice:device count:n radius:radius time:time];
    });
}
@implementation GestureMonitor {
    void *_library;
    CFArrayRef _devices;
    void (*_register)(void *, MTCallback);
    void (*_unregister)(void *, MTCallback);
    void (*_start)(void *, int);
    void (*_stop)(void *);
}
- (BOOL)connected { return self.running; }
- (void)start {
    if (self.running) return;
    self.states = [NSMutableDictionary dictionary];
    self.receivedFrame = NO;
    if (!_library) _library = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LOCAL | RTLD_NOW);
    if (!_library) { self.status = @"제스처 사용 불가: 비공개 프레임워크 없음"; return; }
    CFArrayRef (*createList)(void) = dlsym(_library, "MTDeviceCreateList");
    _register = dlsym(_library, "MTRegisterContactFrameCallback");
    _unregister = dlsym(_library, "MTUnregisterContactFrameCallback");
    _start = dlsym(_library, "MTDeviceStart");
    _stop = dlsym(_library, "MTDeviceStop");
    if (!createList || !_register || !_unregister || !_start || !_stop) {
        self.status = @"제스처 사용 불가: API 호환되지 않음"; return;
    }
    _devices = createList();
    if (!_devices || CFArrayGetCount(_devices) == 0) {
        if (_devices) CFRelease(_devices);
        _devices = NULL; self.status = @"제스처 사용 불가: 장치 없음"; return;
    }
    activeMonitor = self; self.running = YES;
    for (CFIndex i = 0; i < CFArrayGetCount(_devices); i++) {
        void *device = (void *)CFArrayGetValueAtIndex(_devices, i);
        _register(device, contacts); _start(device, 0);
    }
    self.status = @"제스처 장치 연결됨: 첫 입력 대기 중";
    NSLog(@"제스처 장치 연결: %ld개", (long)CFArrayGetCount(_devices));
}
- (void)consumeDevice:(void *)device count:(int)count radius:(double)radius time:(double)time {
    if (!self.running) return;
    if (!self.receivedFrame) {
        self.receivedFrame = YES;
        self.status = @"네 손가락 또는 다섯 손가락 제스처 입력 수신 중";
        NSLog(@"제스처 연결 후 첫 입력 수신");
    }
    NSValue *key = [NSValue valueWithPointer:device];
    MLGestureState state = {0};
    [self.states[key] getValue:&state size:sizeof(state)];
    int direction = MLRecognize(&state, count, radius, time);
    self.states[key] = [NSValue value:&state withObjCType:@encode(MLGestureState)];
    if (direction && self.onGesture) self.onGesture(direction);
}
- (void)stop {
    self.running = NO; activeMonitor = nil;
    atomic_fetch_add(&connectionGeneration, 1);
    if (_devices) {
        for (CFIndex i = 0; i < CFArrayGetCount(_devices); i++) {
            void *device = (void *)CFArrayGetValueAtIndex(_devices, i);
            _unregister(device, contacts); _stop(device);
        }
        CFRelease(_devices); _devices = NULL;
    }
    [self.states removeAllObjects];
    // 종료 중인 콜백이 코드를 참조할 수 있으므로 라이브러리는 프로세스 종료까지 유지합니다.
}
@end
