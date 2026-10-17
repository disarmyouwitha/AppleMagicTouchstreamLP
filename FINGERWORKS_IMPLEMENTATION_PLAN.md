# FingerWorks-informed gesture and typing implementation plan

Implementation design for GlassToKey on macOS · 2026-10-16

The useful discovery is a recognition architecture, not a ready-made firmware port: track contacts, maintain tentative typing and chord candidates, resolve their ownership, then execute explicit actions. GlassToKey can adopt these ideas using Apple trackpad data and its existing production replay system. Reproducing TouchStream's exact recognition behavior would require more reverse engineering and physical validation.

This document proposes implementation work; it does not change recognition behavior. It is based on the current `mac_rewrite` checkout, where `mac` is the reference application and `mac_keyboard` / `mac_gesture_pad` are independent experiments.

## 1. Product direction

Improve typing versus gesture discrimination, especially typing vs mouse.

Use the experiments to answer separate questions:

| Track | Question | First useful result |
| --- | --- | --- |
| `mac_keyboard` | Which contacts should become keys, and when should movement cancel a tentative key? | A small, replayable typing-candidate lifecycle with fewer accidental or missed keys. |
| `mac_gesture_pad` | Which contacts form a chord, and when should a chord become a gesture? | Stable chord acquisition that tolerates staggered landing and partial lift. |
| `mac` | How do those decisions coexist with typing, modifiers, native mouse input, and existing settings? | One ownership coordinator integrating independently validated recognizers. |

The keyboard experiment currently uses a fixed 3 mm movement boundary and retains native mouse handling. That is an experimental baseline, not a recovered FingerWorks rule. The gesture experiment has no physical keyboard hit testing. Neither experiment alone establishes that typing and gestures arbitrate correctly together.

Run one app at a time during live testing. The experiments have separate identities/preferences, but simultaneous input processing and output posting would invalidate measurements.

## 2. What the investigation establishes

Evidence labels used below:

- **Firmware:** supported by decoded data and assembly, with REA/Ghidra assistance.
- **Host/SDK:** supported by the original utility, shipped configuration, or SDK; this does not establish every firmware detail.
- **Proposal:** a GlassToKey design choice requiring tests and evaluation.

All firmware addresses are DSP **word addresses**, four bytes per word. They are research anchors, not offsets or structures to copy into Swift.

| Finding | Evidence and limits | Implementation consequence |
| --- | --- | --- |
| Contacts and typing candidates are separate records. | **Firmware:** `0x8013DF` updates contacts; `0xC033CE` records threshold transitions; `0x803B48` creates linked candidates. | Keep a contact alive independently of whether it produces a key. Tentative candidates can be cancelled before output. |
| Typing processing considers more than initial position. | **Firmware:** `0x8039D6` / `0xC041B5` process displacement, threshold-relative metrics, identity, and weights. Exact metrics and weights remain incomplete. | Evaluate motion, time, and available contact features together. Do not claim recovered scoring coefficients. |
| Chord lookup uses finger identity and geometry. | **Firmware + host:** `0x8021AA` tries exact finger patterns, then a fallback based on non-thumb count and thumb presence; `0x8021E1` selects eligible arrangements using geometry from `0xC0395D`. | Count alone should not identify a chord. Support exact patterns when identity is reliable, with explicit generic fallbacks. |
| Selected chords have a lifecycle. | **Firmware:** acquisition/transition paths are partly traced. **SDK:** describes chord latching until hand lift. Full firmware lockout/hysteresis remains unresolved. | Implement and test a stable cohort lifecycle; label its timing and release policy as a proposal. |
| Actions are configured separately from recognition. | **Firmware + host:** `0x88` upload converts action records; `0xC036D4` expands/schedules actions. | A recognizer emits semantic decisions. Existing action configuration decides their effects. |
| Output has explicit keyboard/mouse state and queuing. | **Firmware:** `0xC03596`, `0x80145C`, `0x801F86`, `0x801F3C`. | Track held outputs and cleanup centrally. Reuse GlassToKey's dispatcher and virtual scheduler. |
| SDK contact paths have stable IDs distinct from anatomical classification. | **Host/SDK:** `FWHID_Contact.c`. Reports describe interpreted contacts, not sensor pixels. | Track by physical contact lifetime; an identity-label change must not create a new touch. |

