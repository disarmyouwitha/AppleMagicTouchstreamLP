# Linux Version Plan

## Bottom line

Yes, a Linux version is realistic for modern Ubuntu.

No, it is not "just a front-end" on top of the current Windows app.

The good news is that Linux already has mainline Apple Magic Trackpad support, so we do **not** need to port or write a Linux kernel driver first. The real job is to build a Linux runtime host around GlassToKey's reusable logic:

- read Magic Trackpad events from Linux input devices
- translate them into GlassToKey frames
- run the existing touch/gesture engine
- inject key and mouse output through Linux APIs
- add Linux configuration UI, packaging, and permissions

My recommendation is:

1. Reuse the Windows C# engine and data model.
2. Do **not** reuse the Windows Raw Input or `SendInput` path.
3. Build a Linux backend on top of `evdev`/`libevdev` for input and `uinput` for output.
4. Treat click suppression / full "keyboard mode" as a second-phase feature, because that is the hardest Linux-specific part on Wayland.

## What the existing codebase tells us

### Windows app: reusable core plus Windows-only shell

The Windows app is currently a Windows-targeted WPF executable:

- `GlassToKey/GlassToKey.csproj` targets `net10.0-windows` and enables WPF/WinForms.
- `GlassToKey/TouchRuntimeService.cs` is strongly tied to Windows APIs:
  - Raw Input device registration
  - `WM_INPUT`
  - `SendInputDispatcher`
  - `GlobalMouseClickSuppressor`
  - `MagicTrackpadActuatorHaptics`
- `GlassToKey/RawInputInterop.cs` is a full Windows Raw Input interop layer.
- `GlassToKey/Core/Dispatch/DispatchKeyResolver.cs` resolves actions into Windows virtual keys.

But a large chunk is already portable in shape:

- `GlassToKey/Core/Engine/TouchProcessorCore.cs`
- `GlassToKey/Core/Engine/TouchProcessorFactory.cs`
- `GlassToKey/Core/Dispatch/DispatchModels.cs`
- `GlassToKey/Core/Dispatch/IInputDispatcher.cs`
- `GlassToKey/KeymapStore.cs`
- layout/config models
- replay and self-test infrastructure in `GlassToKey/Core/Diagnostics/*`

That is the right seam for a Linux port.

### macOS app: same product idea, separate platform runtime

The macOS code confirms the architecture pattern:

- `../mac/GlassToKey/GlassToKey/Runtime/InputRuntimeService.swift` reads trackpad events through `OpenMultitouchSupport`
- `../mac/GlassToKey/GlassToKey/KeyEventDispatcher.swift` injects output through `CGEvent`
- `../mac/GlassToKey/GlassToKey/Engine/TouchProcessorEngine.swift` is a separate platform engine implementation

That means the project has already evolved as:

- shared product behavior
- per-platform input runtime
- per-platform output injection
- per-platform UI

For Linux, the fastest route is **not** to write a third engine in another language. The fastest route is to extract the existing Windows C# engine into a cross-platform library and build a Linux host around it.

## What Linux already gives us

### Mainline driver support already exists

Linux already ships Apple Magic Trackpad support in the upstream `hid-magicmouse` driver. Current upstream source shows support for:

- Magic Trackpad 2
- Bluetooth reports
- USB reports
- USB-C Magic Trackpad 2 IDs

The driver configures multitouch slots and exposes:

- `ABS_MT_POSITION_X`
- `ABS_MT_POSITION_Y`
- `ABS_MT_TOUCH_MAJOR`
- `ABS_MT_TOUCH_MINOR`
- `ABS_MT_ORIENTATION`
- `ABS_MT_PRESSURE`

That matters because it means GlassToKey on Linux can consume **already-decoded input events** instead of parsing raw HID reports the way the Windows runtime does.

### For Ubuntu specifically

Ubuntu tracked the USB-C Magic Trackpad 2 support gap and marked it fixed for Noble in 2025. For "modern Ubuntu", that means the driver story is now good enough that the Linux port should be designed as a userspace application, not a driver project.

