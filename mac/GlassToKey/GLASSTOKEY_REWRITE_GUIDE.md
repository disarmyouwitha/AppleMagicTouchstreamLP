# GlassToKey macOS rewrite guide

Implementation design · 2026-10-17 · based on TouchStream 1.60 assembly, original utility/SDK, and the current `mac_rewrite` checkout.

**Build a contact-to-intent engine with explicit ownership and output lifetimes.** The strongest FingerWorks lesson is that a touch is evidence, not yet a key or gesture. Keep several interpretations while the decision is reversible, commit through one coordinator, and track every held output until release.

The immediate product goal is **typing versus mouse discrimination**. Gesture recognition is a related experiment. This guide does not restore the discarded blanket TouchStream gesture mode. Contact-path visualization remains an independent option.

This is an implementation specification, not an implemented replacement. Firmware facts, host/SDK observations and proposed GlassToKey policy are distinguished below. No physical accuracy or latency improvement has been measured by this investigation.

## 1. What was recovered and what to use

All firmware addresses here are DSP word addresses, four bytes per word. They identify evidence; they are not Swift structure layouts.

| Recovered behavior | Evidence | GlassToKey consequence |
| --- | --- | --- |
| Contact, typing candidate, sequence hypothesis and emitted action are separate objects. | Firmware `8013DF`, `803B48`, `803AD9`, `C0439F`. | A contact can survive cancellation of its typing interpretation. Never equate a raw down with key-down. |
| Initial spatial lookup is followed by alternative keys and a no-key interpretation. | `802E70`, `802ED9`, `803653`, `C04174`; ranked nodes at `803936`. | Keep ambiguity explicit. Allow “no output” to win; adding a language model is optional. |
| Candidate age is separate from finger identity. | Contact `[22]` increments; candidate `[19]` copies it. Startup `C02753` fills reciprocal weights. | Store sample count and anatomical identity in different fields. Sample count must not substitute for elapsed seconds. |
| A held stationary chord and a sliding chord share activation, followed by configured Lift. | `C03B53`, `C03BED`, `C03BC2`, `C01D1E`. | Model tap, dwell, motion and finish separately. Stationary activation must schedule and release correctly without a later motion frame. |
| Activation cancels recent typing through a hand/time-scoped cleanup path. | `C03BC2 → C04823 → C047F6`. | Claim a cohort and cancel its tentative typing atomically. Cleanup releases only owned outputs. |
| Exact finger patterns and geometric templates both contribute to chord selection. | `8021AA`, `8021E1`, `C0395D`; utility serializers. | Count alone is insufficient. Keep confidence and an explicit fallback when thumb identity is unknown. |
| Pointer motion uses configured gain and retained fractional state. | `802864`, `802881`, `C018A8`; host `h.java`. | Preserve small motion deltas and explicit units. Avoid accidental double acceleration with macOS. |
| Recognition feeds configured timed actions and stateful output. | `C036D4`, `C03596`, `80145C`, keyboard/mouse writers. | Reuse the action catalog, scheduler and dispatcher; recognizers do not post OS events. |

The new evidence corrects two earlier interpretations: selector `[9]` means **activated**, including stationary hold, and the bounded candidate `[38]` term participates in the **no-key alternative**, rather than representing confidence that a key is correct.

The exact language model, all commit/replacement branches, adaptive TapArea transformations, anatomical classifier, partial-lift/rearm rules, physical units and complete pointer/scroll filtering remain incomplete. Firmware numbers such as 0.25 pressure-like threshold, 400 ms host timeout, 76 internal age units, or reciprocal sample weights are **research facts, not Apple defaults**. The sensor's 16×82 grid is below Apple's already tracked contact interface.

Read [current findings](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/FINDINGS.md), [reconstruction and address-level evidence](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/reconstruction-2026-10-17/PROGRESS.md), and [remaining uncertainty ledger](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/reconstruction-2026-10-17/coverage-ledger.json). Firmware SHA-256: `87262a818209a1e019990f1e40f1b55d9d2dd030644d0f5aa0ed7e8cf09476e1`.

## 2. Start from the actual three applications

