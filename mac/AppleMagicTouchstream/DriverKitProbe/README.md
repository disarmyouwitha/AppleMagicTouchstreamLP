# AppleMagicTouchstream trackpad takeover

Ported from GesturePad's v22 capture/session boundary. Decoder arithmetic, USB
0201 / Bluetooth F1 payload 02 01 initialization, timer-published bounded streams,
and asynchronous driver cancellation drain are preserved. No legacy blackhole,
native event filter or GesturePad synthetic pointer consumer is included.

Takeover captures **all connected supported model 0324 USB/Bluetooth pads**,
including unselected pads. Left/right selectors route decoded contacts through
AppleMagicTouchstream's existing keyboard, telemetry, capture and render pipeline.
Zero, one or two selections are valid. Sync explicitly applies selector changes
without cycling the extension. Reconnect/replacement requires manual selector
verification and Sync. Refresh is disabled while activation/ownership/removal is
pending, and is visible even when the device list is empty.

Release Trackpads, the menu command and global Control-Option-R request full
extension removal. Sleep, replay and Exit also release; restoration stays pending
until removal is confirmed. The signed background helper watches its exact owning
app process. Menu Restart transfers ownership through its bounded one-use lease;
Config close uses that same restart in background mode. Keyboard output is reset
before transfer. Replay never consumes live DriverKit frames.

## Build and deployment

`takeover-config.json` is the deployment source. After editing it, run
`python3 DriverKitProbe/generate-config.py` from the project root. SwiftPM discovers
runtime files automatically; the Xcode project registers them and embeds the
helper in `Contents/Helpers/AppleMagicTouchstreamDriverService.app`.

The app owner identity is exactly `ink.ranna.applemagictouchstream`, Apple anchored,
team `N9XQZJR4EP`. The permanent shared helper and driver identities remain
`ink.ranna.trackpadtakeover` and `ink.ranna.trackpadtakeover.driver`; wire names and
helper executable remain compatible. The helper accepts only this destination
app's signed identity. **Simultaneous ownership by GesturePad or another app is
unsupported. Release and quit the other owning app before switching.** No
UserClient entitlement is needed. Existing Apple-issued profiles authorizing the
shared identities can be reused; place them in the ignored `profiles/` directory
as `host.provisionprofile` and `driver.provisionprofile`.

From the AppleMagicTouchstream project root:

```sh
./build_framework.sh
./DriverKitProbe/build.sh
python3 DriverKitProbe/sign.py \
  --driver-profile DriverKitProbe/profiles/driver.provisionprofile \
  --host-profile DriverKitProbe/profiles/host.provisionprofile
./build.sh
./test.sh
python3 -m unittest discover -s DriverKitProbe/Tests -p 'test_*.py'
```

Build the signed helper before the first app build, including direct Xcode builds.
`DriverKitProbe/install-integration.sh` runs helper build/signing and app build,
backs up the installed app and installs only `/Applications/AppleMagicTouchstream.app`.
It refuses installation while a shared receiver is registered. Installation does
not activate takeover. The installed app's Takeover button requests activation;
native macOS approval prompts are expected.

## Physical acceptance (manual, not yet validated in this app)

1. Install, open Config, verify USB/Bluetooth selectors, click Takeover and approve.
2. Confirm both selected pads deliver contacts/telemetry and keyboard output.
   Confirm unselected supported pads remain captured; Sync zero/one/two routes.
3. Verify Refresh remains disabled throughout takeover and removal, including an
   empty selector list. Disconnect one pad; the healthy pad must continue. Verify
   selectors and explicitly Sync after reconnect.
4. Test menu Restart and Config-close background restart: no native release/reclaim,
   correct inventory/routing, and no held keyboard modifiers across transfer.
5. Test Release button, menu and Control-Option-R from another app. Verify removal
   completes and native input returns. Repeat with sleep, replay and actual Exit.
6. Test owner-process loss separately; helper must remove the extension after any
   bounded restart lease expires. A status message alone is not proof of native
   hardware restoration.
