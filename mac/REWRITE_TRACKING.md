# GlassToKey macOS Rewrite Tracking

## Purpose
Track a ground-up rewrite of the macOS app and capture stack, using `REWRITE.md` as strategy and `../windows/glasstokey` as runtime parity reference.

## Next Instance Start Here
1. Read `REWRITE.md` for intent, constraints, and parity goals.
2. Read `REWRITE_TRACKING.md` for execution status, phase checklists, and current next slice.

## Scope
- In scope: Objective-C capture bridge (`Framework/OpenMultitouchSupportXCF`), Swift wrapper (`Sources/OpenMultitouchSupport`), app runtime/UI (`GlassToKey/GlassToKey`), parity test infrastructure.
- Out of scope: changing key semantics, adding logging/file I/O on hot paths, hand-editing generated XCFramework artifacts.

## Cutover Directive (2026-02-21)
- Rewrite-first cutover is approved for tonight.
- Minimize effort spent preserving legacy runtime behavior.
- Remove/replace legacy runtime code as soon as rewrite path compiles and passes replay/build verification.

## Baseline Audit (Current macOS)

### 1) Objective-C capture bridge (`OpenMTManager`)
- Raw and object callbacks share callback handlers; object path still allocates per frame (`OpenMTTouch` + `OpenMTEvent`).
- Object listener dispatch hops through a serial response queue (`dispatchResponseAsync`) and can backlog under load.
- Device routing relies on mutable maps keyed by string IDs and pointer dictionaries; read/write ownership is not explicit.
- Device ref lifecycle mixes cached refs, list scans, and string conversion; active-device refresh restarts all devices.
- Callback mode supports both refcon and legacy fallback paths in hot callback code.

### 2) Swift wrapper (`OMSManager`)
- Raw path is improved (buffer pooling), but stream fan-out still duplicates work per consumer (`rawTouchStream(forDeviceIDs:)` detached relays).
- Touch conversion is still performed in multiple layers depending on consumer.
- Device index mapping and continuation fan-out are embedded in one class with capture concerns.

### 3) App runtime (`ContentViewModel` + `ContentView`)
- `ContentViewModel` mixes runtime engine, device/session control, UI publishing, and editor integration in one large actor/object.
- `ContentView` and sidebar both observe the same view model; this couples editor controls with runtime updates.
- Surface rendering currently uses SwiftUI `Canvas`; keymap editor and visualization state still share invalidation pressure.
- Status polling (50 ms) exists, but status state and touch rendering state still share the same top-level observable model.

### 4) Input dispatch and text services
- Key dispatch is centralized (`KeyEventDispatcher`) but tied directly to app runtime internals.
- Autocorrect and AX replacement are functional but coupled to live dispatch events and app-level service wiring.

## Current-to-Target Migration Map
| Current Component | Current Location | Target Component |
| --- | --- | --- |
| Multitouch capture manager | `Framework/OpenMultitouchSupportXCF/OpenMTManager.m` | `MTCaptureBridge` raw-first manager (`OpenMTManagerV2`) |
| Listener/event object bridge | `Framework/OpenMultitouchSupportXCF/OpenMTListener.m`, `OpenMTEvent.m`, `OpenMTTouch.m` | Debug/compat adapter off fast path |
| Swift multitouch wrapper | `Sources/OpenMultitouchSupport/OMSManager.swift` | `InputRuntimeService` + frame fan-out boundary |
| Runtime state machine + UI publishing | `GlassToKey/GlassToKey/ContentViewModel.swift` | `EngineActor` + `SnapshotService` + UI adapter |
| Surface rendering | `GlassToKey/GlassToKey/ContentView.swift` (`CombinedTrackpadCanvas`) | `TrackpadSurfaceView` (AppKit) |
| App status lifecycle | `GlassToKey/GlassToKey/GlassToKeyApp.swift` | thin app shell + mode indicator consumer |
| Dispatch posting | `GlassToKey/GlassToKey/KeyEventDispatcher.swift` | `DispatchService` pump backend |
| Autocorrect and AX text replacement | `GlassToKey/GlassToKey/AutocorrectEngine.swift`, `AccessibilityTextReplacer.swift` | separate text-correction service behind dispatch boundary |

