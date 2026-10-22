# Apple Windows trackpad filters: Ghidra and REA findings

Date: 2026-10-22. Status: **Apple 6.1.8000.6 binaries inspected; the controlled Bluetooth global-toggle test failed contact preservation; exclusive takeover unproven**. Static analysis was read-only with respect to hardware and Windows settings. The separately documented hardware probe temporarily toggled Windows PTP and restored it. No undocumented feature report or IOCTL was sent.

This report addresses a narrow question: can an existing Apple Windows driver suppress native pointer, scroll, click, and shell gesture interpretation for a selected Magic Trackpad while GlassToKey continues to receive populated contacts? No verified driverless takeover has been found. The controlled Bluetooth global-toggle probe stops native movement/wheel events but removes usable contacts. The follow-up investigation corrected a Raw Input metadata bug, mapped the actual collections, inspected both installed open-source binaries, and traced selected Windows input-routing functions. The latest pass rules out direct PT_TOUCHPAD redirection on this build and traces the per-device setter to injection-device machinery. A newly identified Windows mouse-interception path suppresses gesture starts and shell actions, but access requires the session input thread; the inspected callback-registration path requires DWM process identity. It is not an available normal-app takeover route. No usable takeover mechanism has been verified.

**Correction to earlier reports:** the captured `usage=0x00/0x00` values came from GlassToKey's failed device-info query and fallback. A correct query and independent HID capability query identify the Apple report stream as **Digitizer / Touch Pad (`0x0D/0x05`)**. The `0x05` report is not demonstrated to be a separate vendor raw stream. This correction does not change the measured 407 empty frames during suppression.


## Current decision: close open-source USB testing

The user requested returning to the preferred official Apple Bluetooth setup after the controlled USB tests. The direct-read test also returned zero vendor reports during instructed finger movement. No independently populated contact source or takeover mechanism was found on the tested USB stack. **Do not request more open-source USB tests or change its binding on this evidence.** The dated sections below retain the investigation history; earlier “next test” wording is superseded by the completed results and closure at the end. Returning to Bluetooth requires disconnecting the USB data cable and using the existing pairing, not installing/replacing a driver. The previously captured Bluetooth stack included an Apple parent and open-source child filter; “preferred Apple Bluetooth setup” must not be taken as a fresh verification of an Apple-only stack.

## Research checkpoint for return to Bluetooth

Updated after the 15:50 USB test on 2026-10-22. This is the current evidence summary; build-specific addresses, hashes, source pins, and detailed logs follow. **No driverless FLTR-equivalent takeover is verified.**

| Interesting finding | Evidence level | Consequence for GlassToKey |
|---|---|---|
| Apparent Apple usage 00/00 was a 24-byte RID_DEVICE_INFO sizing failure; correct native structure size is 32 bytes | Live metadata + independent HID capabilities | Apple 0x05/50-byte stream is PTP 0D/05, not a proven independent vendor channel. Preserve packing selection when fixing metadata. |
| Global Bluetooth PTP disable retained frame timing but removed contacts | Controlled hardware: 407 confirmed-disabled frames had empty slots | Suppression worked for observed native movement/wheel events, but this stream cannot drive GlassToKey during disable. Do not repeat without a new data source. |
| Mouse-hook event flags/extra info do not identify a trackpad | Recorded physical events had zero flags/extra info; injected event was tagged | WH_MOUSE_LL remains useful instrumentation, but cannot establish selective device takeover from those fields. |
| Apple surface-reporting control gates the same converted contacts the app needs | USB/BT binary and matching descriptor analysis | No found Apple private switch independently disables only Windows interpretation. Do not send guessed reports. |
| Windows MIT interception skips PTP gesture starts and shell actions | Static Windows decompilation | Real suppression machinery exists, but inspected callback registration requires DWM identity and enable requires the session input thread. Not a normal-app route. |
| Pointer redirection accepts touch/pen, rejects touchpad type 5 on this build | Static accepted-type/assembly check | UIAccess does not make the inspected direct PT_TOUCHPAD registration viable. |
| Per-device engine properties can be read normally | All eight selectors read on both Bluetooth collections | Geometry/AAP/GestureOnly fields are real; the inspected setter requires injection-device state. Getter success is not physical-device write permission. |
| Open-source USB stack exposes separate vendor HID functions | Live metadata/PnP: MI_03 input108/reportC0, MI_02 input16/report3F | They are accessible read-only but not demonstrated contact mirrors. |
| Vendor channels returned no data through either observation route tested | Controlled Raw Input: 1,747 PTP frames, zero vendor; direct reads: zero on both channels during instructed touches | Close the open-source USB testing branch. Descriptor capacity/open success did not translate into usable original contacts. |
| WinUSB project bypasses the PTP conversion boundary through USB interface rebinding | External source analysis; not run | Valuable wire-protocol reference, but persistent setup/admin burden is disfavored and Bluetooth is unsupported. No rebinding was attempted. |

### Bluetooth continuation notes

- User preference: return to the existing official Apple Bluetooth setup; keep open-source USB testing closed. No USB rebind, Zadig setup, custom driver, or security change is authorized by that preference.
- First re-check the actual active Bluetooth topology using read-only enumeration after transport changes. Earlier evidence showed an Apple parent and an open-source child filter; do not describe that historical stack as Apple-only. Distinguish two collections from two physical trackpads.
- Reuse OFFICIAL_PTP_SPEC.md for the empirically validated Apple packing, while retaining its corrected usage/metadata note. The open-source USB 50-byte packet and the official Apple 50-byte packet have different slot interpretations.
- Remaining research question: an existing app-readable original-contact path or an existing app-accessible interpretation control. Neither has been found. Static inspection of actual Bluetooth descriptors/interfaces may narrow this; no additional finger test is presently requested.
- Native shell gestures/clicks, retained full geometry/pressure, synthesized output, two physical devices, ordinary-mouse independence, and USB/BT acceptance remain separate final requirements. Do not turn the diagnostics into production takeover behavior.

### Evidence preservation

The three decisive USB logs have been copied into [WindowsDiagnostics/usb-research-captures-20261022](WindowsDiagnostics/usb-research-captures-20261022/manifest.json). The manifest records file size and SHA-256 for reproducibility. Original logs remain at the workspace root. The PnP/capability snapshots, phase-count JSON, and diagnostic scripts are also stored under WindowsDiagnostics. No driver binaries or Windows settings were modified.

## Scope and provenance

| Item | Observation |
|---|---|
| USB filter | `ApplePrecisionTrackpadUSB.sys`, 37,784 bytes, file version `6.1.8000.6`, SHA-256 `944447638112D32AF6FC2CDB4E47BFB75871600B7CDE97DADE3606C22B6AD4A1` |
| Bluetooth filter | `ApplePrecisionTrackpadBluetooth.sys`, 41,896 bytes, file version `6.1.8000.6`, SHA-256 `A589ABCB198326D84F1310FC8A5D9A9A5A2F4D219A55B15181FEEBA9E6893B92` |
| Source | Local `windows_linux/ApplePrecisionTrackpad_amd64.USB-C/` package; hashes match the copies in the Windows DriverStore previously enumerated read-only. Apple USB was staged but not connected in the initial binary-analysis tests; the later live USB tests used the open-source UMDF binding, documented below. |
| Installed stack | Connected Bluetooth `PID_0324` parent uses Apple `oem94.inf`; its `Col01` child uses open-source `oem149.inf` version `2025.3980.1.1000`. This is a mixed stack, so behavior cannot be assigned to the Apple filter alone. |
| Tools | Ghidra `12.1.4`, portable Node `24.11.0`, REA `6.7.0`, existing Temurin JDK `21.0.5`. The Ghidra and Node downloads were verified against publisher SHA-256 values before extraction. REA `doctor --provider ghidra` passed all Ghidra checks, including its Windows native controls. |
| Artifacts | Persistent Ghidra project: `%TEMP%\glasstokey-re-tools\projects\AppleTrackpadWindows.gpr`. Text decompilation inventories: `%TEMP%\glasstokey-re-tools\ApplePrecisionTrackpadUSB.sys.analysis.txt` and `ApplePrecisionTrackpadBluetooth.sys.analysis.txt`. REA overview JSON and snapshots are in the same Temp directory. |

The INFs install these binaries as `LowerFilters` on HID devices. The USB INF targets `VID_05AC&PID_0265&MI_01` and several other IDs, but does **not** list `PID_0324`; the Bluetooth INF lists `VID_004C&PID_0265`, but does **not** list `PID_0324`. The observed `PID_0324` binding is therefore a host-specific manual or compatible binding, not proof that the package supports that ID through its INF match list. The USB INF also writes global PrecisionTouchPad `SuperCurtain*` values **at installation**. We did not run any installer or change those values. Neither INF advertises a separate Apple user-mode control interface.

