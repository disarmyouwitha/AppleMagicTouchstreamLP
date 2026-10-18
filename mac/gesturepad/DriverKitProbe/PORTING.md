# Takeover porting boundary

GesturePad is the validated playground. This refactor changes source boundaries,
not the hardware protocol, identity, entitlements, matching or takeover lifecycle.
The bundle identity migration is documented in `../../BUNDLE_IDENTITIES.md`.

## Capture and session code

- `Runtime/TrackpadContactDecoder.swift`: Compact V7 packet decoding, native scalar
  and velocity reconstruction, timer-published stream record decoding and cursor.
  No AppKit, installation, event posting or old blackhole experiments.
- `Runtime/TrackpadContactFrame.swift`: decoded frame boundary and optional consumer
  interface. `timestamp` is app uptime for ingestion; `sourceTimestamp` is the
  report's monotonic-raw arrival clock used by the existing pointer baseline.
  The actual trackpad sensor ticks remain in contact telemetry and drive velocity
  reconstruction. Do not confuse the two clocks.
- `Runtime/DriverKitTakeover.swift`: activation/removal, stream routing, calibration,
  source gating, manual Sync, restart transfer, stream discontinuity handling and
  decoded-frame delivery. Construct `DriverKitTakeover()` for contacts only and
  attach `onFrame`. No pointer consumer is constructed by default; this path does
  not need Accessibility for event synthesis.
- `Runtime/DriverSession.swift`: signed-helper owner lease, restart snapshot and
  supplemental native-device metadata. Existing snapshot keys/fields are retained.

Each destination app consumes frames and implements its own keyboard, pointer,
click, gesture and chord logic. No GesturePad pointer policy is required to port
capture. Existing optional output settings remain compatibility plumbing for the
playground and its restart snapshots; apps without that consumer can ignore them.

## GesturePad-only output

`Runtime/SyntheticTrackpadOutput.swift` holds the existing two-contact pointer,
physical-button synthesis and button-merging policy. GesturePad explicitly injects
it at its composition point. It is not referenced by the capture coordinator and
need not be copied to the destination apps. The old experiment file retains its
historical diagnostic backends, but takeover no longer imports pointer code from it.

## Deployment configuration

`DriverKitProbe/takeover-config.json` is the source for current app/helper/driver
identities, exact signing team, version, notification names, helper artifact names,
session argument, restart key and generated-event tag. `generate-config.py` emits
checked-in Swift and C++ bindings; both build scripts refresh them only on change.
Direct Xcode builds use those checked-in bindings. After changing the manifest,
run the generator before building directly from Xcode; `--check` and driver tests
reject stale bindings.

The helper, packaging and signing tools consume the same manifest. Caller checking
still requires the exact app bundle ID, Apple signing anchor and team. Do not
replace it with a wildcard or accept an arbitrary client-supplied identity. No
UserClient entitlement has been added. Wire/session names remain compatible. Profiles must authorize the permanent bundle IDs.

When choosing destination identities, deliberately configure each app/helper,
provisioning profiles, embedding path/build target, installer destination and
owner validation. Xcode's existing explicit helper embed reference and the app's
project.env remain project-specific. The permanent shared helper/driver IDs are settled in the manifest. Simultaneous
use by multiple apps remains unimplemented. Preserve the single-owner watchdog/lease semantics.

## Preserved behavior and verification

- All matching supported0324 pads are captured together. Selectors route app input.
- Sync stays manual and never cycles the extension. A healthy pad remains streaming
  while the other disconnects. No per-pad native handoff/retake was restored.
- Refresh stays manual, disabled during ownership/removal, and visible when empty.
- Config-close restarts in the background; menu Restart transfers the live session.
  Real Exit/Release restores all pads through normal system-extension removal.
- Decoder/telemetry math, pointer implementation and driver Stop body were compared
  with the pre-refactor sources and are identical except the event tag now comes
  from the manifest. Bluetooth/USB initialization bytes remain unchanged.
-81 Swift tests and11 driver/signing/configuration tests passed. Configuration tests
  check generated bindings, packaged versions/identities and the exact owner ID.
  Physical takeover/Sync/Restart/release must still be checked on the installed build.
