# AGENTS

## Scope
- This file governs the `windows_linux/` working folder only.
- When working from `windows_linux/`, treat only these top-level folders as in scope:
  - `AppleMagicTouchstream.Windows/`
  - `AppleMagicTouchstream.Core/`
  - `AppleMagicTouchstream.Linux/`
- Do not treat sibling folders such as `../mac/` as in scope unless the user explicitly asks.

## Repo Shape
- `AppleMagicTouchstream.Windows/`: active Windows app and the current primary production target.
- `AppleMagicTouchstream.Core/`: shared engine/layout/keymap/input/dispatch/runtime seam library used by both Windows and Linux.
- `AppleMagicTouchstream.Linux/`: Linux product tree containing:
  - `AppleMagicTouchstream.Linux/`: CLI host
  - `AppleMagicTouchstream.Linux/Platform/`: Linux evdev/uinput/haptics backend
  - `AppleMagicTouchstream.Linux/Host/`: Linux settings/runtime/doctor host layer
  - `AppleMagicTouchstream.Linux/Gui/`: Linux Avalonia tray/config GUI
  - `AppleMagicTouchstream.Linux/packaging/`: Linux package/install artifacts

## Target Selection
- Default production target: `AppleMagicTouchstream.Windows/AppleMagicTouchstream.Windows.csproj`
- Shared extraction target: `AppleMagicTouchstream.Core/AppleMagicTouchstream.Core.csproj`
- Linux backend target: `AppleMagicTouchstream.Linux/Platform/AppleMagicTouchstream.Platform.Linux.csproj`
- Linux host target: `AppleMagicTouchstream.Linux/Host/AppleMagicTouchstream.Linux.Host.csproj`
- Linux CLI target: `AppleMagicTouchstream.Linux/AppleMagicTouchstream.Linux.csproj`
- Linux GUI target: `AppleMagicTouchstream.Linux/Gui/AppleMagicTouchstream.Linux.Gui.csproj`
- If the user says "build" without more detail, prefer the target most relevant to the touched code.

## Boundaries

### Windows
- Keep Windows-only code in `AppleMagicTouchstream.Windows/`.
- Windows owns WPF, WinForms, Raw Input, `SendInput`, click suppression, tray/startup UI, Windows haptics, and Windows-hosted diagnostics.
- Preserve current Windows behavior while extracting shared code.
- Keep Windows as one top-level `AppleMagicTouchstream.Windows` app project unless the user explicitly asks for a larger architecture change.

### Core
- Keep shared engine/runtime seams, layout generation, keymap handling, input/contact models, and platform-neutral dispatch semantics in `AppleMagicTouchstream.Core/`.
- Keep `AppleMagicTouchstream.Core/` free of WPF, WinForms, Raw Input, `SendInput`, `evdev`, `uinput`, XDG/platform settings, and tray/startup/service code.
- Prefer physically moving shared behavior into `AppleMagicTouchstream.Core/` instead of rebuilding similar behavior separately in Windows or Linux.
- Shared code should not remain as linked source back into `AppleMagicTouchstream.Windows/` as a steady state.

### Linux
- Keep Linux evdev ingestion, reconnect supervision, `uinput` output, actuator-hidraw haptics, and Linux permission probing in `AppleMagicTouchstream.Linux/Platform/`.
- Keep Linux settings/config/runtime composition and host-side diagnostics in `AppleMagicTouchstream.Linux/Host/`.
- Keep `AppleMagicTouchstream.Linux/` and `AppleMagicTouchstream.Linux/Gui/` thin as shipped app surfaces.
- Linux work should consume platform-neutral models or semantics, not Windows virtual-key assumptions.
- Prefer semantic actions over Windows-VK fallback whenever the dependency boundary allows it.