The decompiler has no Apple PDBs, so its `FUN_...` names and inferred parameter types are provisional. Addresses below are Ghidra virtual addresses for these exact hashes, not stable APIs. The source referenced by each address is recoverable with [ExportAppleDriver.java](WindowsDiagnostics/Ghidra/ExportAppleDriver.java). [SummarizeAppleHidDescriptor.py](WindowsDiagnostics/Ghidra/SummarizeAppleHidDescriptor.py) independently parses the embedded HID descriptor bytes from the PE files. Neither script opens a device.

### Exports, imports, strings, and installation surface

Neither PE has a user-mode callable export. The string and import inventories show the expected kernel/WDF dependencies (`ntoskrnl.exe`, `WDFLDR.SYS`, `WdfVersionBind`, `WdfVersionBindClass`, WPP/ETW tracing); Bluetooth additionally references allocation and mapped-page routines used by its transport path. The distinctive readable strings are context names such as `HDEVICE_CONTEXT` on USB and `DEVICE_CONTEXT` / `CONTROL_CHANNEL_REQUEST_CONTEXT` on Bluetooth, WDF/WPP names, and Boot Camp version resources. A readable private device-interface name or user-mode API contract did not emerge from these inventories. Absence of a string is weak evidence because a GUID or protocol can be stored only as binary data.

The [USB INF](../ApplePrecisionTrackpad_amd64.USB-C/ApplePrecisionTrackpadUSB/ApplePrecisionTrackpadUSB.inf) registers `ApplePrecisionTrackpadUSB` as a HID lower filter and also installs Microsoft `mshidkmdf`; the [Bluetooth INF](../ApplePrecisionTrackpad_amd64.USB-C/ApplePrecisionTrackpadBluetooth/ApplePrecisionTrackpadBluetooth.inf) includes `hidbth.inf` and registers `ApplePrecisionTrackpadBluetooth` as a HID lower filter. Neither INF has an `AddInterface` registration or a documented app-facing control service. This is useful for narrowing the search, but it does not rule out a control surface created dynamically by code.

## Most useful entry points

| USB address | Bluetooth address | What the code shows | Takeover relevance |
|---|---|---|---|
| `0x140001db8` | `0x140001bb0` | Converts incoming Apple packets into a zero-initialized output report with byte 0 set to `0x05`; successful touch conversions set output length `0x32` (50 bytes). Recognized source packet leads include `0x31`, `0x74` (`'t'`), and `0x75` (`'u'`). | Establishes that Apple’s filter **creates** the `0x05` stream consumed above it. This is an input path, not a takeover control. |
| `0x140001710`, `0x1400018a4`, `0x140001a48` | `0x140001494`, `0x140001650`, `0x140001818` | Parse source packet families into contact slots and button state. The `0x74` path caps contact processing at five, iterates the source contacts, and fills the 50-byte report. | Shows where contact inclusion is gated. See feature report `0x06` below. |
| `0x140001f3c` | `0x140001d38` | Unpacks individual contact geometry and pressure from Apple wire bytes. | Useful for comparing the official `0x05` decoder with Apple’s own conversion, but not a suppression path. |
| `0x140003390` | No direct equivalent identified; Bluetooth uses a different transport path. | USB internal HID request dispatcher with recognized codes listed below. | Search point for a private IOCTL. All recognized USB codes found so far are standard HID codes. |
| `0x140002a28` | Bluetooth feature handling appears within `0x140003e50` and its callers. | USB `SET_FEATURE` handling for report IDs `0x04` and `0x06`. Bluetooth has matching mode and selective-reporting state in its context. | The only concrete Apple configuration path found. It gates contacts or buttons in the same outgoing report; it does not expose a separate native-interpreter switch. |
| `0x140004010` | `0x140003230` | USB read completion / Bluetooth response path invokes the `0x05` conversion and completes the upper request. | Follow this path to identify exactly which HID collection receives converted frames. |
| Embedded descriptor RVA `0x6040` | Embedded descriptor RVA `0x73c0` | Identical 835-byte HID report descriptors in the two binaries. Bluetooth copies its descriptor into its transport descriptor; USB returns its descriptor for HID requests. | Strong evidence that USB and Bluetooth use the same exposed report layout, though their lower transports differ. |

### The `0x05` report is in the embedded touchpad collection

The two embedded descriptors are byte-for-byte identical in the inspected binaries. The parser reports:

| Top-level HID collection | Reports observed | Input size in descriptor |
|---|---|---|
| Generic Desktop Mouse, usage `0x01/0x02` | `0x02` | 56 bits |
| Digitizer Touch Pad, usage `0x0D/0x05` | `0x05`, `0x07`, `0x08` | Report `0x05`: 392 data bits, i.e. 49 data bytes plus one report-ID byte = **50 bytes** |
| Digitizer Device Configuration, usage `0x0D/0x0E` | `0x04`, `0x06` | Feature/configuration reports; no input bits |

This matches the report ID and length in [OFFICIAL_PTP_SPEC.md](OFFICIAL_PTP_SPEC.md). The follow-up live metadata query below reconciles the earlier apparent discrepancy: `0x00/0x00` was a fallback after an undersized interop query failed. Both live input collections identify as `0x0D/0x05`. The Apple auxiliary friendly name does not make its collection vendor-specific or independent of Windows' PTP interpreter.

### Apple feature reports and why they are not takeover

For USB, the dispatcher at `0x140003390` routes standard `IOCTL_HID_SET_FEATURE` (`0xB0191`) to `0x140002a28`. The feature code distinguishes:

- **Report `0x04`, input mode:** accepted mode byte `0` or `3` is mapped to an internal Boolean and compared with / written to Apple feature report `0x02` by `0x140001000`, `0x1400012ec`, and `0x1400014e8`. The Boolean is also checked when handling incoming report `0x02`. The decompilation does not establish a mode where Apple stops only native gestures while continuing an independent contact stream.
- **Report `0x06`, selective reporting:** the two low bits of its data byte are saved as separate flags. USB writes context offsets `+0x4D` (button bit) and `+0x4E` (surface/contact bit); Bluetooth writes `+0x769` and `+0x76A`. These fields are **read** in the contact parsers (`USB 0x140001710/0x1400018a4/0x140001a48`; Bluetooth counterparts above). If the surface bit is zero, those parsers skip adding contacts to the outgoing `0x05` report. The button bit controls whether a button press is included. Thus a report can still arrive with zero contact slots, which is exactly why arrival counts alone are insufficient evidence for GlassToKey takeover.

These are normal PTP configuration controls driven through HID, not a discovered private FLTR equivalent. They might explain the previously observed zero-contact frames during the Windows touchpad-disabled interval, **but that causal link is only a hypothesis**. We did not observe feature traffic, and we did not send a feature report. Turning surface reporting off intentionally would defeat GlassToKey’s contact capture even if native gestures stopped. Button-only suppression would leave native movement, scrolling, and gestures.

