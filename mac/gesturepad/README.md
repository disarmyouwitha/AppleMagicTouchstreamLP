# Gesturepad — TouchStream gesture playground

For the firmware-informed rewrite validation session, start with [RewriteValidation/START_HERE.md](RewriteValidation/START_HERE.md). `swift run RewriteProbe` analyzes saved captures offline and does not change the playground's recognition/output behavior.

FingerWorks gesture/chord playground. Device selection, blank raw-touch surfaces, named finger telemetry/contact paths, per-finger `p:` pressure and per-pad interaction peaks, and capture/replay remain. All GTK gesture recognizers, action configuration/dispatch, keyboard layouts, and layout generation are removed. Only the opt-in selected-trackpad two-finger pointer experiment generates mouse movement; no keyboard, click, voice or haptic actions are generated. Add new FingerWorks logic at `TouchProcessorEngine.processContacts`, shared by live and replay input. Legacy profile commands are compatibility no-ops.

Open `GesturePad/GesturePad.xcodeproj` in Xcode, select the **GesturePad** scheme, and Run. The app is menu-bar based; use **Config...** to select trackpads and test. Run one experiment at a time to avoid both processing the same touches. Each experiment has its own bundle identifier and preferences, separate from the original and from each other. macOS may request Accessibility/Input Monitoring access for each new app.

Build from this directory:

```sh
xcodebuild -project GesturePad/GesturePad.xcodeproj -scheme GesturePad -configuration Debug -destination 'platform=macOS' build
swift test
```

The app product is `GesturePad.app`. The scheme name is `GesturePad`.

Profiles/capture formats retain legacy fields so existing configurations and recordings can still be read. Removed controls do not reactivate removed runtime features when imported. Package tests cover this experiment; inherited fixtures and transcripts are historical references, not parity expectations for the stripped engine.

This is an independent source copy of `../GlassToKey`, without generated build/release output or the SDK reference dump (available in `../sdk`). No source or package dependency points back to the original app. The original project remains unchanged.


## Selected-trackpad control

Under Left Trackpad, **Control selected trackpads** enables continuous control; **30sec test** enables/restarts a timed session and checks the same checkbox. **Release Trackpads**, toggle-off, Command–Escape, and the existing global Control–Option–R/menu action stop control. Config close, selection/refresh changes, sleep, replay and quit also release. This UI no longer seizes HID devices. The raw-HID capture buttons are removed; historical recordings and backend capture schemas remain available for offline investigation.

Control suppresses only ordinary mouse-moved and scroll-wheel events whose nonzero sender ID maps through IORegistry ancestry to a selected trackpad interface. Physical button transitions, native drag events, other pointing devices, and unidentified events pass through. Device identity functions are private APIs resolved at runtime. Missing APIs, unavailable selected services or tap creation failure leave control off. Tap disablement, the timed deadline, or changed device service IDs stop control. Registry work is outside the event callback. Counters show blocked native movement/scroll and unidentified events passed.

Exactly two live contacts on either selected pad enable the experimental synthesized pointer. Contact data continues through the existing Apple touch stream; generated movement carries a tag that bypasses the filter. Pointer synthesis pauses while a mouse button is held so native click-and-drag remains in charge. Native pinch/rotate/system gesture suppression is not implemented. Verify on hardware that contacts remain live, one-finger cursor movement and two-finger native scrolling stop, two-finger synthesized movement works, and mouse/click/drag behavior remains usable.

Use `./build.sh` and `./test.sh` for location-independent builds. `./release.sh --check` validates Release metadata. See [project layout](../README.md).

## Source organization

`GesturePad/GesturePad.xcodeproj`, target and scheme **GesturePad**, produces **GesturePad.app**. The package runtime is **GesturePadRuntime**. The existing bundle ID remains unchanged to preserve settings/permissions.

Keyboard event posting, autocorrect, dictation, key semantic mapping, mobile layout generation, bundled keyboard keymaps, and the old mouse blocker are removed. The menu bar indicates raw-contact monitoring rather than keyboard/mouse modes. There are no microphone or speech permissions.

`GesturePad/GesturePad/Compatibility` contains the legacy data models and portable-profile decoder required by existing captures and offline replay. These types do not enable keyboard layouts, gestures, or output. `Runtime/PassiveOutputBoundary.swift` maintains the capture API without an action-output implementation. Saved settings/screenshots from the original copy are preserved in `LegacyReference` and are not app resources.

## Inline touch workspace