## Windows Reference Patterns To Mirror
- Explicit pipeline separation:
  - input capture service (`TouchRuntimeService`)
  - engine actor (`TouchProcessorActor`)
  - dispatch queue + pump (`DispatchEventQueue`, `DispatchEventPump`)
  - dedicated renderer (`TouchView` + explicit `InvalidateVisual`)
  - fixed status timer for UI state.
- Snapshot-based UI updates and selective invalidation, not broad observable-tree invalidation.
- Strong diagnostics/replay model around engine behavior parity.

## Target Architecture (macOS Rewrite)

### Runtime layers
1. `MTCaptureBridge` (Objective-C)
- Single high-performance raw callback path.
- Numeric device registry and stable callback contexts.
- Zero allocations in callback fast path.

2. `InputRuntimeService` (Swift)
- Owns lifecycle of capture bridge, device routing, and frame ingest.
- Pushes `RawFrame` into engine queue only.
- No UI publishing and no editor logic.

3. `EngineActor` (Swift first, Rust-ready contract)
- Single-threaded state machine execution.
- Produces dispatch events + immutable snapshots.
- No AppKit/SwiftUI dependencies.

4. `DispatchService`
- Ring/queue for key/mouse/haptic events.
- Separate pump thread/queue to avoid engine stalls.

5. `SnapshotService`
- `RenderSnapshot` cadence (touch/geometry/highlights).
- `StatusSnapshot` cadence (contact counts, mode, intent, diagnostics).

6. `TrackpadSurfaceView` (AppKit)
- Dedicated renderer consuming render snapshots.
- Explicit redraw policy independent from sidebar/editor updates.

7. `EditorShell` (SwiftUI)
- Settings/keymap/editor controls only.
- Communicates with runtime through command APIs.

### Thread ownership contract
- Capture callback thread: frame ingest only, no allocations, no UI.
- Engine thread/actor: state transitions, binding, dispatch decisions.
- Dispatch thread: CGEvent/haptics posting.
- Main thread: AppKit/SwiftUI presentation and user commands.

## Data Contracts (Rewrite)
- `RawFrame`: timestamp, deviceNumericID, contact array, frame sequence.
- `DispatchEvent`: key/mouse/haptic intent with metadata.
- `RenderSnapshot`: left/right touches, highlighted key/button, layer, revision.
- `StatusSnapshot`: intent mode, typing/mouse mode, contact counts, diagnostics counters.

## Execution Plan

Phase status summary (synced with `REWRITE.md`, as of 2026-02-21):
- Phase 0: In Progress
- Phase 1: In Progress
- Phase 2: Completed
- Phase 3: In Progress
- Phase 4: Completed
- Phase 5: Not Started
- Phase 6: Not Started

## Phase 0 - Behavior Freeze + Replay Baseline
- [x] Capture canonical behavior traces from current macOS.
- [ ] Capture canonical behavior traces from Windows reference runtime.
- [x] Define parity fixture format (`ATPCAP01` v3 binary fixture).
- [x] Add deterministic replay harness entrypoint for macOS engine.

Exit criteria:
- [x] Replays run headless and produce stable snapshot/dispatch transcripts.

## Phase 1 - New Objective-C Capture Bridge
- [x] Introduce `OpenMTManagerV2` (or equivalent) behind feature flag.
- [x] Raw-first callback API with preallocated frame adapters.
- [x] Replace string-based hot-path mapping with numeric registry.
- [x] Remove response queue hops from fast path.
- [x] Define explicit lock/queue ownership for registry mutations.

Exit criteria:
- [ ] No callback-path heap allocations in normal operation.
- [ ] Stable capture with one and two trackpads at sustained load.

## Phase 2 - Runtime Service + Engine Boundary (Swift)
- [x] Split current `ContentViewModel` responsibilities into runtime services.
- [x] Build `InputRuntimeService` and `EngineActor` interfaces.
- [x] Move touch processing state machine out of `ContentViewModel`.
- [x] Keep only minimal compatibility needed for defaults/keymap persistence (no broad runtime fallback work).

Exit criteria:
- [x] UI can be disconnected while runtime keeps processing.
- [x] Engine accepts replay input and emits deterministic snapshots.

## Phase 3 - Dispatch/Haptics Isolation
- [x] Introduce dispatch event queue and pump service.
- [x] Move key/mouse/haptic posting off engine path.
- [x] Add queue pressure/drop counters and diagnostics snapshot fields.

Exit criteria:
- [ ] Engine frame processing remains stable under dispatch bursts.
- [ ] Dispatch backpressure never blocks capture/engine loops.

