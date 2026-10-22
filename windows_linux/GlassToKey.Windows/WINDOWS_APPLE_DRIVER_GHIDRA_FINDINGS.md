# Apple Windows trackpad filters: Ghidra and REA findings

Date: 2026-10-22. Status: **Apple 6.1.8000.6 binaries inspected; the controlled Bluetooth global-toggle test failed contact preservation; exclusive takeover unproven**. Static analysis was read-only with respect to hardware and Windows settings. The separately documented hardware probe temporarily toggled Windows PTP and restored it. No undocumented feature report or IOCTL was sent.

This report addresses a narrow question: can an existing Apple Windows driver suppress native pointer, scroll, click, and shell gesture interpretation for a selected Magic Trackpad while GlassToKey continues to receive populated contacts? No verified driverless takeover has been found. The controlled Bluetooth global-toggle probe stops native movement/wheel events but removes usable contacts. The follow-up investigation corrected a Raw Input metadata bug, mapped the actual collections, inspected both installed open-source binaries, and traced selected Windows input-routing functions. The most interesting remaining paths are Windows pointer redirection and per-device output configuration, described below. Both require further investigation before hardware writes or production changes.

**Correction to earlier reports:** the captured `usage=0x00/0x00` values came from GlassToKey's failed device-info query and fallback. A correct query and independent HID capability query identify the Apple report stream as **Digitizer / Touch Pad (`0x0D/0x05`)**. The `0x05` report is not demonstrated to be a separate vendor raw stream. This correction does not change the measured 407 empty frames during suppression.

## Scope and provenance

| Item | Observation |
|---|---|
| USB filter | `ApplePrecisionTrackpadUSB.sys`, 37,784 bytes, file version `6.1.8000.6`, SHA-256 `944447638112D32AF6FC2CDB4E47BFB75871600B7CDE97DADE3606C22B6AD4A1` |
| Bluetooth filter | `ApplePrecisionTrackpadBluetooth.sys`, 41,896 bytes, file version `6.1.8000.6`, SHA-256 `A589ABCB198326D84F1310FC8A5D9A9A5A2F4D219A55B15181FEEBA9E6893B92` |
| Source | Local `windows_linux/ApplePrecisionTrackpad_amd64.USB-C/` package; hashes match the copies in the Windows DriverStore previously enumerated read-only. USB is staged but was not connected in these tests. |
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

This work inspected installed Windows code statically; **none of the private functions below was called**. Addresses are specific to `win32kbase.sys` version `10.0.26100.9549`, 3,416,064 bytes, SHA-256 `27CB5E74B2E05C3A2C10D00CC216285F9DCA48854C6CFB57DF5E4D3731EC9AA3`.

Ghidra project: `%TEMP%\glasstokey-re-tools\projects\WindowsInputRouting.gpr`. The initial full analysis reached its 240-second limit, reporting about 252 seconds total; this is **partial whole-image analysis**, not a complete Windows audit. A subsequent bounded export successfully decompiled 93 selected functions/direct callees, including assembly, to `%TEMP%\glasstokey-re-tools\win32kbase.sys.routing.txt`. [ExportInputRouting.java](WindowsDiagnostics/Ghidra/ExportInputRouting.java) implements that export. No missing target or decompilation error was reported in the finished routing export. Function prototypes inferred by the decompiler remain provisional.

Twelve relevant entry points and callees, including their assembly, are preserved in [the Windows routing evidence excerpt](WindowsDiagnostics/Ghidra/Evidence/win32kbase-26100.9549-routing-excerpts.txt). This is decompiler output from the identified binary, not an API header or executable experiment.

