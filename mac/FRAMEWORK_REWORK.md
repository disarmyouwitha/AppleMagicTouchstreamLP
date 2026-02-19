# GlassToKey Framework Rework Plan

## Purpose
- Move high-frequency input transport and capture/replay responsibilities down to the framework/runtime boundary.
- Keep app/UI code out of raw frame handling and recording logic.
- Improve determinism, latency stability, and testability while staying on the private Multitouch API constraint.

## Why this matters
- Current mac app still performs meaningful frame shaping and snapshot coalescing in app-layer code.
- Capture/replay at app level risks drift between what was captured and what runtime actually processed.
- Windows architecture already shows the value of runtime-hosted capture/replay and deterministic self-test loops.

## Design Goals
- Single canonical raw frame format for capture, replay, and diagnostics.
- Hot path free of logging, file I/O, and avoidable allocations.
- Explicit bounded queues with drop counters.
- Runtime stream and UI stream split (full-rate vs coalesced).

## Proposed Architecture

### 1) Canonical Raw Frame Contract
- Define a versioned frame record schema at framework boundary:
  - `schemaVersion`
  - `deviceIDNumeric`
  - `deviceIDString` (optional or derived)
  - `frameIndex`
  - `timestamp`
  - `touchCount`
  - packed touch payload (`id`, `posX`, `posY`, `total`, `pressure`, `major`, `minor`, `angle`, `density`, `state`)
- Keep this record as the only source for:
  - live transport
  - capture serialization
  - replay ingestion

### 2) Transport Split
- Engine transport:
  - full-rate, bounded SPSC ring buffer
  - minimal parsing/allocation, no UI coupling
- UI transport:
  - coalesced/throttled snapshot stream
  - designed for rendering cadence, not frame cadence

### 3) Framework-Side Side Routing
- Resolve left/right active device IDs once and tag frames with side in the framework/runtime layer.
- Avoid repeated side inference/device-index heuristics in app view-model code.

### 4) Capture/Replay Owned by Runtime Host
- Capture writer and replay reader live in runtime service layer, not in config UI.
- Replay modes:
  - headless deterministic replay (for tests)
  - UI replay (for visualization)
- Replay should inject canonical raw frame records directly into processor input path.

### 5) Diagnostics and Telemetry
- Add counters exposed by runtime/framework:
  - frames received
  - frames enqueued
  - frames dropped
  - max queue depth
  - callback overruns
- Keep detailed traces optional and debug-gated.

### 6) Haptics Path Hardening
- Keep actuator cache and open/close lifecycle in framework.
- Add explicit min-interval gating on actuation calls to prevent burst spam from upper layers.

## Prioritized Work Items
1. Introduce canonical frame schema and serializer/deserializer.
2. Add bounded ring-buffer transport for engine stream.
3. Move capture writer/replay reader into runtime service.
4. Add replay clock + deterministic injection path.
5. Add runtime counters and diagnostics API.
6. Add framework-side side-tagging and remove app-side side heuristics.

## Non-Goals (initial)
- Replacing private Multitouch API usage.
- Major changes to device discovery semantics unless required for side-tagging robustness.
- UI redesign details (covered in `GUI_REWORK.md`).

## Risks
- ABI/API compatibility for existing package consumers.
- Replay format migration if schema evolves quickly.
- Queue tuning mistakes (capacity too low/high) affecting latency or memory.

## Mitigations
- Versioned schema with migration adapters.
- Keep legacy stream API as compatibility wrapper around new core transport.
- Add stress tests for queue behavior and replay determinism.

## Acceptance Criteria
- Replay of captured session reproduces identical processor dispatch sequence (or accepted tolerance if timestamp normalization is intentional).
- Runtime hot path shows no regression in p50/p95 dispatch latency.
- UI can remain responsive with visualizer on while engine transport stays stable.
- Capture/replay no longer depends on `ContentView`/`ContentViewModel` reconstruction logic.

## API Sketch (Draft)
The goal is to lock core contracts early so implementation can proceed in parallel.

### 1) Canonical Binary Record
Use little-endian, versioned records for capture/replay.

