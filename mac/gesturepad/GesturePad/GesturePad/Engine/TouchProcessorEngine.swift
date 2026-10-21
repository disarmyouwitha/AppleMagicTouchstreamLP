import Carbon
import Dispatch
import CoreGraphics
import Darwin
import Foundation
import OpenMultitouchSupport
import QuartzCore
import os

/// All recognition deadlines use this boundary, including repeats and typing grace.
/// Implementations run scheduled work on the engine's serial owner.
protocol TouchEngineScheduler: AnyObject, Sendable {
    var now: TimeInterval { get }
    var uptimeNanoseconds: UInt64 { get }
    func schedule(after delay: TimeInterval, _ action: @escaping @Sendable () -> Void)
}

final class LiveTouchEngineScheduler: TouchEngineScheduler, @unchecked Sendable {
    private let queue: DispatchQueue
    init(queue: DispatchQueue) { self.queue = queue }
    var now: TimeInterval { CACurrentMediaTime() }
    var uptimeNanoseconds: UInt64 { DispatchTime.now().uptimeNanoseconds }
    func schedule(after delay: TimeInterval, _ action: @escaping @Sendable () -> Void) {
        queue.asyncAfter(deadline: .now() + max(0, delay), execute: action)
    }
}

/// Virtual time for offline recognition. Equal deadlines retain insertion order.
/// The harness must call this and the engine from one serial owner.
final class ReplayTouchEngineScheduler: TouchEngineScheduler, @unchecked Sendable {
    private struct Deadline {
        let time: TimeInterval
        let ordinal: UInt64
        let action: @Sendable () -> Void
    }
    private var deadlines: [Deadline] = []
    private var nextOrdinal: UInt64 = 0
    private(set) var now: TimeInterval
    var uptimeNanoseconds: UInt64 { UInt64(max(0, now * 1_000_000_000).rounded()) }

    init(startTime: TimeInterval = 0) { now = startTime }

    func schedule(after delay: TimeInterval, _ action: @escaping @Sendable () -> Void) {
        nextOrdinal &+= 1
        deadlines.append(Deadline(time: now + max(0, delay), ordinal: nextOrdinal, action: action))
    }

    func advance(to time: TimeInterval) {
        precondition(time.isFinite && time >= now, "Replay time must be finite and monotonic")
        while let next = deadlines.indices.min(by: {
            let lhs = deadlines[$0], rhs = deadlines[$1]
            return lhs.time == rhs.time ? lhs.ordinal < rhs.ordinal : lhs.time < rhs.time
        }), deadlines[next].time <= time {
            let deadline = deadlines.remove(at: next)
            now = deadline.time
            deadline.action()
        }
        now = time
    }
}

/// Raw-contact playground. No GTK recognizers, chords, key layout, or output actions.
/// Add FingerWorks recognition here; live input and replay share processContacts.
final class TouchProcessorEngine: @unchecked Sendable {
    typealias KeyBinding = ContentViewModel.KeyBinding
    typealias Layout = ContentViewModel.Layout
    typealias IntentDisplay = ContentViewModel.IntentDisplay
    private let dispatchService: PassiveOutputBoundary
    private let onContactCountChanged: @Sendable (SidePair<Int>) -> Void
    private let onIntentStateChanged: @Sendable (SidePair<IntentDisplay>) -> Void
    private var isListening = false
    private var diagnosticsEnabled = false
    private var leftSource = RuntimeSelectedDeviceSource()
    private var rightSource = RuntimeSelectedDeviceSource()
    private var counts = SidePair(left: 0, right: 0)

    init(
        executionQueue: DispatchQueue,
        dispatchService: PassiveOutputBoundary,
        scheduler: (any TouchEngineScheduler)? = nil,
        voiceSessionChanged: @Sendable @escaping (Bool) -> Void = { _ in },
        onTypingEnabledChanged: @Sendable @escaping (Bool) -> Void,
        onActiveLayerChanged: @Sendable @escaping (Int) -> Void,
        onDebugBindingDetected: @Sendable @escaping (KeyBinding) -> Void,
        onContactCountChanged: @Sendable @escaping (SidePair<Int>) -> Void,
        onIntentStateChanged: @Sendable @escaping (SidePair<IntentDisplay>) -> Void,
        onVoiceGestureChanged: @Sendable @escaping (Bool) -> Void
    ) {
        self.dispatchService = dispatchService
        self.onContactCountChanged = onContactCountChanged
        self.onIntentStateChanged = onIntentStateChanged
    }

    func setListening(_ isListening: Bool) {
        self.isListening = isListening
    }

    func setCaptureFrameDiagnosticsEnabled(_ enabled: Bool) {
        diagnosticsEnabled = enabled
    }

    func updateActiveDevices(
        leftIndex: Int?,
        rightIndex: Int?,
        leftDeviceID: String?,
        rightDeviceID: String?
    ) {
        leftSource = RuntimeSelectedDeviceSource(id: leftDeviceID, index: leftIndex)
        rightSource = RuntimeSelectedDeviceSource(id: rightDeviceID, index: rightIndex)
        counts = SidePair(left: 0, right: 0)
        onContactCountChanged(counts)
    }

