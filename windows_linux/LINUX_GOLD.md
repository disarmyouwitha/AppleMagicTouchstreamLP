# Linux Gold

This is the canonical current Linux source of truth for the `windows_linux/` repo.

Keep it aligned with:

- `AGENTS.md`
- `GlassToKey.Linux/README.md`
- `GlassToKey.Linux/Platform/README.md`
- `GlassToKey.Linux/Gui/README.md`
- `GlassToKey.Linux/packaging/README.md`

## Architectural Boundaries

- Keep Windows-only code in `GlassToKey.Windows/`.
- Keep shared engine/runtime seams, layout, keymap, input models, and platform-neutral dispatch semantics in `GlassToKey.Core/`.
- Keep `GlassToKey.Core/` free of WPF, WinForms, Raw Input, `SendInput`, `evdev`, `uinput`, XDG/platform settings, and tray/startup/service code.
- Keep Linux evdev ingestion, reconnect supervision, `uinput` output, haptics probing/writes, and Linux permission probing in `GlassToKey.Linux/Platform/`.
- Keep Linux settings/config/runtime composition and host-side diagnostics in `GlassToKey.Linux/Host/`.
- Keep `GlassToKey.Linux/` and `GlassToKey.Linux/Gui/` thin as shipped app surfaces.
- Prefer physically moving shared behavior into `GlassToKey.Core/` instead of rebuilding similar logic separately in Linux or Windows hosts.
- Prefer platform-neutral semantic actions over Windows-VK assumptions in any shared flow.
- Treat touch processing as latency-sensitive: no avoidable allocations, logging, or file I/O on hot paths.
- The Linux repo layout is intentionally nested under `GlassToKey.Linux/`, but the project boundaries are still real:
  - `GlassToKey.Linux/GlassToKey.Linux.csproj` is the CLI project only.
  - It explicitly excludes `Host/**`, `Platform/**`, `Gui/**`, and `packaging/**` from default item globs.
  - `Host/`, `Platform/`, and `Gui/` stay separate projects and must remain project references rather than source-file includes.
- The nested repo layout does not change the installed product split:
  - CLI installs to `/opt/GlassToKey.Linux`
  - GUI installs to `/opt/GlassToKey.Linux.Gui`

## Validated Host Findings

- Apple trackpads can expose Type B multitouch slots and parallel legacy absolute fields on the same evdev node.
  - The Linux product path now treats the MT slot stream as authoritative and ignores the legacy compatibility fields.
- Prefer the Apple `if01` `-event-mouse` node when multiple event nodes represent one physical trackpad.
- Real `EVIOCGABS` probing works on the host and should be used instead of hardcoded Windows ranges.
- The tested host reported:
  - slot `0..15`
  - X `-3678..3934`
  - Y `-2478..2587`
  - pressure `0..253`
- Linux normalization should subtract axis minima and pass spans `MaxX=7612` and `MaxY=5065`.
- Over Bluetooth on the tested host, `/dev/input/by-id` was absent; stable identity fell back to device `uniq`.
- The same normalized frame path was validated over both USB and Bluetooth on the tested Apple trackpads.
- `run-engine` has been validated end-to-end on the host:
  - evdev input
  - shared engine/runtime host
  - dispatch pump
  - `uinput` output into a real focused app
- Linux keyboard/mouse mode already drives exclusive pointer suppression through `EVIOCGRAB`.
  - The runtime toggles grab on and off from `KeyboardModeEnabled && TypingEnabled && !MomentaryLayerActive`.
  - This is implemented behavior, not a deferred design item.
- Packaging validation changed the permission direction:
  - `uaccess` alone was not reliable for recreated Bluetooth nodes in the tested Ubuntu session.
  - Checked-in packaging now prefers a dedicated `glasstokey` group with `0660` modes.
  - `TAG+="uaccess"` remains only an additive desktop-session hint.
- The `glasstokey` group flow has been validated through a real install/relogin cycle on the host:
  - `/dev/uinput` and matched `/dev/input/event*` nodes came up as `root:glasstokey`
  - `doctor` reported `Summary: ok` after session refresh
  - stable-id bindings survived event-node renumbering across reboot/reconnect