## Phase 4 - Dedicated AppKit Surface Renderer
- [x] Implement `TrackpadSurfaceView` as the production renderer path.
- [x] Move drawing from SwiftUI `Canvas` to AppKit view.
- [x] Keep SwiftUI sidebar/editor; drive status through `StatusSnapshot` polling.

Exit criteria:
- [x] No visible hitch while editing keymap with live touch input.
- [x] Sidebar interaction does not impact surface frame pacing.

## Phase 5 - Rust Shared Core (Optional but Target)
- [ ] Define C ABI for engine config, frame ingest, snapshot readback.
- [ ] Port engine state machine to `g2k-core` with parity tests.
- [ ] Add macOS integration path behind runtime flag.

Exit criteria:
- [ ] Replay parity against Swift engine and Windows reference traces.
- [ ] No latency/CPU regression versus Phase 4 baseline.

## Phase 6 - Cutover + Cleanup
- [ ] Make rewrite stack default.
- [ ] Remove legacy code paths during rewrite cutover.
- [ ] Rebuild and ship updated XCFramework + app.

Exit criteria:
- [ ] Legacy runtime removed from hot path and no longer required for normal app operation.
- [ ] Release checklist and regression suite pass.

## Workstream Tracker

Status legend: `Not Started` | `In Progress` | `Blocked` | `Done`

| Workstream | Owner | Status | Notes |
| --- | --- | --- | --- |
| Capture bridge V2 (ObjC) | TBD | In Progress | `OpenMTManagerV2` runs raw-only callbacks on a dedicated state queue with numeric-ID reconciliation and pre-sized registries; callback allocation profiling + sustained soak signoff remain |
| Runtime service split (Swift) | TBD | Done | Runtime ingest defaults to `InputRuntimeService.rawFrameStream -> EngineActor`; surface touch snapshots now mirror engine-owned `RuntimeRenderSnapshot`; device/session lifecycle selection+resync moved into `RuntimeDeviceSessionService`; status polling/visuals gating moved into `RuntimeStatusVisualsService`; touch snapshot recording/revision streaming moved into `RuntimeRenderSnapshotService`; runtime command/config forwarding moved into `RuntimeCommandService`; lifecycle orchestration (ingest loop + start/stop coupling) moved into `RuntimeLifecycleCoordinatorService`; UI disconnect/runtime-continue behavior validated by controller-owned runtime start plus config-window close path that only disables visual sampling |
| Engine boundary + replay harness | TBD | In Progress | Replay runs against `EngineActor`; app runtime executes touch dispatch/status through `EngineActor` with processor internals lifted into standalone `TouchProcessorEngine` (bridge removed) |
| Dispatch queue/pump | TBD | In Progress | `DispatchService` ring queue + pump now owns key/mouse/haptic posting; `TouchProcessorEngine` emits dispatch commands and `RuntimeStatusSnapshot` diagnostics now publish queue depth/drop counters |
| AppKit surface renderer | TBD | Done | `TrackpadSurfaceView` now renders sensor grid, labels, custom buttons, key/button selection highlights, and touches as the always-on renderer path, with engine-owned render snapshot cadence; Phase 4 exit criteria verified in config/edit mode |
| UI/editor shell refactor | TBD | In Progress | Status polling exists; remaining work is decoupled snapshot transport + command-only editor contract |
| Rust `g2k-core` spike | TBD | Not Started | ABI + parity contract |
| Perf/diagnostics dashboard | TBD | In Progress | Queue depth/drop counters are exposed in runtime status; frame pacing and latency dashboards still pending |

## Performance Budgets (Gate to Ship)
- Input callback to engine enqueue p95: <= 1.5 ms.
- Engine frame process p95: <= 3.0 ms (single trackpad), <= 5.0 ms (dual).
- Render snapshot publish jitter (edit mode): <= 5 ms p95.
- Surface redraw cadence in config window: stable at target 60 FPS when touches active.
- Queue drops: 0 in normal operation; explicit counters for overload cases.