The exact typing-to-key assignment, complete typing-versus-gesture priority, palm classifier, language model, filter coefficients, and pointer acceleration are **not recovered**. The experimental C output is not validated original source. The C3x model has unsupported instructions; successful decompilation does not close these gaps.

### Evidence to read alongside this plan

The preservation archive is outside this app repository. These links point to the local investigation:

- [Findings and uncertainty boundaries](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/FINDINGS.md)
- [Typing-candidate assembly evidence](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/evidence/assembly-typing-candidates.md)
- [Chord selection and host corroboration](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/evidence/assembly-chord-candidates.md)
- [Configuration and action interpretation](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/evidence/assembly-upstream.md)
- [Typed descriptor and runtime evidence](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/evidence/typed-runtime-evidence.json)
- [REA validation limits](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/evidence/validation-summary.json)

Analyzed firmware: `touchstream.U.byt`, vendor version `0x0160`, SHA-256 `87262a818209a1e019990f1e40f1b55d9d2dd030644d0f5aa0ed7e8cf09476e1`.

## 3. Fit the existing macOS architecture

Keep the existing ingestion and serial execution boundary:

```text
OMSManager → InputRuntimeService → RuntimeCore / TouchProcessorEngine
                                             ↓
                           contact lifecycle and feature extraction
                                  ↙                     ↘
                         typing candidates          chord candidates
                                  ↘                     ↙
                                ownership / commit coordinator
                                             ↓
                           semantic actions → DispatchService
                                             ↓
                                    KeyEventDispatcher
```

The middle recognition boundaries are proposed extractions. Do not add concurrent recognizers that independently post OS events. One serial owner must observe candidates, decide ownership, and order output.

The reference engine already has `TouchEngineScheduler`, live/virtual implementations, and production-engine replay. Extend those facilities. The older architecture review describes gaps that have since been addressed; do not recreate a second replay engine or assume repeat scheduling still needs its first virtualization.

### Implementation map

Paths below are relative to the `mac` directory; experiment copies use corresponding paths.

| Existing location | Responsibility in this work |
| --- | --- |
| `Sources/OpenMultitouchSupport/OMSTouchData.swift` | Preserve raw telemetry and explicit absence. Document device-specific field interpretation. |
| `GlassToKey/GlassToKey/Runtime/RuntimeContracts.swift` | Versioned candidate diagnostics, feature availability, and output provenance. |
| `GlassToKey/GlassToKey/Engine/TouchProcessorEngine.swift` | Integrate contact lifecycle, candidate transitions, and ownership behind a captured feature setting. |
| `GlassToKey/GlassToKey/Engine/EngineActorBoundary.swift` | Serial ownership, configuration application, replay session, and recording sink. |
| `GlassToKey/GlassToKey/ContentViewModel.swift` | Shared action catalog and profile persistence; expose tuning only after experiments identify meaningful controls. |
| `GlassToKey/GlassToKey/KeyEventDispatcher.swift` | Single native output path, held-output bookkeeping, cancellation and cleanup. |
| `GlassToKey/GlassToKey/GlassToKeyApp.swift` | Permission-sensitive native mouse suppression policy, if the pointer experiment proceeds. |
| `GlassToKey/GlassToKey/Render/TrackpadSurfaceView.swift` | Existing contact paths plus optional candidate/ownership overlays. |
| `Sources/ReplayFixtureKit/`, `Tests/ProductionEngineTests/` | Captured configuration, deterministic schedules, state-transition tests, expected transcripts. |

Suggested small new files are `ContactLifecycle.swift`, `TypingCandidateRecognizer.swift`, `ChordRecognizer.swift`, and `RecognitionCoordinator.swift` under `Engine/`. These are proposed names, not existing APIs. Add app files to the Xcode project and package source list where required. Extract incrementally from the reference engine rather than replacing its entire frame loop.

## 4. Contact identity and features

Introduce a contact key containing device identity, runtime session epoch, raw path ID, and a lifetime generation. Increment the generation when a path ID is reused after terminal release; increment the epoch on replay seek, reset, or device reconnection. Device index alone is not a durable identity.

Keep anatomical identity as a separate estimate: finger kind, source, confidence, and last change. The user-observed Apple mapping is thumb=1, index=2, middle=3, ring=4, pinky=5, palm=6. Use it initially as a device-specific hypothesis to validate against labeled captures. The wrapper currently marks raw identity codes and absolute-coordinate units as unverified. Unknown identity must remain representable.

