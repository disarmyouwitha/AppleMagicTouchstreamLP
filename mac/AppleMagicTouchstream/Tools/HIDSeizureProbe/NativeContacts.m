#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/hid/IOHIDKeys.h>
#include <stdatomic.h>
#include <math.h>
#include <unistd.h>
#include "NativeContacts.h"
#include "../../Framework/OpenMultitouchSupportXCF/OpenMTInternal.h"

static CFArrayRef nativeInventory;
static MTDeviceRef nativeDevice;
static atomic_bool accepting;
static _Atomic(void *) activeDevice;
static atomic_int_fast64_t lastIdentifier, lastX, lastY;
static OSStatus lastStartStatus, lastStopStatus;
static atomic_uint_fast64_t frames, withContacts, lastCount, maxCount;

static NSString *identityString(io_service_t service, CFStringRef key) {
    if (!service) return @"";
    id value = CFBridgingRelease(IORegistryEntrySearchCFProperty(service, kIOServicePlane,
        key, kCFAllocatorDefault, kIORegistryIterateRecursively | kIORegistryIterateParents));
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static void contactFrame(MTDeviceRef device, MTTouch *touches, int count, double timestamp, int frame) {
    (void)timestamp; (void)frame;
    if (!atomic_load(&accepting) || device != atomic_load(&activeDevice)) return;
    if (touches && count > 0 && count <= 20) {
        float x = touches[0].normalizedPosition.position.x, y = touches[0].normalizedPosition.position.y;
        if (isfinite(x) && isfinite(y) && fabsf(x) < 10 && fabsf(y) < 10) {
            atomic_store(&lastIdentifier, touches[0].identifier);
            atomic_store(&lastX, (int64_t)(x * 1000000));
            atomic_store(&lastY, (int64_t)(y * 1000000));
        }
    }
    uint64_t size = count > 0 ? (uint64_t)count : 0;
    atomic_fetch_add(&frames, 1);
    if (size) atomic_fetch_add(&withContacts, 1);
    atomic_store(&lastCount, size);
    uint_fast64_t previous = atomic_load(&maxCount);
    while (size > previous && !atomic_compare_exchange_weak(&maxCount, &previous, size)) {}
}

static int startNative(const char *serial, const char *transport, bool filter) {
    if (nativeInventory || nativeDevice) return 4;
    if (!MTDeviceCreateList || !MTDeviceGetService) return 1;
    NSString *expectedSerial = [NSString stringWithUTF8String:serial];
    NSString *expectedTransport = [NSString stringWithUTF8String:transport];
    if (!expectedSerial.length || !expectedTransport.length) return 2;
    nativeInventory = MTDeviceCreateList();
    if (!nativeInventory) return 2;
    unsigned matches = 0;
    for (CFIndex i = 0; i < CFArrayGetCount(nativeInventory); ++i) {
        MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(nativeInventory, i);
        if (MTDeviceIsBuiltIn && MTDeviceIsBuiltIn(device)) continue;
        io_service_t service = MTDeviceGetService(device); // borrowed
        NSString *actualSerial = identityString(service, CFSTR(kIOHIDSerialNumberKey));
        NSString *actualTransport = identityString(service, CFSTR(kIOHIDTransportKey));
        if ([actualSerial caseInsensitiveCompare:expectedSerial] == NSOrderedSame &&
            [actualTransport isEqualToString:expectedTransport]) {
            nativeDevice = device;
            ++matches;
        }
    }
    if (matches != 1) {
        nativeDevice = NULL;
        CFRelease(nativeInventory); nativeInventory = NULL;
        return matches ? 3 : 2;
    }
    if (filter) {
        int driverType = -1;
        io_service_t service = MTDeviceGetService(nativeDevice);
        id vendor = CFBridgingRelease(IORegistryEntrySearchCFProperty(service, kIOServicePlane,
            CFSTR(kIOHIDVendorIDKey), kCFAllocatorDefault, kIORegistryIterateRecursively | kIORegistryIterateParents));
        id product = CFBridgingRelease(IORegistryEntrySearchCFProperty(service, kIOServicePlane,
            CFSTR(kIOHIDProductIDKey), kCFAllocatorDefault, kIORegistryIterateRecursively | kIORegistryIterateParents));
        if (![vendor isKindOfClass:NSNumber.class] || ![product isKindOfClass:NSNumber.class] ||
            [vendor unsignedIntValue] != 0x4c || [product unsignedIntValue] != 0x324 ||
            MTDeviceGetDriverType(nativeDevice, &driverType) || driverType != 4) {
            ProbeNativeStop(); return 6;
        }
        uint64_t owned = 0;
        if (ProbeNativeFilterClients(&owned) != 0) { ProbeNativeStop(); return 7; }
    }
    atomic_store(&lastIdentifier, -1); atomic_store(&lastX, 0); atomic_store(&lastY, 0);
    atomic_store(&frames, 0); atomic_store(&withContacts, 0);
    atomic_store(&lastCount, 0); atomic_store(&maxCount, 0);
    MTRegisterContactFrameCallback(nativeDevice, contactFrame);
    atomic_store(&activeDevice, nativeDevice);
    atomic_store(&accepting, true);
    // Bit 30 maps driver type 4 to IOServiceOpen type FLTR on the inspected OS.
    OSStatus result = MTDeviceStart(nativeDevice, (MTRunMode)(filter ? 0x40000000u : 0));
    lastStartStatus = result;
    if (result) { ProbeNativeStop(); return 5; }
    return 0;
}

void ProbeNativeStop(void) {
    atomic_store(&accepting, false);
    atomic_store(&activeDevice, NULL);
    if (nativeDevice) {
        lastStopStatus = MTDeviceStop(nativeDevice);
        MTUnregisterContactFrameCallback(nativeDevice, contactFrame);
        nativeDevice = NULL;
    }
    if (nativeInventory) { CFRelease(nativeInventory); nativeInventory = NULL; }
    // Callback counters have static lifetime: late native callbacks cannot
    // reference freed Swift context or capture buffers.
}

ProbeNativeCounts ProbeNativeRead(void) {
    return (ProbeNativeCounts){atomic_load(&frames), atomic_load(&withContacts),
                              atomic_load(&lastCount), atomic_load(&maxCount)};
}

int ProbeNativeStart(const char *serial, const char *transport) { return startNative(serial, transport, false); }
int ProbeNativeStartFilter(const char *serial) { return startNative(serial, "Bluetooth", true); }
int32_t ProbeNativeLastStartStatus(void) { return lastStartStatus; }
int32_t ProbeNativeLastStopStatus(void) { return lastStopStatus; }
ProbeNativePosition ProbeNativeReadPosition(void) {
    return (ProbeNativePosition){atomic_load(&lastIdentifier), atomic_load(&lastX), atomic_load(&lastY)};
}

int ProbeNativeFilterClients(uint64_t *ownedCount) {
    *ownedCount = 0;
    if (!nativeDevice) return -1;
    io_iterator_t iterator = IO_OBJECT_NULL;
    if (IORegistryEntryGetChildIterator(MTDeviceGetService(nativeDevice), kIOServicePlane, &iterator) != KERN_SUCCESS) return -1;
    int count = 0;
    io_service_t child;
    NSString *prefix = [NSString stringWithFormat:@"pid %d,", getpid()];
    while ((child = IOIteratorNext(iterator))) {
        if (IOObjectConformsTo(child, "AppleMultitouchDeviceUserClient")) {
            id value = CFBridgingRelease(IORegistryEntryCreateCFProperty(child, CFSTR("FilterEnabled"), kCFAllocatorDefault, 0));
            if ([value isEqual:@YES]) {
                count++;
                id creator = CFBridgingRelease(IORegistryEntryCreateCFProperty(child, CFSTR("IOUserClientCreator"), kCFAllocatorDefault, 0));
                if ([creator isKindOfClass:NSString.class] && [creator hasPrefix:prefix]) (*ownedCount)++;
            }
        }
        IOObjectRelease(child);
    }
    IOObjectRelease(iterator);
    return count;
}
