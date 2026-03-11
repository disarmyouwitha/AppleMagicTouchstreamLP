# AGENTS

## Scope
- This file governs the `windows_linux/` working folder only.
- When working from `windows_linux/`, treat only these top-level folders as in scope:
  - `GlassToKey.Windows/`
  - `GlassToKey.Core/`
  - `GlassToKey.Linux/`
- Do not treat sibling folders such as `../mac/` as in scope unless the user explicitly asks.

## Repo Shape
- `GlassToKey.Windows/`: active Windows app and the current primary production target.
- `GlassToKey.Core/`: shared engine/layout/keymap/input/dispatch/runtime seam library used by both Windows and Linux.
- `GlassToKey.Linux/`: Linux product tree containing:
  - `GlassToKey.Linux/`: CLI host
  - `GlassToKey.Linux/Platform/`: Linux evdev/uinput/haptics backend
  - `GlassToKey.Linux/Host/`: Linux settings/runtime/doctor host layer
  - `GlassToKey.Linux/Gui/`: Linux Avalonia tray/config GUI
  - `GlassToKey.Linux/packaging/`: Linux package/install artifacts

## Target Selection
- Default production target: `GlassToKey.Windows/GlassToKey.Windows.csproj`
- Shared extraction target: `GlassToKey.Core/GlassToKey.Core.csproj`
- Linux backend target: `GlassToKey.Linux/Platform/GlassToKey.Platform.Linux.csproj`
- Linux host target: `GlassToKey.Linux/Host/GlassToKey.Linux.Host.csproj`
- Linux CLI target: `GlassToKey.Linux/GlassToKey.Linux.csproj`
- Linux GUI target: `GlassToKey.Linux/Gui/GlassToKey.Linux.Gui.csproj`
- If the user says "build" without more detail, prefer the target most relevant to the touched code.

## Boundaries

### Windows
- Keep Windows-only code in `GlassToKey.Windows/`.
- Windows owns WPF, WinForms, Raw Input, `SendInput`, click suppression, tray/startup UI, Windows haptics, and Windows-hosted diagnostics.
- Preserve current Windows behavior while extracting shared code.
- Keep Windows as one top-level `GlassToKey.Windows` app project unless the user explicitly asks for a larger architecture change.

### Core
- Keep shared engine/runtime seams, layout generation, keymap handling, input/contact models, and platform-neutral dispatch semantics in `GlassToKey.Core/`.
- Keep `GlassToKey.Core/` free of WPF, WinForms, Raw Input, `SendInput`, `evdev`, `uinput`, XDG/platform settings, and tray/startup/service code.
- Prefer physically moving shared behavior into `GlassToKey.Core/` instead of rebuilding similar behavior separately in Windows or Linux.
- Shared code should not remain as linked source back into `GlassToKey.Windows/` as a steady state.

### Linux
- Keep Linux evdev ingestion, reconnect supervision, `uinput` output, actuator-hidraw haptics, and Linux permission probing in `GlassToKey.Linux/Platform/`.
- Keep Linux settings/config/runtime composition and host-side diagnostics in `GlassToKey.Linux/Host/`.
- Keep `GlassToKey.Linux/` and `GlassToKey.Linux/Gui/` thin as shipped app surfaces.
- Linux work should consume platform-neutral models or semantics, not Windows virtual-key assumptions.
- Prefer semantic actions over Windows-VK fallback whenever the dependency boundary allows it.

## Structural Guardrails
- The Linux repo layout is intentionally nested under `GlassToKey.Linux/`, but the project boundaries are still real.
- `GlassToKey.Linux/GlassToKey.Linux.csproj` is the CLI project only.
- `GlassToKey.Linux/GlassToKey.Linux.csproj` explicitly excludes `Host/**`, `Platform/**`, `Gui/**`, and `packaging/**` from default item globs.
- Do not add source files from `GlassToKey.Linux/Host/`, `GlassToKey.Linux/Platform/`, or `GlassToKey.Linux/Gui/` directly to `GlassToKey.Linux/GlassToKey.Linux.csproj`; keep those as project references.
- Treat `GlassToKey.Linux/`, `GlassToKey.Linux/Platform/`, `GlassToKey.Linux/Host/`, `GlassToKey.Linux/Gui/`, and `GlassToKey.Linux/packaging/` as separate ownership zones even though they share one top-level folder.
- The nested repo layout does not change the installed product split:
  - CLI installs to `/opt/GlassToKey.Linux`
  - GUI installs to `/opt/GlassToKey.Linux.Gui`