## Verification Matrix
- [ ] Unit tests for mapping, layout normalization, action resolution.
- [ ] Replay parity tests for typing, holds, repeats, layer toggles, intent transitions.
- [ ] Long-run soak test (>=30 min, dual trackpad).
- [ ] Config-window stress test (edit mode open + rapid selection changes).
- [ ] Sleep/wake and reconnect scenario tests.
- [ ] Build verification:
  - [x] `swift test --disable-sandbox`
  - [x] `swift run --disable-sandbox ReplayHarness --fixture ReplayFixtures/macos_first_capture_2026-02-20.atpcap --output ReplayFixtures/macos_first_capture_2026-02-20.engine.transcript.jsonl`
  - [x] `swift run --disable-sandbox ReplayHarness --fixture ReplayFixtures/macos_first_capture_2026-02-20.atpcap --expected-transcript ReplayFixtures/macos_first_capture_2026-02-20.engine.transcript.jsonl`
  - [x] `xcodebuild -project Framework/OpenMultitouchSupportXCF.xcodeproj -scheme OpenMultitouchSupportXCF -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/omtxcf-derived build`
  - [x] `xcodebuild build -project Framework/OpenMultitouchSupportXCF.xcodeproj -scheme OpenMultitouchSupportXCF -destination 'generic/platform=macOS' -configuration Release -derivedDataPath Framework/build`
  - [x] `xcodebuild -create-xcframework -framework Framework/build/Build/Products/Release/OpenMultitouchSupportXCF.framework -output OpenMultitouchSupportXCF.xcframework`
  - [x] `xcodebuild -project GlassToKey/GlassToKey.xcodeproj -scheme GlassToKey -configuration Debug -destination 'platform=macOS' build`
  - [ ] `xcodebuild -project GlassToKey/GlassToKey.xcodeproj -scheme GlassToKey -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/glasstokey-derived build` (currently fails in this environment: missing package product `OpenMultitouchSupport`)

Current-sync reruns (2026-02-21):
- `swift test --disable-sandbox`
- `swift run --disable-sandbox ReplayHarness --fixture ReplayFixtures/macos_first_capture_2026-02-20.atpcap --expected-transcript ReplayFixtures/macos_first_capture_2026-02-20.engine.transcript.jsonl`

## Migration Rules
- Rewrite-first cutover is preferred over no-big-bang migration for the remaining slices.
- Keep compatibility only where required for persisted defaults/keymap storage.
- Do not add logging or file I/O in callback/engine hot paths.
- Treat generated artifacts (`OpenMultitouchSupportXCF.xcframework`) as build outputs only.

## Immediate Next Slice (Execution Ready)
- [x] Complete `TrackpadSurfaceView` rendering parity with `CombinedTrackpadCanvas` (labels, key/button highlights, debug overlays) so the AppKit path can become default.
- [x] Shift surface inputs to engine-owned `RenderSnapshot` cadence and retire UI-managed touch snapshot transport from hot rendering path.
- [x] Finish runtime split by moving remaining runtime/session responsibilities out of `ContentViewModel` into dedicated runtime/snapshot services (completed: device/session lifecycle in `RuntimeDeviceSessionService`; status/snapshot controls in `RuntimeStatusVisualsService` + `RuntimeRenderSnapshotService`; command/config forwarding in `RuntimeCommandService`; lifecycle orchestration in `RuntimeLifecycleCoordinatorService`).
- [ ] Run sustained dual-trackpad soak + callback-path allocation profiling for `OpenMTManagerV2`; close remaining Phase 1 exit criteria.
- [ ] Run dispatch burst stress verification and close remaining Phase 3 exit criteria.
- [ ] Capture Windows reference traces in `.atpcap` and stand up macOS-vs-Windows replay parity checks.
- [ ] Execute Phase 6 cutover: default-on rewrite toggles, remove legacy hot paths, and rebuild/re-verify.

Latest replay artifact:
- `ReplayFixtures/macos_first_capture_2026-02-20.atpcap` (canonical baseline fixture; 52 captured frames).
- `ReplayFixtures/macos_first_capture_2026-02-20.engine.transcript.jsonl` (current committed baseline transcript from `EngineActor` boundary for parity checks).
- `ReplayFixtures/macos_dispatch_soak_2026-02-21.atpcap` (longer capture used for dispatch-path stress evaluation).

## Open Decisions
- [ ] Rust core timing: after Swift split (recommended) or in parallel.
- [ ] Snapshot transport: lock-protected structs vs. lock-free ring.
- [ ] Diagnostics persistence format and retention policy outside hot path.
- [ ] Windows adoption of `.atpcap` v3 payload path for true mac<->windows capture/replay interoperability.
