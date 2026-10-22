# FingerWorks implementation plan

The consolidated reverse-engineering implementation reference is now
[FINDINGS.md](FINDINGS.md), updated2026-10-21. Use it for recovered gesture,
chording, typing arbitration, mouse and ownership behavior, including evidence
limits. This plan tracks project scope and next work; GesturePad's engine document
tracks implemented behavior.

Current implementation and research review · **2026-10-20**.

This is the cross-project status and next-work plan. GesturePad's
[gesture engine rules](gesturepad/GESTURE_ENGINE.md) are the central specification
for implemented gestures, thresholds, arbitration and lifecycle. The
[GlassToKey rewrite guide](GlassToKey/GLASSTOKEY_REWRITE_GUIDE.md) preserves useful
firmware-backed design evidence and proposed typing/spatial architecture; its
older project/status language is not the current implementation inventory.

Keep source evidence, proposed policy, implemented behavior, offline replay and
hardware observations distinct. A feature that feels like TouchStream is useful
progress, not proof that its proprietary algorithm has been reconstructed.

## 1. Project roles and current implementation

| Project | Implemented now | Not yet established or ported |
| --- | --- | --- |
| [GesturePad](gesturepad/) | Selected-pad native FLTR takeover; persistent default-off-until-opt-in takeover checkbox; automatic restoration after opt-in; live contact/pressure/path display and capture/replay; accelerated two-finger mouse, four-finger precise scroll with momentum, and two-finger primary tap click. | Full FingerWorks chord selection, anatomical classification, typing arbitration, keyboard output and complete native-equivalent calibration. Latest tap tuning still needs broader acceptance. |
| [AppleMagicTouchstream](AppleMagicTouchstream/) | Keyboard bootstrap: key/modifier/shortcut output, tap/hold, repeat, layers and optional haptics; native contact telemetry/capture/replay; selected-pad native FLTR takeover controls; TouchStream reference layout. | GesturePad's persistent automatic takeover and new mouse/scroll/momentum/tap engine are **not ported**. Original typing/chord arbitration, English spelling correction/BackSpace Auto-Correct and variable-speed typematic remain fidelity goals. |
| [GlassToKey](GlassToKey/) | Reference GTK keyboard/gesture engine; native OMS ingestion; native FLTR takeover controls; layout editing/TouchStream reference layout; haptics/autocorrect; production recognition replay. | New GesturePad gesture engine and persistent automatic takeover are **not ported**. FingerWorks candidate/cohort ownership and adaptive spatial decoding remain design work. Existing GTK gestures are not evidence of TouchStream fidelity. |

Each project owns its source, bridge, tests and capture formats. Port deliberately
when requested; user direction is to get GesturePad right first. Run one owning/
output application at a time. The old `mac_keyboard` / `mac_gesture_pad` names are
retired. The temporary AppleMagicTouchstream classifier (“key landing = typing;
3 mm travel = mouse”) and existing repeat scaffolding are not original firmware
reconstructions.

## 2. Input ownership: current path, not the old DriverKit plan

The custom DriverKit implementation, helper, raw decoder integration and signing/
provisioning flow were removed from these apps. **Do not restore them as a
prerequisite for current gesture work.** DriverKit permission requests and old
registry polling/notification experiments are historical research, not release
requirements or the current data path.

The working route is the native MultitouchSupport/OMS bridge, using Apple's
undocumented FLTR client to suppress native processing on the **selected**
supported pads while retaining contact delivery. USB and Bluetooth have both
been confirmed on the supported model. Validation remains scoped to external
model0324/type4 and its existing USB/Bluetooth vendor/service checks; do not
claim arbitrary-generation support.

GesturePad now:

- Deduplicates left/right physical IDs, validates transitions and preserves retained
  clients. It does not take every connected supported pad indiscriminately.
- Allows selection and Refresh while takeover is enabled, with pause/reconciliation,
  preflight, rollback and explicit failure status. Selecting None can release a pad.
- Routes frames by native numeric device ID, not reusable bridge index slots.
- Keeps the owner process and clients when Config closes or active Restart rebuilds
  Config. There is no interprocess helper/owner-transfer lease.
- Cancels output and releases for explicit release, quit, sleep and replay through
  existing lifecycle rules. Restored opt-in can reacquire through reconciliation;
  no new background reconnect scanner is implied.
- Uses **Ctrl-Option-R** and the Release Trackpads menu for emergency release,
  persisting takeover off. Quit preserves the preference for the next launch.

