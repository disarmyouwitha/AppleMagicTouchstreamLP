# GlassToKey mac GUI Rework Plan (Performance + Windows Parity)

## 1) Objectives
- Replace the current mac config GUI with a modular, maintainable UI while preserving or improving input-to-key latency.
- Keep runtime input processing independent from window/UI lifecycle (same operating model as Windows tray runtime).
- Achieve feature parity with `../windows/glasstokey` where platform-appropriate, prioritizing control surface, tuning, keymap editing, status indicators, and mode behavior.
- Keep hot path allocation-free (or allocation-minimal), with no logging/file I/O in per-frame processing.

## 2) Current Issues (mac)
- UI and runtime concerns are tightly coupled in very large files:
  - `GlassToKey/GlassToKey/ContentView.swift` (~2972 lines)
  - `GlassToKey/GlassToKey/ContentViewModel.swift` (~4830 lines)
- A large amount of settings persistence and runtime mutation is driven directly from `@AppStorage` + `onChange` chains in view code.
- Runtime processing logic is nested inside view model code instead of being hosted as a first-class runtime service.
- This makes parity work and GUI iteration slower, and increases risk of regressions when changing UI.

## 3) Windows Architecture to Mirror (Primary References)
Use these as the architectural baseline for mac:
- App/tray orchestration: `../windows/glasstokey/App.xaml.cs`
- Runtime host decoupled from UI: `../windows/glasstokey/TouchRuntimeService.cs`
- Window as observer/editor, not runtime owner: `../windows/glasstokey/MainWindow.xaml.cs`
- Runtime/frame observer contracts: `../windows/glasstokey/RuntimeObserverContracts.cs`
- Shared config/layout builder: `../windows/glasstokey/RuntimeConfigurationFactory.cs`
- Persistent settings normalization/migration: `../windows/glasstokey/UserSettings.cs`
- Keymap/custom button persistence model: `../windows/glasstokey/KeymapStore.cs`
- Rendering surface abstraction: `../windows/glasstokey/TouchView.cs`
- Dispatch separation: `../windows/glasstokey/Core/Dispatch/DispatchEventQueue.cs`, `../windows/glasstokey/Core/Dispatch/DispatchEventPump.cs`, `../windows/glasstokey/Core/Dispatch/SendInputDispatcher.cs`
- Core processor isolation: `../windows/glasstokey/Core/Engine/TouchProcessorCore.cs`

## 4) Target mac Architecture
### 4.1 Process Model
- Keep status app lifetime independent from config window.
- Runtime always-on while app is active; config window can open/close without restarting runtime.

### 4.2 Layering
- `AppShell` layer: app lifecycle, tray menu, window presentation.
- `Runtime` layer: touch input ingestion, processing actor/core, dispatch pump, status snapshot.
- `State/Persistence` layer: settings store + keymap store + migrations/normalization.
- `UI` layer: pure presentation + user intents, observing runtime snapshot and editing state.

### 4.3 Core Rule
- UI never owns hot-path processing objects.
- Runtime never blocks on UI thread.

## 5) Concrete Module/File Plan
Create the following mac modules/files (incremental; keep old code until each replacement is complete):

### 5.1 AppShell
- `GlassToKey/GlassToKey/App/GlassToKeyApp.swift` (thin entry)
- `GlassToKey/GlassToKey/App/AppCoordinator.swift`
- `GlassToKey/GlassToKey/App/StatusTrayController.swift`
- `GlassToKey/GlassToKey/App/ConfigWindowController.swift`
- `GlassToKey/GlassToKey/App/GlobalClickSuppressor.swift`

Windows parity refs:
- `../windows/glasstokey/App.xaml.cs`
- `../windows/glasstokey/StatusTrayController.cs`

### 5.2 Runtime
- `GlassToKey/GlassToKey/Runtime/TouchRuntimeService.swift`
- `GlassToKey/GlassToKey/Runtime/RuntimeObserverContracts.swift`
- `GlassToKey/GlassToKey/Runtime/TouchProcessorCore.swift` (extract from current processor logic)
- `GlassToKey/GlassToKey/Runtime/TouchProcessorActor.swift`
- `GlassToKey/GlassToKey/Runtime/DispatchEventQueue.swift`
- `GlassToKey/GlassToKey/Runtime/DispatchEventPump.swift`
- `GlassToKey/GlassToKey/Runtime/RuntimeSnapshot.swift`

Windows parity refs:
- `../windows/glasstokey/TouchRuntimeService.cs`
- `../windows/glasstokey/RuntimeObserverContracts.cs`
- `../windows/glasstokey/Core/Engine/TouchProcessorCore.cs`
- `../windows/glasstokey/Core/Dispatch/DispatchEventQueue.cs`
- `../windows/glasstokey/Core/Dispatch/DispatchEventPump.cs`

