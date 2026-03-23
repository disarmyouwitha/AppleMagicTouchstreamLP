import Dispatch
import Foundation
import CoreGraphics
import os

protocol EngineActorBoundary: Sendable {
    func ingest(
        _ frame: RuntimeRawFrame,
        captureRenderSnapshot: Bool
    ) async -> RuntimeRenderSnapshot?
    func setLiveRenderSnapshotHandler(
        _ handler: (@Sendable (RuntimeRenderSnapshot) -> Void)?
    )
    func ingestLive(
        _ frame: OMSRawTouchFrame,
        captureRenderSnapshot: Bool
    )
    func setListening(_ isListening: Bool) async
    func updateActiveDevices(
        leftIndex: Int?,
        rightIndex: Int?,
        leftDeviceID: String?,
        rightDeviceID: String?
    ) async
    func updateLayouts(
        leftLayout: ContentViewModel.Layout,
        rightLayout: ContentViewModel.Layout,
        leftLabels: [[String]],
        rightLabels: [[String]],
        trackpadSize: CGSize,
        trackpadWidthMm: CGFloat
    ) async
    func updateCustomButtons(_ buttons: [CustomButton]) async
    func updateKeyMappings(_ actions: LayeredKeyMappings) async
    func setPersistentLayer(_ layer: Int) async
    func updateHoldThreshold(_ seconds: TimeInterval) async
    func updateDragCancelDistance(_ distance: CGFloat) async
    func updateTypingGrace(_ milliseconds: Double) async
    func updateIntentMoveThreshold(_ millimeters: Double) async
    func updateIntentVelocityThreshold(_ millimetersPerSecond: Double) async
    func updateAllowMouseTakeover(_ enabled: Bool) async
    func updateForceClickMin(_ grams: Double) async
    func updateForceClickCap(_ grams: Double) async
    func updateForceClickThreshold(_ grams: Double) async
    func updateHapticStrength(_ normalized: Double) async
    func updateSnapRadiusPercent(_ percent: Double) async
    func updateKeyboardModeEnabled(_ enabled: Bool) async
    func updateHoldRepeatEnabled(_ enabled: Bool) async
    func setKeymapEditingEnabled(_ enabled: Bool) async
    func updateTapClickCadence(_ milliseconds: Double) async
    func updateGestureActions(_ actions: GestureActionSet) async
    func updateGestureRepeatCadenceMsById(_ cadenceById: [String: Int]?) async
    func clearVisualCaches() async
    func reset(stopVoiceDictation: Bool) async
}

final class EngineActor: EngineActorBoundary, @unchecked Sendable {
    private struct PendingLiveFrame {
        var frame: OMSRawTouchFrame
        var captureRenderSnapshot: Bool
    }

    private struct LiveRingState {
        static let capacity = 256

        var slots: [PendingLiveFrame?] = Array(repeating: nil, count: capacity)
        var readIndex = 0
        var writeIndex = 0
        var count = 0
        var drainScheduled = false
    }

    private let queue: DispatchQueue
    private var latestRender = RuntimeRenderSnapshot()
    private var leftDeviceIndex: Int?
    private var rightDeviceIndex: Int?
    private let processor: TouchProcessorEngine
    private let liveRingLock = OSAllocatedUnfairLock<LiveRingState>(
        uncheckedState: LiveRingState()
    )
    private let liveRenderSnapshotHandlerLock = OSAllocatedUnfairLock<((RuntimeRenderSnapshot) -> Void)?>(
        uncheckedState: nil
    )

