# Linux Project Skeleton

## Purpose

This document turns the Linux plan into a concrete repo split.

The goal is to get GlassToKey to a shape where:

- Windows keeps its existing app host
- Linux gets a native backend
- the touch engine is shared instead of duplicated

This skeleton is intentionally incremental. It does not require rewriting the current Windows app before Linux work can start.

## Target repo shape

```text
windows/
  GlassToKey/                    current Windows app host
  GlassToKey.Core/               new shared engine/library
  GlassToKey.Platform.Linux/     new Linux input/output backend
  GlassToKey.Linux/              new Linux app host
  LINUX_VERSION.md
  LINUX_PROJECT_SKELETON.md
  LINUX_EVDEV_MAPPING.md
```

## Project responsibilities

### `GlassToKey`

Keep this as the current Windows executable for now.

Responsibilities:

- WPF UI
- tray/status behavior
- Windows Raw Input
- Windows key injection
- Windows click suppression
- Windows haptics

What changes later:

- it should reference `GlassToKey.Core` once the shared extraction is complete
- Windows-specific code can optionally move to a future `GlassToKey.Platform.Windows`

### `GlassToKey.Core`

This becomes the cross-platform heart of the product.

Responsibilities:

- contact/frame model
- touch engine
- gesture detection
- dispatch event model
- layout generation
- keymap JSON model
- replay/test logic
- platform-neutral action semantics

This project should not know anything about:

- WPF
- WinForms
- Raw Input
- `SendInput`
- `uinput`
- `evdev`
- CGEvent
- startup registration
- tray icons

### `GlassToKey.Platform.Linux`

This is the Linux systems layer.

Responsibilities:

- trackpad enumeration via `evdev` and udev identity
- multitouch slot assembly from `EV_ABS`/`EV_SYN`
- Linux device reconnect handling
- virtual keyboard/mouse output via `uinput`
- Linux permission probing

This project should not own:

- gesture behavior
- key layout math
- keymap semantics
- UI

### `GlassToKey.Linux`

This is the Ubuntu/Linux app host.

Responsibilities:

- process entry point
- config storage under XDG paths
- UI or CLI host
- selecting left/right devices
- runtime startup/shutdown
- surfacing diagnostics

## Concrete extraction map

## Move first into `GlassToKey.Core`

These are the best first candidates because they are already close to platform-neutral.

### Engine and input model

- `GlassToKey/Core/Engine/TouchProcessorCore.cs`
- `GlassToKey/Core/Engine/TouchProcessorFactory.cs`
- `GlassToKey/Core/Engine/EngineModels.cs`
- `GlassToKey/Core/Engine/BindingIndex.cs`
- `GlassToKey/Core/Engine/TouchTable.cs`
- `GlassToKey/Core/Input/InputFrame.cs`
- `GlassToKey/Core/Input/ForceNormalizer.cs`
- `GlassToKey/Core/Input/ButtonEdgeTracker.cs`

### Dispatch model

- `GlassToKey/Core/Dispatch/DispatchModels.cs`
- `GlassToKey/Core/Dispatch/IInputDispatcher.cs`
- `GlassToKey/Core/Dispatch/DispatchEventQueue.cs`
- `GlassToKey/Core/Dispatch/DispatchEventPump.cs`

Notes:

- `DispatchEventPump` may stay in the host layer if its threading assumptions remain platform-specific
- the dispatch event model itself belongs in core

### Layout and keymap

- `GlassToKey/KeyLayout.cs`
- `GlassToKey/LayoutBuilder.cs`
- `GlassToKey/GridKeyPosition.cs`
- `GlassToKey/TrackpadLayoutPreset.cs`
- `GlassToKey/ColumnLayoutSettings.cs`
- `GlassToKey/KeymapStore.cs`

### Decoder and replay

- `GlassToKey/PtpReport.cs`
- `GlassToKey/TrackpadReportDecoder.cs`
- `GlassToKey/TrackpadDecoderProfile.cs`
- `GlassToKey/TrackpadDecoderDebugFormatter.cs`
- `GlassToKey/Core/Diagnostics/*`

Notes:

- Linux v1 will not ingest raw HID, but replay and Windows still need the decoder path
- this code is still logically core if it is kept free of Windows interop constants

## Keep in `GlassToKey` for now

These files are host/platform-specific and should not block the Linux extraction.

- `GlassToKey/TouchRuntimeService.cs`
- `GlassToKey/RawInputInterop.cs`
- `GlassToKey/GlobalMouseClickSuppressor.cs`
- `GlassToKey/Core/Haptics/MagicTrackpadActuatorHaptics.cs`
- `GlassToKey/Core/Dispatch/SendInputDispatcher.cs`
- `GlassToKey/MainWindow.xaml`
- `GlassToKey/MainWindow.xaml.cs`
- `GlassToKey/App.xaml`
- `GlassToKey/App.xaml.cs`
- `GlassToKey/StatusTrayController.cs`
- `GlassToKey/StartupRegistration.cs`

## Split later

These need refactoring, not blind copying.

### `RuntimeConfigurationFactory.cs`

Why split:

- some constants and layout math belong in core
- some settings assembly is host-specific

Recommended split:

- `GlassToKey.Core/Configuration/CoreRuntimeDefaults.cs`
- `GlassToKey.Core/Configuration/LayoutConfigurationFactory.cs`
- host-side settings translators stay in Windows/Linux hosts

### `UserSettings.cs`

Why split:

- it mixes app behavior, platform behavior, and engine behavior

Recommended split:

