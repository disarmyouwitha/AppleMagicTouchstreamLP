// Include the implementation to test actuator lifetime with fake CF objects.
// No enumeration, native actuator open, actuation, or capture is permitted.
#import "../../Framework/OpenMultitouchSupportXCF/OpenMTManager.m"

@interface FakeHapticManager : OpenMTManager
@property NSMutableDictionary<NSNumber *, NSNumber *> *opens;
@property NSUInteger closes;
@property NSUInteger pulses;
@property BOOL refusePulse;
@end
@implementation FakeHapticManager
- (void)enumerateDevices { }
- (CFTypeRef)createAndOpenActuatorForDeviceID:(UInt64)deviceID {
    NSNumber *key = @(deviceID);
    self.opens[key] = @([self.opens[key] unsignedIntegerValue] + 1);
    return CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("fake-%llu"), deviceID);
}
- (void)closeCachedActuator:(CFTypeRef)actuator { self.closes++; CFRelease(actuator); }
- (IOReturn)actuateCachedActuator:(CFTypeRef)actuator waveform:(SInt32)waveform
                        unknown1:(UInt32)unknown1 level:(Float32)level unknown3:(Float32)unknown3 {
    NSCAssert(waveform == 6 && level == 0.25f, @"Haptic parameters must stay unchanged");
    self.pulses++;
    return self.refusePulse ? kIOReturnNotOpen : kIOReturnSuccess;
}
@end
#define HAPTIC_CHECK(...) do { if (!(__VA_ARGS__)) { fprintf(stderr,"Haptic cache FAIL line %d: %s\n",__LINE__,#__VA_ARGS__); exit(1); } } while (0)
static BOOL pulse(FakeHapticManager *m, NSString *device) {
    return [m triggerRawHaptic:6 unknown1:0 unknown2:0.25f unknown3:0 deviceID:device];
}
void runHapticCacheTests(void) {
    FakeHapticManager *m = FakeHapticManager.new;
    m.opens = NSMutableDictionary.new;
    HAPTIC_CHECK(pulse(m,@"7") && pulse(m,@"8"));
    HAPTIC_CHECK(pulse(m,@"7") && [m.opens[@7] intValue] == 1);
    [m invalidateHapticDeviceID:@"7"];
    HAPTIC_CHECK(m.closes == 1);
    HAPTIC_CHECK(pulse(m,@"7") && [m.opens[@7] intValue] == 2); // Same-ID reconnect.
    HAPTIC_CHECK(pulse(m,@"8") && [m.opens[@8] intValue] == 1); // Retained pad untouched.
    [m invalidateHapticDeviceID:@"99"];
    HAPTIC_CHECK(m.closes == 1); // Absent cache entry is harmless.
    m.refusePulse = YES;
    NSUInteger before = m.pulses;
    HAPTIC_CHECK(!pulse(m,@"7") && m.pulses == before + 1); // No duplicate retry.
    HAPTIC_CHECK(m.closes == 2);
    m.refusePulse = NO;
    HAPTIC_CHECK(pulse(m,@"7") && [m.opens[@7] intValue] == 3);
    dispatch_apply(100, dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^(size_t index) {
        if (index % 2) [m invalidateHapticDeviceID:@"7"];
        else HAPTIC_CHECK(pulse(m,@"7"));
    });
    HAPTIC_CHECK(pulse(m,@"8") && [m.opens[@8] intValue] == 1);
    [m clearActuatorCache];
    HAPTIC_CHECK(m.actuatorCache.count == 0);
    printf("Native haptic cache recovery checks passed.\n");
}