## Answer to the main question

### "Can we use the Windows GlassToKey and just write a Linux front-end?"

Not directly.

What can be reused:

- touch processing logic
- gesture rules
- layout generation
- keymap JSON model
- replay/capture/self-test concepts

What cannot be reused as-is:

- WPF UI
- Windows Raw Input ingestion
- Windows virtual-key dispatch
- click suppression hook
- Windows haptics implementation

So the honest answer is:

- **not** "just a front-end"
- **also not** a full rewrite

It is a medium-size platform port if we refactor the code correctly.

## Recommended Linux architecture

## Principle

On Linux, do **not** start from raw HID unless forced to.

Start from the kernel's evdev event stream, because Linux is already doing the hard device parsing in `hid-magicmouse`.

### Ingestion layer

Use one event device per selected trackpad and read it through:

- `libevdev` (preferred wrapper), or
- direct `evdev` ioctl/read calls

Why `libevdev`:

- it normalizes event reading
- it exposes device capabilities and abs ranges
- it is the standard userspace wrapper for this layer

Do **not** use `libinput` as the primary source for GlassToKey gesture recognition. `libinput` is too high-level for this use case; GlassToKey wants raw contact data, slot state, pressure, and exact frame boundaries.

### Event model

Build a Linux event reader that reconstructs a per-frame contact snapshot from:

- `ABS_MT_SLOT`
- `ABS_MT_TRACKING_ID`
- `ABS_MT_POSITION_X`
- `ABS_MT_POSITION_Y`
- `ABS_MT_PRESSURE`
- `ABS_MT_ORIENTATION`
- optional `ABS_MT_TOUCH_MAJOR` / `ABS_MT_TOUCH_MINOR`
- `BTN_TOUCH`
- `BTN_LEFT` if the device exposes physical click state
- `SYN_REPORT` as frame boundary

Then convert that snapshot into the app's existing `InputFrame` / `ContactFrame` shape.

### Output layer

Inject keys and mouse clicks through `/dev/uinput`.

This is the correct Linux equivalent of the Windows `SendInput` path because it creates a virtual input device seen by the compositor/desktop as hardware input.

That is the important Wayland point:

- desktop automation APIs are limited on Wayland
- a `uinput` virtual keyboard/mouse is the robust approach

### UI layer

For fastest delivery, keep Linux in C# and use one of these:

1. Avalonia
2. a minimal CLI + debug window first, then UI later

I recommend:

1. first milestone: headless daemon + CLI/config file + optional debug window
2. second milestone: full Linux GUI

Reason: the platform work is in input/output and permissions, not in drawing controls.

### Device identity

Use stable Linux device identity from:

- `/dev/input/by-id/*`
- device `uniq` when `/dev/input/by-id/*` is not present, which was the case for the tested Bluetooth Apple trackpads
- udev properties for vendor/product
- device name and phys path as fallback

Do not key device selection off ephemeral `/dev/input/eventN` numbers.

Observed on current Ubuntu 24.04 hardware:

- USB Apple trackpads exposed stable `/dev/input/by-id/*` links
- Bluetooth Apple trackpads did not expose `/dev/input/by-id/*` links
- both transports exposed the same multitouch axis ranges and worked with the same normalized evdev frame path

## Proposed refactor in this repo

### Step 1: extract a cross-platform core library

Create a new library project, for example:

- `GlassToKey.Core`

Move or copy into it:

- `Core/Engine/*`
- `Core/Dispatch/DispatchModels.cs`
- `Core/Dispatch/IInputDispatcher.cs`
- layout builders and geometry types
- `KeymapStore.cs`
- config models used by engine/runtime
- replay/self-test pieces that do not require Windows APIs

Keep out of this core:

- `RawInputInterop.cs`
- `TouchRuntimeService.cs`
- `SendInputDispatcher.cs`
- `GlobalMouseClickSuppressor.cs`
- `MagicTrackpadActuatorHaptics.cs`
- WPF UI files

### Step 2: replace Windows key semantics with platform-neutral semantics

