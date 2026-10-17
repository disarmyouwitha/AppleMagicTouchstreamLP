import CoreGraphics
import Foundation
import OpenMultitouchSupport
import os

final class InputRuntimeService: @unchecked Sendable {
    typealias LiveFrameHandler = @Sendable (OMSRawTouchFrame, RuntimeCaptureIngressSnapshot?) -> Void
    typealias CaptureStateProvider = @Sendable () -> Bool

    struct Metrics: Sendable {
        var ingestedFrames: UInt64 = 0
        var emittedFrames: UInt64 = 0
        var liveDroppedFrames: UInt64 = 0
        var releasedWithoutConsumers: UInt64 = 0
    }

    private struct Consumers {
        var liveHandler: LiveFrameHandler?
        var captureStateProvider: CaptureStateProvider?
    }

    private struct State {
        var isRunning = false
        var generation: UInt64 = 0
        var sequence: UInt64 = 0
        var metrics = Metrics()
    }

    private let manager: OMSManager
    private let consumersLock = OSAllocatedUnfairLock<Consumers>(
        uncheckedState: Consumers()
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

    func setCaptureStateProvider(_ provider: CaptureStateProvider?) {
        consumersLock.withLockUnchecked { $0.captureStateProvider = provider }
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

        manager.setRawFrameSink(self)
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
        manager.setRawFrameSink(nil)
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
        let shouldCapture = consumers.captureStateProvider?() ?? false
        guard consumers.liveHandler != nil || shouldCapture else {
            stateLock.withLockUnchecked { state in
                state.metrics.releasedWithoutConsumers &+= 1
            }
            frame.release()
            return
        }

        let sequenceSnapshot = stateLock.withLockUnchecked { state -> (sequence: UInt64, liveDroppedFrames: UInt64) in
                state.sequence &+= 1
                return (state.sequence, state.metrics.liveDroppedFrames)
            }
        frame.sequence = sequenceSnapshot.sequence

        let ingress: RuntimeCaptureIngressSnapshot?
        if shouldCapture {
            let dispatchMetrics = DispatchService.shared.snapshotMetrics()
            ingress = RuntimeCaptureIngressSnapshot(
                deliveryMode: consumers.liveHandler != nil ? .liveAndCapture : .captureOnly,
                liveQueueDepth: 0,
                liveDroppedFrames: sequenceSnapshot.liveDroppedFrames,
                dispatchQueueDepth: dispatchMetrics.queueDepth,
                dispatchDropped: dispatchMetrics.drops
            )
        } else {
            ingress = nil
        }

        if let liveHandler = consumers.liveHandler {
            let currentState = stateLock.withLockUnchecked { state in
                (isRunning: state.isRunning, generation: state.generation)
            }
            guard currentState.isRunning,
                  currentState.generation == stateSnapshot.generation else {
                frame.release()
                return
            }
            liveHandler(frame, ingress)
        } else {
            frame.release()
        }

        stateLock.withLockUnchecked { state in
            state.metrics.emittedFrames &+= 1
        }
    }
}

extension InputRuntimeService: OMSRawTouchFrameSink {
    func handleRawTouchFrame(_ frame: OMSRawTouchFrame) {
        handleRawFrame(frame)
    }
}

protocol RuntimeRenderSnapshotSink: AnyObject, Sendable {
    func submitRuntimeRenderSnapshot(_ renderSnapshot: RuntimeRenderSnapshot)
}

final class RuntimeRenderSnapshotService: @unchecked Sendable {
    private final class RevisionContinuationStore: @unchecked Sendable {
        var continuation: AsyncStream<UInt64>.Continuation?
    }

    private struct RevisionDeliveryState {
        var pendingRevision: UInt64?
        var drainScheduled = false
    }

    private let snapshotLock = OSAllocatedUnfairLock<RuntimeTouchSnapshot>(
        uncheckedState: RuntimeTouchSnapshot()
    )
    private let recordingLock = OSAllocatedUnfairLock<Bool>(
        uncheckedState: false
    )
    private let revisionDeliveryQueue = DispatchQueue(
        label: "ink.ranna.glasstokey.runtime.render-snapshot-updates",
        qos: .userInteractive
    )
    private let revisionDeliveryLock = OSAllocatedUnfairLock<RevisionDeliveryState>(
        uncheckedState: RevisionDeliveryState()
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
            revisionDeliveryLock.withLockUnchecked { state in
                state.pendingRevision = 0
            }
            scheduleRevisionDrainIfNeeded()
        }
    }

