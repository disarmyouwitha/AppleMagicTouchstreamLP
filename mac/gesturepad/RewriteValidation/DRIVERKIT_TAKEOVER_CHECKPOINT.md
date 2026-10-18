# DriverKit takeover checkpoint — 2026-10-18

## What we proved

On the development Intel iMac, macOS 15.7.4 (24G517), **SIP enabled**, a narrowly
matched HIDDriverKit receiver received full contact packets from both selected
Magic Trackpads. Native trackpad output was suppressed during the receiver test
(user observation). This is the viable path for replacing native interpretation
with GesturePad's own touch/gesture interpreter; it does not require cursor warping.

| Test | Right USB, v0.3/build 3 | Left Bluetooth, v0.4/build 4 |
| --- | --- | --- |
| Vendor/product | 05AC:0324 | 004C:0324 |
| Serial | J84HMA00H0B0000501 | D0:C0:50:D4:75:6C |
| Reports | 369 / 9,630 bytes | 884 / 14,588 bytes |
| One-contact packets | 160 × 21 bytes | 540 × 13 bytes |
| Two-contact packets | 209 × 30 bytes | 344 × 22 bytes |
| Malformed / mapping errors | 0 / 0 | 0 / 0 |
| Timed Close result | 0 (success) | 0 (success) |
| Mode command | Feature ID02, bytes0201, once after2s; success | None |
| Packet layout | ID02, 12-byte prefix +9 bytes/contact | ID31, 4-byte prefix +9 bytes/contact |

USB sample: `02000000000000013180ab80ce1b442089881208aa`.
Bluetooth sample: `319c22810582f42332550e0a6b`.
These lengths establish contact-record counts, not anatomical finger identity.

## The working boundary

The standalone prototype is [DriverKitProbe](../DriverKitProbe/README.md).
An IOService matches the selected **IOHIDInterface, usage0001:0002**, with exact
transport/vendor/product/serial checks in both personality and runtime guard.
It seeds four 4096-byte report buffers using AddReportToPool **before** ordinary
Open(this,0,reportAction). ReportAvailable delivers actual-length buffers, which
are returned to the pool. A serial dispatch queue handles reports and the15s timer.
No simultaneous application-level IOHIDDevice seizure is used.

Earlier ordinary application raw HID delivery truncated USB reports to the
8-byte descriptor size. SIP-off DTrace research proved full contact data still
existed underneath, including during seizure. DriverKit now receives that data
with SIP on. The end-user implementation must not depend on DTrace or disabling SIP.

The Linux packet reference is
[hid-magicmouse.c](https://github.com/torvalds/linux/blob/master/drivers/hid/hid-magicmouse.c).
Do not assume USB and Bluetooth headers or initialization commands are identical.
The USB command was present in the successful test; its necessity is **not proven**.
Bluetooth succeeded without any feature/mode write.

## Current code and evidence

Current source and installed standalone host are **v0.4, left Bluetooth only**.
They do not currently contain a dual-device runtime selector. The signed working
USB v0.3 app is archived in ignored
`DriverKitProbe/evidence/build3-success/GesturePadRawHIDProbe-v0.3.app`.

Saved host/state logs:
- `DriverKitProbe/evidence/build3-success/driver.log`
- `DriverKitProbe/evidence/build4-bluetooth-success/driver.log`

Evidence, profiles and build products are ignored local files, so they will not
follow a Git checkout. This checkpoint and the chronological
[HID findings](HID_CAPTURE_FINDINGS.md) preserve the essential observations.
Only the first full packet and aggregate counters were retained by these probes;
these were not full stream recordings. Logs identify ProbeBuild3/4 explicitly.

After the tests, v0.3 and v0.4 were deactivated/uninstalled. The old v0.1 entry was
still awaiting removal on reboot. No new receiver crash report was found after
v0.3's non-null Cancel completion fix; that is limited evidence, not a stress test.

## Activation lessons

Install the signed host in `/Applications`, leave GesturePad control released,
keep an independent mouse connected, then explicitly Activate. The host does not
activate on launch. On macOS15, approve/enable under General → Login Items &
Extensions → Driver Extensions. A pending approval is **not** a running capture.
Repeated Activate clicks do not advance approval or rearm a completed receiver.
The host's older Privacy & Security instruction is stale.

The15s timer closes the interface but does not guarantee Apple's previous handler
rematches. Read results **before** disabling/uninstalling, which removes the registry
counters. Disabling restored native handling in observed tests; reconnect/power
cycle is a fallback, not an established mandatory step. Removal can also make the
Driver Extensions Settings row disappear. Always check systemextensionsctl and
actual driver Start/counters instead of inferring results from UI alone.

## Signing and development environment

Build validated with Xcode26.3 / DriverKit25.2 SDK, driver deployment20.0 and host
macOS13. Team N9XQZJR4EP; host bundle
`ink.ranna.glasstokey.gesturepad.rawhidprobe`, driver adds `.driver`.
Driver entitlements: `com.apple.developer.driverkit` and
`com.apple.developer.driverkit.transport.hid`; host:
`com.apple.developer.system-extension.install`. Apple-issued development profiles
and a common authorized installed signing identity were used. Driver profile
expires2027-03-01; host profile2027-10-18. Development profiles include this iMac;
public distribution entitlement/provisioning/notarization is not established.
Never commit profiles or export private signing keys.

## Next integration work — not yet proven

1. Preserve a reproducible USB/Bluetooth build or runtime target selection, with
   exact selected-device matching and protection for unrelated devices.
2. Add bounded driver-to-host streaming, decode both packet formats, and feed the
   GesturePad visualizer/interpreter. Preserve replay/capture compatibility.
3. Verify simultaneous full contacts and native suppression explicitly for motion,
   scroll, buttons and gestures; existing evidence is reports plus user observation.
4. Add opt-in continuous ownership and two-finger synthetic movement. This probe
   currently emits **no** synthetic events and is not integrated into GesturePad.
5. Exercise manual release, timeout, app/driver crash, sleep, reconnect, Bluetooth
   disconnect, device selection changes, and restoration of Apple's handling.
6. Verify both pads together, additional hardware/OS versions and distribution.

Do not reintroduce cursor correction/warping or broad suppression of other mice.
Do not describe this checkpoint as a finished production takeover implementation.
