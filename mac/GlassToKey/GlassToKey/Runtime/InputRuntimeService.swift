import CoreGraphics
import Foundation
import os

final class InputRuntimeService: @unchecked Sendable {
    typealias LiveFrameHandler = @Sendable (OMSRawTouchFrame) -> Void
    typealias CaptureFrameHandler = @Sendable (RuntimeRawFrame) -> Void

    struct Metrics: Sendable {
        var ingestedFrames: UInt64 = 0
        var emittedFrames: UInt64 = 0
        var liveDroppedFrames: UInt64 = 0
        var releasedWithoutConsumers: UInt64 = 0
    }

    private struct Consumers {
        var liveHandler: LiveFrameHandler?
        var captureHandlerID: UUID?
        var captureHandler: CaptureFrameHandler?
    }

    private struct State {
        var isRunning = false
        var generation: UInt64 = 0
        var sequence: UInt64 = 0
        var metrics = Metrics()
    }

    private struct PendingLiveFrame {
        var frame: OMSRawTouchFrame
        var generation: UInt64
    }

    private struct LiveDeliveryState {
        static let capacity = 256

        var slots: [PendingLiveFrame?] = Array(repeating: nil, count: capacity)
        var readIndex = 0
        var writeIndex = 0
        var count = 0
        var drainScheduled = false
    }

    private let manager: OMSManager
    private let liveDeliveryQueue = DispatchQueue(
        label: "ink.ranna.glasstokey.runtime.live-delivery",
        qos: .userInteractive
    )
    private let consumersLock = OSAllocatedUnfairLock<Consumers>(
        uncheckedState: Consumers()
    )
    private let liveDeliveryLock = OSAllocatedUnfairLock<LiveDeliveryState>(
        uncheckedState: LiveDeliveryState()
    )
    private let stateLock = OSAllocatedUnfairLock<State>(uncheckedState: State())

    init(manager: OMSManager = .shared) {
        self.manager = manager
    }

    deinit {
        stop()
    }

    func setLiveFrameHandler(_ handler: LiveFrameHandler?) {
        consumersLock.withLockUnchecked { $0.liveHandler = handler }
    }

    func addCaptureFrameHandler(_ handler: @escaping CaptureFrameHandler) -> UUID {
        let id = UUID()
        consumersLock.withLockUnchecked { consumers in
            consumers.captureHandlerID = id
            consumers.captureHandler = handler
        }
        return id
    }

    func removeCaptureFrameHandler(_ id: UUID) {
        consumersLock.withLockUnchecked { consumers in
            guard consumers.captureHandlerID == id else { return }
            consumers.captureHandlerID = nil
            consumers.captureHandler = nil
        }
    }

    @discardableResult
    func start() -> Bool {
        let shouldStart = stateLock.withLockUnchecked { state in
            guard !state.isRunning else { return false }
            state.isRunning = true
            state.generation &+= 1
            return true
        }
        guard shouldStart else { return false }

        guard manager.startListening() else {
            stateLock.withLockUnchecked { state in
                state.isRunning = false
            }
            return false
        }

        manager.setRawFrameHandler { [weak self] frame in
            self?.handleRawFrame(frame)
        }
        return true
    }

    @discardableResult
    func stop() -> Bool {
        let shouldStop = stateLock.withLockUnchecked { state -> Bool in
            guard state.isRunning else { return false }
            state.isRunning = false
            return true
        }
        guard shouldStop else { return false }
        manager.setRawFrameHandler(nil)
        _ = manager.stopListening()
        return true
    }

    func snapshotMetrics() -> Metrics {
        stateLock.withLockUnchecked { $0.metrics }
    }

    var isRunning: Bool {
        stateLock.withLockUnchecked { $0.isRunning }
    }

    private func handleRawFrame(_ frame: OMSRawTouchFrame) {
        let stateSnapshot = stateLock.withLockUnchecked { state -> (isRunning: Bool, generation: UInt64) in
            guard state.isRunning else { return (false, state.generation) }
            state.metrics.ingestedFrames &+= 1
            return (true, state.generation)
        }
        guard stateSnapshot.isRunning else { return }

        let consumers = consumersLock.withLockUnchecked { $0 }
        guard consumers.liveHandler != nil || consumers.captureHandler != nil else {
            stateLock.withLockUnchecked { state in
                state.metrics.releasedWithoutConsumers &+= 1
            }
            frame.release()
            return
        }

        if let captureHandler = consumers.captureHandler {
            let sequence = stateLock.withLockUnchecked { state -> UInt64 in
                state.sequence &+= 1
                return state.sequence
            }
            let runtimeFrame = RuntimeRawFrame(sequence: sequence, frame: frame)
            captureHandler(runtimeFrame)
        }

        if consumers.liveHandler != nil {
            enqueueLiveFrame(frame, generation: stateSnapshot.generation)
        } else {
            frame.release()
        }

        stateLock.withLockUnchecked { state in
            state.metrics.emittedFrames &+= 1
        }
    }