### 5.3 State + Config
- `GlassToKey/GlassToKey/State/AppSettingsStore.swift`
- `GlassToKey/GlassToKey/State/KeymapStore.swift`
- `GlassToKey/GlassToKey/State/SettingsMigration.swift`
- `GlassToKey/GlassToKey/State/RuntimeConfigurationFactory.swift`

Windows parity refs:
- `../windows/glasstokey/UserSettings.cs`
- `../windows/glasstokey/KeymapStore.cs`
- `../windows/glasstokey/RuntimeConfigurationFactory.cs`

### 5.4 UI
- `GlassToKey/GlassToKey/UI/ConfigRootView.swift`
- `GlassToKey/GlassToKey/UI/StatusHeaderView.swift`
- `GlassToKey/GlassToKey/UI/DevicePanelView.swift`
- `GlassToKey/GlassToKey/UI/SurfacePanelView.swift`
- `GlassToKey/GlassToKey/UI/Controls/ColumnTuningView.swift`
- `GlassToKey/GlassToKey/UI/Controls/KeymapTuningView.swift`
- `GlassToKey/GlassToKey/UI/Controls/TypingTuningView.swift`
- `GlassToKey/GlassToKey/UI/Controls/GestureTuningView.swift`
- `GlassToKey/GlassToKey/UI/Controls/ModeTogglesView.swift`
- `GlassToKey/GlassToKey/UI/Controls/DiagnosticsView.swift`
- `GlassToKey/GlassToKey/UI/TouchSurfaceView.swift` (or `NSViewRepresentable` backed renderer for lower overhead)

Windows parity refs:
- `../windows/glasstokey/MainWindow.xaml`
- `../windows/glasstokey/MainWindow.xaml.cs`
- `../windows/glasstokey/TouchView.cs`

## 6) Feature Parity Backlog (Windows -> mac)
Implement in this order:
1. Status pills and mode indicators parity (`idle/cand/typing/mouse/gest`, mode color behavior).
2. Devices panel parity (left/right device selection + refresh/resync behavior).
3. Controls panel parity structure:
   - Column tuning
   - Keymap tuning (primary/hold, layered)
   - Typing tuning
   - Gesture tuning (3/4/5 finger swipes, holds, corner/triangle/force actions as applicable)
   - Mode toggles
4. Surface parity:
   - Key highlight/selection
   - Custom button edit overlays
   - Last-hit/contacts/peak signals
5. Import/export settings parity (combined settings + keymap profile).
6. Diagnostics parity baseline (runtime snapshots, queue depth, drops, transition counters).

## 7) Performance Design Rules (Non-Negotiable)
- No file I/O in touch callback path.
- No logging in hot path unless debug-only with compile-time guards.
- No per-frame heap allocations where avoidable:
  - Reuse buffers for touch/contact collections.
  - Reuse dispatch event scratch arrays.
  - Prefer ring buffers for queues/diagnostics.
- Runtime/UI decoupling:
  - Runtime updates snapshot on background thread/actor.
  - UI polling/subscription at bounded cadence (e.g. 20-60 Hz), never per raw frame.
- Backpressure strategy:
  - Bounded queue with drop counters.
  - Drop oldest/newest policy decided explicitly and tested.
- State store writes are batched/debounced and never on hot path.

## 8) Implementation Phases

### Phase 0: Baseline and guardrails
- Capture baseline performance metrics from current mac build:
  - input frame rate
  - end-to-end dispatch latency
  - queue depth/drop counts
  - CPU usage with config window closed/open
- Add lightweight benchmark hooks (debug only) for later regression checks.
- Exit criteria: baseline report committed.

### Phase 1: Introduce runtime host without UI rewrite
- Implement `TouchRuntimeService.swift` and contracts.
- Move startup/runtime ownership out of `ContentViewModel` into app coordinator.
- Keep existing UI reading via adapter to new runtime snapshot.
- Exit criteria: behavior unchanged, runtime continues with window closed.

### Phase 2: Extract processor and dispatch pipeline
- Move processor core/actor from `ContentViewModel.swift` into runtime module.
- Introduce dedicated dispatch queue/pump abstractions.
- Keep `KeyEventDispatcher` internals but route through new dispatch pipeline.
- Exit criteria: zero functional regression on typing/mode toggles/device routing.