    init(
        dispatchService: DispatchService = .shared,
        onTypingEnabledChanged: @Sendable @escaping (Bool) -> Void = { _ in },
        onActiveLayerChanged: @Sendable @escaping (Int) -> Void = { _ in },
        onDebugBindingDetected: @Sendable @escaping (ContentViewModel.KeyBinding) -> Void = { _ in },
        onContactCountChanged: @Sendable @escaping (SidePair<Int>) -> Void = { _ in },
        onIntentStateChanged: @Sendable @escaping (SidePair<ContentViewModel.IntentDisplay>) -> Void = { _ in },
        onVoiceGestureChanged: @Sendable @escaping (Bool) -> Void = { _ in }
    ) {
        let queue = DispatchQueue(
            label: "ink.ranna.glasstokey.engine.runtime",
            qos: .userInitiated
        )
        self.queue = queue
        processor = TouchProcessorEngine(
            executionQueue: queue,
            dispatchService: dispatchService,
            onTypingEnabledChanged: onTypingEnabledChanged,
            onActiveLayerChanged: onActiveLayerChanged,
            onDebugBindingDetected: onDebugBindingDetected,
            onContactCountChanged: onContactCountChanged,
            onIntentStateChanged: onIntentStateChanged,
            onVoiceGestureChanged: onVoiceGestureChanged
        )
    }

    func ingest(
        _ frame: RuntimeRawFrame,
        captureRenderSnapshot: Bool
    ) async -> RuntimeRenderSnapshot? {
        await query {
            self.processIngest(
                frame,
                captureRenderSnapshot: captureRenderSnapshot
            )
        }
    }

    func setLiveRenderSnapshotHandler(
        _ handler: (@Sendable (RuntimeRenderSnapshot) -> Void)?
    ) {
        liveRenderSnapshotHandlerLock.withLockUnchecked { $0 = handler }
    }

