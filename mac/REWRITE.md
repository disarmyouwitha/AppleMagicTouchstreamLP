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

## Phase Plan

### Phase 1: Runtime/UI decoupling (in progress)
- Add fixed-interval status polling (50 ms) in `ContentViewModel`.
- Stop high-frequency status push callbacks from touch processor.
- Keep touch snapshot stream independent of status stream.
- Gate typing/gesture processing while `Edit Keymap` is active.

Acceptance:
- No visible hitch when selecting a key in `Edit Keymap`.
- Contact/intent badges still update smoothly (~20 Hz).

### Phase 2: Dedicated surface renderer
- Replace composite SwiftUI canvas path with a dedicated `NSView`-backed renderer for macOS trackpad surfaces.
- Move key grid, custom button, highlight, and touch ellipse drawing into direct AppKit drawing.
- Keep sidebar/settings in SwiftUI; renderer receives immutable snapshots.

Acceptance:
- Surface render remains smooth with key editor open and controls changing.
- Minimal SwiftUI invalidation from touch motion.

### Phase 3: Editor virtualization + data-path hardening
- Virtualize key action lists and avoid rebuilding picker content on unrelated state changes.
- Introduce explicit editor-state model (`selected key`, `selected button`, `editing layer`) disconnected from touch revisions.
- Precompute display label matrices per layer and update only on mapping/layout mutations.

Acceptance:
- Selecting key/action has constant-time UI update behavior.
- No additional render cost from action menu size.

### Phase 4: Shared core extraction (Rust preferred)
- Define a stable engine interface from current macOS/Windows behavior.
- Port processor logic into Rust with parity tests against existing traces.
- Integrate into macOS and Windows behind runtime feature flags.
- Validate parity for key dispatch, hold/repeat, layers, and intent transitions.

Acceptance:
- Core behavior parity across macOS and Windows for identical touch traces.
- No regression in latency or CPU in hot paths.

### Phase 5: Framework/runtime alignment
- Audit `OMSManager`/listener dispatch threading and coalescing to mirror Windows scheduling assumptions.
- Rewrite OpenMultitouchSupportXCF callback/data-path according to framework scope above (raw-first, lock ownership, numeric registries, zero-allocation fast path).
- Add optional fixed render tick for visuals independent from device frame cadence.
- Add lightweight in-app frame timing diagnostics for regression detection.

Acceptance:
- Consistent frame pacing with one or two trackpads active.
- Measurable reduction in render jitter and main-thread spikes.

## Immediate next implementation slice
1. Introduce `TrackpadSurfaceView` (AppKit) and wire it beside existing SwiftUI canvas behind a feature flag.
2. Feed `TrackpadSurfaceView` from current `TouchSnapshot` and key/button selection state only.
3. Remove direct touch-driven redraw pressure from `RightSidebarView`.
4. Wire `OpenMTManagerV2` into `OMSManager` behind a feature flag so capture can run on the raw-only bridge.
5. Add replay harness tooling to ingest canonical `ReplayFixtures/*.atpcap` captures, feed `RuntimeRawFrame`, and emit deterministic transcripts.
6. Add fixture/schema validation tests (including canonical touch-state labels) and baseline fixtures.

Current execution directive:
1. Replace legacy runtime paths directly as rewrite equivalents land.
2. Keep temporary feature flags only as short-lived safety toggles during tonight's cutover.

## Non-goals
- Changing key mapping semantics.
- Changing touch processor dispatch logic except for edit-mode isolation and scheduling.
- Adding logging/file I/O in hot paths.