FingerWorks' internal mask is a different encoding: thumb `0x02`, index `0x04`, middle `0x08`, ring `0x10`, pinky `0x20`. SDK exported chord encodings differ again. Convert explicitly if needed; do not compare these numbers directly with Apple `fingerID`. SDK palm classifications also have more categories than a single Apple palm code. Trackpad left/right routing is not proof of anatomical hand identity.

Each contact observation should include:

- Logical timestamp, source sequence, contact key, and explicit lifecycle state.
- Position in normalized pad coordinates plus physical millimeters when device dimensions are known; orientation is part of the transform.
- Displacement from acquisition, filtered velocity, age, and feature-validity flags.
- Optional pressure/contact-strength, area, orientation, and identity estimates with their provenance.

Do not silently substitute zero for missing pressure or identity. Do not assume FingerWorks proximity units, Apple pressure, or raw absolute coordinates are interchangeable. Use pad dimensions and normalized coordinates until absolute units are verified.

An explicit terminal event releases ownership promptly. Missing observations use a bounded, configurable timeout driven by the scheduler, including when no further callback arrives. Distinguish an omitted contact from a lost frame or disconnected device. Never import the SDK's two-absent-frame host buffering as a universal firmware debounce rule.

## 5. Typing candidates and dynamic key geometry

Use the conceptual lifecycle `observed → tentative → committed → finished`, with a separate `cancelled` terminal outcome. A contact need not ever create a typing candidate. A tentative candidate has not posted a key and can still lose ownership to a gesture or mouse decision.

At candidate creation, retain acquisition time/position, contact key, relevant feature summaries, candidate bindings, and a geometry/configuration revision. Update peak/threshold evidence and displacement without overwriting the acquisition anchors.

The first implementation should retain existing key targeting and output timing in a compatibility policy. Run the new candidate evaluator in shadow mode. Only then trial a new commit policy, with these explicit rules:

1. A completed tap can commit on release if it has a valid target, passes the selected typing policy, and its contact remains unclaimed.
2. A hold, modifier, or repeat-capable binding uses its own explicit activation rule. Once activated, it owns the contact until release/cancellation; a later gesture cannot retract its already posted output.
3. Movement can cancel a tentative candidate. It cannot erase an emitted character. Do not try to compensate by sending Backspace: focus or application state may have changed.
4. Several simultaneous candidates are allowed. Ordinary typing rollover is not automatically a chord, and a configured modifier on one pad must still combine with typing on the other.
5. A cancelled contact cannot generate a key during its later release path. A new generation after a real lift may type again.

Proposal for feature evaluation: combine target fit, displacement, velocity, age, and calibrated contact-strength evidence. Begin with interpretable gates and logged rejection reasons; add weighted scores only when labeled evaluation shows a benefit. The recovered firmware does not provide trustworthy weights for Apple hardware.

Treat contact acquisition and key activation as different thresholds, with hysteresis where a usable strength metric exists. FingerWorks host defaults such as `0.22` touch and `0.25` keypress thresholds are documentation, not Apple tuning values. The same applies to its four-frame FIR setting and 400 ms tap/typematic defaults. Avoid mandatory smoothing or a fixed multi-frame wait on every keystroke.

### Dynamic keys

Take one immutable geometry snapshot per revision. Cache hit-test structures when geometry changes, rather than rebuilding them per contact per frame. Measure current allocations before replacing `TouchTable` or caches.

Latch the binding and geometry revision used by a candidate, so a reflow cannot move its target while the finger is down. For explicit layout/layer replacement, cancel tentative candidates under the old revision. Release active outputs through their original bindings; future contacts use the new revision. A deliberately held modifier/layer action follows its configured semantics rather than a layout-edit reset.

If spatial calibration is later added, retain a small ranked key candidate set instead of immediately discarding ambiguity. Train from prompted intended keys or explicit corrections, not automatically from emitted characters. Spatial learning and language models are separate follow-up work; firmware option flags do not reveal a recovered spelling algorithm.

## 6. Chord acquisition and gesture motion

Use a cohort of contact keys, not just the current contact count. Proposed states are `idle → assembling → committed → releasing → idle`; an abandoned assembly can return to idle without output.