AppleMagicTouchstream and GlassToKey have the earlier selected-pad native takeover
port with explicit Takeover/Release controls, selection/refresh locking and no
startup takeover. Do not transfer GesturePad's newer preference/selection policy
or hardware acceptance to those apps without a deliberate port and verification.

Details: [GesturePad takeover](gesturepad/TRACKPAD_TAKEOVER.md),
[AppleMagicTouchstream takeover](AppleMagicTouchstream/TRACKPAD_TAKEOVER.md),
[GlassToKey takeover](GlassToKey/TRACKPAD_TAKEOVER.md).
The native route avoids the removed custom DriverKit entitlement dependency;
it remains an undocumented API dependency and needs OS/lifecycle testing.

## 3. Gesture behavior worth retaining

The user directly compared FingerWorks hardware and established the interaction
rule that **activation and continuation are separate**. Two fingers start mouse;
additional fingers or partial lifts keep it in mouse mode until all-up. The same
session principle is used for four-finger scroll. Counts do not reclassify an
already owned gesture.

| Feature | Current rule / evidence |
| --- | --- |
| Two-finger mouse | Moving two-finger chord, 0.35 mm initiation; any positive count continues. Matched contact-ID displacement prevents landing/lift centroid jumps. Accelerated feel and count latching hardware-confirmed. |
| Four-finger scroll | Moving four-finger chord, 0.20 mm initiation; any positive count continues. Separate per-axis scroll curves/history, natural direction and precise fractional events. User reported good feel. |
| Momentum | Included after scroll lift. Recent accelerated release velocity and analytically integrated exponential decay; new same-pad touch brakes. User reported good feel. Decay is app tuning, not recovered Apple momentum. |
| Two-finger tap | Primary click at all-up, maximum 500 ms with bounded pair/lift skew and individual motion. Movement ownership and momentum braking suppress clicks. Latest 0.35 mm mouse threshold improved reported feel. |

Mouse/scroll/tap controls default on with opted-in takeover and can be disabled
independently. Sensitivities start at 1.00×. Every output remains live-only,
selected-and-owned, successfully armed and Accessibility-gated. Tap requires no
acceleration profile; mouse/scroll require their appropriate readable profiles.

Do not implement a second set of threshold rules in this plan. Use
[GESTURE_ENGINE.md](gesturepad/GESTURE_ENGINE.md), which includes the current
threshold tables, cancellation, defaults and a template for the next recognizer.

### Capture-backed tap tuning

The first rapid move–tap recording reproduced six valid tap candidates losing
to the old 0.20 mm mouse threshold. Raising only mouse initiation to 0.35 mm
changed production replay from **19 to 25 predicted clicks**, with no clicks in
29 clear movement cycles. The second recording predicts **22 clicks and no clicks
in 23 movement cycles**, including ten initial stationary taps and eleven final
no-click strokes. The old threshold would lose five of those taps. Larger tested
thresholds add no benefit.

Keep 0.35 mm. This changes initial distance arbitration, not acceleration, the
latch or a fixed waiting time. The 500 ms tap setting is a maximum, not a delay
before clicking. These recordings contain contact evidence, not actual delivered
click events or per-cycle intent labels; replay predictions plus improved user
feel support the tuning without proving all missed/false clicks are resolved.

[Capture analysis and repeatable regression](gesturepad/RewriteValidation/TWO_FINGER_TAP_CAPTURE_ANALYSIS.md).

## 4. Acceleration and measurement boundaries

Retain the independent Apple-source parametric models and provenance. Pointer and
scroll acceleration are different paths; scroll uses its own curves and history.
Preserve fractional movement, timing units, phase sequences and independent pad/
axis state. Do not replace accepted feel with firmware constants merely because
they exist in a disassembly.

Current contact-to-count conversion uses the explicit **resolution / 25.4 ×
sensitivity** hypothesis and 160 × 114.9 mm surface dimensions. Good hardware feel
is not proof of Apple's unpublished multitouch processing or effective filter
configuration. Momentum constants are provisional app policy, not recovered code.

Useful references:

- [Pointer equations, installed settings and baseline limitations](gesturepad/POINTER_ACCELERATION.md).
- [Mouse/latching implementation](gesturepad/TWO_FINGER_MOUSE.md).
- [Scroll acceleration, fine events and momentum](gesturepad/FOUR_FINGER_SCROLL.md).
- [Tap recognition and click output](gesturepad/TWO_FINGER_TAP.md).

