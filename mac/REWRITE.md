# GlassToKey Rewrite Plan (Windows-Parity Runtime + Shared Core Track)

## Goal
Make macOS behavior and feel match the Windows app under heavy touch load, especially during `Edit Keymap`, while preparing for a shared cross-platform core:

- Stable touch visuals while editing mappings
- No sidebar-induced frame drops
- Status updates decoupled from hot input path
- Minimal main-thread invalidation churn
- Cross-platform behavior parity via a shared engine path (Rust preferred)

## Execution Tracking
Use `REWRITE_TRACKING.md` as the execution source of truth for phase checklists, workstream status, and current implementation slice.

## Cutover Directive (2026-02-21)
- Prioritize full rewrite cutover tonight.
- Do not spend additional time preserving legacy runtime behavior unless needed to keep the app building while a rewrite replacement lands.
- Prefer deleting/replacing legacy paths once rewrite equivalents are validated by build + replay checks.

## Decisions from this review
1. Keep native app stacks:
- macOS app/UI in Swift, private framework bridge in Objective-C.
- Windows app/UI in C#.
2. Do not keep current macOS UI invalidation architecture.
3. Build a strict runtime pipeline and make UI a consumer of snapshots, not the source of hot-path backpressure.
4. Proceed with optional shared core library and prioritize Rust over C++.
5. Execute rewrite-first cutover (not compatibility-first hardening) for the remaining implementation slice.

## Why a rewrite is needed
Windows uses explicit visual invalidation and timed status polling, while macOS currently relies on broader SwiftUI `ObservableObject` invalidation. When edit controls are active, that causes larger view tree re-evaluations than the Windows model.

## Framework audit findings (OpenMultitouchSupportXCF)
Current framework hotspots and rewrite needs:

1. Object-event path allocates per frame.
- `OpenMTManager` still builds `OpenMTTouch` objects + `OpenMTEvent` for non-raw listeners.
- This is allocation-heavy and should not be on any hot path.

2. Event dispatch uses an extra serial response queue.
- Non-raw listener dispatch currently hops through `dispatch_async` on a serial queue.
- This can create backlog and latency under bursty touch frames.

3. Mixed thread access to mutable device lookup structures.
- Device ID caches/maps are mutated during device reconfiguration and read from callback paths.
- Needs a strict lock/queue ownership model to avoid races and unpredictable stalls.

4. Device enumeration and ID handling are string-heavy.
- Device references are repeatedly rebuilt from ID strings and list scans.
- Internal runtime should use numeric IDs and pointer-stable registries.

5. Dual callback mode complexity (legacy + refcon fallback).
- Supporting both callback paths in hot runtime code increases branching and lifecycle complexity.
- Rewrite should make one primary callback path explicit and testable.

## Framework rewrite scope
1. Raw-first API contract
- Make raw frame callback the only performance path.
- Keep object-event API as debug/compat mode (off by default).

2. Deterministic callback threading
- Define one callback execution model (direct callback thread or dedicated high-priority queue).
- Remove unnecessary queue hops for latency-sensitive consumers.

3. Locking and ownership model
- Replace ad hoc mutable map access with explicit synchronization boundaries.
- Separate control-plane state (device changes) from data-plane reads (callbacks).

4. Device/actuator registry rewrite
- Maintain stable numeric-ID keyed registries for active devices and actuators.
- Avoid string parsing/lookups on hot paths.
- Minimize full device list rebuilds unless hardware topology changes.

5. Memory and allocation policy
- Zero dynamic allocations in callback fast path.
- Preallocate/reuse callback context and frame adaptation buffers.

6. Integration boundary for shared Rust core
- Framework remains platform IO bridge.
- Feed raw frames into shared `g2k-core` interface with deterministic, allocation-controlled handoff.