    func ingestLive(
        _ frame: OMSRawTouchFrame,
        captureRenderSnapshot: Bool
    ) {
        enum EnqueueResult {
            case scheduled
            case queued
            case dropped
        }

        let result = liveRingLock.withLockUnchecked { state -> EnqueueResult in
            guard state.count < state.slots.count else {
                return .dropped
            }
            state.slots[state.writeIndex] = PendingLiveFrame(
                frame: frame,
                captureRenderSnapshot: captureRenderSnapshot
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
            queue.async { [weak self] in
                self?.drainLiveFrames()
            }
        case .queued:
            return
        case .dropped:
            frame.release()
        }
    }

    func setListening(_ isListening: Bool) async {
        await run {
            self.processor.setListening(isListening)
        }
    }

    func updateActiveDevices(
        leftIndex: Int?,
        rightIndex: Int?,
        leftDeviceID: String?,
        rightDeviceID: String?
    ) async {
        await run {
            self.leftDeviceIndex = leftIndex
            self.rightDeviceIndex = rightIndex
            self.processor.updateActiveDevices(
                leftIndex: leftIndex,
                rightIndex: rightIndex,
                leftDeviceID: leftDeviceID,
                rightDeviceID: rightDeviceID
            )
        }
    }

    func updateLayouts(
        leftLayout: ContentViewModel.Layout,
        rightLayout: ContentViewModel.Layout,
        leftLabels: [[String]],
        rightLabels: [[String]],
        trackpadSize: CGSize,
        trackpadWidthMm: CGFloat
    ) async {
        await run {
            self.processor.updateLayouts(
                leftLayout: leftLayout,
                rightLayout: rightLayout,
                leftLabels: leftLabels,
                rightLabels: rightLabels,
                trackpadSize: trackpadSize,
                trackpadWidthMm: trackpadWidthMm
            )
        }
    }

    func updateCustomButtons(_ buttons: [CustomButton]) async {
        await run {
            self.processor.updateCustomButtons(buttons)
        }
    }

    func updateKeyMappings(_ actions: LayeredKeyMappings) async {
        await run {
            self.processor.updateKeyMappings(actions)
        }
    }

    func setPersistentLayer(_ layer: Int) async {
        await run {
            self.processor.setPersistentLayer(layer)
        }
    }

    func updateHoldThreshold(_ seconds: TimeInterval) async {
        await run {
            self.processor.updateHoldThreshold(seconds)
        }
    }

    func updateDragCancelDistance(_ distance: CGFloat) async {
        await run {
            self.processor.updateDragCancelDistance(distance)
        }
    }

    func updateTypingGrace(_ milliseconds: Double) async {
        await run {
            self.processor.updateTypingGrace(milliseconds)
        }
    }

    func updateIntentMoveThreshold(_ millimeters: Double) async {
        await run {
            self.processor.updateIntentMoveThreshold(millimeters)
        }
    }

    func updateIntentVelocityThreshold(_ millimetersPerSecond: Double) async {
        await run {
            self.processor.updateIntentVelocityThreshold(millimetersPerSecond)
        }
    }

    func updateAllowMouseTakeover(_ enabled: Bool) async {
        await run {
            self.processor.updateAllowMouseTakeover(enabled)
        }
    }

    func updateForceClickMin(_ grams: Double) async {
        await run {
            self.processor.updateForceClickMin(grams)
        }
    }

    func updateForceClickCap(_ grams: Double) async {
        await run {
            self.processor.updateForceClickCap(grams)
        }
    }

    func updateForceClickThreshold(_ grams: Double) async {
        await run {
            self.processor.updateForceClickThreshold(grams)
        }
    }

    func updateHapticStrength(_ normalized: Double) async {
        await run {
            self.processor.updateHapticStrength(normalized)
        }
    }

    func updateSnapRadiusPercent(_ percent: Double) async {
        await run {
            self.processor.updateSnapRadiusPercent(percent)
        }
    }

    func updateKeyboardModeEnabled(_ enabled: Bool) async {
        await run {
            self.processor.updateKeyboardModeEnabled(enabled)
        }
    }

    func updateHoldRepeatEnabled(_ enabled: Bool) async {
        await run {
            self.processor.updateHoldRepeatEnabled(enabled)
        }
    }

    func setKeymapEditingEnabled(_ enabled: Bool) async {
        await run {
            self.processor.setKeymapEditingEnabled(enabled)
        }
    }

    func updateTapClickCadence(_ milliseconds: Double) async {
        await run {
            self.processor.updateTapClickCadence(milliseconds)
        }
    }

    func updateGestureActions(_ actions: GestureActionSet) async {
        await run {
            self.processor.updateGestureActions(actions)
        }
    }

    func updateGestureRepeatCadenceMsById(_ cadenceById: [String: Int]?) async {
        await run {
            self.processor.updateGestureRepeatCadenceMsById(cadenceById)
        }
    }

    func clearVisualCaches() async {
        await run {
            self.processor.clearVisualCaches()
        }
    }

    func reset(stopVoiceDictation: Bool) async {
        await run {
            self.processor.resetState(stopVoiceDictation: stopVoiceDictation)
            self.latestRender = RuntimeRenderSnapshot()
        }
    }

    private func run(_ work: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { continuation in
            queue.async {
                work()
                continuation.resume()
            }
        }
    }

    private func query<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: work())
            }
        }
    }

    private func drainLiveFrames() {
        let renderSnapshotHandler = liveRenderSnapshotHandlerLock.withLockUnchecked { $0 }
        while true {
            let pending = liveRingLock.withLockUnchecked { state -> PendingLiveFrame? in
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
            defer { pending.frame.release() }
            guard let renderSnapshot = processIngest(
                pending.frame,
                captureRenderSnapshot: pending.captureRenderSnapshot
            ) else {
                continue
            }
            renderSnapshotHandler?(renderSnapshot)
        }
    }

    private func processIngest(
        _ frame: RuntimeRawFrame,
        captureRenderSnapshot: Bool
    ) -> RuntimeRenderSnapshot? {
        processor.processRuntimeRawFrame(frame)
        guard captureRenderSnapshot else { return nil }
        updateRenderSnapshot(from: frame)
        return latestRender
    }

    private func processIngest(
        _ frame: OMSRawTouchFrame,
        captureRenderSnapshot: Bool
    ) -> RuntimeRenderSnapshot? {
        processor.processRawFrame(frame)
        guard captureRenderSnapshot else { return nil }
        updateRenderSnapshot(from: frame)
        return latestRender
    }

    private func updateRenderSnapshot(from frame: OMSRawTouchFrame) {
        let deviceIndex = frame.deviceIndex
        let matchedLeft = leftDeviceIndex.map { $0 == deviceIndex } ?? false
        let matchedRight = rightDeviceIndex.map { $0 == deviceIndex } ?? false
        guard matchedLeft || matchedRight else { return }

        let touches = Self.renderTouches(from: frame)
        if matchedLeft {
            latestRender.leftTouches = touches
        }
        if matchedRight {
            latestRender.rightTouches = touches
        }
        latestRender.hasTransitionState = Self.hasTransitionState(
            left: latestRender.leftTouches,
            right: latestRender.rightTouches
        )
        latestRender.revision &+= 1
    }

    private func updateRenderSnapshot(from frame: RuntimeRawFrame) {
        let deviceIndex = frame.deviceIndex
        let matchedLeft = leftDeviceIndex.map { $0 == deviceIndex } ?? false
        let matchedRight = rightDeviceIndex.map { $0 == deviceIndex } ?? false
        guard matchedLeft || matchedRight else { return }

        let touches = Self.renderTouches(from: frame)
        if matchedLeft {
            latestRender.leftTouches = touches
        }
        if matchedRight {
            latestRender.rightTouches = touches
        }
        latestRender.hasTransitionState = Self.hasTransitionState(
            left: latestRender.leftTouches,
            right: latestRender.rightTouches
        )
        latestRender.revision &+= 1
    }

    private static func renderTouches(from frame: OMSRawTouchFrame) -> [OMSTouchData] {
        let touches = frame.touches
        guard !touches.isEmpty else { return [] }
        return touches.map { touch in
            OMSTouchData(
                deviceID: frame.deviceID,
                deviceIndex: frame.deviceIndex,
                id: touch.id,
                position: OMSPosition(x: touch.posX, y: touch.posY),
                total: touch.total,
                pressure: touch.pressure,
                axis: OMSAxis(major: touch.majorAxis, minor: touch.minorAxis),
                angle: touch.angle,
                density: touch.density,
                state: touch.state,
                timestamp: frame.timestamp
            )
        }
    }

    private static func renderTouches(from frame: RuntimeRawFrame) -> [OMSTouchData] {
        let touches = frame.rawTouches
        let deviceID = String(frame.deviceNumericID)
        if !touches.isEmpty {
            return touches.map { touch in
                OMSTouchData(
                    deviceID: deviceID,
                    deviceIndex: frame.deviceIndex,
                    id: touch.id,
                    position: OMSPosition(x: touch.posX, y: touch.posY),
                    total: touch.total,
                    pressure: touch.pressure,
                    axis: OMSAxis(major: touch.majorAxis, minor: touch.minorAxis),
                    angle: touch.angle,
                    density: touch.density,
                    state: touch.state,
                    timestamp: frame.timestamp
                )
            }
        }
        return frame.contacts.map { contact in
            OMSTouchData(
                deviceID: deviceID,
                deviceIndex: frame.deviceIndex,
                id: contact.id,
                position: OMSPosition(x: contact.posX, y: contact.posY),
                total: 0,
                pressure: contact.pressure,
                axis: OMSAxis(major: contact.majorAxis, minor: contact.minorAxis),
                angle: contact.angle,
                density: contact.density,
                state: contact.state,
                timestamp: frame.timestamp
            )
        }
    }

    private static func hasTransitionState(
        left: [OMSTouchData],
        right: [OMSTouchData]
    ) -> Bool {
        func containsTransition(_ touches: [OMSTouchData]) -> Bool {
            for touch in touches {
                switch touch.state {
                case .starting, .breaking, .leaving:
                    return true
                default:
                    break
                }
            }
            return false
        }
        return containsTransition(left) || containsTransition(right)
    }
}