### Phase 3: State/persistence split
- Replace direct `@AppStorage` scatter with `AppSettingsStore` + `KeymapStore` APIs.
- Implement settings normalization and migration path.
- Keep backward compatibility with existing stored keys/profile data.
- Exit criteria: old settings load correctly, no hot-path persistence operations.

### Phase 4: UI shell replacement
- Build `ConfigRootView` with Windows-style sectioned controls layout.
- Add status header + device panel + surfaces + right controls pane.
- Keep existing feature wiring via adapters.
- Exit criteria: old monolithic view no longer used by default.

### Phase 5: Feature parity controls
- Add gesture tuning sections and bindings inspired by Windows panels.
- Add import/export settings profile parity.
- Add diagnostics panel parity subset (queue/drops/mode transitions).
- Exit criteria: agreed parity checklist complete.

### Phase 6: Surface renderer optimization
- If SwiftUI `Canvas` diffing is bottlenecked, switch to `NSView` backed renderer (`TouchSurfaceView`) with explicit invalidation.
- Cache static paths/labels/layout geometry; redraw only dynamic layers.
- Exit criteria: equal or lower CPU than baseline with visualization on.

### Phase 7: Remove legacy paths
- Delete or archive old monolithic view/viewmodel code paths.
- Keep only modular runtime + UI.
- Exit criteria: clean build, smaller blast radius for future changes.

## 9) Testing and Verification
- Build gate: `xcodebuild -project GlassToKey/GlassToKey.xcodeproj -scheme GlassToKey -configuration Debug -destination 'platform=macOS' build`
- Add deterministic runtime tests for:
  - intent transitions
  - key dispatch behavior
  - layer/toggle behavior
  - snap radius and drag cancel rules
- Add config/state tests for:
  - migration compatibility
  - layout/keymap persistence
  - gesture action serialization
- Add perf regression checks comparing Phase 0 baseline.

## 10) Rollout Strategy
- Ship behind internal feature flag:
  - `UseNewConfigUI`
  - `UseRuntimeServiceHost`
- Start with runtime host migration first, then UI replacement.
- Keep fallback path for one release cycle; remove after validation.

## 11) Risks and Mitigations
- Risk: runtime regressions while moving processor out of view model.
  - Mitigation: phase separation + snapshot parity tests + synthetic frame tests.
- Risk: UI rewrite accidentally increases hot-path coupling.
  - Mitigation: strict runtime observer contracts and no direct runtime mutation from view rendering.
- Risk: parity scope creep (Windows has broad gesture controls).
  - Mitigation: enforce backlog order in Section 6 and ship in increments.

## 12) Immediate Next Actions
1. Create `RuntimeObserverContracts.swift` and `TouchRuntimeService.swift` skeletons.
2. Wire `GlassToKeyApp` to runtime service ownership (window-independent).
3. Add adapter layer so existing `ContentView` reads runtime snapshots (no logic change yet).
4. Start extracting processor core from `ContentViewModel.swift` into `Runtime/TouchProcessorCore.swift`.

## 13) Research Snapshot (February 18, 2026)
This section records concrete repository analysis to guide implementation sequencing.

mac observations:
- Tray/app shell is already separate from config window, but runtime ownership still flows through `GlassToKeyController` and `ContentViewModel` lifecycle (`GlassToKey/GlassToKey/GlassToKeyApp.swift:18`, `GlassToKey/GlassToKey/GlassToKeyController.swift:41`, `GlassToKey/GlassToKey/ContentViewModel.swift:343`).
- Config UI is monolithic with broad `@AppStorage` and many `onChange` mutation paths (`GlassToKey/GlassToKey/ContentView.swift:98`, `GlassToKey/GlassToKey/ContentView.swift:350`).
- Runtime path already uses lock-based state and async streams, which is a strong base for extraction (`Sources/OpenMultitouchSupport/OMSManager.swift:68`, `GlassToKey/GlassToKey/ContentViewModel.swift:185`).
- mac currently includes five-finger swipe + tap-click + chordal shift + voice dictation gesture logic, but does not expose Windows-level full gesture tuning breadth (`GlassToKey/GlassToKey/ContentViewModel.swift:3476`, `GlassToKey/GlassToKey/ContentViewModel.swift:3564`).

