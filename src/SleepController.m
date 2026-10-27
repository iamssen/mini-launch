#import "SleepController.h"
#import "SleepLog.h"
#import <IOKit/pwr_mgt/IOPMLib.h>

@implementation SleepController {
    NSMutableDictionary<NSString *, NSNumber *> *_assertions;
}
- (instancetype)init {
    if ((self = [super init])) _assertions = [NSMutableDictionary new];
    return self;
}
- (MLSleepMode)mode {
    if (_assertions[(__bridge NSString *)kIOPMAssertionTypePreventUserIdleDisplaySleep]) return MLSleepModeDisplayAndSystem;
    return _assertions.count ? MLSleepModeSystem : MLSleepModeOff;
}
- (BOOL)setMode:(MLSleepMode)mode error:(NSError **)error {
    MLSleepMode previous = self.mode;
    [self.log recordEvent:@"mode_requested" fields:@{@"previous_mode": @(previous), @"requested_mode": @(mode)}];
    NSArray<NSString *> *wanted;
    switch (mode) {
        case MLSleepModeOff: wanted = @[]; break;
        case MLSleepModeSystem: wanted = @[(__bridge NSString *)kIOPMAssertionTypePreventUserIdleSystemSleep]; break;
        case MLSleepModeDisplayAndSystem:
            wanted = @[(__bridge NSString *)kIOPMAssertionTypePreventUserIdleSystemSleep,
                       (__bridge NSString *)kIOPMAssertionTypePreventUserIdleDisplaySleep];
            break;
        default: return NO;
    }
    NSMutableDictionary<NSString *, NSNumber *> *created = [NSMutableDictionary new];
    // 먼저 필요한 요청을 확보하여 생성 실패 시 기존 모드를 유지합니다.
    for (NSString *type in wanted) {
        if (_assertions[type]) continue;
        IOPMAssertionID identifier = kIOPMNullAssertionID;
        IOReturn result = IOPMAssertionCreateWithName((__bridge CFStringRef)type, kIOPMAssertionLevelOn,
                                                    CFSTR("MiniLaunch Caffein"), &identifier);
        [self.log recordEvent:@"assertion_create" fields:@{@"type": type, @"id": @(identifier), @"result": @(result)}];
        if (result != kIOReturnSuccess) {
            for (NSString *createdType in created) {
                NSNumber *value = created[createdType];
                IOReturn releaseResult = IOPMAssertionRelease(value.unsignedIntValue);
                [self.log recordEvent:@"assertion_rollback" fields:@{@"type": createdType, @"id": value, @"result": @(releaseResult)}];
                if (releaseResult != kIOReturnSuccess) _assertions[createdType] = value;
            }
            if (error) *error = [self errorWithCode:result operation:@"생성"];
            [self.log recordEvent:@"mode_failed" fields:self.diagnosticState];
            return NO;
        }
        created[type] = @(identifier);
    }
    [_assertions addEntriesFromDictionary:created];
    for (NSString *type in _assertions.allKeys) {
        if ([wanted containsObject:type]) continue;
        IOReturn result = IOPMAssertionRelease(_assertions[type].unsignedIntValue);
        [self.log recordEvent:@"assertion_release" fields:@{@"type": type, @"id": _assertions[type], @"result": @(result)}];
        if (result != kIOReturnSuccess) {
            if (error) *error = [self errorWithCode:result operation:@"해제"];
            [self.log recordEvent:@"mode_failed" fields:self.diagnosticState];
            return NO;
        }
        [_assertions removeObjectForKey:type];
    }
    [self.log recordEvent:@"mode_applied" fields:self.diagnosticState];
    return YES;
}
- (NSDictionary *)diagnosticState {
    CFDictionaryRef result = NULL;
    IOReturn code = IOPMCopyAssertionsByProcess(&result);
    NSDictionary *processes = CFBridgingRelease(result);
    NSMutableArray *actual = [NSMutableArray new];
    NSMutableArray *types = [NSMutableArray new];
    BOOL active = YES;
    NSMutableArray *ownedChecks = [NSMutableArray new];
    for (NSString *type in _assertions) {
        NSNumber *identifier = _assertions[type];
        NSDictionary *properties = CFBridgingRelease(IOPMAssertionCopyProperties(identifier.unsignedIntValue));
        BOOL valid = properties && [properties[(__bridge NSString *)kIOPMAssertionTypeKey] isEqual:type] &&
                     [properties[(__bridge NSString *)kIOPMAssertionLevelKey] intValue] == kIOPMAssertionLevelOn;
        active = active && valid;
        [ownedChecks addObject:@{@"type": type, @"id": identifier, @"valid": @(valid)}];
    }
    for (NSDictionary *entry in processes[@(NSProcessInfo.processInfo.processIdentifier)]) {
        if (![entry[(__bridge NSString *)kIOPMAssertionNameKey] isEqualToString:@"MiniLaunch Caffein"]) continue;
        NSString *type = entry[(__bridge NSString *)kIOPMAssertionTypeKey] ?: @"";
        NSNumber *level = entry[(__bridge NSString *)kIOPMAssertionLevelKey] ?: @0;
        [types addObject:type];
        active = active && level.intValue == kIOPMAssertionLevelOn;
        [actual addObject:@{@"type": type, @"level": level}];
    }
    BOOL matches = code == kIOReturnSuccess && active && types.count == _assertions.count &&
                   [[NSSet setWithArray:types] isEqualToSet:[NSSet setWithArray:_assertions.allKeys]];
    // 조회 실패를 요청 없음으로 단정하지 않고 반환 코드를 함께 남깁니다.
    return @{@"mode": @(self.mode), @"owned_assertions": [_assertions copy], @"actual_assertions": actual,
             @"owned_checks": ownedChecks,
             @"query_result": @(code), @"matches": @(matches),
             @"uptime_seconds": @(NSProcessInfo.processInfo.systemUptime)};
}
- (NSError *)errorWithCode:(IOReturn)code operation:(NSString *)operation {
    return [NSError errorWithDomain:@"MiniLaunch.SleepController" code:code userInfo:@{
        NSLocalizedDescriptionKey: [NSString stringWithFormat:@"잠자기 방지 요청을 %@하지 못했습니다. (IOKit: %d)", operation, code]
    }];
}
- (void)dealloc {
    for (NSNumber *value in _assertions.allValues) IOPMAssertionRelease(value.unsignedIntValue);
}
@end
