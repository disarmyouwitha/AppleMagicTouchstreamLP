# Right-click tap: guide versus configured recognition

For the consolidated reverse-engineering source of truth covering gesture
implementation, chording, typing arbitration, mouse behavior and release
ownership, use [mac/FINDINGS.md](mac/FINDINGS.md). The right-click-specific narrative
below remains as the earlier detailed research/implementation checkpoint.

2026-10-21. Original research was read-only; the subsequently authorized GesturePad implementation is recorded below. This pass reuses the retained REA/Ghidra firmware evidence and independently follows original packaged XML and utility source. It does not claim a fresh REA session, new emulator cases or hardware validation.

## The guide is explicit, but it is not the whole recognition contract

`docs/TouchStream_QuickGuides.pdf`, page1, says: “Right Click - Tap thumb, middle, & ring fingers.” Page2 additionally distinguishes the spread right-click/drag arrangement in Linux/Unix or three-button mode. The guide is copyrighted1999–2002, while the retained configuration declares1.6.0. A pictured/recommended finger set is not by itself proof of an exact-only classifier predicate. Text was extracted with pypdf; the PDF remains the source, and diagram details are not inferred from text extraction.

## Original shipped configuration

In `FW_defaults.jar`, `fingerworks/evmaps/app_config/FW_stealth_chords.xml`, the right-hand ordinary mouse group contains:

```xml
<Chord finger_combo="T2F" template_ref="Search &amp; Right Click/Drag"
       arrangement_ref="T2F Spread"/>
```

It also contains a compact T2F arrangement with the middle-click template restricted by categories `three_buttons emacs_op`, and a distinct TIP Spread arrangement for XWinder. Configuration/context therefore matters; count alone does not identify the resulting action.

`FW_parameter_macros.xml` defines:

| Arrangement | best_fingers | Template points |
| --- | --- | --- |
| T2F Compact | TIM | (-2,-2.9), (0,1.3), (2,1.6) |
| T2F Spread | STRP | (-6,-4.5), (2,2.5), (4,2.0) |
| TIP Spread | STIP | (-5,-4), (-2,2), (7,2) |

Those are vendor template coordinates, not calibrated Apple millimetres. `ac.java:F()` explicitly maps S→bit0, T→bit1, I→bit2, M→bit3, R→bit4, P→bit5. Thus STRP encodes **spread + thumb + ring + pinky**, not thumb+middle+ring. The layout name also reports spread via the arrangement reference. This disagrees with an assumption that the illustrated set is the only accepted anatomical set; it does not show that the guide itself is unusable.

`e.java:cfr_renamed_8` parses T2F as thumb plus two nonthumb fingertips and sets the any-permutation flag0x100000. `ag()` incorporates the arrangement's preferred anatomical bits without removing that flag. Consequently preferred STRP does not turn the definition into an exact-only TRP rule.

## Firmware selection connects anatomy, count fallback and geometry

Recovered `8021AA` first searches an eligible exact-pattern list. If none is eligible, it uses nonthumb population count plus thumb presence to select a fallback list. `8021E1` scores eligible arrangement candidates; `C0395D` evaluates template residuals scaled by configured hand size, and `C03933` handles optional regions. See the retained [original chord analysis](/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/evidence/assembly-chord-candidates.md) and raw REA assembly for8021AA/8021E1.

Therefore **TRP is not inherently a rejected right-click identity** in the recovered default-selection model. It is the spread arrangement's preferred set; a TMR observation can still reach a count fallback when exact selection does not take precedence. The result still depends on active categories, other eligible definitions, region/template fit and lifecycle gates. We have not run this exact configuration through the complete DSP FP scorer or inspected the user's physical TouchStream runtime configuration.

This is materially different from GesturePad's exact native set{1,3,4} and its rejection of any later contradictory known label. Existing mutable firmware anatomical assignment also does not prove the firmware binds immutable anatomical slots to tracking IDs for this tap. Apple's labels are a separate estimator and handID=1 is not a recovered anatomical-hand guarantee.

## Tap is one branch of a shared tap/hold/motion definition

`FW_chord_macros.xml` maps `Search & Right Click/Drag` SyncTap to `Secondary Click Event`, Timedown to secondary press, LiftSlide to secondary release, and a locking XY Slide to secondary drag. `FW_command_macros.xml` expands Secondary Click Event to `MouseEvent subType="click" modifiers="Button2" duration="30"`. This is a configured click-action duration, not a30-unit contact dwell threshold or an Apple event-delay recommendation.

Firmware `C01D57` quick-tap path checks selection activation/lock state and elapsed time against configured tap timeout before traversing eligible configured actions. Existing hold/motion activation follows distinct routes. A chord that has already activated hold/motion does not simply receive an extra quick click at release. Full Lift is derived from the active chord, and partial-lift behavior has additional policy; do not reduce this to a universal raw-contact-count rule.