- Do not change packaging install destinations to mirror the nested repo layout.

## Windows Notes
- `GlassToKey.Windows` is the active Windows app. Live mode runs as a tray/status app that reads touchpad report `0x05` via Raw Input and drives key mapping in the background.
- Core Windows hot-path/runtime file: `GlassToKey.Windows/TouchRuntimeService.cs`
- Windows Raw Input ingestion: `GlassToKey.Windows/RawInputInterop.cs`
- Windows output injection: `GlassToKey.Windows/WindowsDispatch/SendInputDispatcher.cs`
- Windows haptics helper: `GlassToKey.Windows/WindowsHaptics/MagicTrackpadActuatorHaptics.cs`
- Windows diagnostics/self-test surface: `GlassToKey.Windows/WindowsDiagnostics/`
- In mixed mode, OS mouse/gesture behavior should remain intact. In keyboard mode, global mouse clicks are swallowed outside the visualizer process.

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
  - `glasstokey start`, `__background-run`, and `run-engine` use `HeadlessPureKeyboard`
  - the packaged user `systemd` service inherits that same headless policy because it launches `run-engine`
  - headless only auto-resolves devices when no saved left/right stable IDs exist; it does not persist those choices
  - headless forces `KeyboardModeEnabled=true`, `TypingEnabled=true`, and `ThreeFingerDragEnabled=false`
  - headless ignores typing-toggle actions so the background runtime cannot flip itself out of pure keyboard mode
  - headless also disables pointer-intent takeover in core, so it never transitions into `MouseCandidate` or `MouseActive`
  - headless exclusive grab is now policy-driven: in a graphical session it grabs evdev unconditionally for the pure-keyboard policy; in proven no-pointer environments it skips grab; `glasstokey start --no-grab` and `glasstokey run-engine --no-grab` explicitly opt out
- Graphical Linux config handoff should preserve mouse usability:
  - when bare `glasstokey` is used from a graphical session while a detached headless runtime or user service is active, stop that headless runtime first
  - then launch the full tray host so the GUI becomes the active desktop path instead of leaving the headless runtime grabbing pointer input underneath it
- Prefer the Apple `if01` `-event-mouse` node when multiple event nodes represent one physical device.
- On the validated Ubuntu host, `EVIOCGABS` reports real ranges and Linux normalization should produce `MaxX=7612` and `MaxY=5065`.
- Over Bluetooth on the validated host, `/dev/input/by-id` may be absent; use `uniq` as the stable-id fallback.
- Linux packaging should use the dedicated `glasstokey` group model rather than relying on `uaccess` alone.
- Linux actuator writes use the raw 14-byte `0x53` report payload on the validated host.
- Treat sandboxed `EVIOCGABS` failures as environment artifacts first, not immediate product bugs.

## Build Commands
- Run overlapping `dotnet build` / `dotnet publish` commands for the same project graph sequentially. Parallel publishes can collide in shared `bin/` / `obj/` paths.

### Windows
- Build:
  - `dotnet build GlassToKey.Windows/GlassToKey.Windows.csproj -c Release`
- Self-test:
  - `dotnet run --project GlassToKey.Windows/GlassToKey.Windows.csproj -c Release -- --selftest`

### Core
- Build:
  - `dotnet build GlassToKey.Core/GlassToKey.Core.csproj -c Release`

### Linux Builds
- Platform:
  - `dotnet build GlassToKey.Linux/Platform/GlassToKey.Platform.Linux.csproj -c Release`
- Host:
  - `dotnet build GlassToKey.Linux/Host/GlassToKey.Linux.Host.csproj -c Release`