    func updateLayouts(
        leftLayout: Layout,
        rightLayout: Layout,
        leftLabels: [[String]],
        rightLabels: [[String]],
        trackpadSize: CGSize,
        trackpadWidthMm: CGFloat
    ) {
        // Legacy capture/profile command retained for file compatibility only.
    }

    func updateCustomButtons(_ buttons: [CustomButton]) {
        // Legacy capture/profile command retained for file compatibility only.
    }

    func updateKeyMappings(_ actions: LayeredKeyMappings) {
        // Legacy capture/profile command retained for file compatibility only.
    }

    func setKeymapEditingEnabled(_ enabled: Bool) {
        // Legacy capture/profile command retained for file compatibility only.
    }

    func setPersistentLayer(_ layer: Int) {
        // Legacy capture/profile command retained for file compatibility only.
    }

    func updateHoldThreshold(_ seconds: TimeInterval) {
        // Legacy capture/profile command retained for file compatibility only.
    }

    func updateDragCancelDistance(_ distance: CGFloat) {
        // Legacy capture/profile command retained for file compatibility only.
    }

    func updateTypingGrace(_ milliseconds: Double) {
        // Legacy capture/profile command retained for file compatibility only.
    }

    func updateIntentMoveThreshold(_ millimeters: Double) {
        // Legacy capture/profile command retained for file compatibility only.
    }

    func updateIntentVelocityThreshold(_ millimetersPerSecond: Double) {
        // Legacy capture/profile command retained for file compatibility only.
    }

    func updateAllowMouseTakeover(_ enabled: Bool) {
        // Legacy capture/profile command retained for file compatibility only.
    }

    func updateForceClickMin(_ grams: Double) {
        // Legacy capture/profile command retained for file compatibility only.
    }

    func updateForceClickCap(_ grams: Double) {
        // Legacy capture/profile command retained for file compatibility only.
    }

    func updateForceClickThreshold(_ grams: Double) {
        // Legacy capture/profile command retained for file compatibility only.
    }

    func updateHapticStrength(_ normalized: Double) {
        // Legacy capture/profile command retained for file compatibility only.
    }

    func updateSnapRadiusPercent(_ percent: Double) {
        // Legacy capture/profile command retained for file compatibility only.
    }

    func updateTapClickCadence(_ milliseconds: Double) {
        // Legacy capture/profile command retained for file compatibility only.
    }

    func updateGestureActions(_ actions: GestureActionSet) {
        // Legacy capture/profile command retained for file compatibility only.
    }

    func updateGestureRepeatCadenceMsById(_ cadenceById: [String: Int]?) {
        // Legacy capture/profile command retained for file compatibility only.
    }

    func updateKeyboardModeEnabled(_ enabled: Bool) {
        // Legacy capture/profile command retained for file compatibility only.
    }

    func updateHoldRepeatEnabled(_ enabled: Bool) {
        // Legacy capture/profile command retained for file compatibility only.
    }

    func processRawFrame(_ frame: OMSRawTouchFrame) -> RuntimeFrameDiagnostic? {
        processContacts(frame.touches, deviceID: frame.deviceIDNumeric, deviceIndex: frame.deviceIndex,
            sequence: frame.sequence, timestamp: frame.timestamp)
    }

    func processRuntimeRawFrame(_ frame: RuntimeRawFrame) -> RuntimeFrameDiagnostic? {
        processContacts(frame.rawTouches, deviceID: frame.deviceNumericID, deviceIndex: frame.deviceIndex,
            sequence: frame.sequence, timestamp: frame.timestamp)
    }

    func resetState(stopVoiceDictation: Bool = false) {
        dispatchService.clearQueue()
        counts = SidePair(left: 0, right: 0)
        onContactCountChanged(counts)
        onIntentStateChanged(SidePair(left: .idle, right: .idle))
    }

    func clearVisualCaches() {
        // Legacy capture/profile command retained for file compatibility only.
    }

    private func processContacts<Touches: RandomAccessCollection>(
        _ touches: Touches, deviceID: UInt64, deviceIndex: Int, sequence: UInt64, timestamp: TimeInterval
    ) -> RuntimeFrameDiagnostic? where Touches.Element == OMSRawTouch {
        guard isListening else { return nil }
        let side: TrackpadSide
        if leftSource.matches(numericID: deviceID, index: deviceIndex) { side = .left }
        else if rightSource.matches(numericID: deviceID, index: deviceIndex) { side = .right }
        else { return nil }
        let count = touches.reduce(0) { count, touch in
            switch touch.state {
            case .starting, .making, .touching: count + 1
            default: count
            }
        }
        if counts[side] != count {
            counts[side] = count
            onContactCountChanged(counts)
        }
        guard diagnosticsEnabled else { return nil }
        return RuntimeFrameDiagnostic(sequence: sequence, timestamp: timestamp,
            deviceIndex: deviceIndex, activeLayer: 0, leftIntent: "idle", rightIntent: "idle",
            ingress: nil, touches: touches.map { touch in
                RuntimeTouchDiagnostic(id: touch.id, state: String(describing: touch.state),
                    side: side == .left ? "left" : "right", x: Double(touch.posX),
                    y: Double(touch.posY), pressure: Double(touch.pressure), phase: .none,
                    decision: .none, reason: nil, target: nil, armed: false,
                    dwellMilliseconds: nil, maxDistance: nil, forceThresholdSatisfied: false)
            })
    }
}