Live contact values flank the paired visualizers: left contacts in the left sidebar, right contacts in the right sidebar. Each sidebar scrolls independently; the workspace scrolls horizontally on narrower displays. Each contact shows its finger name, `p:` pressure, identity/state, normalized position, and available velocity. Expand **Raw measurements** for absolute coordinates, frame/time, axes, total, and density. Per-pad peak pressure and contact paths remain on the visualizers. Contact columns update live, including during replay; use Capture for recorded telemetry. The workspace scrolls vertically when the window cannot fit all contacts; there is no live-values popover.

Inline left/right touch telemetry remains in sidebars flanking the visualizers. Event filtering is scoped through the selected pads’ current registry interfaces.

**Release Trackpads** is directly below Config in the menu. **Control–Option–R** is registered as a global keyboard shortcut and releases the same session even when another app is focused (if the shortcut is available). The Config button and Command–Escape shortcut remain available as well.

## Two-finger pointer experiment

Exactly two live contacts drive midpoint-based relative motion while selected-trackpad control is active. Each pad has an independent contact-ID baseline; contact count/identity changes, stale frames, held buttons, release and runtime stop reset tracking. Known palms are excluded. Accessibility permission is required. Capture/replay remains output-free during replay.

Gain is provisionally 6 screen points/mm on nominal 160 × 114.9 mm geometry; this is not recovered TouchStream acceleration or chord/gating logic. Live suppression and contact delivery still require physical verification.

### Historical raw HID captures

The old `GesturePad.RawHID` version 1 JSON files are unchanged. They store identities, report descriptors, timing, report IDs/results and base64 payloads, with bounded buffers/drop counts. Later files also record Input Monitoring state, ownership mode, callback setup, input-element discovery and raw/value callback counts. The former raw HID buttons are no longer in Config. See [HID_CAPTURE_FINDINGS.md](RewriteValidation/HID_CAPTURE_FINDINGS.md) for the zero-report investigation and the successful pointer identity recordings.

### Pointer source identity test (observation only)

**Test pointer sources (40s)** under Left Trackpad releases any HID session, keeps native input enabled, and starts a listen-only CGEvent tap for pointer motion, button, drag and scroll events. Follow the on-screen phases: 0–10s left pad, 10–20s right pad, 20–30s normal mouse, 30–40s mixed input. The phase labels are user instructions, not inferred source identities. **Stop observer** or **Release Trackpads** ends it early; config close/sleep/replay/quit/selection change also stop it.

Live results are atomically replaced once per second at `/tmp/GesturePad-pointer-identity.json`, so they can be inspected during testing without another Save dialog. Encoding/file I/O run on a separate serial queue. Output includes OS/symbol availability, tap interruptions, selected trackpad identities, bounded aggregates by phase/event type/underlying-HID availability/sender ID, and registry ancestry for nonzero sender IDs. `CGEventCopyIOHIDEvent` and `IOHIDEventGetSenderID` are private symbols resolved at runtime; absent symbols, missing HID events and zero sender IDs remain explicit diagnostic outcomes. No timing-based source guesses, event suppression, synthetic output or HID opens are used by the observer. A nonzero sender ID still requires validation against device identities and mixed-device testing before filtering can be trusted for a new configuration.

### Pointer synthesis and native cursor correction

**Synthetic 2-finger pointer** explicitly enables/disables generated movement independently of native-event filtering. Status reports synthesis ON/OFF and the number of movement events posted; disabling synthesis leaves selected-pad native motion/scroll filtering enabled. **macOS 3-finger drag** is a read-only preference indicator (On/Off/Unknown), matching GTK's behavior, with a System Settings button. Native drag/button events remain allowed.

A hardware test showed identified mouseMoved events were discarded (blocked counter increased) while the visible cursor still moved. A cursor-warp correction was tried and rejected by the user; it has been removed. Current control discards identified movement events but does not claim native cursor suppression. Scroll filtering and synthetic two-finger movement remain. No cursor warping or global mouse/cursor dissociation is used. A replacement must stop pointer movement upstream while preserving contacts and unrelated devices; no such replacement has yet been validated.

### Retired upstream callback test

The upstream callback-access test returned zero callbacks and has been removed from Config and runtime code. Its saved findings remain in RewriteValidation. Test Pointer Sources stays available during control verification; Stop observer and Restore pointer gain appear only while their respective test is active. Historical raw-HID capture backend/schemas remain unchanged and have no Config buttons.

### Timed minimum native pointer gain experiment

