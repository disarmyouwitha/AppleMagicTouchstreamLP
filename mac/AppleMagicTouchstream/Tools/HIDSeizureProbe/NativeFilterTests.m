#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import "../../Framework/OpenMultitouchSupportXCF/OpenMTInternal.h"
#import "NativeContacts.h"
#include <unistd.h>

static bool fakeOpen, foreignFilter;
static uint32_t openedMode;
static unsigned starts, stops, cursor;
static int driverType = 4, productID = 0x324;
static OSStatus startStatus;
static MTFrameCallbackFunction registered;
static MTDeviceRef fixture(void) { return (__bridge void *)@"fixture"; }
CFArrayRef MTDeviceCreateList(void) { return CFBridgingRetain(@[@"fixture"]); }
io_service_t MTDeviceGetService(MTDeviceRef device) { (void)device; return 1; }
bool MTDeviceIsBuiltIn(MTDeviceRef device) { (void)device; return false; }
OSStatus MTDeviceGetDriverType(MTDeviceRef device, int *value) { (void)device; *value = driverType; return 0; }
void MTRegisterContactFrameCallback(MTDeviceRef device, MTFrameCallbackFunction callback) { (void)device; registered = callback; }
void MTUnregisterContactFrameCallback(MTDeviceRef device, MTFrameCallbackFunction callback) { (void)device; (void)callback; registered = NULL; }
OSStatus MTDeviceStart(MTDeviceRef device, MTRunMode mode) { (void)device; starts++; openedMode = mode; fakeOpen = startStatus == 0; return startStatus; }
OSStatus MTDeviceStop(MTDeviceRef device) { (void)device; stops++; fakeOpen = false; return 0; }

CFTypeRef FakeSearch(io_registry_entry_t entry, const io_name_t plane, CFStringRef key, CFAllocatorRef allocator, IOOptionBits options) {
    (void)entry; (void)plane; (void)allocator; (void)options;
    if (CFEqual(key, CFSTR("SerialNumber"))) return CFRetain(CFSTR("D0:C0:50:D5:69:55"));
    if (CFEqual(key, CFSTR("VendorID"))) return CFBridgingRetain(@(0x4c));
    if (CFEqual(key, CFSTR("ProductID"))) return CFBridgingRetain(@(productID));
    if (CFEqual(key, CFSTR("Transport"))) return CFRetain(CFSTR("Bluetooth"));
    return NULL;
}
kern_return_t FakeChildren(io_registry_entry_t entry, const io_name_t plane, io_iterator_t *iterator) {
    (void)entry; (void)plane; cursor = 0; *iterator = 10; return KERN_SUCCESS;
}
io_object_t FakeNext(io_iterator_t iterator) {
    (void)iterator;
    if (cursor++ == 0 && fakeOpen) return 20;
    if (foreignFilter && cursor <= 2) { cursor = 3; return 21; }
    return 0;
}
boolean_t FakeConforms(io_object_t object, const io_name_t name) { (void)object; (void)name; return true; }
kern_return_t FakeRelease(io_object_t object) { (void)object; return KERN_SUCCESS; }
CFTypeRef FakeProperty(io_registry_entry_t entry, CFStringRef key, CFAllocatorRef allocator, IOOptionBits options) {
    (void)allocator; (void)options;
    if (CFEqual(key, CFSTR("FilterEnabled"))) {
        return (entry == 21 || (fakeOpen && openedMode == 0x40000000u)) ? CFRetain(kCFBooleanTrue) : NULL;
    }
    if (CFEqual(key, CFSTR("IOUserClientCreator"))) {
        return CFBridgingRetain([NSString stringWithFormat:@"pid %d, fixture", entry == 20 ? getpid() : getpid() + 1]);
    }
    return NULL;
}
int main(void) { @autoreleasepool {
    unsigned checks = 0;
    #define CHECK(value) do { if (!(value)) { fprintf(stderr, "Failed: %s\n", #value); return 1; } checks++; } while (0)
    CHECK(ProbeNativeStart("D0:C0:50:D5:69:55", "Bluetooth") == 0 && openedMode == 0);
    MTTouch touch = {0}; touch.identifier = 7; touch.normalizedPosition.position.x = 0.25; touch.normalizedPosition.position.y = 0.5;
    registered(fixture(), &touch, 1, 0, 1);
    CHECK(ProbeNativeRead().withContacts == 1 && ProbeNativeReadPosition().identifier == 7);
    CHECK(ProbeNativeReadPosition().xMillionths == 250000 && ProbeNativeReadPosition().yMillionths == 500000);
    MTFrameCallbackFunction late = registered;
    ProbeNativeStop(); late(fixture(), &touch, 1, 0, 2);
    CHECK(ProbeNativeRead().frames == 1 && !fakeOpen && !registered);
    CHECK(ProbeNativeStartFilter("D0:C0:50:D5:69:55") == 0 && openedMode == 0x40000000u);
    uint64_t owned = 0;
    CHECK(ProbeNativeFilterClients(&owned) == 1 && owned == 1);
    ProbeNativeStop();
    CHECK(!fakeOpen && !registered);
    unsigned previous = starts;
    foreignFilter = true;
    CHECK(ProbeNativeStartFilter("D0:C0:50:D5:69:55") == 7 && starts == previous);
    foreignFilter = false; driverType = 1;
    CHECK(ProbeNativeStartFilter("D0:C0:50:D5:69:55") == 6 && starts == previous);
    driverType = 4; productID = 0x325;
    CHECK(ProbeNativeStartFilter("D0:C0:50:D5:69:55") == 6 && starts == previous);
    productID = 0x324; startStatus = kIOReturnNotPrivileged;
    CHECK(ProbeNativeStartFilter("D0:C0:50:D5:69:55") == 5 && !fakeOpen && !registered);
    CHECK(ProbeNativeLastStartStatus() == kIOReturnNotPrivileged);
    startStatus = 0;
    CHECK(ProbeNativeStartFilter("WRONG") != 0);
    printf("%u native-filter checks passed with fake MT/registry functions; no hardware calls.\n", checks);
    #undef CHECK
} return 0; }
