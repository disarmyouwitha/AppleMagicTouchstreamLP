# Apple Windows trackpad filters: Ghidra and REA findings

Date: 2026-10-22. Status: **static analysis complete for the two Apple 6.1.8000.6 binaries; exclusive takeover unproven**. All work here was read-only with respect to hardware, driver installation, device state, and Windows input settings. No undocumented feature report or IOCTL was sent.

This report addresses a narrow question: can an existing Apple Windows driver suppress native pointer, scroll, click, and shell gesture interpretation for a selected Magic Trackpad while GlassToKey continues to receive populated contacts? The inspected Apple filters contain contact-reporting controls, but none identified so far provides that split. The most useful next test is a controlled finger hold during the already implemented, automatically restored Windows Precision Touchpad toggle.

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

This matches the report ID and length in [OFFICIAL_PTP_SPEC.md](OFFICIAL_PTP_SPEC.md). **It weakens the earlier idea that `0x05` must be an independent, non-PTP raw collection.** The host’s Raw Input API nevertheless reported usage `0x00/0x00` for its 50-byte stream, and the observed PnP path was the Apple auxiliary `Col02` sibling of the open-source PTP child. We have not reconciled those host-facing collection labels with this embedded descriptor. A format match does not prove that disabling Windows PTP interpretation leaves report generation untouched. The exact PnP/HID routing still needs a read-only interface mapping or a controlled hardware capture.

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

## What is proven, and what remains a hypothesis

| Technique | Privileges | USB / Bluetooth | Populated raw contacts while suppressed | Native pointer / scroll / gestures | Ordinary mouse | Current judgment |
|---|---|---|---|---|---|---|
| `WH_MOUSE_LL` movement gate | User | Hook is transport-neutral | `0x05` frames arrived during the Bluetooth probe; contacts were not its suppression target | Hook-visible moves can be swallowed; wheel and shell gestures were not blocked by this gate | Physical mouse motion also blocked | Diagnostic only, never final takeover. |
| Windows Ctrl+Win+F24 PTP toggle | User on this host | Bluetooth tested; USB untested | **Unknown.** 408/408 and 459/463 disabled frames had zero contact count in uncontrolled runs; four nonzero frames were near a transition | No native move/wheel reached the hook during disabled intervals; synthetic move worked. Shell gestures not manually checked. | Expected independent, not tested with an ordinary mouse | Most useful immediate experiment. A controlled continuous touch decides whether the raw stream remains usable. It affects every PTP device, including the built-in Dell pad. |
| Apple feature report `0x06` surface off | HID access / driver ownership unknown | Present in both inspected binaries | **No in the decoded `0x05` path:** Apple parsers skip contacts when the surface flag is off | Could reduce native touch behavior; not hardware tested and cannot satisfy full contact capture | Likely unaffected | Source-level dead end for exclusive interpretation. Do not send speculative reports. |
| Apple feature report `0x06` button off | HID access / driver ownership unknown | Present in both | Contacts plausibly continue | Click only; native movement/scroll/gestures remain | Likely unaffected | Possible narrow click control, not takeover. Untested. |
| Apple report `0x04` input mode | HID access / driver ownership unknown | Present in both | Unknown and likely at risk | Unknown | Likely unaffected | No evidence of a mode that separates app contacts from Windows interpretation. Do not send speculative reports. |
| Private Apple user-mode control | Unknown | No candidate identified | Unknown | Unknown | Unknown | No interface/IOCTL with takeover semantics found in these binaries; negative result is bounded by missing PDBs and incomplete data-flow tracing. |
| Disable only the PTP child devnode | Usually administrator | Host topology differs by transport/driver stack | Unknown | Potentially per-device | Other mice would be unaffected | Read-only PnP topology makes this a hypothesis. Do not change devnode state under the current exploratory policy. |

The macOS mechanism in [TRACKPAD_TAKEOVER.md](../../mac/gesturepad/TRACKPAD_TAKEOVER.md) is a filter-client routing choice in the native Apple macOS driver. No equivalent routing choice was found in these Windows Apple binaries. A Windows feature report that merely tells the device/driver to stop reporting touch does not reproduce FLTR.

## Next decision: one controlled hardware capture

The already built diagnostic is isolated from the normal typing engine, lasts 25 seconds, requires an actual positive-contact frame before toggling, restores the PTP setting ten seconds later, and starts a separate restore watchdog. It does not install a driver, change a devnode, or save application settings. Run from `windows_linux`:

```powershell
.\GlassToKey.Windows\bin\Release\net10.0-windows\GlassToKey.Windows.exe --ptp-diagnostic .\ptp-os-toggle-controlled.log --ptp-os-toggle-probe
```

For the **Bluetooth** run, begin touching the Magic Trackpad before second 5. Keep at least one finger continuously on it and moving through the entire ten-second disabled interval. During that interval, also attempt a two-finger scroll and a three- or four-finger Windows shell gesture, and note whether the cursor, page, or shell actually responds. Press **Escape** to restore early if necessary. The program skips the toggle if it never sees a positive contact in the trigger window. Repeat separately with **USB** attached when available, without changing its driver binding. A normal mouse is useful later for independent-operation acceptance, but the test needs only the trackpad and keyboard.

**Pass criterion for a possible global-toggle approach:** the log shows positive contact counts and nonzero contact-slot payload continuously while `osEnabled=false`; the native cursor, scrolling, clicks, and shell gestures do not act; tagged `SendInput` still moves the cursor; state is restored. If contacts go to zero despite continuous touch, the global toggle cannot serve as GlassToKey takeover for this stream. Even if it passes, its system-wide PTP scope means we would still need a per-device route or an explicit product decision before changing production behavior.

If the global toggle fails, the next safe work is read-only mapping of the actual `Col01`/`Col02` HID interfaces and the open-source filter’s PTP output path. The question is whether any existing per-device user-mode control suppresses only the PTP child’s consumption while Apple’s `0x05` reports continue. No such control has yet been demonstrated. Do not disable devnodes, modify bindings, or send undocumented Bluetooth/HID commands to guess.

## Reproducing this analysis

- `Open-AppleTrackpadGhidra.ps1 -Mode Doctor` verifies the local REA/Ghidra provider. `-Mode InspectUsb` and `-Mode InspectBluetooth` invoke REA over the selected immutable `.sys`; `-Mode Open` opens the prepared local Ghidra project for interactive inspection. These commands affect analysis files only.
- The Ghidra project already contains both analyzed programs. In CodeBrowser, use **G** to navigate to the virtual addresses above. The `ExportAppleDriver.java` post-script generated the two text inventories in `%TEMP%\glasstokey-re-tools` with strings, xrefs, and decompilation. Ghidra’s analysis database may be annotated without altering driver files.
- The descriptor parser can be rerun with `python WindowsDiagnostics/Ghidra/SummarizeAppleHidDescriptor.py <driver.sys> --transport usb|bluetooth` from `GlassToKey.Windows`. It uses fixed RVAs for these verified hashes; do not apply those offsets to another driver version.

Primary references: [Ghidra 12.1.4 release and archive hash](https://github.com/NationalSecurityAgency/ghidra/releases/tag/Ghidra_12.1.4_build), [REA Windows Ghidra guide](https://github.com/morluto/rea/blob/main/docs/windows-ghidra-p0.md), [Microsoft PTP configuration collection](https://learn.microsoft.com/en-us/windows-hardware/design/component-guidelines/touchpad-configuration-collection), and the locally installed Windows SDK `hidport.h`/`hidclass.h`.