## Structural Guardrails
- The Linux repo layout is intentionally nested under `AppleMagicTouchstream.Linux/`, but the project boundaries are still real.
- `AppleMagicTouchstream.Linux/AppleMagicTouchstream.Linux.csproj` is the CLI project only.
- `AppleMagicTouchstream.Linux/AppleMagicTouchstream.Linux.csproj` explicitly excludes `Host/**`, `Platform/**`, `Gui/**`, and `packaging/**` from default item globs.
- Do not add source files from `AppleMagicTouchstream.Linux/Host/`, `AppleMagicTouchstream.Linux/Platform/`, or `AppleMagicTouchstream.Linux/Gui/` directly to `AppleMagicTouchstream.Linux/AppleMagicTouchstream.Linux.csproj`; keep those as project references.
- Treat `AppleMagicTouchstream.Linux/`, `AppleMagicTouchstream.Linux/Platform/`, `AppleMagicTouchstream.Linux/Host/`, `AppleMagicTouchstream.Linux/Gui/`, and `AppleMagicTouchstream.Linux/packaging/` as separate ownership zones even though they share one top-level folder.
- The nested repo layout does not change the installed product split:
  - CLI installs to `/opt/AppleMagicTouchstream.Linux`
  - GUI installs to `/opt/AppleMagicTouchstream.Linux.Gui`
- Do not change packaging install destinations to mirror the nested repo layout.

## Historical Windows research

[RESEARCH_ARCHIVE.md](RESEARCH_ARCHIVE.md) locates the external BT/USB research,
diagnostic scripts, exact Apple driver package, evidence logs and compressed Ghidra
projects. Active test fixtures remain in the Windows project. Archived hardware
probes are manual tools, not build steps.

## Windows Notes
- `AppleMagicTouchstream.Windows` is the active Windows app. Live mode runs as a tray/status app that reads touchpad report `0x05` via Raw Input and drives key mapping in the background.
- Core Windows hot-path/runtime file: `AppleMagicTouchstream.Windows/TouchRuntimeService.cs`
- Windows Raw Input ingestion: `AppleMagicTouchstream.Windows/RawInputInterop.cs`
- Windows output injection: `AppleMagicTouchstream.Windows/WindowsDispatch/SendInputDispatcher.cs`
- Windows haptics helper: `AppleMagicTouchstream.Windows/WindowsHaptics/MagicTrackpadActuatorHaptics.cs`
- Windows diagnostics/self-test surface: `AppleMagicTouchstream.Windows/WindowsDiagnostics/`
- Windows Config has a top Gestures / Keyboard workspace selector, in that order; Keyboard remains the default. Device/takeover controls span both workspaces. Gestures replaces the visualizer and keyboard inspector with three resizable columns: navigation, assignment cards, Action inspector. Keyboard retains both pads, typing test and its separate settings inspector. Preserve named controls and runtime bindings. A single selected pad determines the initial gesture editing side; show which side is selected. Preserve disconnected saved device paths. All gesture metadata, including explicit None, round-trips through full settings exports; invalid bundles must not silently fall back to keymap-only import.
- Mac is the UI reference. TouchStream has independent traced geometry, automatic reference backgrounds and disabled column tuning. Gesture Left/Right, Mirror Edit and coordinated Both are distinct. Existing numeric enum identities must remain stable; append new identities. See `AppleMagicTouchstream.Windows/MAC_GOLD_PARITY.md` for implemented contracts, limitations and verification.
- Windows Typing Tuning exposes Hold Duration, Haptic Strength and Restore Defaults. Legacy Typing Grace, Drag Cancel and intent movement/velocity fields remain decode-compatible but cannot gate unified Windows typing. Unreserved contacts stay keyboard input; tap eligibility is bounded by max(200 ms, Hold Duration), release geometry and snap. Preserve Linux legacy policy separately.
- Gesture Hold has independent 100–5000 ms thresholds (500 default) and once/held shortcut output. Held shortcuts use the keyboard dispatch pump and shared modifier/key ownership; Left, Right and coordinated Both have distinct leases. All-up, stale/invalid input, reconfiguration, output failure, queue overflow and teardown release only the appropriate owners. Gesture keyboard events must not use the pointer worker's private native key buffers.
- Established MO/modifier chords and committed key holds retain same-pad priority through all-up. Unresolved candidates retain fixed-capacity owned keyboard proposals while gestures see original frames once. Winning/cancelled gestures discard proposals; never-activated rollover may resolve at partial lift/all-up. Generation/layer/epoch changes and invalid/stale/overflowed input cancel proposals. Live semantic keyboard publication bypasses the offline diagnostic ring and writes directly to the bounded output queue; publication overflow cancels the cycle and inserts a release barrier.
- Windows uses unified keyboard/gesture policy: typing remains enabled; the former Keyboard/Mouse mode, typing toggle and selective click filter are removed. Shared legacy mode fields remain for Linux compatibility but cannot reactivate Windows modes.
- `GlobalMouseInputHook.cs` observes mouse activity and supports explicit Mouse Takeover/diagnostic gates only. Mouse Takeover defaults off on first launch and saves explicit opt-in locally for startup restoration. Uncheck, tray release and Ctrl+Alt+R clear opt-in; tests stay temporary and lifecycle releases preserve it. Startup restoration waits/retries for delayed Bluetooth availability; explicit release, activation, sleep/session changes and disposal cancel the startup retry state. Settings write errors must be visible. The tray/app icon uses the Mac hand silhouette filled black.

