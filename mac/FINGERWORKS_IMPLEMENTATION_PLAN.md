# FingerWorks implementation plan

The maintained macOS app is [AppleMagicTouchstream](AppleMagicTouchstream/).
[Gesture rules](AppleMagicTouchstream/GESTURE_ENGINE.md) specify current behavior;
[FINDINGS.md](FINDINGS.md) records firmware evidence, and
[RESEARCH_ARCHIVE.md](RESEARCH_ARCHIVE.md) preserves useful experiments and design work.

## Current architecture

```text
native selected-pad FLTR callbacks
  → device/contact identity and timestamps
  → established keyboard / Both / corner arbitration
  → keyboard reservation and per-pad gesture candidates
  → activated gesture ownership
  → configured actions and explicit output lifetimes
```

The keyboard engine supports keys, modifiers/Hyper, shortcuts, layers, per-key
Primary/Hold, Force instead of hold and repeat. The gesture engine supports
latched pointer/drag/scroll, precise momentum, taps, Force, thumb-required
Pinch/Spread, stationary Hold, directions with held repeats, directional scroll/pan,
and coordinated Both chords. Settings are independent per pad, with Mirror Edit
and portable gesture settings. See the current specification for exact defaults.

Native takeover operates only on selected supported model0324/type4 pads; USB and
Bluetooth are hardware-tested. It has persistent default-off opt-in, differential
selection, rollback, lifecycle cleanup and Ctrl-Option-R release. It uses the native
multitouch driver and does not require a custom DriverKit extension or helper.

## Design principles

- Separate contact tracking/anatomical hints, tentative candidates, activated
  gestures and output ownership. Count is activation evidence, not a mode switch.
- Preserve established ownership and balance releases before handing control over.
- Keep per-pad state independent; coordinate only explicit Both gestures and shared
  cursor/button resources. Existing keyboard MO/modifier chords have explicit priority.
- Reserve gesture candidates before irreversible typing output. Keep rejected input
  reserved through release; never emit speculative text then attempt global undo.
- Reuse shared latch, direction, tap and cleanup logic. Different geometry or clocks
  justify separate evidence adapters, not duplicated event ownership implementations.
- Keep original firmware facts, app approximations, capture observations and hardware
  acceptance distinct. Preserve calibrated evidence and unresolved measurement bounds.

## Dimensions and calibration

| Surface | Width × height used for comparison |
| --- | --- |
| TouchStream, each pad | 165 × 121 mm |
| Apple Magic Trackpad | 160 × 114.9 mm |

Axis fit is about 97.0% width / 95.0% height; aspect-preserving fit is about 95.0%.
These are physical comparison dimensions, not verified active sensing bounds.
The app uses the latter scale for normalized contact motion; actual sensor mapping
is documented separately in [HID layout](../../new_code/touchstream-archive/AppleMagicTouchstream-research-2026-10-26/notes/APPLE_CONTACT_HID_LAYOUT.md).
Do not derive native coordinate bounds or force units from housing dimensions.

The TouchStream layout has independent traced left/right key regions and stable
IDs, supports per-key overrides and shows its reference automatically. Column tuning
is disabled for this layout. A reference image is not recognition input.

## Research to retain

Original firmware `touchstream.U.byt`, version `0x0160`, SHA-256
`87262a818209a1e019990f1e40f1b55d9d2dd030644d0f5aa0ed7e8cf09476e1`, uses C3x DSP
word addresses. Findings cover distinct contact/candidate/action lifetimes, mutable
anatomy, count fallback plus arrangement scoring, selected versus activated chords,
combined-hand acquisition, scoped typing cancellation and balanced output release.
The current app implements selected interaction rules; full DSP scoring and
language-based interpretation are not yet reconstructed.

Apple pointer and scroll models use separate published parametric/history paths.
Preserve fractional movement, per-axis/per-pad history and physical-unit assumptions.
The contact-to-count hypothesis is `resolution / 25.4 × sensitivity`. Accepted feel
is useful evidence but does not establish the complete proprietary Apple pipeline.

## Next work

1. Keep the current accepted motion/tap/drag behavior stable with capture regressions.
2. Define rotation/new gesture families using the same explicit session contract.
3. Improve decision/output observability: capture intent, rejection reason, queue age
   and delivery timing without logging in the contact callback. Input captures alone
   cannot prove application event receipt.
4. Measure downstream queue depth/age before choosing overflow policy; preserve final
   release and output cleanup. Do not drop arbitrary frames to hide overload.
5. Extract engine/UI type aliases incrementally if needed for new recognition work.
6. Research competing compact/spread arrangement scores, adaptive geometry, original
   spelling correction and variable-speed typematic independently. Use intended-key
   labels, `noKey` alternatives and held-out captures; learning from emitted text
   alone is not a reliable calibration signal.

## Acceptance

Use `./mac/AppleMagicTouchstream/test.sh`. Offline checks cover serial recognition,
key output, gesture ownership, native lifecycle fakes, settings and rendering. Keep
original captures unchanged and review any intentional baseline change. Hardware
checks cover BT/USB, independent pads, takeover/release, native restoration, selection,
None/duplicate pads, Config/Restart, sleep/replay and physical-button interference.
Build/install stays separate from activating live input.
