# Typing and gesture arbitration audit

2026-10-25. The capture audit below describes the original failing behavior; the
implemented targeted change is documented after the firmware evidence.
It investigates missing letters during fast typing while preserving the accepted
feel of two-finger pointer movement, tap click, and one-finger key taps.

## Confirmed behavior before the fix

`Engine/GestureKeyboardArbitration.swift` reserves a pad's entire cycle as soon as
its active count matches an enabled multi-finger family. For two contacts, an
enabled Move, Tap, Pinch or Spread is sufficient. It does not receive contact
landing/release history, key targets, or a successful gesture decision.

`EngineActorBoundary.processIngest` applies that reservation before keyboard
processing and before local gesture recognition. `TouchProcessorEngine` then
marks the pad's existing/present key contacts `gestureReserved`. Reservation
survives partial lifts and replacements until all-up. Established same-pad
MO/modifier ownership is an exception; ordinary letter rollover is not.

This protects against typing during gestures, but also destroys ordinary pending
keys before a gesture has actually qualified. A rejected gesture candidate does
not restore them. A sequence of overlapping key contacts can prolong the loss.

The captured build retained `typingGraceMs` as a compatibility-only no-op. The
600 ms value in this recording did not create a typing grace period. The targeted
change removes its defaults, UI plumbing, engine APIs and new export fields; old
JSON fields are ignored during import. It does not enable that old timer.

## Capture evidence: typing.atpcap

Source: `AppleMagicTouchstream/AppleMagicTouchstream/typing.atpcap` within this
project. SHA-256: `c1c6071b4e7c7b03b16ce9bbf7673701cd4bb8ba3ea32d9e77b6a0692682d995`.

| Observation | Recorded result |
| --- | --- |
| Processed frames | 1,213 across two native device identities |
| Last recorded arrival | 30,813.923 ms from the capture clock origin |
| `gestureReserved` diagnostic samples | 890 |
| Observed contact lifetimes with that reason | 37 of 120 |
| Active-count cycles containing reservation | 14 |
| Recorded tap dispatch decisions / posted keystrokes | 72 / 72 |
| Maximum recorded live/dispatch dropped counters | 0 / 0 |
| Maximum recorded live/dispatch queue depths | 0 / 0 |
| Other targeting issue | 24 `missedTarget` samples; separate from reservation |

Samples are not keys: the same rejected contact can appear in many consecutive
frames. These counts do not establish 37 intended lost letters. Contact lifetime
bounds can be capture-censored, and no expected typed text was supplied. Queue
counters describe the recorded app queues, not all upstream hardware delivery.

### Concrete rollover example

On native device `288230377507875157`, at approximately 13,827–14,018 ms of
capture-arrival time, recorded key targets are L, then K, then J. Within-device
source times relative to L's first observed making frame show:

| Source-relative time | Contact evidence | Recorded keyboard result |
| --- | --- | --- |
| 0 ms | L making | Ordinary key candidate |
| 34 ms | K starting while L remains down | Both still pending |
| 45 ms | K making, L touching | Both become `gestureReserved` |
| 56 ms | L leaving, K touching | Both remain rejected |
| 135 ms | J starting while K remains down | J inherits reservation |
| 169 ms | K breaking | Still rejected |
| 214 ms | J leaving | Still rejected |
| 225 ms | Empty frame | Cycle ends |

The first pair has only about 11 ms of making/touching overlap, below the current
20 ms minimum complete overlap for a two-finger tap. Nevertheless count-based
reservation has already removed its keyboard candidates. This directly connects
recorded missing-key rejection to the current arbitration policy. It does not
prove the entire gesture recognizer's internal state or intended text.

Raw lift records are present in this example. The evidence points to deliberate
software rejection rather than lost lifts or a full dispatch queue.

The capture's embedded profile includes legacy Typing Grace = 600 ms, but omits
`handGestureSettings`. Its legacy gesture fields are not the current configurable
gesture assignments. Therefore do not claim a fully faithful replay of live
recognition from that profile. Recorded live diagnostics remain usable. Absence
of pointer events in its dispatch stream does not establish absence of direct
pointer output.

## What the original TouchStream evidence establishes

Archive: `/Users/nap/Documents/new_code/Touchstream-archive`.
Firmware SHA-256: `87262a818209a1e019990f1e40f1b55d9d2dd030644d0f5aa0ed7e8cf09476e1`.
Addresses below are DSP word addresses. This is recovered static flow and retained
bounded execution, not recovered original C or a newly executed physical device.

- Typing candidates, selected chords, activated gestures and owned outputs are
  different objects. Contact count alone is not gesture activation.
