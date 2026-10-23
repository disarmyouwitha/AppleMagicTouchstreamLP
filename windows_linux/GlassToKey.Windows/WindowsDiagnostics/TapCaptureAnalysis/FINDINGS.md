# Two-finger tap landing investigation

## Result

The supplied capture reproduces two tap-to-movement errors in the unmodified Windows gesture engine. A targeted pending-chord baseline change fixes both offline, without changing the activation frame of any of the 14 longer movement cycles. No general tap delay, larger movement threshold, or acceleration change was added.

The existing all-up ownership/lift behavior and the fast-motion fix remain intact. Mac source and the unrelated items in `windows_linux/TODO.md` were not changed.

## Evidence

- Source: `windows_linux/capture-20261023-142718_taps.atpcap`.
- SHA-256: `56efb77d83d8bda5a10cc719e8c1a0714cff7527661ea4cc1c6f94491675a225`.
- Capture v2; 1,059 records over 29.555 seconds. Production decoder successfully decoded every report: ID 0x05, 50 bytes, Official profile, usage metadata 0/0. No decoder changes were made.
- 26 all-up-delimited cycles: one single-contact cycle and 25 cycles reaching two contacts.
- Analysis uses actual arrival timestamps and production-decoded tip contacts, normalized with the Windows runtime defaults: 7612 x 5065 units mapped to 160 x 114.9 mm.
- Capture does not contain gesture preferences, takeover state, actual cursor positions, or output decisions. Before/after results are offline engine output under Apple reference acceleration at 1x; both Pointer and PrimaryDrag assignments are covered by regression tests. They are not direct measurements of the native cursor.

## Cause

The original router computed shared-ID movement between adjacent reports, then tested the *new* finger count. If a one-finger report was followed by two fingers, a landing-related shift of the first finger could exceed 0.35 mm and immediately activate two-finger movement. That activation cancelled tap recognition despite the complete contact cycle still fitting the tap limits.

| Cycle (zero-based) | Frames | Duration | First-finger shift as second lands | Subsequent stable-pair maximum | Before | After |
|---|---|---|---|---|---|---|
| 2 | 476–483 | 100.3 ms | 0.9821 mm | 0.1863 mm | 6 pointer steps, no click | No movement, one click |
| 6 | 533–541 | 121.9 ms | 0.8116 mm | 0.1288 mm | 7 pointer steps, no click | No movement, one click |

The 0.35 mm movement threshold and 1 mm per-finger tap slop are unchanged. These two cycles do not require a global threshold increase: their movement evidence came from the wrong interval.

## Change

When no continuous gesture owns the cycle, two fingers have just formed or changed membership, and a two-finger tap action is assigned, that report establishes a fresh movement baseline. Movement activation then uses travel observed with the stable pair.

Once a gesture has latched, shared-ID movement continues across added/lifted fingers exactly as before. With two-finger tap set to None, the tap-specific baseline rule is bypassed and the original movement activation behavior is preserved. A pair present from the first report can still activate on its next movement report; there is no fixed settling timer. A single ambiguous interval during a staggered landing is intentionally discarded.

## Full capture replay

| Offline engine output | Before | After |
|---|---:|---:|
| Pointer step calls | 587 | 574 |
| Tap actions | 9 | 11 |
| Cycles producing movement | 16 | 14 |

Only the 13 false movement calls in the two affected tap cycles were removed. All 14 remaining movement cycles retain their exact first-output frame. Replaying the same capture with two-finger movement assigned to Drag / Select gives 14 balanced drag-down/up pairs; the repaired tap cycles emit neither drag edge.

The new embedded `WindowsDiagnostics/Fixtures/TwoFingerTapLanding.json` contains all 1,059 normalized frames, source hash and normalization parameters. `HandGestureTests.RunCapturedTapLanding` checks the repaired taps, exact preserved activation frames, full output counts, balanced drag cleanup, and tap=None behavior. This test was run before the fix and failed at captured tap 476, then passed after the fix. The existing acceleration golden vectors and fast-motion tests also pass.