**Test minimum pointer gain (15s)** stops other experiments and synthesis, matches HID service ancestry to the current selected pads, and requires an existing numeric `HIDPointerAccelerationMultiplier` on every selected pad. It saves originals before writing fixed-point `1` (the smallest positive value), records immediate and once-per-second delayed readbacks, and restores on any rejected write or after 15 seconds. An accepted write remains under physical test for the full interval even if readbacks retain the original value. **Restore pointer gain** and Release Trackpads/menu/global shortcut restore early; config close, selection/refresh, sleep/replay/quit also restore through the shared release path. Failed restoration keeps original service references and exposes Retry via Restore pointer gain/Release Trackpads. A failed or interrupted process may require restarting the device/session to reset a service property; no preference files are modified.

Zero is deliberately not used: Apple's pointer filter replaces zero multiplier with its default value. This test checks extreme gain reduction, not a claimed exact disable. Only selected services are written; no session/global property setters, cursor correction, HID opens or synthetic events are used. Watch one-finger cursor movement and live contacts on each pad, then compare the normal mouse. Original numeric values, setter results and readbacks are logged at `/tmp/GesturePad-gain-probe.json`. Readback proves a property value only, not a physical effect. The probe has not yet been activated on hardware by automated tooling.

### Single-interface seizure test

The minimum-gain test controls have been replaced by **Single-interface test**. Choose one listed interface from either selected trackpad, then press **Capture one (15s)**. Each entry includes transport, identity suffix, usage page/usage and registry ID. Only that interface is opened with exclusive ownership; keyboards are excluded. Existing pointer control, source observation, gain experiments and synthesis are stopped first. There is no automatic progression or combined-interface seizure.

While touching the tested pad, compare native cursor movement, scrolling/clicking and its contact dots. The OMS counter records live frame/nonempty-frame evidence for both selected touch-device IDs; it is separate from raw HID report delivery. Compare each pad's evidence separately: frames from the other pad do not establish continued contacts on the tested pad. Test the mouse and the other pad as controls. Counts are evidence of callbacks, not proof that native output is suppressed. Interface IDs identify HID services/collections; they may share an underlying device path, so opening one can still affect other routes.

It releases automatically after 15 seconds. **Release interface**, Release Trackpads menu/global shortcut, selection/refresh, config close, sleep/replay and quit release early. Results update automatically at `/tmp/GesturePad-interface-<registryID>.json`, including the exact tested interface, open/close results and per-device contact callback counts. Repeating an interface overwrites that interface's result file. Report observations for each tested interface; no native behavior is inferred from successful opens. No cursor correction, device mode commands or synthetic output are used.

The single-interface test now also records bounded original HID payload bytes (up to 8192 reports / 2 MiB per interface), with capture storage prepared before exclusive open. The schema remains `GesturePad.RawHID` version 1, with `captureMode: exclusive-single-interface`; payloads and report descriptors are base64 and report IDs are stored separately without modifying the payload bytes. On release, encoding/file writes run off the input callback and the capture saves automatically to `/tmp/GesturePad-<transport>-HID-<registryID>-<timestamp>.json`. Status shows report/drop counts and the saved path. The per-interface observation JSON still saves independently. Initial USB sequence: one-finger back-and-forth, two fingers together, two-finger scrolling, then physical click/release. Do not infer PTP from report counts: the prior report ID 2 / eight-byte signature differs from the confirmed Windows report ID 5 / 50-byte stream. No feature reports or device-mode commands are sent.

### Optional USB-C multitouch-mode request

For the exact USB 05AC:0324 mouse interface (usage 0001:0002), the single-interface capture UI offers **Request USB multitouch mode after 2s (02 01)**, default off. When enabled, capture starts before seizure, records a two-second baseline, sends exactly one IOHIDDeviceSetReport feature request (ID 0x02, bytes 02 01), then continues capturing until the same 15-second deadline. The result code, relative command time and prior report count are recorded in the capture's openResults. Recording continues on command failure because an error return alone does not establish whether a mode changed. No retries, other mode bytes, firmware writes, or commands to Bluetooth/other models are used. Capture mode is `exclusive-single-interface-usb-multitouch-request`.

Protocol reference: Linux hid-magicmouse.c, magicmouse_enable_multitouch, explicitly handles USB-C product 0x0324 using 02 01. Its native USB touch reports also use input report ID 2, but expect a twelve-byte prefix plus nine bytes per contact. That is a candidate signature, not a claim the macOS callback will deliver them. Native Apple/Windows report formats and descriptor limits may differ. Release closes exclusive ownership; no reverse mode command is invented. If normal input does not recover after release, unplug/replug the USB pad (or power-cycle if necessary). This option is experimental and has not been sent by automated tooling.