This is the biggest architectural cleanup required before Linux feels clean.

Right now the Windows runtime resolves labels to Windows virtual keys in `DispatchKeyResolver.cs`. That is fine for Windows, but Linux wants evdev key codes.

Recommended change:

- keep `KeyAction.Label` as the stored user-facing format for compatibility
- add a platform-neutral semantic layer, for example:
  - `SemanticKey.A`
  - `SemanticKey.Enter`
  - `SemanticModifier.Shift`
  - `SemanticMouseButton.Left`
- `SemanticAction.BrightnessUp`
- have each platform map semantic actions to native output codes

This avoids making Linux pretend that Windows VK codes are portable.

Current repo status:

- the shared dispatch model now carries `DispatchSemanticAction` metadata alongside Windows VK fields
- `EngineKeyAction` now preserves semantic identity through dispatch generation instead of relying on VKs alone
- Windows still uses the existing VK-based output path, but Linux output work now has a semantic payload to target
- the first Linux `uinput` dispatcher now exists and can emit a smoke-test key through a virtual device on this host

### Step 3: add a Linux runtime backend

Create a project such as:

- `GlassToKey.Platform.Linux`

Responsibilities:

- enumerate candidate trackpads
- open selected event devices
- read and assemble multitouch frames
- expose `InputFrame`-compatible snapshots
- inject output through `uinput`
- optionally support an exclusive-grab mode

Suggested internal pieces:

- `LinuxTrackpadEnumerator`
- `LinuxEvdevReader`
- `LinuxMtFrameAssembler`
- `LinuxInputRuntimeService`
- `LinuxUinputDispatcher`
- `LinuxPermissionProbe`

Current repo status:

- `LinuxInputRuntimeService` can now stream frames either to a Linux-specific observer or directly into the shared `TrackpadFrameEnvelope` / `ITrackpadFrameTarget` seam
- `GlassToKey.Linux` exposes `probe-uinput` to validate `/dev/uinput` presence and rw access separately from evdev capture
- `GlassToKey.Linux uinput-smoke A` now validates basic virtual key injection through the Linux dispatcher path

### Step 4: add a Linux app host

Create:

- `GlassToKey.Linux`

Responsibilities:

- config loading/saving
- device selection
- UI or tray/window
- startup integration
- logs and diagnostics

## Feature-by-feature plan

### Phase 0: spike / proof of life

Goal: prove the kernel event stream has what we need on Ubuntu.

Deliverables:

- enumerate Magic Trackpad devices on Ubuntu
- print capability matrix for each device
- read live `ABS_MT_*` frames and `BTN_LEFT`
- verify pressure exists on target hardware
- verify one-trackpad and two-trackpad detection

Exit criteria:

- confirmed event stream contains enough data to feed `InputFrame`
- confirmed `uinput` can inject keystrokes recognized by both X11 and Wayland sessions

Estimated effort:

- 1 to 3 days

### Phase 1: core extraction

Goal: make the engine build without Windows.

Deliverables:

- new cross-platform core project
- existing self-tests running against the extracted core
- semantic action model or an equivalent abstraction boundary

Exit criteria:

- engine compiles on Linux with `dotnet build`
- deterministic replay/self-tests still pass

Estimated effort:

- 3 to 7 days

### Phase 2: Linux input pipeline

Goal: feed the core from evdev.

Deliverables:

- evdev device enumeration
- MT slot/frame assembler
- translation from evdev state to `InputFrame`
- support for left/right selected trackpads

Important detail:

Use actual device abs ranges from the Linux device instead of assuming Windows constants. The engine already normalizes by `maxX`/`maxY`, so Linux should pass the real values from `EVIOCGABS`.

Exit criteria:

- live touches render as correct key hits
- single-finger typing works
- gesture counts are stable

Estimated effort:

- 4 to 8 days

### Phase 3: Linux output pipeline

Goal: inject keys and clicks.

Deliverables:

- virtual keyboard via `uinput`
- virtual mouse/button device via `uinput`
- semantic-to-evdev key mapping table
- support for modifier down/up, tap, hold, repeat

