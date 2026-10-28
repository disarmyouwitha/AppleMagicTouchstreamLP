# Windows fallback: raw contacts + mouse-hook gate

Date: 2026-10-22. **Existing diagnostic; combined gesture-settings fallback unverified.**

## Approach we used

Keep Windows PTP enabled so GlassToKey continues receiving HID contacts through `WM_INPUT`. Install `WH_MOUSE_LL` using the existing [GlobalMouseClickSuppressor.cs](GlobalMouseClickSuppressor.cs). While the diagnostic movement gate is active, return nonzero for `WM_MOUSEMOVE` events without `LLMHF_INJECTED`. Pass injected movement through, allowing GlassToKey to generate its own output using `SendInput`. This intercepts downstream mouse delivery; Windows still receives and interprets the original trackpad contacts.

The gate follows the idea in [openMouse MouseGate](https://github.com/alstonmendonca/openMouse/blob/main/src/main.cpp). Microsoft documents [nonzero hook returns](https://learn.microsoft.com/en-us/windows/win32/winmsg/lowlevelmouseproc) and the [injected-event flag](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-msllhookstruct). This is separate from the later global PTP-disable test, which removed usable contacts.

## What the original test established

[Bluetooth gate log](../ptp-takeover-probe.log), 2026-10-21:

| Observation | Recorded result |
|---|---|
| Raw Apple reports | 885 report-0x05 / 50-byte frames; 394 during the gate |
| Hook-visible movement during gate | 119 events; gate code returns nonzero for non-injected movement |
| Wheel events during gate | 128 vertical, 4 horizontal; diagnostic passes these through |
| Synthetic move | SendInput returned 1; hook recorded injected flag and tag 0x47544B50 |
| Device metadata | Physical events had flags/extra-info zero; neither identifies the originating device |

Raw report arrival survived this gate. That older log did not record contact-slot payloads/counts, actual post-hook cursor position, or shell actions, so it does not independently prove full contact geometry, a frozen native cursor, or complete gesture suppression. Its two device entries were collections of one Bluetooth trackpad, not two physical trackpads. The logged zero HID usage was subsequently traced to a metadata sizing bug; actual usage is PTP 0D/05.

## Proposed fallback: user disables Windows gestures

This is worth testing as a limited fallback: retain the raw-contact path and mouse gate, while the user disables conflicting Windows actions in **Settings → Bluetooth & devices → Touchpad**. Microsoft documents [gesture customization there](https://support.microsoft.com/en-us/windows/hardware/input-devices/touch-gestures-for-windows).

- Set three/four-finger swipe and tap actions to **Nothing**, where offered.
- If GlassToKey owns scrolling, zooming, and tap-clicks too, disable the corresponding two-finger scrolling, pinch-to-zoom, and tap options where offered. Physical button clicks need separate handling.
- **Leave the main Touchpad switch on.** The tested global disable emptied our Bluetooth contact stream.

Hypothesis: disabling action bindings removes those native outputs while populated contacts remain available. That combination has not been hardware-tested. Do not assume settings are per-device; other touchpads may be affected. Record previous choices and restore them after exploratory testing. No settings were changed to prepare this note.

## Limits and next check

**The existing movement gate blocks all non-injected mouse movement, including an ordinary mouse.** Hook metadata supplies no reliable device identity, and correlating raw timestamps is not a proven attribution method. Disabling touchpad gestures does not solve this. Thus this fallback does not yet meet the final ordinary-mouse-independence requirement. Hook timeouts/removal also make it less reliable than exclusive ownership. Existing production click suppression uses a separate recent-button-edge heuristic; it is not a verified per-device takeover mechanism.

The useful next Bluetooth test would verify actual cursor position, populated contact geometry/counts, synthetic output, and scroll/click/shell behavior with gesture bindings disabled. Keep the established Escape release, ten-second gate, 25-second total duration, deadline checks, and fail-open disposal. No production change is proposed.

## Existing diagnostic entry point

Implemented in [PtpTakeoverDiagnostic.cs](PtpTakeoverDiagnostic.cs). After building Release, run from `windows_linux`:

```powershell
$log = Join-Path $PWD ("ptp-movement-{0}.log" -f (Get-Date -Format yyyyMMdd-HHmmss-fff))
& .\GlassToKey.Windows\bin\Release\net10.0-windows\GlassToKey.Windows.exe --ptp-diagnostic $log --ptp-movement-gate
```

It starts immediately: gate at 5 seconds, one synthetic move at 8 seconds, release at 15 seconds, exit at 25 seconds; Escape exits early. It does not change gesture settings or run the typing engine. This command reproduces the existing movement-only experiment; it is not a completed implementation of the combined fallback.

For other investigated leads and their access barriers, see the [research checkpoint](WINDOWS_APPLE_DRIVER_GHIDRA_FINDINGS.md#research-checkpoint-for-return-to-bluetooth).

## Mouse Takeover interactive test (2026-10-22)

The user accepted all-physical-mouse suppression as a possible compromise and requested a keyboard release and status UI. A separate opt-in test window is now available; it does not enable takeover in normal production startup or persist a setting.

```powershell
.\GlassToKey.Windows\WindowsDiagnostics\Run-MouseTakeoverTest.ps1
```

This builds into the isolated `bin/MouseTakeoverTestV2` directory and opens an unchecked **Mouse Takeover** checkbox, **30sec test** button, release button, status/countdown, raw/contact-count counters, and hook-event counters. Both the checkbox and test button arm for at most 30 seconds; expiry unchecks the box. Physical movement/buttons/wheel from all mice are blocked while injected input passes. A tagged 20-pixel synthetic move occurs five seconds into each activation. No Windows gesture setting is changed.

Release is **Ctrl+Alt+F10 globally**, or **Escape**. The tool refuses to arm if the global shortcut cannot be registered, and refuses activation while a physical mouse button is already held. The hook itself checks its deadline and emergency keys; an independent thread-pool timer also releases the gate. Closing/exiting releases it. A stale timer cannot release a newer activation. The UI remains topmost during the test and clearly indicates release afterward. Hook installation/status is not proof of OS-wide suppression; verify the observed behavior.

Suggested manual checks:

1. Verify normal pointer operation before activating; confirm raw frames arrive while touching.
2. Start a short activation and verify Ctrl+Alt+F10 releases immediately, then Escape on another activation.
3. Run a full 30 seconds: verify physical movement, scrolling, and clicks stop; watch the contact counters; verify the small synthetic jump at five seconds and automatic release/uncheck.
4. Try three/four-finger shell gestures separately. Record any remaining action; Windows gesture bindings remain enabled unless the user separately changes them. If testing disabled bindings, record and restore the previous choices.
5. If the ordinary GlassToKey engine is already running in its separate process, verify typing, haptics, and injected dragging independently. This test window itself does not run that engine.

Logs `mouse-takeover-test-*.log` record activation/release reasons, per-device raw payloads/counts, hook flags/extra info, sampled actual cursor positions, and synthetic send/after-position. Diagnostic queues/payload logging are bounded. Automated tests cover unarmed behavior, injected pass-through, exact expiry, explicit/emergency release, stale watchdogs, and invalid durations. Hardware validation remains pending; permanent-mode UI integration should follow a successful test.

### Hotkey startup fix

The first interactive launch refused activation because RegisterHotKey returned 1409 for Ctrl+Alt+F12. Windows reserves F12 for debuggers, as documented in [RegisterHotKey](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerhotkey). This was a test implementation error, not evidence that the mouse hook failed. The test now tries Ctrl+Alt+F10, then F9/F8 if occupied; the window displays/logs the actual registered shortcut. Escape remains an independent release. Controls stay disabled until initialization succeeds, and startup faults are shown in red. A direct temporary registration probe confirmed Ctrl+Alt+F10 works on this host and unregistered it immediately. The launcher uses a fresh V2 output directory because an old test process held the previous executable open.

The corrected V2 build completed with zero warnings/errors and all self-tests passed. The requested window was opened with takeover OFF; `mouse-takeover-test-20261022-162351-171.log` records `READY release=Ctrl+Alt+F10,Escape durationLimit=30s`, followed by populated Bluetooth Apple Col02 reports with `gate=False`. Thus actual hotkey/hook/Raw Input initialization is now verified, not merely compilation. Activation/release behavior remains the user's next physical check.

## Hardware result: Apple Bluetooth, 16:23 local

**Movement gate + populated contacts + synthetic movement succeeded in this run.** [Preserved log through release](WindowsDiagnostics/mouse-takeover-evidence-20261022/mouse-takeover-162351-through-release.log), [phase/count analysis](WindowsDiagnostics/mouse-takeover-20261022-162351-summary.json).

- Takeover ON at t=5.602; UI records release at t=35.689, 30.087 seconds later, consistent with the 30-second deadline plus UI polling.
- 1,206 raw Apple Col02 reports while the gate was active; 1,193 have nonzero reported contact count. Counts range from one to five, with changing coordinates and pressure bytes. Reports span activation+0.006 s through activation+29.975 s.
- The largest inter-frame gap is 4.881 s, between activation+24.991 and +29.872 s. The preceding Apple slot has release lifecycle 0x01, ID8; the next has active lifecycle 0x03, ID9. This is consistent with lifting/replacing a finger, not proof of continuous touching or a driver stall. The log therefore proves retained populated contacts during takeover, not an uninterrupted stream under continuous touch for every instant.
- Hook recorded 451 non-injected movement and 362 wheel events during takeover; one injected move passed. Actual cursor samples remain (-1218,483) before the synthetic move and (-1153,483) afterward, with no other sampled displacement. SendInput returned 1/error0; the user also saw the jump. The requested relative delta was 20; observed screen displacement was 65 pixels, so do not label this a measured 20-pixel screen jump.
- No button events were recorded. Native click suppression, visible scroll outcome, shell gestures, emergency keyboard release, the normal GlassToKey engine's typing/haptics/dragging, two-trackpad behavior, and long-running reliability are not established by this log. The sampled cursor result is not a per-event screen recording.

This is evidence for the user-accepted all-physical-mouse fallback, not per-device FLTR ownership. No Windows gesture settings or device configuration were changed. Keep the permanent production checkbox pending the remaining release/output checks.
