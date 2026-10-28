#pragma once
#import <Foundation/Foundation.h>
#import <IOBluetooth/IOBluetooth.h>

// Disabled after hardware logs proved the private accessor attempts connections.
// Always returns nil without messaging the device. Kept for regression checks.
NSArray<IOBluetoothL2CAPChannel *> * _Nullable ProbeBluetoothChannels(IOBluetoothDevice * _Nonnull device);
// Calls the installed, undocumented open API with findExisting=NO, PSM0013 only.
// Unrecognized signatures fail before invocation. Never supplies a delegate.
IOReturn ProbeBluetoothOpenFresh(IOBluetoothDevice * _Nonnull device,
    IOBluetoothL2CAPChannel * _Nullable __autoreleasing * _Nonnull channel);
BOOL ProbeBluetoothFreshAPIAvailable(IOBluetoothDevice * _Nonnull device);
