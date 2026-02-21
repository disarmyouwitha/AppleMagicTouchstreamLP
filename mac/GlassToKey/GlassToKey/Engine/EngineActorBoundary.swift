import Foundation
import CoreGraphics
import OpenMultitouchSupport

protocol EngineActorBoundary: Sendable {
    func ingest(_ frame: RuntimeRawFrame) async
    func renderSnapshot() async -> RuntimeRenderSnapshot
    func statusSnapshot() async -> RuntimeStatusSnapshot
    func setRenderSnapshotsEnabled(_ enabled: Bool) async
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
    func updateForceClickCap(_ grams: Double) async
    func updateHapticStrength(_ normalized: Double) async
    func updateSnapRadiusPercent(_ percent: Double) async
    func updateChordalShiftEnabled(_ enabled: Bool) async
    func updateKeyboardModeEnabled(_ enabled: Bool) async
    func setKeymapEditingEnabled(_ enabled: Bool) async
    func updateTapClickEnabled(_ enabled: Bool) async
    func updateTapClickCadence(_ milliseconds: Double) async
    func clearVisualCaches() async
    func reset(stopVoiceDictation: Bool) async
}

actor EngineActor: EngineActorBoundary {
    private var latestRender = RuntimeRenderSnapshot()
    private var latestStatus = RuntimeStatusSnapshot()
    private var leftDeviceIndex: Int?
    private var rightDeviceIndex: Int?
    private var renderSnapshotsEnabled = false
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
        processor = TouchProcessorEngine(
            dispatchService: dispatchService,
            onTypingEnabledChanged: onTypingEnabledChanged,
            onActiveLayerChanged: onActiveLayerChanged,
            onDebugBindingDetected: onDebugBindingDetected,
            onContactCountChanged: onContactCountChanged,
            onIntentStateChanged: onIntentStateChanged,
            onVoiceGestureChanged: onVoiceGestureChanged
        )
    }

    func ingest(_ frame: RuntimeRawFrame) async {
        await processor.processRuntimeRawFrame(frame)
        if renderSnapshotsEnabled {
            updateRenderSnapshot(from: frame)
        }
        await refreshStatusFromProcessor()
        latestStatus.diagnostics.captureFrames &+= 1
    }

    func renderSnapshot() async -> RuntimeRenderSnapshot {
        latestRender
    }

    func statusSnapshot() async -> RuntimeStatusSnapshot {
        await refreshStatusFromProcessor()
        return latestStatus
    }

    func setRenderSnapshotsEnabled(_ enabled: Bool) async {
        guard renderSnapshotsEnabled != enabled else { return }
        renderSnapshotsEnabled = enabled
        if !enabled {
            latestRender = RuntimeRenderSnapshot()
        }
    }

    func setListening(_ isListening: Bool) async {
        await processor.setListening(isListening)
    }

    func updateActiveDevices(
        leftIndex: Int?,
        rightIndex: Int?,
        leftDeviceID: String?,
        rightDeviceID: String?
    ) async {
        leftDeviceIndex = leftIndex
        rightDeviceIndex = rightIndex
        await processor.updateActiveDevices(
            leftIndex: leftIndex,
            rightIndex: rightIndex,
            leftDeviceID: leftDeviceID,
            rightDeviceID: rightDeviceID
        )
    }

    func updateLayouts(
        leftLayout: ContentViewModel.Layout,
        rightLayout: ContentViewModel.Layout,
        leftLabels: [[String]],
        rightLabels: [[String]],
        trackpadSize: CGSize,
        trackpadWidthMm: CGFloat
    ) async {
        await processor.updateLayouts(
            leftLayout: leftLayout,
            rightLayout: rightLayout,
            leftLabels: leftLabels,
            rightLabels: rightLabels,
            trackpadSize: trackpadSize,
            trackpadWidthMm: trackpadWidthMm
        )
    }

    func updateCustomButtons(_ buttons: [CustomButton]) async {
        await processor.updateCustomButtons(buttons)
    }

    func updateKeyMappings(_ actions: LayeredKeyMappings) async {
        await processor.updateKeyMappings(actions)
    }

    func setPersistentLayer(_ layer: Int) async {
        await processor.setPersistentLayer(layer)
    }

    func updateHoldThreshold(_ seconds: TimeInterval) async {
        await processor.updateHoldThreshold(seconds)
    }

    func updateDragCancelDistance(_ distance: CGFloat) async {
        await processor.updateDragCancelDistance(distance)
    }

    func updateTypingGrace(_ milliseconds: Double) async {
        await processor.updateTypingGrace(milliseconds)
    }

    func updateIntentMoveThreshold(_ millimeters: Double) async {
        await processor.updateIntentMoveThreshold(millimeters)
    }

    func updateIntentVelocityThreshold(_ millimetersPerSecond: Double) async {
        await processor.updateIntentVelocityThreshold(millimetersPerSecond)
    }

    func updateAllowMouseTakeover(_ enabled: Bool) async {
        await processor.updateAllowMouseTakeover(enabled)
    }

    func updateForceClickCap(_ grams: Double) async {
        await processor.updateForceClickCap(grams)
    }

    func updateHapticStrength(_ normalized: Double) async {
        await processor.updateHapticStrength(normalized)
    }

    func updateSnapRadiusPercent(_ percent: Double) async {
        await processor.updateSnapRadiusPercent(percent)
    }

    func updateChordalShiftEnabled(_ enabled: Bool) async {
        await processor.updateChordalShiftEnabled(enabled)
    }

    func updateKeyboardModeEnabled(_ enabled: Bool) async {
        await processor.updateKeyboardModeEnabled(enabled)
    }

    func setKeymapEditingEnabled(_ enabled: Bool) async {
        await processor.setKeymapEditingEnabled(enabled)
    }

    func updateTapClickEnabled(_ enabled: Bool) async {
        await processor.updateTapClickEnabled(enabled)
    }

    func updateTapClickCadence(_ milliseconds: Double) async {
        await processor.updateTapClickCadence(milliseconds)
    }

    func clearVisualCaches() async {
        await processor.clearVisualCaches()
    }

    func reset(stopVoiceDictation: Bool) async {
        await processor.resetState(stopVoiceDictation: stopVoiceDictation)
        latestRender = RuntimeRenderSnapshot()
        latestStatus = RuntimeStatusSnapshot()
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

    private func refreshStatusFromProcessor() async {
        let snapshot = await processor.statusSnapshot()
        latestStatus.intentBySide = SidePair(
            left: Self.mapRuntimeIntent(snapshot.intentDisplays.left),
            right: Self.mapRuntimeIntent(snapshot.intentDisplays.right)
        )
        latestStatus.contactCountBySide = snapshot.contactCounts
        latestStatus.typingEnabled = snapshot.typingEnabled
        latestStatus.keyboardModeEnabled = snapshot.keyboardModeEnabled
        latestStatus.diagnostics.dispatchQueueDepth = snapshot.dispatchQueueDepth
        latestStatus.diagnostics.dispatchDrops = snapshot.dispatchDrops
    }

    private static func renderTouches(from frame: RuntimeRawFrame) -> [OMSTouchData] {
        let deviceID = String(frame.deviceNumericID)
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

    private static func mapRuntimeIntent(_ intent: ContentViewModel.IntentDisplay) -> RuntimeIntentMode {
        switch intent {
        case .idle:
            return .idle
        case .keyCandidate:
            return .keyCandidate
        case .typing:
            return .typing
        case .mouse:
            return .mouse
        case .gesture:
            return .gesture
        }
    }
}

actor EngineActorStub: EngineActorBoundary {
    private let impl = EngineActor()

    func ingest(_ frame: RuntimeRawFrame) async {
        await impl.ingest(frame)
    }

    func renderSnapshot() async -> RuntimeRenderSnapshot {
        await impl.renderSnapshot()
    }

    func statusSnapshot() async -> RuntimeStatusSnapshot {
        await impl.statusSnapshot()
    }

    func setRenderSnapshotsEnabled(_ enabled: Bool) async {
        await impl.setRenderSnapshotsEnabled(enabled)
    }

    func setListening(_ isListening: Bool) async {
        await impl.setListening(isListening)
    }

    func updateActiveDevices(
        leftIndex: Int?,
        rightIndex: Int?,
        leftDeviceID: String?,
        rightDeviceID: String?
    ) async {
        await impl.updateActiveDevices(
            leftIndex: leftIndex,
            rightIndex: rightIndex,
            leftDeviceID: leftDeviceID,
            rightDeviceID: rightDeviceID
        )
    }

    func updateLayouts(
        leftLayout: ContentViewModel.Layout,
        rightLayout: ContentViewModel.Layout,
        leftLabels: [[String]],
        rightLabels: [[String]],
        trackpadSize: CGSize,
        trackpadWidthMm: CGFloat
    ) async {
        await impl.updateLayouts(
            leftLayout: leftLayout,
            rightLayout: rightLayout,
            leftLabels: leftLabels,
            rightLabels: rightLabels,
            trackpadSize: trackpadSize,
            trackpadWidthMm: trackpadWidthMm
        )
    }

    func updateCustomButtons(_ buttons: [CustomButton]) async {
        await impl.updateCustomButtons(buttons)
    }

    func updateKeyMappings(_ actions: LayeredKeyMappings) async {
        await impl.updateKeyMappings(actions)
    }

    func setPersistentLayer(_ layer: Int) async {
        await impl.setPersistentLayer(layer)
    }

    func updateHoldThreshold(_ seconds: TimeInterval) async {
        await impl.updateHoldThreshold(seconds)
    }

    func updateDragCancelDistance(_ distance: CGFloat) async {
        await impl.updateDragCancelDistance(distance)
    }

    func updateTypingGrace(_ milliseconds: Double) async {
        await impl.updateTypingGrace(milliseconds)
    }

    func updateIntentMoveThreshold(_ millimeters: Double) async {
        await impl.updateIntentMoveThreshold(millimeters)
    }

    func updateIntentVelocityThreshold(_ millimetersPerSecond: Double) async {
        await impl.updateIntentVelocityThreshold(millimetersPerSecond)
    }

    func updateAllowMouseTakeover(_ enabled: Bool) async {
        await impl.updateAllowMouseTakeover(enabled)
    }

    func updateForceClickCap(_ grams: Double) async {
        await impl.updateForceClickCap(grams)
    }

    func updateHapticStrength(_ normalized: Double) async {
        await impl.updateHapticStrength(normalized)
    }

    func updateSnapRadiusPercent(_ percent: Double) async {
        await impl.updateSnapRadiusPercent(percent)
    }

    func updateChordalShiftEnabled(_ enabled: Bool) async {
        await impl.updateChordalShiftEnabled(enabled)
    }

    func updateKeyboardModeEnabled(_ enabled: Bool) async {
        await impl.updateKeyboardModeEnabled(enabled)
    }

    func setKeymapEditingEnabled(_ enabled: Bool) async {
        await impl.setKeymapEditingEnabled(enabled)
    }

    func updateTapClickEnabled(_ enabled: Bool) async {
        await impl.updateTapClickEnabled(enabled)
    }

    func updateTapClickCadence(_ milliseconds: Double) async {
        await impl.updateTapClickCadence(milliseconds)
    }

    func clearVisualCaches() async {
        await impl.clearVisualCaches()
    }

    func reset(stopVoiceDictation: Bool) async {
        await impl.reset(stopVoiceDictation: stopVoiceDictation)
    }
}
