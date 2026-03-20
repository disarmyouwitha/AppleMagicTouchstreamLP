import CoreGraphics
import Foundation
import OpenMultitouchSupport
import os

final class InputRuntimeService: @unchecked Sendable {
    typealias RuntimeRawFrameHandler = @Sendable (RuntimeRawFrame) -> Void

    struct Metrics: Sendable {
        var ingestedFrames: UInt64 = 0
        var emittedFrames: UInt64 = 0
        var releasedWithoutConsumers: UInt64 = 0
    }

    private struct ContinuationStore {
        var byID: [UUID: AsyncStream<RuntimeRawFrame>.Continuation] = [:]
        var list: [AsyncStream<RuntimeRawFrame>.Continuation] = []
    }

    private struct HandlerStore {
        var byID: [UUID: RuntimeRawFrameHandler] = [:]
        var list: [RuntimeRawFrameHandler] = []
    }

    private struct State {
        var isRunning = false
        var rawHandlerID: UUID?
        var sequence: UInt64 = 0
        var metrics = Metrics()
    }

    private let manager: OMSManager
    private let handlerLock = OSAllocatedUnfairLock<HandlerStore>(
        uncheckedState: HandlerStore()
    )
    private let continuationLock = OSAllocatedUnfairLock<ContinuationStore>(
        uncheckedState: ContinuationStore()
    )
    private let stateLock = OSAllocatedUnfairLock<State>(uncheckedState: State())

    init(manager: OMSManager = .shared) {
        self.manager = manager
    }

    deinit {
        stop()
    }

    var rawFrameStream: AsyncStream<RuntimeRawFrame> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let id = UUID()
            continuationLock.withLockUnchecked { store in
                store.byID[id] = continuation
                store.list = Array(store.byID.values)
            }
            continuation.onTermination = { [continuationLock] _ in
                continuationLock.withLockUnchecked { store in
                    store.byID.removeValue(forKey: id)
                    store.list = Array(store.byID.values)
                }
            }
        }
    }

    @discardableResult
    func start() -> Bool {
        let shouldStart = stateLock.withLockUnchecked { state in
            guard !state.isRunning else { return false }
            state.isRunning = true
            state.sequence = 0
            return true
        }
        guard shouldStart else { return false }

        guard manager.startListening() else {
            stateLock.withLockUnchecked { state in
                state.isRunning = false
            }
            return false
        }

        let handlerID = manager.addRawFrameHandler { [weak self] frame in
            self?.handleRawFrame(frame)
        }
        stateLock.withLockUnchecked { state in
            state.rawHandlerID = handlerID
        }
        return true
    }

    @discardableResult
    func stop() -> Bool {
        let rawHandlerID = stateLock.withLockUnchecked { state -> UUID? in
            guard state.isRunning else { return nil }
            state.isRunning = false
            let handlerID = state.rawHandlerID
            state.rawHandlerID = nil
            return handlerID
        }
        guard let rawHandlerID else { return false }
        manager.removeRawFrameHandler(rawHandlerID)
        _ = manager.stopListening()
        return true
    }

    func snapshotMetrics() -> Metrics {
        stateLock.withLockUnchecked { $0.metrics }
    }

    var isRunning: Bool {
        stateLock.withLockUnchecked(\.isRunning)
    }

    @discardableResult
    func addFrameHandler(
        _ handler: @escaping RuntimeRawFrameHandler
    ) -> UUID {
        let id = UUID()
        handlerLock.withLockUnchecked { store in
            store.byID[id] = handler
            store.list = Array(store.byID.values)
        }
        return id
    }

    func removeFrameHandler(_ id: UUID) {
        handlerLock.withLockUnchecked { store in
            store.byID.removeValue(forKey: id)
            store.list = Array(store.byID.values)
        }
    }

    private func handleRawFrame(_ frame: OMSRawTouchFrame) {
        let sequence = stateLock.withLockUnchecked { state -> UInt64 in
            guard state.isRunning else { return 0 }
            state.sequence &+= 1
            state.metrics.ingestedFrames &+= 1
            return state.sequence
        }
        guard sequence != 0 else { return }
        let runtimeFrame = RuntimeRawFrame(sequence: sequence, frame: frame)
        emit(runtimeFrame)
    }

    private func emit(_ frame: RuntimeRawFrame) {
        let handlers = handlerLock.withLockUnchecked { $0.list }
        let continuations = continuationLock.withLockUnchecked { $0.list }
        if handlers.isEmpty, continuations.isEmpty {
            stateLock.withLockUnchecked { state in
                state.metrics.releasedWithoutConsumers &+= 1
            }
            return
        }

        for handler in handlers {
            handler(frame)
        }
        for continuation in continuations {
            continuation.yield(frame)
        }
        stateLock.withLockUnchecked { state in
            state.metrics.emittedFrames &+= 1
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
        snapshotLock.withLockUnchecked { snapshot in
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

    func isRecordingEnabled() -> Bool {
        recordingLock.withLockUnchecked(\.self)
    }

    @discardableResult
    func consume(_ renderSnapshot: RuntimeRenderSnapshot) -> Bool {
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

    func ingest(
        _ rawFrame: RuntimeRawFrame,
        runtimeEngine: TouchProcessorEngine
    ) async -> Bool {
        let shouldRecord = isRecordingEnabled()
        let renderSnapshot = await runtimeEngine.ingest(
            rawFrame,
            captureRenderSnapshot: shouldRecord
        )
        guard shouldRecord, let renderSnapshot else { return false }
        return consume(renderSnapshot)
    }
}

@MainActor
final class RuntimeStatusVisualsService {
    private let runtimeEngine: TouchProcessorEngine
    private let pollIntervalNanoseconds: UInt64
    private let onStatusSnapshot: @MainActor (RuntimeStatusSnapshot) -> Void
    private var pollingTask: Task<Void, Never>?
    private var visualsEnabled = true

    init(
        runtimeEngine: TouchProcessorEngine,
        pollIntervalNanoseconds: UInt64 = 50_000_000,
        onStatusSnapshot: @escaping @MainActor (RuntimeStatusSnapshot) -> Void
    ) {
        self.runtimeEngine = runtimeEngine
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        self.onStatusSnapshot = onStatusSnapshot
    }

    deinit {
        pollingTask?.cancel()
    }

    func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
                guard visualsEnabled else { continue }
                let snapshot = await runtimeEngine.statusSnapshot()
                guard visualsEnabled else { continue }
                onStatusSnapshot(snapshot)
            }
        }
    }

    func setVisualsEnabled(_ enabled: Bool) {
        visualsEnabled = enabled
        guard enabled else { return }
        let runtimeEngine = runtimeEngine
        Task { [weak self] in
            let snapshot = await runtimeEngine.statusSnapshot()
            guard let self, self.visualsEnabled else { return }
            self.onStatusSnapshot(snapshot)
        }
    }
}