- The checked-in package-manager install flow and user-service flow were validated on the Ubuntu host.
- Linux haptics has been validated end-to-end on the host for both tested USB trackpads:
  - older Magic Trackpad (`0x05ac/0x0265`) actuator node `/dev/hidraw11`
  - newer Magic Trackpad (`0x05ac/0x0324`) actuator node `/dev/hidraw15`
- The working Linux actuator write shape on this host is the raw 14-byte `0x53` report payload.
  - Do not treat the Windows-style 64-byte padded write as the Linux default.
- Packaged/user-mode haptics depends on the same `glasstokey` group model as input/output:
  - matched actuator `/dev/hidraw*` nodes must come up as `root:glasstokey` with mode `0660`
  - `doctor` should report `HapticsWriteAccess: ok` for each USB-bound trackpad
  - both validated USB product ids need actuator rules: `0x0265` and `0x0324`
- The Linux user service now runs `run-engine` until interrupted rather than timing out after 10 seconds.
- Packaged reconnect validation is proven on the host for both:
  - Bluetooth power off/on churn
  - USB unplug/replug churn
- A reconnect bug was fixed in the runtime supervision path:
  - a dropped engine frame no longer causes a fake evdev disconnect/rebind loop
- Real Linux `.atpcap` fixtures exist under `GlassToKey.Linux/fixtures/linux/` for:
  - `bluetooth-trackpad`
  - `bluetooth-reconnect`
  - `usb-trackpad`
- Linux already ships its own bundled `GLASSTOKEY_DEFAULT_KEYMAP.json`.
  - It no longer ships Windows-only defaults like `EMOJI`, `LWin`, or `Win+H`.
- Linux replay/fixture tooling is already the preferred long-form diagnostic path.
  - Separate live dispatch tracing is not a product requirement and is not planned.
- Sandbox caveat:
  - `EVIOCGABS` can fail inside the coding sandbox even when it works on the real host
  - treat that as an environment validation issue first, not product-side evidence that fallback logic is required

## Open Work

Only keep real unchecked work here.

### 1. Arch Validation

- Validate and document the checked-in Arch package install/runtime story on a real Arch test environment.

### 2. Shared Semantic Cleanup

- Reduce remaining shared-flow dependence on Windows virtual-key compatibility where semantic actions should be authoritative.

### 3. Linux Force-Click Decision

- Decide whether Linux force-click parity is explicitly out of scope for v1 or worth pursuing later as a Linux-specific calibrated pressure path.

## Build Commands

Run overlapping builds/publishes for the same project graph sequentially.

### Shared/Linux builds

- `dotnet build GlassToKey.Core/GlassToKey.Core.csproj -c Release`
- `dotnet build GlassToKey.Linux/Platform/GlassToKey.Platform.Linux.csproj -c Release`
- `dotnet build GlassToKey.Linux/Host/GlassToKey.Linux.Host.csproj -c Release`
- `dotnet build GlassToKey.Linux/GlassToKey.Linux.csproj -c Release`
- `dotnet build GlassToKey.Linux/Gui/GlassToKey.Linux.Gui.csproj -c Release`

### Linux publish

- `dotnet publish GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -p:PublishProfile=LinuxFrameworkDependent`
- `dotnet publish GlassToKey.Linux/GlassToKey.Linux.csproj -c Release -p:PublishProfile=LinuxSelfContained`
- `dotnet publish GlassToKey.Linux/Gui/GlassToKey.Linux.Gui.csproj -c Release -p:PublishProfile=LinuxGuiFrameworkDependent`
- `dotnet publish GlassToKey.Linux/Gui/GlassToKey.Linux.Gui.csproj -c Release -p:PublishProfile=LinuxGuiSelfContained`

### Linux package build

- `bash GlassToKey.Linux/packaging/deb/build-deb.sh --version 0.1.0-dev --output-dir /tmp/glasstokey-deb-out`

### Arch local package build

- `sudo pacman -S --needed base-devel dotnet-sdk`
- `cd GlassToKey.Linux/packaging/arch`
- `makepkg -f`

## Doc Rule

If Linux scope, status, or packaging reality changes:

- update this file first
- then update `AGENTS.md`
- keep project/package READMEs short and local to their project surface
