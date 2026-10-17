# Magic Trackpad follow-up experiments

Prepared 2026-10-17, before returning to TouchStream firmware work.

Purpose: establish which Apple contact fields can supply the geometry, motion, strength and lifecycle features recovered from TouchStream. These experiments observe input. They do not test a new gesture recognizer, prove where Apple's classification runs, or validate native-event suppression.

## Resume here

Use the updated **GlassToKeyGesturePad**, with the keyboard/reference apps quit. It provides the same contact source without generating our own typing or gesture actions. Native macOS gestures can still occur. Select one pad and verify its traces before recording. The `mac`, `mac_keyboard` and `mac_gesture_pad` projects all have the total-preservation fix, but the gesture playground is preferred for these trials.

Save new files in a new dated subfolder under `RewriteValidation/captures/`, retaining earlier recordings. Use Capture from the app menu, wait about one second with everything lifted, perform the trial, lift everything, wait another second, then stop capture. Repeat each pattern three times unless specified otherwise. Separate files are easier to interpret than one long session.

Write a short `notes.md` beside the files: capture filename, intended anatomical finger/hand, pad model, transport (Bluetooth/USB if known), app revision/build date, macOS version, selected device/routing index, physical pad orientation, and any accidental touch or native click. Record intended actions even when the displayed finger label disagrees. Do not adjust recognizer thresholds or redo only the trials that look successful.

**First session priority: tests 0–4 below.** Budget roughly 20–30 minutes including notes. Tests 5–7 can wait. Reuse the earlier partial-lift and two-pad recordings before requesting more of the same.

## 0. Verify the fixed data path before interpreting new experiments

**No new physical trial required.** Select an existing capture where `total` and `pressure` differ. Check its rawTouches, processed contact decode, and a rewritten/reloaded fixture.

Expected software contract:

- A newly written processed contact preserves `total` independently of pressure.
- An old contact lacking total recovers it from a unique matching raw ID in the same device/frame, regardless of array order.
- An explicit processed total takes precedence. Ambiguous duplicate IDs do not select an arbitrary raw value.
- The package's historical pressure fallback is used only if neither source supplies total; flag such samples as unavailable for independent strength comparisons.
- The original input file is never rewritten during analysis.

Regression coverage already exercises recovery with reordered raw contacts and round-trip scalar preservation. The capture/replay test selection passed in all three projects, and all three Debug app builds succeeded. Before a later session, rerun from the gesture playground:

```sh
swift test --filter ReplayFixtureKitTests
```

This software check is essential: historical processed-only analysis could have compared pressure with a second copy of pressure. Current recordings retain the original total in rawTouches, so those originals do not need to be recorded again.

## 1. Separate strength, force-like response and contact area

**Question:** which scalars respond to stronger contact versus a larger patch of skin? Can any form a useful, calibrated proxy for TouchStream strength?

| File | Recording steps |
| --- | --- |
| `amt-strength-ramp.atpcap` | Place the index pad near the centre. Hold lightly for 2 seconds, gradually press more firmly over about 2 seconds, relax over 2 seconds, then lift. Stay comfortable; a physical click is optional and should be noted. Repeat three times. |
| `amt-area-roll.atpcap` | Hold one index contact near the centre. Slowly roll from fingertip toward the flatter finger pad and back, aiming for a similar contact centre and comfortable light contact. Repeat three times, lifting fully between repetitions. |
| `amt-strength-hold.atpcap` | Hold the same finger as still as comfortable for 8 seconds, then lift. Repeat once with light and once with firmer contact. |

Analyze total, pressure, density, major/minor axes, ellipse-area proxy (`major × minor`, without asserting an area unit), position and state on the same timeline. Compare onset, saturation, hysteresis, drift and correlations within each lifetime. Keep raw zeros and transition samples; summarize them separately from steady contact. Check whether scalar changes coincide with label/state changes.

**Decision this informs:** which features to retain separately, whether a strength proxy needs geometry compensation, and whether a peak/envelope analogous to firmware t20 is useful. These hand-controlled trials do not measure force in newtons, prove channel independence, or recover a conversion to firmware t2.