    private func enqueueLiveFrame(_ frame: OMSRawTouchFrame, generation: UInt64) {
        enum EnqueueResult {
            case scheduled
            case queued
            case dropped
        }

        let result = liveDeliveryLock.withLockUnchecked { state -> EnqueueResult in
            guard state.count < state.slots.count else {
                return .dropped
            }
            state.slots[state.writeIndex] = PendingLiveFrame(
                frame: frame,
                generation: generation
            )
            state.writeIndex = (state.writeIndex + 1) % state.slots.count
            state.count += 1
            guard !state.drainScheduled else {
                return .queued
            }
            state.drainScheduled = true
            return .scheduled
        }

        switch result {
        case .scheduled:
            // The raw Multitouch callback can re-enter synchronously under load.
            // Drain on a dedicated queue so burst delivery stays iterative.
            liveDeliveryQueue.async { [weak self] in
                self?.drainLiveFrames()
            }
        case .queued:
            return
        case .dropped:
            stateLock.withLockUnchecked { state in
                state.metrics.liveDroppedFrames &+= 1
            }
            frame.release()
        }
    }

    private func drainLiveFrames() {
        while true {
            let pending = liveDeliveryLock.withLockUnchecked { state -> PendingLiveFrame? in
                guard state.count > 0 else {
                    state.drainScheduled = false
                    return nil
                }
                let next = state.slots[state.readIndex]
                state.slots[state.readIndex] = nil
                state.readIndex = (state.readIndex + 1) % state.slots.count
                state.count -= 1
                return next
            }
            guard let pending else { return }

            let currentState = stateLock.withLockUnchecked { state in
                (isRunning: state.isRunning, generation: state.generation)
            }
            guard currentState.isRunning,
                  currentState.generation == pending.generation else {
                pending.frame.release()
                continue
            }

            guard let liveHandler = consumersLock.withLockUnchecked({ $0.liveHandler }) else {
                pending.frame.release()
                continue
            }
            liveHandler(pending.frame)
        }
    }
}

final class RuntimeRenderSnapshotService: @unchecked Sendable {
    private final class RevisionContinuationStore: @unchecked Sendable {
        var continuation: AsyncStream<UInt64>.Continuation?
    }

    private let snapshotLock = OSAllocatedUnfairLock<RuntimeTouchSnapshot>(
        uncheckedState: RuntimeTouchSnapshot()
    )
    private let recordingLock = OSAllocatedUnfairLock<Bool>(
        uncheckedState: false
    )
    private let continuationStore: RevisionContinuationStore
    let revisionUpdates: AsyncStream<UInt64>

    init() {
        let continuationStore = RevisionContinuationStore()
        self.continuationStore = continuationStore
        revisionUpdates = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuationStore.continuation = continuation
        }
    }

    deinit {
        continuationStore.continuation?.finish()
    }

    func snapshot() -> RuntimeTouchSnapshot {
        snapshotLock.withLockUnchecked { $0 }
    }

    func snapshotIfUpdated(since revision: UInt64) -> RuntimeTouchSnapshot? {
        snapshotLock.withLockUnchecked { snapshot -> RuntimeTouchSnapshot? in
            guard snapshot.revision != revision else { return nil }
            return snapshot
        }
    }

    func setRecordingEnabled(_ enabled: Bool) {
        recordingLock.withLockUnchecked { $0 = enabled }
        if !enabled {
            snapshotLock.withLockUnchecked { $0 = RuntimeTouchSnapshot() }
        }
    }

    var isRecordingEnabled: Bool {
        recordingLock.withLockUnchecked { $0 }
    }

    func ingest(
        _ rawFrame: RuntimeRawFrame,
        runtimeEngine: EngineActorBoundary
    ) async -> Bool {
        let shouldRecord = isRecordingEnabled
        guard let renderSnapshot = await runtimeEngine.ingest(
            rawFrame,
            captureRenderSnapshot: shouldRecord
        ) else {
            return false
        }
        return publish(renderSnapshot)
    }

    @discardableResult
    func publish(_ renderSnapshot: RuntimeRenderSnapshot) -> Bool {
        var updatedRevision: UInt64?
        snapshotLock.withLockUnchecked { snapshot in
            guard snapshot.revision != renderSnapshot.revision else { return }
            snapshot.left = renderSnapshot.leftTouches
            snapshot.right = renderSnapshot.rightTouches
            snapshot.hasTransitionState = renderSnapshot.hasTransitionState
            snapshot.revision = renderSnapshot.revision
            updatedRevision = snapshot.revision
        }
        guard let revision = updatedRevision else { return false }
        continuationStore.continuation?.yield(revision)
        return true
    }
}