- CLI:
  - `dotnet build GlassToKey.Linux/GlassToKey.Linux.csproj -c Release`
- GUI:
  - `dotnet build GlassToKey.Linux/Gui/GlassToKey.Linux.Gui.csproj -c Release`

### Linux Publish
- CLI framework-dependent:
  - `dotnet publish GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -p:PublishProfile=LinuxFrameworkDependent`
- CLI self-contained:
  - `dotnet publish GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -p:PublishProfile=LinuxSelfContained`
- GUI framework-dependent:
  - `dotnet publish GlassToKey.Linux/Gui/GlassToKey.Linux.Gui.csproj -c Release -p:PublishProfile=LinuxGuiFrameworkDependent`
- GUI self-contained:
  - `dotnet publish GlassToKey.Linux/Gui/GlassToKey.Linux.Gui.csproj -c Release -p:PublishProfile=LinuxGuiSelfContained`

### Linux `.atpcap`
- Capture:
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- capture-atpcap /tmp/capture.atpcap 10`
- Replay:
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- replay-atpcap /tmp/capture.atpcap /tmp/replay-trace.json`
- Summary:
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- summarize-atpcap /tmp/capture.atpcap`
- Fixture write:
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- write-atpcap-fixture /tmp/capture.atpcap /tmp/capture.fixture.json`
- Fixture check:
  - `dotnet run --project GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -- check-atpcap-fixture /tmp/capture.atpcap /tmp/capture.fixture.json /tmp/replay-trace.json`

### Linux Packaging
- Debian:
  - `bash GlassToKey.Linux/packaging/deb/build-deb.sh --version 0.1.0-dev --output-dir /tmp/glasstokey-deb-out`
- Arch:
  - default non-Arch-host path:
    `./GlassToKey.Linux/packaging/arch/build-in-docker.sh`
  - only use raw `makepkg` on a real Arch host that already has Arch tooling installed
  - if you need the raw host flow on Arch:
    `sudo pacman -S --needed base-devel dotnet-sdk`
    `cd GlassToKey.Linux/packaging/arch`
    `makepkg -f`

## Key Files
- Windows runtime hot path: `GlassToKey.Windows/TouchRuntimeService.cs`
- Windows Raw Input: `GlassToKey.Windows/RawInputInterop.cs`
- Windows output injection: `GlassToKey.Windows/WindowsDispatch/SendInputDispatcher.cs`
- Windows diagnostics/self-test: `GlassToKey.Windows/WindowsDiagnostics/SelfTestRunner.cs`
- Shared touch engine: `GlassToKey.Core/Engine/TouchProcessorCore.cs`
- Shared keymap/layout path:
  - `GlassToKey.Core/Keymap/KeymapStore.cs`
  - `GlassToKey.Core/Layout/LayoutBuilder.cs`
  - `GlassToKey.Core/Layout/KeyLayout.cs`

## Working Rules
- Prefer extraction to `GlassToKey.Core/` over Linux-only or Windows-only reimplementation when behavior is truly shared.
- For hot paths, prefer precomputed tables and fixed-size state arrays.
- Avoid avoidable allocations, logging, and file I/O in per-frame processing.
- When evolving the Linux GUI, prefer converging toward the Windows config surface rather than inventing parallel Linux-only layouts.
- Do not add duplicate static keymap displays when the same loaded keymap can be shown directly on the live preview surface.
- If Linux device probing or validation requires real host access, request escalation instead of guessing about driver behavior.
- The user has stated they will approve out-of-sandbox access when needed for Linux device validation; still request escalation normally.
- Do not create or enable persistent validation installs, user `systemd` services, or `/opt/GlassToKey.Linux.validation`-style test payloads unless the user explicitly asks for that lifecycle.

## Linux Tracking
- `LINUX_GOLD.md` is now Linux-only remaining work and test tracking.
- If Linux scope, status, packaging defaults, or workflow expectations change:
  - update `AGENTS.md`
  - update `LINUX_GOLD.md`
  - keep project/package READMEs short and local to their project surface