    var isRecordingEnabled: Bool {
        recordingLock.withLockUnchecked { $0 }
    }

    func ingest(
        _ rawFrame: RuntimeRawFrame,
        runtimeEngine: RuntimeCoreBoundary,
        ingress: RuntimeCaptureIngressSnapshot? = nil
    ) async -> Bool {
        let shouldRecord = isRecordingEnabled
        let result = await runtimeEngine.ingest(
            rawFrame,
            ingress: ingress,
            captureRenderSnapshot: shouldRecord
        )
        guard let renderSnapshot = result.renderSnapshot else {
            return false
        }
        return submit(renderSnapshot)
    }

    @discardableResult
    func submit(_ renderSnapshot: RuntimeRenderSnapshot) -> Bool {
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
        enqueueRevisionUpdate(revision)
        return true
    }

    private func enqueueRevisionUpdate(_ revision: UInt64) {
        revisionDeliveryLock.withLockUnchecked { state in
            state.pendingRevision = revision
        }
        scheduleRevisionDrainIfNeeded()
    }

    private func scheduleRevisionDrainIfNeeded() {
        let shouldSchedule = revisionDeliveryLock.withLockUnchecked { state -> Bool in
            guard state.pendingRevision != nil, !state.drainScheduled else {
                return false
            }
            state.drainScheduled = true
            return true
        }
        guard shouldSchedule else { return }
        revisionDeliveryQueue.async { [weak self] in
            self?.drainRevisionUpdates()
        }
    }

    private func drainRevisionUpdates() {
        while true {
            let revision = revisionDeliveryLock.withLockUnchecked { state -> UInt64? in
                guard let revision = state.pendingRevision else {
                    state.drainScheduled = false
                    return nil
                }
                state.pendingRevision = nil
                return revision
            }
            guard let revision else { return }
            continuationStore.continuation?.yield(revision)
        }
    }
}

extension RuntimeRenderSnapshotService: RuntimeRenderSnapshotSink {
    func submitRuntimeRenderSnapshot(_ renderSnapshot: RuntimeRenderSnapshot) {
        _ = submit(renderSnapshot)
    }
}

final class RuntimeCommandService: @unchecked Sendable {
    private let runtimeEngine: RuntimeCoreBoundary

    init(runtimeEngine: RuntimeCoreBoundary) {
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
    private let runtimeEngine: RuntimeCoreBoundary
    private let runtimeCommandService: RuntimeCommandService

    init(
        inputRuntimeService: InputRuntimeService,
        renderSnapshotService: RuntimeRenderSnapshotService,
        runtimeEngine: RuntimeCoreBoundary,
        runtimeCommandService: RuntimeCommandService
    ) {
        self.inputRuntimeService = inputRuntimeService
        self.renderSnapshotService = renderSnapshotService
        self.runtimeEngine = runtimeEngine
        self.runtimeCommandService = runtimeCommandService
        inputRuntimeService.setCaptureStateProvider { [weak runtimeEngine] in
            runtimeEngine?.isCaptureActive ?? false
        }
        inputRuntimeService.setLiveFrameHandler { [weak self] rawFrame, ingress in
            self?.handleLiveFrame(rawFrame, ingress: ingress)
        }
    }

    deinit {
        inputRuntimeService.setCaptureStateProvider(nil)
        inputRuntimeService.setLiveFrameHandler(nil)
    }

    private func handleLiveFrame(
        _ rawFrame: OMSRawTouchFrame,
        ingress: RuntimeCaptureIngressSnapshot?
    ) {
        let shouldCaptureRenderSnapshot = renderSnapshotService.isRecordingEnabled
        runtimeEngine.ingestLive(
            rawFrame,
            ingress: ingress,
            captureRenderSnapshot: shouldCaptureRenderSnapshot,
            renderSnapshotSink: shouldCaptureRenderSnapshot ? renderSnapshotService : nil
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
    private let runtimeEngine: RuntimeCoreBoundary
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
        runtimeEngine: RuntimeCoreBoundary,
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