- Windows hand gestures now include grouped anatomical inspector sections, 1–5-finger force clicks (reported pressure only) and independent 2–5-finger pinch/spread. Keep the Apple pointer profile fixed, tap-capture priority and 120 ms drag/scroll settling. Windows Zoom is balanced Ctrl+wheel; system actions use Windows shortcut plans. See `AppleMagicTouchstream.Windows/WINDOWS_MAC_GESTURE_PORT.md` for platform limits and offline/live verification.

## Linux Notes
- The Linux CLI currently supports:
  - `list-devices`, `probe-axes`, `probe-uinput`, `doctor`, `init-config`
  - `print-keymap`, `bind-left`, `bind-right`, `swap-sides`, `print-udev-rules`
  - `selftest`, `read-events`, `read-frames`, `uinput-smoke`, `watch-runtime`, `run-engine`
  - `capture-atpcap`, `replay-atpcap`, `summarize-atpcap`, `write-atpcap-fixture`, `check-atpcap-fixture`
  - `pulse-haptics`
- Linux keyboard/mouse mode already uses `EVIOCGRAB` for exclusive pointer suppression when `KeyboardModeEnabled && TypingEnabled && !MomentaryLayerActive`.
- Desktop Linux runtime/device selection should stay explicit:
  - GUI defaults to no bound devices unless stable IDs were previously saved
  - do not silently persist first-available trackpads into Linux host settings on desktop startup
- Headless Linux runtime policy is now distinct from desktop:
  - `applemagictouchstream start`, `__background-run`, and `run-engine` use `HeadlessPureKeyboard`
  - the packaged user `systemd` service inherits that same headless policy because it launches `run-engine`
  - headless only auto-resolves devices when no saved left/right stable IDs exist; it does not persist those choices
  - headless forces `KeyboardModeEnabled=true`, `TypingEnabled=true`, and `ThreeFingerDragEnabled=false`
  - headless ignores typing-toggle actions so the background runtime cannot flip itself out of pure keyboard mode
  - headless also disables pointer-intent takeover in core, so it never transitions into `MouseCandidate` or `MouseActive`
  - headless exclusive grab is now policy-driven: in a graphical session it grabs evdev unconditionally for the pure-keyboard policy; in proven no-pointer environments it skips grab; `applemagictouchstream start --no-grab` and `applemagictouchstream run-engine --no-grab` explicitly opt out