| Directory | Current role | First implementation work |
| --- | --- | --- |
| `mac` | Reference app: current recognition, output, settings and production replay. | Instrument baseline decisions; later integrate validated helpers behind a versioned experimental policy. |
| `mac_keyboard` | Conservative restart from `mac`: original keyboard pipeline, autocorrect, layouts, holds, modifiers, layers and haptics retained. A key landing permits typing; movement beyond 3 mm selects mouse intent until all lift. Existing gesture recognition is behind a default-off toggle. | Explicit candidate states and diagnostics, preserving this restart's intended behavior until deliberately changed. |
| `mac_gesture_pad` | **Raw-contact playground.** No recognizers or keyboard, mouse, voice or haptic dispatch. Named-finger/pressure telemetry, traces and capture/replay remain. | Shadow chord observations at `TouchProcessorEngine.processContacts`; continue producing no actions during recognition evaluation. |

The gesture playground is not an existing gesture engine waiting to be configured. The keyboard experiment was restarted during this investigation; use its [current README](../AppleMagicTouchstream/README.md) as the baseline, rather than the earlier stripped version described in the first plan. Its button/drag event blocker is distinct from suppressing ordinary pointer movement, and it does not implement the proposed two-finger synthetic pointer. Do not bring removed features back merely to satisfy inherited transcripts. Run one app at a time for live evaluation.

Keep the reference boundary:

```text
OMSManager → InputRuntimeService → serial RuntimeCore / TouchProcessorEngine
                                  ├─ contact/features
                                  ├─ typing hypotheses
                                  ├─ chord/pointer proposals
                                  └─ ownership coordinator
                                       → semantic commands
                                       → existing dispatch / KeyEventDispatcher
```

Live input and production replay must call the same reducer and scheduler. Keep Core Graphics, UI state and wall-clock queries outside recognition. Existing virtual-time replay is an asset to preserve, not a subsystem to reinvent.

## 3. Define data contracts before moving the engine

The following are **proposed interfaces**, not existing type names or vendor definitions:

```swift
// Schematic contracts; use existing app types where they express these roles.
ContactKey(deviceID, rawID, generation, epoch)
ContactObservation(key, timestamp, positionMM, phase, optionalFeatures)
ContactState(key, acquiredAt, acquiredPosition, latestPosition,
             sampleCount, peakStrength, velocity, identityEvidence)
TypingCandidate(id, contactKey, state, geometryRevision,
                alternatives, bindingSnapshot, cancellationReason)
ChordCandidate(id, members, selection, confidence, activation, state)
DecisionProposal(owner, members, event, confidence, reason)
OwnedOutput(token, owner, action, epoch)
Engine.step(frame, dueDeadlines, configuration) -> bounded decisions
```

Each field has a contract:

- Use monotonic time and seconds internally; record source timestamps and frame sequence. Define how timestamp regressions and missing frames are handled.
- Convert positions into physical device-local millimetres once. Retain device dimensions, orientation and source coordinates in capture metadata. Mirror only under an explicit routing/orientation model.
- Track raw IDs by lifetime, not anatomical label. Reused IDs receive a new generation; reset, replay seek or reconnect starts a new epoch.
- Identity is evidence with validity/confidence, not a constant. The requested display convention is thumb=1, index=2, middle=3, ring=4, pinky=5, palm=6. It is distinct from FingerWorks internal bits and from stable contact IDs.
- **Apple capture evidence:** isolated intended index taps were mostly labeled4; adding contacts revised existing labels without lifting. A single-finger slide also changed5→4→3→2. Raw labels can be stable and wrong, so persistence alone is not confidence. No confidence value was supplied in these captured telemetry records. Use anatomical estimates as soft evidence; do not manufacture anatomical truth from stable codes. See [the capture review](../gesturepad/RewriteValidation/CAPTURE_FINDINGS.md).
- Optional pressure, area, orientation and finger labels require validity flags. Missing data is not zero pressure or “thumb absent.” Check what OMS actually supplies on the tested device before using it for classification.
- Derive peak, path length, maximum displacement and velocity from input frames, not rendered traces. Use elapsed time for temporal features rather than assuming a fixed frame rate.

Keep this state confined to the existing serial owner. Prefer bounded storage and reuse existing `TouchTable` until profiling supports replacement. No per-frame file I/O, verbose strings, configuration decoding or unbounded histories on the input queue. Record bounded numeric diagnostics and serialize off the hot path.

## 4. Build typing in two stages

### Stage A: interpretable deterministic candidates

Use `tentative → committed → finished`, plus terminal `cancelled`. Contact tracking continues after a typing candidate cancels.

At acquisition, snapshot the geometry revision, candidate bindings and relevant feature availability. Update motion/strength evidence while tentative. Plain keys commit under an explicit measured policy, initially the experiment's intended tap-release behavior; a configured hold/modifier/layer has its own activation deadline. Do not impose the firmware's global 1.5× timeout on every tap.