During assembly, allow staggered arrivals within a measured acquisition window. This window is a parameter to evaluate, not a known firmware constant. Maintain exact finger patterns only when identity is sufficiently reliable. Try eligible exact patterns first, then a generic non-thumb-count/thumb-presence group. Unknown thumb status must not be treated as thumb absent; provide an explicit unknown-identity fallback or decline recognition.

For geometry matching, convert to a common physical coordinate system, subtract the cohort centroid, and compare against templates scaled for hand size. Mirror only under an explicit hand/orientation model. A first proposed score is mean squared position residual over observed, confidently associated fingers. Use missing-finger penalties and an ambiguity margin against the next candidate. These normalization and rejection choices are GlassToKey proposals; only the firmware's template-residual principle is recovered.

Commit requires more than the lowest score: eligibility, adequate confidence, and an activation event such as deliberate slide, configured dwell, or a completed tap. An early two-finger subset must not fire an action while a three-finger chord is still assembling. Once a side commits a cohort, latch its semantic chord until that cohort ends; do not silently upgrade it as fingers arrive.

For the first implementation, use one active chord cohort per routed pad side. Extra arrivals after commit are quarantined from typing and do not change the action. Partial lift moves the cohort toward release; it never becomes a smaller fresh chord. All involved contacts must lift before rearming. This intentionally conservative lifecycle is a proposal to test, not a recovered firmware law.

For pointer, scroll, and drag movement, track centroid translation separately from expansion/contraction. Rebase the motion origin when membership changes or tracking resumes so a disappearing finger cannot cause a cursor jump. Evaluate directional hysteresis and noise filtering from captures. Do not assume the original acceleration curve has been recovered.

Shipped FingerWorks profiles offer optional test cases: right-hand two-finger pointing, three-finger drag, four-finger scroll/pan; left-hand pointing/selection/navigation; thumb expansion/contraction zoom. They are configuration examples, not a universal default map. Original Mac pan actions can include pointer movement rather than two-axis scrolling. Inspect each action before reproducing it.

## 7. Ownership and commitment

One coordinator resolves proposals before any output. Track ownership per contact and cohort, with explicit owners for typing, modifier/hold, gesture, pointer, and rejected/palm contacts. Candidate observation is non-exclusive; committed ownership is exclusive. Treat cohorts spanning both pads as a future explicit feature, not an accidental consequence of a global contact count.

Initial integration policy:

- A committed typing/hold contact cannot join a newly committed gesture. Established modifiers can affect other contacts' actions without surrendering their ownership.
- A gesture can commit only from contacts whose tentative typing candidates are still cancellable. Cancel those candidates atomically with claiming the cohort.
- A gesture that has committed retains ownership through partial lift. Its remaining contacts cannot fall through to key-release typing.
- Unresolved ambiguity produces no new irreversible action. Compare missed taps and latency before enabling that policy outside the experiment.

This policy makes the tradeoff visible: early key commitment reduces typing delay but closes the opportunity to recognize a later chord. Do not claim both zero added delay and perfect retrospective classification. Evaluate different acquisition/commit windows with the same labeled sessions.

| Scenario | Required behavior |
| --- | --- |
| Two fingers type different keys with overlap | Two independent typing candidates; count alone does not steal them into a gesture. |
| Three-finger gesture lands one finger at a time | Assemble before activation; avoid an intermediate two-finger action. |
| Gesture loses one finger | Preserve the committed action and finish safely; emit no stray key or smaller gesture. |
| Raw identity changes index → middle mid-path | Keep the same contact lifetime; update evidence without a synthetic lift/down. |
| Held Shift plus opposite-pad tap | Apply Shift and release it exactly once when its owner ends. |
| Device disconnects while dragging | Release the app-owned mouse button, cancel future work, clear ownership. |
| Replay seeks or layout changes | End the old epoch/revision according to policy; no stale callback may activate output afterward. |

## 8. Timed output and the two-finger pointer experiment

Use the existing action catalog and `DispatchService` / `KeyEventDispatcher`. If an action needs explicit begin, slide, end, key-up, mouse-button, or scroll semantics absent from current contracts, extend those contracts and the recording sink together. Do not hide new output behavior in renderer callbacks or direct recognizer `CGEvent` calls.

