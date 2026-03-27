If there was a 3rd better architecture you could realize — what would it be? You can start from the ground up and  implement things however you want, as long as they are grounded in our actual code.


• A better third architecture would be a single-owner runtime core: one hot-path engine thread, one canonical OMS bridge, and two explicit outputs layered off the same sequenced frame log.

  The core problem with the old design is scheduler overhead. The core problem with the PR design is that it spreads ownership across too many queues and copies of the OMS layer. The better design is to be more strict, not more abstract.

  Architecture

  1. Canonical ingest layer

  - Keep exactly one OMS implementation in Sources/OpenMultitouchSupport/OMSManager.swift.
  - Extend that layer to expose a single-consumer raw sink plus optional passive observers.
  - Preserve the zero-copy OMSRawTouchFrame / buffer-pool idea from the PR, because that is the right direction for hot input.
  - Do not duplicate OMS types in the app target.

  2. Single runtime owner

  - Replace both the old actor model and the PR’s multi-queue fanout with one dedicated serial runtime queue that owns:
      - input ingest
      - TouchProcessorEngine
      - repeat timers
      - intent state
      - render snapshot generation
      - capture diagnostics generation
  - In practice, EngineActor becomes a runtime loop object, not an actor and not a lock-heavy queue boundary.
  - Nothing mutates engine state off that queue. No exceptions.

  3. Immutable frame journal

  - Every live frame gets a monotonic sequence number immediately at ingest.
  - The runtime queue processes frames in order and emits a compact ProcessedFrameRecord:
      - sequence
      - timestamp
      - device info
      - raw touch summary or retained raw frame reference
      - engine decisions
      - dispatch events caused by that frame
      - render delta or snapshot revision
  - Capture, replay, UI, and diagnostics all derive from that same record stream.

  4. Split outputs by importance

  - Live UI path:
      - lossy
      - latest-value only
      - revision-coalesced like the PR’s render update work in GlassToKey/GlassToKey/Render/TrackpadSurfaceView.swift:726
  - Capture path:
      - lossless while enabled
      - append-only writer or bounded preallocated spool with backpressure/error
      - never shares the same drop policy as live UI

  5. Dispatch as part of engine transaction

  - DispatchService should not feel like a separate asynchronous universe for capture purposes.
  - The engine should enqueue dispatch commands and also record them in the same per-frame transaction before release.
  - The actual CG event posting can still happen on its own queue, but capture metadata should be committed
    synchronously with engine processing, not inferred later.

  Why This Is Better

  Pros over the old actor/AsyncStream model:

  - Keeps strict sequencing without async task churn.
  - Removes polling entirely.
  - Preserves hot-path performance.

  Pros over the PR:

  - Much simpler ownership model.
  - No diagnostics start/stop race, because capture is just another sink on the runtime queue.
  - No duplicated OMS wrapper.

  Concrete shape in this repo

  I would structure it around these existing files:

  - Sources/OpenMultitouchSupport/OMSManager.swift
      - Keep this as the only OMS bridge wrapper.
      - Move the PR’s pooled raw frame/buffer-view work here.
  - GlassToKey/GlassToKey/Engine/TouchProcessorEngine.swift
      - Keep most of the decision logic here.
      - Strip out cross-thread scheduling concerns.
      - Return structured per-frame results instead of pushing side effects everywhere.
  - GlassToKey/GlassToKey/Engine/EngineActorBoundary.swift
      - Replace with a RuntimeCore or RuntimeLoop.
      - One serial queue.
      - Public API is command submission plus observer registration.
  - GlassToKey/GlassToKey/Runtime/RuntimeContracts.swift
      - Add a first-class ProcessedFrameRecord.
      - Make capture/replay serialize that, not partially reconstructed side channels.
  - GlassToKey/GlassToKey/Runtime/ATPCaptureV3Coordinator.swift
      - Stop subscribing independently to input frames, diagnostics, and dispatch events.
      - Subscribe once to processed-frame records.
      - That eliminates the current correlation races.

  The model

  Think of it like this:

  - OMS callback: “raw frame arrived”
  - Runtime queue: “assign sequence, process, dispatch, snapshot, log”
  - Outputs:
      - UI gets latest snapshot revision
      - capture gets exact frame record
      - replay re-feeds exact recorded frame record or raw frame subset

  That is the cleanest architecture grounded in your codebase and goals: lower latency than the old engine, fewer correctness hazards than the PR, and better replay/capture determinism than either.