## Reproduction

From `windows_linux`:

```powershell
dotnet .\GlassToKey.Windows\bin\Release\net10.0-windows\GlassToKey.Windows.dll --raw-analyze .\capture-20261023-142718_taps.atpcap --raw-analyze-out .\GlassToKey.Windows\WindowsDiagnostics\TapCaptureAnalysis\raw-summary.json --raw-analyze-contacts-out .\GlassToKey.Windows\WindowsDiagnostics\TapCaptureAnalysis\contacts.csv
```

Then run `analyze.py` in this directory with Python. It combines decoded CSV contacts with capture arrival times and writes frames/cycles JSON. `replay-before.json` and `replay-after.json` record actual pure-engine replay results; they inject no input. The embedded capture regression runs with the ordinary Windows `--selftest` command.

## Verification and remaining hardware check

- Release build to the regular `bin/Release/net10.0-windows` directory: zero warnings/errors.
- All self-tests passed in both the staging and final regular Release builds. Patch whitespace check is clean.
- No driver settings, Windows gesture settings, or Mac behavior were changed.
- Live cursor behavior of the corrected build still needs the user's check. Repeat staggered two-finger taps and normal two-finger movement, with full lift between cycles.

## Cycle comparison

Frame indices below are zero-based capture record indices. These are classifier outputs; the capture does not label user intent for each cycle.

| Cycle | First frame | Duration (ms) | Pointer calls before/after | Tap actions before/after | First movement frame before/after |
|---|---:|---:|---:|---:|---:|
| 0 | 0 | 4776.7 | 0/0 | 0/0 | -1/-1 |
| 1 | 293 | 3060.4 | 178/178 | 0/0 | 297/297 |
| 2 | 476 | 100.3 | 6/0 | 0/1 | 477/-1 |
| 3 | 485 | 528.1 | 19/19 | 0/0 | 498/498 |
| 4 | 519 | 99.6 | 0/0 | 1/1 | -1/-1 |
| 5 | 526 | 79.7 | 0/0 | 1/1 | -1/-1 |
| 6 | 533 | 121.9 | 7/0 | 0/1 | 534/-1 |
| 7 | 542 | 110.9 | 0/0 | 1/1 | -1/-1 |
| 8 | 550 | 123.8 | 0/0 | 1/1 | -1/-1 |
| 9 | 559 | 112.5 | 0/0 | 1/1 | -1/-1 |
| 10 | 568 | 101.5 | 0/0 | 1/1 | -1/-1 |
| 11 | 577 | 101.5 | 0/0 | 1/1 | -1/-1 |
| 12 | 585 | 103.7 | 0/0 | 1/1 | -1/-1 |
| 13 | 591 | 327.1 | 14/14 | 0/0 | 597/597 |
| 14 | 613 | 427.8 | 23/23 | 0/0 | 617/617 |
| 15 | 641 | 483.4 | 25/25 | 0/0 | 646/646 |
| 16 | 673 | 604.8 | 34/34 | 0/0 | 676/676 |
| 17 | 711 | 563.5 | 33/33 | 0/0 | 712/712 |
| 18 | 747 | 572.7 | 27/27 | 0/0 | 755/755 |
| 19 | 783 | 685.8 | 34/34 | 0/0 | 791/791 |
| 20 | 827 | 561.2 | 28/28 | 0/0 | 833/833 |
| 21 | 863 | 630.2 | 29/29 | 0/0 | 872/872 |
| 22 | 902 | 450.7 | 20/20 | 0/0 | 909/909 |
| 23 | 931 | 662.5 | 33/33 | 0/0 | 938/938 |
| 24 | 973 | 1292.9 | 77/77 | 0/0 | 974/974 |
| 25 | 1052 | 89.4 | 0/0 | 1/1 | -1/-1 |