Scheduled work should carry owner ID, epoch, action sequence, deadline, source frame sequence, and deterministic insertion order. Reuse the engine scheduler; define ordering between deadlines and an input frame at the same timestamp and test it. Cancel future activations when ownership ends, while preserving required releases. Maintain app-owned held-key/button/modifier bookkeeping so two owners sharing a modifier cannot release it prematurely.

Bound output work, measure queue age/depth, and reserve a cleanup path. Clearing an overflowing queue must not discard the only key-up or mouse-up. Reset should release app-owned state, not synthesize releases for unrelated physical input. Test loss/overflow recovery rather than copying the firmware's 64-entry ring capacity.

TouchStream's six ordinary keyboard HID slots and signed 8-bit mouse deltas are transport limits. Do not impose six-key rollover or `[-127, 127]` cursor clamping on macOS software output. Preserve fractional motion accumulation and choose documented app-side pointer/scroll units.

### Two-finger mouse mode is a separate feasibility milestone

The requested idea—suppress one-finger native movement and synthesize motion from two fingers—could help distinguish typing from pointing. It is a product experiment, not a fact established by the recovered firmware.

First determine whether native events can be suppressed narrowly enough for selected trackpads. Receiving raw contacts does not itself stop macOS cursor movement, scrolling, or system gestures. Establish the limitations of event attribution; do not globally swallow another mouse's input under the assumption that every event came from the selected pad.

Build and verify a small end-to-end prototype before adding a supported setting:

1. Report Accessibility/Input Monitoring and event-tap availability separately; define what each feature actually requires.
2. Define which native event classes can be blocked and what continues to be handled by macOS. Do not silently change system preferences.
3. Tag injected events so the blocker bypasses GlassToKey's own output.
4. Prove there is one pointer-motion source and no duplicate native/synthetic scrolling or clicking.
5. Verify two-finger movement, drag acquisition/release, lost contact, permission revocation, event-tap disablement, sleep/wake, and disconnect cleanup.
6. Provide an immediate disable path. If suppression fails, stop synthetic pointer output and return to a documented native-input mode.

Keep recognition experiments usable with native pointer handling while this feasibility work proceeds. Do not advertise complete device-specific suppression before it is demonstrated on the intended hardware.

## 9. Contact traces and diagnostics

Keep the existing contact-path option independent of recognition policy. It is a visualization of observed paths, not proof that a key or gesture was accepted. Display-rate history must never supply the engine's motion evidence: rendering can skip frames.

An optional developer overlay should show stable contact key/generation, raw identity versus interpreted identity, cohort, ownership, candidate state, target, and cancellation reason. Distinguish tentative and committed paths visually. Feed bounded snapshots to the UI; avoid per-frame strings, file writes, or unbounded arrays on the input queue.

Extend capture/replay with versioned configuration sufficient to reproduce decisions: recognizer version and feature setting, geometry revision/snapshot, device dimensions/orientation, calibration, feature availability, and arbitration timing. Extend diagnostics with candidate IDs, transitions, scores/reasons, ownership, and output provenance. Older captures without telemetry must remain readable and explicitly use the reduced-feature policy.

See [production replay](PRODUCTION_REPLAY.md), [telemetry](TOUCH_TELEMETRY.md), and [capture format](ReplayFixtures/FORMAT.md). Record human intent labels separately from emitted output; a transcript cannot label its own mistakes as correct.

## 10. Implementation sequence and exit criteria

| Step | Work | Exit criterion |
| --- | --- | --- |
| 1. Baseline and lifecycle | Measure existing behavior; add generation/epoch handling and candidate diagnostics in shadow mode. Start from each experiment's own baseline. | ID reuse, missing release, disconnect, and seek are deterministic; output remains unchanged in reference compatibility mode. |
| 2. Keyboard experiment | Implement explicit tentative/commit/cancel states, motion features, latched geometry, and feature-validity handling in `mac_keyboard`. | Labeled taps, overlapping typing, movement cancellation, and layer changes have reviewed outcomes. No duplicate or release-after-cancel key. |
| 3. Gesture experiment | Add cohorts, identity-aware lookup, geometry scoring, ambiguity rejection, and partial-lift latching in `mac_gesture_pad`. | Staggered landings and identity changes produce one stable decision; partial lift never retriggers. |
| 4. Reference integration | Extract validated helpers into `mac`; add one ownership coordinator behind a default-off, captured experimental setting. | Existing reference replay parity with setting off; explicit new expected results with it on. Cross-pad modifiers and typing rollover work. |
| 5. Output lifecycle | Extend action semantics only as needed; test scheduler cancellation, shared modifiers, queue recovery, drag cleanup. | Every accepted down has a matching cleanup path, including errors and reset. No stale-epoch activation. |
| 6. Pointer feasibility | Prototype native suppression plus two-finger synthesis independently of typing recognition. | Device scope and limitations demonstrated; no doubled motion; permission loss and disconnect recover safely. |
| 7. Live evaluation | Compare reference and experimental policies using labeled sessions, then expose the proven controls. | Accuracy and latency tradeoffs are measured; defaults change only with supporting evidence and reviewed behavior. |

