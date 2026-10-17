# Second capture review: partial lift, palms and per-pad rearm

2026-10-17. Four new human recordings, analyzed offline with `RewriteProbe` and an independent framed-container timeline reader. The reader cross-checks every route's frame and active-sample counts against the Swift parser. Input hashes and compact results are in [LIFECYCLE_CAPTURE_VERIFICATION.json](LIFECYCLE_CAPTURE_VERIFICATION.json). These recordings observe contacts; this playground has no gesture recognizer decision stream or action output.

## What we learned

Your distinction between revisable finger estimates and a stable gesture owner remains a useful design. These recordings provide concrete lifecycle fixtures for a future shadow recognizer. They do not themselves demonstrate whether any gesture activated or stayed selected.

| Capture | Observed contact structure | Rewrite implication |
| --- | --- | --- |
| palm-held-cohorts | One continuous contact8 for14.619s; four finger-pair cycles while it stays down; peak3 | Raw all-up blocks independent finger-cohort rearm while an incidental palm remains |
| partial-lift-replacement | Three episodes each containing3→2→3; two tracked IDs survive each replacement | A later third contact must not silently retarget an activated owner; acquisition and late-arrival policy need separate tests |
| five-to-two-rearm | Two5→2→5 sequences; IDs8/9 survive each two-contact interval | Retain member lifetimes and distinguish peak size, current membership and possible rearm |
| opposite-pad-held | Route1 contact held0–6.457s; route0 completes three pairs during it | Owner/reset scope must be per pad unless a specific bimanual gesture owns both |

Route indices identify capture routing, not anatomical left/right.

## Palm-held: raw label filtering alone is insufficient

Contact8 stays active from the first recorded frame until explicit release at14.619s. Its label histogram is:

| Raw code | Active samples on contact8 |
| --- | ---: |
| 6 | 1,198 |
| 1 | 54 |
| 12 | 48 |
| 0 | 1 |

There are19 label revisions on this same lifetime, including repeated6↔1 changes while it is the **only** active contact. For example, code6 becomes1 at3.617s and returns to6 at3.875s; a second such interval runs4.608–4.832s. Code12 is retained as an uninterpreted raw value; this investigation has not established its anatomical meaning. It must not be forced into the1–6 UI convention.

The four finger-pair intervals are approximately1.277–3.584s,5.012–6.959s,8.274–10.097s and11.548–13.550s, measured from the first captured arrival. Their individual landings/releases are slightly staggered. The palm-like contact remains through every gap between them; the only raw-empty transition is its final release.

Therefore an implementation that ignores **only the current code6** will intermittently treat this continuous contact as a thumb or unknown. A future exclusion decision needs retained lifetime/geometry evidence and an explicit uncertainty policy. Do not globally blacklist code1 or12, and do not silently change an active owner's membership when the label changes. Whether this recorded contact is truly a palm comes from the intended trial, not from firmware-equivalent classification.

## Partial lift and replacement: three repeated examples

All times below use the capture arrival clock. The surviving IDs stay active while one contact lifts and a new contact joins.

| Episode | Original IDs | Partial lift | New third contact | Final raw-empty |
| --- | --- | --- | --- | --- |
| 1 | 1,9,11 | 11 leaves1.429s;1/9 survive | 6 joins2.396s | 5.321s |
| 2 | 5,8,10 | 8 leaves7.303s;5/10 survive | 6 generation2 joins8.314s | 9.416s |
| 3 | 2,3,7 | 2 leaves12.532s;3/7 survive | 6 generation3 joins13.961s | 15.232s |

There are21 raw label revisions overall. A peak count or instantaneous count alone cannot tell an original member from a new arrival. Preserve `(device, contactID, generation)` plus the activated owner's explicit membership. The same raw ID6 is reused across separate episodes and must not inherit old ownership.

These repetitions include partial holds of approximately0.87–1.42s before the first lift. Capture start and sparse idle delivery prevent precise claims about every physical first-down time; they are not a measured acquisition or activation delay.

## Five to two: useful steady survivors and tentative contacts

First sequence: IDs8/9 survive while the other three leave by1.271s. Three new contacts join3.262–3.274s; all lift by5.580s. Second sequence: the ordinary five-contact set is established by7.717s, falls to IDs8/9 by9.483s, then returns to five by11.452s before final release13.590s.

There are two additional one-sample lifetimes during the second landing: ID9 generation2 and ID8 generation2, each lasting about11ms, with pressure0 and raw label0. Both have explicit inactive records before their later generations start. The analyzer correctly retains them as separate observed lifetimes. These are evidence for tentative input handling and ID-generation tests, not proof that two real fingers physically tapped or that the tracker lost established contacts. Do not invent a merge rule from this one capture.

The stable two-contact intervals are about1.99s and1.95s. Raw captures cannot establish whether the TouchStream five-finger exception, or any proposed Apple equivalent, would activate in those intervals. Its epoch count and action/option/timing gates are not present in this telemetry.

## Opposite pad: reset independence is directly testable

Route1 has one continuous contact until6.457s. Route0 completes pairs at1.491–2.548s,3.100–4.394s and4.967–6.015s. Each route0 pair ends with explicit release while route1 is still held. A hypothetical global all-up reset could not rearm between those pairs. A per-pad reset could.

Use arrival times for this cross-device comparison. Native source timestamps remain per-device evidence and are not subtracted across devices.

## Data quality and limits

All observed routes have zero active-frame gaps over the declared100ms budget, timestamp regressions, duplicate IDs, invalid samples or device-identity changes. All observed lifetimes end explicitly. Telemetry is present for every active sample.

The existing analyzer still conservatively marks several lifetimes start-censored:1 palm-held,7 replacement,8 five-to-two, and6+1 across the two routes of opposite-pad. That includes contacts present in the first frame and first observations after sparse idle frame delivery. These flags were retained; no thresholds or earlier test expectations were changed to make a report pass. Release/member overlap evidence is stronger here than a claim about exact physical landing time.

Physical sensing dimensions remain uncalibrated, so this pass makes no millimetre drift or distance assertions. Pressure0 at acquisition is a recorded device value, not a force threshold recommendation.

## What to implement next

The next useful implementation is an output-free shadow owner in the gesture playground, with acquiring/activated/finishing states, per-pad epochs, contact generations, tentative arrivals, and explicit late-arrival/exclusion/rearm reasons. Feed these four captures into it and assert:

- Label revisions alone never create a fresh lifetime or retarget an activated semantic owner.
- The partial-lift/newcomer sequences cannot accidentally dispatch a smaller or replacement gesture.
- Reset on one pad is independent of an unrelated held contact on the other.
- A palm exclusion policy is evaluated over retained evidence, including its6↔1 and unknown12 intervals; raw-all-up remains a comparison policy.
- The one-sample code0/pressure0 records remain tentative and cannot inherit ownership through raw-ID reuse.
- Reset, cancellation and any eventual real output release only what that owner acquired.

These are proposed recognizer contracts. No new shadow recognizer, live gesture behavior or OS output was added by this review.

## Reproduce

From `mac/gesturepad`:

```sh
swift build --product RewriteProbe
python3 RewriteValidation/tools/review_lifecycle_captures.py
```

Detailed Swift observations for both routes, membership/label timelines, a compact console summary and the build log are under `RewriteValidation/reports-lifecycle-2026-10-17/`. That generated folder and raw captures remain local. The committed-capable script, this review and the verification JSON preserve the conclusions and provenance without adding private capture data to Git.
