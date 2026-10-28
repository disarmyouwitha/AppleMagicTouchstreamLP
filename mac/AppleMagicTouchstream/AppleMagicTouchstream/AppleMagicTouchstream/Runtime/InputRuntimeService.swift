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
        InterpretedTrackpadPointer.shared.stop()
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
    private let continuations = OSAllocatedUnfairLock<[UUID:AsyncStream<UInt64>.Continuation]>(
        uncheckedState: [:]
    )

    // Each visualizer attachment owns an independent stream. Cancellation must
    // remove only that subscriber, never terminate future/replacement views.
    var revisionUpdates: AsyncStream<UInt64> {
        AsyncStream(bufferingPolicy:.bufferingNewest(1)) { continuation in
            let id = UUID()
            continuation.onTermination = { [weak self] _ in
                _ = self?.continuations.withLockUnchecked { $0.removeValue(forKey:id) }
            }
            continuations.withLockUnchecked { $0[id] = continuation }
        }
    }

    deinit {
        let subscribers = continuations.withLockUnchecked { Array($0.values) }
        for subscriber in subscribers { subscriber.finish() }
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
            // Delivery runs off the input path; release the lock before yielding,
            // since termination may synchronously remove its own subscription.
            let subscribers = continuations.withLockUnchecked { Array($0.values) }
            for subscriber in subscribers { subscriber.yield(revision) }
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



    func prepareNativeTakeoverRelease() async {
        await runtimeEngine.setListening(false)
        await runtimeEngine.reset(stopVoiceDictation: true)
    }

    func finishNativeTakeoverRelease(listening: Bool) async {
        await runtimeEngine.setListening(listening)
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

/// Transport IDs are connection-scoped; a physical key may match BT and USB.
struct TrackpadRecoveryIdentity: Codable, Equatable, Sendable {
    var connection: String
    var physical: String?
    var aliases: [String]? = nil

    func acceptsSavedConnection(_ value: String) -> Bool { connection == value || aliases?.contains(value) == true }

    static func choose(_ desired: Self?, from available: [Self], excluding: Set<String> = [],
                       usb: Set<String> = []) -> String? {
        guard let desired else { return nil }
        let candidates = available.filter { !excluding.contains($0.connection) }
        if let physical = desired.physical {
            let matches = candidates.filter { $0.physical == physical }
            let wired = matches.filter { usb.contains($0.connection) }
            if wired.count == 1 { return wired[0].connection }
            if matches.count == 1 { return matches[0].connection }
            if matches.count > 1 { return nil } // Ambiguous identity: never guess.
        }
        return candidates.first { candidate in
            guard candidate.connection == desired.connection else { return false }
            if let old = desired.physical, let new = candidate.physical,
               old.hasPrefix("bt:"), new.hasPrefix("bt:"), old != new { return false }
            return true
        }?.connection
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
    var recoveryAllowed: (() -> Bool)?
    var recoverSelection: (([OMSDeviceInfo], OMSDeviceInfo?, OMSDeviceInfo?) async -> Bool)?
    private let manager: OMSManager
    private let runtimeEngine: RuntimeCoreBoundary
    private let onStateChanged: @MainActor (State) -> Void
    private var state = State()
    private var desiredLeft: TrackpadRecoveryIdentity?
    private var desiredRight: TrackpadRecoveryIdentity?
    private var recoveryTask: Task<Void, Never>?
    private var revision = 0

    init(manager: OMSManager = .shared, runtimeEngine: RuntimeCoreBoundary,
         onStateChanged: @escaping @MainActor (State) -> Void = { _ in }) {
        self.manager = manager; self.runtimeEngine = runtimeEngine; self.onStateChanged = onStateChanged
    }
    deinit { recoveryTask?.cancel() }
    var snapshot: State { state }
    var requestedSelectionIDs: (left: String, right: String) {
        (desiredLeft?.connection ?? "", desiredRight?.connection ?? "")
    }

    private func identity(_ device: OMSDeviceInfo?) -> TrackpadRecoveryIdentity? {
        device.map { .init(connection: $0.deviceID, physical: $0.physicalIdentity) }
    }
    private func remember(_ device: OMSDeviceInfo?, side: String) -> TrackpadRecoveryIdentity? {
        let key = "AppleMagicTouchstream.recoveryIdentity." + side
        let legacy = side == "left" ? GlassToKeyDefaultsKeys.leftDeviceID : GlassToKeyDefaultsKeys.rightDeviceID
        if let device {
            var value = identity(device)!
            if let data = UserDefaults.standard.data(forKey: key),
               let previous = try? JSONDecoder().decode(TrackpadRecoveryIdentity.self, from: data),
               let physical = value.physical, physical == previous.physical {
                value.aliases = Array(Set((previous.aliases ?? []) + [previous.connection, device.deviceID])).sorted()
            }
            UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
            return value
        }
        // A disconnected saved selection must survive startup. Explicit None is
        // represented by an empty saved connection ID and clears the identity.
        let saved = UserDefaults.standard.string(forKey: legacy) ?? ""
        if !saved.isEmpty, let data = UserDefaults.standard.data(forKey: key),
           let value = try? JSONDecoder().decode(TrackpadRecoveryIdentity.self, from: data),
           value.acceptsSavedConnection(saved) { return value }
        if !saved.isEmpty { return .init(connection: saved, physical: nil) }
        UserDefaults.standard.removeObject(forKey: key)
        return nil
    }
    func loadDevices(preserveSelection: Bool = false) {
        state.availableDevices = manager.discoverDevices()
        if !preserveSelection {
            state.leftDevice = state.availableDevices.first
            state.rightDevice = state.availableDevices.dropFirst().first
            desiredLeft = identity(state.leftDevice); desiredRight = identity(state.rightDevice)
        } else {
            let resolved = resolve(state.availableDevices)
            state.leftDevice = resolved.0; state.rightDevice = resolved.1
        }
        updateActiveDevices(); publishState()
    }
    func selectDevices(left: OMSDeviceInfo?, right: OMSDeviceInfo?, editedSide: TrackpadSide) {
        if editedSide == .left {
            if left == nil { UserDefaults.standard.set("", forKey: GlassToKeyDefaultsKeys.leftDeviceID) }
            desiredLeft = remember(left, side: "left")
        } else {
            if right == nil { UserDefaults.standard.set("", forKey: GlassToKeyDefaultsKeys.rightDeviceID) }
            desiredRight = remember(right, side: "right")
        }
        state.leftDevice = left; state.rightDevice = right
        revision += 1; updateActiveDevices(); publishState()
    }
    func selectLeftDevice(_ device: OMSDeviceInfo?) {
        desiredLeft = remember(device, side: "left"); state.leftDevice = device
        revision += 1; updateActiveDevices(); publishState()
    }
    func selectRightDevice(_ device: OMSDeviceInfo?) {
        desiredRight = remember(device, side: "right"); state.rightDevice = device
        revision += 1; updateActiveDevices(); publishState()
    }
    func startConnectionRecovery() {
        guard recoveryTask == nil else { return }
        recoveryTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                guard let self else { return }
                await self.checkConnections()
            }
        }
    }
    private func resolve(_ devices: [OMSDeviceInfo]) -> (OMSDeviceInfo?, OMSDeviceInfo?) {
        let identities = devices.compactMap(identity)
        let usb = Set(devices.filter { $0.transport == "USB" }.map(\.deviceID))
        let leftID = TrackpadRecoveryIdentity.choose(desiredLeft, from: identities, usb: usb)
        let rightID = TrackpadRecoveryIdentity.choose(desiredRight, from: identities,
            excluding: Set([leftID].compactMap { $0 }), usb: usb)
        return (devices.first { $0.deviceID == leftID }, devices.first { $0.deviceID == rightID })
    }
    private func checkConnections() async {
        guard recoveryAllowed?() == true else { return }
        let devices = manager.discoverDevices()
        let next = resolve(devices)
        let changed = next.0 != state.leftDevice || next.1 != state.rightDevice
        if changed {
            guard let recoverSelection else { return }
            let version = revision
            // Remove only vanished connection routes before touching native clients.
            // New routes are published only after acquisition succeeds.
            let retainedLeft = state.leftDevice?.deviceID == next.0?.deviceID ? state.leftDevice : nil
            let retainedRight = state.rightDevice?.deviceID == next.1?.deviceID ? state.rightDevice : nil
            await runtimeEngine.updateActiveDevices(
                leftIndex: retainedLeft.flatMap { manager.deviceIndex(for: $0.deviceID) },
                rightIndex: retainedRight.flatMap { manager.deviceIndex(for: $0.deviceID) },
                leftDeviceID: retainedLeft?.deviceID, rightDeviceID: retainedRight?.deviceID)
            guard version == revision, recoveryAllowed?() == true else { return }
            guard await recoverSelection(devices, next.0, next.1), version == revision else {
                updateRouting(); return
            }
            state.availableDevices = devices; state.leftDevice = next.0; state.rightDevice = next.1
            if let left = next.0 { desiredLeft = remember(left, side: "left") }
            if let right = next.1 { desiredRight = remember(right, side: "right") }
            updateRouting(); publishState()
        } else if devices != state.availableDevices {
            // Inventory changes do not rebuild callbacks or reset input.
            state.availableDevices = devices; publishState()
        }
    }
    private func publishState() {
        state.hasDisconnectedTrackpads = (desiredLeft != nil && state.leftDevice == nil)
            || (desiredRight != nil && state.rightDevice == nil)
        onStateChanged(state)
    }
    private func updateActiveDevices() {
        let devices = [state.leftDevice, state.rightDevice].compactMap { $0 }
        // Native selected FLTR sessions are already committed by the coordinator.
        if manager.nativeTakeoverStatus["active"] as? Bool != true {
            _ = manager.reconcileOrdinaryDevices(devices)
        }
        updateRouting()
    }
    private func updateRouting() {
        let left = state.leftDevice, right = state.rightDevice
        let leftIndex = left.flatMap { manager.deviceIndex(for: $0.deviceID) }
        let rightIndex = right.flatMap { manager.deviceIndex(for: $0.deviceID) }
        let runtimeEngine = runtimeEngine
        Task { await runtimeEngine.updateActiveDevices(leftIndex: leftIndex, rightIndex: rightIndex,
            leftDeviceID: left?.deviceID, rightDeviceID: right?.deviceID) }
    }
}