final class RuntimeCommandService: @unchecked Sendable {
    private let runtimeEngine: EngineActorBoundary

    init(runtimeEngine: EngineActorBoundary) {
        self.runtimeEngine = runtimeEngine
    }

    func setListening(_ isListening: Bool) {
        let runtimeEngine = runtimeEngine
        Task {
            await runtimeEngine.setListening(isListening)
        }
    }

    func stopListeningAndReset(stopVoiceDictation: Bool) {
        let runtimeEngine = runtimeEngine
        Task {
            await runtimeEngine.setListening(false)
            await runtimeEngine.reset(stopVoiceDictation: stopVoiceDictation)
        }
    }

    func reset(stopVoiceDictation: Bool) {
        let runtimeEngine = runtimeEngine
        Task {
            await runtimeEngine.reset(stopVoiceDictation: stopVoiceDictation)
        }
    }

    func updateLayouts(
        leftLayout: ContentViewModel.Layout,
        rightLayout: ContentViewModel.Layout,
        leftLabels: [[String]],
        rightLabels: [[String]],
        trackpadSize: CGSize,
        trackpadWidthMm: CGFloat
    ) {
        let runtimeEngine = runtimeEngine
        Task {
            await runtimeEngine.updateLayouts(
                leftLayout: leftLayout,
                rightLayout: rightLayout,
                leftLabels: leftLabels,
                rightLabels: rightLabels,
                trackpadSize: trackpadSize,
                trackpadWidthMm: trackpadWidthMm
            )
        }
    }

    func updateCustomButtons(_ buttons: [CustomButton]) {
        let runtimeEngine = runtimeEngine
        Task {
            await runtimeEngine.updateCustomButtons(buttons)
        }
    }

    func updateKeyMappings(_ actions: LayeredKeyMappings) {
        let runtimeEngine = runtimeEngine
        Task {
            await runtimeEngine.updateKeyMappings(actions)
        }
    }

    func setPersistentLayer(_ layer: Int) {
        let runtimeEngine = runtimeEngine
        Task {
            await runtimeEngine.setPersistentLayer(layer)
        }
    }

    func updateHoldThreshold(_ seconds: TimeInterval) {
        let runtimeEngine = runtimeEngine
        Task {
            await runtimeEngine.updateHoldThreshold(seconds)
        }
    }

    func updateDragCancelDistance(_ distance: CGFloat) {
        let runtimeEngine = runtimeEngine
        Task {
            await runtimeEngine.updateDragCancelDistance(distance)
        }
    }

    func updateTypingGrace(_ milliseconds: Double) {
        let runtimeEngine = runtimeEngine
        Task {
            await runtimeEngine.updateTypingGrace(milliseconds)
        }
    }

    func updateIntentMoveThreshold(_ millimeters: Double) {
        let runtimeEngine = runtimeEngine
        Task {
            await runtimeEngine.updateIntentMoveThreshold(millimeters)
        }
    }

    func updateIntentVelocityThreshold(_ millimetersPerSecond: Double) {
        let runtimeEngine = runtimeEngine
        Task {
            await runtimeEngine.updateIntentVelocityThreshold(millimetersPerSecond)
        }
    }

    func updateAllowMouseTakeover(_ enabled: Bool) {
        let runtimeEngine = runtimeEngine
        Task {
            await runtimeEngine.updateAllowMouseTakeover(enabled)
        }
    }

    func updateForceClickMin(_ grams: Double) {
        let runtimeEngine = runtimeEngine
        Task {
            await runtimeEngine.updateForceClickMin(grams)
        }
    }