```c
// FRAME magic: 'OMTF'
typedef struct {
    uint32_t magic;              // 0x46544D4F
    uint16_t schemaVersion;      // start at 1
    uint16_t headerSize;         // sizeof(OMTFrameHeaderV1)
    uint64_t frameIndex;
    uint64_t timestampNs;        // monotonic timestamp
    uint64_t deviceIDNumeric;
    uint8_t  side;               // 0 unknown, 1 left, 2 right
    uint8_t  reserved0;
    uint16_t touchCount;
    uint32_t touchesByteLength;  // touchCount * sizeof(OMTTouchV1)
} OMTFrameHeaderV1;

typedef struct {
    int32_t identifier;
    uint32_t state;
    float posX;
    float posY;
    float total;
    float pressure;
    float majorAxis;
    float minorAxis;
    float angle;
    float density;
} OMTTouchV1;
```

Notes:
- Keep device name and other debug fields out of hot records.
- Optional metadata blocks can be separate record types.

### 2) Objective-C Framework Interfaces
Expose a low-level frame callback and capture/replay primitives.

```objective-c
typedef NS_ENUM(uint8_t, OMTSide) {
    OMTSideUnknown = 0,
    OMTSideLeft = 1,
    OMTSideRight = 2
};

typedef struct {
    const OMTFrameHeaderV1 *header;
    const OMTTouchV1 *touches;
} OMTFrameView;

typedef void (^OMTRawFrameV1Callback)(OMTFrameView frame);

@interface OpenMTManager (RawV1)
- (id)addRawFrameV1Listener:(OMTRawFrameV1Callback)callback;
- (void)removeRawFrameV1Listener:(id)listenerToken;
- (BOOL)setActiveDeviceIDs:(NSArray<NSNumber *> *)deviceIDs
                    leftID:(NSNumber * _Nullable)leftID
                   rightID:(NSNumber * _Nullable)rightID;
@end

@interface OMTCaptureWriter : NSObject
- (instancetype)initWithURL:(NSURL *)url schemaVersion:(uint16_t)schemaVersion;
- (BOOL)appendFrame:(OMTFrameView)frame error:(NSError **)error;
- (BOOL)close:(NSError **)error;
@end

@interface OMTReplayReader : NSObject
- (instancetype)initWithURL:(NSURL *)url;
- (BOOL)readNextFrame:(OMTFrameView *)outFrame error:(NSError **)error;
- (BOOL)seekToFrameIndex:(uint64_t)frameIndex error:(NSError **)error;
@end
```

Notes:
- Listener token API avoids object allocation patterns in caller code.
- Capture/replay objects should keep internal buffers and reuse them.

### 3) Swift Runtime Interfaces
Runtime host consumes canonical records, not UI-shaped models.

```swift
public struct RuntimeFrame {
    public let frameIndex: UInt64
    public let timestampNs: UInt64
    public let deviceIDNumeric: UInt64
    public let side: UInt8
    public let touches: UnsafeBufferPointer<OMTTouchV1>
}

public protocol RuntimeFrameSource: Sendable {
    func start() throws
    func stop()
    func setRouting(activeDeviceIDs: Set<UInt64>, leftID: UInt64?, rightID: UInt64?) throws
    func installConsumer(_ consumer: @escaping @Sendable (RuntimeFrame) -> Void) -> AnyObject
    func removeConsumer(_ token: AnyObject)
}

public protocol CaptureService: Sendable {
    func startCapture(to url: URL) throws
    func stopCapture() throws
}

public protocol ReplayService: Sendable {
    func loadReplay(from url: URL) throws
    func play(speed: Double) throws
    func pause()
    func seek(frameIndex: UInt64) throws
    func stop()
}
```

### 4) Engine/UI Stream Split
Two stream types should be explicit in APIs:
- `EngineFrameStream`: full-rate frames to processor actor.
- `UISnapshotStream`: coalesced snapshots (for example 20-60 Hz) to config window.

```swift
public protocol RuntimeSnapshotSource: Sendable {
    func snapshot() -> RuntimeSnapshot
    func subscribe(_ handler: @escaping @Sendable (RuntimeSnapshot) -> Void) -> AnyObject
    func unsubscribe(_ token: AnyObject)
}
```

### 5) Telemetry Surface
Telemetry should be polled, not logged from hot path.