## 5. Pad dimensions and layout scaling

Preserve these user-provided comparison dimensions:

| Surface | Width × height |
| --- | --- |
| FingerWorks TouchStream, each pad | 165 × 121 mm |
| Apple Magic Trackpad | 160 × 114.9 mm |

The surfaces are close in size. Axis-fitting a TouchStream layout gives about
97.0% width and 95.0% height; aspect-preserving fit is about 95.0%, with horizontal
margin. The original “16.5 mm” comparison was interpreted as 16.5 cm. These are
not verified active sensing bounds: confirm touch extents before calibration.
Similar dimensions do not establish matching key placement or gesture thresholds.

The traced TouchStream preset/reference is implemented in both keyboard projects:
[GlassToKey layout](GlassToKey/TOUCHSTREAM_LAYOUT.md) and
[AppleMagicTouchstream layout](AppleMagicTouchstream/TOUCHSTREAM_LAYOUT.md).
Keep stable key IDs, independent left/right geometry, editable overrides and inert
unsupported legends. The background image is a reference, not a recognizer.

## 6. Telemetry findings retained from the earlier work

Historical decoder research remains useful even though it is no longer the live
input implementation. The [both-pad parity result](gesturepad/RewriteValidation/TELEMETRY_PARITY_BOTH_PADS_RESULT.json)
compared 2,815 contacts with zero mismatches under that check's tolerances. It
supports the documented reconstruction, not raw electrode access or the complete
Apple gesture pipeline. Preserve the
[Apple contact HID layout](gesturepad/APPLE_CONTACT_HID_LAYOUT.md), reference
vectors and optional legacy `telemetry.driverKit` serialization for old captures.

Finger display labels (thumb=1, index=2, middle=3, ring=4, pinky=5, palm=6) are
separate from contact tracking IDs. Labels can change without a lift and can
misidentify intended anatomy; persistence is not confidence. Native hand labels
are not physical left/right routing. Pressure is not calibrated force in newtons.
Keep native/reconstructed velocity provenance, quantization and first-frame/gap
resets distinguishable from measured zero. Terminal records belong in captures
but not active-finger counts.

The old 16 ms DriverKit registry ring/polling, failed notification wake-up probe,
UserClient/Virtual HID delivery proposals and helper-transfer experiments remain
historical evidence. Do not optimize or depend on that removed transport as the
next step for the native callback-based implementation.

## 7. Firmware/SDK research worth carrying forward

The [rewrite guide](GlassToKey/GLASSTOKEY_REWRITE_GUIDE.md) and local
[firmware investigation findings](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/FINDINGS.md)
retain the detailed evidence. Analyzed image: `touchstream.U.byt`, version
`0x0160`, SHA-256
`87262a818209a1e019990f1e40f1b55d9d2dd030644d0f5aa0ed7e8cf09476e1`.
DSP addresses are word addresses, not Swift layouts or byte offsets to transplant.
Local SDK/reference material lives under `mac/sdk`, outside the Swift packages.

Retain these architectural lessons without treating proposed extractions as done:

- Contact lifetime, typing candidate, alternative sequence and emitted action are
  separate. A cancelled key hypothesis need not destroy the contact.
- Initial spatial lookup can have ranked alternatives plus `noKey`; ambiguity is
  real. A language model and complete scoring are not already implemented here.
- Sample age, elapsed time and anatomical identity are different quantities.
- Chord selection/identity, stationary or motion activation, configured gain,
  timed output and finish actions have separate boundaries.
- Partial lifts and ownership need an explicit rearm policy. The user's current
  FingerWorks comparison supplies concrete mouse-latching evidence; it does not
  settle every proprietary chord or typing interaction.
- Only commit output once its ownership decision is safe. Already emitted text
  cannot be retroactively cancelled. Held outputs need balanced cleanup even when
  no later input frame arrives.

For future typing integration, use one serial recognition owner:

```text
native contacts -> contact features/lifetimes
                -> tentative typing and gesture candidates
                -> ownership/commit arbitration
                -> actions and explicit output lifetimes
```

The current generic GestureSessionEngine handles per-pad continuous ownership,
activation/continuation and lifecycle; the router registers mouse/scroll and
feeds tap rejection. Discrete tap recognizers remain separate candidates;
it is **not** the full proposed typing/cohort coordinator. Do not restore discarded
GTK recognizers or create another parallel engine as an incidental shortcut.

