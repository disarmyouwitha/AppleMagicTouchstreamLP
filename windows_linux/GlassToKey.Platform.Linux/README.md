# GlassToKey.Platform.Linux

Linux systems backend in progress.

Current responsibilities:

- enumerate Magic Trackpad devices from Linux input nodes
- prefer the Apple `if01` event interface when multiple nodes map to one physical device
- probe real evdev axis metadata through `EVIOCGABS`
- capture raw evdev events for device validation
- support normalized Linux `.atpcap` frame capture for offline replay-oriented diagnostics via the Linux host
- assemble multitouch frames from evdev Type B slots and observed legacy absolute fallback fields
- expose Linux device capabilities and stable IDs
- stream normalized `InputFrame` data through a runtime service/sink seam or directly into the shared `TrackpadFrameEnvelope` target
- probe `uinput` readiness and permission state for future virtual keyboard/mouse output
- inject keyboard and mouse output through `uinput`
- map semantic dispatch codes to evdev output before falling back to Windows VK compatibility
- surface Linux-specific diagnostics and permission checks
- support a minimal `run-engine` host path that drives the shared engine and dispatches through `uinput`

Current caveats:

- On the current Ubuntu 24.04 setup, Apple Magic Trackpads expose usable evdev traffic and can emit both `ABS_MT_*` slot updates and parallel legacy absolute updates on the same node.
- `EVIOCGABS` works on the host devices and reports real axis ranges. It may still be denied inside the sandboxed coding environment, so validation in this environment may require escalation rather than product-side fallback logic.
- The current Linux CLI exposes `probe-uinput` so packaging/permission work can be validated separately from evdev capture.
- The current Linux CLI also exposes `uinput-smoke` for a focused-app sanity check of the virtual input path.
- The current Linux CLI also exposes `run-engine`, and that path has now been validated end-to-end on the host with real Apple Magic Trackpads over both USB and Bluetooth.
- The current Linux CLI now also exposes `selftest`, which validates the bundled Linux keymap import path and checks that the current semantic Linux action surface maps cleanly to evdev codes.
- The current Linux CLI now also exposes `doctor`, `capture-atpcap`, `summarize-atpcap`, `replay-atpcap`, `write-atpcap-fixture`, and `check-atpcap-fixture`, so packaging checks and offline diagnostics are no longer just planned.
- The Linux host now also exposes `show-config`, `init-config`, and `print-udev-rules` so device selection, keymap choice, and packaging permission scaffolding can be exercised without a GUI.
- The Linux output path now covers semantic volume and brightness aliases (`VOL_UP`, `VOL_DOWN`, `BRIGHT_UP`, `BRIGHT_DOWN`) directly instead of depending on Windows-VK fallback.
- The Linux host now also checks in publish profiles for framework-dependent and self-contained `linux-x64` publishes, so packaging work has moved from planning into repo-backed build artifacts.
- The repo now also carries install artifacts under `packaging/linux/`: a checked-in `udev` rule template and an install script for published Linux builds with wrapper-vs-service install decisions.
- Over Bluetooth, Apple trackpads on this machine do not show up under `/dev/input/by-id`; the backend should fall back to `uniq` for stable identity.
- The validated Bluetooth event nodes used the same axis ranges and normalized frame path as USB, so the Linux backend should keep one transport-agnostic evdev pipeline.
- Dispatch tracing is still optional. It is a useful debug aid, but it is not required for the product path and should not be allowed to burden the normal hot path. Future `.atpcap` capture remains the better offline diagnostic artifact.
- Current Linux `.atpcap` version 3 capture preserves normalized contact frames and physical click state in shared frame-header flags, and Linux now has fixture-based replay checks for regression validation.

This project should not contain gesture behavior or layout logic. Those belong in `GlassToKey.Core`.
