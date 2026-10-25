# Bluetooth channel experiment: suspended after hardware test

The [reconnect observer](RECONNECT_TEST.md) is a separate diagnostic.
Do not rerun the earlier channel test. The wrapper now exits
without launching a probe, and the rebuilt binary refuses `--listen` before any
device access. `--inventory` now reads IORegistry properties only.

## Observed result

The right Bluetooth pad (`D0:C0:50:D5:69:55`) returned `0xe00002bc`
(`kIOReturnError`, a generic IOKit error), no channel object, and no listener.
User capture: `/tmp/amt-bluetooth-channel.Yj5NAa`.

The unified log for BluetoothChannelProbe PID 81177 at 21:20:01 local time adds:

- `TCC is approved`.
- `CBInternalErrorDomain Code=24 "L2CAP PSM already connected"` for PSM 0x13.
- A synchronous-open timeout at 21:20:04, mapped to the generic return code.
- Crucially, the earlier private `l2capChannels` accessor constructed proxies for
  PSMs 0x11, 0x13 and 0x01, followed by `CBClassicMsgIdOpenL2CAPChannel` requests
  for all three from this process. Those connection attempts also failed.

This accessor initiates transport operations and is quarantined and returns nil without messaging the device;
a fake-object regression check verifies that behavior. The live open/listen flow
was removed from the executable. The unused fresh-open ABI bridge remains only
as research code exercised with fake objects by the offline tests.

The log shows approved Bluetooth privacy access and a duplicate-PSM condition;
it does not establish that every user-space Bluetooth route is impossible. Because
our enumeration itself initiated requests, it also does not cleanly establish
which connection caused each duplicate failure. We have not received contact
bytes through this transport. There is no evidence here of a missing DriverKit
entitlement causing this particular failure.

## Next research boundary

A useful next experiment must address ownership of the already active Bluetooth
HID transport, rather than repeat a second-channel request. Before offering that
experiment, determine whether any listener can observe the native transport
without constructing new connections or stealing its consumer. A nil delegate
on a local proxy is not evidence that the underlying channel is unowned. Do not
close or replace the native channel based on that assumption.

No further hardware action is needed for this failed test. If native input is
unresponsive, power-cycle the selected pad and let it reconnect. The main app,
custom DriverKit implementation, pairing, entitlements and security settings
were not changed by this diagnostic.

## Offline verification

`./test.sh` checks argument/packet parsing and the Objective-C bridge using fake
objects. `./build.sh` builds both standalone probes; neither is integrated into
the production release. Help and disabled-listen smoke checks need no device.

See [recovered research](RESEARCH_RECOVERY.md) for the earlier HID report boundary
and native-driver evidence. The channel accessor is not a read-only inventory API.