- core settings model for gesture/layout/typing configuration
- host settings model for tray, startup, permissions, platform toggles

### `DispatchKeyResolver.cs`

Why split:

- it currently resolves labels to Windows virtual keys
- Linux needs evdev key codes, not Windows VKs

Recommended replacement:

- create platform-neutral action semantics in core
- add per-platform semantic mappers in Windows and Linux backends

## New files and namespaces to introduce

## `GlassToKey.Core`

Suggested folders:

```text
GlassToKey.Core/
  Configuration/
  Diagnostics/
  Dispatch/
  Engine/
  Input/
  Keymap/
  Layout/
  Semantics/
```

Suggested first namespaces:

- `GlassToKey.Core.Engine`
- `GlassToKey.Core.Input`
- `GlassToKey.Core.Dispatch`
- `GlassToKey.Core.Layout`
- `GlassToKey.Core.Keymap`
- `GlassToKey.Core.Semantics`

## `GlassToKey.Platform.Linux`

Suggested folders:

```text
GlassToKey.Platform.Linux/
  Contracts/
  Devices/
  Evdev/
  Uinput/
  Models/
  Diagnostics/
```

Suggested first namespaces:

- `GlassToKey.Platform.Linux.Contracts`
- `GlassToKey.Platform.Linux.Devices`
- `GlassToKey.Platform.Linux.Evdev`
- `GlassToKey.Platform.Linux.Uinput`
- `GlassToKey.Platform.Linux.Models`

## `GlassToKey.Linux`

Suggested folders:

```text
GlassToKey.Linux/
  Config/
  Runtime/
  Ui/
  Commands/
```

Suggested first namespaces:

- `GlassToKey.Linux`
- `GlassToKey.Linux.Config`
- `GlassToKey.Linux.Runtime`
- `GlassToKey.Linux.Ui`

## Dependency direction

The dependency graph should be one-way:

```text
GlassToKey.Core
  ^
  |
GlassToKey.Platform.Linux
  ^
  |
GlassToKey.Linux
```

And separately:

```text
GlassToKey.Core
  ^
  |
GlassToKey
```

`GlassToKey.Core` must stay dependency-clean so both hosts can consume it.

## Concrete phase plan

## Phase 1: scaffold only

Deliverables:

- add `GlassToKey.Core`
- add `GlassToKey.Platform.Linux`
- add `GlassToKey.Linux`
- no code moved yet
- docs define exact responsibilities

This is the current scaffold state.

## Phase 2: shared model extraction

Move first:

- `InputFrame.cs`
- `ForceNormalizer.cs`
- `DispatchModels.cs`
- `KeymapStore.cs`
- layout types

Goal:

- compile the shared model without Windows target framework

## Phase 3: engine extraction

Move next:

- `TouchProcessorCore.cs`
- supporting engine files
- replay types

Goal:

- run deterministic engine tests from the core project

## Phase 4: semantic action layer

Introduce:

- semantic key ids
- semantic modifier ids
- semantic mouse actions
- platform-specific output mapping adapters

Goal:

- stop binding the engine to Windows VKs

## Phase 5: Linux backend

Add:

- evdev enumerator
- MT slot/frame assembler
- `uinput` dispatcher
- device selection contracts

Goal:

- feed real Linux touches into the shared core

## Phase 6: Linux host

Add:

- CLI or GUI host
- XDG settings
- diagnostics
- packaging hooks

## Concrete v1 Linux file plan

These are the first real implementation files I would create after the scaffold.

### In `GlassToKey.Core`

- `Semantics/SemanticAction.cs`
- `Semantics/SemanticKey.cs`
- `Semantics/SemanticModifier.cs`
- `Semantics/SemanticMouseButton.cs`
- `Semantics/ActionLabelParser.cs`

### In `GlassToKey.Platform.Linux`

- `Models/LinuxInputDeviceDescriptor.cs`
- `Models/LinuxMtContactSnapshot.cs`
- `Devices/LinuxTrackpadEnumerator.cs`
- `Evdev/LinuxMtFrameAssembler.cs`
- `Evdev/LinuxEvdevReader.cs`
- `Uinput/LinuxUinputKeyboard.cs`
- `Uinput/LinuxUinputMouse.cs`
- `LinuxInputRuntimeService.cs`
- `LinuxInputDispatcher.cs`

### In `GlassToKey.Linux`

- `Program.cs`
- `Runtime/LinuxAppRuntime.cs`
- `Config/LinuxSettingsStore.cs`
- `Commands/ListDevicesCommand.cs`
- `Commands/RunCommand.cs`

## Known refactor blockers

These are the places where extraction will require deliberate edits.

### Windows constants embedded in shared logic

Example:

- `SelfTestRunner.cs` currently uses `RawInputInterop.ReportIdMultitouch`

Fix:

- move common report constants into core, or
- stop using Windows interop constants from diagnostics

### Windows key resolution in shared flow

Example:

- `DispatchKeyResolver.cs`

Fix:

- replace with semantic action parsing in core
- map semantics to native output in platform layers

### Force-click semantics are Apple-report-shaped today

Example:

- `ForceNormalizer.cs`
- force gesture thresholds in `TouchProcessorCore.cs`

Fix:

- Linux v1 should not pretend evdev pressure is Apple phase-aware force data
- either disable force-click gestures on Linux initially or add a Linux-specific calibrated force path later

## Acceptance criteria for the skeleton

The skeleton is good enough if:

- a new contributor can see where Linux code belongs
- we know what moves to core and what stays platform-specific
- the dependency direction is explicit
- the first Linux implementation files are already named

That is the purpose of this scaffold.