• Goal

  Refactor the mac runtime into a single-owner, single-source-of-truth architecture:

  - one canonical OMS bridge
  - one serial runtime queue
  - one sequenced processed-frame pipeline
  - lossy UI output
  - lossless capture output

  This should preserve the performance intent of PR #90 while removing the queue/ownership races and the duplicated
  OMS stack.

  Target Architecture

  1. OMS bridge is canonical

  - Keep all OMS types and raw-frame lifecycle management in Sources/OpenMultitouchSupport/OMSManager.swift.
  - Remove app-local duplicates from GlassToKey/GlassToKey/OMSManager.swift and GlassToKey/GlassToKey/OMSTouchData.swift.
  - The app target should import and use the package wrapper again, not its own copy.

  2. Runtime has one owner

  - Replace the current EngineActorBoundary implementation with a RuntimeCore-style object backed by exactly one
    serial DispatchQueue.


› Run /review on my current changes
    happen on that queue.
  - No separate live ingest ring in the engine layer.

  3. Processed frame is the canonical output


  - Introduce a ProcessedFrameRecord in GlassToKey/GlassToKey/Runtime/RuntimeContracts.swift.
  - Every raw frame gets:
      - sequence
      - raw frame metadata
      - engine touch diagnostics / decisions
      - dispatch events caused by that frame
      - render snapshot revision or snapshot payload
      - ingress metrics if capture is enabled
  - Capture and replay should serialize/consume this record model, not reconstruct it from independent
  subscriptions.

  4. Output paths are explicitly different

  - UI/render path:
      - revision-coalesced
      - latest-value only
      - allowed to skip intermediate frames
  - Capture path:
      - exact ordered records
      - no dropped diagnostics for captured frames
      - capture start/stop must flush the runtime queue before closing

  Implementation Plan

  1. Unify the OMS layer

  - Port the useful PR changes from app-local OMS into Sources/OpenMultitouchSupport/OMSManager.swift:
      - pooled OMSRawTouchFrame
      - OMSRawTouchBufferView
      - raw buffer reuse
      - explicit release()
      - optional single sink callback
  - Keep exported OMS types in the package wrapper.
  - Delete app-local OMS duplicates and switch app files back to importing the package types.
  - Update Package.swift and GlassToKey/GlassToKey.xcodeproj/project.pbxproj so there is only one OMS API surface.

  Acceptance:

  - app builds against package OMS types only
  - tools and app share the same frame/state definitions

  2. Replace EngineActorBoundary with a single-queue runtime core

  - Refactor GlassToKey/GlassToKey/Engine/EngineActorBoundary.swift into:
      - RuntimeCore or similar
      - one serial queue
      - sync/async command methods that marshal onto that queue
  - Remove:
      - engine-side live ring buffer
      - multi-stage capture handler toggles
      - status polling APIs
  - Keep:
      - render snapshot caching
      - callback-based contact count / intent updates
  - Ensure TouchProcessorEngine is only touched from that queue.

  Acceptance:

  - one queue owns all runtime mutation
  - no actor + queue hybrid
  - no separate live frame queue inside engine boundary

  3. Move repeat/timer scheduling fully into runtime ownership

  - Keep the PR’s move away from detached Task.sleep, but ensure scheduling happens only from the single runtime queue.
  - In GlassToKey/GlassToKey/Engine/TouchProcessorEngine.swift, simplify timer generation logic so it assumes one owner queue.
  - Preserve the PR’s tap/hold fixes and frame diagnostic generation where valid.

  Acceptance:

  - repeat and typing-grace scheduling never mutate state off-owner
  - no extra locks needed inside the engine

  4. Introduce ProcessedFrameRecord

  - Add to GlassToKey/GlassToKey/Runtime/RuntimeContracts.swift:
      - ProcessedFrameRecord
      - ProcessedDispatchEvent
      - ProcessedRenderUpdate or snapshot reference
  - TouchProcessorEngine.process... should return structured per-frame results instead of only firing side effects
    through callbacks.
  - DispatchService should support recording dispatch intents for the current frame transaction before actual async
    posting.

  Acceptance:

  - one object contains everything capture needs for one frame
  - no need to correlate three separate streams later

  5. Rebuild capture on top of processed-frame records

  - Refactor GlassToKey/GlassToKey/Runtime/ATPCaptureV3Coordinator.swift so capture subscribes once to processed-frame records.
  - Remove independent subscriptions to:
      - raw capture frames
      - capture diagnostics handler
      - dispatch event handler
  - Add explicit startCapture and stopCapture barriers:
      - start: enable capture mode on runtime queue before next frame
      - stop: flush runtime queue, then write file
  - Keep the richer .atpcap schema from PR #90, but populate it from one source.

  Acceptance:

  - no missing tail diagnostics
  - no startup race between first captured frame and diagnostics enablement
  - recorded dispatch events are causally attached to the right frame sequence

  6. Keep the render improvements

  - Retain the revision-driven display logic from GlassToKey/GlassToKey/Render/TrackpadSurfaceView.swift:726.
  - Feed it from the runtime core’s coalesced render snapshot publisher.
  - Do not reintroduce polling.

  Acceptance:

  - UI stays revision-driven
  - no visual polling service returns

  7. Reconcile DispatchService

  - Keep queue-based event posting in GlassToKey/GlassToKey/KeyEventDispatcher.swift.
  - Remove capture as a global side-channel callback.
  - Instead, runtime core creates ProcessedDispatchEvent records at decision time and passes commands to
    DispatchService.
  - DispatchService remains responsible for OS posting, not capture truth.

  Acceptance:

  - dispatch capture metadata is generated in runtime transaction scope
  - actual CG event posting can remain asynchronous

  8. Update replay to consume the canonical model

  - Ensure replay can still feed raw frames through the engine deterministically.
  - If practical, add a replay verification mode that compares generated processed-frame transcripts against committed baselines.
  - Keep existing .engine.transcript.jsonl harness behavior or extend it minimally.

  Acceptance:

  - replay determinism preserved
  - transcript fixtures still usable

  Suggested Work Breakdown

  Worker 1: OMS unification

  - Own:
      - Sources/OpenMultitouchSupport/OMSManager.swift
      - Package.swift
      - GlassToKey/GlassToKey.xcodeproj/project.pbxproj
  - Deliver:
      - one canonical OMS implementation
      - app-local OMS files removed
  - Must not revert unrelated edits.

  Worker 2: Runtime core refactor

  - Own:
      - GlassToKey/GlassToKey/Engine/EngineActorBoundary.swift
      - GlassToKey/GlassToKey/Engine/TouchProcessorEngine.swift
      - GlassToKey/GlassToKey/Runtime/RuntimeContracts.swift
  - Deliver:
      - single-owner runtime queue
      - processed-frame record model
      - engine result structuring
  - Must coordinate with Worker 3 on capture contracts.

  Worker 3: Capture/replay integration

  - Own:
      - GlassToKey/GlassToKey/Runtime/ATPCaptureV3Coordinator.swift
      - GlassToKey/GlassToKey/Runtime/InputRuntimeService.swift
      - replay harness files if needed
  - Deliver:
      - capture fed from processed-frame records
      - clean start/stop barriers
      - no split subscriptions

  Worker 4: UI/render wiring

  - Own:
      - GlassToKey/GlassToKey/ContentViewModel.swift
      - GlassToKey/GlassToKey/Render/TrackpadSurfaceView.swift
  - Deliver:
      - runtime callbacks wired to main actor safely
      - revision-driven rendering preserved
      - no polling status service reintroduced

  Non-Negotiable Constraints

  - Do not add a second OMS implementation.
  - Do not reintroduce status polling.
  - Do not let capture depend on racing subscriptions to separate streams.
  - Do not put avoidable allocations/logging on the hot path in:
      - GlassToKey/GlassToKey/Engine/TouchProcessorEngine.swift
      - GlassToKey/GlassToKey/Runtime/InputRuntimeService.swift
      - GlassToKey/GlassToKey/KeyEventDispatcher.swift

  Verification

  Minimum:

  1. swift test
  2. Replay transcript parity:

  swift run ReplayHarness --fixture ReplayFixtures/macos_first_capture_2026-02-20.atpcap --expected-transcript ReplayFixtures/macos_first_capture_2026-02-20.engine.transcript.jsonl

  3. If engine behavior intentionally changes, regenerate transcript baselines and explain why.
  4. xcodebuild -project GlassToKey/GlassToKey.xcodeproj -scheme GlassToKey -configuration Debug -destination 'platform=macOS' build

  Handoff Prompt

  Use this directly with another Codex instance:

  Refactor the mac runtime to a third architecture with these requirements:

  - one canonical OMS bridge in Sources/OpenMultitouchSupport only
  - no app-local OMS duplicate types or manager
  - one single-owner serial runtime queue
  - no actor/queue hybrid and no status polling
  - introduce a canonical ProcessedFrameRecord model that capture/replay/UI derive from
  - capture must be lossless while enabled and must not correlate diagnostics via separate racing subscriptions
  - keep revision-driven UI rendering
  - preserve or improve replay determinism

  Key files:
  - Sources/OpenMultitouchSupport/OMSManager.swift
  - GlassToKey/GlassToKey/Engine/EngineActorBoundary.swift
  - GlassToKey/GlassToKey/Engine/TouchProcessorEngine.swift
  - GlassToKey/GlassToKey/Runtime/RuntimeContracts.swift
  - GlassToKey/GlassToKey/Runtime/InputRuntimeService.swift
  - GlassToKey/GlassToKey/Runtime/ATPCaptureV3Coordinator.swift
  - GlassToKey/GlassToKey/ContentViewModel.swift
  - GlassToKey/GlassToKey/Render/TrackpadSurfaceView.swift
  - GlassToKey/GlassToKey/KeyEventDispatcher.swift
  - Package.swift
  - GlassToKey/GlassToKey.xcodeproj/project.pbxproj

  Do not revert unrelated changes. Preserve hot-path performance. Keep replay/capture deterministic. Run swift test and the replay harness if possible, and
  report any intentional transcript changes.