The first implementation PR should be **contact/candidate diagnostics and lifecycle tests with unchanged reference output**. This gives both experiments comparable evidence before changing arbitration thresholds.

Keep experiments independent while exploring. Once a helper is validated, port the same implementation and tests deliberately; avoid long-term divergent copies of the coordinator. Do not reintroduce removed keyboard or gesture features into the stripped experiments simply to make inherited transcripts match.

## 11. Verification and measurements

Use deterministic unit/replay tests for state transitions and real hardware sessions for input quality and OS delivery. The recording sink verifies intended commands; it cannot prove that macOS delivered a native event or suppressed a system gesture.

Required fixtures include fast alternating taps, overlapping taps, held modifiers across pads, one-finger motion, two/three/four-finger staggered landings, thumb inclusion, unknown/incorrect identity, palm-like contacts, partial lift, contact replacement, ID reuse, missing telemetry, pressure noise, layer/layout edits, pause/resume, disconnect, and reset during repeat/drag. Exercise timer expiry with no subsequent input frame and at equal frame/deadline timestamps.

For each scenario assert candidate transitions, owner, semantic action, down/up balance, order, and source sequence. Snapshot parity alone is insufficient. Add output-queue stress and stale-callback tests if output scheduling changes.

Collect labeled sessions covering multiple speeds, both pads, different hand postures, and intended typing versus gestures. Keep calibration sessions separate from evaluation sessions. Report:

- Wrong, missed, and duplicated keys per intended key; include modifier failures.
- Gesture precision/recall and false activations during typing; do not use one combined accuracy percentage.
- Candidate-to-commit latency and frame-arrival-to-post latency at p50/p95/p99, plus queue depth/age and processing time.
- Cursor drift while typing, unintended clicks, missing mouse-up, and duplicate pointer/scroll output.
- Candidate allocation counts and retained memory under sustained input, with tracing enabled and disabled.

No latency or accuracy improvement has been measured by this investigation. Set numeric acceptance budgets after collecting the reference baseline and documenting timestamp boundaries. At minimum, every deterministic lifecycle fixture must pass, reference behavior must remain unchanged with the feature off, and evaluation must disclose any latency added to gain gesture discrimination.

For implementation changes to the reference app, run from `mac`:

```sh
xcodebuild -project GlassToKey/GlassToKey.xcodeproj -scheme GlassToKey \
  -configuration Debug -destination 'platform=macOS' build
swift test
swift run ReplayHarness --fixture ReplayFixtures/production_typing.atpcap \
  --expected-transcript ReplayFixtures/production_typing.engine.transcript.jsonl
```

Run experiment builds/tests from their own directories and use their intended expectations. The production typing fixture is synthetic; passing it is not a physical typing-accuracy study. Review intentional transcript changes instead of regenerating baselines until they pass. Bridge changes require `./build_framework.sh`; pure recognition work should not need bridge changes unless a required field is unavailable. Signing/notarization belongs to release validation, after recognition is validated.

## 12. Remaining decisions

Before enabling a replacement policy, choose its commit/acquisition windows from captures, validate Apple's identity/strength fields, and settle the target pointer behavior: native mouse handling or experimentally suppressed/synthetic handling. Define whether chord geometry needs anatomical handedness or only device-local templates.

Further firmware analysis could refine candidate scoring, chord lockout, key assignment, and motion filtering. None of those gaps prevents the first diagnostic/lifecycle work. They do prevent claiming that the resulting Swift recognizer is an exact TouchStream 1.60 implementation.
