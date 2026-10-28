#import "BluetoothChannels.h"

@interface FakeDevice : NSObject
@property NSUInteger calls;
@property NSUInteger enumerationCalls;
@property BluetoothL2CAPPSM psm;
@property BOOL reused;
- (NSArray *)l2capChannels;
- (IOReturn)openL2CAPChannel:(BluetoothL2CAPPSM)psm findExisting:(BOOL)existing newChannel:(IOBluetoothL2CAPChannel **)channel;
@end
@implementation FakeDevice
- (NSArray *)l2capChannels { self.enumerationCalls++; return @[]; }
- (IOReturn)openL2CAPChannel:(BluetoothL2CAPPSM)psm findExisting:(BOOL)existing newChannel:(IOBluetoothL2CAPChannel **)channel {
    self.calls++; self.psm = psm; self.reused = existing; *channel = nil;
    return kIOReturnSuccess;
}
@end

@interface WrongSignature : NSObject
@property NSUInteger calls;
- (IOReturn)openL2CAPChannel:(uint32_t)psm findExisting:(BOOL)existing newChannel:(IOBluetoothL2CAPChannel **)channel;
@end
@implementation WrongSignature
- (IOReturn)openL2CAPChannel:(uint32_t)psm findExisting:(BOOL)existing newChannel:(IOBluetoothL2CAPChannel **)channel {
    (void)psm; (void)existing; (void)channel; self.calls++; return kIOReturnSuccess;
}
@end

int main(void) { @autoreleasepool {
    unsigned checks = 0;
    #define CHECK(condition) do { if (!(condition)) { fprintf(stderr, "Failed: %s\n", #condition); return 1; } ++checks; } while (0)
    FakeDevice *fake = [FakeDevice new];
    IOBluetoothDevice *device = (IOBluetoothDevice *)(id)fake;
    CHECK(ProbeBluetoothFreshAPIAvailable(device));
    CHECK(ProbeBluetoothChannels(device) == nil && fake.enumerationCalls == 0);
    IOBluetoothL2CAPChannel *channel = nil;
    CHECK(ProbeBluetoothOpenFresh(device, &channel) == kIOReturnSuccess);
    CHECK(fake.calls == 1 && fake.psm == 0x13 && fake.reused == NO && channel == nil);
    WrongSignature *wrong = [WrongSignature new];
    CHECK(!ProbeBluetoothFreshAPIAvailable((IOBluetoothDevice *)(id)wrong));
    CHECK(ProbeBluetoothOpenFresh((IOBluetoothDevice *)(id)wrong, &channel) == kIOReturnUnsupported);
    CHECK(wrong.calls == 0);
    NSObject *missing = [NSObject new];
    CHECK(ProbeBluetoothChannels((IOBluetoothDevice *)(id)missing) == nil);
    CHECK(!ProbeBluetoothFreshAPIAvailable((IOBluetoothDevice *)(id)missing));
    printf("%u Bluetooth bridge checks passed using fake objects only; no Bluetooth calls.\n", checks);
    #undef CHECK
} return 0; }