Movement beyond the chosen cancellation rule can cancel a **tentative** key. A candidate claimed by a pointer/gesture cannot type on later release. After commitment, movement cannot retract an emitted character. A held key keeps its original binding until cleanup; it does not silently morph into a gesture. Cross-pad modifiers must still apply to independently owned typing contacts.

Maintain reason codes such as `moved`, `claimedByChord`, `missingFeature`, `layoutReplaced`, `deviceLost`, and `ambiguous`. They make replay disagreements diagnosable. Preserve tuning behavior for peak-force bounds and per-key force holds unless evaluation justifies changing it; those are different conditions.

### Stage B: bounded alternative interpretations

Once Stage A has a labeled baseline, consider a small configurable set of plausible keys plus `noKey`. Firmware supports that architecture but does not supply calibrated Apple scores or a recovered beam width.

For a proposed spatial model, normalize acquisition displacement against key geometry and measured per-user spread; score motion, duration and available strength evidence separately. Specify score direction and units. A GlassToKey log-score could be:

```text
sequenceScore = predecessorScore
              + spatialEvidence
              + temporalEvidence
              + optionalContextEvidence
```

This is a **proposal**, not the recovered complete firmware formula. Score `noKey` explicitly, use a rejection/ambiguity margin, bound alternatives and sequence depth, and record the components. Do not copy a skip-contact weight into a “keypress confidence” field. Include a tie-break based on stable candidate order so replay is deterministic.

Start with spatial evidence alone. Add optional language context only if held-out intended-text sessions show an improvement without unacceptable substitutions or delay. Emitted text cannot serve as its own ground truth. Modifier chords, shortcuts, password-like text and non-text actions need a context-free path. Do not automatically send Backspace to revise a prior application's text; any future correction feature needs its own explicit scope, focus guards and evaluation.

The latency tradeoff is unavoidable: early irreversible commitment reduces delay but closes the chance to recognize a later chord. Measure that tradeoff; no policy can promise both zero extra delay and perfect retrospective interpretation.

## 5. Make every key movable without destabilizing typing

Separate stable identity, geometry and action binding:

```text
KeyDefinition: keyID, optional columnID, local shape/pose
ColumnDefinition: columnID, transform, stable ordered keyIDs
LayerBindings: (layerID, keyID) → actionID
LayoutSnapshot: revision, device transform, immutable resolved shapes/index
```

This is a proposed rewrite model. A key can belong to a column while retaining an independent offset. Moving a column composes its transform with each child's local transform; moving one key edits only that key's local pose. Never encode its identity solely as a row/column array index or displayed character. Keep visual labels separate from action semantics.

For click-and-drag editing, enter an explicit editing mode, suspend recognition output from affected surfaces, and release app-owned holds before an edit session. The UI works on a draft layout. Render a preview during dragging, validate on commit, then publish **one immutable new revision** and one undo operation. Coalesce pointer movement; do not rebuild the recognizer's index on every drag pixel.

Define overlap precedence, hit boundaries, out-of-pad geometry and transform order. Use one resolved geometry snapshot for both rendering and hit testing. Convert screen pixels through the device transform; retain millimetres as the recognition coordinate system. Layer changes usually replace bindings, not geometry. Layout generators produce editable definitions rather than regenerating away saved manual edits.

An active contact retains its target/binding snapshot. Publishing a structural layout edit cancels old tentative candidates and cleans up active outputs through their original bindings. New contacts use the new revision. Persist stable IDs, transforms and schema version; migrate current profiles with a preview and export/round-trip checks. A repeated load/save must not gradually move keys.

Do not introduce speculative spatial trees for a small keyboard. Cache resolved bounds at revision changes, benchmark linear scans versus the existing lookup, and optimize measured costs.

## 6. Give chords distinct selection and activation

A **proposed** conservative lifecycle is:

```text
idle → assembling → selected
selected + valid quick release → tap action → finished
selected + dwell deadline     → activated(.hold)
selected + deliberate motion  → activated(.motion)
activated + updates           → motion/action updates
activated + finish/cancel     → release owned output → finished
```

Selection alone posts no output. Dwell uses the scheduler even when no new input frame arrives. If a chord activates, its later release must not also trigger the quick-tap action. A stationary drag-button hold still needs mouse-up on finish or cancellation.

