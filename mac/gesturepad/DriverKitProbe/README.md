# GesturePad HIDDriverKit receiver prototype

**USB and Bluetooth full-contact delivery succeeded with SIP enabled on2026-10-18.**
Read the [takeover checkpoint](../RewriteValidation/DRIVERKIT_TAKEOVER_CHECKPOINT.md)
first: it records measured results, working architecture, local evidence, activation
pitfalls and remaining integration work. This is a development takeover implementation, not
an integrated or production-ready GesturePad backend.

Current source/host: **v0.6, both exact tested pads**, continuous stream integration.
See [the integration test](INTEGRATION_TEST.md) before activating. v0.4 was the
successful Bluetooth-only baseline with no mode command.
USB v0.3 succeeded previously; its signed app is archived locally (see checkpoint).
The receiver preallocates report buffers before ordinary IOHIDInterface Open,
counts actual-length reports, retains one sample and closes after15s. No automatic
activation/rearm, synthetic output or concurrent application HID seizure.

## Build and sign

```sh
./mac/gesturepad/DriverKitProbe/build.sh
python3 mac/gesturepad/DriverKitProbe/sign.py \
  --driver-profile mac/gesturepad/DriverKitProbe/profiles/driver.provisionprofile \
  --host-profile mac/gesturepad/DriverKitProbe/profiles/host.provisionprofile
```

Output: `build/GesturePadRawHIDProbe.app`. Rebuilding requires signing again.
Signing verifies profile expiry, app identity, capabilities, team and a common
authorized installed certificate. It does not install or activate. Xcode26.3 /
DriverKit25.2 SDK compilation and strict signature verification passed.

## Provisioning setup (completed locally on 2026-10-18)

Local team N9XQZJR4EP has valid Apple Development and Developer ID Application
signing identities. Both explicit identifiers are now registered. Apple-issued development profiles
are saved in ignored profiles/driver.provisionprofile and profiles/host.provisionprofile.
Both include the registered development iMac. Required entitlement Booleans and
a common installed signing certificate were verified, and sign.py signed/verified
both local bundles. Live installation and activation have now succeeded on both transports. Driver profile
expires2027-03-01; host profile expires2027-10-18. Certificates alone do not grant
DriverKit capabilities. The following steps document regeneration.

In Apple Developer Account → Certificates, Identifiers & Profiles:

1. Register explicit macOS identifiers:
   - `ink.ranna.glasstokey.gesturepad.rawhidprobe.driver`
   - `ink.ranna.glasstokey.gesturepad.rawhidprobe`
2. Driver profile must grant BOTH Boolean entitlements:
   - `com.apple.developer.driverkit`
   - `com.apple.developer.driverkit.transport.hid`
3. Host profile must grant `com.apple.developer.system-extension.install`.
4. Download appropriate development profiles for both identifiers, using the same
   team and an installed signing certificate (and registering this Mac if asked).
   If HID transport is unavailable, request the necessary managed capabilities
   from Apple. A local entitlement plist is not a substitute for Apple's grant.
5. Save profiles in the ignored `profiles/` folder, then run:

```sh
python3 mac/gesturepad/DriverKitProbe/sign.py \
  --driver-profile mac/gesturepad/DriverKitProbe/profiles/driver.provisionprofile \
  --host-profile mac/gesturepad/DriverKitProbe/profiles/host.provisionprofile
```

Signing checks profile capability/team/app identity/expiry and common authorized
certificate, then verifies both bundle signatures. It performs no installation.
Profile files/approved signing entitlements/build outputs are ignored by Git.

## Live test and diagnostics

Use [INTEGRATION_TEST.md](INTEGRATION_TEST.md) for the current v0.6 test, launched
from GesturePad with the signed helper installed. Do not follow older standalone
v0.3/v0.4 instructions with this dual-pad build. Takeover remains active until Release Trackpads or lifecycle release.

`trace-delivery.sh` remains an older USB-oriented90s metadata diagnostic; its v0.3
prompts do not describe the v0.6 integration. It does not activate a driver.
Chronological earlier failures and baseline successes are in
[HID_CAPTURE_FINDINGS.md](../RewriteValidation/HID_CAPTURE_FINDINGS.md).
