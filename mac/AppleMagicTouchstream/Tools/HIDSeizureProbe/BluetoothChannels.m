#import "BluetoothChannels.h"
#import <objc/message.h>
#include <string.h>

static BOOL freshSignature(IOBluetoothDevice *device) {
    SEL selector = NSSelectorFromString(@"openL2CAPChannel:findExisting:newChannel:");
    if (![device respondsToSelector:selector]) return NO;
    NSMethodSignature *signature = [device methodSignatureForSelector:selector];
    if (signature.numberOfArguments != 5 || signature.methodReturnLength != sizeof(IOReturn)) return NO;
    const char *psm = [signature getArgumentTypeAtIndex:2];
    const char *flag = [signature getArgumentTypeAtIndex:3];
    const char *output = [signature getArgumentTypeAtIndex:4];
    return strcmp(psm, @encode(BluetoothL2CAPPSM)) == 0 &&
        (strcmp(flag, "c") == 0 || strcmp(flag, "B") == 0) && strcmp(output, "^@") == 0;
}

BOOL ProbeBluetoothFreshAPIAvailable(IOBluetoothDevice *device) { return freshSignature(device); }

NSArray<IOBluetoothL2CAPChannel *> *ProbeBluetoothChannels(IOBluetoothDevice *device) {
    // Quarantined: on this host the private accessor constructed proxies that
    // attempted new connections to every returned PSM. It is not inspection.
    (void)device;
    return nil;
}

IOReturn ProbeBluetoothOpenFresh(IOBluetoothDevice *device,
    IOBluetoothL2CAPChannel *__autoreleasing *channel) {
    *channel = nil;
    if (!freshSignature(device)) return kIOReturnUnsupported;
    SEL selector = NSSelectorFromString(@"openL2CAPChannel:findExisting:newChannel:");
    return ((IOReturn (*)(id, SEL, BluetoothL2CAPPSM, BOOL, IOBluetoothL2CAPChannel *__autoreleasing *))objc_msgSend)
        (device, selector, 0x13, NO, channel);
}