    func updateForceClickCap(_ grams: Double) {
        let runtimeEngine = runtimeEngine
        Task {
            await runtimeEngine.updateForceClickCap(grams)
        }
    }

    func updateForceClickThreshold(_ grams: Double) {
        let runtimeEngine = runtimeEngine
        Task {
            await runtimeEngine.updateForceClickThreshold(grams)
        }
    }

    func updateHapticStrength(_ normalized: Double) {
        let runtimeEngine = runtimeEngine
        Task {
            await runtimeEngine.updateHapticStrength(normalized)
        }
    }

    func updateSnapRadiusPercent(_ percent: Double) {
        let runtimeEngine = runtimeEngine
        Task {
            await runtimeEngine.updateSnapRadiusPercent(percent)
        }
    }

    func updateKeyboardModeEnabled(_ enabled: Bool) {
        let runtimeEngine = runtimeEngine
        Task {
            await runtimeEngine.updateKeyboardModeEnabled(enabled)
        }
    }

    func updateHoldRepeatEnabled(_ enabled: Bool) {
        let runtimeEngine = runtimeEngine
        Task {
            await runtimeEngine.updateHoldRepeatEnabled(enabled)
        }
    }

    func setKeymapEditingEnabled(_ enabled: Bool) {
        let runtimeEngine = runtimeEngine
        Task {
            await runtimeEngine.setKeymapEditingEnabled(enabled)
        }
    }

    func updateTapClickCadence(_ milliseconds: Double) {
        let runtimeEngine = runtimeEngine
        Task {
            await runtimeEngine.updateTapClickCadence(milliseconds)
        }
    }

    func updateGestureActions(_ actions: GestureActionSet) {
        let runtimeEngine = runtimeEngine
        Task {
            await runtimeEngine.updateGestureActions(actions)
        }
    }

    func updateGestureRepeatCadenceMsById(_ cadenceById: [String: Int]?) {
        let runtimeEngine = runtimeEngine
        Task {
            await runtimeEngine.updateGestureRepeatCadenceMsById(cadenceById)
        }
    }

    func clearVisualCaches() {
        let runtimeEngine = runtimeEngine
        Task {
            await runtimeEngine.clearVisualCaches()
        }
    }
}

final class RuntimeLifecycleCoordinatorService: @unchecked Sendable {
    private let inputRuntimeService: InputRuntimeService
    private let renderSnapshotService: RuntimeRenderSnapshotService
    private let runtimeEngine: EngineActorBoundary
    private let runtimeCommandService: RuntimeCommandService

    init(
        inputRuntimeService: InputRuntimeService,
        renderSnapshotService: RuntimeRenderSnapshotService,
        runtimeEngine: EngineActorBoundary,
        runtimeCommandService: RuntimeCommandService
    ) {
        self.inputRuntimeService = inputRuntimeService
        self.renderSnapshotService = renderSnapshotService
        self.runtimeEngine = runtimeEngine
        self.runtimeCommandService = runtimeCommandService
        runtimeEngine.setLiveRenderSnapshotHandler { [renderSnapshotService] renderSnapshot in
            _ = renderSnapshotService.publish(renderSnapshot)
        }
        inputRuntimeService.setLiveFrameHandler { [weak self] rawFrame in
            self?.handleLiveFrame(rawFrame)
        }
    }

    deinit {
        runtimeEngine.setLiveRenderSnapshotHandler(nil)
        inputRuntimeService.setLiveFrameHandler(nil)
    }

    private func handleLiveFrame(_ rawFrame: OMSRawTouchFrame) {
        let shouldCaptureRenderSnapshot = renderSnapshotService.isRecordingEnabled
        runtimeEngine.ingestLive(
            rawFrame,
            captureRenderSnapshot: shouldCaptureRenderSnapshot
        )
    }

    @discardableResult
    func start() -> Bool {
        let started = inputRuntimeService.start()
        if started {
            runtimeCommandService.setListening(true)
        }
        return started
    }

    @discardableResult
    func stop(stopVoiceDictation: Bool) -> Bool {
        let stopped = inputRuntimeService.stop()
        if stopped {
            runtimeCommandService.stopListeningAndReset(
                stopVoiceDictation: stopVoiceDictation
            )
        }
        return stopped
    }
}

@MainActor
final class RuntimeDeviceSessionService {
    struct State {
        var availableDevices: [OMSDeviceInfo] = []
        var leftDevice: OMSDeviceInfo?
        var rightDevice: OMSDeviceInfo?
        var hasDisconnectedTrackpads = false
    }