final class RuntimeCommandService: @unchecked Sendable {
    private let runtimeEngine: TouchProcessorEngine

    init(runtimeEngine: TouchProcessorEngine) {
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

    func updateChordalShiftEnabled(_ enabled: Bool) {
        let runtimeEngine = runtimeEngine
        Task {
            await runtimeEngine.updateChordalShiftEnabled(enabled)
        }
    }

    func updateKeyboardModeEnabled(_ enabled: Bool) {
        let runtimeEngine = runtimeEngine
        Task {
            await runtimeEngine.updateKeyboardModeEnabled(enabled)
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

    func updateGestureActions(
        twoFingerTap: KeyAction,
        threeFingerTap: KeyAction,
        twoFingerHold: KeyAction,
        threeFingerHold: KeyAction,
        fourFingerHold: KeyAction,
        outerCornersHold: KeyAction,
        innerCornersHold: KeyAction,
        fiveFingerSwipeLeft: KeyAction,
        fiveFingerSwipeRight: KeyAction
    ) {
        let runtimeEngine = runtimeEngine
        Task {
            await runtimeEngine.updateGestureActions(
                twoFingerTap: twoFingerTap,
                threeFingerTap: threeFingerTap,
                twoFingerHold: twoFingerHold,
                threeFingerHold: threeFingerHold,
                fourFingerHold: fourFingerHold,
                outerCornersHold: outerCornersHold,
                innerCornersHold: innerCornersHold,
                fiveFingerSwipeLeft: fiveFingerSwipeLeft,
                fiveFingerSwipeRight: fiveFingerSwipeRight
            )
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
    private struct LiveIngestState {
        var handlerID: UUID?
        var generation: UInt64 = 0
    }

#if DEBUG
    private let pipelineSignposter = OSSignposter(
        subsystem: "com.kyome.GlassToKey",
        category: "InputPipeline"
    )
#endif
    private let inputRuntimeService: InputRuntimeService
    private let renderSnapshotService: RuntimeRenderSnapshotService
    private let runtimeEngine: TouchProcessorEngine
    private let runtimeCommandService: RuntimeCommandService
    private let liveIngestLock = OSAllocatedUnfairLock<LiveIngestState>(
        uncheckedState: LiveIngestState()
    )

    init(
        inputRuntimeService: InputRuntimeService,
        renderSnapshotService: RuntimeRenderSnapshotService,
        runtimeEngine: TouchProcessorEngine,
        runtimeCommandService: RuntimeCommandService
    ) {
        self.inputRuntimeService = inputRuntimeService
        self.renderSnapshotService = renderSnapshotService
        self.runtimeEngine = runtimeEngine
        self.runtimeCommandService = runtimeCommandService
    }

    deinit {
        cancelLiveIngest()
    }

    private func ensureLiveFrameHandlerRegistered() {
        let registerState = liveIngestLock.withLockUnchecked { state -> (Bool, UInt64) in
            (state.handlerID == nil, state.generation)
        }
        let shouldRegister = registerState.0
        let generation = registerState.1
        guard shouldRegister else { return }
        let handlerID = inputRuntimeService.addFrameHandler { [weak self] rawFrame in
            self?.ingestLiveFrame(rawFrame, generation: generation)
        }
        liveIngestLock.withLockUnchecked { state in
            guard state.handlerID == nil else { return }
            state.handlerID = handlerID
        }
    }

    private func isLiveGenerationActive(_ generation: UInt64) -> Bool {
        liveIngestLock.withLockUnchecked { state in
            state.handlerID != nil && state.generation == generation
        }
    }

    private func ingestLiveFrame(_ rawFrame: RuntimeRawFrame, generation: UInt64) {
        guard isLiveGenerationActive(generation) else { return }
        let renderSnapshotService = renderSnapshotService
        let runtimeEngine = runtimeEngine
        let isGenerationActive = self.isLiveGenerationActive
#if DEBUG
        let pipelineSignposter = pipelineSignposter
#endif
        Task.detached(priority: .userInitiated) {
            guard isGenerationActive(generation) else { return }
#if DEBUG
            let signpostState = pipelineSignposter.beginInterval("InputFrameV2")
            defer { pipelineSignposter.endInterval("InputFrameV2", signpostState) }
            let ingestSignpostState = pipelineSignposter.beginInterval("EngineIngestV2")
            defer { pipelineSignposter.endInterval("EngineIngestV2", ingestSignpostState) }
#endif
            let shouldRecord = renderSnapshotService.isRecordingEnabled()
            let renderSnapshot = await runtimeEngine.ingest(
                rawFrame,
                captureRenderSnapshot: shouldRecord
            )
            guard isGenerationActive(generation) else { return }
            guard shouldRecord, let renderSnapshot else { return }
            let updated = renderSnapshotService.consume(renderSnapshot)
            if updated {
#if DEBUG
                pipelineSignposter.emitEvent("SnapshotUpdateV2")
#endif
            }
        }
    }

    @discardableResult
    func start() -> Bool {
        ensureLiveFrameHandlerRegistered()
        let started = inputRuntimeService.start()
        if started {
            runtimeCommandService.setListening(true)
        } else {
            cancelLiveIngest()
        }
        return started
    }

    @discardableResult
    func stop(stopVoiceDictation: Bool) -> Bool {
        cancelLiveIngest()
        let stopped = inputRuntimeService.stop()
        if stopped {
            runtimeCommandService.stopListeningAndReset(
                stopVoiceDictation: stopVoiceDictation
            )
        }
        return stopped
    }

    private func cancelLiveIngest() {
        let handlerID = liveIngestLock.withLockUnchecked { state in
            let handlerID = state.handlerID
            state.handlerID = nil
            state.generation &+= 1
            return handlerID
        }
        if let handlerID {
            inputRuntimeService.removeFrameHandler(handlerID)
        }
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
    private let runtimeEngine: TouchProcessorEngine
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
        runtimeEngine: TouchProcessorEngine,
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