For spatial learning, preserve stable key identity separately from geometry and
labels; publish immutable geometry revisions and latch bindings for held contacts.
Use prompted intended keys and held-out sessions, retain `noKey`, start in shadow
mode and do not learn automatically from emitted/autocorrected text. The previous
Gboard/Microsoft references are background design pointers in the rewrite guide,
not measurements or dependencies of the current implementation.

## 8. Unresolved engineering findings

Source rechecked 2026-10-20; none of these is fixed or experimentally proved by
this documentation update:

- **GlassToKey autocorrect ring publication:** `AutocorrectEngine.enqueue` advances
  `writeIndex` before writing `storage[slot]`. A consumer already draining can
  observe publication before the value; overflow/consumption also deserves review.
  Preserve as a code-level race concern, not a reproduced user failure. Investigate
  a bounded synchronized queue and stress test separately from gesture tuning.
- **Downstream backpressure:** `RuntimeCore.ingestLive` queues per-frame work while
  ingestion telemetry reports `liveQueueDepth: 0`. The upstream stream limit does
  not measure/bound that serial queue. Measure age/depth before overflow policy;
  never arbitrarily drop release frames or leave app-owned outputs held.
- **Core/UI coupling:** engine domain types still alias `ContentViewModel` types.
  Extract incrementally when needed; a learned spatial decoder is not present.
- **Delivery observability:** contact captures predict recognizer decisions but do
  not establish posted-event timing, OS/application receipt, physical-button
  suppression or human intent. Label intended actions and add measured evidence
  before declaring native-equivalent latency or zero missed/false actions.

Kara's immutable weak-reference capture fix has been applied to all three Mac
`ContentViewModel` initializers, with passing tests/universal builds on installed
Xcode 26.3. Xcode 27 is not installed here; do not call it directly verified.

## 9. Next work and acceptance order

1. Keep the improved tap threshold; use the follow-up capture as a regression.
   Collect actual click/intent evidence if misses remain instead of repeatedly
   loosening thresholds. Include deliberate short no-click mouse strokes.
2. Define each next gesture in the central rules **before** implementation:
   activation, continuation, ownership priority, completion/cancellation, output,
   thresholds, defaults and verification. Preserve accepted mouse/scroll feel.
3. Broaden lifecycle/physical testing: selection while active, None/duplicate pads,
   USB/BT switching, independent pad changes, pause/brake/release, Config/Restart,
   sleep/replay/quit and native input restoration. Confirm closed event phases
   and no stuck outputs rather than relying solely on return codes.
4. Continue evidence-backed chord/cohort and typing-vs-gesture investigation in
   GesturePad, observing candidates before committing irreversible key output.
   Use reliable identity evidence with unknown/generic fallbacks.
5. Port only the reviewed GesturePad behavior to AppleMagicTouchstream and then
   selected GlassToKey improvements when requested. Respect each app's existing
   keyboard/reset and configuration boundaries; no automatic cross-project port.
6. Evaluate spelling correction, variable-speed typematic and adaptive geometry
   separately, using intended-key labels and held-out captures. They remain goals,
   not completed TouchStream fidelity.

Regression cases should include staggered landing/lift, partial lift, added
fingers, thumb/unknown/palm telemetry, contact ID reuse/replacement, missing frames,
button suppression, tap-vs-motion, independent pads, interrupted momentum, layout/
layer changes and future held-output cleanup. Rendering is diagnostic, never the
recognition source. Recorded commands alone do not prove OS delivery.

From the repository root:

```sh
./mac/gesturepad/test.sh
./mac/AppleMagicTouchstream/test.sh
./mac/GlassToKey/test.sh
```

Native takeover checks are included by the project wrappers. The removed
`DriverKitProbe/Tests` suite is **not** a current prerequisite. Optional capture
regressions skip if their local unbundled recording is absent; tests must not post
input or activate takeover. For the existing GlassToKey production transcript:

```sh
cd mac/GlassToKey
swift run ReplayHarness --fixture ReplayFixtures/production_typing.atpcap \
  --expected-transcript ReplayFixtures/production_typing.engine.transcript.jsonl
```

Review intentional baseline changes instead of regenerating to silence failures.
Use project-local bridge rebuilds for native edits; build, signing, physical
ownership and recognition acceptance are separate checks. This refresh changes
documentation only, not code, permissions, installed apps or live hardware state.
