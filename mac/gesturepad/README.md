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

A hardware test showed identified mouseMoved events were discarded (blocked counter increased) while the visible cursor still moved. The filter now corrects only positively identified selected-pad ordinary movement back to the last allowed cursor destination, then discards the event. Allowed mouse movement, unidentified movement, native drags and tagged synthetic movement update that destination. No global mouse/cursor dissociation is used. Correction failures stop control. Status calls these movements `corrected`, not proof of visually smooth suppression. Test first with synthesis OFF using the 30-second mode, then turn synthesis ON and test two-finger motion and mixed mouse input; actual cursor behavior/jitter remains a hardware check.
