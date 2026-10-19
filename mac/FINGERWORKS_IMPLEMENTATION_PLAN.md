# FingerWorks implementation plan

Current checkout review · 2026-10-18

This is the cross-project status and work order. The detailed recognition and
editable-layout design lives in the [GlassToKey rewrite guide](GlassToKey/GLASSTOKEY_REWRITE_GUIDE.md).
A proposed state machine or recovered firmware routine is not an implemented
TouchStream recognizer. Keep source evidence, implemented behavior and physical
validation separate.

## Project roles and current implementation

| Project | Implemented now | Still to build or validate |
| --- | --- | --- |
| [gesturepad](gesturepad/) | Raw-contact playground; USB/Bluetooth DriverKit takeover; Compact V7 decoder; contact/pressure/path display; capture/replay; optional synthetic two-finger pointer and physical click output. | Original FingerWorks chord selection/activation and typing arbitration are not implemented. Pointer feel and transport efficiency remain experiments. |
| [AppleMagicTouchstream](AppleMagicTouchstream/) | Keyboard bootstrap with key/modifier/shortcut output, tap/hold, repeat, layers and optional haptics; raw telemetry/capture/replay. GesturePad's takeover/session/decoder boundary is now ported into its keyboard ingestion pipeline. | The port's own USB/Bluetooth, output and lifecycle acceptance checklist remains a hardware test. Original TouchStream chords, gesture logic, English spelling correction and variable-speed typematic remain future work. |
| [GlassToKey](GlassToKey/) | Reference GTK keyboard/gesture engine, OMS ingestion, layout editing, haptics/autocorrect and production recognition replay with virtual deadlines. | DriverKit takeover is not ported here. New FingerWorks candidate/cohort/ownership boundaries and adaptive spatial decoding remain design work. |

The old `mac_keyboard` and `mac_gesture_pad` names are retired. The temporary
AppleMagicTouchstream rule (“key landing = typing; 3 mm travel = mouse”) is a
bootstrap classifier, not recovered FingerWorks logic. Existing hold repeat is
not proof of TouchStream variable-speed typematic fidelity. GesturePad has no
keyboard output. Each project owns its sources, bridge and tests; port validated
boundaries deliberately. Run one owning/output application at a time.

## Pad dimensions and layout scaling

User-provided per-pad dimensions for the hardware comparison:

| Surface | Width × height |
| --- | --- |
| FingerWorks TouchStream, each pad | 16.5 × 12.1 cm (165 × 121 mm) |
| Apple Magic Trackpad | 16.0 × 11.49 cm (160 × 114.9 mm) |

TouchStream is only 5 mm wider and 6.1 mm taller per pad. The surfaces are close
in size, making a slightly scaled TouchStream keymap a useful starting point for
AppleMagicTouchstream experiments. Fitting the full layout by axis would use
approximately 97.0% width and 95.0% height; preserving aspect ratio would use a
uniform scale of approximately 95.0%, leaving some horizontal margin.

These are user-provided comparison dimensions, not verified active sensing bounds.
The original “16.5 mm” width is interpreted as 16.5 cm to match the stated size
comparison. Confirm usable touch extents before calibrating a physical keymap.
Keep physical millimetres and normalized coordinates explicit; similar pad sizes
do not establish identical key placement, contact calibration or gesture thresholds.

## Input ownership: what we have established

GesturePad established raw contact delivery while suppressing Apple's native
input through a DriverKit receiver. Matching covers connected supported Magic
Trackpad2 model **0324** USB/Bluetooth interfaces with arbitrary serials, not every
AMT generation. Takeover captures **all supported connected pads**, including
unselected pads. Left/right selections and manual Sync route app input; zero,
one or two selections are valid. Selected-only native ownership is not provided.

A healthy pad continues streaming when the other disconnects. Reconnect needs
selector verification and manual Sync; do not restore automatic whole-driver
teardown on a single-pad disconnect. Refresh is disabled during ownership and
removal. Release/Exit remove the extension and may require macOS authorization;
after release the user may need manual Refresh. Warm Restart and Config-close
background restart use a signed helper owner-transfer lease. A watchdog and
asynchronous driver cancellation drain preserve cleanup.

AppleMagicTouchstream contains the port of those controls and consumes decoded
contacts through its existing keyboard engine. It does **not** include GesturePad's
synthetic pointer consumer or legacy blackhole experiments. Its [integration
checklist](AppleMagicTouchstream/DriverKitProbe/README.md) remains the acceptance
source; do not transfer GesturePad's hardware pass to this app without testing.
GlassToKey still uses OMS and its existing native-mouse policy. Takeover remains
an optional input/control route for the planned GlassToKey rewrite.