## 2. Calibrate coordinates and native velocity

**Question:** how do normalized position, absolute position and the two velocity vectors relate? What scale and axis conventions should an adapter use?

| File | Recording steps |
| --- | --- |
| `amt-axis-paths.atpcap` | With one index finger, make separate straight slides: left→right, right→left, near→far, far→near. Pause for a second before and after each slide while maintaining contact, then lift. Repeat at a slow and a comfortable faster speed. Note the pad's orientation. |
| `amt-distance.atpcap` | Use a ruler beside the pad to identify two points about 30 mm apart, comfortably inside the sensing area. Slide between them three times along each axis. Record the actual intended separation and endpoint uncertainty in notes. Do not infer the distance from the on-screen trace. |
| `amt-edge-path.atpcap` | Move slowly near each edge, then briefly beyond the sensing boundary and lift. Keep the finger otherwise comfortable and avoid accidental second contacts. Repeat once. |

Analyze normalized versus absolute coordinate pairs and fit their affine relationship per device/axis. Compare native velocity against timestamped finite differences in the same units; measure signs, scale, lag and behavior at stops. Check clipping, out-of-range coordinates and state changes near edges. Fit using source timestamps within one device; compare arrival timing separately.

**Decision this informs:** physical-distance mapping, axis inversion and orientation, usable speed estimates, and whether firmware speed/history gates can be meaningfully tested after recalibration. Outer case dimensions and the word “absolute” do not establish physical sensing dimensions. Ruler-guided travel has uncertainty; retain that uncertainty rather than declaring exact millimetres.

## 3. Relate ellipse shape to orientation

**Question:** do the axes and angle behave like a consistent contact ellipse, suitable for comparison to TouchStream's aspect/orientation features?

File: `amt-orientation.atpcap`. Place an index finger with its long direction approximately along the pad's vertical axis, hold 2 seconds and lift. Repeat at approximately 45° and 90°. Then make one slow comfortable roll/rotation while down, keeping the centre approximately stationary. Repeat the sequence three times; note which orientation each segment represents.

Analyze axis ordering, minor/major ratio, angle range/wraps, and continuity near circular contacts. Determine whether an axis swap accompanies an angle jump. Compare total/density changes during the same motions.

**Decision this informs:** angle normalization, handling of ambiguous near-circular orientation, and whether the callback's aspect ratio is a useful proxy for firmware t4. Do not assume anatomical direction is uniquely recoverable from an ellipse; 180° symmetry may remain.

## 4. Test identity revisions separately from contact continuity

**Question:** which changes follow hand context, which follow contact geometry, and do any force a new contact generation?

File: `amt-identity-context.atpcap`. Keep one known index finger planted. Hold alone 2 seconds; add middle, ring, pinky and thumb one at a time, about 1 second apart; hold all briefly; lift the added fingers one at a time while keeping the original index planted; finally lift index. Repeat three times. If comfortable, make a second file with the opposite hand in the same region of the pad.

Analyze the planted contact's ID, raw fingerID, handID, state, position, shape, total and pressure together. Count label revisions within its continuous lifetime; distinguish label revisions from explicit retirements, disappearances and ID reuse. Record delay after each contextual change, without interpreting that delay as gesture activation.

**Decision this informs:** how strongly to weight Apple's anatomical hints and how to keep those hints separate from recognizer membership. The existing all_fingers capture already demonstrates revisions; this more controlled timing sequence is for attribution and repeatability, not reconfirming that revisions exist.

## 5. Resolve short lifts and replacement lifecycles

**Question:** what does the parsed contact stream actually report across short interruptions, and when is continuity uncertain?

Files: `amt-brief-lifts.atpcap` and, only if earlier captures leave a specific gap, `amt-replacement.atpcap`.

For brief lifts, make five ordinary taps, then five quick lift/recontacts in approximately the same spot, then five slower lift/recontacts. For replacement, hold index and middle, lift index while keeping middle down, place ring nearby, then lift everything. Repeat three times. Human timing is approximate; do not claim a millisecond debounce threshold from these instructions.

