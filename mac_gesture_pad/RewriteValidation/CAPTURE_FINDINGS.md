# First capture review: revisable labels and latched gestures

2026-10-17. Seven user recordings analyzed with `RewriteProbe`; input hashes are retained with the generated reports. This is Apple-contact evidence, not additional TouchStream firmware execution.

**The user's observation is supported:** anatomical labels change within a continuous contact lifetime, and labels on existing contacts can change shortly after additional fingers land. Stable raw labels are not necessarily anatomically correct either. Contact identity and anatomical interpretation must remain separate.

## Results from the six planned trials

| Recording | Observed result | Interpretation |
| --- | --- | --- |
| Index taps | 10 lifetimes; 226 active samples, 224 labeled 4 and 2 labeled 0; two 0→4 revisions. | The user declares these index taps, but code 4 means ring under the UI convention. Repeatable classification is not anatomical accuracy. |
| Thumb taps | 10 lifetimes; 219 active samples, 215 labeled 1 and 4 labeled 0; four 0→1 revisions. | Consistent with the user's thumb trial and UI convention, but not proof the convention/estimate always holds. |
| Stationary hold | One continuous lifetime, about 1,766 ms; one 0→4 revision. | Only the `maximumIdentityChanges=0` assertion fails. Duration, lifetime count and contact count pass. This invalidates the zero-revision expectation; it is not evidence that the physical contact broke. |
| One-finger motion | One lifetime, about 821 ms; labels 5→4→3→2 while only one contact is active. | Revisions also occur without another contact landing. More-finger context is not the only situation in which labels change. |
| Staggered/partial lift | Two lifetimes, peak 2; one partial-lift frame; landing spread about 856 ms. | The input contains the requested membership transition. The spread is longer than the suggested 200 ms stimulus; this does not validate any chosen acquisition window. |
| Palm observation | One lifetime; 123 active samples, first 4 labeled 1 then 119 labeled 6. | Acting on the earliest apparent thumb label could misinterpret a declared palm contact. |

All selected-device active samples have identity telemetry. The analyzer found no active-frame gaps over the declared 100 ms budget, regressing timestamps, duplicate IDs or invalid samples in these recordings. Original recordings and the original trial plan were not changed to make assertions pass.

Five planned trials pass their observation checks. The hold trial fails the strict label-stability check only. That failure is useful data about the hypothesis, not a reason to throw away the capture.

Physical dimensions are still uncalibrated in the supplied plans. No conclusion about drift in millimetres or the suitability of the keyboard experiment's 3 mm boundary is made here.

## `all_fingers.atpcap` directly demonstrates context revisions

This recording contains both capture routes. Treat them independently: raw device IDs and touch IDs are device-scoped.

| Capture route | Frames | Active contact samples | Peak contacts | Lifetimes across the recording | Label revisions |
| --- | --- | --- | --- | --- | --- |
| 0 | 599 | 2374 | 5 | 6 | 7 |
| 1 | 653 | 2358 | 5 | 9 | 13 |

The total 20 revisions include 13 transitions from raw0 to a nonzero code and 7 nonzero-to-nonzero changes. This is a numeric distinction; it does not infer the driver's undocumented meaning for0. All active samples have telemetry, and neither route has the analyzer's continuity/quality errors.

Examples of **existing contacts changing label without lifting**:

| Route | Stable contact:generation | Label change | Simultaneous contacts | Time after latest context landing, same device source clock |
| --- | --- | --- | --- | --- |
| 0 | 1:1 | 4→2 | 2 | about 11 ms |
| 0 | 9:1 | 4→3 | 4 | about 11 ms |
| 0 | 11:1 | 5→4 | 4 | about 11 ms |
| 1 | 9:1 | 5→4 | 4 | about 11 ms |
| 1 | 5:1 | 5→4 | 5 | about 12 ms |
| 1 | 6:2 | 3→2 | 5 | about 12 ms |
| 1 | 9:1 | 4→3 | 5 | about 12 ms |

These events have matching active-contact continuity and generation. There is no synthetic finger-up/down caused by relabeling. The same changes occur about 11.1–12.9 ms after the latest landing on the capture-arrival clock. Source clocks are compared only within a device; their absolute values differ across devices and must not be mixed.

This supports context-sensitive revisions, but does not establish the internal inference algorithm or whether it recomputes on every frame. The capture supplies a raw estimate each sample; an unchanged output cannot reveal whether the internal estimate was recomputed.

It also does not prove that all final labels are anatomically correct. The index trial's stable but wrong label is a direct counterexample to using persistence alone as confidence.

## The gesture model the user described

Keep these separate:

1. **Observation:** position, stable contact key and latest anatomical guess continue to update.
2. **Acquisition:** while uncommitted, consider arrivals, geometry and current label evidence. A first arriving finger is not necessarily the whole intended chord.
3. **Commitment:** freeze the selected semantic gesture and its owning contact keys. Later label changes do not replace the gesture or transfer output ownership.
4. **Partial lift:** remaining members do not become a newly recognized smaller chord. The cohort remains committed or draining under the action's defined finish policy.
5. **Rearm:** require all-up on the owning hand/surface before a new cohort. Until reliable hand segmentation exists, a conservative implementation can use all-up on that routed pad, including quarantined late arrivals. Do not require the opposite pad to lift its independent modifier.

This describes **gesture latching**, not label freezing. The exact action finish rule—such as when a held mouse button releases—must be specified separately from when another chord can start.

These raw-playground captures contain no gesture-recognition/commit decisions. They therefore cannot prove the full TouchStream latch/rearm law, a one-second gesture delay, or a particular existing recognizer's release semantics. No fixed wait is inferred from the 11–12 ms label revisions. Testing those laws needs a shadow recognizer decision trace or actual gesture/output events alongside the contacts.

## Changes made for the rewrite

- The offline analyzer now records each same-lifetime label revision with capture time, native source time/frame, old/new codes, contact generation, previous/current active counts and the entire current contact-label context.
- Report tables show those revisions explicitly. Context is assembled before processing contacts so a same-frame landing is handled identically regardless of touch-array order.
- A regression fixture covers an existing contact4→2 when another finger joins, preserving its lifetime. Both contact-array orders are tested.
- The rewrite guide now records stable but wrong estimates and separates acquisition, commitment and all-up rearm.
- **28 Swift package tests pass**, including 13 probe tests. This pass changes no live recognizer, anatomical mapping, gesture defaults or OS dispatch path; the app bundle did not need rebuilding for offline-tool changes.

## Open the evidence or reproduce it

- [Six-trial report](reports-capture-review/report.md)
- [Both-pad all-fingers report](reports-all-fingers/report.md)
- [Timing/context audit](reports-all-fingers/context-revision-audit.json)
- [Input hashes](reports-capture-review/input-sha256.json)

From `mac_gesture_pad`:

```sh
swift run RewriteProbe --plan RewriteValidation/session.json \
  --output RewriteValidation/reports-capture-review
swift run RewriteProbe --plan RewriteValidation/session.all-fingers.json \
  --output RewriteValidation/reports-all-fingers
```

The first command intentionally returns 1 because the original hold assertion fails. The all-fingers observation plan passes for both routes; it checks five-contact availability and telemetry, not anatomical or gesture correctness. Captures and generated reports remain ignored by Git. The saved review and regression source remain in the repository.
