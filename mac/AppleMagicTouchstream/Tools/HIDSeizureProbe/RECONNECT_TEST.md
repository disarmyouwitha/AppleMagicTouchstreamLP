# Observe Bluetooth HID channels across reconnect

Prepared and hardware-tested 2026-10-19. This follows the failed second-channel request; it does not
repeat it. The earlier private channel enumeration remains disabled.

## Question

Does Apple's public notification mechanism expose the selected pad's HID channel
objects when it reconnects, including direction and channel IDs? If so, there is
an actual notification-delivered object to investigate before considering a
bounded ownership/data-listener experiment. Notification delivery itself grants
neither exclusive ownership nor access to contact bytes. No delivery also does
not prove that all lower-level access is impossible.

Turning the pad off removes its current connections, but does not unregister
macOS's HID service. A first-come takeover race is a hypothesis, not an established
property of this API. Apple's documentation describes notifications of opened
channels, not a pre-connection veto or priority reservation.

## Hardware procedure

1. Release DriverKit takeover and quit AppleMagicTouchstream. Keep
   an independent mouse and keyboard available. Switch the right pad OFF.
2. From the repository root, run this without sudo:

```sh
./mac/AppleMagicTouchstream/Tools/HIDSeizureProbe/run-reconnect-test.sh D0:C0:50:D5:69:55
```

3. When `WATCHING` appears, turn the right pad ON. Allow Bluetooth privacy access
   if macOS asks; if the prompt consumes the observation window, report that.
   Move several fingers after it reconnects and observe native pointer behavior.
4. Wait for the 30-second summary, or press Ctrl-C. Send the entire output and
   say whether the native pointer worked. The wrapper saves a new private session
   log under `/tmp/amt-bluetooth-reconnect.XXXXXX`.

If the pad fails to recover, stop the probe and power-cycle that pad. This observer
has not yet been exercised against hardware. We do not assume that public API
registration behavior is validated on this host merely because it compiles.

## Implementation boundaries

- Registers public device-connect notifications and public L2CAP channel-open
  notifications for PSM 0x11 and 0x13 in either direction. Filters callback output
  by the exact explicit MAC address. Does not require an existing IORegistry pad,
  since the intended starting condition is powered off.
- Logs only matching connect/channel-open counts, relative time, direction, PSM,
  and local/remote channel IDs. Does not retain callback channel objects.
- Does not enumerate channels, query/create SDP records, open a device/channel,
  install a data delegate, read contacts, write modes, close channels, unpair,
  disconnect devices, or load a driver. Native contacts are not monitored.
- Unregisters notification tokens on normal completion, Ctrl-C/termination, and
  partial registration failure. No production app/release integration.
- Default/help do not register or access Bluetooth. The previous `--listen` mode
  remains refused before device access. `--inventory` remains IORegistry-only.

A `CONNECT` without `CHANNEL_OPEN` distinguishes device notification visibility
from HID-channel visibility. A PSM 0x13 `CHANNEL_OPEN` establishes that the public
API supplies a channel object on this system; further research must determine
whether data access can coexist or whether an owner can be transferred/restored.
Do not infer that a nil local delegate makes a native channel safe to claim.

References:

- [Apple channel-open notifications](https://developer.apple.com/documentation/iobluetooth/iobluetoothl2capchannel/register(forchannelopennotifications:selector:withpsm:direction:))
- [Apple Bluetooth Device Access Guide](https://developer.apple.com/library/archive/documentation/DeviceDrivers/Conceptual/Bluetooth/BT_Develop_BT_Apps/BT_Develop_BT_Apps.html)
- [Previous hardware result](BLUETOOTH_TEST.md)

## Hardware result: 2026-10-19

User capture `/tmp/amt-bluetooth-reconnect.2eArjR/session.log`:

```text
CONNECT t=4.236 address=D0:C0:50:D5:69:55
SUMMARY connectNotifications=1 controlNotifications=0 interruptNotifications=0
```

The watcher registered successfully and Bluetooth privacy access was approved.
No channel callback ran; no channel object or contact bytes were delivered.
Native pointer operation was not stated in the submitted result.

Read-only unified-log inspection of this same run (probe PID 81989) established
this sequence, in local log timestamps:

| Time | Observed daemon event |
| --- | --- |
|21:33:13.542|Incoming connection request from the selected pad for PSM 17 (0x11); HID handler accepts using default connection policy|
|21:33:13.561|Incoming connection request from the same pad for PSM 19 (0x13)|
|21:33:13.574|HID connection status 0; `Creating TrackpadInputDevice`; sending device-connected notification|
|21:33:13.579|Probe's IOBluetooth/CoreBluetooth connection callback is logged|

These channels were established while our channel notifications were registered,
yet they were not exposed through those notifications. Opening a channel from
the device-connect callback would start after native HID acceptance in this
observed sequence. This does not establish that every possible pre-registered
transport owner is impossible; it rules out treating the device-connect callback
as a demonstrated way to beat native ownership.

Do not repeat this test unchanged. No takeover or raw-contact receive path has
been established by the Bluetooth experiments. The next distinct research target
is the native `bluetoothd` TrackpadInputDevice-to-HID bridge: determine whether a
per-device interception/ownership interface exists, and its access requirements,
before preparing another hardware test. Existing IOHID seizure remains known to
stop both native contacts and the app's report callbacks. Do not conflate that
with evidence that a Bluetooth input-data path has been obtained.