    private static let connectedResyncIntervalNanoseconds = UInt64(10.0 * 1_000_000_000)
    private static let disconnectedResyncIntervalNanoseconds = UInt64(1.0 * 1_000_000_000)

    private let manager: OMSManager
    private let runtimeEngine: EngineActorBoundary
    private let onStateChanged: @MainActor (State) -> Void
    private var state = State()

    private var requestedLeftDeviceID: String?
    private var requestedRightDeviceID: String?
    private var requestedLeftDeviceName: String?
    private var requestedRightDeviceName: String?
    private var requestedLeftIsBuiltIn: Bool?
    private var requestedRightIsBuiltIn: Bool?
    private var autoResyncTask: Task<Void, Never>?
    private var autoResyncEnabled = false

    init(
        manager: OMSManager = .shared,
        runtimeEngine: EngineActorBoundary,
        onStateChanged: @escaping @MainActor (State) -> Void = { _ in }
    ) {
        self.manager = manager
        self.runtimeEngine = runtimeEngine
        self.onStateChanged = onStateChanged
    }

    deinit {
        autoResyncTask?.cancel()
    }

    var snapshot: State {
        state
    }

    func loadDevices(preserveSelection: Bool = false) {
        let previousLeftDeviceID = preserveSelection ? requestedLeftDeviceID : nil
        let previousRightDeviceID = preserveSelection ? requestedRightDeviceID : nil
        let previousLeftDeviceName = preserveSelection ? requestedLeftDeviceName : nil
        let previousRightDeviceName = preserveSelection ? requestedRightDeviceName : nil
        let previousLeftIsBuiltIn = preserveSelection ? requestedLeftIsBuiltIn : nil
        let previousRightIsBuiltIn = preserveSelection ? requestedRightIsBuiltIn : nil
        state.availableDevices = manager.availableDevices

        func matchByID(_ id: String?) -> OMSDeviceInfo? {
            guard let id else { return nil }
            return state.availableDevices.first { $0.deviceID == id }
        }

        func matchByName(
            _ name: String?,
            isBuiltIn: Bool?,
            excluding excludedIDs: Set<String>
        ) -> OMSDeviceInfo? {
            guard let name, !name.isEmpty else { return nil }
            let candidates = state.availableDevices.filter { candidate in
                guard !excludedIDs.contains(candidate.deviceID) else { return false }
                guard candidate.deviceName == name else { return false }
                if let isBuiltIn {
                    return candidate.isBuiltIn == isBuiltIn
                }
                return true
            }
            return candidates.count == 1 ? candidates[0] : nil
        }

        func matchSingleRemaining(excluding excludedIDs: Set<String>) -> OMSDeviceInfo? {
            let candidates = state.availableDevices.filter { !excludedIDs.contains($0.deviceID) }
            return candidates.count == 1 ? candidates[0] : nil
        }

        var usedIDs = Set<String>()
        let leftRequested = preserveSelection && previousLeftDeviceID != nil
        let rightRequested = preserveSelection && previousRightDeviceID != nil

        if leftRequested {
            state.leftDevice = matchByID(previousLeftDeviceID)
                ?? matchByName(previousLeftDeviceName, isBuiltIn: previousLeftIsBuiltIn, excluding: usedIDs)
        } else if !preserveSelection {
            state.leftDevice = state.availableDevices.first
        } else {
            state.leftDevice = nil
        }
        if let leftDevice = state.leftDevice {
            usedIDs.insert(leftDevice.deviceID)
        }

        let shouldFallbackRight = !preserveSelection || (preserveSelection && previousRightDeviceID != nil)
        if rightRequested {
            state.rightDevice = matchByID(previousRightDeviceID)
                ?? matchByName(previousRightDeviceName, isBuiltIn: previousRightIsBuiltIn, excluding: usedIDs)
        } else if shouldFallbackRight {
            state.rightDevice = state.availableDevices.first(where: { candidate in
                guard let leftID = state.leftDevice?.deviceID else { return true }
                return candidate.deviceID != leftID
            })
        } else {
            state.rightDevice = nil
        }
        if let rightDevice = state.rightDevice {
            usedIDs.insert(rightDevice.deviceID)
        }

        if state.leftDevice == nil, leftRequested {
            state.leftDevice = matchSingleRemaining(excluding: usedIDs)
            if let leftDevice = state.leftDevice {
                usedIDs.insert(leftDevice.deviceID)
            }
        }
        if state.rightDevice == nil, rightRequested {
            state.rightDevice = matchSingleRemaining(excluding: usedIDs)
            if let rightDevice = state.rightDevice {
                usedIDs.insert(rightDevice.deviceID)
            }
        }

        if !preserveSelection {
            requestedLeftDeviceID = state.leftDevice?.deviceID
            requestedRightDeviceID = state.rightDevice?.deviceID
            requestedLeftDeviceName = state.leftDevice?.deviceName
            requestedRightDeviceName = state.rightDevice?.deviceName
            requestedLeftIsBuiltIn = state.leftDevice?.isBuiltIn
            requestedRightIsBuiltIn = state.rightDevice?.isBuiltIn
        } else {
            if let leftDevice = state.leftDevice {
                requestedLeftDeviceID = leftDevice.deviceID
                requestedLeftDeviceName = leftDevice.deviceName
                requestedLeftIsBuiltIn = leftDevice.isBuiltIn
            }
            if let rightDevice = state.rightDevice {
                requestedRightDeviceID = rightDevice.deviceID
                requestedRightDeviceName = rightDevice.deviceName
                requestedRightIsBuiltIn = rightDevice.isBuiltIn
            }
        }

        updateDisconnectedTrackpadState()
        updateActiveDevices()
        publishState()
    }