## Strict pipeline (target)
1. Input Capture Layer
- Platform-native capture only, zero UI work, no blocking calls.
2. Processing Engine Layer
- Intent/state machine, binding resolution, dispatch decisions.
- Hot path independent from rendering and inspector/editor state.
3. Snapshot Layer
- Immutable visual/status snapshots with explicit cadence boundaries.
4. Render Layer
- Dedicated platform-native surface renderer (`NSView` on macOS, WPF surface on Windows).
5. UI/Editor Layer
- Polls status snapshots on fixed interval.
- Applies config/keymap edits through command/update APIs only.

## Language and component strategy
### Native shells (stay native)
- macOS shell: Swift + Objective-C bridge.
- Windows shell: C#.

### Shared core track (approved direction)
- Build a shared `g2k-core` in Rust (preferred) for:
  - touch state machine
  - intent classification
  - binding resolution
  - repeat/hold/momentary layer logic
  - deterministic snapshot generation
- Expose thin FFI adapters:
  - macOS: Rust -> C ABI -> Swift bridge.
  - Windows: Rust -> C ABI or C# interop layer.
- Keep platform-specific device IO, event posting, and haptics native.

## Phase Plan (Consolidated with `REWRITE_TRACKING.md`)
Use the same phase numbering/status in both documents.

### Phase 0: Behavior Freeze + Replay Baseline — In Progress
- `.atpcap` fixture schema + replay harness are in place.
- Canonical macOS baseline fixture/transcript is committed.
- Remaining: capture canonical Windows traces for parity comparisons.

### Phase 1: New Objective-C Capture Bridge — In Progress
- `OpenMTManagerV2` raw-first bridge is integrated behind backend selection.
- Numeric-ID registry + dedicated state queue landed.
- Remaining: callback-path allocation verification and sustained dual-trackpad soak signoff.

### Phase 2: Runtime Service + Engine Boundary (Swift) — Completed
- `InputRuntimeService` and `EngineActor` boundary are live in runtime and replay harness.
- Touch processing state machine has moved into `TouchProcessorEngine`.
- Device/session lifecycle management is now extracted into `RuntimeDeviceSessionService`.
- Status polling + visuals gating now run via `RuntimeStatusVisualsService`.
- Touch snapshot recording/revision streaming now run via `RuntimeRenderSnapshotService`.
- Runtime command/config forwarding now runs via `RuntimeCommandService`.
- Runtime lifecycle orchestration (ingest loop + start/stop coupling) now runs via `RuntimeLifecycleCoordinatorService`.
- Exit criteria verified on 2026-02-21, including UI disconnect while runtime remains active.

### Phase 3: Dispatch/Haptics Isolation — In Progress
- `DispatchService` ring queue + pump landed and is wired to engine output.
- Dispatch queue depth/drop diagnostics are published in status snapshots.
- Remaining: sustained stress verification proving dispatch bursts do not perturb capture/engine timing.

### Phase 4: Dedicated AppKit Surface Renderer — Completed
- `TrackpadSurfaceView` is now the default/always-on surface renderer path.
- Surface input cadence now comes from engine-owned `RuntimeRenderSnapshot`.
- Exit criteria verified in config/edit mode (live touches + sidebar interaction) on 2026-02-21.

### Phase 5: Rust Shared Core (Optional but Target) — Not Started
- ABI and parity contract remain pending after Swift runtime split completes.

### Phase 6: Cutover + Cleanup — Not Started
- Rewrite stack is not default yet.
- Legacy runtime paths are still present and have not been fully removed.

## Immediate next implementation slice
1. Run callback allocation profiling + dual-trackpad sustained soak on `OpenMTManagerV2` and close remaining Phase 1 exit checks.
2. Run dispatch burst stress verification and close remaining Phase 3 exit checks.
3. Capture canonical Windows reference traces and start direct replay parity comparison against macOS transcripts (Phase 0 closeout).
4. Execute Phase 6 cutover: remove legacy hot paths and rebuild/re-verify.

Current execution directive:
1. Replace legacy runtime paths directly as rewrite equivalents land.
2. Keep temporary feature flags only as short-lived safety toggles during tonight's cutover.

## Non-goals
- Changing key mapping semantics.
- Changing touch processor dispatch logic except for edit-mode isolation and scheduling.
- Adding logging/file I/O in hot paths.
