import Dispatch
import Foundation
import CoreGraphics
import OpenMultitouchSupport

protocol EngineActorBoundary: Sendable {
    func ingest(
        _ frame: RuntimeRawFrame,
        captureRenderSnapshot: Bool
    ) async -> RuntimeRenderSnapshot?
    func ingestLive(
        _ frame: OMSRawTouchFrame,
        captureRenderSnapshot: Bool,
        onRenderSnapshot: @Sendable @escaping (RuntimeRenderSnapshot) -> Void
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
    private let queue: DispatchQueue
    private var latestRender = RuntimeRenderSnapshot()
    private var leftDeviceIndex: Int?
    private var rightDeviceIndex: Int?
    private let processor: TouchProcessorEngine

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

    func ingestLive(
        _ frame: OMSRawTouchFrame,
        captureRenderSnapshot: Bool,
        onRenderSnapshot: @Sendable @escaping (RuntimeRenderSnapshot) -> Void
    ) {
        queue.async { [weak self, frame] in
            guard let self else {
                frame.release()
                return
            }
            defer { frame.release() }
            guard let renderSnapshot = self.processIngest(
                frame,
                captureRenderSnapshot: captureRenderSnapshot
            ) else {
                return
            }
            onRenderSnapshot(renderSnapshot)
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