The current500ms/80ms/20ms/1mm GesturePad tap limits are app policy. This investigation does not establish them as original FingerWorks values or prove the complete firmware SyncTap/release behavior. The original combined template's secondary hold/drag support is also broader than GesturePad's intentionally discrete right-click tap.

## Implications and diagnostic experiment

Historical recommendation before implementation: preserve the exact chord while diagnosing. Color diagnostics should display current classification, not mask changes by latching colors. To diagnose misses, record intended TMR and TRP trials separately with the current build. Inspect the full contact lifetime: whether any full three-contact frame ever has{1,3,4}, whether a later known relabel rejects a previously matched candidate, and whether movement/landing/release timing or another owner cancels it. Distinguish those rejection reasons from actual output delivery.

A later, separately reviewed fidelity experiment could compare exact-anatomy policy with **thumb+two-fingertip candidates selected by arrangement geometry and context**, retaining the original classifier and all competing chord arbitration. Do not merely accept TRP unconditionally: the configuration supplies multiple competing T2F arrangements. The user subsequently authorized this change; the implementation checkpoint below supersedes that earlier recommendation.

## Preserved evidence

The four original XML members are copied unchanged beside this report. `provenance.json` records their hashes plus original JAR, quick guide, utility source and GNU assembly hashes. No diagrams, fresh project annotations, test assertions or whole-gesture execution are claimed. Prior Ghidra projects and firmware bytes remain untouched.

## GesturePad implementation checkpoint

GesturePad now uses a positively identified thumb and two positively identified fingertips (codes2..5), rather than exact middle/ring identities. A provisional spread geometry test requires fingertip separation2..40mm, thumb-to-nearest-fingertip distance>=15mm and>=1.5 times fingertip separation, using the existing160×114.9 coordinate conversion. These are explicit app approximations, not a port of the DSP scorer or verified sensing calibration.

After matching, tracking IDs bind the thumb role and interchangeable fingertip pair. Unknown labels remain tolerated; fingertip relabeling is allowed, while known thumb/fingertip role changes or contradictory hand labels reject. Existing timing, movement, lifecycle and output safeguards remain. No compact middle-click or TIP/XWinder competing scorer was added; this is a focused right-click approximation, not complete firmware arrangement arbitration.

Original XML members and provenance remain under `/Users/nap/Documents/new_code/touchstream-archive/firmware-analysis/rea-investigation/right-click-2026-10-21/`. The canonical narrative now lives in this file.

Validation: GesturePad ./test.sh passed138 tests with2 skipped and0 failures. Hardware acceptance of the spread approximation remains pending.


## 3spread capture and installed-build mismatch (2026-10-21)

The user reported compact placements clicking but natural TMR/TRP missing, and
asked whether geometry was too restrictive. The geometry remains fingertip pair
2–40 mm, nearest thumb distance ≥15 mm and ≥1.5× fingertip separation. No tuning
was performed in this pass.

A read-only offline replay of `mac/gesturepad/RewriteValidation/captures/3spread.atpcap`
(SHA-256 `55c32e6a111c1fa540cd319cbda4165f2f7ae4c1f35bc55d1b9d751f3d31af85`)
found 1,006 frames and 53 completed contact cycles. Cycles are contact lifetimes,
not verified intended taps. Both current T2F and HEAD's prior exact-anatomy
recognizers were fed native telemetry and the production mouse/scroll/drag router.
No events were posted, hardware activated or captures modified.

| Check | Result |
| --- | --- |
| Current T2F predicted right-clicks | 40 |
| Prior exact-TMR predicted right-clicks | 18 |
| Isolated three-contact timing recognizer, without geometry/movement arbitration | 45 taps |
| Anatomically eligible T2F frames passing geometry | 494 / 494 |
| Observed fingertip separation | 15.57–32.74 app mm |
| Nearest thumb distance | 37.30–104.12 app mm |
| Thumb-distance / fingertip-separation ratio | 1.78–4.82 |

The existing geometry does **not** reject any eligible T2F frame in this capture.
Five otherwise timing-valid cycles (14,24,31,43,46) are claimed by two-finger mouse
before/around completion of the chord. Two others (34,41) exceed individual tap
travel: approximately1.193 and1.169 app mm versus the1 mm limit. Six cycles
(15,49–53) never contain three active contacts; the final four show Ring+Pinky
without a thumb, and cycle49 is one Index contact. This does not establish why
the third physical finger was absent, whether every cycle was intended as a tap,
or actual click delivery. Distances inherit the provisional160×114.9 scale.

At inspection the running process was `/Applications/GesturePad.app/Contents/MacOS/GesturePad`.
Both installed and Release binaries still carried the old `Thumb + middle + ring: right-click`
label, with modification time preceding the T2F source change; neither contained
the current Spread label. The source implementation and tested installed build
were therefore out of sync. This pass rebuilds and installs current T2F alongside
the requested legend/F-number cleanup; recognition rules are unchanged. Hardware
retest should use this fresh build before tuning geometry.

The JSON report and scratch offline replay source are retained under
`mac/gesturepad/build/RightClickCaptureAnalysis/` (ignored build artifacts).