- Graphical Linux config handoff should preserve mouse usability:
  - when bare `applemagictouchstream` is used from a graphical session while a detached headless runtime or user service is active, stop that headless runtime first
  - then launch the full tray host so the GUI becomes the active desktop path instead of leaving the headless runtime grabbing pointer input underneath it
- Prefer the Apple `if01` `-event-mouse` node when multiple event nodes represent one physical device.
- On the validated Ubuntu host, `EVIOCGABS` reports real ranges and Linux normalization should produce `MaxX=7612` and `MaxY=5065`.
- Linux force-click tuning uses the Linux pressure range directly; the Linux GUI force-click threshold slider is `80..255` and the bundled Linux default threshold is `80`.
- Over Bluetooth on the validated host, `/dev/input/by-id` may be absent; use `uniq` as the stable-id fallback.
- Linux packaging should use the dedicated `applemagictouchstream` group model rather than relying on `uaccess` alone.
- Linux actuator writes use the raw 14-byte `0x53` report payload on the validated host.
- Treat sandboxed `EVIOCGABS` failures as environment artifacts first, not immediate product bugs.

## Build Commands
- Run overlapping `dotnet build` / `dotnet publish` commands for the same project graph sequentially. Parallel publishes can collide in shared `bin/` / `obj/` paths.

### Windows
- Build:
  - `dotnet build AppleMagicTouchstream.Windows/AppleMagicTouchstream.Windows.csproj -c Release`
- Self-test:
  - `dotnet run --project AppleMagicTouchstream.Windows/AppleMagicTouchstream.Windows.csproj -c Release -- --selftest`

### Core
- Build:
  - `dotnet build AppleMagicTouchstream.Core/AppleMagicTouchstream.Core.csproj -c Release`

### Linux Builds
- Platform:
  - `dotnet build AppleMagicTouchstream.Linux/Platform/AppleMagicTouchstream.Platform.Linux.csproj -c Release`
- Host:
  - `dotnet build AppleMagicTouchstream.Linux/Host/AppleMagicTouchstream.Linux.Host.csproj -c Release`
- CLI:
  - `dotnet build AppleMagicTouchstream.Linux/AppleMagicTouchstream.Linux.csproj -c Release`
- GUI:
  - `dotnet build AppleMagicTouchstream.Linux/Gui/AppleMagicTouchstream.Linux.Gui.csproj -c Release`

### Linux Publish
- CLI framework-dependent:
  - `dotnet publish AppleMagicTouchstream.Linux/AppleMagicTouchstream.Linux.csproj -c Release -p:PublishProfile=LinuxFrameworkDependent`
- CLI self-contained:
  - `dotnet publish AppleMagicTouchstream.Linux/AppleMagicTouchstream.Linux.csproj -c Release -p:PublishProfile=LinuxSelfContained`
- GUI framework-dependent:
  - `dotnet publish AppleMagicTouchstream.Linux/Gui/AppleMagicTouchstream.Linux.Gui.csproj -c Release -p:PublishProfile=LinuxGuiFrameworkDependent`
- GUI self-contained:
  - `dotnet publish AppleMagicTouchstream.Linux/Gui/AppleMagicTouchstream.Linux.Gui.csproj -c Release -p:PublishProfile=LinuxGuiSelfContained`

### Linux `.atpcap`
- Capture:
  - `dotnet run --project AppleMagicTouchstream.Linux/AppleMagicTouchstream.Linux.csproj -c Release -- capture-atpcap /tmp/capture.atpcap 10`
- Replay:
  - `dotnet run --project AppleMagicTouchstream.Linux/AppleMagicTouchstream.Linux.csproj -c Release -- replay-atpcap /tmp/capture.atpcap /tmp/replay-trace.json`
- Summary:
  - `dotnet run --project AppleMagicTouchstream.Linux/AppleMagicTouchstream.Linux.csproj -c Release -- summarize-atpcap /tmp/capture.atpcap`