Continuously revisable labels and a latched gesture are separate states. During acquisition, new context may change the preferred chord. At commitment, latch its semantic action and owning contact keys; a later label revision or partial lift must not silently create a different/smaller chord. For the initial conservative experiment, gate rearm on all-up of the owning hand/surface, including quarantined late arrivals, while permitting independent activity on the other pad. Action finish/release timing is a separate explicit rule. This is a proposed GlassToKey lifecycle; raw contact captures alone cannot prove the full TouchStream rule or any fixed one-second delay.

The [lifecycle follow-up](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/lifecycle-2026-10-17/PROGRESS.md) now directly verifies the ordinary activated-selection replacement guard. Firmware hand14 is raw contact count, hand17 ordinary assigned fingers, hand20 their peak, and hand19 an epoch-qualified subset. Its special grips and five-finger-peak path can finish/rearm without raw all-up. Therefore keep `rawContacts`, `estimatedFingerMembership`, `acquiringCandidate` and `activatedOwner` separate in the Swift design. Do not freeze the first uncertain anatomical label; freeze semantic ownership at activation. Log the explicit rearm reason and whether only an incidental palm remains. Test that distinction before weakening the conservative all-up policy. Never release another owner's outputs when changing epochs.

**Second Apple session:** [the lifecycle capture review](../gesturepad/RewriteValidation/LIFECYCLE_CAPTURE_FINDINGS.md) now supplies four repeated finger-pair cycles over a continuous14.6s palm-like contact, three3→2→3 replacements, two5→2→5 sequences and three independent pairs while the other pad stays held. The continuous palm-like contact revises6↔1 and includes raw code12, so current-code-only palm exclusion is insufficient. Preserve unknown codes and exclusion evidence over lifetimes; test both conservative raw-all-up and an explicitly justified cohort reset in shadow mode. Two one-sample pressure0/code0 lifetimes during landing also belong in tentative-acquisition and raw-ID generation tests. These observations do not establish gesture activation or its timing.

Assemble using a cohort of contact keys and arrival times, not just a count. Try reliable exact patterns before generic non-thumb-count/thumb-presence templates. Unknown identity gets its own fallback or rejection. Estimate geometric fit relative to centroid and hand size; document any normalization and missing-finger penalty as GlassToKey choices. Require a margin against the second candidate, not just the smallest residual.

Test staggered landings so an early two-finger subset does not fire while a three-finger chord is forming. For the first experiment, latch an activated cohort, quarantine extra arrivals, and disallow reinterpretation as a smaller chord on partial lift. Rebase centroid motion on any allowed membership change to prevent jumps. Requiring full cohort lift before rearming is a conservative **proposal**, not a recovered universal TouchStream law.

Keep gesture recognition in shadow mode in `mac_gesture_pad`: output diagnostics and candidate states only. Add action dispatch later as a separately reviewed implementation stage.

## 7. Resolve ownership in one place

Recognizers may observe the same tentative contacts; committed ownership is exclusive. One coordinator applies decisions in deterministic order before dispatch:

1. Expire/cancel stale epoch, disconnected device and invalid configuration work.
2. Deliver required releases and retire finished owners.
3. Evaluate tentative typing/chord/pointer proposals against remaining contacts.
4. Atomically claim the chosen cohort, cancel conflicting tentative interpretations, then emit semantic activation commands.
5. Schedule future work tagged with owner, epoch, sequence and configuration revision.

The priority and same-timestamp ordering above are proposed policy and must be fixture-tested. A pre-existing committed key/hold cannot be stolen by a newly arriving gesture. Several independent keys can commit with overlap; rollover is not automatically a chord. A held modifier can affect another contact without surrendering ownership.

Output ownership uses tokens/refcounts, not a single global “Shift is down” Boolean. Two owners sharing a modifier cannot release each other's hold. Reset releases **app-owned** state, not unrelated physical input. Haptics occur at the intended accepted transition and do not repeat merely because a replay frame is reevaluated.

## 8. Treat native pointer control as its own feasibility milestone

Receiving raw Apple contacts does not itself suppress native macOS pointer, click, scroll or system gesture events. The restarted keyboard app's `MouseEventBlocker` subscribes to button/down/up/drag events, not ordinary `mouseMoved` or `scrollWheel`; it is not a two-finger pointer implementation. A two-finger-only synthetic pointer requires a tested native-event suppression strategy before recognition accuracy can solve the whole problem.