windows observations used for parity:
- Runtime host is decoupled and UI is an observer/editor (`../windows/glasstokey/TouchRuntimeService.cs:9`, `../windows/glasstokey/MainWindow.xaml.cs:22`).
- Processing and dispatch are explicitly split via queue + pump (`../windows/glasstokey/TouchRuntimeService.cs:67`, `../windows/glasstokey/Core/Dispatch/DispatchEventQueue.cs:19`).
- Settings model is centralized and normalized on load (`../windows/glasstokey/UserSettings.cs:160`, `../windows/glasstokey/UserSettings.cs:217`).
- UI organization is grouped and scalable (Column/Keymap/Typing/Gesture/Mode sections) (`../windows/glasstokey/MainWindow.xaml:126`, `../windows/glasstokey/MainWindow.xaml:182`, `../windows/glasstokey/MainWindow.xaml:246`, `../windows/glasstokey/MainWindow.xaml:352`, `../windows/glasstokey/MainWindow.xaml:746`).

## 14) Parity Gap Matrix (Windows -> mac)
| Capability | Windows Baseline | mac Current | Gap | Planned Phase |
|---|---|---|---|---|
| Runtime host independent from config window | `TouchRuntimeService` owns runtime (`../windows/glasstokey/TouchRuntimeService.cs:9`) | Runtime start/stream processing tied to view model lifecycle (`GlassToKey/GlassToKey/GlassToKeyController.swift:45`, `GlassToKey/GlassToKey/ContentViewModel.swift:343`) | Medium | 1 |
| Runtime snapshot/observer contract | `SetFrameObserver` + `TryGetSnapshot` (`../windows/glasstokey/TouchRuntimeService.cs:154`, `../windows/glasstokey/TouchRuntimeService.cs:169`) | No dedicated runtime service contract module | High | 1 |
| Dispatch queue + pump separation | Explicit queue/pump (`../windows/glasstokey/Core/Dispatch/DispatchEventQueue.cs:19`) | Direct dispatcher usage via view-model-owned processor | Medium | 2 |
| Centralized settings normalization | `UserSettings.NormalizeRanges()` (`../windows/glasstokey/UserSettings.cs:217`) | `@AppStorage` + ad hoc load/save pathways (`GlassToKey/GlassToKey/ContentView.swift:98`, `GlassToKey/GlassToKey/ContentView.swift:2574`) | High | 3 |
| Gesture tuning UI breadth | Full gesture tuning panel with 3/4/5 finger, holds, corners, triangles, force-click mappings (`../windows/glasstokey/MainWindow.xaml:352`) | Not exposed at parity level in mac config UI | High | 5 |
| Layer model breadth | 0..7 layers in keymap/runtime (`../windows/glasstokey/KeymapStore.cs:333`, `../windows/glasstokey/Core/Engine/TouchProcessorCore.cs:242`) | Keymap normalization effectively 2 layers (`GlassToKey/GlassToKey/ContentViewModel.swift:5167`) | Medium | 5 |
| Force threshold tuning | Force min and max controls (`../windows/glasstokey/UserSettings.cs:63`, `../windows/glasstokey/UserSettings.cs:64`) | Force cap only (`GlassToKey/GlassToKey/ContentView.swift:143`) | Medium | 5 |
| Tray operations | Config/Capture/Replay/Restart/Exit (`../windows/glasstokey/StatusTrayController.cs:33`) | Config/Sync/Restart/Quit (`GlassToKey/GlassToKey/GlassToKeyApp.swift:59`) | Low for GUI rework, medium for tooling parity | 5+ |
| Diagnostics/self-test depth | replay + self-test + fault logging (`../windows/glasstokey/README.md:80`, `../windows/glasstokey/Core/Diagnostics/SelfTestRunner.cs:7`) | Signpost diagnostics exist, but no equivalent deterministic self-test suite in repo | Medium | 5 |

## 15) Hot Path Inventory (Do Not Regress)
Treat these as strict hot paths:
- Obj-C frame callbacks: `Framework/OpenMultitouchSupportXCF/OpenMTManager.m:808`, `Framework/OpenMultitouchSupportXCF/OpenMTManager.m:840`
- Swift raw frame handling: `Sources/OpenMultitouchSupport/OMSManager.swift:272`
- Runtime stream processing loop: `GlassToKey/GlassToKey/ContentViewModel.swift:348`
- Touch processor frame handling: `GlassToKey/GlassToKey/ContentViewModel.swift:1694`

Hard constraints during refactor:
- No `UserDefaults`, JSON encode/decode, file I/O, or UI work in any hot-path function above.
- No dynamic logging in release hot path (debug-only signposts are already present and acceptable).
- Maintain bounded buffering semantics (`bufferingNewest(2)` and coalescing) unless benchmarked improvements are proven (`Sources/OpenMultitouchSupport/OMSManager.swift:68`, `GlassToKey/GlassToKey/ContentViewModel.swift:203`).