| Function / virtual address | What was observed | Research judgment |
|---|---|---|
| `NtUserEnableTouchPad`, `0x1401d8d70` → `EnablePTPDevices`, `0x1401ccf30` | Boolean enable argument; the worker walks the session's device list, handles `0D/0E` configuration collections, updates processor state, and publishes input-setting state. | This is a global PTP path, not a selected-trackpad ownership interface. It is consistent with the global-toggle test. |
| `NtRIMSetTestModeStatus`, `0x1401f3320` → `RIMSetTestModeStatus`, `0x1401f1840` | The syscall checks `FUN_140231694` and returns access denied if it fails. The worker sets a Boolean at session state `+0xA1`; clearing it invokes device-list work. | Session-wide internal test state. No per-device argument, lease, or app-owned contact channel established. The exact access gate and flag consumers remain unresolved; do not treat it as an available takeover API. |
| `NtRIMSetExtendedDeviceProperty`, `0x1401f3230` → `FUN_140206e08` | Resolves a device handle, requires a 20-byte payload and specific device-state flags, then switches on property selectors `0..7`. Writes include several four-integer groups and Boolean/integer fields; it refreshes device output state and calls `CPTPProcessor::EnvironmentChanged` for processor kind 7. | The most interesting **per-device static lead**. It demonstrably changes device output configuration, but no selector has been identified as a safe interpreter-only suppression switch. Field names, permissions, lifetime, getters, and restoration semantics must be established before any call. |
| `NtRIMAddInputObserver`, `0x1401f2640` | Validates arguments and an access helper before registering an observer. | Observation is not demonstrated suppression. No exclusive filter semantics established from this trace. |
| `NtUserDownlevelTouchpad`, `0x1400ade40` → `FUN_1400adfd8` / `FUN_1400ae0a0` | Uses a pointer ID/current-thread frame, accepts operation types 0/1/2, and constructs wheel-like input or a Ctrl key event. | Compatibility delivery for already routed pointer input, not a hardware-device disable/claim mechanism. Its name alone was misleading. |

`RIMSetExtendedDeviceProperty` is worth further tracing because it operates after device identification and reaches output configuration. A Boolean store inside that function is insufficient evidence of a touchpad-enable bit. The branch can affect other digitizer properties. Do not send guessed 20-byte structures, invoke private setters experimentally, patch kernel memory, or bypass their access checks.

### Documented Windows APIs: promising scope and limits

[RegisterPointerInputTarget](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerpointerinputtarget) redirects a pointer type to an application window. Its ownership is tied to the registered window; destroying/unregistering the window releases it. The documented API requires **UIAccess**, which is distinct from administrator elevation. The contract is global by pointer type rather than device, excludes mouse redirection, and describes normal processing for injection by the owner. **Whether this host accepts `PT_TOUCHPAD`, whether redirection precedes cursor/shell interpretation, and whether complete contacts remain available were not established.** Those are the next static questions. A legitimate UIAccess deployment would require normal application trust/installation requirements, not a new driver; no certificate, manifest, install location, or security policy was changed.

The installed `win32kfull.sys` exports `NtUserRegisterPointerInputTarget` at `0x1402abcf0`. Its version is `10.0.26100.9711`, 4,403,200 bytes, SHA-256 `94F00AABE76A4AF3794E2134B806BF89E556B66814859C285DE62173350A5173`. This address was found by PE export enumeration; **its implementation was not decompiled in this pass**. Checking its accepted types, UIAccess path, and subsequent routing is a concrete next Ghidra task.