Build a narrow prototype that establishes event attribution to selected devices, event classes actually suppressible, permission behavior, and an immediate disable path. Never assume all mouse events came from the selected trackpad and silently swallow another mouse. Tag injected events to bypass interception. Demonstrate exactly one motion/click/scroll source and cleanup on event-tap disablement, permission loss, sleep and disconnect. If suppression becomes unavailable, stop synthetic movement and return to a documented native-input mode.

The alternative of sinking all pointer traffic is an explicit global product mode with broader effects; it must not happen implicitly as a fallback. Do not change system trackpad preferences automatically.

Once suppression is feasible, derive cohort-centroid displacement in millimetres, apply one documented gain policy, retain per-axis fractional residuals and emit motion through the dispatcher. Choose whether macOS or the app owns acceleration, then verify delivered behavior; do not stack two unmeasured curves. Reset residuals at epoch/owner changes. Define click, drag, scroll and momentum separately. TouchStream's signed-byte HID clamp and six keyboard slots are transport constraints, not macOS software limits to copy.

## 9. Use traces to explain decisions, not to make them

Keep the user's contact tracing option independent of policy. It displays observed paths even when recognition produces no key. Render snapshots may skip frames and cannot feed recognition history back into the engine.

A developer overlay should optionally show contact key/generation, raw identity versus interpretation, sample count, candidate target(s), ownership, phase, score components and cancellation reason. Keep displayed pressure peaks distinct from acquisition/activation thresholds. Publish bounded snapshots at UI cadence; no per-frame formatting or unlimited path arrays on the runtime queue.

Extend captures with recognizer/config version, dimensions/orientation, feature validity, geometry snapshot/revision, calibration and arbitration timings. Decision logs need owner/candidate IDs, input sequence, transitions, reasons and output tokens. Preserve older captures through an explicit reduced-feature policy. See [production replay](PRODUCTION_REPLAY.md), [telemetry contract tests](Tests/ReplayFixtureKitTests/MacTouchTelemetryTests.swift), and [capture format](ReplayFixtures/FORMAT.md).

## 10. Implement in reviewable milestones

| Milestone | Deliverable | Exit condition |
| --- | --- | --- |
| 1. Baseline | Versioned configuration, lifetime IDs and shadow candidate diagnostics in existing live/replay boundary. | Reference output unchanged; ID reuse, reset and device loss deterministic. |
| 2. Keyboard states | Tentative/commit/cancel and explicit hold deadlines in `mac_keyboard`; preserve intended layers/modifiers/repeat. | No release-after-cancel keys, duplicate keys or stuck holds across lifecycle fixtures. |
| 3. Editable geometry | Stable key/column IDs, transforms, draft/commit editor and immutable revision snapshots. | Column and individual-key drag work; undo and persistence round-trip; active contacts cannot retarget mid-hold. |
| 4. Shadow chords | Assembly, exact/generic pattern lookup, confidence, tap/dwell/motion states in `mac_gesture_pad`. | Labeled staggered/partial-lift captures produce stable decisions with no action output. |
| 5. Integration | One ownership coordinator in `mac`, versioned experimental policy, existing action catalog/dispatch. | Setting off preserves reference replay; setting on passes explicit typing/chord coexistence fixtures. |
| 6. Pointer feasibility | Scoped suppression prototype and separately enabled two-finger synthesis. | No doubled movement/clicks; failure and permission transitions release owned buttons and recover. |
| 7. Optional ambiguity model | Bounded alternate-key/no-key ranking, initially context-free. | Held-out intended-key data improves accuracy within an agreed latency budget. |
| 8. Default decision | Compare live reference and rewrite, then select proven defaults. | Publish errors, latency and pointer behavior; do not declare success from transcript parity alone. |

Suggested first PR: lifecycle IDs plus shadow candidate/ownership diagnostics and focused replay tests. That gives the keyboard and raw-contact experiments comparable evidence before changing thresholds.

Keep experiments independent while learning. Move a validated helper and its tests into the reference intentionally; avoid permanent competing copies of the coordinator. Add new app files to the Xcode project and package targets where required. Bridge work belongs in sources and requires rebuilding the XCFramework; do not edit generated framework contents.

## 11. Verification that can justify a rewrite

Required deterministic fixtures cover overlapping taps, fast alternation, held modifiers across pads, repeat/hold deadlines without further frames, same-timestamp timer/frame ordering, force boundaries, one-finger movement, two/three/four-finger staggered landings, unknown thumb/palm labels, partial lift, late extra contact, ID reuse, missing samples, layout/layer changes, replay seek, reset and disconnect during drag. Assert state transitions, ownership, output order and balanced down/up tokens.