- Hold and moving activation converge through C03BED / C03BC2. Activation calls
  C04823 to cancel typing within a qualified scope before executing actions.
  Special-pattern C039E1 can also invoke cancellation before ordinary activation;
  the firmware cannot be reduced to “never cancel until a gesture emits output.”
- C047F6 scans recent candidates and applies hand/time predicates. It stops at an
  age boundary and does not discard every key on both hands. The boot word at
  8062D0 is 90, used by this cancellation window. It is not evidence for a universal
  90 ms grace period or a delay to add to every key or mouse gesture.
- C04823 processes surviving hypotheses. “Forced” processing can reject, prune or
  advance alternatives as well as post output; it does not emit every survivor.
- Typing phase timestamps include signal-strength transitions, not just physical
  touchdown/lift. Apple pressure is not a calibrated substitute for those signals.
- C0432B has qualified paired-action timing checks (duration >= 50 and phase-clock
  differences < 36 on its traced path), plus semantic, strength and geometry gates.
  These are not a universal rule for distinguishing all typing from all two-finger
  gestures. The current Apple tap limits remain app policy.

Retained source reports:

- [Connected system map](/Users/nap/Documents/new_code/Touchstream-archive/firmware-analysis/rea-investigation/system-2026-10-17/SYSTEM_MAP.md)
- [Typing cleanup and surviving candidates](/Users/nap/Documents/new_code/Touchstream-archive/firmware-analysis/rea-investigation/typing-policy-2026-10-17/cleanup-trace/FINDINGS.md)
- [Qualified paired timing and output revision](/Users/nap/Documents/new_code/Touchstream-archive/firmware-analysis/rea-investigation/typing-policy-2026-10-17/commit-trace/FINDINGS.md)
- [Current consolidated findings](../FINDINGS.md#11-typing-and-gestures-share-arbitration-not-one-boolean-mode)

This audit independently checked the firmware container identity and compared
1,487 retained assembly words (751 cleanup + 736 commit) with the decoded boot
memory. No archive files, REA projects or firmware were changed. No new CPU
emulation or complete timing calibration was performed. The older commit report's
blocked ABSI cases have later follow-up coverage; consult current FINDINGS.md
rather than treating the older report as the final execution ledger.

## Implemented targeted change

The existing recognizers continue to process original live frames. Only unresolved
keyboard input is retained. Two fixed-capacity banks preallocate owned contact
storage at RuntimeCore creation; native pooled frames are returned normally.
Pending input preserves native route, sequence, timestamp and modifier context.
Actual gesture claim discards it, and the owner remains exclusive until all-up.
Never-activated rollover commits once the remaining contact/tap evidence resolves
to typing; that typing cycle then owns its remaining contacts. Single-finger taps
keep the direct path. Paused/unavailable gesture output does not fall back to keys.

Buffers cancel on invalid/duplicate/palm input, gaps of at least 150 ms, capacity
overflow, selection/reset/stop and configuration/layer invalidation. They hold at
most 1,024 frames of up to 16 contacts each. They never grow on the callback path
or flush from a cancellation. Settings/lifecycle cleanup retains its normal key
release obligations; cancellation does not fabricate old key presses.

### Additional activation defect found by replaying the raw contacts

At the captured K-making frame, L moves about 0.84 mm vertically relative to its
previous solo-contact frame. Previously this interval could immediately activate
TwoFingerMove when K joined, although it straddled the cohort's formation. Fixing
count reservation alone therefore did not recover this recording.

The shared activation rules now let TwoFingerMove require full-chord motion.
A pending membership-changing interval establishes the baseline rather than
contributing solo displacement. The nominal 0.35 mm threshold, acceleration and
activated latch are unchanged. Stable-pair golden tests retain the same activation
frame and deltas across 2→1→3→4 changes. **A staggered landing that previously
activated from solo motion can begin a frame later**; hardware feel must confirm
that boundary. Existing three-finger staggered drag remains unchanged.

### Difference from TouchStream and consequences

This borrows the separation of tentative input, activation and output ownership,
not the complete firmware implementation. TouchStream keeps scored key/no-key and
sequence hypotheses, signal-strength phase clocks, anatomical/context gates and
qualified correction paths. This app retains bounded raw keyboard proposals for
its existing key processor, uses the existing Apple-contact recognizers, and does
not synthesize Backspace corrections or import firmware pressure coefficients.

Unambiguous one-finger typing and stable two-finger movement gain no timer. An
ambiguous overlap can wait for partial lift or all-up before typing commits. Very
long unresolved input, changed configuration and invalid delivery cancel safely.
Simultaneous/coherently moving typing can still resemble a real gesture; this is
not a claim to have recovered all of FingerWorks' typing intelligence. No blanket
600 ms typing protection or post-typing mouse blackout is introduced.

## Reverse-engineering follow-up, 2026-10-25

The [focused firmware report](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/arbitration-2026-10-25/FINDINGS.md) adds exact boundaries rather than another grace timer:

- C047F6 stops at acquisition-phase9<=reference-window. Recent candidates require matching hand and phase10>=reference. This can preserve older same-hand typing that a whole-pad bank discards. These phases are not raw contact down/up.
- Ordinary activation records its time but passes reference0; cancellation derives its anchor from hand acquisition history. Combined gestures use each hand's own initial anchor. Quick taps and special-marker recognition can arbitrate without posted pointer movement.
- Wait-for-lift is the app's explicit proposal-resolution rule, not a recovered universal TouchStream condition. Firmware pending/commit decisions also depend on signal phases, semantic classes and scored alternatives. No firmware constant should be added as a mouse blackout or unconditional typing timer.
- The current full-chord-motion guard resets on count changes. A+B→A+C at count2 retains shared A movement; complete identity replacement rebases. This merits an offline case, but the firmware velocity/activity gate does not establish a literal reset-on-every-ID-change rule.

The fresh280cases cover scope routing, cancellation scan and one pending-phase decision. Scope/cleanup callees are explicitly recorded stubs or excluded; they are not complete recognizer/output tests. The [source audit](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/arbitration-2026-10-25/app-audit/REPORT.md) also distinguishes component LKJ tests from private live RuntimeCore ingress coverage. No app source, pointer settings, build or installed release was changed by this research pass.

## Design requirements

Replace destructive count reservation with explicit provisional versus activated
ownership in the existing serialized coordinator. This is an arbitration change,
not a pointer acceleration or recognition-threshold change.

1. Keep original per-contact key proposals, key/layer bindings and timestamps
   during unresolved multi-contact input. Two fingers present is a candidate,
   not permission to permanently delete those proposals.
2. Continue feeding the current gesture recognizers immediately. A real pointer
   activation must produce movement on the same frame as today, at the existing
   0.35 mm threshold, without a new typing timer or post-typing dead period.
3. Resolve ordinary staggered tap/release evidence against pending gesture
   evidence. Commit eligible typing proposals when arbitration resolves to typing;
   cancel overlapping uncommitted proposals when a genuine gesture wins. Do not
   resurrect typing from a gesture that has already activated or owns output.
4. Preserve original ordering and emit each selected key once. Already committed
   text is not retracted through synthetic Backspace. Preserve MO/modifier holds,
   other-pad independence, all-up/lifecycle cleanup and the accepted gesture latch.
5. Use recent typing context only if the evidence requires it, as a scoped bias
   on ambiguous proposals. Do not blindly activate the old 600 ms profile field.

Some simultaneous stationary key contacts and intentional gesture taps are
inherently ambiguous from these measurements. Captures and controlled tests must
establish the policy; firmware constants alone cannot decide user intent.

Acceptance checks before installation:

- Isolated single-finger key taps preserve output timing and haptics.
- The captured L/K/J overlap sequence no longer disappears merely at count two.
- Deliberate two-finger movement has the same activation frame, output deltas,
  acceleration and all-up latch; 2→1 and 2→3/4 transitions remain smooth.
- Deliberate two-finger taps never also type keys, including over assigned keys.
- Gesture-to-typing and typing-to-gesture transitions have no arbitrary blackout.
- MO/modifier chords, held shortcuts, Both handoff, stale/disconnect cancellation
  and release balance retain their existing guarantees.

## Reproduce the audit without native input

```sh
python3 mac/AppleMagicTouchstream/Tools/TypingArbitrationAudit/analyze.py \
  mac/AppleMagicTouchstream/AppleMagicTouchstream/AppleMagicTouchstream/typing.atpcap \
  --output /tmp/amt-typing-arbitration-audit.json
```

The tool reads the capture and writes only the requested report. Its timeline,
contact lifetimes and count cycles allow further inspection without inferred
intended text or modifying the original recording.

The legacy count-gate tests still describe exclusive reservation once explicitly
requested. New regression tests exercise the retained proposal path with an
extracted L/K/J fixture, deliberate two-finger taps, stable-pair motion golden
deltas, copying/capacity/invalid-input cleanup, modifier context and retired-field
imports. The original recording remains unchanged. Offline checks cannot establish
physical mouse/typing feel; a fresh capture is appropriate if hardware still shows
missed letters.