Analyze every state, not only active samples: last active record, explicit inactive records, disappearance, next appearance, ID reuse, timestamp gaps and acquisition scalars. Preserve `(device, ID, generation)` and mark ambiguous continuity. Compare native source time with callback/capture arrival time.

**Decision this informs:** tentative arrivals, retirement, partial-lift ownership and conservative rearm. A missing idle frame is not proof of continuous physical contact. Neither this test nor Apple's enum directly recovers TouchStream's missing-scan/departure rules.

## 6. Check repeatability across devices or transport

**Question:** is a calibration reusable, or does it need a per-device/transport profile?

If available, repeat only the strength ramp and axis paths on the second pad. Optionally repeat them on the same pad over a different transport, after explicitly verifying the transport changed. Add `-pad2`, `-bluetooth` or `-usb` to filenames and record routing/identity each time.

Compare scalar ranges, coordinate transforms, callback cadence, ID/state behavior and label revisions. Do not infer anatomical hand from deviceIndex or subtract source timestamps across devices. The earlier opposite-pad capture already supplies overlap evidence; new recordings are needed only for these missing comparisons.

**Decision this informs:** per-device normalization and which assumptions can be shared. One recording per model is not a general hardware compatibility claim.

## 7. Optional deeper report provenance experiment

**Question:** which transport/report parser is active for these recordings, and which hints are already in that report before contact forwarding?

This requires additional capture tooling; the current contact .atpcap files cannot answer it retrospectively. Before asking the user to record, implement and verify a separate read-only full-frame/report capture path with source identity, report bytes, lengths and timestamps. Establish which layer that callback represents; a “full frame” name alone does not establish on-wire provenance. Correlate it with the contact callback using a justified matching method.

First use a short one-finger hold/context-change trial. Decode only the identified report format and compare labels/state/geometry with the forwarded contacts. In the recovered Compact V7 parser, wire finger code 7 maps to callback code 12; 512 selected Ghidra cases validate that unpacker behavior. This is not yet proof that the earlier code-12 samples used that parser or proof of where anatomical classification occurred.

**Decision this informs:** provenance of fields and which transformations Apple adds. Driver replacement, exclusive access and OS-event suppression are outside this experiment.

## Analysis and completion rules

Existing `RewriteProbe --inspect` remains useful for routing, lifetimes, labels and basic quality:

```sh
swift run RewriteProbe --inspect RewriteValidation/captures/SESSION/amt-strength-ramp.atpcap --device-index 0
```

Replace SESSION and device index with the actual recording route. This command is **not** a complete implementation of the scalar/velocity/shape comparisons above. Prepare that offline analysis before interpreting those experiments. The old session.json describes the earlier six trials; Run Checks.command does not automatically run this new plan.

For each new file, preserve its SHA-256 and an analysis record containing app/source revision, chosen route, decoded frame/sample counts, field availability, duplicate IDs, invalid values, timestamp regressions, active gaps, and censored/uncertain lifetimes. Record rawTouches and processed decode comparisons after the total fix. Keep physical intent labels and derived metrics separate.

Quality failures make the affected inference inconclusive, not a passing test. The existing 100 ms active-gap budget is a declared analysis choice, not a hardware specification or firmware threshold. Sparse idle delivery also limits physical onset/release timing. Do not silently discard strange labels or zero-strength observations.

Deliverables on return: a compact report per experiment, linked plots of the relevant channels on shared time axes, field/provenance notes, and an updated AMT→TouchStream adapter table stating what is observed, inferred, calibrated, or still unknown. New interpretation should be evaluated on fresh repetitions before adopting recognizer coefficients.

Related evidence: [AMT→TouchStream data contract](/Users/nap/Documents/new_code/touchstream-archive/driver-analysis/mac-native-15.7.4-24G517/data-contract-2026-10-17/FINDINGS.md), [first capture review](CAPTURE_FINDINGS.md), and [lifecycle review](LIFECYCLE_CAPTURE_FINDINGS.md).
