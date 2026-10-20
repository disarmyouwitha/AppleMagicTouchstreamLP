// Offline lifecycle tests: fake devices and native operations, no hardware opens.
#import "../../Framework/OpenMultitouchSupportXCF/OpenMTManagerV2.m"

@interface TestManager : OpenMTManagerV2
@property NSMutableArray<NSString *> *operations;
@property NSNumber *invalidID;
@property uintptr_t failStart;
@property uintptr_t failStop;
@property BOOL wrongOwner;
@property NSMutableSet<NSNumber *> *filtering;
@end
@implementation TestManager
- (NSArray *)collectAvailableDevices { return @[]; }
- (NSString *)validatedNativeFilterLabelForDeviceID:(NSNumber *)deviceID {
    return [deviceID isEqual:self.invalidID] ? nil : deviceID.stringValue;
}
- (OSStatus)startNativeDevice:(MTDeviceRef)device mode:(MTRunMode)mode {
    uintptr_t number = (uintptr_t)device;
    [self.operations addObject:[NSString stringWithFormat:@"start:%lu:%x", number, mode]];
    if (mode && number == self.failStart) return -99;
    if (mode) [self.filtering addObject:@(number)];
    return 0;
}
- (OSStatus)stopNativeDevice:(MTDeviceRef)device {
    uintptr_t number = (uintptr_t)device;
    [self.operations addObject:[NSString stringWithFormat:@"stop:%lu", number]];
    if (number == self.failStop) return -98;
    [self.filtering removeObject:@(number)];
    return 0;
}
- (int)nativeFilterClients:(MTDeviceRef)device own:(BOOL)own {
    return own && self.wrongOwner ? 0 : [self.filtering containsObject:@((uintptr_t)device)];
}
- (void)stopHandlingRawCallbacks {
    [self endNativeTakeover];
    [self clearActiveDeviceRefs];
}
// Fake retained references must never reach MTDeviceRelease on teardown.
- (void)clearActiveDeviceRefs {
    for (NSValue *value in self.callbackContextsByRef.allValues) free(value.pointerValue);
    [self.callbackContextsByRef removeAllObjects];
    [self.deviceRefsByNumericID removeAllObjects];
}
@end
static TestManager *makeManager(void) {
    TestManager *m = TestManager.new;
    m.operations = NSMutableArray.new;
    m.filtering = NSMutableSet.new;
    for (uintptr_t number = 1; number <= 2; number++) {
        MTDeviceRef ref = (void *)number;
        MTDeviceV2CallbackContext *context = calloc(1, sizeof(*context));
        context->deviceID = number;
        atomic_init(&context->frames, number * 10);
        atomic_init(&context->contactFrames, number * 9);
        m.deviceRefsByNumericID[@(number)] = [NSValue valueWithPointer:ref];
        m.callbackContextsByRef[[NSValue valueWithPointer:ref]] = [NSValue valueWithPointer:context];
    }
    return m;
}
#define CHECK(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); exit(1); } } while (0)
int main(void) { @autoreleasepool {
    TestManager *m = makeManager();
    CHECK(![m beginNativeTakeoverForDeviceIDs:@[]]);
    CHECK(m.operations.count == 0);
    m.invalidID = @2;
    CHECK(![m beginNativeTakeoverForDeviceIDs:@[@1, @2]]);
    CHECK(m.operations.count == 0); // All selections validated before any stop.

    m = makeManager();
    CHECK([m beginNativeTakeoverForDeviceIDs:@[@1, @1, @2]]);
    CHECK(m.filtering.count == 2);
    CHECK(m.operations.count == 4); // Duplicate selector does not start twice.
    CHECK(![m beginNativeTakeoverForDeviceIDs:@[@1]]);
    CHECK(m.operations.count == 4);
    CHECK(![m setActiveDevices:@[]]);
    [m refreshAvailableDevices];
    CHECK(m.filtering.count == 2 && m.operations.count == 4);
    MTDeviceV2CallbackContext *first = m.callbackContextsByRef[[NSValue valueWithPointer:(void *)1]].pointerValue;
    MTDeviceV2CallbackContext *second = m.callbackContextsByRef[[NSValue valueWithPointer:(void *)2]].pointerValue;
    atomic_store(&first->frames, 7); atomic_store(&second->frames, 13);
    CHECK([[m nativeTakeoverStatus][@"frames"] unsignedLongLongValue] == 20);
    [m endNativeTakeover];
    CHECK([[m nativeTakeoverStatus][@"frames"] unsignedLongLongValue] == 20);
    CHECK(m.filtering.count == 0);
    CHECK(![[m nativeTakeoverStatus][@"active"] boolValue]);
    CHECK([m.operations containsObject:@"start:1:0"]);
    CHECK([m.operations containsObject:@"start:2:0"]);
    NSUInteger count = m.operations.count;
    [m endNativeTakeover];
    CHECK(m.operations.count == count); // Idempotent release.
    CHECK([m beginNativeTakeoverForDeviceIDs:@[@2]]); // Reuse after release.
    [m endNativeTakeover];

    m = makeManager(); m.failStart = 2;
    CHECK(![m beginNativeTakeoverForDeviceIDs:@[@1, @2]]);
    CHECK(m.filtering.count == 0);
    CHECK([m.operations containsObject:@"start:1:0"]);
    CHECK([m.operations containsObject:@"start:2:0"]); // Restore failed-start pad too.

    m = makeManager(); m.failStop = 2;
    CHECK(![m beginNativeTakeoverForDeviceIDs:@[@1, @2]]);
    CHECK(m.filtering.count == 0);
    CHECK([m.operations containsObject:@"start:1:0"]);
    CHECK(![m.operations containsObject:@"start:2:40000000"]);

    m = makeManager(); m.wrongOwner = YES;
    CHECK(![m beginNativeTakeoverForDeviceIDs:@[@1]]);
    CHECK(m.filtering.count == 0);
    CHECK([m.operations containsObject:@"start:1:0"]);

    m = makeManager();
    CHECK([m beginNativeTakeoverForDeviceIDs:@[@1, @2]]);
    m.failStop = 1;
    [m endNativeTakeover];
    CHECK(m.filtering.count == 1 && [m.filtering containsObject:@1]);
    CHECK([m.operations containsObject:@"start:2:0"]); // One failure cannot skip another pad.
    CHECK([[m nativeTakeoverStatus][@"active"] boolValue]);
    m.failStop = 0;
    [m endNativeTakeover];
    CHECK(m.filtering.count == 0);
    CHECK(![[m nativeTakeoverStatus][@"active"] boolValue]);
    puts("Native takeover offline lifecycle checks passed.");
} return 0; }
