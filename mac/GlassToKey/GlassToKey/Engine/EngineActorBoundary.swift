import Foundation
import CoreGraphics

protocol EngineActorBoundary: Sendable {
    func ingest(_ frame: RuntimeRawFrame) async
    func renderSnapshot() async -> RuntimeRenderSnapshot
    func statusSnapshot() async -> RuntimeStatusSnapshot
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

protocol EngineActorPhase2Delegate: Sendable {
    func ingest(_ frame: RuntimeRawFrame) async
    func statusSnapshot() async -> RuntimeStatusSnapshot
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

actor EngineActorPhase2: EngineActorBoundary {
    private var latestRender = RuntimeRenderSnapshot()
    private var latestStatus = RuntimeStatusSnapshot()
    private var leftDeviceIndex: Int?
    private var rightDeviceIndex: Int?
    private let delegate: (any EngineActorPhase2Delegate)?

    init(delegate: (any EngineActorPhase2Delegate)? = nil) {
        self.delegate = delegate
    }

    func ingest(_ frame: RuntimeRawFrame) async {
        if let delegate {
            await delegate.ingest(frame)
            latestStatus = await mergeStatusSnapshot(from: delegate)
            latestStatus.diagnostics.captureFrames &+= 1
            latestRender.revision &+= 1
            return
        }
        guard let side = side(for: frame.deviceIndex) else { return }
        let contactCount = frame.contacts.count
        if side == .left {
            latestStatus.contactCountBySide.left = contactCount
            latestStatus.intentBySide.left = Self.intent(for: contactCount)
        } else {
            latestStatus.contactCountBySide.right = contactCount
            latestStatus.intentBySide.right = Self.intent(for: contactCount)
        }
        latestStatus.diagnostics.captureFrames &+= 1
        latestRender.revision &+= 1
    }

    func renderSnapshot() async -> RuntimeRenderSnapshot {
        latestRender
    }

    func statusSnapshot() async -> RuntimeStatusSnapshot {
        if let delegate {
            latestStatus = await mergeStatusSnapshot(from: delegate)
        }
        return latestStatus
    }

    func setListening(_ isListening: Bool) async {
        await delegate?.setListening(isListening)
    }

    func updateActiveDevices(
        leftIndex: Int?,
        rightIndex: Int?,
        leftDeviceID: String?,
        rightDeviceID: String?
    ) async {
        leftDeviceIndex = leftIndex
        rightDeviceIndex = rightIndex
        await delegate?.updateActiveDevices(
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
        await delegate?.updateLayouts(
            leftLayout: leftLayout,
            rightLayout: rightLayout,
            leftLabels: leftLabels,
            rightLabels: rightLabels,
            trackpadSize: trackpadSize,
            trackpadWidthMm: trackpadWidthMm
        )
    }

    func updateCustomButtons(_ buttons: [CustomButton]) async {
        await delegate?.updateCustomButtons(buttons)
    }

    func updateKeyMappings(_ actions: LayeredKeyMappings) async {
        await delegate?.updateKeyMappings(actions)
    }

    func setPersistentLayer(_ layer: Int) async {
        await delegate?.setPersistentLayer(layer)
    }

    func updateHoldThreshold(_ seconds: TimeInterval) async {
        await delegate?.updateHoldThreshold(seconds)
    }

    func updateDragCancelDistance(_ distance: CGFloat) async {
        await delegate?.updateDragCancelDistance(distance)
    }

    func updateTypingGrace(_ milliseconds: Double) async {
        await delegate?.updateTypingGrace(milliseconds)
    }

    func updateIntentMoveThreshold(_ millimeters: Double) async {
        await delegate?.updateIntentMoveThreshold(millimeters)
    }

    func updateIntentVelocityThreshold(_ millimetersPerSecond: Double) async {
        await delegate?.updateIntentVelocityThreshold(millimetersPerSecond)
    }

    func updateAllowMouseTakeover(_ enabled: Bool) async {
        await delegate?.updateAllowMouseTakeover(enabled)
    }

    func updateForceClickCap(_ grams: Double) async {
        await delegate?.updateForceClickCap(grams)
    }

    func updateHapticStrength(_ normalized: Double) async {
        await delegate?.updateHapticStrength(normalized)
    }

    func updateSnapRadiusPercent(_ percent: Double) async {
        await delegate?.updateSnapRadiusPercent(percent)
    }

    func updateChordalShiftEnabled(_ enabled: Bool) async {
        await delegate?.updateChordalShiftEnabled(enabled)
    }

    func updateKeyboardModeEnabled(_ enabled: Bool) async {
        await delegate?.updateKeyboardModeEnabled(enabled)
    }

    func setKeymapEditingEnabled(_ enabled: Bool) async {
        await delegate?.setKeymapEditingEnabled(enabled)
    }

    func updateTapClickEnabled(_ enabled: Bool) async {
        await delegate?.updateTapClickEnabled(enabled)
    }

    func updateTapClickCadence(_ milliseconds: Double) async {
        await delegate?.updateTapClickCadence(milliseconds)
    }

    func clearVisualCaches() async {
        await delegate?.clearVisualCaches()
    }

    func reset(stopVoiceDictation: Bool) async {
        await delegate?.reset(stopVoiceDictation: stopVoiceDictation)
        latestRender = RuntimeRenderSnapshot()
        latestStatus = RuntimeStatusSnapshot()
    }

    private static func intent(for contactCount: Int) -> RuntimeIntentMode {
        switch contactCount {
        case ...0:
            return .idle
        case 1:
            return .keyCandidate
        default:
            return .typing
        }
    }

    private func side(for deviceIndex: Int) -> TrackpadSide? {
        if let leftDeviceIndex, deviceIndex == leftDeviceIndex {
            return .left
        }
        if let rightDeviceIndex, deviceIndex == rightDeviceIndex {
            return .right
        }
        if leftDeviceIndex == nil, rightDeviceIndex == nil {
            return deviceIndex == 0 ? .left : .right
        }
        return nil
    }

    private func mergeStatusSnapshot(from delegate: any EngineActorPhase2Delegate) async -> RuntimeStatusSnapshot {
        let delegateStatus = await delegate.statusSnapshot()
        return RuntimeStatusSnapshot(
            intentBySide: delegateStatus.intentBySide,
            contactCountBySide: delegateStatus.contactCountBySide,
            typingEnabled: delegateStatus.typingEnabled,
            keyboardModeEnabled: delegateStatus.keyboardModeEnabled,
            diagnostics: RuntimeDiagnosticsCounters(
                captureFrames: latestStatus.diagnostics.captureFrames,
                dispatchQueueDepth: delegateStatus.diagnostics.dispatchQueueDepth,
                dispatchDrops: delegateStatus.diagnostics.dispatchDrops
            )
        )
    }
}

actor EngineActorStub: EngineActorBoundary {
    private let impl = EngineActorPhase2()

    func ingest(_ frame: RuntimeRawFrame) async {
        await impl.ingest(frame)
    }

    func renderSnapshot() async -> RuntimeRenderSnapshot {
        await impl.renderSnapshot()
    }

    func statusSnapshot() async -> RuntimeStatusSnapshot {
        await impl.statusSnapshot()
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