Preserve these boundaries:

- `TrackpadContactDecoder.swift`: packet/scalar/lifecycle reconstruction, independent
  of UI, output posting and installation.
- `TrackpadContactFrame.swift`: typed decoded-frame boundary; app uptime, report
  arrival clock and sensor timing have distinct meanings.
- `DriverKitTakeover.swift` / `DriverSession.swift`: activation, routing, stream
  discontinuities, source gating and signed-owner lease.
- GesturePad's `SyntheticTrackpadOutput.swift`: optional app-owned output. Each
  destination app implements its own pointer/click behavior.
- `DriverKitProbe/takeover-config.json`: per-project owner/deployment manifest;
  shared helper/driver IDs are documented in [bundle identities](BUNDLE_IDENTITIES.md).

No scoped UserClient Access or Allow Any UserClient permission is compiled into
these current takeover builds. Seamless handback while leaving the extension
enabled is not established by the current implementation. Do not reintroduce
per-pad handoff/retake or cursor warping as an incidental prerequisite.

## Telemetry and delivery evidence

The [both-pad parity result](gesturepad/RewriteValidation/TELEMETRY_PARITY_BOTH_PADS_RESULT.json)
compared **2,815 contacts with zero mismatches under the check's tolerances**.
This supports Compact V7 reconstruction against the native contact contract;
it does not establish raw electrode access or reproduce Apple's entire gesture
pipeline. Preserve original report bytes, feature provenance, calibration and
explicitly unavailable fields. Terminal `notTouching` records belong in captures
but are excluded from visible active contacts.

Finger labels use the display convention thumb=1, index=2, middle=3, ring=4,
pinky=5, palm=6. Tracking IDs are separate from anatomy. Captures show anatomical
labels can change without a lift and can disagree with the intended finger; label
persistence is not confidence. The native hand field is not reliable left/right
routing. `P:` is the contact pressure value, not a calibrated force in newtons.
Velocity may be native-quantized/reconstructed; first-frame and gap resets must
remain distinguishable from a measured zero.

Current DriverKit delivery uses a bounded registry ring, published on a 16 ms
driver timer and polled by the app at approximately 16 ms. It is not callback-driven
OMS delivery; similar report counts do not prove equal latency or CPU cost.
The [active notification probe](gesturepad/RewriteValidation/NOTIFICATION_TRANSPORT_RESULT.json)
observed advancing reports without general-interest/property-change notifications.
Registry publication alone is therefore not a wake-up channel.

Efficient-delivery routes remain investigations:

1. Measure and optimize existing-permission discovery, unchanged-data reads and
   active/idle polling without changing manual Sync or independent-pad behavior.
2. Scoped UserClient Access could support authenticated commands and asynchronous
   delivery/shared-memory designs. Approval, implementation and physical handback
   validation are separate gates.
3. A vendor-defined Virtual HID relay could deliver callbacks without our custom
   UserClient. It remains unimplemented; exact permissions, loss behavior, latency
   and app permission requirements need validation. The user reports submitting
   the Virtual HID request; submission is not approval.

See [transport investigation](gesturepad/RewriteValidation/NOTIFICATION_TRANSPORT_ROUTES.md)
for technical evidence; its portal/draft notes are historical. No end-to-end
latency, CPU-efficiency or typing-accuracy improvement is established here.

## Recognition work still ahead

The [rewrite guide](GlassToKey/GLASSTOKEY_REWRITE_GUIDE.md) supersedes the earlier
plan's claims that initial key lookup and pointer acceleration were wholly
unrecovered. Evidence supports initial spatial alternatives plus `noKey`, separate
contact/candidate lifetimes, identity/geometry-based chord selection, stationary
hold activation, configured motion gain/fractional state and timed output.
Complete scoring, language model, anatomical classification, partial-lift/rearm
policy and Apple calibration are still incomplete. Firmware constants are not
Apple tuning values.

Preserve the firmware evidence anchors in the guide and [investigation findings](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/FINDINGS.md).
Analyzed firmware: `touchstream.U.byt`, version `0x0160`, SHA-256
`87262a818209a1e019990f1e40f1b55d9d2dd030644d0f5aa0ed7e8cf09476e1`.
DSP addresses are word addresses, not offsets to copy into Swift.

Build toward this pipeline inside one serial recognition owner:

```text
OMS or DriverKit contacts -> contact lifecycle/features
                         -> tentative typing + chord candidates
                         -> exclusive ownership/commit coordinator
                         -> configured actions + scheduled output cleanup
```

The middle boundaries are proposed extractions, not existing standalone recognizers.
Keep contact identity keyed by device/session/path lifetime; distinguish sample
count from elapsed time and anatomy. Commit ownership atomically with cancellation
of tentative alternatives. Already emitted characters cannot be retroactively
cancelled. Partial lifts must not accidentally rearm smaller chords or type on
release. Use immutable geometry revisions and latched bindings for held contacts.

For movable keys/columns and spatial decoding, preserve stable key IDs separately
from geometry/action labels; publish layout revisions rather than mutate live
recognition geometry during dragging. Start calibration from prompted intended
keys, test on held-out sessions, retain a `noKey` alternative and start in shadow
mode. Do not learn automatically from emitted text or autocorrect substitutions.
These are proposals, not current adaptive behavior or recovered coefficients.

Spatial-model research references:
[Google's Gboard personalization paper](https://research.google/pubs/spatial-model-personalization-in-gboard/)
and [Microsoft's soft-keyboard language-modeling paper](https://www.microsoft.com/en-us/research/publication/language-modeling-for-soft-keyboards/).
They are design references, not measurements of this implementation.

## Remaining architecture work

Current source contains these actionable findings, checked on 2026-10-18:

- **Autocorrect ring publication race (GlassToKey):**
  `AutocorrectEngine.enqueue` increments `writeIndex` before writing `storage[slot]`;
  an already-draining consumer can observe the new index first. Overflow can also
  race slot consumption. This remains a code-level concern, not a reproduced
  failure. Prefer a bounded synchronized queue and process spelling outside its
  lock; fix and stress-test separately from recognizer work.
- **Downstream backpressure is not measured:** `RuntimeCore.ingestLive` schedules
  one serial queue block per frame, while `InputRuntimeService` reports
  `liveQueueDepth: 0`. The upstream buffer limit does not bound that queue. Measure
  depth and age before introducing overflow behavior; never drop release frames
  arbitrarily. Any recovery must release app-owned outputs/reset contact state.
- **Core/UI coupling and spatial ambiguity remain:** the engine aliases
  `ContentViewModel` domain types, and existing targeting is not a learned ranked
  spatial decoder. Extract incrementally, without another parallel engine.

## Next implementation order and acceptance

1. Validate the AppleMagicTouchstream takeover port on USB/Bluetooth, including
   zero/one/two routes, independent disconnect, Sync, keyboard/modifier cleanup,
   warm restart, release shortcut, replay/sleep/Exit and native restoration.
2. Keep the working registry transport as fallback. Measure delivery/processing
   latency, gaps, batches, idle wakeups and CPU before choosing a new transport.
3. Add contact/candidate diagnostics and generation/epoch tests without changing
   reference output. Observe typing and chord hypotheses in shadow mode.
4. Implement original chord/cohort selection and activation in GesturePad, then
   deliberately port validated logic to AppleMagicTouchstream. Exact identity
   patterns require reliable evidence; retain unknown/generic fallbacks.
5. Trial explicit tentative/commit/cancel typing and ownership integration under
   captured configuration. GlassToKey adopts only the useful, validated parts;
   native-input use must remain available independently of takeover.
6. Evaluate editable geometry/spatial decoding separately from intent rejection.
   Measure wrong/missed/duplicate keys, gesture false positives, modifier balance
   and latency percentiles with human intent labels, not emitted transcripts.

Acceptance fixtures need staggered landings, thumb/unknown/palm evidence, partial
lift, ID reuse, missing frames/telemetry, held modifiers across pads, layout/layer
changes, timer expiry without a later frame, reset/disconnect during repeat/drag,
and output down/up balance. Rendering paths are diagnostics, never recognition
input. A recording sink tests intended commands, not actual OS delivery.

From the repository root, use each project's `build.sh` and `test.sh`. For takeover
changes also run that project's `DriverKitProbe/Tests` Python suite. For GlassToKey
production replay, run from `mac/GlassToKey`:

```sh
./test.sh
swift run ReplayHarness --fixture ReplayFixtures/production_typing.atpcap \
  --expected-transcript ReplayFixtures/production_typing.engine.transcript.jsonl
```

Review intentional baseline changes; do not regenerate fixtures merely to pass.
Bridge changes require the project-local framework workflow. Build/signing and
physical ownership checks are separate from recognition accuracy. This document
refresh changes no code, permissions, release artifacts or live hardware state.