## 16) Settings and Schema Alignment Plan
Current mac persisted surface:
- scalar keys in `GlassToKeyDefaultsKeys` (`GlassToKey/GlassToKey/GlassToKeyDefaultsKeys.swift:3`)
- encoded blobs for keymap, column settings, custom buttons (`GlassToKey/GlassToKey/ContentView.swift:101`, `GlassToKey/GlassToKey/ContentView.swift:103`, `GlassToKey/GlassToKey/ContentView.swift:104`)
- profile import/export model (`GlassToKey/GlassToKey/ContentView.swift:50`)

Alignment approach:
1. Introduce a versioned `AppSettingsStore` JSON model and keep a migration loader from legacy `UserDefaults` keys.
2. Keep legacy read path for at least one release cycle, write only new schema after successful migration.
3. Split storage domains:
   - `settings.json`: runtime/UI scalar settings + selected devices + layout preset.
   - `keymap.json`: layered key mappings + custom buttons by layout/layer.
4. Preserve current defaults key names as migration source of truth to avoid data loss.

## 17) Scope Decisions for GUI Rework
In scope for this GUI rework:
- Runtime/UI separation.
- New modular config window with Windows-like control grouping.
- Gesture tuning expansion to match Windows action configuration surface where mac runtime supports it.
- Parity status pills and mode behavior.

Out of scope for initial GUI rework:
- Full Windows capture/replay feature port.
- Decoder profile selection UI (Windows-specific raw HID concern).
- Non-GUI platform tooling parity tasks (installer/startup registration polish can follow).

## 18) Measurable Acceptance Gates
Use baseline from Phase 0, then enforce:
- End-to-end key dispatch latency:
  - p50 not worse than baseline.
  - p95 regression <= 5%.
- Runtime queue health:
  - zero drops in normal typing sessions.
  - bounded drops under synthetic stress with explicit counters.
- CPU:
  - with config window closed: <= baseline + 5%.
  - with config window open and visuals on: <= baseline + 10%.
- Memory:
  - no monotonic growth during 30-minute idle + typing soak.
- Functional parity:
  - status mode indicators, keymap editing, device selection, tuning controls, and custom buttons validated by checklist.

## 19) Pre-Implementation Spikes (Recommended)
1. Runtime host spike:
   - Build `TouchRuntimeService` + snapshot contract only.
   - Keep old UI unchanged.
   - Validate no behavior regressions.
2. Renderer spike:
   - Compare current SwiftUI `Canvas` path vs `NSViewRepresentable` renderer for two surfaces with visuals enabled.
   - Choose implementation based on measured CPU/frame stability.
3. Gesture config spike:
   - Prototype action-model schema for extended gesture bindings.
   - Confirm compatibility with current mac processor capabilities before UI wiring.

## 20) Open Questions to Resolve Before Coding
- Layer count target for mac parity:
  - keep 2 layers for now or expand to 8-layer model for Windows parity.
- Gesture parity boundary:
  - which Windows gesture actions are required on mac in first milestone.
- Storage direction:
  - continue `UserDefaults` as backing store with centralized adapter, or migrate directly to file-based settings store.

## 21) Framework Track Link
Framework-level rewrite insights and capture/replay architecture are tracked in:
- `FRAMEWORK_REWORK.md`

Coordination rule:
- Phase 1-2 of this GUI plan should run alongside the first framework milestones (canonical frame schema + runtime-owned capture/replay transport) so UI work does not reintroduce app-layer frame reconstruction.

## 22) Visualizer Fast Path (Immediate Performance Win)
Observation:
- Current touch drawing computes rotated ellipses using `major/minor/angle` and variable opacity from force/total:
  - ellipse construction and rotation path: `GlassToKey/GlassToKey/ContentView.swift:2076`
  - per-touch fill with opacity: `GlassToKey/GlassToKey/ContentView.swift:3105`

Recommendation:
- Add a render mode switch for touch visualization:
  - `Fast`: fixed-size, fully opaque circles (`Color.green`) with no rotation, no per-touch alpha.
  - `Detailed`: current ellipse + angle + pressure-driven opacity behavior.
- Default to `Fast` for normal runtime editing; keep `Detailed` for diagnostics.

Why this helps:
- Eliminates per-touch path rotation/transforms and alpha blending variability in the hottest UI drawing path.
- Matches the proven Windows approach (simple opaque circles) and should materially reduce UI render cost when visualizer is on.

Implementation notes:
1. Add `TouchRenderMode` enum (`fast`, `detailed`) in UI state/settings.
2. Branch in `drawTrackpadTouches`:
   - `fast`: draw circles from touch position only.
   - `detailed`: keep current `makeEllipse` path.
3. Persist render mode in settings store (not on hot path).
4. Include this mode in Phase 0 baseline comparisons.