[RegisterTouchpadCapableWindow / Thread](https://learn.microsoft.com/en-us/windows/win32/input-precisiontouchpad/registertouchpadcapable) offers a narrower supported route: an opted-in application receives touchpad two-finger `WM_POINTER` gestures; forwarding those messages to `DefWindowProc` produces normal wheel messages. It can also expose touchpads through pointer-device enumeration and identify touchpad-originated messages on an opted-in thread. This supports control of interactions in our own window. The documentation does not establish global takeover, one-finger cursor suppression, or cancellation of shell gestures across other apps. These APIs were found in this host's exports but were not called in this pass.

[TOUCHPAD_PARAMETERS_V1](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-touchpad_parameters_v1) contains settings for detected touchpads collectively, with no per-device handle. `touchpadEnabled` and `touchpadActive` are read-only information for SPI writes. Pan/zoom/tap fields are configurable; cursor speed has range 1–20, so zero is not a documented way to stop movement. There is no documented complete-contact interpreter-bypass flag in that structure. No SPI settings were written.

## Paths forward, ranked after this research pass

| Priority / path | Evidence | Privileges | USB / Bluetooth | Contacts and native suppression | Ordinary mice / limitations |
|---|---|---|---|---|---|
| 1. Trace documented pointer redirection through Windows | Existing API and identifiable kernel entry point; window lifetime provides a natural restoration boundary | UIAccess per documentation; administrator rights alone do not establish it | Transport-independent in concept; neither verified | Both still unknown for `PT_TOUCHPAD`; must verify accepted type and ordering before preparing a hardware probe | Mouse type is excluded from the API, but practical independence is untested; scope is all devices of the pointer type |
| 2. Resolve Windows per-device output configuration | Actual device-handle setter reaches `CPTPProcessor::EnvironmentChanged` | Exact access policy unresolved | Transport-independent in concept; neither verified | No suppression selector or preserved-contact behavior identified | Could meet selected-device requirements if semantics prove suitable; private/unstable interface is a reliability concern |
| 3. App-window touchpad pointer handling | Documented touchpad-capable window/thread behavior | No documented UIAccess requirement for this opt-in | OS abstraction; not tested here | Useful for an app-local experiment; no complete desktop suppression contract | Does not supply the required background/global takeover by itself |
| 4. USB comparison after the static route is clearer | Apple USB and Bluetooth descriptors and converter logic match, while transports differ | Diagnostic uses normal user access on tested host | USB untested | Needed for final acceptance, but another Bluetooth global-toggle repeat is low value | No ordinary mouse needed for this capture; independence still requires later mouse testing |

The global PTP toggle and Apple surface-reporting switch fail or defeat the needed data path. The known open-source control device has no takeover command. Disabling the open-source child does not isolate the Apple PTP stream from Windows. `RIMSetTestModeStatus` is session-wide internal state with unresolved access/lifetime, so it is not the recommended next experiment.

**No meatspace action is needed to finish this static pass.** Before requesting another physical test, establish either a supported pointer-redirection route for `PT_TOUCHPAD` or a fully understood per-device output control. Any resulting diagnostic must be standalone, opt-in, short, keyboard-releasable, and fail open. Final acceptance still requires full contact geometry/counts, native movement/click/scroll/shell suppression, GlassToKey injection, two physical trackpads, ordinary-mouse independence, and separate USB/Bluetooth validation. No production takeover behavior was enabled.

## Reproducing this analysis

- `Open-AppleTrackpadGhidra.ps1 -Mode Doctor` verifies the local REA/Ghidra provider. `-Mode InspectUsb` and `-Mode InspectBluetooth` invoke REA over the selected immutable `.sys`; `-Mode Open` opens the prepared local Ghidra project for interactive inspection. These commands affect analysis files only.
- The Ghidra project already contains both analyzed programs. In CodeBrowser, use **G** to navigate to the virtual addresses above. The `ExportAppleDriver.java` post-script generated the two text inventories in `%TEMP%\glasstokey-re-tools` with strings, xrefs, and decompilation. Ghidra’s analysis database may be annotated without altering driver files.
- The descriptor parser can be rerun with `python WindowsDiagnostics/Ghidra/SummarizeAppleHidDescriptor.py <driver.sys> --transport usb|bluetooth` from `GlassToKey.Windows`. It uses fixed RVAs for these verified hashes; do not apply those offsets to another driver version.

Primary references: [Ghidra 12.1.4 release and archive hash](https://github.com/NationalSecurityAgency/ghidra/releases/tag/Ghidra_12.1.4_build), [REA Windows Ghidra guide](https://github.com/morluto/rea/blob/main/docs/windows-ghidra-p0.md), [Microsoft PTP configuration collection](https://learn.microsoft.com/en-us/windows-hardware/design/component-guidelines/touchpad-configuration-collection), and the locally installed Windows SDK `hidport.h`/`hidclass.h`.