Exit criteria:

- text entry works in normal Ubuntu apps
- modifiers and repeated keys work
- mouse button gestures work

Estimated effort:

- 3 to 6 days

### Phase 4: usable alpha

Goal: parity with the most important current behavior.

Deliverables:

- device picker
- settings persistence
- keymap import/export
- layout selection
- headless runtime or simple UI
- capture/replay path adapted for Linux

Exit criteria:

- user can select trackpad(s), type, remap, restart, and recover from unplug/replug

Estimated effort:

- 4 to 8 days

### Phase 5: keyboard mode / suppression

Goal: emulate the Windows "full keyboard, no mouse intent" mode as closely as Linux allows.

This is the hardest feature on Linux.

The issue:

- in mixed mode, passive reading is easy because the desktop still consumes the trackpad normally
- in keyboard mode, the compositor will also continue to receive the real trackpad unless we actively suppress it

Practical options:

1. `EVIOCGRAB` the selected trackpad device while keyboard mode is active
2. compositor-specific integrations
3. accept reduced parity on first Linux release

Recommended path:

- first Linux alpha ships mixed mode first
- add optional exclusive-grab keyboard mode later

Warnings about exclusive grab:

- it can interfere with normal desktop behavior
- it must always release on crash/exit
- it is a poor fit for system-wide polish if multiple consumers expect the device
- `libevdev` documentation explicitly warns that grabbing is generally a bad idea unless you are intentionally taking full control of the device

Estimated effort:

- 3 to 8 days for a safe first implementation
- more for polish and edge cases

### Phase 6: haptics

Goal: restore trackpad haptic feedback if possible.

This is optional and high-risk.

The existing Windows implementation is deeply HID/Windows-specific. Linux input support does not automatically give us a clean userspace haptics API for Magic Trackpad 2 actuator control.

Recommended plan:

- defer haptics until the typing pipeline works
- investigate `hidraw` or output reports later
- treat this as an experimental feature, not part of v1

Estimated effort:

- unknown / research-heavy

## Linux-specific design decisions

### 1. Use evdev, not raw HID, for v1

Reason:

- upstream Linux already parses the device
- lower complexity
- better compatibility across Ubuntu kernels
- less reverse-engineering risk

Only add a raw HID path if evdev is missing a critical signal we truly need.

### 2. Use `uinput`, not desktop automation APIs

Reason:

- works with Wayland better than app-level injection hacks
- integrates as a virtual keyboard/mouse device
- matches how serious Linux input remappers behave

### 3. Keep the existing capture/replay strategy

The current repo already has strong replay/self-test infrastructure and supports cross-platform capture normalization. That is a major advantage for the Linux port.

Recommended extension:

- add a Linux evdev capture adapter
- optionally add a converter from Linux capture -> canonical `InputFrame` replay fixture

### 4. Plan for Wayland first

Modern Ubuntu is Wayland-first. If the Linux version works only on X11, it will feel obsolete immediately.

So:

- input read path should be compositor-agnostic
- output should use `uinput`
- suppression/grab behavior should be tested specifically under GNOME Wayland

## Packaging and permissions for Ubuntu

This app will need privileged device access compared to a normal desktop app.

Required access:

- read selected `/dev/input/event*`
- write `/dev/uinput`

Expected install tasks:

- a udev rule for the app or a dedicated group
- instructions or installer for group membership
- optional systemd user service

Recommended deliverables:

- Debian package or install script
- udev rule file
- post-install permission check command

Example permission areas to document:

- `input` group or equivalent read access
- `uinput` access
- logout/login after group change

This packaging/permissions work is mandatory for a real Ubuntu release.

## Risks and unknowns

### Low risk

- basic touch ingestion
- key injection through `uinput`
- reusing layout/keymap logic
- replay/self-test reuse

### Medium risk

- dual-trackpad device management
- semantic key mapping parity
- media/brightness/system key behavior across desktops

### High risk

- keyboard-mode suppression parity under Wayland
- haptics
- exact force-click parity if the evdev stream differs by hardware/firmware