    func selectLeftDevice(_ device: OMSDeviceInfo?) {
        requestedLeftDeviceID = device?.deviceID
        requestedLeftDeviceName = device?.deviceName
        requestedLeftIsBuiltIn = device?.isBuiltIn
        state.leftDevice = device
        updateDisconnectedTrackpadState()
        updateActiveDevices()
        publishState()
    }

    func selectRightDevice(_ device: OMSDeviceInfo?) {
        requestedRightDeviceID = device?.deviceID
        requestedRightDeviceName = device?.deviceName
        requestedRightIsBuiltIn = device?.isBuiltIn
        state.rightDevice = device
        updateDisconnectedTrackpadState()
        updateActiveDevices()
        publishState()
    }

    func setAutoResyncEnabled(_ enabled: Bool) {
        guard autoResyncEnabled != enabled else { return }
        autoResyncEnabled = enabled
        autoResyncTask?.cancel()
        autoResyncTask = nil
        if enabled {
            loadDevices(preserveSelection: true)
            autoResyncTask = Task { [weak self] in
                guard let self else { return }
                await self.autoResyncLoop()
            }
        }
    }

    private func publishState() {
        onStateChanged(state)
    }

    private func updateDisconnectedTrackpadState() {
        let availableIDs = Set(state.availableDevices.map(\.deviceID))
        var hasMissing = false
        if let leftID = requestedLeftDeviceID,
           !leftID.isEmpty,
           !availableIDs.contains(leftID) {
            hasMissing = true
        }
        if let rightID = requestedRightDeviceID,
           !rightID.isEmpty,
           !availableIDs.contains(rightID) {
            hasMissing = true
        }
        state.hasDisconnectedTrackpads = hasMissing
    }

    private func autoResyncLoop() async {
        while autoResyncEnabled {
            let interval = state.hasDisconnectedTrackpads
                ? Self.disconnectedResyncIntervalNanoseconds
                : Self.connectedResyncIntervalNanoseconds
            do {
                try await Task.sleep(nanoseconds: interval)
            } catch {
                break
            }
            guard autoResyncEnabled else { break }
            loadDevices(preserveSelection: true)
        }
    }

    private func updateActiveDevices() {
        let devices = [state.leftDevice, state.rightDevice].compactMap { $0 }
        if !devices.isEmpty, manager.setActiveDevices(devices) {
            let runtimeEngine = runtimeEngine
            Task {
                await runtimeEngine.reset(stopVoiceDictation: false)
            }
        }

        let leftIndex = state.leftDevice.flatMap { manager.deviceIndex(for: $0.deviceID) }
        let rightIndex = state.rightDevice.flatMap { manager.deviceIndex(for: $0.deviceID) }
        let leftDeviceID = state.leftDevice?.deviceID
        let rightDeviceID = state.rightDevice?.deviceID
        let runtimeEngine = runtimeEngine
        Task {
            await runtimeEngine.updateActiveDevices(
                leftIndex: leftIndex,
                rightIndex: rightIndex,
                leftDeviceID: leftDeviceID,
                rightDeviceID: rightDeviceID
            )
        }
    }
}