For pointer integration, add event-tap disablement, permission revocation, injected-event bypass, another mouse in use and duplicate native/synthetic event checks. Recording sinks prove intended commands; only OS/hardware checks prove actual event delivery or suppression.

Collect separate calibration and held-out evaluation sessions with intended keys/actions recorded independently of output. Report wrong/missed/duplicated keys, modifier failures, gesture false activations during typing, candidate-to-commit and frame-to-post latency p50/p95/p99, cursor drift, unintended clicks, queue age/depth and sustained memory/CPU cost with traces enabled/disabled. Establish numeric budgets from a reference baseline; none has yet been measured by this investigation.

For reference implementation changes, run from `mac`:

```sh
xcodebuild -project GlassToKey/GlassToKey.xcodeproj -scheme GlassToKey \
  -configuration Debug -destination 'platform=macOS' build
swift test
swift run ReplayHarness --fixture ReplayFixtures/production_typing.atpcap \
  --expected-transcript ReplayFixtures/production_typing.engine.transcript.jsonl
```

Use each experiment's own build/tests and intended behavior. The production typing fixture is synthetic, not a physical accuracy study. Review changed transcripts against requirements rather than regenerating until green. Run `./build_framework.sh` only when bridge changes require it; signed release/notarization follows recognition validation.

## 12. What further firmware work would change this plan

**Connected-system checkpoint:** read the [contact → assignment → ownership → output → release map](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/system-2026-10-17/SYSTEM_MAP.md) before choosing new recognition policy. It joins contextual, revisable finger assignment to departure timing, scoped cancellation and explicit release ownership. The [remaining-work ledger](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/system-2026-10-17/coverage-ledger.json) keeps sensor/metric, FP, language and special-lifecycle gaps explicit. The candidate-refresh probe also corrects an easy delayed-branch mistake: both identity and sample count keep updating when position refresh is frozen.


**Follow-up, 2026-10-17:** the [rewrite-focused investigation](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/rewrite-followup-2026-10-17/PROGRESS.md) now reconstructs the positive-input log10 helper, alternative/head score ratio and increasing age threshold `t²/(300²+t²)`, plus the conditional 100/350-unit timing selection. The integer tail passed 960 synthetic branch cases. Sequence release/motion summary bits and a 24-candidate alignment/lookahead bound are also traced; that bound is not a recovered beam width.

This strengthens Stage B's case for confidence-dependent patience and retained motion evidence. It does not justify copying those numeric time units into Apple defaults, and return-zero from the gate does not guarantee emission. The full language/pruning model and adaptive geometry remain incomplete. The newer [lifecycle pass](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/lifecycle-2026-10-17/PROGRESS.md) adds verified register MPYI3 and one indirect TSTB3 form. Membership now completes174/174 integer-arm cases; its middle FP arm remains unexecuted. Another560 bounded cases verify ordinary replacement, termination and a five-finger rearm exception. These refine the policy choices but do not establish a universal firmware lifecycle.

**Apple-contact testing is prepared:** start with [tomorrow's session walkthrough](../gesturepad/RewriteValidation/START_HERE.md). The raw-contact playground has an offline `RewriteProbe` executable, declarative intended trials, readable contact tables, input hashes and focused tests. It checks contact assumptions and treats missing data/calibration as inconclusive. It changes no live recognizer or OS output; shadow recognizer/accuracy tests come after examining the recordings.

Exact confidence/time gates, adaptive geometry and language/pruning recovery could refine Stage B. Full lifecycle reconstruction could replace the conservative rearm proposal. Better axis/context reconstruction could supply additional motion experiments. None removes the need to calibrate Apple contacts or prove native-event suppression.

The latest processor suite has168 decoder/emulator assertions, 256 actual modifier-helper cases, 512 bounded candidate-gate cases, and 504 stationary-hold-gate cases, followed by the scoped probes above. These improve confidence in specific recovered paths; they are not tests of this proposed Swift recognizer. Both real Ghidra projects contain the follow-up annotations, and the [latest saved-project audit](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/lifecycle-2026-10-17/saved-project-verification.json) verifies that firmware memory remains unchanged.

The [next physical session](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/lifecycle-2026-10-17/RETURN_TESTS.md) targets a palm held across repeated finger cohorts, partial-lift replacement, five-to-two transitions and independent-pad rearm. Raw recordings can validate the available input evidence; a shadow decision stream is still required to test recognizer ownership and actual gesture selection.