## Suggested milestone order

1. Linux probe tool
2. cross-platform core extraction
3. Linux evdev reader
4. Linux `uinput` dispatcher
5. headless typing alpha
6. settings UI
7. keyboard-mode suppression
8. haptics

## Realistic effort estimate

If one person who already knows this codebase is doing it:

- proof of concept: about 1 week
- useful alpha on Ubuntu: about 3 to 5 weeks
- polished daily-driver Linux version: about 6 to 10 weeks

That assumes:

- we reuse the existing C# engine
- we do **not** chase haptics in v1
- we accept that keyboard-only suppression may land after mixed-mode typing

If you tried to keep the current Windows project structure unchanged and "just swap the front-end", it would take longer, because the wrong abstraction boundary would fight you the whole time.

## Recommended v1 scope

Ship this first:

- Ubuntu 24.04+ support
- Wayland-compatible key injection through `uinput`
- one or two Magic Trackpad devices
- mixed mode typing
- keymap import/export
- replay/self-tests
- no haptics
- keyboard mode marked experimental or deferred

That is the smallest scope that still feels like a real Linux release.

## Concrete buildout plan

### Workstream A: core extraction

- create `GlassToKey.Core`
- move engine/layout/keymap/replay code into it
- isolate Windows-only code behind interfaces
- add semantic action abstraction

### Workstream B: Linux runtime

- implement device enumeration from udev/evdev
- implement multitouch frame assembler
- implement `uinput` keyboard/mouse output
- add health logging and reconnect logic

### Workstream C: Linux app host

- settings storage under XDG config paths
- device picker
- startup behavior
- optional tray/status integration

### Workstream D: tests and diagnostics

- keep deterministic engine self-tests
- add Linux capture tool
- add Ubuntu smoke test checklist
- record real-device fixtures

### Workstream E: packaging

- package dependencies
- udev rules
- installer script or `.deb`
- troubleshooting docs

## Final recommendation

Pursue the Linux version.

The port is feasible because the hardest low-level part, the device driver, is already in mainline Linux and available on modern Ubuntu. The right plan is to reuse GlassToKey's engine and rebuild only the platform shell.

If you want the shortest path to success, the target architecture should be:

- shared C# core
- Linux evdev reader
- Linux `uinput` injector
- Ubuntu-first packaging
- keyboard-mode suppression and haptics deferred until after the typing path is stable

## Sources used

Local code:

- `GlassToKey/GlassToKey.csproj`
- `GlassToKey/TouchRuntimeService.cs`
- `GlassToKey/RawInputInterop.cs`
- `GlassToKey/TrackpadReportDecoder.cs`
- `GlassToKey/Core/Engine/*`
- `GlassToKey/Core/Dispatch/*`
- `GlassToKey/Core/Diagnostics/*`
- `GlassToKey/README.md`
- `../mac/GlassToKey/GlassToKey/Runtime/InputRuntimeService.swift`
- `../mac/GlassToKey/GlassToKey/Engine/TouchProcessorEngine.swift`
- `../mac/GlassToKey/GlassToKey/KeyEventDispatcher.swift`

Online sources:

- Linux `hid-magicmouse` source:
  - https://raw.githubusercontent.com/torvalds/linux/master/drivers/hid/hid-magicmouse.c
- Linux multitouch protocol documentation:
  - https://docs.kernel.org/input/multi-touch-protocol.html
- Linux event code documentation:
  - https://docs.kernel.org/input/event-codes.html
- Linux `uinput` documentation:
  - https://docs.kernel.org/input/uinput.html
- `libevdev` grabbing documentation:
  - https://www.freedesktop.org/software/libevdev/doc/latest/group__init.html
- Ubuntu Noble Magic Trackpad 2 USB-C fix tracking:
  - https://bugs.launchpad.net/ubuntu/+source/linux/+bug/2098063
- Upstream Linux USB-C Magic Trackpad 2 support commit reference:
  - https://github.com/torvalds/linux/commit/c9844f2f1f70e41e4ec6c1acef8fe575ae79e44b