The installed open-source driver is a separate layer. In its matching [v2.0 `Hid.c`](https://github.com/vitoplantamura/MagicTrackpad2ForWindows/blob/v2.0/AmtPtpHidFilter/Hid.c), `PtpInputOn`, `PtpReportTouch`, and `PtpReportButton` are written but have no source-wide read references. This does **not** mean Apple’s similarly named concepts are inert: the Apple binaries demonstrably read their context flags when constructing contacts.

### Internal request surface

USB `0x140003390` compares only these internal HID request codes in its visible switch/branch tree:

| Code | Windows HID meaning |
|---|---|
| `0xB0003`, `0xB0007`, `0xB000B`, `0xB000F`, `0xB0013` | Get device descriptor, get report descriptor, read report, write report, get string |
| `0xB001F`, `0xB0023`, `0xB0027`, `0xB002B` | Activate, deactivate, get device attributes, idle notification |
| `0xB0191`, `0xB0192` | Set feature, get feature |

Those mappings come from the locally installed Windows SDK `hidport.h` and `hidclass.h` macros. The code falls through with an error for other values; this is evidence against an **obvious** private IOCTL in that dispatcher, not proof that no other path exists. Neither Apple binary exports a callable control API. The Bluetooth binary also handles lower Bluetooth control-channel and descriptor traffic, but the inspected INF/strings/decompilation did not reveal a user-mode takeover device interface or a safe command with the desired semantics. The Bluetooth code deserves further review if the global toggle test fails; we should not infer an undocumented command from a raw byte constant.

## Controlled Bluetooth result: 2026-10-22, 13:37 local

Evidence: [capture](../ptp-toggle-20261022-133717-030.log) and [restore watchdog](../ptp-toggle-20261022-133717-030.log.watchdog.log). The user ran the guided launcher and reported that the test looked and felt good. The run enabled the toggle mode, detected active contacts before switching, observed `enabled=False` at second 5.13, sent restoration at approximately second 15.1, and observed `enabled=True` at second 15.14. The watchdog subsequently confirmed enabled state. The log still identifies one Bluetooth physical device with two enumerated collection paths, not two separately tested trackpads.

| Interval, bounded by log events | Raw frames | Positive contact counts | Nonzero contact-slot payloads | Non-injected movement / vertical wheel events |
|---|---:|---:|---:|---|
| Before `OS_TOGGLE_OFF` | 240 | 234 | 234 | 98 / 110 |
| Off command to first disabled status | 5 | 1 | 1 | 0 / 0 |
| Confirmed disabled status to `OS_RESTORE` | **407** | **0** | **0** | **0 / 0** |
| Restore command to first enabled status | 3 | 3 | 3 | 0 / 0 |
| After enabled status | 331 | 324 | 324 | 142 / 156 |

All 407 frames in the confirmed disabled interval have zero contact count at byte 48 and zero bytes throughout the five contact slots (bytes 1–45). Their scan-time fields continue changing: 407 distinct values. The raw transport is therefore alive, but it supplies no contact geometry for the engine. The sole hook event inside this interval is the tagged injected move (`flags=0x00000001`, `extra=0x47544B50`); cursor polling confirms the move from `(-362,414)` to `(-298,414)`. No non-injected mouse event was logged in that interval.

**The three positive frames summarized as `osEnabled=False` are not evidence of preserved contacts.** All three occur after the `OS_RESTORE` command and before the next 50-ms status poll updates the cached label. They each contain two contacts. For this capture, sequence boundaries around the commands and status observations are more informative than grouping solely by the cached `osEnabled` field. The same polling lag briefly labels empty frames as enabled after the off command.

**Result:** native movement/wheel suppression, synthetic movement, and restoration worked; preserving usable contacts failed in the tested Bluetooth stack. This does not establish USB behavior or an alternative per-device route. Shell actions and click suppression were not independently measured; the user's general positive observation does not specify which gestures were attempted. The pattern is consistent with the Apple surface-reporting gate found in static analysis, but the particular feature traffic responsible was not captured. Keep the global toggle out of the production takeover path.

## What is proven, and what remains a hypothesis

The follow-up sections below update the original PnP-child isolation hypothesis and identify the remaining Windows routing candidates.

| Technique | Privileges | USB / Bluetooth | Populated raw contacts while suppressed | Native pointer / scroll / gestures | Ordinary mouse | Current judgment |
|---|---|---|---|---|---|---|
| `WH_MOUSE_LL` movement gate | User | Hook is transport-neutral | `0x05` frames arrived during the Bluetooth probe; contacts were not its suppression target | Hook-visible moves can be swallowed; wheel and shell gestures were not blocked by this gate | Physical mouse motion also blocked | Diagnostic only, never final takeover. |
| Windows Ctrl+Win+F24 PTP toggle | User on this host | Bluetooth tested; USB untested | **Failed in the controlled Bluetooth run:** 407/407 frames before restore had empty slots. Three positive frames with a stale disabled label arrived after restore. | No native move/wheel events during confirmed disabled interval; injected move changed cursor position. Shell gestures/clicks not independently confirmed. | Expected independent, not tested with an ordinary mouse | Does not satisfy takeover on this Bluetooth stream. It also affects every PTP device, including the built-in Dell pad. |
| Apple feature report `0x06` surface off | HID access / driver ownership unknown | Present in both inspected binaries | **No in the decoded `0x05` path:** Apple parsers skip contacts when the surface flag is off | Could reduce native touch behavior; not hardware tested and cannot satisfy full contact capture | Likely unaffected | Source-level dead end for exclusive interpretation. Do not send speculative reports. |
| Apple feature report `0x06` button off | HID access / driver ownership unknown | Present in both | Contacts plausibly continue | Click only; native movement/scroll/gestures remain | Likely unaffected | Possible narrow click control, not takeover. Untested. |
| Apple report `0x04` input mode | HID access / driver ownership unknown | Present in both | Unknown and likely at risk | Unknown | Likely unaffected | No evidence of a mode that separates app contacts from Windows interpretation. Do not send speculative reports. |
| Private Apple user-mode control | Unknown | No candidate identified | Unknown | Unknown | Unknown | No interface/IOCTL with takeover semantics found in these binaries; negative result is bounded by missing PDBs and incomplete data-flow tracing. |
| Disable only the open-source PTP child devnode | Usually administrator | This host's Bluetooth topology only | Apple sibling would be a separate devnode, but is itself PTP | Not established: the Apple sibling remains an interpreted PTP input collection | Other mice would be unaffected | Corrected topology gives no basis for treating the open-source child as the sole interpreter path. Disabling Apple's reporting child would also remove the path GlassToKey reads. Do not change devnode state. |

The macOS mechanism in [TRACKPAD_TAKEOVER.md](../../mac/gesturepad/TRACKPAD_TAKEOVER.md) is a filter-client routing choice in the native Apple macOS driver. No equivalent routing choice was found in these Windows Apple binaries. A Windows feature report that merely tells the device/driver to stop reporting touch does not reproduce FLTR.

## Reproducing the controlled capture; USB remains untested

The already built diagnostic is isolated from the normal typing engine, lasts 25 seconds, requires an actual positive-contact frame before toggling, restores the PTP setting ten seconds later, and starts a separate restore watchdog. It does not install a driver, change a devnode, or save application settings. Run from `windows_linux`:

```powershell
.\GlassToKey.Windows\WindowsDiagnostics\Run-PtpToggleProbe.ps1
```

The launcher waits for Enter, supplies the toggle argument, shows progress and status events, and saves a uniquely named `ptp-toggle-*.log` in `windows_linux`. It surfaces startup errors and rejects a run that reports `osToggle=False`. For a passive 25-second capture, use `-ObserveOnly`; that mode does not test suppression. The earlier `ptp-os-toggle-controlled.log` ran for 25 seconds but recorded `osToggle=False`, so it provides no evidence about contacts during suppression. The missing toggle argument in that run has not been explained; the parser accepts it correctly in isolation.

For the **Bluetooth** run, begin touching the Magic Trackpad before second 5. Keep at least one finger continuously on it and moving through the entire ten-second disabled interval. During that interval, also attempt a two-finger scroll and a three- or four-finger Windows shell gesture, and note whether the cursor, page, or shell actually responds. Press **Escape** to restore early if necessary. The program skips the toggle if it never sees a positive contact in the trigger window. Repeat separately with **USB** attached when available, without changing its driver binding. A normal mouse is useful later for independent-operation acceptance, but the test needs only the trackpad and keyboard.

**Pass criterion for a possible global-toggle approach:** the log shows positive contact counts and nonzero contact-slot payload continuously while `osEnabled=false`; the native cursor, scrolling, clicks, and shell gestures do not act; tagged `SendInput` still moves the cursor; state is restored. If contacts go to zero despite continuous touch, the global toggle cannot serve as GlassToKey takeover for this stream. Even if it passes, its system-wide PTP scope means we would still need a per-device route or an explicit product decision before changing production behavior.

The read-only collection mapping and installed-filter inspection have now been completed to the extent described below. No repeat of the same Bluetooth test is needed to establish that this capture fails the preservation criterion. USB still needs separate validation when available. The next static targets are Windows pointer redirection and the per-device output-configuration path. Do not disable devnodes, modify bindings, or send undocumented Bluetooth/HID commands to guess.

## Follow-up: the zero-usage metadata was an interop failure

[Read-RawInputMetadata.ps1](WindowsDiagnostics/Read-RawInputMetadata.ps1) independently enumerates Raw Input handles and reads metadata. It does not register an input sink, open a hardware device, read reports, or change any setting. The saved [metadata snapshot](WindowsDiagnostics/raw-input-metadata-20261022.json) contains the complete results and HID value capabilities.

GlassToKey's `RawInputInterop.RID_DEVICE_INFO` declares an explicit union containing only the 16-byte HID member. This makes its managed size **24 bytes**: an eight-byte header plus the HID member. The Windows union also contains a 24-byte keyboard member, so the actual native structure is **32 bytes**. The existing code passes its managed size for both `cbSize` and the buffer length.

The independent probe tested both sizes against the same live handles, using a safely allocated 32-byte buffer even for the legacy-size query:

| Query | Result on both PTP input handles |
|---|---|
| `cbSize=24`, buffer length 24 | Return `0xFFFFFFFF`, Win32 error **122**, required size **32** |
| `cbSize=32`, buffer length 32 | Return **32**, error **0**, type `RIM_TYPEHID` |
| `RIDI_PREPARSEDDATA` followed by `HidP_GetCaps` | Independently confirms usage page `0x0D`, usage `0x05`, input report length 50 |

When GlassToKey's query fails, its device-path VID/PID fallback leaves usage fields zero. Consequently the earlier log label was never evidence that the Windows API successfully returned a vendor-specific usage. The corrected live values are:

| Collection suffix | VID / PID | Actual usage | Input length | Input value capabilities |
|---|---|---|---:|---|
| `Col01&Col01` under the open-source filter | `8910 / 0324` | `0D / 05` | 50 | 32-bit contact ID; X `0..7612`; Y `0..5065`; 17 input value capabilities |
| Apple sibling `Col02`, which supplies GlassToKey's captured frames | `004C / 0324` | `0D / 05` | 50 | 16-bit contact ID; X `0..15225`; Y `0..10130`; 16-bit Digitizer pressure `0..2000`; 22 input value capabilities |

These differences also demonstrate that usage alone does not select the report packing. **Do not fix the production structure in isolation.** `TrackpadReportDecoder.NormalizeOfficialTouchFields` currently selects Apple's custom packing when the usage is not native PTP. Correcting metadata alone would change that branch and could break working typing/force decoding. A subsequent production fix must separate actual device metadata from report-format selection, preserve the existing Apple byte mapping, and verify it against saved captures. No production decoder or metadata behavior was changed in this research pass. The empirically observed byte layout in `OFFICIAL_PTP_SPEC.md` remains useful; its old usage classification needs the correction above.

Windows references: [RID_DEVICE_INFO union](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-rid_device_info), [keyboard union member](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-rid_device_info_keyboard), and [GetRawInputDeviceInfo sizing contract](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getrawinputdeviceinfoa).

## Follow-up: actual installed collection routing

[Read-TrackpadPnpTopology.ps1](WindowsDiagnostics/Read-TrackpadPnpTopology.ps1) saves parent, driver, service, filter, and hardware-ID properties without changing devices. The sandbox denied the initial PnP read; the same read-only exploration was then run with approved host access. The [topology snapshot](WindowsDiagnostics/trackpad-pnp-topology-20261022.json) records:

```text
Bluetooth HID parent: HidBth + ApplePrecisionTrackpadBluetooth lower filter, oem94.inf
  Col01: mshidkmdf + AmtPtpHidFilter lower filter, oem149.inf
    Col01&Col01: HID-compliant touch pad, input.inf, actual usage 0D/05
    Col01&Col02: Microsoft Input Configuration Device, MTConfig
  Col02: Apple Multi-touch Auxiliary Services, oem149.inf, no function service
         actual usage 0D/05; source of the captured Apple 0x05 frames
  Col03: Microsoft Input Configuration Device, MTConfig
```

The open-source INF's `NullDevice` section assigns no function service to Apple's `Col02`, but this is **not** the same as disabling the devnode or preventing RIM from consuming its PTP collection. The live metadata identifies that sibling as PTP, and the capture confirms it supplies input. A friendly name and an empty `Service` property do not establish an interpreter-free channel.

This substantially weakens the earlier suggestion to disable only `Col01&Col01`: doing so would not, by itself, remove Apple's PTP sibling. Conversely, disabling the Apple `Col02` path would target the same collection GlassToKey reads. No devnode was disabled to test either possibility, and no such experiment is recommended on the current evidence.

Microsoft documents that RIM opens PTP collections exclusively; a zero-access metadata handle may still be opened, but that is not a supported way to acquire input ownership from Windows. See [HID architecture and exclusive client access](https://learn.microsoft.com/en-us/windows-hardware/drivers/hid/hid-architecture). Raw Input observation does not itself transfer ownership.

## Follow-up: installed open-source binaries and pinned source

Both installed package binaries were imported and decompiled in the existing Ghidra project:

The key installed KMDF control/feature/dispatch decompilations are preserved in [the control evidence excerpt](WindowsDiagnostics/Ghidra/Evidence/AmtPtpHidFilter-control-excerpts.txt), rather than depending only on Temp artifacts.

| Binary | Bytes | SHA-256 |
|---|---:|---|
| `AmtPtpHidFilter.sys` | 50,400 | `CAFDBD374E705A314DDF5C4EF638235227C92AE9D74985028073F2AAC11C522C` |
| `AmtPtpDeviceUsbUm.dll` | 68,936 | `28050D0D9A4CA86D2B7B593848E6BCB8B2B488FA192BBF9833E29875C782BA55` |

Source comparison was pinned to upstream **v2.0**, commit `6a308eccf6ae4fbc3cdcf267c3a525b4818824e3`, cloned read-only into `%TEMP%\glasstokey-driver-v2`. Its INF version matches installed `2025.3980.1.1000`; that is not a claim that the source was reproduced into an identical binary. The previously downloaded `%TEMP%\glasstokey-driver-src` is newer source (`2026.3982.1.1000`) and must not be presented as the installed version. The binary inspection independently confirms the important control-dispatch behavior.

| Installed KMDF address | Observation | Consequence |
|---|---|---|
| `0x1400059d0` | User control dispatcher recognizes only `0x222000` (settings reload) and `0x222004` (battery); other codes take an invalid-request path. | A real existing control surface exists, but no takeover command was found there. |
| `0x140003f0c` | HID feature handler stores input mode and selective-reporting flags at context offsets `+0x70`, `+0x71`, `+0x72`. | Corresponds to v2.0 source fields `PtpInputOn`, `PtpReportTouch`, `PtpReportButton`; source-wide reads of those fields were not found. |
| `0x140004ff0` | Internal HID dispatcher routes standard descriptor/read/feature requests. | No app contact-mirror or exclusive-interpreter command identified in that dispatcher. |
| `0x14000314c` | Settings-load path called by reload. | Settings relate to button/pressure/size/palm filtering and haptics, not an app-owned raw stream. |

The source control name is `\\.\AmtPtpControlDeviceUm`; its creation uses an administrators/system security descriptor, and its settings target driver context / the first device rather than an app-selected per-device takeover session. Reload also applies haptic settings. No reload or battery IOCTL was sent in this pass. See pinned [ControlDevice.c](https://github.com/vitoplantamura/MagicTrackpad2ForWindows/blob/v2.0/AmtPtpHidFilter/ControlDevice.c) and [Hid.c](https://github.com/vitoplantamura/MagicTrackpad2ForWindows/blob/v2.0/AmtPtpHidFilter/Hid.c).

The USB UMDF DLL was also decompiled and compared with its [queue dispatcher](https://github.com/vitoplantamura/MagicTrackpad2ForWindows/blob/v2.0/AmtPtpDeviceUsbUm/Queue.c). Its app-visible device-interface registration does not imply a bypass API: the inspected dispatch path handles standard HID operations. Pressure/size settings alter the contacts delivered to the OS, including locking coordinates, so they cannot be assumed to preserve a separate complete stream for GlassToKey. USB transport behavior remains untested on hardware.

## Follow-up: Windows input-routing functions inspected in Ghidra

This work inspected installed Windows code statically; **none of the private setters or interception functions below was called**. A later pass successfully called only the read-only user32 extended-property getter, as detailed below. Addresses are specific to `win32kbase.sys` version `10.0.26100.9549`, 3,416,064 bytes, SHA-256 `27CB5E74B2E05C3A2C10D00CC216285F9DCA48854C6CFB57DF5E4D3731EC9AA3`.

Ghidra project: `%TEMP%\glasstokey-re-tools\projects\WindowsInputRouting.gpr`. The initial full analysis reached its 240-second limit, reporting about 252 seconds total; this is **partial whole-image analysis**, not a complete Windows audit. A subsequent bounded export successfully decompiled 93 selected functions/direct callees, including assembly, to `%TEMP%\glasstokey-re-tools\win32kbase.sys.routing.txt`. [ExportInputRouting.java](WindowsDiagnostics/Ghidra/ExportInputRouting.java) implements that export. No missing target or decompilation error was reported in the finished routing export. Function prototypes inferred by the decompiler remain provisional.

Twelve relevant entry points and callees, including their assembly, are preserved in [the Windows routing evidence excerpt](WindowsDiagnostics/Ghidra/Evidence/win32kbase-26100.9549-routing-excerpts.txt). This is decompiler output from the identified binary, not an API header or executable experiment.

| Function / virtual address | What was observed | Research judgment |
|---|---|---|
| `NtUserEnableTouchPad`, `0x1401d8d70` → `EnablePTPDevices`, `0x1401ccf30` | Boolean enable argument; the worker walks the session's device list, handles `0D/0E` configuration collections, updates processor state, and publishes input-setting state. | This is a global PTP path, not a selected-trackpad ownership interface. It is consistent with the global-toggle test. |
| `NtRIMSetTestModeStatus`, `0x1401f3320` → `RIMSetTestModeStatus`, `0x1401f1840` | The syscall checks `FUN_140231694` and returns access denied if it fails. The worker sets a Boolean at session state `+0xA1`; clearing it invokes device-list work. | Session-wide internal test state. No per-device argument, lease, or app-owned contact channel established. The exact access gate and flag consumers remain unresolved; do not treat it as an available takeover API. |
| `NtRIMSetExtendedDeviceProperty`, `0x1401f3230` → `FUN_140206e08` | Resolves a device handle, requires a 20-byte payload and specific device-state flags, then switches on property selectors `0..7`. Writes include several four-integer groups and Boolean/integer fields; it refreshes device output state and calls `CPTPProcessor::EnvironmentChanged` for processor kind 7. | Initial lead, now narrowed by the follow-up below: selectors are geometry/AAP/GestureOnly; the syscall requires an injection-device flag. Readable physical-device properties do not establish a writable physical-device control. |
| `NtRIMAddInputObserver`, `0x1401f2640` | Validates arguments and an access helper before registering an observer. | Observation is not demonstrated suppression. No exclusive filter semantics established from this trace. |
| `NtUserDownlevelTouchpad`, `0x1400ade40` → `FUN_1400adfd8` / `FUN_1400ae0a0` | Uses a pointer ID/current-thread frame, accepts operation types 0/1/2, and constructs wheel-like input or a Ctrl key event. | Compatibility delivery for already routed pointer input, not a hardware-device disable/claim mechanism. Its name alone was misleading. |

### Pointer redirection: accepted types now verified

The installed `win32kfull.sys` is version `10.0.26100.9711`, 4,403,200 bytes, SHA-256 `94F00AABE76A4AF3794E2134B806BF89E556B66814859C285DE62173350A5173`. Its `NtUserRegisterPointerInputTarget` at `0x1402abcf0` was decompiled in this follow-up. [Saved decompilation and assembly](WindowsDiagnostics/Ghidra/Evidence/win32kfull-26100.9711-pointer-target-excerpts.txt).

After checking UIAccess/window ownership, the code accepts **only pointer types 2 and 3 (touch and pen)**. At `0x1402abe25`, `LEA EAX,[R15-2]`, followed by comparison with 1 and an unsigned-above rejection, rejects `PT_TOUCHPAD=5` with error `0x57`. UIAccess does not remove this type restriction. Worker `0x14029dd04` stores separate desktop/window routing slots for touch and pen. This rules out direct type-5 registration on this exact build; it is not a prediction for every Windows version.

The [documented registration contract](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerpointerinputtarget) requires UIAccess, which differs from administrator elevation. No UIAccess manifest, certificate, installation location, policy, or registration was changed. Redirecting type 2 is not demonstrated to intercept native touchpad cursor and shell output: the PTP engine delivers those through separate output branches. It is not the next proposed physical test.

### Documented Windows APIs: narrower scope

[RegisterTouchpadCapableWindow / Thread](https://learn.microsoft.com/en-us/windows/win32/input-precisiontouchpad/registertouchpadcapable) offers a narrower supported route: an opted-in application receives touchpad two-finger `WM_POINTER` gestures; forwarding those messages to `DefWindowProc` produces normal wheel messages. It can also expose touchpads through pointer-device enumeration and identify touchpad-originated messages on an opted-in thread. This supports control of interactions in our own window. The documentation does not establish global takeover, one-finger cursor suppression, or cancellation of shell gestures across other apps. These APIs were found in this host's exports but were not called in this pass.

[TOUCHPAD_PARAMETERS_V1](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-touchpad_parameters_v1) contains settings for detected touchpads collectively, with no per-device handle. `touchpadEnabled` and `touchpadActive` are read-only information for SPI writes. Pan/zoom/tap fields are configurable; cursor speed has range 1–20, so zero is not a documented way to stop movement. There is no documented complete-contact interpreter-bypass flag in that structure. No SPI settings were written.

## Follow-up: actual per-device engine properties

A matched Microsoft public PDB was downloaded from Microsoft's symbol server and applied to the analysis database using [LoadResearchSymbols.java](WindowsDiagnostics/Ghidra/LoadResearchSymbols.java). The binary RSDS key is `7BD4193FFA935A0483172A97C84B455D1`; local PDB size is 2,756,608 bytes. Public names improve attribution; they do not supply a supported user-mode API contract or prove every inferred prototype. Whole-image analysis remains partial. All addresses in this section refer to the identified `win32kbase.sys` build.

`RIMSetExtendedPointerDeviceProperty` (`0x140206e08`) and its getter (`0x1402069f0`) use a 20-byte record: a selector followed by four 32-bit payload fields. Validation at `0x14020699c` accepts selectors 0–7 for processor kind 7. Embedded `RIM::RimDevice ExtendedTouchpadProps` TraceLogging metadata supplies the field names. [Saved property traces](WindowsDiagnostics/Ghidra/Evidence/win32kbase-26100.9549-properties-excerpts.txt).

| Selector | Fields | Meaning established / limitation |
|---|---|---|
| 0 | CurtainLeft, Top, Right, Bottom | Geometry/palm filtering; not a demonstrated enable switch |
| 1 | SuperCurtainLeft, Top, Right, Bottom | Additional geometry filtering |
| 2 | RCZWidth, RCZHeight | Zone dimensions; complete suppression not established |
| 3 | AAPEnabled | AAP heuristic Boolean |
| 4 | VisibleBounds | Rectangle; an empty rectangle falls back to hardware bounds |
| 5 | PrimaryClickZone | Rectangle |
| 6 | SecondaryClickZone | Rectangle |
| 7 | GestureOnly | Suppresses mouse-processing branches when nonzero; gesture processing still runs |

`StaticBuildEnvironment` (`0x14004f4e0`) copies these values into the engine environment. Invalid negative curtain dimensions and empty visible bounds fall back to hardware geometry. Setting a zero rectangle is therefore not an established way to exclude all contacts. `EngineDoTPMouseProcessing` (`0x1400fab3c`) checks GestureOnly; `ApplyHeuristics` (`0x1400f5e74`) also branches on it. Neither is evidence that GestureOnly disables shell gestures.

### Read-only live getter result

[Read-RawInputMetadata.ps1](WindowsDiagnostics/Read-RawInputMetadata.ps1) now has an optional `-ReadEngineProperties` switch. It invokes the existing user32 `GetExtendedPointerDeviceProperty` getter with the statically verified five-integer buffer; it contains **no setter**. The getter is exported on this host but absent from the installed SDK winuser.h. The corresponding syscall validates/copies a 20-byte buffer. No administrator elevation was needed for this read.

[Saved JSON](WindowsDiagnostics/ptp-engine-properties-20261022.json) records successful reads (True, error 0) for all eight selectors on both actual input collections. Apple Col02 has curtain values `[5300,500,5301,0]`; the open-source Col01&Col01 has `[5500,500,5501,0]`. Both return super-curtains `[150,700,150,100]`, RCZ `[50,25,0,0]`, AAP `[1,0,0,0]`, and zero payloads for selectors 4–7. These are two collections of the observed Bluetooth device, not proof of two physical trackpads or USB behavior.

### Setter guard: injection-device flag

`NtRIMSetExtendedDeviceProperty` (`0x1401f3230`) requires the resolved RIM device's flag at `+0xa8` to contain `0x2000`, along with HID/state checks. `RIMCreateDev` (`0x1401efc1c`) sets that flag on the injection-context creation branch, which captures injector identity and populates injected-device properties. `RIMAddInjectionDeviceOfType` (`0x1401f36b0`) and `RIMIDE_InitializePointerDeviceInjection` (`0x140206434`) trace to this machinery. Physical property initialization uses `RIMPopulateExtendedPointerDeviceProperties`; injected devices have a separate `RIMIDEPopulateExtendedPointerDeviceProperties` path. [Saved guard/creation traces](WindowsDiagnostics/Ghidra/Evidence/win32kbase-26100.9549-injection-guard-excerpts.txt).

**Conclusion:** physical-device read access is proven; physical-device write access is not. The inspected syscall is guarded for injection-device state. Do not present it as a physical-trackpad takeover API or try guessed writes. Administrator elevation alone is not evidence that this structural device check can be satisfied. No setter was called and no injection device was created.

## Follow-up: Windows mouse interception and gesture suppression

The strongest new static observation is in `CPTPProcessor::OnEngineOutput` (`0x1400f8c30`). [Saved output trace](WindowsDiagnostics/Ghidra/Evidence/win32kbase-26100.9549-ptp-output-excerpt.txt):

- Mouse output follows `QueuePTPMouseEvent` / `InitiatePTPMouseProcessing` separately.
- Gesture-start output creates a gesture cache and calls `ProcessTouchpadInput` only when `IsMouseInterceptEnabled()` is false. Already-started gesture continuation/cleanup has separate handling; the trace does not prove instantaneous cancellation of an existing gesture.
- Shell-action output calls `SendShellAction` only when interception is disabled.

This is a concrete existing mechanism for preventing new native gesture and shell-action delivery while the PTP engine is running. It is **not** the low-level mouse hook, and it does not by itself prove raw contacts survive, that every cursor/button path is intercepted, or that devices can be selected independently.

`NtMITEnableMouseIntercept` (`0x1401d5f00`) accepts behavior values 0 or 1, but first calls `IsInputThread`; failure sets error 5. `NtMITDisableMouseIntercept` (`0x1401d5e00`) has the same requirement. `IsInputThread` (`0x1400d6880`) compares the current thread ID with the session's stored input-thread ID. Creating an ordinary message-loop thread does not satisfy this check. The interception state stores owner thread and desktop IDs. [Saved interception traces](WindowsDiagnostics/Ghidra/Evidence/win32kbase-26100.9549-intercept-excerpts.txt).

`UserModeCallout` (`0x14022dd18`) routes through the session `InputExtensibilityCallout`, not an arbitrary app callback passed to Enable. `PrepareDataForIntercept` (`0x14022cec8`) includes an internal source/device-related value, event identity, flags, and coordinates; its first field has not yet been established as a usable public Raw Input device handle. Device-specific pass-through must not be assumed. The gesture/shell interception gate is session/desktop state, so it could affect all PTP devices even if mouse events could be filtered individually.

### Access tracing completed: DWM owns the inspected path

`NtMITSetInputCallbacks` (`0x1401d6800`) checks `IsCurrentProcessDwm()` and rejects callers that are not DWM with error 5. It also rejects a thread already declared as the input thread. On success it calls `UserSetMITInputCallbacks` (`0x140223d78`), which installs the session callback and calls `CInputThreadBase::DeclareThreadAsInput` (`0x1401ad4bc`). That worker stores the current thread ID at the exact state offset read by `IsInputThread`. `NtMITActivateInputProcessing` (`0x1401d59e0`) itself also requires `IsInputThread`. [Saved access and thread-declaration traces](WindowsDiagnostics/Ghidra/Evidence/win32kbase-26100.9549-mit-access-excerpts.txt).

`NtMITInitMinuserThread` initializes a separate minuser event/thread state; it does not perform the session input-thread declaration above. Its name must not be mistaken for permission to take over the master input thread. Administrator elevation and UIAccess do not establish DWM identity.

**Conclusion:** the inspected MIT registration/enabling route is unavailable to an ordinary GlassToKey process. This is a concrete negative result for this route, not proof that every Windows extensibility mechanism has been exhausted. Do not inject into DWM, impersonate it, patch checks, or register guessed callbacks. No MIT API, callback registration, thread declaration, setter, or interception enable/disable was invoked. No physical test is warranted for this route under the stated constraints.

## Paths forward, assessed after this research pass

| Path | Evidence / status | Privileges | USB / Bluetooth | Contacts and native suppression | Ordinary mice / reliability |
|---|---|---|---|---|---|
| Windows MIT interception | Gesture/shell gates found, but inspected callback registration requires DWM | DWM identity plus session input thread; admin/UIAccess do not satisfy this | Neither tested | Suppression exists internally; raw retention unverified | Session/desktop scope; not a viable ordinary-app route through inspected entry points |
| Trace physical-device property initialization/readers | All eight current properties read successfully; writable syscall guarded for injection devices | Getter normal user; physical write path not established | Bluetooth collections read; USB untested | GestureOnly is not full suppression; geometry controls can fall back to full bounds | No established physical takeover control; no writes proposed |
| App-window touchpad-capable handling | Documented app-local pointer interaction | Normal app opt-in per documented contract | OS abstraction, not hardware tested | Does not establish desktop/global cursor and shell takeover | Useful for app-local behavior; insufficient for objective |
| USB transport comparison | Apple USB/BT descriptors and converters match but transport differs | Read-only diagnostic normally user level; host-specific access may differ | USB still needs separate capture | A transport comparison cannot turn empty reports into retained contacts | Defer physical work until a useful candidate/probe exists |
| Direct PT_TOUCHPAD pointer redirection | Rejected by accepted-type check on this build | UIAccess does not fix type check | Neither | Ruled out as direct type-5 route here | No physical experiment warranted |

The global PTP toggle fails contact preservation on the controlled Bluetooth stream. Apple selective reporting gates the needed contacts themselves. Installed open-source control dispatch exposes no takeover command. Disabling one open-source child leaves Apple's PTP sibling; disabling the captured source removes the app's input path. No driverless equivalent of macOS FLTR has yet been verified.

**No meatspace test is needed yet.** MIT access tracing is complete enough to reject the inspected route. The remaining investigative question with the best fit to the constraints is whether an existing, app-readable HID collection exposes Apple's original contacts before the same data is converted into the PTP stream. Current Bluetooth topology/metadata and the Apple feature handlers do not establish such a collection. Next enumerate descriptor/collection boundaries and existing upper/lower interface registrations without opening write channels; explicitly distinguish hardware wire packets from app-visible HID reports. A separate original-contact source could make native PTP suppression usable, but its existence and retained reporting are hypotheses. USB hardware will eventually be needed to validate its topology; first prepare a specific read-only capture with clear evidence goals.

A useful next experiment requires either an identified independent complete-contact source or an existing app-accessible interpreter control. Only then prepare an opt-in diagnostic with Escape release, independent timeout/watchdog, and automatic restoration. Final acceptance still requires populated contact geometry/counts, cursor/click/scroll/shell suppression, GlassToKey injection, two physical trackpads, independent ordinary-mouse operation, USB and Bluetooth, and recovery on shutdown/failure. Production behavior remains unchanged.

## Follow-up: user-supplied open-source and WinUSB projects

Reviewed on 2026-10-22. The user prefers avoiding Zadig and its administrator/setup burden. **WinUSB rebinding is therefore a protocol-research reference, not the recommended product installation or next test.** No driver package was installed, replaced, removed, or rebound. The external applications were not run and their mode-switch commands were not sent.

### Signed open-source PTP driver: valuable source, same interpretation boundary

The current upstream [MagicTrackpad2ForWindows](https://github.com/vitoplantamura/MagicTrackpad2ForWindows) HEAD was verified with `git ls-remote` as `b004554d4402c7195e7ef93b522efec481ae0cc6` (2026-10-19), matching the newer local research checkout. Keep this distinct from the installed v2.0 package analyzed above. Its INF explicitly matches USB Lightning PID0265 and USB-C PID0324 MI_01, plus Bluetooth Col01 for both product IDs. USB uses a UMDF component; Bluetooth uses the KMDF filter. The project advertises Microsoft-signed Windows 11 packages. Source: [pinned INF](https://github.com/vitoplantamura/MagicTrackpad2ForWindows/blob/b004554d4402c7195e7ef93b522efec481ae0cc6/build/AmtPtpDevice_AMD64.inf).

The important architectural point is that the shipped code converts Apple packets into PTP HID reports for Windows to interpret. Full source makes that boundary auditable; it does not supply user-mode interception rights over the packets below it. In the inspected current source:

- [ControlDevice.c](https://github.com/vitoplantamura/MagicTrackpad2ForWindows/blob/b004554d4402c7195e7ef93b522efec481ae0cc6/AmtPtpHidFilter/ControlDevice.c), lines 30–80, still dispatches only settings reload and battery query. No takeover lease, contact mirror, or per-device native-output gate was found there.
- [Input.c](https://github.com/vitoplantamura/MagicTrackpad2ForWindows/blob/b004554d4402c7195e7ef93b522efec481ae0cc6/AmtPtpHidFilter/Input.c), lines 56–69 and 438–518, couples transport reads to pending upstream HID reads, parses Apple report 0x31, and completes the PTP read path. A registered interface name alone does not establish a second independent raw-contact queue.
- `PtpInputOn`, `PtpReportTouch`, and `PtpReportButton` are assigned in Hid.c; a source-wide search still finds no corresponding reads outside their declarations/assignments. Their presence does not demonstrate a working selective-interpretation switch.

**Worth exploring: yes**, particularly the existing exposed interfaces, Bluetooth packet formats, descriptor creation, and recovery logic. **Already solves exclusive interpretation: not established.** Adding a new mirror/filter command would require changing and distributing a driver, which falls outside this task's no-custom-driver/signing constraints even if based on this source. Installing an existing signed package could be considered separately, but there is no verified reason that upgrading alone would produce takeover. This host already has the older open-source filter in its mixed Bluetooth stack.

### RNCHEN WinUSB project: direct USB ownership explains its result

Research checkout pinned to `3c1bad1cf3f1c9d445202c0bb0c1e6f11609eaef` (2026-08-01). [Project README](https://github.com/RNCHEN/magic-trackpad-winusb) describes replacing the MI_01 binding with Microsoft's in-box WinUSB and doing interpretation in user mode. That is a concrete alternative architecture; it does not show that the existing PTP stack exposes the same stream to an application.

The reviewed [Program.cs](https://github.com/RNCHEN/magic-trackpad-winusb/blob/3c1bad1cf3f1c9d445202c0bb0c1e6f11609eaef/src/Program.cs) selects the first USB VID05AC/PID0324 device, claims interface 1, finds an IN endpoint with fallback 0x83, performs a Wellspring mode read/write, then reads packets and synthesizes input. The parser infers finger count from a 12-byte header and 9-byte records and unpacks coordinates. These observations identify a useful pre-PTP protocol source. They are static source findings, not a successful GlassToKey hardware test.

| Requirement | Assessment from source / documentation |
|---|---|
| New custom .sys / security bypass | Uses existing Microsoft WinUSB; no new kernel implementation required. Driver binding/package setup is still involved. |
| Unchanged device configuration during exploration | Rebinding persists beyond app exit; it is not a temporary ownership API. Do not perform it in this exploratory pass. |
| USB | Source targets PID0324; other models and report layouts are not established by this application. |
| Bluetooth | Unsupported by this project. USB endpoint access does not generalize to the Bluetooth HID stack. |
| Two physical trackpads | Current code selects FirstOrDefault and manages one device. Multi-device support is not implemented there. |
| Native movement/scroll/gestures | Replacing the PTP interface can remove that interpreter's data path. Residual mouse interfaces, native event absence, and haptic behavior still need hardware verification; no exclusive success is claimed here. |
| Ordinary mice | Device/interface-specific binding is structurally preferable to a global mouse hook; actual independent operation remains untested. |
| Failure recovery | App exit closes handles but does not restore the prior driver binding. It has no independent timeout/watchdog restoring native interpretation. |
| Complete contacts | Endpoint packets expose richer original data; application parsing is narrow and does not demonstrate a robust complete-contact/pressure/identity model for GlassToKey. |

The app's finally block closes the USB context/device; it does not restore the prior mode/binding or guarantee release of a held injected button on an exception. Read results are not checked before deriving contacts, and mode-transfer failures are logged only when debugging is enabled. These are concrete reasons to study the transport rather than run this app as our diagnostic. No speculative transfer was copied into an experiment.

Microsoft's [WinUSB installation documentation](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/winusb-installation) distinguishes using the existing WinUSB binary from installing a device binding/interface GUID or driver package. An inbox binary does not make an already HID-bound device directly accessible through WinUSB without setup. The user's objection to that setup is retained as a product constraint/preference.

### Useful physical assistance: read-only USB topology capture

Connect one trackpad with a data-capable USB cable, retain its current driver, and identify whether it is USB-C or Lightning. There is no need to change pairing, disable Bluetooth globally, install Zadig, or replace a driver. If Windows sees both USB and Bluetooth paths, the capture must distinguish them rather than assuming transport changed.

[Save-TrackpadInterfaceSnapshot.ps1](WindowsDiagnostics/Save-TrackpadInterfaceSnapshot.ps1) combines the existing Raw Input metadata and PnP snapshots with `pnputil /enum-devices` interface/stack enumeration for matching trackpad instances. It writes a unique local results directory and changes no device/input state. It does not open a raw endpoint or issue feature reports. Run from `windows_linux`:

```powershell
.\GlassToKey.Windows\WindowsDiagnostics\Save-TrackpadInterfaceSnapshot.ps1
```

The capture asks: which USB function owns MI_01, which HID collections and existing app interfaces are actually registered, and whether any candidate interface sits before PTP conversion. Enumeration cannot prove that a candidate supplies complete contacts. Contact-stream testing follows only after its supported read contract, access policy, and safety are understood. A snapshot that contains only Bluetooth records is not a USB result.

## Live USB baseline: existing open-source binding confirmed

A read-only capture at 15:17 local on 2026-10-22 now confirms a connected USB-C PID0324 device. No Bluetooth driver switch was needed. The first sandbox attempt saved Raw Input metadata but could not query PnP; an approved host-access rerun completed with 12 matching device records. The snapshot launcher now detects missing child-script output instead of treating that failure as an empty successful inventory.

Saved evidence: [USB PnP topology](WindowsDiagnostics/usb-interfaces-20261022/pnp-topology.json), [Raw Input/HID capabilities](WindowsDiagnostics/usb-interfaces-20261022/raw-input-metadata.json), and the adjacent per-device interface/stack text files.

USB MI_01 is bound to open-source `oem149.inf`, provider Bingxing Wang / Vito Plantamura, version `2025.3980.1.1000`, service `MsHidUmdf`, lower filter `WUDFRd`. Its Col01 is PTP usage 0D/05, input report 0x05/50 bytes, with open-source VID8910 and X/Y ranges 7612/5065. This validates the user's description of the existing USB driver; it is not a newer package installation.

Two separate physical USB functions are especially relevant to the original-contact question:

| Function | Live HID capability | Binding / significance |
|---|---|---|
| MI_02 | Usage FF00/000D, input 16 bytes, report 0x3F (15 payload bytes), output 64 bytes, no feature bytes | HidUsb / input.inf; an exposed vendor channel. Payload purpose unestablished; do not write to it. |
| MI_03 | Usage FF00/0003, input 108 bytes, report 0xC0 (107 payload bytes), no output or feature bytes | HidUsb / input.inf; an exposed input-only vendor channel, structurally interesting for passive observation. |

These interfaces are separate USB functions from the MI_01 UMDF PTP function. Their existence, input sizes, and registered HID paths are **proven by metadata**. They have not yet been shown to emit frames during touch, encode contacts, retain data when PTP is suppressed, or bypass an exclusive access policy. A large input report is not evidence that it contains finger geometry. Do not repeat the earlier mistake of treating a vendor-looking path as a proven independent contact stream.

The next useful physical test is a bounded **passive** observation of these vendor reports while touching the already-connected USB trackpad, with native input left enabled. First prepare collection-specific capture and payload logging; no driver changes, Wellspring commands, feature/output reports, or global input toggles are needed for that baseline. If it produces useful contacts, then assess a separate safe suppression/retention experiment. Bluetooth equivalent collections remain a separate question.

Keep the preferred Apple Bluetooth binding and the existing open-source USB binding for this comparison. No additional driver switch is justified yet. This single connected USB device does not establish simultaneous two-trackpad behavior.

## Reproducing this analysis

- `Open-AppleTrackpadGhidra.ps1 -Mode Doctor` verifies the local REA/Ghidra provider. `-Mode InspectUsb` and `-Mode InspectBluetooth` invoke REA over the selected immutable `.sys`; `-Mode Open` opens the prepared local Ghidra project for interactive inspection. These commands affect analysis files only.
- The Apple Ghidra project contains the Apple and installed open-source programs. The separate WindowsInputRouting project contains win32kbase and win32kfull. In CodeBrowser, use **G** to navigate to the virtual addresses above. The `ExportAppleDriver.java` post-script generated the two text inventories in `%TEMP%\glasstokey-re-tools` with strings, xrefs, and decompilation. Ghidra’s analysis database may be annotated without altering driver files.
- The descriptor parser can be rerun with `python WindowsDiagnostics/Ghidra/SummarizeAppleHidDescriptor.py <driver.sys> --transport usb|bluetooth` from `GlassToKey.Windows`. It uses fixed RVAs for these verified hashes; do not apply those offsets to another driver version.

Primary references: [Ghidra 12.1.4 release and archive hash](https://github.com/NationalSecurityAgency/ghidra/releases/tag/Ghidra_12.1.4_build), [REA Windows Ghidra guide](https://github.com/morluto/rea/blob/main/docs/windows-ghidra-p0.md), [Microsoft PTP configuration collection](https://learn.microsoft.com/en-us/windows-hardware/design/component-guidelines/touchpad-configuration-collection), and the locally installed Windows SDK `hidport.h`/`hidclass.h`.

## Passive USB vendor-report diagnostic prepared

[Capture-UsbVendorReports.ps1](WindowsDiagnostics/Capture-UsbVendorReports.ps1) is a standalone PowerShell/Add-Type diagnostic. It registers a private message-only window for Raw Input usages FF00/0003, FF00/000D, and the PTP baseline 0D/05. It filters logged frames to the USB Magic Trackpad paths, saves full report payloads with timestamps, handles batched HID reports, and records per-path frame counts. It performs no HID device opens, output/feature requests, native-input suppression, mouse injection, or configuration writes. App-local Raw Input registrations are removed at cleanup; process exit also releases them. Escape stops capture, duration is bounded to 2–30 seconds, and captured payload data is capped at 16 MiB.

Compilation and a two-second startup/cleanup smoke run succeeded. The idle smoke log `usb-vendor-20261022-152631-430.log` contains START and END, with no frames; this is not evidence about contact delivery during touching. The instructed 30-second user capture is pending. The protocol is idle 0–5 s, one finger 5–12 s, two fingers 12–19 s, three fingers 19–26 s, idle 26–30 s. Native Windows gestures may still occur during this deliberately passive test.

Run in a dedicated PowerShell process from `windows_linux`:

```powershell
.\GlassToKey.Windows\WindowsDiagnostics\Capture-UsbVendorReports.ps1
```

The script waits for Enter before starting and prints phase changes. No new driver or app production behavior is involved. Zero vendor frames with clearly positive PTP baseline contacts would narrow this observation route, but would not prove the underlying USB endpoint never carries data or that a mode-changing command is justified.

### Windows PowerShell 5.1 compatibility correction

The first user launch failed during Add-Type compilation because .NET Framework lacks Convert.ToHexString; no Raw Input registration/capture started. Replaced that call with BitConverter.ToString(...).Replace to preserve the same contiguous hexadecimal log format. Compilation and a two-second startup/cleanup run were then verified explicitly using Windows PowerShell 5.1 (`System32/WindowsPowerShell/v1.0/powershell.exe`), in addition to the earlier PowerShell 7 check. The 5.1 smoke log is `usb-vendor-20261022-153205-255.log`. The instructed finger-motion capture remains pending.

## Controlled passive USB result: 2026-10-22 15:38 local

The user completed [usb-vendor-20261022-153842-354.log](WindowsDiagnostics/usb-research-captures-20261022/usb-vendor-20261022-153842-354.log), a complete 30.013-second passive Raw Input capture. There are **1,747 frames, all report 0x05 / 50 bytes**, from the USB MI_01 Col01 open-source PTP path. No MI_02 report 0x3F or MI_03 report 0xC0 was observed. No FAULT or early release is recorded. [Machine-readable phase analysis](WindowsDiagnostics/usb-vendor-20261022-153842-summary.json).

| Scheduled phase | PTP frames | Matching active-tip frames |
|---|---:|---:|
| Idle, 0–5 s | 0 | 0 |
| One finger, 5–12 s | 530 | 528 with one active tip |
| Two fingers, 12–19 s | 590 | 538 with two active tips |
| Three fingers, 19–26 s | 542 | 489 with three active tips |
| Ending idle, 26–30 s | 85 | 82 still have three active tips during the user's transition |

The programmed phase label is a timing cue, not a measurement that fingers changed at that exact instant. Positive PTP data and changing coordinates establish that actual touches occurred during observation. Slot tips were decoded using the open-source flags/u32-ID/u16-X/u16-Y layout; reported contact count alone includes release samples. Native input stayed enabled.

**Result:** neither vendor channel supplied a contact mirror through Raw Input during this run. This does not prove that ordinary HID ReadFile receives no packets, that an endpoint never emits anything, or that a mode-changing command would be justified. No native suppression or vendor command was used.

### Ordinary read-only HID access: both channels open

Added [Read-UsbVendorAccess.ps1](WindowsDiagnostics/Read-UsbVendorAccess.ps1), using documented CreateFile/ReadFile access via an asynchronous FileStream. Access is GENERIC_READ with shared read/write compatibility (no write access is requested). Read buffers use the live HID input-report length. The helper issues no HidD_GetInputReport, feature report, output report, or device IOCTL. Pending reads are cancelled with CancelIoEx at the deadline and completion is observed before normal disposal.

An autonomous two-second-per-channel run in Windows PowerShell 5.1 succeeded at ordinary user access. [Access log](WindowsDiagnostics/usb-research-captures-20261022/usb-vendor-read-20261022-154803-408.log): MI_03 and MI_02 both return OPEN_OK; both yield zero frames during this uninstructed short interval; both pending reads cancel successfully with error 0 and TaskCanceledException completion. These are access/cleanup results, not a controlled moving-contact test. No sandbox retry/elevation was needed.

The next concrete test is ten seconds of direct reading on each channel while the user repeatedly moves one, two, and three fingers. The helper prints the current channel and optionally waits for Enter via `-Prompt`. Native PTP remains enabled. A negative result with that protocol would further weaken these currently exposed vendor channels as an always-on original-contact source. It would not establish that a speculative activation command is safe or useful.

Microsoft references: [opening HID collections](https://learn.microsoft.com/en-us/windows-hardware/drivers/hid/opening-hid-collections), [obtaining HID reports with ReadFile](https://learn.microsoft.com/en-us/windows-hardware/drivers/hid/obtaining-hid-reports). The latter distinguishes streaming reads from GetInputReport polling; the diagnostic uses the streaming read path.

## Controlled direct HID result and USB branch closure: 15:50 local

The user completed [usb-vendor-read-20261022-155019-252.log](WindowsDiagnostics/usb-research-captures-20261022/usb-vendor-read-20261022-155019-252.log) while repeatedly moving one, two, and three fingers.

| Vendor collection | Read-only open | Reading interval | Reports | Cleanup |
|---|---|---:|---:|---|
| MI_03, 108-byte input / report 0xC0 | OPEN_OK | 10.002 s | 0 | CancelIoEx True, error 0; cancelled task completed |
| MI_02, 16-byte input / report 0x3F | OPEN_OK | 10.012 s | 0 | CancelIoEx True, error 0; cancelled task completed |

There are no FRAME records. Both handles were disposed after cancellation; no feature/output reports, configuration changes, injection, or input suppression occurred. Finger activity was instructed and reported by the user, rather than measured by a simultaneous PTP baseline in this direct-read run. The preceding Raw Input run independently established valid one/two/three-contact PTP data on the same USB setup.

**What we learned:** the existing vendor channels are accessible without an installation or permission workaround, but neither supplied reports through Raw Input or ordinary streaming reads during the tested activity. An accessible handle and a 108-byte input descriptor do not establish an independent contact stream. This does not prove that the channels can never emit data or describe their protocol; it provides no basis for speculative activation commands.

**Decision:** close this open-source USB testing branch at the user's request. The full source remains useful for static comparison of Apple wire-format parsing and PTP conversion, but no takeover advantage was demonstrated. WinUSB rebinding remains disfavored by the user and was never attempted. No additional USB test or driver installation is recommended now.

For subsequent work, return to the existing Apple Bluetooth connection, re-identify its actual active collections/filters read-only, and keep researching existing interfaces without changing the preferred binding. Do not repeat the already failed Bluetooth global-toggle contact-retention test without a new data-path hypothesis. The original no-custom-driver, no-security-change, full-contact, ordinary-mouse-independence, and two-trackpad requirements remain unsolved. Production typing, haptics, dragging, and input behavior were not changed by these diagnostics.

## Separate practical fallback note

At the user's request, [WINDOWS_MOUSE_HOOK_FALLBACK.md](WINDOWS_MOUSE_HOOK_FALLBACK.md) describes the existing WM_INPUT + WH_MOUSE_LL movement gate, original measured results, and the proposed user-disabled Windows gesture fallback. The combined fallback is unverified; ordinary-mouse independence remains unsolved. This records a possible fallback without changing production behavior or Windows settings.

## User-approved compromise: Mouse Takeover test

The user now accepts blocking all physical mice if needed, with keyboard release. Implemented a separate bounded interactive test, documented in [the fallback note](WINDOWS_MOUSE_HOOK_FALLBACK.md#mouse-takeover-interactive-test-2026-10-22). This supersedes ordinary-mouse independence as a blocker for this explicitly chosen fallback experiment; it does not claim device-specific FLTR ownership. No normal-startup takeover or saved checkbox has been enabled. Gesture suppression and retained populated contacts still require hardware validation.

## Mouse Takeover: first positive Bluetooth hardware result

The user ran the corrected interactive test and observed the synthetic jump. The log confirms a roughly 30-second gate, 1,206 raw reports (1,193 populated), sampled cursor position stable except for the injected move, and release consistent with timeout. A late 4.881-second report gap is bracketed by release/new-contact lifecycle samples; populated reports resume just before expiry. See [the detailed measured result and outstanding checks](WINDOWS_MOUSE_HOOK_FALLBACK.md#hardware-result-apple-bluetooth-1623-local). This advances the explicitly accepted global-mouse compromise; it does not solve device-specific takeover or prove shell-gesture/click/scroll suppression. No normal production behavior has been enabled.

## Windows app integration

At the user's request, Mouse Takeover is now integrated below the decoder selectors in Windows GlassToKey. It is session-only and defaults off, with a continuous checkbox, 30-second test, status, global Ctrl+Alt+R release (matching Mac Control+Option+R), and tray release/status. See [WINDOWS_MOUSE_TAKEOVER.md](WINDOWS_MOUSE_TAKEOVER.md) for current behavior and safety/lifecycle details. The original standalone test's F10/Escape shortcuts remain diagnostic-specific; the main app uses Ctrl+Alt+R and preserves ordinary Escape behavior. The Mac source was read for reference only and was not modified.