```swift
public struct RuntimeCounters: Sendable {
    public var framesReceived: UInt64
    public var framesEnqueued: UInt64
    public var framesDropped: UInt64
    public var maxQueueDepth: UInt32
    public var callbackOverruns: UInt64
}

public protocol RuntimeDiagnosticsSource: Sendable {
    func counters() -> RuntimeCounters
}
```

### 6) Compatibility Adapters
Keep current APIs as wrappers while migrating:
- `OMSManager.rawTouchStream` adapts from new frame source.
- Existing `OMSTouchData` conversion remains available as a convenience layer.
- New runtime path should bypass conversion where possible.

Migration rule:
- New runtime consumes `OMTTouchV1` buffers directly.
- Legacy API remains for package consumers until deprecation window ends.

## Migration Sequence by PR (Draft)
Use this sequence to minimize risk while preserving momentum.

### PR1: Canonical Frame Types + Feature Flags
Goal:
- Introduce canonical frame structs and plumbing flags without changing runtime behavior.
Expected files:
- `Framework/OpenMultitouchSupportXCF/OpenMTInternal.h`
- `Framework/OpenMultitouchSupportXCF/OpenMTManager.h`
- `Sources/OpenMultitouchSupport/OMSManager.swift`
- new shared schema header/source files (as needed)

### PR2: Raw V1 Listener API in Framework
Goal:
- Add `addRawFrameV1Listener`/`removeRawFrameV1Listener` and side-tag routing support.
Expected files:
- `Framework/OpenMultitouchSupportXCF/OpenMTManager.h`
- `Framework/OpenMultitouchSupportXCF/OpenMTManager.m`
- `Framework/OpenMultitouchSupportXCF/OpenMTListener.h`
- `Framework/OpenMultitouchSupportXCF/OpenMTListener.m`

### PR3: Runtime Transport (Bounded Ring Buffer)
Goal:
- Add engine-grade bounded transport path and counters.
Expected files:
- `Sources/OpenMultitouchSupport/OMSManager.swift` (adapter layer)
- `GlassToKey/GlassToKey/Runtime/DispatchEventQueue.swift` (or equivalent new runtime queue files)
- `GlassToKey/GlassToKey/Runtime/TouchRuntimeService.swift`

### PR4: Capture Writer (Canonical Record)
Goal:
- Runtime-owned capture writer consumes canonical frames directly.
Expected files:
- new capture files in `GlassToKey/GlassToKey/Runtime/` (for example `CaptureWriter.swift`)
- optional Obj-C helpers if keeping writer in framework
- wiring in runtime host (`TouchRuntimeService.swift`)

### PR5: Replay Reader + Injection Path
Goal:
- Deterministic replay reader and replay clock feeding same processor input path as live data.
Expected files:
- new replay files in `GlassToKey/GlassToKey/Runtime/` (for example `ReplayReader.swift`, `ReplayClock.swift`)
- runtime host integration (`TouchRuntimeService.swift`)
- processor ingestion adapter (`TouchProcessorActor.swift`/core bridge)

### PR6: UI Replay/Capture Controls (Adapter-Only)
Goal:
- UI controls call runtime capture/replay services; UI does not parse raw frame payloads.
Expected files:
- `GlassToKey/GlassToKey/UI/` controls and coordinator files
- `GlassToKey/GlassToKey/App/StatusTrayController.swift`
- no hot-path frame parsing in `ContentView` replacements

### PR7: Compatibility Layer + Deprecation Pass
Goal:
- Keep old APIs working through adapters; mark legacy paths for deprecation.
Expected files:
- `Sources/OpenMultitouchSupport/OMSManager.swift`
- any legacy stream wrappers and documentation updates

### PR8: Determinism + Perf Validation
Goal:
- Lock acceptance with replay determinism checks and latency/queue metrics.
Expected files:
- runtime diagnostics files
- test targets/files for replay + counters + queue behavior
- docs updates in `FRAMEWORK_REWORK.md` and `GUI_REWORK.md`

## PR Gate Checklist
Apply to each PR:
1. No file I/O in callback/hot processing path.
2. No new unbounded queues.
3. Counters exposed for drops/depth where queues are added.
4. Debug logging only behind compile-time or runtime debug gates.
5. Buildable with existing app flow (feature-flagged if behavior changes).