- Fixture write:
  - `dotnet run --project AppleMagicTouchstream.Linux/AppleMagicTouchstream.Linux.csproj -c Release -- write-atpcap-fixture /tmp/capture.atpcap /tmp/capture.fixture.json`
- Fixture check:
  - `dotnet run --project AppleMagicTouchstream.Linux/AppleMagicTouchstream.Linux.csproj -c Release -- check-atpcap-fixture /tmp/capture.atpcap /tmp/capture.fixture.json /tmp/replay-trace.json`

### Linux Packaging
- Debian:
  - `bash AppleMagicTouchstream.Linux/packaging/deb/build-deb.sh --version 0.1.0-dev --output-dir /tmp/applemagictouchstream-deb-out`
- Arch:
  - default non-Arch-host path:
    `./AppleMagicTouchstream.Linux/packaging/arch/build-in-docker.sh`
  - only use raw `makepkg` on a real Arch host that already has Arch tooling installed
  - if you need the raw host flow on Arch:
    `sudo pacman -S --needed base-devel dotnet-sdk`
    `cd AppleMagicTouchstream.Linux/packaging/arch`
    `makepkg -f`

## Key Files
- Windows runtime hot path: `AppleMagicTouchstream.Windows/TouchRuntimeService.cs`
- Windows Raw Input: `AppleMagicTouchstream.Windows/RawInputInterop.cs`
- Windows output injection: `AppleMagicTouchstream.Windows/WindowsDispatch/SendInputDispatcher.cs`
- Windows diagnostics/self-test: `AppleMagicTouchstream.Windows/WindowsDiagnostics/SelfTestRunner.cs`
- Shared touch engine: `AppleMagicTouchstream.Core/Engine/TouchProcessorCore.cs`
- Shared keymap/layout path:
  - `AppleMagicTouchstream.Core/Keymap/KeymapStore.cs`
  - `AppleMagicTouchstream.Core/Layout/LayoutBuilder.cs`
  - `AppleMagicTouchstream.Core/Layout/KeyLayout.cs`

## Working Rules
- Prefer extraction to `AppleMagicTouchstream.Core/` over Linux-only or Windows-only reimplementation when behavior is truly shared.
- For hot paths, prefer precomputed tables and fixed-size state arrays.
- Avoid avoidable allocations, logging, and file I/O in per-frame processing.
- When evolving the Linux GUI, prefer converging toward the Windows config surface rather than inventing parallel Linux-only layouts.
- Do not add duplicate static keymap displays when the same loaded keymap can be shown directly on the live preview surface.
- If Linux device probing or validation requires real host access, request escalation instead of guessing about driver behavior.
- The user has stated they will approve out-of-sandbox access when needed for Linux device validation; still request escalation normally.
- Do not create or enable persistent validation installs, user `systemd` services, or `/opt/AppleMagicTouchstream.Linux.validation`-style test payloads unless the user explicitly asks for that lifecycle.

## Linux Tracking
- `AppleMagicTouchstream.Linux/LINUX_GOLD.md` is now Linux-only remaining work and test tracking.
- If Linux scope, status, packaging defaults, or workflow expectations change:
  - update `AGENTS.md`
  - update `AppleMagicTouchstream.Linux/LINUX_GOLD.md`
  - keep project/package READMEs short and local to their project surface


## Hyper and modifier-only actions (2026-10-24)

The shared DispatchShortcutHelper and EngineActionResolver support Hyper and
modifier-only combinations. Hyper stays named Hyper; it is Ctrl+Shift+Alt+Meta.
Both GUI builders offer Key: None with modifier toggles, plus the Primary/Hold
Hyper preset. Keep ownership reference-counted through lift/cancel/teardown;
never synthesize a dummy character or repeat pure modifier groups. Windows
left/generic modifiers share an index; right-side/AltGr semantics remain intact.
See AppleMagicTouchstream.Core/HYPER_MODIFIERS.md. Focused Linux validation is
`selftest --hyper`; it does not access evdev/uinput or write host settings.
