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

final class TouchProcessorEngine: @unchecked Sendable {
    typealias KeyBinding = ContentViewModel.KeyBinding
    typealias KeyBindingAction = ContentViewModel.KeyBindingAction
    typealias Layout = ContentViewModel.Layout
    typealias IntentDisplay = ContentViewModel.IntentDisplay
    private enum ModifierKey {
        case shift
        case control
        case option
        case rightOption
        case command
    }

    private enum DisqualifyReason: String {
        case dragCancelled
        case pendingDragCancelled
        case leftContinuousRect
        case leftKeyRect
        case pendingLeftRect
        case typingDisabled
        case intentMouse
        case offKeyNoSnap
        case momentaryLayerCancelled
    }

    private enum DispatchKind: String {
        case tap
        case hold
        case continuous
    }

    private struct DispatchInfo {
        let kind: DispatchKind
        let durationMs: Int?
        let maxDistance: CGFloat?
    }

    private struct FrameDecisionRecord {
        var outcome: RuntimeTouchDecisionOutcome
        var reason: String?
        var target: RuntimeTouchTargetSnapshot?
    }

    private typealias TouchKey = UInt64

    private enum IntentMode {
        case idle
        case keyCandidate(start: TimeInterval, touchKey: TouchKey, centroid: CGPoint)
        case typingCommitted(untilAllUp: Bool)
        case mouseCandidate(start: TimeInterval)
        case mouseActive
        case gestureCandidate(start: TimeInterval)
    }

    private static func makeTouchKey(deviceIndex: Int, id: Int32) -> TouchKey {
        let deviceBits = UInt64(UInt32(deviceIndex))
        let idBits = UInt64(UInt32(bitPattern: id))
        return (deviceBits << 32) | idBits
    }

    private static func touchKeyDeviceIndex(_ key: TouchKey) -> Int {
        Int(UInt32(key >> 32))
    }

    private static func touchKeyID(_ key: TouchKey) -> Int32 {
        Int32(bitPattern: UInt32(truncatingIfNeeded: key))
    }

    private static func touchIDKey(from touchKey: TouchKey) -> TouchKey {
        TouchKey(UInt64(UInt32(bitPattern: touchKeyID(touchKey))))
    }

    private func touchKeySide(_ key: TouchKey) -> TrackpadSide? {
        let deviceIndex = Self.touchKeyDeviceIndex(key)
        if leftDeviceIndex == deviceIndex {
            return .left
        }
        if rightDeviceIndex == deviceIndex {
            return .right
        }
        return nil
    }


    private struct IntentConfig {
        var keyBufferSeconds: TimeInterval = 0.02
        var typingGraceSeconds: TimeInterval = 0.12
        var moveThresholdMm: CGFloat = 3.0
        var velocityThresholdMmPerSec: CGFloat = 50.0
    }

    private struct IntentTouchInfo {
        let startPoint: CGPoint
        let startTime: TimeInterval
        var lastPoint: CGPoint
        var lastTime: TimeInterval
        var maxDistanceSquared: CGFloat
    }

    private struct ActiveTouch {
        let binding: KeyBinding
        let layer: Int
        let startTime: TimeInterval
        let startPoint: CGPoint
        let modifierKey: ModifierKey?
        let isContinuousKey: Bool
        let holdBinding: KeyBinding?
        var didHold: Bool
        var holdRepeatActive: Bool = false
        var maxDistanceSquared: CGFloat
        var modifierEngaged: Bool

    }
    private struct PendingTouch {
        let binding: KeyBinding
        let layer: Int
        let startTime: TimeInterval
        let startPoint: CGPoint
        var maxDistanceSquared: CGFloat

    }

    private struct RepeatEntry {
        let token: RepeatToken
        let interval: UInt64
        var nextFire: UInt64
        let fire: @Sendable (RepeatToken) -> Void
        let stop: @Sendable () -> Void
    }

    private struct GestureRepeatKey: Hashable {
        let bindingId: String
        let side: TrackpadSide?
    }

    private enum RepeatOwner: Hashable {
        case touch(TouchKey)
        case gesture(GestureRepeatKey)
    }

    private enum TouchState {
        case pending(PendingTouch)
        case active(ActiveTouch)
    }

    private struct TouchTable<Value> {
        private enum SlotState: UInt8 {
            case empty = 0
            case occupied = 1
            case tombstone = 2
        }

        private var keys: [TouchKey]
        private var values: [Value?]
        private var states: [SlotState]
        private(set) var count: Int
        private var tombstones: Int

        init(minimumCapacity: Int = 16) {
            let capacity = max(16, TouchTable.nextPowerOfTwo(minimumCapacity))
            keys = Array(repeating: 0, count: capacity)
            values = Array(repeating: nil, count: capacity)
            states = Array(repeating: .empty, count: capacity)
            count = 0
            tombstones = 0
        }

        var isEmpty: Bool { count == 0 }

        mutating func removeAll(keepingCapacity: Bool = true) {
            if keepingCapacity {
                for index in states.indices {
                    states[index] = .empty
                    values[index] = nil
                }
                count = 0
                tombstones = 0
            } else {
                self = TouchTable(minimumCapacity: 16)
            }
        }

        func value(for key: TouchKey) -> Value? {
            guard let index = findIndex(for: key) else { return nil }
            return values[index]
        }

        mutating func set(_ key: TouchKey, _ value: Value) {
            ensureCapacity(for: count + 1)
            let capacityMask = keys.count - 1
            var index = TouchTable.hashIndex(for: key, mask: capacityMask)
            var firstTombstone: Int?
            while true {
                switch states[index] {
                case .empty:
                    let insertIndex = firstTombstone ?? index
                    keys[insertIndex] = key
                    values[insertIndex] = value
                    states[insertIndex] = .occupied
                    count += 1
                    if firstTombstone != nil {
                        tombstones -= 1
                    }
                    return
                case .occupied:
                    if keys[index] == key {
                        values[index] = value
                        return
                    }
                case .tombstone:
                    if firstTombstone == nil {
                        firstTombstone = index
                    }
                }
                index = (index + 1) & capacityMask
            }
        }

        @discardableResult
        mutating func remove(_ key: TouchKey) -> Value? {
            guard let index = findIndex(for: key) else { return nil }
            let value = values[index]
            values[index] = nil
            states[index] = .tombstone
            count -= 1
            tombstones += 1
            return value
        }

        func forEach(_ body: (TouchKey, Value) -> Void) {
            for index in states.indices where states[index] == .occupied {
                if let value = values[index] {
                    body(keys[index], value)
                }
            }
        }

        private mutating func ensureCapacity(for desiredCount: Int) {
            let capacity = keys.count
            if desiredCount * 2 < capacity && (desiredCount + tombstones) * 2 < capacity {
                return
            }
            rehash(to: capacity * 2)
        }

        private mutating func rehash(to newCapacity: Int) {
            var newTable = TouchTable(minimumCapacity: newCapacity)
            for index in states.indices where states[index] == .occupied {
                if let value = values[index] {
                    newTable.set(keys[index], value)
                }
            }
            self = newTable
        }

        private func findIndex(for key: TouchKey) -> Int? {
            let capacityMask = keys.count - 1
            var index = TouchTable.hashIndex(for: key, mask: capacityMask)
            while true {
                switch states[index] {
                case .empty:
                    return nil
                case .occupied:
                    if keys[index] == key {
                        return index
                    }
                case .tombstone:
                    break
                }
                index = (index + 1) & capacityMask
            }
        }

        private static func nextPowerOfTwo(_ value: Int) -> Int {
            var result = 1
            while result < value {
                result <<= 1
            }
            return result
        }

        private static func hashIndex(for key: TouchKey, mask: Int) -> Int {
            var x = key
            x ^= x >> 33
            x &*= 0xff51afd7ed558ccd
            x ^= x >> 33
            x &*= 0xc4ceb9fe1a85ec53
            x ^= x >> 33
            return Int(truncatingIfNeeded: x) & mask
        }
    }

    private struct MomentaryLayerTouches {
        private var table0 = TouchTable<Int>(minimumCapacity: 8)
        private var table1 = TouchTable<Int>(minimumCapacity: 8)

        var isEmpty: Bool { table0.isEmpty && table1.isEmpty }

        mutating func removeAll() {
            table0.removeAll()
            table1.removeAll()
        }

        func value(for touchKey: TouchKey) -> Int? {
            guard let tableIndex = tableIndex(for: touchKey) else { return nil }
            let idKey = TouchProcessorEngine.touchIDKey(from: touchKey)
            switch tableIndex {
            case 0:
                return table0.value(for: idKey)
            case 1:
                return table1.value(for: idKey)
            default:
                return nil
            }
        }

        mutating func set(_ touchKey: TouchKey, _ layer: Int) {
            guard let tableIndex = tableIndex(for: touchKey) else { return }
            let idKey = TouchProcessorEngine.touchIDKey(from: touchKey)
            switch tableIndex {
            case 0:
                table0.set(idKey, layer)
            case 1:
                table1.set(idKey, layer)
            default:
                break
            }
        }

        @discardableResult
        mutating func remove(_ touchKey: TouchKey) -> Int? {
            guard let tableIndex = tableIndex(for: touchKey) else { return nil }
            let idKey = TouchProcessorEngine.touchIDKey(from: touchKey)
            switch tableIndex {
            case 0:
                return table0.remove(idKey)
            case 1:
                return table1.remove(idKey)
            default:
                return nil
            }
        }

        func forEachLayer(_ body: (Int) -> Void) {
            table0.forEach { _, layer in
                body(layer)
            }
            table1.forEach { _, layer in
                body(layer)
            }
        }

        private func tableIndex(for touchKey: TouchKey) -> Int? {
            let deviceIndex = TouchProcessorEngine.touchKeyDeviceIndex(touchKey)
            switch deviceIndex {
            case 0, 1:
                return deviceIndex
            default:
                return nil
            }
        }
    }

    private struct BindingGrid {
        private let rows: Int
        private let cols: Int
        private let canvasSize: CGSize
        private let invWidth: CGFloat
        private let invHeight: CGFloat
        private var buckets: [[[KeyBinding]]]

        init(canvasSize: CGSize, rows: Int, cols: Int) {
            self.canvasSize = canvasSize
            self.rows = max(1, rows)
            self.cols = max(1, cols)
            self.invWidth = canvasSize.width > 0 ? 1.0 / canvasSize.width : 0
            self.invHeight = canvasSize.height > 0 ? 1.0 / canvasSize.height : 0
            var filledBuckets: [[[KeyBinding]]] = []
            filledBuckets.reserveCapacity(self.rows)
            for _ in 0..<self.rows {
                var rowBuckets: [[KeyBinding]] = []
                rowBuckets.reserveCapacity(self.cols)
                for _ in 0..<self.cols {
                    rowBuckets.append([])
                }
                filledBuckets.append(rowBuckets)
            }
            self.buckets = filledBuckets
        }

        mutating func insert(_ binding: KeyBinding) {
            let range = bucketRange(for: binding.rect)
            for row in range.rowRange {
                for col in range.colRange {
                    buckets[row][col].append(binding)
                }
            }
        }

        func binding(at point: CGPoint) -> KeyBinding? {
            let row = bucketIndex(for: normalize(point.y, invAxisSize: invHeight), count: rows)
            let col = bucketIndex(for: normalize(point.x, invAxisSize: invWidth), count: cols)
            var bestBinding: KeyBinding?
            var bestScore: CGFloat = -1
            var bestArea: CGFloat = .greatestFiniteMagnitude
            for binding in buckets[row][col] {
                guard binding.hitGeometry.contains(point) else { continue }
                let score = binding.hitGeometry.distanceToEdge(from: point)
                let area = binding.hitGeometry.area
                if score > bestScore || (score == bestScore && area < bestArea) {
                    bestBinding = binding
                    bestScore = score
                    bestArea = area
                }
            }
            return bestBinding
        }

        func binding(atNormalizedPoint point: CGPoint) -> KeyBinding? {
            let clampedPoint = CGPoint(
                x: min(max(point.x, 0), 1),
                y: min(max(point.y, 0), 1)
            )
            let row = bucketIndex(for: clampedPoint.y, count: rows)
            let col = bucketIndex(for: clampedPoint.x, count: cols)
            var bestBinding: KeyBinding?
            var bestScore: CGFloat = -1
            var bestArea: CGFloat = .greatestFiniteMagnitude
            for binding in buckets[row][col] {
                guard binding.normalizedHitGeometry.contains(clampedPoint) else { continue }
                let score = binding.normalizedHitGeometry.distanceToEdge(from: clampedPoint)
                let area = binding.normalizedHitGeometry.area
                if score > bestScore || (score == bestScore && area < bestArea) {
                    bestBinding = binding
                    bestScore = score
                    bestArea = area
                }
            }
            return bestBinding
        }

        private func bucketRange(for rect: CGRect) -> (rowRange: ClosedRange<Int>, colRange: ClosedRange<Int>) {
            let minX = normalize(rect.minX, invAxisSize: invWidth)
            let maxX = normalize(rect.maxX, invAxisSize: invWidth)
            let minY = normalize(rect.minY, invAxisSize: invHeight)
            let maxY = normalize(rect.maxY, invAxisSize: invHeight)
            let startCol = bucketIndex(for: minX, count: cols)
            let endCol = bucketIndex(for: maxX, count: cols)
            let startRow = bucketIndex(for: minY, count: rows)
            let endRow = bucketIndex(for: maxY, count: rows)
            return (
                rowRange: min(startRow, endRow)...max(startRow, endRow),
                colRange: min(startCol, endCol)...max(startCol, endCol)
            )
        }

        private func bucketIndex(for normalizedValue: CGFloat, count: Int) -> Int {
            guard count > 0 else { return 0 }
            let clamped = min(max(normalizedValue, 0), 1)
            let index = Int(clamped * CGFloat(count))
            return index >= count ? count - 1 : index
        }

        @inline(__always)
        private func normalize(_ coordinate: CGFloat, invAxisSize: CGFloat) -> CGFloat {
            return min(max(coordinate * invAxisSize, 0), 1)
        }
    }

    private struct BindingIndex {
        let keyGrid: BindingGrid
        let customGrid: BindingGrid?
        let customBindings: [KeyBinding]
        let snapBindings: [KeyBinding]
        let snapCentersX: [Float]
        let snapCentersY: [Float]
        let snapRadiusSq: [Float]
    }

    private let scheduler: any TouchEngineScheduler
    private let voiceSessionChanged: @Sendable (Bool) -> Void
    private let dispatchService: DispatchService
    private let onTypingEnabledChanged: @Sendable (Bool) -> Void
    private let onActiveLayerChanged: @Sendable (Int) -> Void
    private let onDebugBindingDetected: @Sendable (KeyBinding) -> Void
    private let onContactCountChanged: @Sendable (SidePair<Int>) -> Void
    private let onIntentStateChanged: @Sendable (SidePair<IntentDisplay>) -> Void
    private let onVoiceGestureChanged: @Sendable (Bool) -> Void
    private var isListening = false
    private var keymapEditingEnabled = false
    private var isTypingEnabled = false
    private var keyboardModeEnabled = false
    private var holdRepeatEnabled = false
    private var gestureRepeatCadenceMsById: [String: Int] = [:]
    private var activeLayer: Int = 0
    private var persistentLayer: Int = 0
    private var leftDeviceIndex: Int?
    private var rightDeviceIndex: Int?
    private var leftDeviceID: String?
    private var rightDeviceID: String?
    private var customButtons: [CustomButton] = []
    private var customButtonsByLayerAndSide: [Int: [TrackpadSide: [CustomButton]]] = [:]
    private var customKeyMappingsByLayer: LayeredKeyMappings = [:]
    private var touchStates = TouchTable<TouchState>()
    private var disqualifiedTouches = TouchTable<Bool>()
    private var releaseHandledTouches = TouchTable<Bool>()
    private var leftShiftTouchCount = 0
    private var controlTouchCount = 0
    private var leftOptionTouchCount = 0
    private var rightOptionTouchCount = 0
    private var commandTouchCount = 0
    private var repeatEntries: [RepeatOwner: RepeatEntry] = [:]
    // Dictionary enumeration must not determine the order of simultaneous output.
    private var repeatOrder: [RepeatOwner] = []
    private var repeatLoopGeneration: UInt64 = 0
    private var repeatLoopScheduled = false
    private var toggleTouchStarts = TouchTable<TimeInterval>()
    private var layerToggleTouchStarts = TouchTable<Int>()
    private var momentaryLayerTouches = MomentaryLayerTouches()
    private var lastMomentaryLayer: Int?
    private var touchInitialContactPoint = TouchTable<CGPoint>()
    private var tapMaxDuration: TimeInterval = 0.2
    private var holdMinDuration: TimeInterval = 0.2
    private let minimumTapMaxDuration: TimeInterval = 0.2
    private var dragCancelDistance: CGFloat = 2.5
    private let clickActuationForce: Float = 125
    private var forceClickMin: Float = 0
    private var forceClickCap: Float = 255
    private var forceClickThreshold: Float = Float(GlassToKeySettings.forceClickThreshold)
    private var snapRadiusFraction: Float = 0.35
#if DEBUG
    nonisolated(unsafe) private static var snapAttemptCount: Int64 = 0
    nonisolated(unsafe) private static var snapAcceptedCount: Int64 = 0
    nonisolated(unsafe) private static var snapRejectedCount: Int64 = 0
    nonisolated(unsafe) private static var snapOffKeyCount: Int64 = 0
#endif
    private var contactFingerCountsBySide = SidePair(left: 0, right: 0)
    private var lastReportedContactCounts = SidePair(left: -1, right: -1)

    private let contactCountHoldDuration: TimeInterval = 0.06
    private let holdGestureMoveCancelMm: CGFloat = 1.0
    private let repeatInterval: UInt64 = 50_000_000
    private let spaceRepeatMultiplier: UInt64 = 2
    private var leftLayout: Layout?
    private var rightLayout: Layout?
    private var leftLabels: [[String]] = []
    private var rightLabels: [[String]] = []
    private var trackpadSize: CGSize = .zero
    private var trackpadWidthMm: CGFloat = 1.0
    private var bindingsCache = SidePair<BindingIndex?>(left: nil, right: nil)
    private var bindingsCacheLayer: Int = -1
    private var bindingsGeneration = 0
    private var bindingsGenerationBySide = SidePair(left: -1, right: -1)
    private var bindingCacheBySide = SidePair(
        left: TouchTable<KeyBinding>(minimumCapacity: 16),
        right: TouchTable<KeyBinding>(minimumCapacity: 16)
    )
    private var framePointCache = TouchTable<CGPoint>(minimumCapacity: 16)
    private var peakPressureByTouch = TouchTable<Float>(minimumCapacity: 32)
    private var lastFourPlusContactTime = SidePair(left: TimeInterval(-1), right: TimeInterval(-1))
    private var lastFivePlusContactTime = SidePair(left: TimeInterval(-1), right: TimeInterval(-1))
    private var hapticStrength: Double = 0
    private static let hapticMinIntervalNanos: UInt64 = 20_000_000
    private var lastHapticTimeBySide = SidePair<UInt64>(repeating: 0)
    private struct IntentState {
        var mode: IntentMode = .idle
        var touches = TouchTable<IntentTouchInfo>()
        var lastContactCount = 0
    }

    private var intentState = IntentState()
    private var intentDisplayBySide = SidePair(left: IntentDisplay.idle, right: .idle)
    private var intentConfig = IntentConfig()
    private var currentProcessingTimestamp: TimeInterval?
    private var currentProcessingSequence: UInt64?
    private var captureFrameDiagnosticsEnabled = false
    private var currentFrameDecisions: [TouchKey: FrameDecisionRecord] = [:]
    private var intentCurrentKeys = TouchTable<Bool>(minimumCapacity: 16)
    private var intentRemovalBuffer: [TouchKey] = []
    private var unitsPerMillimeter: CGFloat = 1.0
    private var intentMoveThresholdSquared: CGFloat = 0
    private var intentVelocityThreshold: CGFloat = 0
    private var allowMouseTakeoverDuringTyping = false
    private var typingGraceDeadline: TimeInterval?
    private var typingGraceGeneration: UInt64 = 0
    private var doubleTapDeadline: TimeInterval?
    private var awaitingSecondTap = false
    private var tapClickCadenceSeconds: TimeInterval = 0.28
    private struct TapCandidate {
        let deadline: TimeInterval
    }
    private enum GestureSlot: Hashable {
        case twoFingerTap
        case threeFingerTap
        case fourFingerHold
        case innerCornersHold
        case fiveFingerSwipeLeft
        case fiveFingerSwipeRight
    }
    private var twoFingerTapCandidate: TapCandidate?
    private var threeFingerTapCandidate: TapCandidate?
    private var twoFingerTapAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.twoFingerTapGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var threeFingerTapAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.threeFingerTapGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var twoFingerHoldAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.twoFingerHoldGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var threeFingerHoldAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.threeFingerHoldGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var fourFingerHoldAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.fourFingerHoldGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var outerCornersHoldAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.outerCornersHoldGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var innerCornersHoldAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.innerCornersHoldGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var leftEdgeUpAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.leftEdgeUpGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var leftEdgeDownAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.leftEdgeDownGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var rightEdgeUpAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.rightEdgeUpGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var rightEdgeDownAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.rightEdgeDownGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var topEdgeLeftAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.topEdgeLeftGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var topEdgeRightAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.topEdgeRightGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var bottomEdgeLeftAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.bottomEdgeLeftGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var bottomEdgeRightAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.bottomEdgeRightGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var threeFingerSwipeLeftAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.threeFingerSwipeLeftGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var threeFingerSwipeRightAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.threeFingerSwipeRightGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var threeFingerSwipeUpAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.threeFingerSwipeUpGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var threeFingerSwipeDownAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.threeFingerSwipeDownGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var fourFingerSwipeLeftAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.fourFingerSwipeLeftGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var fourFingerSwipeRightAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.fourFingerSwipeRightGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var fourFingerSwipeUpAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.fourFingerSwipeUpGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var fourFingerSwipeDownAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.fourFingerSwipeDownGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var fiveFingerSwipeLeftAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.fiveFingerSwipeLeftGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var fiveFingerSwipeRightAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.fiveFingerSwipeRightGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var fiveFingerSwipeUpAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.fiveFingerSwipeUpGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var fiveFingerSwipeDownAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.fiveFingerSwipeDownGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var topLeftCornerSwipeAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.topLeftCornerSwipeGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var topRightCornerSwipeAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.topRightCornerSwipeGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var bottomLeftCornerSwipeAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.bottomLeftCornerSwipeGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var bottomRightCornerSwipeAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.bottomRightCornerSwipeGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var topLeftTriangleAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.topLeftTriangleGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var topRightTriangleAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.topRightTriangleGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var bottomLeftTriangleAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.bottomLeftTriangleGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var bottomRightTriangleAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.bottomRightTriangleGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var upperLeftCornerClickAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.upperLeftCornerClickGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var upperRightCornerClickAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.upperRightCornerClickGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var lowerLeftCornerClickAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.lowerLeftCornerClickGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var lowerRightCornerClickAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.lowerRightCornerClickGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var threeFingerClickAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.threeFingerClickGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var fourFingerClickAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.fourFingerClickGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var topLeftForceClickAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.topLeftForceClickGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var topRightForceClickAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.topRightForceClickGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var bottomLeftForceClickAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.bottomLeftForceClickGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private var bottomRightForceClickAction: KeyAction = KeyActionCatalog.action(
        for: GlassToKeySettings.bottomRightForceClickGestureActionLabel
    ) ?? KeyActionCatalog.noneAction
    private struct DirectionalSwipeState {
        var active: Bool = false
        var triggered: Bool = false
        var startX: CGFloat = 0
        var startY: CGFloat = 0
        var repeatBindingId: String?
    }
    private enum SwipeDirection {
        case left
        case right
        case up
        case down
    }
    private enum EdgeGestureZone {
        case left
        case right
        case top
        case bottom
    }
    private enum CornerGestureZone {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }
    private struct EdgeSlideState {
        var active = false
        var candidateValid = false
        var zone: EdgeGestureZone = .left
        var startTime: TimeInterval = 0
        var startX: CGFloat = 0
        var startY: CGFloat = 0
        var lastX: CGFloat = 0
        var lastY: CGFloat = 0
        var minX: CGFloat = 0
        var maxX: CGFloat = 0
        var minY: CGFloat = 0
        var maxY: CGFloat = 0
        var repeatBindingId: String?
    }
    private struct CornerSwipeState {
        var active = false
        var candidateValid = false
        var corner: CornerGestureZone = .topLeft
        var startTime: TimeInterval = 0
        var startX: CGFloat = 0
        var startY: CGFloat = 0
        var peakX: CGFloat = 0
        var peakY: CGFloat = 0
        var lastX: CGFloat = 0
        var lastY: CGFloat = 0
        var repeatBindingId: String?
    }
    private struct TriangleGestureState {
        var active = false
        var candidateValid = false
        var corner: CornerGestureZone = .topLeft
        var startTime: TimeInterval = 0
        var startX: CGFloat = 0
        var startY: CGFloat = 0
        var peakX: CGFloat = 0
        var peakY: CGFloat = 0
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0
        var lastX: CGFloat = 0
        var lastY: CGFloat = 0
        var repeatBindingId: String?
    }
    private struct ThreeFingerTapState {
        var active = false
        var candidateValid = false
        var startTime: TimeInterval = 0
        var startX: CGFloat = 0
        var startY: CGFloat = 0
        var maxDistanceMm: CGFloat = 0
        var repeatBindingId: String?
    }
    private struct CornerClickState {
        var active = false
        var candidateValid = false
        var forceArmed = false
        var corner: CornerGestureZone = .topLeft
        var startTime: TimeInterval = 0
        var startX: CGFloat = 0
        var startY: CGFloat = 0
        var lastX: CGFloat = 0
        var lastY: CGFloat = 0
        var maxDistanceMm: CGFloat = 0
        var peakPressure: Float = 0
        var repeatBindingId: String?
    }
    private struct ForceClickState {
        var active = false
        var candidateValid = false
        var corner: CornerGestureZone?
        var startTime: TimeInterval = 0
        var startX: CGFloat = 0
        var startY: CGFloat = 0
        var lastX: CGFloat = 0
        var lastY: CGFloat = 0
        var maxDistanceMm: CGFloat = 0
        var peakPressure: Float = 0
        var triggered = false
        var repeatBindingId: String?
    }
    private struct MultiFingerClickState {
        var maxContactsSeen = 0
        var forceTriggeredForCurrentPress = false
        var repeatBindingId: String?
    }
    private var threeFingerSwipeState = SidePair(left: DirectionalSwipeState(), right: DirectionalSwipeState())
    private var fourFingerSwipeState = SidePair(left: DirectionalSwipeState(), right: DirectionalSwipeState())
    private var fiveFingerSwipeState = SidePair(left: DirectionalSwipeState(), right: DirectionalSwipeState())
    private var edgeSlideState = SidePair(left: EdgeSlideState(), right: EdgeSlideState())
    private var cornerSwipeState = SidePair(left: CornerSwipeState(), right: CornerSwipeState())
    private var triangleGestureState = SidePair(left: TriangleGestureState(), right: TriangleGestureState())
    private var threeFingerTapStateBySide = SidePair(left: ThreeFingerTapState(), right: ThreeFingerTapState())
    private var cornerClickState = SidePair(left: CornerClickState(), right: CornerClickState())
    private var forceClickState = SidePair(left: ForceClickState(), right: ForceClickState())
    private var multiFingerClickState = SidePair(left: MultiFingerClickState(), right: MultiFingerClickState())
    private let directionalSwipeThresholdMm: CGFloat = 10.0
    private let directionalSwipeAxisDominanceRatio: CGFloat = 1.2
    private let fourFingerDominanceSuppressSeconds: TimeInterval = 0.18
    private let fiveFingerDominanceSuppressSeconds: TimeInterval = 0.18
    private let edgeSlideStartThreshold: CGFloat = 0.045
    private let edgeSlideStayThreshold: CGFloat = 0.12
    private let edgeSlideTriggerDistanceMm: CGFloat = 24.0
    private let edgeSlideMaxLateralTravelMm: CGFloat = 10.0
    private let edgeSlideDirectionDominanceRatio: CGFloat = 2.0
    private let edgeSlideMaxDuration: TimeInterval = 2.5
    private let cornerSwipeStartThreshold: CGFloat = 0.12
    private let cornerSwipeTriggerDistanceMm: CGFloat = 24.0
    private let cornerSwipeAxisBalanceRatio: CGFloat = 2.4
    private let cornerSwipeMaxReverseTravelMm: CGFloat = 10.0
    private let cornerSwipeMaxDuration: TimeInterval = 2.0
    private let triangleStartThreshold: CGFloat = 0.12
    private let triangleFirstLegDxThreshold: CGFloat = 0.16
    private let triangleFirstLegDyThreshold: CGFloat = 0.22
    private let triangleReturnAxisThreshold: CGFloat = 0.14
    private let triangleTurnDotUpperBound: CGFloat = 0.35
    private let triangleMaxDuration: TimeInterval = 3.0
    private let threeFingerTapMaxDuration: TimeInterval = 0.22
    private let threeFingerTapMaxMovementMm: CGFloat = 1.6
    private let cornerClickZoneThreshold: CGFloat = 0.283
    private let cornerClickMaxDuration: TimeInterval = 2.0
    private let forceClickMaxDuration: TimeInterval = 2.0
    private struct MultiFingerHoldState {
        var active: Bool = false
        var triggered: Bool = false
        var startTime: TimeInterval = 0
        var startCentroid: CGPoint = .zero
        var blockedUntilAllUp: Bool = false
        var repeatBindingId: String?
    }

    private struct GestureContactSummary {
        var count: Int = 0
        var centroid: CGPoint = .zero
    }
    private enum CornerHoldGestureKind {
        case outer
        case inner
    }
    private struct VoiceDictationGestureState {
        var holdStart: TimeInterval = 0
        var holdCandidateActive = false
        var holdDidToggle = false
        var isDictating = false
        var side: TrackpadSide?
        var kind: CornerHoldGestureKind = .outer
        var repeatBindingId: String?
    }
    private var chordShiftActivationCount = SidePair(left: 0, right: 0)
    private var twoFingerHoldState = SidePair(left: MultiFingerHoldState(), right: MultiFingerHoldState())
    private var threeFingerHoldState = SidePair(left: MultiFingerHoldState(), right: MultiFingerHoldState())
    private var fourFingerHoldState = SidePair(left: MultiFingerHoldState(), right: MultiFingerHoldState())
    private var chordShiftLastContactTime = SidePair(left: TimeInterval(0), right: TimeInterval(0))
    private var chordShiftKeyDown = false
    private var voiceDictationGestureState = VoiceDictationGestureState()
    private var voiceGestureActive = false
    private let voiceDictationLeftEdgeMaxX: CGFloat = 0.28
    private let voiceDictationRightEdgeMinX: CGFloat = 0.72
    private let voiceDictationTopMaxY: CGFloat = 0.28
    private let voiceDictationBottomMinY: CGFloat = 0.72

#if DEBUG
    private let signposter = OSSignposter(
        subsystem: "ink.ranna.GlassToKey",
        category: "TouchProcessing"
    )
#endif

    init(
        executionQueue: DispatchQueue,
        dispatchService: DispatchService,
        scheduler: (any TouchEngineScheduler)? = nil,
        voiceSessionChanged: @Sendable @escaping (Bool) -> Void = { active in
            if active { VoiceDictationManager.shared.beginSession() }
            else { VoiceDictationManager.shared.endSession() }
        },
        onTypingEnabledChanged: @Sendable @escaping (Bool) -> Void,
        onActiveLayerChanged: @Sendable @escaping (Int) -> Void,
        onDebugBindingDetected: @Sendable @escaping (KeyBinding) -> Void,
        onContactCountChanged: @Sendable @escaping (SidePair<Int>) -> Void,
        onIntentStateChanged: @Sendable @escaping (SidePair<IntentDisplay>) -> Void,
        onVoiceGestureChanged: @Sendable @escaping (Bool) -> Void
    ) {
        self.scheduler = scheduler ?? LiveTouchEngineScheduler(queue: executionQueue)
        self.voiceSessionChanged = voiceSessionChanged
        self.dispatchService = dispatchService
        self.onTypingEnabledChanged = onTypingEnabledChanged
        self.onActiveLayerChanged = onActiveLayerChanged
        self.onDebugBindingDetected = onDebugBindingDetected
        self.onContactCountChanged = onContactCountChanged
        self.onIntentStateChanged = onIntentStateChanged
        self.onVoiceGestureChanged = onVoiceGestureChanged
    }

    func setListening(_ isListening: Bool) {
        self.isListening = isListening
        if !isListening {
            dispatchService.setThreeFingerHoldDragSuppression(false)
        }
    }

    func setCaptureFrameDiagnosticsEnabled(_ enabled: Bool) {
        captureFrameDiagnosticsEnabled = enabled
        if !enabled {
            currentProcessingSequence = nil
            currentFrameDecisions.removeAll(keepingCapacity: false)
        }
    }

    func updateActiveDevices(
        leftIndex: Int?,
        rightIndex: Int?,
        leftDeviceID: String?,
        rightDeviceID: String?
    ) {
        leftDeviceIndex = leftIndex
        rightDeviceIndex = rightIndex
        self.leftDeviceID = leftDeviceID
        self.rightDeviceID = rightDeviceID
    }

    func updateLayouts(
        leftLayout: Layout,
        rightLayout: Layout,
        leftLabels: [[String]],
        rightLabels: [[String]],
        trackpadSize: CGSize,
        trackpadWidthMm: CGFloat
    ) {
        self.trackpadSize = trackpadSize
        self.trackpadWidthMm = max(1, trackpadWidthMm)
        self.leftLayout = Layout(keyRects: [])
        self.rightLayout = Layout(keyRects: [])
        updateIntentThresholdCache()
    }

    func updateCustomButtons(_ buttons: [CustomButton]) {
        // Keyboard/custom-button surface removed.
    }

    func updateKeyMappings(_ actions: LayeredKeyMappings) {
        // Keyboard mappings removed.
    }

    func setKeymapEditingEnabled(_ enabled: Bool) {
        guard keymapEditingEnabled != enabled else { return }
        keymapEditingEnabled = enabled
    }

    func setPersistentLayer(_ layer: Int) {
        activeLayer = 0
    }

    func updateHoldThreshold(_ seconds: TimeInterval) {
        let clamped = max(0, seconds)
        holdMinDuration = clamped
        tapMaxDuration = max(clamped, minimumTapMaxDuration)
    }

    func updateDragCancelDistance(_ distance: CGFloat) {
        dragCancelDistance = max(0, distance)
    }

    func updateTypingGrace(_ milliseconds: Double) {
        let clampedMs = max(0, milliseconds)
        intentConfig.typingGraceSeconds = clampedMs / 1000.0
    }

    func updateIntentMoveThreshold(_ millimeters: Double) {
        intentConfig.moveThresholdMm = max(0, CGFloat(millimeters))
        updateIntentThresholdCache()
    }

    func updateIntentVelocityThreshold(_ millimetersPerSecond: Double) {
        intentConfig.velocityThresholdMmPerSec = max(0, CGFloat(millimetersPerSecond))
        updateIntentThresholdCache()
    }

    func updateAllowMouseTakeover(_ enabled: Bool) {
        allowMouseTakeoverDuringTyping = enabled
    }

    func updateForceClickMin(_ grams: Double) {
        let clamped = Float(min(max(grams, 0), 255))
        forceClickMin = clamped
        if forceClickCap < clamped {
            forceClickCap = clamped
        }
    }

    func updateForceClickCap(_ grams: Double) {
        let clamped = Float(min(max(grams, 0), 255))
        forceClickCap = max(clamped, forceClickMin)
    }

    func updateForceClickThreshold(_ grams: Double) {
        forceClickThreshold = Float(min(max(grams, 130), 500))
    }

    func updateHapticStrength(_ normalized: Double) {
        let clamped = min(max(normalized, 0.0), 1.0)
        hapticStrength = clamped
    }

    func updateSnapRadiusPercent(_ percent: Double) {
        let clamped = min(max(percent, 0.0), 100.0)
        snapRadiusFraction = Float(clamped / 100.0)
        invalidateBindingsCache()
    }

    func updateTapClickCadence(_ milliseconds: Double) {
        let clampedMs = min(max(milliseconds, 50.0), 1000.0)
        tapClickCadenceSeconds = clampedMs / 1000.0
        awaitingSecondTap = false
        doubleTapDeadline = nil
    }

    func updateGestureActions(_ actions: GestureActionSet) {
        stopAllGestureRepeats()
        twoFingerTapAction = actions.twoFingerTap
        threeFingerTapAction = actions.threeFingerTap
        twoFingerHoldAction = actions.twoFingerHold
        threeFingerHoldAction = actions.threeFingerHold
        fourFingerHoldAction = actions.fourFingerHold
        outerCornersHoldAction = actions.outerCornersHold
        innerCornersHoldAction = actions.innerCornersHold
        leftEdgeUpAction = actions.leftEdgeUp
        leftEdgeDownAction = actions.leftEdgeDown
        rightEdgeUpAction = actions.rightEdgeUp
        rightEdgeDownAction = actions.rightEdgeDown
        topEdgeLeftAction = actions.topEdgeLeft
        topEdgeRightAction = actions.topEdgeRight
        bottomEdgeLeftAction = actions.bottomEdgeLeft
        bottomEdgeRightAction = actions.bottomEdgeRight
        threeFingerSwipeLeftAction = actions.threeFingerSwipeLeft
        threeFingerSwipeRightAction = actions.threeFingerSwipeRight
        threeFingerSwipeUpAction = actions.threeFingerSwipeUp
        threeFingerSwipeDownAction = actions.threeFingerSwipeDown
        fourFingerSwipeLeftAction = actions.fourFingerSwipeLeft
        fourFingerSwipeRightAction = actions.fourFingerSwipeRight
        fourFingerSwipeUpAction = actions.fourFingerSwipeUp
        fourFingerSwipeDownAction = actions.fourFingerSwipeDown
        fiveFingerSwipeLeftAction = actions.fiveFingerSwipeLeft
        fiveFingerSwipeRightAction = actions.fiveFingerSwipeRight
        fiveFingerSwipeUpAction = actions.fiveFingerSwipeUp
        fiveFingerSwipeDownAction = actions.fiveFingerSwipeDown
        topLeftCornerSwipeAction = actions.topLeftCornerSwipe
        topRightCornerSwipeAction = actions.topRightCornerSwipe
        bottomLeftCornerSwipeAction = actions.bottomLeftCornerSwipe
        bottomRightCornerSwipeAction = actions.bottomRightCornerSwipe
        topLeftTriangleAction = actions.topLeftTriangle
        topRightTriangleAction = actions.topRightTriangle
        bottomLeftTriangleAction = actions.bottomLeftTriangle
        bottomRightTriangleAction = actions.bottomRightTriangle
        upperLeftCornerClickAction = actions.upperLeftCornerClick
        upperRightCornerClickAction = actions.upperRightCornerClick
        lowerLeftCornerClickAction = actions.lowerLeftCornerClick
        lowerRightCornerClickAction = actions.lowerRightCornerClick
        threeFingerClickAction = actions.threeFingerClick
        fourFingerClickAction = actions.fourFingerClick
        topLeftForceClickAction = actions.topLeftForceClick
        topRightForceClickAction = actions.topRightForceClick
        bottomLeftForceClickAction = actions.bottomLeftForceClick
        bottomRightForceClickAction = actions.bottomRightForceClick
        twoFingerHoldState[.left] = MultiFingerHoldState()
        twoFingerHoldState[.right] = MultiFingerHoldState()
        threeFingerHoldState[.left] = MultiFingerHoldState()
        threeFingerHoldState[.right] = MultiFingerHoldState()
        fourFingerHoldState[.left] = MultiFingerHoldState()
        fourFingerHoldState[.right] = MultiFingerHoldState()
        awaitingSecondTap = false
        doubleTapDeadline = nil
        chordShiftActivationCount[.left] = 0
        chordShiftActivationCount[.right] = 0
        chordShiftLastContactTime[.left] = 0
        chordShiftLastContactTime[.right] = 0
        lastFourPlusContactTime[.left] = -1
        lastFourPlusContactTime[.right] = -1
        lastFivePlusContactTime[.left] = -1
        lastFivePlusContactTime[.right] = -1
        threeFingerSwipeState[.left] = DirectionalSwipeState()
        threeFingerSwipeState[.right] = DirectionalSwipeState()
        fourFingerSwipeState[.left] = DirectionalSwipeState()
        fourFingerSwipeState[.right] = DirectionalSwipeState()
        fiveFingerSwipeState[.left] = DirectionalSwipeState()
        fiveFingerSwipeState[.right] = DirectionalSwipeState()
        edgeSlideState[.left] = EdgeSlideState()
        edgeSlideState[.right] = EdgeSlideState()
        cornerSwipeState[.left] = CornerSwipeState()
        cornerSwipeState[.right] = CornerSwipeState()
        triangleGestureState[.left] = TriangleGestureState()
        triangleGestureState[.right] = TriangleGestureState()
        threeFingerTapStateBySide[.left] = ThreeFingerTapState()
        threeFingerTapStateBySide[.right] = ThreeFingerTapState()
        cornerClickState[.left] = CornerClickState()
        cornerClickState[.right] = CornerClickState()
        forceClickState[.left] = ForceClickState()
        forceClickState[.right] = ForceClickState()
        multiFingerClickState[.left] = MultiFingerClickState()
        multiFingerClickState[.right] = MultiFingerClickState()
        updateChordShiftKeyState()
        updateThreeFingerHoldDragSuppression()
        if actions.outerCornersHold.kind != .voice, actions.innerCornersHold.kind != .voice {
            stopVoiceDictationGesture()
        }
    }

    func updateGestureRepeatCadenceMsById(_ cadenceById: [String: Int]?) {
        gestureRepeatCadenceMsById = GestureRepeatCadenceStorage.normalized(cadenceById) ?? [:]
        stopAllGestureRepeats()
    }

    func updateKeyboardModeEnabled(_ enabled: Bool) {
        keyboardModeEnabled = false
    }

    func updateHoldRepeatEnabled(_ enabled: Bool) {
        holdRepeatEnabled = enabled
    }

    private func beginFrameDiagnostics(sequence: UInt64) {
        guard captureFrameDiagnosticsEnabled else { return }
        currentProcessingSequence = sequence
        currentFrameDecisions.removeAll(keepingCapacity: true)
    }

    private func currentDispatchSourceSequence() -> UInt64? {
        guard captureFrameDiagnosticsEnabled else { return nil }
        return currentProcessingSequence
    }

    private func targetSnapshot(for binding: KeyBinding) -> RuntimeTouchTargetSnapshot {
        RuntimeTouchTargetSnapshot(
            label: binding.label,
            side: binding.side == .left ? "left" : "right",
            storageKey: binding.position?.storageKey,
            buttonID: binding.customButtonID?.uuidString,
            actionKind: captureActionKindLabel(binding.action),
            holdForceThreshold: Int(binding.holdForceThreshold.rounded()),
            isContinuousKey: isContinuousKey(binding)
        )
    }

    private func captureActionKindLabel(_ action: KeyBindingAction) -> String {
        switch action {
        case .key:
            return "key"
        case .appLaunch:
            return "appLaunch"
        case .leftClick:
            return "leftClick"
        case .doubleClick:
            return "doubleClick"
        case .rightClick:
            return "rightClick"
        case .middleClick:
            return "middleClick"
        case .volumeUp:
            return "volumeUp"
        case .volumeDown:
            return "volumeDown"
        case .volumeUpSmall:
            return "volumeUpSmall"
        case .volumeDownSmall:
            return "volumeDownSmall"
        case .brightnessUp:
            return "brightnessUp"
        case .brightnessDown:
            return "brightnessDown"
        case .brightnessUpSmall:
            return "brightnessUpSmall"
        case .brightnessDownSmall:
            return "brightnessDownSmall"
        case .voice:
            return "voice"
        case .typingToggle:
            return "typingToggle"
        case .chordalShift:
            return "chordalShift"
        case .gestureTwoFingerTap:
            return "gestureTwoFingerTap"
        case .gestureThreeFingerTap:
            return "gestureThreeFingerTap"
        case .gestureFourFingerHold:
            return "gestureFourFingerHold"
        case .gestureInnerCornersHold:
            return "gestureInnerCornersHold"
        case .gestureFiveFingerSwipeLeft:
            return "gestureFiveFingerSwipeLeft"
        case .gestureFiveFingerSwipeRight:
            return "gestureFiveFingerSwipeRight"
        case .layerMomentary:
            return "layerMomentary"
        case .layerToggle:
            return "layerToggle"
        case .none:
            return "none"
        }
    }

    private func recordFrameDecision(
        _ touchKey: TouchKey,
        outcome: RuntimeTouchDecisionOutcome,
        reason: String? = nil,
        binding: KeyBinding? = nil
    ) {
        guard captureFrameDiagnosticsEnabled else { return }
        let existing = currentFrameDecisions[touchKey]
        let target = binding.map(targetSnapshot(for:)) ?? existing?.target
        currentFrameDecisions[touchKey] = FrameDecisionRecord(
            outcome: outcome,
            reason: reason ?? existing?.reason,
            target: target
        )
    }

    private func binding(from state: TouchState?) -> KeyBinding? {
        guard let state else { return nil }
        switch state {
        case let .pending(pending):
            return pending.binding
        case let .active(active):
            return active.binding
        }
    }

    private func makeFrameDiagnostic<Touches: RandomAccessCollection>(
        deviceIndex: Int,
        touches: Touches,
        bindings: BindingIndex,
        now: TimeInterval
    ) -> RuntimeFrameDiagnostic? where Touches.Element == OMSRawTouch {
        guard captureFrameDiagnosticsEnabled, let sequence = currentProcessingSequence else { return nil }
        return RuntimeFrameDiagnostic(sequence: sequence, timestamp: now, deviceIndex: deviceIndex,
            activeLayer: 0, leftIntent: intentDisplayBySide.left.rawValue,
            rightIntent: intentDisplayBySide.right.rawValue, ingress: nil,
            touches: touches.map { touch in
                RuntimeTouchDiagnostic(id: touch.id, state: String(describing: touch.state),
                    side: leftDeviceIndex == deviceIndex ? "left" : "right",
                    x: Double(touch.posX), y: Double(touch.posY), pressure: Double(touch.pressure),
                    phase: .none, decision: .none, reason: nil, target: nil, armed: false,
                    dwellMilliseconds: nil, maxDistance: nil, forceThresholdSatisfied: false)
            })
    }

    func processRawFrame(_ frame: OMSRawTouchFrame) -> RuntimeFrameDiagnostic? {
        guard isListening,
              let leftLayout,
              let rightLayout else {
            return nil
        }
        if leftDeviceIndex == nil && rightDeviceIndex == nil {
            return nil
        }
        let now = frame.timestamp
        currentProcessingTimestamp = now
        beginFrameDiagnostics(sequence: frame.sequence)
        defer {
            currentProcessingSequence = nil
            currentProcessingTimestamp = nil
        }
        let touches = frame.touches
        let deviceIndex = frame.deviceIndex
        let isLeftDevice = leftDeviceIndex.map { $0 == deviceIndex } ?? false
        let isRightDevice = rightDeviceIndex.map { $0 == deviceIndex } ?? false
        let activeSide: TrackpadSide? = if isLeftDevice {
            .left
        } else if isRightDevice {
            .right
        } else {
            nil
        }
        let hasTouchData = !touches.isEmpty
        if let activeSide {
            if hasTouchData {
                updateSideGestures(for: activeSide, touches: touches, now: now)
            } else {
                resetGestureState(for: activeSide)
            }
            updateChordShiftKeyState()
        }
        let leftTouches = isLeftDevice ? touches : OMSRawTouchBufferView.empty
        let rightTouches = isRightDevice ? touches : OMSRawTouchBufferView.empty
        let empty = BindingIndex(keyGrid: BindingGrid(canvasSize: trackpadSize, rows: 1, cols: 1), customGrid: nil, customBindings: [], snapBindings: [], snapCentersX: [], snapCentersY: [], snapRadiusSq: [])
        _ = updateIntent(leftTouches: leftTouches, rightTouches: rightTouches,
            leftDeviceIndex: leftDeviceIndex, rightDeviceIndex: rightDeviceIndex,
            now: now, leftBindings: empty, rightBindings: empty)
        if let activeSide { contactFingerCountsBySide[activeSide] = touches.filter { Self.isContactState($0.state) }.count }
        notifyContactCounts()
        return makeFrameDiagnostic(
            deviceIndex: deviceIndex,
            touches: touches,
            bindings: empty,
            now: now
        )
    }

    func processRuntimeRawFrame(_ frame: RuntimeRawFrame) -> RuntimeFrameDiagnostic? {
        guard isListening,
              let leftLayout,
              let rightLayout else {
            return nil
        }
        if leftDeviceIndex == nil && rightDeviceIndex == nil {
            return nil
        }
        let now = frame.timestamp
        currentProcessingTimestamp = now
        beginFrameDiagnostics(sequence: frame.sequence)
        defer {
            currentProcessingSequence = nil
            currentProcessingTimestamp = nil
        }
        let touches = frame.rawTouches
        let deviceIndex = frame.deviceIndex
        let isLeftDevice = leftDeviceIndex.map { $0 == deviceIndex } ?? false
        let isRightDevice = rightDeviceIndex.map { $0 == deviceIndex } ?? false
        let activeSide: TrackpadSide? = if isLeftDevice {
            .left
        } else if isRightDevice {
            .right
        } else {
            nil
        }
        let hasTouchData = !touches.isEmpty
        if let activeSide {
            if hasTouchData {
                updateSideGestures(for: activeSide, touches: touches, now: now)
            } else {
                resetGestureState(for: activeSide)
            }
            updateChordShiftKeyState()
        }
        let leftTouches = isLeftDevice ? touches : []
        let rightTouches = isRightDevice ? touches : []
        let empty = BindingIndex(keyGrid: BindingGrid(canvasSize: trackpadSize, rows: 1, cols: 1), customGrid: nil, customBindings: [], snapBindings: [], snapCentersX: [], snapCentersY: [], snapRadiusSq: [])
        _ = updateIntent(leftTouches: leftTouches, rightTouches: rightTouches,
            leftDeviceIndex: leftDeviceIndex, rightDeviceIndex: rightDeviceIndex,
            now: now, leftBindings: empty, rightBindings: empty)
        if let activeSide { contactFingerCountsBySide[activeSide] = touches.filter { Self.isContactState($0.state) }.count }
        notifyContactCounts()
        return makeFrameDiagnostic(
            deviceIndex: deviceIndex,
            touches: touches,
            bindings: empty,
            now: now
        )
    }

    func resetState(stopVoiceDictation: Bool = false) {
        dispatchService.clearQueue()
        releaseHeldKeys(stopVoiceDictation: stopVoiceDictation)
        peakPressureByTouch.removeAll()
        contactFingerCountsBySide[.left] = 0
        contactFingerCountsBySide[.right] = 0
        notifyContactCounts()
    }

    private func forceRange() -> (min: Float, max: Float) {
        let minForce = min(forceClickMin, forceClickCap)
        let maxForce = max(forceClickMin, forceClickCap)
        return (min: minForce, max: maxForce)
    }

    private func isPressureWithinForceRange(_ pressure: Float) -> Bool {
        let range = forceRange()
        return pressure >= range.min && pressure <= range.max
    }

    private func holdAction(for position: GridKeyPosition?, label: String) -> KeyAction? {
        let layerMappings = customKeyMappingsByLayer[activeLayer] ?? [:]
        if let position, let mapping = layerMappings[position.storageKey] {
            return mapping.hold
        }
        return KeyActionCatalog.holdAction(for: label)
    }

    private func binding(at point: CGPoint, index: BindingIndex) -> KeyBinding? {
        if let binding = index.keyGrid.binding(at: point) {
            return binding
        }
        if let customGrid = index.customGrid {
            return customGrid.binding(at: point)
        }
        var bestBinding: KeyBinding?
        var bestScore: CGFloat = -1
        var bestArea: CGFloat = .greatestFiniteMagnitude
        for binding in index.customBindings {
            guard binding.hitGeometry.contains(point) else { continue }
            let score = binding.hitGeometry.distanceToEdge(from: point)
            let area = binding.hitGeometry.area
            if score > bestScore || (score == bestScore && area < bestArea) {
                bestBinding = binding
                bestScore = score
                bestArea = area
            }
        }
        return bestBinding
    }

    private var isSnapRadiusEnabled: Bool {
        snapRadiusFraction > 0
    }

    private static func isContactState(_ state: OMSState) -> Bool {
        switch state {
        case .starting, .making, .touching:
            return true
        default:
            return false
        }
    }

    private static func isIntentContactState(_ state: OMSState) -> Bool {
        switch state {
        case .starting, .making, .touching, .breaking, .leaving:
            return true
        default:
            return false
        }
    }

    private static func isChordShiftContactState(_ state: OMSState) -> Bool {
        switch state {
        case .starting, .making, .touching, .breaking, .leaving, .lingering:
            return true
        default:
            return false
        }
    }

    private static func isDictationContactState(_ state: OMSState) -> Bool {
        switch state {
        case .starting, .making, .touching, .lingering:
            return true
        default:
            return false
        }
    }

    private func gestureContactSummary<Touches: Sequence>(
        in touches: Touches
    ) -> GestureContactSummary where Touches.Element == OMSRawTouch {
        var count = 0
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        for touch in touches where Self.isChordShiftContactState(touch.state) {
            count += 1
            sumX += CGFloat(touch.posX) * trackpadSize.width
            sumY += CGFloat(1.0 - touch.posY) * trackpadSize.height
        }
        guard count > 0 else {
            return GestureContactSummary()
        }
        return GestureContactSummary(
            count: count,
            centroid: CGPoint(x: sumX / CGFloat(count), y: sumY / CGFloat(count))
        )
    }

    private func updateSideGestures<Touches: Sequence>(
        for side: TrackpadSide,
        touches: Touches,
        now: TimeInterval
    ) where Touches.Element == OMSRawTouch {
        let summary = gestureContactSummary(in: touches)
        if summary.count >= 4 {
            lastFourPlusContactTime[side] = now
        }
        if summary.count >= 5 {
            lastFivePlusContactTime[side] = now
        }
        updateTwoFingerHold(for: side, summary: summary, now: now)
        updateThreeFingerHold(for: side, summary: summary, now: now)
        updateFourFingerHold(for: side, summary: summary, now: now)
        updateThreeFingerDirectionalSwipe(for: side, summary: summary, now: now)
        updateFourFingerDirectionalSwipe(for: side, summary: summary, now: now)
        updateFiveFingerDirectionalSwipe(for: side, summary: summary, now: now)
        updateSingleTouchShapeGestures(for: side, touches: touches, now: now)
        updateThreeFingerTap(for: side, summary: summary, now: now)
        updateMultiFingerClicks(for: side, summary: summary, now: now)
    }

    private func resetGestureState(for side: TrackpadSide) {
        stopAllGestureRepeats(on: side)
        chordShiftActivationCount[side] = 0
        twoFingerHoldState[side] = MultiFingerHoldState()
        threeFingerHoldState[side] = MultiFingerHoldState()
        fourFingerHoldState[side] = MultiFingerHoldState()
        chordShiftLastContactTime[side] = 0
        lastFourPlusContactTime[side] = -1
        lastFivePlusContactTime[side] = -1
        threeFingerSwipeState[side] = DirectionalSwipeState()
        fourFingerSwipeState[side] = DirectionalSwipeState()
        fiveFingerSwipeState[side] = DirectionalSwipeState()
        edgeSlideState[side] = EdgeSlideState()
        cornerSwipeState[side] = CornerSwipeState()
        triangleGestureState[side] = TriangleGestureState()
        threeFingerTapStateBySide[side] = ThreeFingerTapState()
        cornerClickState[side] = CornerClickState()
        forceClickState[side] = ForceClickState()
        multiFingerClickState[side] = MultiFingerClickState()
        updateThreeFingerHoldDragSuppression()
    }

    private func isChordShiftGestureAction(_ action: KeyAction) -> Bool {
        if action.kind == .chordalShift {
            return true
        }
        guard action.kind == .key, action.flags == 0 else {
            return false
        }
        let code = CGKeyCode(action.keyCode)
        return code == CGKeyCode(kVK_Shift) || code == CGKeyCode(kVK_RightShift)
    }

    private var isChordShiftGestureActive: Bool {
        isChordShiftGestureAction(twoFingerHoldAction)
            || isChordShiftGestureAction(threeFingerHoldAction)
            || isChordShiftGestureAction(fourFingerHoldAction)
    }

    private func updateTwoFingerHold(for side: TrackpadSide, summary: GestureContactSummary, now: TimeInterval) {
        updateMultiFingerHold(
            for: side,
            summary: summary,
            bindingId: GestureBindingID.twoFingerHold,
            requiredContactCount: 2,
            action: twoFingerHoldAction,
            state: &twoFingerHoldState[side],
            now: now
        )
    }

    private func updateThreeFingerHold(for side: TrackpadSide, summary: GestureContactSummary, now: TimeInterval) {
        updateMultiFingerHold(
            for: side,
            summary: summary,
            bindingId: GestureBindingID.threeFingerHold,
            requiredContactCount: 3,
            action: threeFingerHoldAction,
            state: &threeFingerHoldState[side],
            now: now
        )
        updateThreeFingerHoldDragSuppression()
    }

    private func updateFourFingerHold(for side: TrackpadSide, summary: GestureContactSummary, now: TimeInterval) {
        let action = fourFingerHoldAction
        guard action.kind != .none else {
            stopGestureRepeatIfNeeded(fourFingerHoldState[side].repeatBindingId, side: side)
            fourFingerHoldState[side] = MultiFingerHoldState()
            return
        }

        updateMultiFingerHold(
            for: side,
            summary: summary,
            bindingId: GestureBindingID.fourFingerHold,
            requiredContactCount: 4,
            action: action,
            state: &fourFingerHoldState[side],
            now: now
        )
    }

    private func updateMultiFingerHold(
        for side: TrackpadSide,
        summary: GestureContactSummary,
        bindingId: String,
        requiredContactCount: Int,
        action: KeyAction,
        state: inout MultiFingerHoldState,
        now: TimeInterval
    ) {
        let contactCount = summary.count
        let usesChordShift = isChordShiftGestureAction(action)
        guard action.kind != .none else {
            stopGestureRepeatIfNeeded(state.repeatBindingId, side: side)
            if state.triggered, usesChordShift {
                chordShiftActivationCount[side] = max(0, chordShiftActivationCount[side] - 1)
            }
            state = MultiFingerHoldState()
            return
        }

        if contactCount == 0 {
            if state.blockedUntilAllUp {
                stopGestureRepeatIfNeeded(state.repeatBindingId, side: side)
                if state.triggered, usesChordShift {
                    chordShiftActivationCount[side] = max(0, chordShiftActivationCount[side] - 1)
                }
                state = MultiFingerHoldState()
                return
            }
            if state.active {
                let elapsed = now - chordShiftLastContactTime[side]
                if elapsed >= contactCountHoldDuration {
                    stopGestureRepeatIfNeeded(state.repeatBindingId, side: side)
                    if state.triggered, usesChordShift {
                        chordShiftActivationCount[side] = max(0, chordShiftActivationCount[side] - 1)
                    }
                    state = MultiFingerHoldState()
                }
            }
            return
        }

        if contactCount > 0 {
            chordShiftLastContactTime[side] = now
        }

        if state.blockedUntilAllUp {
            return
        }

        if state.active {
            if contactCount != requiredContactCount {
                stopGestureRepeatIfNeeded(state.repeatBindingId, side: side)
                if state.triggered, usesChordShift {
                    chordShiftActivationCount[side] = max(0, chordShiftActivationCount[side] - 1)
                }
                var blocked = MultiFingerHoldState()
                blocked.blockedUntilAllUp = true
                state = blocked
                return
            }

            let holdCancelThreshold = holdGestureMoveCancelMm * unitsPerMillimeter
            if distanceSquared(from: state.startCentroid, to: summary.centroid) > (holdCancelThreshold * holdCancelThreshold) {
                stopGestureRepeatIfNeeded(state.repeatBindingId, side: side)
                if state.triggered, usesChordShift {
                    chordShiftActivationCount[side] = max(0, chordShiftActivationCount[side] - 1)
                }
                var blocked = MultiFingerHoldState()
                blocked.blockedUntilAllUp = true
                state = blocked
                return
            }
            let holdDelay = gestureHoldDelay(for: action)
            if !state.triggered, holdDelay > 0, now - state.startTime >= holdDelay {
                state.triggered = true
                state.repeatBindingId = bindingId
                if usesChordShift {
                    chordShiftActivationCount[side] += 1
                } else {
                    performGestureAction(action, now: now, side: side, bindingId: bindingId)
                }
            }
            return
        }

        guard contactCount == requiredContactCount else { return }
        if (requiredContactCount == 2 || requiredContactCount == 3),
           !areSideTouchStartsSynchronizedForHold(side, expectedCount: requiredContactCount) {
            return
        }
        state.active = true
        state.startTime = now
        state.startCentroid = summary.centroid
        state.blockedUntilAllUp = false
        let holdDelay = gestureHoldDelay(for: action)
        if holdDelay <= 0 {
            state.triggered = true
            state.repeatBindingId = bindingId
            if usesChordShift {
                chordShiftActivationCount[side] += 1
            } else {
                performGestureAction(action, now: now, side: side, bindingId: bindingId)
            }
            return
        }
        state.triggered = false
    }

    private func gestureHoldDelay(for action: KeyAction) -> TimeInterval {
        isChordShiftGestureAction(action) ? 0 : holdMinDuration
    }

    private func updateThreeFingerHoldDragSuppression() {
        let enabled = shouldSuppressDragDuringThreeFingerHold(threeFingerHoldState[.left])
            || shouldSuppressDragDuringThreeFingerHold(threeFingerHoldState[.right])
        dispatchService.setThreeFingerHoldDragSuppression(enabled)
    }

    private func shouldSuppressDragDuringThreeFingerHold(_ state: MultiFingerHoldState) -> Bool {
        guard threeFingerHoldAction.kind != .none else { return false }
        return state.active && !state.blockedUntilAllUp
    }

    private func areSideTouchStartsSynchronizedForHold(
        _ side: TrackpadSide,
        expectedCount: Int
    ) -> Bool {
        let sideDeviceIndex: Int?
        switch side {
        case .left:
            sideDeviceIndex = leftDeviceIndex
        case .right:
            sideDeviceIndex = rightDeviceIndex
        }
        guard let sideDeviceIndex else { return false }

        var count = 0
        var minTime = TimeInterval.greatestFiniteMagnitude
        var maxTime: TimeInterval = 0
        intentState.touches.forEach { touchKey, info in
            guard Self.touchKeyDeviceIndex(touchKey) == sideDeviceIndex else { return }
            count += 1
            if info.startTime < minTime {
                minTime = info.startTime
            }
            if info.startTime > maxTime {
                maxTime = info.startTime
            }
        }
        guard count == expectedCount else { return false }
        return maxTime - minTime <= intentConfig.keyBufferSeconds
    }

    private func isChordShiftActive(on side: TrackpadSide) -> Bool {
        chordShiftActivationCount[side] > 0
    }

    private func updateChordShiftKeyState() {
        let shouldBeDown = chordShiftActivationCount[.left] > 0 || chordShiftActivationCount[.right] > 0
        guard shouldBeDown != chordShiftKeyDown else { return }
        chordShiftKeyDown = shouldBeDown
        let shiftBinding = KeyBinding(
            rect: .zero,
            normalizedRect: NormalizedRect(x: 0, y: 0, width: 0, height: 0),
            canvasSize: .zero,
            label: "Shift",
            action: .key(code: CGKeyCode(kVK_Shift), flags: []),
            position: nil,
            side: .left,
            holdAction: nil
        )
        postKey(binding: shiftBinding, keyDown: shouldBeDown)
    }

    private func updateIntent<Touches: RandomAccessCollection>(
        leftTouches: Touches,
        rightTouches: Touches,
        leftDeviceIndex: Int?,
        rightDeviceIndex: Int?,
        now: TimeInterval,
        leftBindings: BindingIndex,
        rightBindings: BindingIndex
    ) -> Bool where Touches.Element == OMSRawTouch {
        framePointCache.removeAll(keepingCapacity: true)
        guard trackpadSize.width > 0,
              trackpadSize.height > 0 else {
            intentState = IntentState()
            updateIntentDisplayIfNeeded()
            bindingCacheBySide[.left].removeAll(keepingCapacity: true)
            bindingCacheBySide[.right].removeAll(keepingCapacity: true)
            return isTypingEnabled
        }

        return updateIntentGlobal(
            leftTouches: leftTouches,
            rightTouches: rightTouches,
            leftDeviceIndex: leftDeviceIndex,
            rightDeviceIndex: rightDeviceIndex,
            leftBindings: leftBindings,
            rightBindings: rightBindings,
            now: now,
            moveThresholdSquared: intentMoveThresholdSquared,
            velocityThreshold: intentVelocityThreshold,
            unitsPerMm: unitsPerMillimeter,
            bindingCacheBySide: &bindingCacheBySide
        )
    }

    private func updateIntentGlobal<Touches: RandomAccessCollection>(
        leftTouches: Touches,
        rightTouches: Touches,
        leftDeviceIndex: Int?,
        rightDeviceIndex: Int?,
        leftBindings: BindingIndex,
        rightBindings: BindingIndex,
        now: TimeInterval,
        moveThresholdSquared: CGFloat,
        velocityThreshold: CGFloat,
        unitsPerMm: CGFloat,
        bindingCacheBySide: inout SidePair<TouchTable<KeyBinding>>
    ) -> Bool where Touches.Element == OMSRawTouch {
        var state = intentState
        let graceActive = isTypingGraceActive(now: now)
        let keyboardOnly = keyboardModeEnabled && isTypingEnabled
        bindingCacheBySide[.left].removeAll(keepingCapacity: true)
        bindingCacheBySide[.right].removeAll(keepingCapacity: true)

        var contactCount = 0
        var onKeyCount = 0
        var offKeyCount = 0
        var maxVelocity: CGFloat = 0
        var maxDistanceSquared: CGFloat = 0
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        var gestureContactCount = 0
        var gestureSumX: CGFloat = 0
        var gestureSumY: CGFloat = 0
        var firstOnKeyTouchKey: TouchKey?
        intentCurrentKeys.removeAll(keepingCapacity: true)
        var hasKeyboardAnchor = false
        var twoFingerTapDetected = false
        var threeFingerTapDetected = false
        let staggerWindow = max(tapClickCadenceSeconds, contactCountHoldDuration)

        func process(_ touch: OMSRawTouch, deviceIndex: Int, side: TrackpadSide, bindings: BindingIndex) {
            let isChordState = Self.isChordShiftContactState(touch.state)
            let isIntentState = Self.isIntentContactState(touch.state)
            guard isChordState || isIntentState else { return }
            let touchKey = Self.makeTouchKey(deviceIndex: deviceIndex, id: touch.id)
            let point = CGPoint(
                x: CGFloat(touch.posX) * trackpadSize.width,
                y: CGFloat(1.0 - touch.posY) * trackpadSize.height
            )
            framePointCache.set(touchKey, point)
            if isChordState {
                gestureContactCount += 1
                gestureSumX += point.x
                gestureSumY += point.y
            }
            if !isIntentState {
                return
            }
            let isMomentaryLayerTouch = momentaryLayerTouches.value(for: touchKey) != nil
            if isMomentaryLayerTouch {
                hasKeyboardAnchor = true
                return
            }
            contactCount += 1
            sumX += point.x
            sumY += point.y
            intentCurrentKeys.set(touchKey, true)

            if var info = state.touches.value(for: touchKey) {
                let distanceSq = distanceSquared(from: info.startPoint, to: point)
                info.maxDistanceSquared = max(info.maxDistanceSquared, distanceSq)
                maxDistanceSquared = max(maxDistanceSquared, info.maxDistanceSquared)
                let dt = max(1.0 / 240.0, now - info.lastTime)
                let velocity = sqrt(distanceSquared(from: info.lastPoint, to: point)) / dt
                maxVelocity = max(maxVelocity, velocity)
                info.lastPoint = point
                info.lastTime = now
                state.touches.set(touchKey, info)
            } else {
                state.touches.set(touchKey, IntentTouchInfo(
                    startPoint: point,
                    startTime: now,
                    lastPoint: point,
                    lastTime: now,
                    maxDistanceSquared: 0
                ))
            }
        }

        if let leftDeviceIndex {
            for touch in leftTouches {
                process(touch, deviceIndex: leftDeviceIndex, side: .left, bindings: leftBindings)
            }
        }
        if let rightDeviceIndex {
            for touch in rightTouches {
                process(touch, deviceIndex: rightDeviceIndex, side: .right, bindings: rightBindings)
            }
        }

        if let candidate = twoFingerTapCandidate, now > candidate.deadline {
            twoFingerTapCandidate = nil
        }
        if let candidate = threeFingerTapCandidate, now > candidate.deadline {
            threeFingerTapCandidate = nil
        }
        if let deadline = doubleTapDeadline, now > deadline {
            doubleTapDeadline = nil
            awaitingSecondTap = false
        }

        let detectsTwoFingerTap = isTapGestureConfigured(twoFingerTapAction)
        let detectsThreeFingerTap = isTapGestureConfigured(threeFingerTapAction)

        if keyboardOnly {
            twoFingerTapCandidate = nil
            threeFingerTapCandidate = nil
            awaitingSecondTap = false
            doubleTapDeadline = nil
        } else if detectsThreeFingerTap,
                  intentCurrentKeys.count == 2,
               state.touches.count == 3,
               shouldTriggerTapClick(
                state: state.touches,
                now: now,
                moveThresholdSquared: moveThresholdSquared,
                fingerCount: 3
               ) {
            threeFingerTapCandidate = TapCandidate(deadline: now + staggerWindow)
        } else if detectsThreeFingerTap,
                  intentCurrentKeys.count == 0,
                      state.touches.count == 3,
                      shouldTriggerTapClick(
                        state: state.touches,
                        now: now,
                        moveThresholdSquared: moveThresholdSquared,
                        fingerCount: 3
                      ) {
            threeFingerTapDetected = true
            threeFingerTapCandidate = nil
        } else if detectsThreeFingerTap,
                  intentCurrentKeys.count == 0,
                      let candidate = threeFingerTapCandidate,
                      now <= candidate.deadline {
            threeFingerTapDetected = true
            threeFingerTapCandidate = nil
        } else if detectsTwoFingerTap,
                  intentCurrentKeys.count == 1,
                      state.touches.count == 2,
                      shouldTriggerTapClick(
                        state: state.touches,
                        now: now,
                        moveThresholdSquared: moveThresholdSquared,
                        fingerCount: 2
                      ) {
            twoFingerTapCandidate = TapCandidate(deadline: now + staggerWindow)
        } else if detectsTwoFingerTap,
                  intentCurrentKeys.count == 0,
                      state.touches.count == 2,
                      shouldTriggerTapClick(
                        state: state.touches,
                        now: now,
                        moveThresholdSquared: moveThresholdSquared,
                        fingerCount: 2
                      ) {
            twoFingerTapDetected = true
            twoFingerTapCandidate = nil
        } else if detectsTwoFingerTap,
                  intentCurrentKeys.count == 0,
                      let candidate = twoFingerTapCandidate,
                      now <= candidate.deadline {
            twoFingerTapDetected = true
            twoFingerTapCandidate = nil
        } else {
            if !detectsTwoFingerTap {
                twoFingerTapCandidate = nil
            }
            if !detectsThreeFingerTap {
                threeFingerTapCandidate = nil
            }
        }

        if state.touches.count != intentCurrentKeys.count {
            intentRemovalBuffer.removeAll(keepingCapacity: true)
            state.touches.forEach { key, _ in
                if intentCurrentKeys.value(for: key) == nil {
                    intentRemovalBuffer.append(key)
                }
            }
            for key in intentRemovalBuffer {
                state.touches.remove(key)
            }
        }
        let outerCornersHoldSide = outerCornersHoldSide(leftTouches: leftTouches, rightTouches: rightTouches)
        let innerCornersHoldSide = innerCornersHoldSide(leftTouches: leftTouches, rightTouches: rightTouches)
        let cornerHoldGestureEngaged = updateCornerHoldGesture(
            holdSide: outerCornersHoldSide ?? innerCornersHoldSide,
            kind: outerCornersHoldSide != nil ? .outer : .inner,
            now: now
        )

        state.lastContactCount = contactCount
        if contactCount == 0 {
            if threeFingerTapDetected {
                performGestureAction(threeFingerTapAction, now: now, side: nil, bindingId: GestureBindingID.threeFingerTap)
            } else if twoFingerTapDetected { performTwoFingerTapAction(now: now) }
        }
        state.mode = contactCount > 0 || cornerHoldGestureEngaged ? .gestureCandidate(start: now) : .idle
        intentState = state
        updateIntentDisplayIfNeeded()
        return false
    }

    private func shouldTriggerTapClick(
        state: TouchTable<IntentTouchInfo>,
        now: TimeInterval,
        moveThresholdSquared: CGFloat,
        fingerCount: Int
    ) -> Bool {
        if state.count != fingerCount {
            return false
        }
        var maxDuration: TimeInterval = 0
        var maxDistanceSquared: CGFloat = 0
        state.forEach { _, info in
            let duration = now - info.startTime
            if duration > maxDuration {
                maxDuration = duration
            }
            if info.maxDistanceSquared > maxDistanceSquared {
                maxDistanceSquared = info.maxDistanceSquared
            }
        }
        if maxDuration > tapMaxDuration {
            return false
        }
        if maxDistanceSquared > moveThresholdSquared {
            return false
        }
        return true
    }

    private func isTapGestureConfigured(_ action: KeyAction) -> Bool {
        action.kind != .none
    }

    private func updateIntentDisplayIfNeeded() {
        let next = intentDisplay(for: intentState.mode)
        if next == intentDisplayBySide[.left], next == intentDisplayBySide[.right] {
            return
        }
        intentDisplayBySide[.left] = next
        intentDisplayBySide[.right] = next
        onIntentStateChanged(intentDisplayBySide)
    }

    private func intentDisplay(for mode: IntentMode) -> IntentDisplay {
        switch mode {
        case .idle:
            return .idle
        case .keyCandidate:
            return .keyCandidate
        case .typingCommitted:
            return .typing
        case .mouseCandidate, .mouseActive:
            return .mouse
        case .gestureCandidate:
            return .gesture
        }
    }


    private func isTypingGraceActive(now: TimeInterval? = nil) -> Bool {
        let currentNow = now ?? currentTime()
        if let deadline = typingGraceDeadline, currentNow < deadline {
            return true
        }
        typingGraceDeadline = nil
        return false
    }

    private var trackpadHeightMillimeters: CGFloat {
        guard unitsPerMillimeter > 0 else { return 1.0 }
        return max(1.0, trackpadSize.height / unitsPerMillimeter)
    }

    private func normalizedPoint(for touch: OMSRawTouch) -> CGPoint {
        CGPoint(x: CGFloat(touch.posX), y: CGFloat(1.0 - touch.posY))
    }

    private func updateDirectionalSwipe(
        state: inout DirectionalSwipeState,
        side: TrackpadSide,
        summary: GestureContactSummary,
        armContacts: Int,
        sustainContacts: Int,
        releaseContacts: Int,
        leftBindingId: String,
        rightBindingId: String,
        upBindingId: String,
        downBindingId: String,
        leftAction: KeyAction,
        rightAction: KeyAction,
        upAction: KeyAction,
        downAction: KeyAction,
        now: TimeInterval
    ) {
        let enabled = leftAction.kind != .none
            || rightAction.kind != .none
            || upAction.kind != .none
            || downAction.kind != .none
        guard enabled else {
            stopGestureRepeatIfNeeded(state.repeatBindingId, side: side)
            state = DirectionalSwipeState()
            return
        }
        if !state.active {
            if summary.count >= armContacts {
                state.active = true
                state.triggered = false
                state.startX = summary.centroid.x
                state.startY = summary.centroid.y
            }
            return
        }
        if summary.count <= releaseContacts {
            stopGestureRepeatIfNeeded(state.repeatBindingId, side: side)
            state = DirectionalSwipeState()
            return
        }
        if summary.count < sustainContacts || state.triggered {
            return
        }
        let dx = summary.centroid.x - state.startX
        let dy = summary.centroid.y - state.startY
        let threshold = directionalSwipeThresholdMm * unitsPerMillimeter
        let absDx = abs(dx)
        let absDy = abs(dy)
        let action: KeyAction
        let bindingId: String
        if absDx >= threshold, absDx >= absDy * directionalSwipeAxisDominanceRatio {
            if dx >= 0 {
                action = rightAction
                bindingId = rightBindingId
            } else {
                action = leftAction
                bindingId = leftBindingId
            }
        } else if absDy >= threshold, absDy >= absDx * directionalSwipeAxisDominanceRatio {
            if dy >= 0 {
                action = downAction
                bindingId = downBindingId
            } else {
                action = upAction
                bindingId = upBindingId
            }
        } else {
            return
        }
        guard action.kind != .none else { return }
        state.triggered = true
        state.repeatBindingId = bindingId
        performGestureAction(action, now: now, side: side, bindingId: bindingId)
    }

    private func updateThreeFingerDirectionalSwipe(
        for side: TrackpadSide,
        summary: GestureContactSummary,
        now: TimeInterval
    ) {
        if summary.count >= 4
            || fourFingerSwipeState[side].active
            || hadRecentFourPlusContact(on: side, now: now) {
            stopGestureRepeatIfNeeded(threeFingerSwipeState[side].repeatBindingId, side: side)
            threeFingerSwipeState[side] = DirectionalSwipeState()
            return
        }
        updateDirectionalSwipe(
            state: &threeFingerSwipeState[side],
            side: side,
            summary: summary,
            armContacts: 3,
            sustainContacts: 2,
            releaseContacts: 1,
            leftBindingId: GestureBindingID.threeFingerSwipeLeft,
            rightBindingId: GestureBindingID.threeFingerSwipeRight,
            upBindingId: GestureBindingID.threeFingerSwipeUp,
            downBindingId: GestureBindingID.threeFingerSwipeDown,
            leftAction: threeFingerSwipeLeftAction,
            rightAction: threeFingerSwipeRightAction,
            upAction: threeFingerSwipeUpAction,
            downAction: threeFingerSwipeDownAction,
            now: now
        )
    }

    private func updateFourFingerDirectionalSwipe(
        for side: TrackpadSide,
        summary: GestureContactSummary,
        now: TimeInterval
    ) {
        let fiveSwipeEnabled = fiveFingerSwipeLeftAction.kind != .none
            || fiveFingerSwipeRightAction.kind != .none
            || fiveFingerSwipeUpAction.kind != .none
            || fiveFingerSwipeDownAction.kind != .none
        if fiveSwipeEnabled,
           (summary.count >= 5
            || fiveFingerSwipeState[side].active
            || hadRecentFivePlusContact(on: side, now: now)) {
            stopGestureRepeatIfNeeded(fourFingerSwipeState[side].repeatBindingId, side: side)
            fourFingerSwipeState[side] = DirectionalSwipeState()
            return
        }
        updateDirectionalSwipe(
            state: &fourFingerSwipeState[side],
            side: side,
            summary: summary,
            armContacts: 4,
            sustainContacts: 3,
            releaseContacts: 1,
            leftBindingId: GestureBindingID.fourFingerSwipeLeft,
            rightBindingId: GestureBindingID.fourFingerSwipeRight,
            upBindingId: GestureBindingID.fourFingerSwipeUp,
            downBindingId: GestureBindingID.fourFingerSwipeDown,
            leftAction: fourFingerSwipeLeftAction,
            rightAction: fourFingerSwipeRightAction,
            upAction: fourFingerSwipeUpAction,
            downAction: fourFingerSwipeDownAction,
            now: now
        )
    }

    private func updateFiveFingerDirectionalSwipe(
        for side: TrackpadSide,
        summary: GestureContactSummary,
        now: TimeInterval
    ) {
        updateDirectionalSwipe(
            state: &fiveFingerSwipeState[side],
            side: side,
            summary: summary,
            armContacts: 5,
            sustainContacts: 4,
            releaseContacts: 1,
            leftBindingId: GestureBindingID.fiveFingerSwipeLeft,
            rightBindingId: GestureBindingID.fiveFingerSwipeRight,
            upBindingId: GestureBindingID.fiveFingerSwipeUp,
            downBindingId: GestureBindingID.fiveFingerSwipeDown,
            leftAction: fiveFingerSwipeLeftAction,
            rightAction: fiveFingerSwipeRightAction,
            upAction: fiveFingerSwipeUpAction,
            downAction: fiveFingerSwipeDownAction,
            now: now
        )
    }

    private func hadRecentFourPlusContact(on side: TrackpadSide, now: TimeInterval) -> Bool {
        let last = lastFourPlusContactTime[side]
        guard last >= 0 else { return false }
        return now - last <= fourFingerDominanceSuppressSeconds
    }

    private func hadRecentFivePlusContact(on side: TrackpadSide, now: TimeInterval) -> Bool {
        let last = lastFivePlusContactTime[side]
        guard last >= 0 else { return false }
        return now - last <= fiveFingerDominanceSuppressSeconds
    }

    private func updateSingleTouchShapeGestures<Touches: Sequence>(
        for side: TrackpadSide,
        touches: Touches,
        now: TimeInterval
    ) where Touches.Element == OMSRawTouch {
        let contactTouches = touches.filter { Self.isContactState($0.state) }
        let singleTouch = contactTouches.count == 1 ? contactTouches[0] : nil
        updateEdgeSlide(for: side, touch: singleTouch, now: now)
        updateCornerSwipe(for: side, touch: singleTouch, now: now)
        updateTriangleGesture(for: side, touch: singleTouch, now: now)
        updateCornerClick(for: side, touch: singleTouch, now: now)
        updateForceClick(for: side, touch: singleTouch, now: now)
    }

    private func updateThreeFingerTap(
        for side: TrackpadSide,
        summary: GestureContactSummary,
        now: TimeInterval
    ) {
        guard threeFingerTapAction.kind != .none else {
            stopGestureRepeatIfNeeded(threeFingerTapStateBySide[side].repeatBindingId, side: side)
            threeFingerTapStateBySide[side] = ThreeFingerTapState()
            return
        }
        var state = threeFingerTapStateBySide[side]
        if summary.count == 3 {
            if !state.active {
                state.active = true
                state.candidateValid = true
                state.startTime = now
                state.startX = summary.centroid.x
                state.startY = summary.centroid.y
                state.maxDistanceMm = 0
            } else if state.candidateValid {
                let dxMm = abs(summary.centroid.x - state.startX) / unitsPerMillimeter
                let dyMm = abs(summary.centroid.y - state.startY) / unitsPerMillimeter
                state.maxDistanceMm = max(state.maxDistanceMm, hypot(dxMm, dyMm))
                if now - state.startTime > threeFingerTapMaxDuration
                    || state.maxDistanceMm > threeFingerTapMaxMovementMm {
                    state.candidateValid = false
                }
            }
            threeFingerTapStateBySide[side] = state
            return
        }
        if state.active, state.candidateValid,
           summary.count < 3,
           now - state.startTime <= threeFingerTapMaxDuration,
           state.maxDistanceMm <= threeFingerTapMaxMovementMm {
            state.repeatBindingId = GestureBindingID.threeFingerTap
            performGestureAction(
                threeFingerTapAction,
                now: now,
                side: side,
                bindingId: GestureBindingID.threeFingerTap
            )
        }
        stopGestureRepeatIfNeeded(state.repeatBindingId, side: side)
        threeFingerTapStateBySide[side] = ThreeFingerTapState()
    }

    private func updateMultiFingerClicks(
        for side: TrackpadSide,
        summary: GestureContactSummary,
        now: TimeInterval
    ) {
        var state = multiFingerClickState[side]
        if summary.count <= 0 {
            stopGestureRepeatIfNeeded(state.repeatBindingId, side: side)
            state = MultiFingerClickState()
            multiFingerClickState[side] = state
            return
        }
        state.maxContactsSeen = max(state.maxContactsSeen, summary.count)
        let action: KeyAction
        let bindingId: String?
        switch state.maxContactsSeen {
        case 3:
            action = threeFingerClickAction
            bindingId = GestureBindingID.threeFingerClick
        case 4:
            action = fourFingerClickAction
            bindingId = GestureBindingID.fourFingerClick
        default:
            action = KeyActionCatalog.noneAction
            bindingId = nil
        }
        if !state.forceTriggeredForCurrentPress,
           action.kind != .none,
           let pressure = currentPeakPressureForSide(side),
           isClickActuationSatisfied(pressure) {
            state.forceTriggeredForCurrentPress = true
            state.repeatBindingId = bindingId
            performGestureAction(action, now: now, side: side, bindingId: bindingId)
        }
        multiFingerClickState[side] = state
    }

    private func currentPeakPressureForSide(_ side: TrackpadSide) -> Float? {
        var peak: Float?
        peakPressureByTouch.forEach { touchKey, value in
            guard touchKeySide(touchKey) == side else { return }
            peak = max(peak ?? 0, value)
        }
        return peak
    }

    private func updateEdgeSlide(for side: TrackpadSide, touch: OMSRawTouch?, now: TimeInterval) {
        var state = edgeSlideState[side]
        let enabled = leftEdgeUpAction.kind != .none || leftEdgeDownAction.kind != .none
            || rightEdgeUpAction.kind != .none || rightEdgeDownAction.kind != .none
            || topEdgeLeftAction.kind != .none || topEdgeRightAction.kind != .none
            || bottomEdgeLeftAction.kind != .none || bottomEdgeRightAction.kind != .none
        guard enabled else {
            stopGestureRepeatIfNeeded(edgeSlideState[side].repeatBindingId, side: side)
            edgeSlideState[side] = EdgeSlideState()
            return
        }
        guard let touch else {
            stopGestureRepeatIfNeeded(edgeSlideState[side].repeatBindingId, side: side)
            edgeSlideState[side] = EdgeSlideState()
            return
        }
        let point = normalizedPoint(for: touch)
        if !state.active {
            guard let zone = classifyEdgeZone(point) else { return }
            state.active = true
            state.candidateValid = true
            state.zone = zone
            state.startTime = now
            state.startX = point.x
            state.startY = point.y
            state.lastX = point.x
            state.lastY = point.y
            state.minX = point.x
            state.maxX = point.x
            state.minY = point.y
            state.maxY = point.y
            edgeSlideState[side] = state
            return
        }
        guard state.candidateValid else {
            edgeSlideState[side] = state
            return
        }
        state.lastX = point.x
        state.lastY = point.y
        state.minX = min(state.minX, point.x)
        state.maxX = max(state.maxX, point.x)
        state.minY = min(state.minY, point.y)
        state.maxY = max(state.maxY, point.y)
        if !isWithinEdgeZone(state.zone, point)
            || edgeSlideLateralTravelMm(state) > edgeSlideMaxLateralTravelMm
            || now - state.startTime > edgeSlideMaxDuration {
            stopGestureRepeatIfNeeded(state.repeatBindingId, side: side)
            state.candidateValid = false
            edgeSlideState[side] = state
            return
        }
        if let direction = matchedEdgeSlideDirection(state),
           let bindingId = edgeSlideBindingId(for: state.zone, direction: direction),
           let action = edgeSlideAction(for: state.zone, direction: direction),
           action.kind != .none {
            state.candidateValid = false
            state.repeatBindingId = bindingId
            performGestureAction(action, now: now, side: side, bindingId: bindingId)
        }
        edgeSlideState[side] = state
    }

    private func updateCornerSwipe(for side: TrackpadSide, touch: OMSRawTouch?, now: TimeInterval) {
        var state = cornerSwipeState[side]
        let enabled = topLeftCornerSwipeAction.kind != .none || topRightCornerSwipeAction.kind != .none
            || bottomLeftCornerSwipeAction.kind != .none || bottomRightCornerSwipeAction.kind != .none
        guard enabled else {
            stopGestureRepeatIfNeeded(cornerSwipeState[side].repeatBindingId, side: side)
            cornerSwipeState[side] = CornerSwipeState()
            return
        }
        guard let touch else {
            stopGestureRepeatIfNeeded(cornerSwipeState[side].repeatBindingId, side: side)
            cornerSwipeState[side] = CornerSwipeState()
            return
        }
        let point = normalizedPoint(for: touch)
        if !state.active {
            guard let corner = classifyCorner(point, threshold: cornerSwipeStartThreshold),
                  cornerSwipeAction(for: corner).kind != .none else { return }
            state.active = true
            state.candidateValid = true
            state.corner = corner
            state.startTime = now
            state.startX = point.x
            state.startY = point.y
            state.peakX = point.x
            state.peakY = point.y
            state.lastX = point.x
            state.lastY = point.y
            cornerSwipeState[side] = state
            return
        }
        guard state.candidateValid else {
            cornerSwipeState[side] = state
            return
        }
        state.lastX = point.x
        state.lastY = point.y
        state.peakX = cornerSignX(for: state.corner) > 0 ? max(state.peakX, point.x) : min(state.peakX, point.x)
        state.peakY = cornerSignY(for: state.corner) > 0 ? max(state.peakY, point.y) : min(state.peakY, point.y)
        if now - state.startTime > cornerSwipeMaxDuration
            || cornerSwipeReverseTravelXmm(state) > cornerSwipeMaxReverseTravelMm
            || cornerSwipeReverseTravelYmm(state) > cornerSwipeMaxReverseTravelMm {
            stopGestureRepeatIfNeeded(state.repeatBindingId, side: side)
            state.candidateValid = false
            cornerSwipeState[side] = state
            return
        }
        if cornerSwipeMatches(state, minDistanceMm: cornerSwipeTriggerDistanceMm),
           cornerSwipeAction(for: state.corner).kind != .none {
            state.candidateValid = false
            let bindingId = cornerSwipeBindingId(for: state.corner)
            state.repeatBindingId = bindingId
            performGestureAction(
                cornerSwipeAction(for: state.corner),
                now: now,
                side: side,
                bindingId: bindingId
            )
        }
        cornerSwipeState[side] = state
    }

    private func updateTriangleGesture(for side: TrackpadSide, touch: OMSRawTouch?, now: TimeInterval) {
        var state = triangleGestureState[side]
        let enabled = topLeftTriangleAction.kind != .none || topRightTriangleAction.kind != .none
            || bottomLeftTriangleAction.kind != .none || bottomRightTriangleAction.kind != .none
        guard enabled else {
            stopGestureRepeatIfNeeded(triangleGestureState[side].repeatBindingId, side: side)
            triangleGestureState[side] = TriangleGestureState()
            return
        }
        guard let touch else {
            stopGestureRepeatIfNeeded(triangleGestureState[side].repeatBindingId, side: side)
            triangleGestureState[side] = TriangleGestureState()
            return
        }
        let point = normalizedPoint(for: touch)
        if !state.active {
            guard let corner = classifyCorner(point, threshold: triangleStartThreshold),
                  triangleAction(for: corner).kind != .none else { return }
            state.active = true
            state.candidateValid = true
            state.corner = corner
            state.startTime = now
            state.startX = point.x
            state.startY = point.y
            state.peakX = point.x
            state.peakY = point.y
            state.maxX = point.x
            state.maxY = point.y
            state.lastX = point.x
            state.lastY = point.y
            triangleGestureState[side] = state
            return
        }
        guard state.candidateValid else {
            triangleGestureState[side] = state
            return
        }
        state.lastX = point.x
        state.lastY = point.y
        state.maxX = cornerSignX(for: state.corner) > 0 ? max(state.maxX, point.x) : min(state.maxX, point.x)
        state.maxY = cornerSignY(for: state.corner) > 0 ? max(state.maxY, point.y) : min(state.maxY, point.y)
        let progress = ((point.x - state.startX) * cornerSignX(for: state.corner))
            + ((point.y - state.startY) * cornerSignY(for: state.corner))
        let peakProgress = ((state.peakX - state.startX) * cornerSignX(for: state.corner))
            + ((state.peakY - state.startY) * cornerSignY(for: state.corner))
        if progress > peakProgress {
            state.peakX = point.x
            state.peakY = point.y
        }
        if now - state.startTime > triangleMaxDuration {
            stopGestureRepeatIfNeeded(state.repeatBindingId, side: side)
            state.candidateValid = false
            triangleGestureState[side] = state
            return
        }
        if triangleMatches(state), triangleAction(for: state.corner).kind != .none {
            state.candidateValid = false
            let bindingId = triangleBindingId(for: state.corner)
            state.repeatBindingId = bindingId
            performGestureAction(
                triangleAction(for: state.corner),
                now: now,
                side: side,
                bindingId: bindingId
            )
        }
        triangleGestureState[side] = state
    }

    private func updateCornerClick(for side: TrackpadSide, touch: OMSRawTouch?, now: TimeInterval) {
        var state = cornerClickState[side]
        let enabled = upperLeftCornerClickAction.kind != .none || upperRightCornerClickAction.kind != .none
            || lowerLeftCornerClickAction.kind != .none || lowerRightCornerClickAction.kind != .none
        guard enabled else {
            stopGestureRepeatIfNeeded(cornerClickState[side].repeatBindingId, side: side)
            cornerClickState[side] = CornerClickState()
            return
        }
        guard let touch else {
            if state.active, state.candidateValid, state.forceArmed,
               cornerClickAction(for: state.corner).kind != .none {
                let bindingId = cornerClickBindingId(for: state.corner)
                state.repeatBindingId = bindingId
                performGestureAction(
                    cornerClickAction(for: state.corner),
                    now: now,
                    side: side,
                    bindingId: bindingId
                )
            }
            stopGestureRepeatIfNeeded(state.repeatBindingId, side: side)
            cornerClickState[side] = CornerClickState()
            return
        }
        let point = normalizedPoint(for: touch)
        if !state.active {
            guard let corner = classifyCorner(point, threshold: cornerClickZoneThreshold),
                  cornerClickAction(for: corner).kind != .none else { return }
            state.active = true
            state.candidateValid = true
            state.forceArmed = isClickActuationSatisfied(touch.pressure)
            state.corner = corner
            state.startTime = now
            state.startX = point.x
            state.startY = point.y
            state.lastX = point.x
            state.lastY = point.y
            state.maxDistanceMm = 0
            state.peakPressure = max(0, touch.pressure)
            cornerClickState[side] = state
            return
        }
        guard state.candidateValid else {
            cornerClickState[side] = state
            return
        }
        state.peakPressure = max(state.peakPressure, max(0, touch.pressure))
        state.forceArmed = state.forceArmed || isClickActuationSatisfied(state.peakPressure)
        state.lastX = point.x
        state.lastY = point.y
        state.maxDistanceMm = max(state.maxDistanceMm, normalizedDistanceMm(from: CGPoint(x: state.startX, y: state.startY), to: point))
        if state.maxDistanceMm > dragCancelDistance
            || now - state.startTime > cornerClickMaxDuration
            || classifyCorner(point, threshold: cornerClickZoneThreshold) != state.corner
            || cornerForceClickOverrideAction(for: state.corner).kind != .none
                && isForceClickGestureTriggered(state.peakPressure) {
            state.candidateValid = false
        }
        cornerClickState[side] = state
    }

    private func updateForceClick(for side: TrackpadSide, touch: OMSRawTouch?, now: TimeInterval) {
        var state = forceClickState[side]
        let enabled = topLeftForceClickAction.kind != .none || topRightForceClickAction.kind != .none
            || bottomLeftForceClickAction.kind != .none || bottomRightForceClickAction.kind != .none
        guard enabled else {
            stopGestureRepeatIfNeeded(forceClickState[side].repeatBindingId, side: side)
            forceClickState[side] = ForceClickState()
            return
        }
        guard let touch else {
            stopGestureRepeatIfNeeded(forceClickState[side].repeatBindingId, side: side)
            forceClickState[side] = ForceClickState()
            return
        }
        let point = normalizedPoint(for: touch)
        if !state.active {
            state.active = true
            state.candidateValid = true
            state.corner = classifyCorner(point, threshold: cornerClickZoneThreshold)
            state.startTime = now
            state.startX = point.x
            state.startY = point.y
            state.lastX = point.x
            state.lastY = point.y
            state.maxDistanceMm = 0
            state.peakPressure = max(0, touch.pressure)
            state.triggered = false
            forceClickState[side] = state
            return
        }
        guard state.candidateValid else {
            forceClickState[side] = state
            return
        }
        state.corner = classifyCorner(point, threshold: cornerClickZoneThreshold)
        state.lastX = point.x
        state.lastY = point.y
        state.maxDistanceMm = max(state.maxDistanceMm, normalizedDistanceMm(from: CGPoint(x: state.startX, y: state.startY), to: point))
        state.peakPressure = max(state.peakPressure, max(0, touch.pressure))
        if state.maxDistanceMm > dragCancelDistance || now - state.startTime > forceClickMaxDuration {
            stopGestureRepeatIfNeeded(state.repeatBindingId, side: side)
            state.candidateValid = false
            forceClickState[side] = state
            return
        }
        if !state.triggered,
           isForceClickGestureTriggered(state.peakPressure),
           let corner = state.corner,
           forceClickAction(for: corner).kind != .none {
            state.triggered = true
            state.candidateValid = false
            let bindingId = forceClickBindingId(for: corner)
            state.repeatBindingId = bindingId
            performGestureAction(
                forceClickAction(for: corner),
                now: now,
                side: side,
                bindingId: bindingId
            )
        }
        forceClickState[side] = state
    }

    private func normalizedDistanceMm(from start: CGPoint, to end: CGPoint) -> CGFloat {
        let dxMm = (end.x - start.x) * trackpadWidthMm
        let dyMm = (end.y - start.y) * trackpadHeightMillimeters
        return hypot(dxMm, dyMm)
    }

    private func classifyEdgeZone(_ point: CGPoint) -> EdgeGestureZone? {
        if point.x <= edgeSlideStartThreshold { return .left }
        if point.x >= (1.0 - edgeSlideStartThreshold) { return .right }
        if point.y <= edgeSlideStartThreshold { return .top }
        if point.y >= (1.0 - edgeSlideStartThreshold) { return .bottom }
        return nil
    }

    private func isWithinEdgeZone(_ zone: EdgeGestureZone, _ point: CGPoint) -> Bool {
        switch zone {
        case .left:
            return point.x <= edgeSlideStayThreshold
        case .right:
            return point.x >= (1.0 - edgeSlideStayThreshold)
        case .top:
            return point.y <= edgeSlideStayThreshold
        case .bottom:
            return point.y >= (1.0 - edgeSlideStayThreshold)
        }
    }

    private func matchedEdgeSlideDirection(_ state: EdgeSlideState) -> SwipeDirection? {
        let primaryTravelMm: CGFloat
        let lateralTravelMm: CGFloat
        let direction: SwipeDirection
        switch state.zone {
        case .left, .right:
            let upTravel = (state.startY - state.minY) * trackpadHeightMillimeters
            let downTravel = (state.maxY - state.startY) * trackpadHeightMillimeters
            direction = downTravel > upTravel ? .down : .up
            primaryTravelMm = max(upTravel, downTravel)
            lateralTravelMm = (state.maxX - state.minX) * trackpadWidthMm
        case .top, .bottom:
            let leftTravel = (state.startX - state.minX) * trackpadWidthMm
            let rightTravel = (state.maxX - state.startX) * trackpadWidthMm
            direction = rightTravel > leftTravel ? .right : .left
            primaryTravelMm = max(leftTravel, rightTravel)
            lateralTravelMm = (state.maxY - state.minY) * trackpadHeightMillimeters
        }
        guard primaryTravelMm >= edgeSlideTriggerDistanceMm,
              primaryTravelMm >= lateralTravelMm * edgeSlideDirectionDominanceRatio else {
            return nil
        }
        return direction
    }

    private func edgeSlideLateralTravelMm(_ state: EdgeSlideState) -> CGFloat {
        switch state.zone {
        case .left, .right:
            return (state.maxX - state.minX) * trackpadWidthMm
        case .top, .bottom:
            return (state.maxY - state.minY) * trackpadHeightMillimeters
        }
    }

    private func edgeSlideAction(for zone: EdgeGestureZone, direction: SwipeDirection) -> KeyAction? {
        switch (zone, direction) {
        case (.left, .up):
            return leftEdgeUpAction
        case (.left, .down):
            return leftEdgeDownAction
        case (.right, .up):
            return rightEdgeUpAction
        case (.right, .down):
            return rightEdgeDownAction
        case (.top, .left):
            return topEdgeLeftAction
        case (.top, .right):
            return topEdgeRightAction
        case (.bottom, .left):
            return bottomEdgeLeftAction
        case (.bottom, .right):
            return bottomEdgeRightAction
        default:
            return nil
        }
    }

    private func edgeSlideBindingId(for zone: EdgeGestureZone, direction: SwipeDirection) -> String? {
        switch (zone, direction) {
        case (.left, .up):
            return GestureBindingID.leftEdgeUp
        case (.left, .down):
            return GestureBindingID.leftEdgeDown
        case (.right, .up):
            return GestureBindingID.rightEdgeUp
        case (.right, .down):
            return GestureBindingID.rightEdgeDown
        case (.top, .left):
            return GestureBindingID.topEdgeLeft
        case (.top, .right):
            return GestureBindingID.topEdgeRight
        case (.bottom, .left):
            return GestureBindingID.bottomEdgeLeft
        case (.bottom, .right):
            return GestureBindingID.bottomEdgeRight
        default:
            return nil
        }
    }

    private func classifyCorner(_ point: CGPoint, threshold: CGFloat) -> CornerGestureZone? {
        let left = point.x <= threshold
        let right = point.x >= (1.0 - threshold)
        let top = point.y <= threshold
        let bottom = point.y >= (1.0 - threshold)
        if left && top { return .topLeft }
        if right && top { return .topRight }
        if left && bottom { return .bottomLeft }
        if right && bottom { return .bottomRight }
        return nil
    }

    private func cornerSignX(for corner: CornerGestureZone) -> CGFloat {
        switch corner {
        case .topLeft, .bottomLeft:
            return 1
        case .topRight, .bottomRight:
            return -1
        }
    }

    private func cornerSignY(for corner: CornerGestureZone) -> CGFloat {
        switch corner {
        case .topLeft, .topRight:
            return 1
        case .bottomLeft, .bottomRight:
            return -1
        }
    }

    private func cornerSwipeMatches(_ state: CornerSwipeState, minDistanceMm: CGFloat) -> Bool {
        let inwardX = ((state.peakX - state.startX) * cornerSignX(for: state.corner)) * trackpadWidthMm
        let inwardY = ((state.peakY - state.startY) * cornerSignY(for: state.corner)) * trackpadHeightMillimeters
        let larger = max(inwardX, inwardY)
        let smaller = min(inwardX, inwardY)
        return inwardX >= minDistanceMm
            && inwardY >= minDistanceMm
            && larger <= smaller * cornerSwipeAxisBalanceRatio
    }

    private func cornerSwipeReverseTravelXmm(_ state: CornerSwipeState) -> CGFloat {
        max(0, ((state.peakX - state.lastX) * cornerSignX(for: state.corner))) * trackpadWidthMm
    }

    private func cornerSwipeReverseTravelYmm(_ state: CornerSwipeState) -> CGFloat {
        max(0, ((state.peakY - state.lastY) * cornerSignY(for: state.corner))) * trackpadHeightMillimeters
    }

    private func triangleMatches(_ state: TriangleGestureState) -> Bool {
        let outwardDx = ((state.maxX - state.startX) * cornerSignX(for: state.corner))
        let outwardDy = ((state.maxY - state.startY) * cornerSignY(for: state.corner))
        guard outwardDx >= triangleFirstLegDxThreshold,
              outwardDy >= triangleFirstLegDyThreshold else {
            return false
        }
        let returnDx = ((state.peakX - state.lastX) * cornerSignX(for: state.corner))
        let returnDy = ((state.peakY - state.lastY) * cornerSignY(for: state.corner))
        guard max(returnDx, returnDy) >= triangleReturnAxisThreshold else {
            return false
        }
        let firstLeg = CGPoint(
            x: (state.peakX - state.startX) * cornerSignX(for: state.corner),
            y: (state.peakY - state.startY) * cornerSignY(for: state.corner)
        )
        let returnLeg = CGPoint(
            x: (state.lastX - state.peakX) * cornerSignX(for: state.corner),
            y: (state.lastY - state.peakY) * cornerSignY(for: state.corner)
        )
        let firstLength = max(0.0001, hypot(firstLeg.x, firstLeg.y))
        let returnLength = max(0.0001, hypot(returnLeg.x, returnLeg.y))
        let dot = ((firstLeg.x * returnLeg.x) + (firstLeg.y * returnLeg.y)) / (firstLength * returnLength)
        return dot <= triangleTurnDotUpperBound
    }

    private func cornerSwipeAction(for corner: CornerGestureZone) -> KeyAction {
        switch corner {
        case .topLeft:
            return topLeftCornerSwipeAction
        case .topRight:
            return topRightCornerSwipeAction
        case .bottomLeft:
            return bottomLeftCornerSwipeAction
        case .bottomRight:
            return bottomRightCornerSwipeAction
        }
    }

    private func cornerSwipeBindingId(for corner: CornerGestureZone) -> String {
        switch corner {
        case .topLeft:
            return GestureBindingID.topLeftCornerSwipe
        case .topRight:
            return GestureBindingID.topRightCornerSwipe
        case .bottomLeft:
            return GestureBindingID.bottomLeftCornerSwipe
        case .bottomRight:
            return GestureBindingID.bottomRightCornerSwipe
        }
    }

    private func triangleAction(for corner: CornerGestureZone) -> KeyAction {
        switch corner {
        case .topLeft:
            return topLeftTriangleAction
        case .topRight:
            return topRightTriangleAction
        case .bottomLeft:
            return bottomLeftTriangleAction
        case .bottomRight:
            return bottomRightTriangleAction
        }
    }

    private func triangleBindingId(for corner: CornerGestureZone) -> String {
        switch corner {
        case .topLeft:
            return GestureBindingID.topLeftTriangle
        case .topRight:
            return GestureBindingID.topRightTriangle
        case .bottomLeft:
            return GestureBindingID.bottomLeftTriangle
        case .bottomRight:
            return GestureBindingID.bottomRightTriangle
        }
    }

    private func cornerClickAction(for corner: CornerGestureZone) -> KeyAction {
        switch corner {
        case .topLeft:
            return upperLeftCornerClickAction
        case .topRight:
            return upperRightCornerClickAction
        case .bottomLeft:
            return lowerLeftCornerClickAction
        case .bottomRight:
            return lowerRightCornerClickAction
        }
    }

    private func cornerClickBindingId(for corner: CornerGestureZone) -> String {
        switch corner {
        case .topLeft:
            return GestureBindingID.upperLeftCornerClick
        case .topRight:
            return GestureBindingID.upperRightCornerClick
        case .bottomLeft:
            return GestureBindingID.lowerLeftCornerClick
        case .bottomRight:
            return GestureBindingID.lowerRightCornerClick
        }
    }

    private func forceClickAction(for corner: CornerGestureZone) -> KeyAction {
        switch corner {
        case .topLeft:
            return topLeftForceClickAction
        case .topRight:
            return topRightForceClickAction
        case .bottomLeft:
            return bottomLeftForceClickAction
        case .bottomRight:
            return bottomRightForceClickAction
        }
    }

    private func forceClickBindingId(for corner: CornerGestureZone) -> String {
        switch corner {
        case .topLeft:
            return GestureBindingID.topLeftForceClick
        case .topRight:
            return GestureBindingID.topRightForceClick
        case .bottomLeft:
            return GestureBindingID.bottomLeftForceClick
        case .bottomRight:
            return GestureBindingID.bottomRightForceClick
        }
    }

    private func cornerForceClickOverrideAction(for corner: CornerGestureZone) -> KeyAction {
        forceClickAction(for: corner)
    }

    private func performTwoFingerTapAction(now: TimeInterval) {
        let action = twoFingerTapAction
        if action.kind == .leftClick {
            if awaitingSecondTap, let deadline = doubleTapDeadline, now <= deadline {
                dispatchService.postLeftClick(
                    clickCount: 2,
                    sourceSequence: currentDispatchSourceSequence()
                )
                awaitingSecondTap = false
                doubleTapDeadline = nil
            } else {
                dispatchService.postLeftClick(sourceSequence: currentDispatchSourceSequence())
                awaitingSecondTap = true
                doubleTapDeadline = now + tapClickCadenceSeconds
            }
            return
        }
        awaitingSecondTap = false
        doubleTapDeadline = nil
        performGestureAction(action, now: now, side: nil, bindingId: GestureBindingID.twoFingerTap)
    }

    private func performGestureAction(
        _ action: KeyAction,
        now _: TimeInterval,
        side: TrackpadSide?,
        bindingId: String? = nil,
        visited: Set<GestureSlot> = []
    ) {
        switch action.kind {
        case .none:
            break
        case .appLaunch:
            dispatchService.postAppLaunch(
                action.label,
                sourceSequence: currentDispatchSourceSequence()
            )
        case .leftClick:
            dispatchService.postLeftClick(sourceSequence: currentDispatchSourceSequence())
        case .doubleClick:
            dispatchService.postLeftClick(
                clickCount: 2,
                sourceSequence: currentDispatchSourceSequence()
            )
        case .rightClick:
            dispatchService.postRightClick(sourceSequence: currentDispatchSourceSequence())
        case .middleClick:
            dispatchService.postMiddleClick(sourceSequence: currentDispatchSourceSequence())
        case .volumeUp:
            if tryBeginRepeatableGestureDispatch(bindingId: bindingId, action: action, side: side) {
                return
            }
            dispatchService.postVolumeUp(sourceSequence: currentDispatchSourceSequence())
        case .volumeDown:
            if tryBeginRepeatableGestureDispatch(bindingId: bindingId, action: action, side: side) {
                return
            }
            dispatchService.postVolumeDown(sourceSequence: currentDispatchSourceSequence())
        case .volumeUpSmall:
            if tryBeginRepeatableGestureDispatch(bindingId: bindingId, action: action, side: side) {
                return
            }
            dispatchService.postVolumeUpSmall(sourceSequence: currentDispatchSourceSequence())
        case .volumeDownSmall:
            if tryBeginRepeatableGestureDispatch(bindingId: bindingId, action: action, side: side) {
                return
            }
            dispatchService.postVolumeDownSmall(sourceSequence: currentDispatchSourceSequence())
        case .brightnessUp:
            if tryBeginRepeatableGestureDispatch(bindingId: bindingId, action: action, side: side) {
                return
            }
            dispatchService.postBrightnessUp(sourceSequence: currentDispatchSourceSequence())
        case .brightnessDown:
            if tryBeginRepeatableGestureDispatch(bindingId: bindingId, action: action, side: side) {
                return
            }
            dispatchService.postBrightnessDown(sourceSequence: currentDispatchSourceSequence())
        case .brightnessUpSmall:
            if tryBeginRepeatableGestureDispatch(bindingId: bindingId, action: action, side: side) {
                return
            }
            dispatchService.postBrightnessUpSmall(sourceSequence: currentDispatchSourceSequence())
        case .brightnessDownSmall:
            if tryBeginRepeatableGestureDispatch(bindingId: bindingId, action: action, side: side) {
                return
            }
            dispatchService.postBrightnessDownSmall(sourceSequence: currentDispatchSourceSequence())
        case .voice:
            toggleVoiceDictationSession()
        case .typingToggle:
            toggleTypingMode()
        case .chordalShift:
            break
        case .gestureTwoFingerTap:
            triggerGestureSlot(.twoFingerTap, side: side, bindingId: bindingId, visited: visited)
        case .gestureThreeFingerTap:
            triggerGestureSlot(.threeFingerTap, side: side, bindingId: bindingId, visited: visited)
        case .gestureFourFingerHold:
            triggerGestureSlot(.fourFingerHold, side: side, bindingId: bindingId, visited: visited)
        case .gestureInnerCornersHold:
            triggerGestureSlot(.innerCornersHold, side: side, bindingId: bindingId, visited: visited)
        case .gestureFiveFingerSwipeLeft:
            triggerGestureSlot(.fiveFingerSwipeLeft, side: side, bindingId: bindingId, visited: visited)
        case .gestureFiveFingerSwipeRight:
            triggerGestureSlot(.fiveFingerSwipeRight, side: side, bindingId: bindingId, visited: visited)
        case .key:
            if tryBeginRepeatableGestureDispatch(bindingId: bindingId, action: action, side: side) { return }
            dispatchService.postKeyStroke(code: CGKeyCode(action.keyCode),
                flags: CGEventFlags(rawValue: action.flags).union(currentModifierFlags()),
                altAscii: 0, sourceSequence: currentDispatchSourceSequence())
        case .layerMomentary, .layerToggle:
            break
        }
    }

    private func triggerGestureSlot(
        _ slot: GestureSlot,
        side: TrackpadSide?,
        bindingId: String?,
        visited: Set<GestureSlot>
    ) {
        guard !visited.contains(slot) else { return }
        var updatedVisited = visited
        updatedVisited.insert(slot)
        let action: KeyAction
        switch slot {
        case .twoFingerTap:
            action = twoFingerTapAction
        case .threeFingerTap:
            action = threeFingerTapAction
        case .fourFingerHold:
            action = fourFingerHoldAction
        case .innerCornersHold:
            action = innerCornersHoldAction
        case .fiveFingerSwipeLeft:
            action = fiveFingerSwipeLeftAction
        case .fiveFingerSwipeRight:
            action = fiveFingerSwipeRightAction
        }
        performGestureAction(
            action,
            now: currentTime(),
            side: side,
            bindingId: bindingId,
            visited: updatedVisited
        )
    }

    private func outerCornersHoldSide<Touches: Sequence>(
        leftTouches: Touches,
        rightTouches: Touches
    ) -> TrackpadSide? where Touches.Element == OMSRawTouch {
        var leftContactCount = 0
        var topNearLeftEdge = false
        var bottomNearLeftEdge = false
        for touch in leftTouches {
            guard Self.isDictationContactState(touch.state) else { continue }
            leftContactCount += 1
            let x = CGFloat(touch.posX)
            let y = CGFloat(1.0 - touch.posY)
            if x <= voiceDictationLeftEdgeMaxX, y <= voiceDictationTopMaxY {
                topNearLeftEdge = true
            }
            if x <= voiceDictationLeftEdgeMaxX, y >= voiceDictationBottomMinY {
                bottomNearLeftEdge = true
            }
        }

        var rightContactCount = 0
        var topNearRightEdge = false
        var bottomNearRightEdge = false
        for touch in rightTouches {
            guard Self.isDictationContactState(touch.state) else { continue }
            rightContactCount += 1
            let x = CGFloat(touch.posX)
            let y = CGFloat(1.0 - touch.posY)
            if x >= voiceDictationRightEdgeMinX, y <= voiceDictationTopMaxY {
                topNearRightEdge = true
            }
            if x >= voiceDictationRightEdgeMinX, y >= voiceDictationBottomMinY {
                bottomNearRightEdge = true
            }
        }

        let leftHold = leftContactCount == 2
            && rightContactCount == 0
            && topNearLeftEdge
            && bottomNearLeftEdge
        if leftHold { return .left }

        let rightHold = rightContactCount == 2
            && leftContactCount == 0
            && topNearRightEdge
            && bottomNearRightEdge
        if rightHold { return .right }

        return nil
    }

    private func innerCornersHoldSide<Touches: Sequence>(
        leftTouches: Touches,
        rightTouches: Touches
    ) -> TrackpadSide? where Touches.Element == OMSRawTouch {
        var leftContactCount = 0
        var topNearRightEdge = false
        var bottomNearRightEdge = false
        for touch in leftTouches {
            guard Self.isDictationContactState(touch.state) else { continue }
            leftContactCount += 1
            let x = CGFloat(touch.posX)
            let y = CGFloat(1.0 - touch.posY)
            if x >= voiceDictationRightEdgeMinX, y <= voiceDictationTopMaxY {
                topNearRightEdge = true
            }
            if x >= voiceDictationRightEdgeMinX, y >= voiceDictationBottomMinY {
                bottomNearRightEdge = true
            }
        }

        var rightContactCount = 0
        var topNearLeftEdge = false
        var bottomNearLeftEdge = false
        for touch in rightTouches {
            guard Self.isDictationContactState(touch.state) else { continue }
            rightContactCount += 1
            let x = CGFloat(touch.posX)
            let y = CGFloat(1.0 - touch.posY)
            if x <= voiceDictationLeftEdgeMaxX, y <= voiceDictationTopMaxY {
                topNearLeftEdge = true
            }
            if x <= voiceDictationLeftEdgeMaxX, y >= voiceDictationBottomMinY {
                bottomNearLeftEdge = true
            }
        }

        let leftHold = leftContactCount == 2
            && rightContactCount == 0
            && topNearRightEdge
            && bottomNearRightEdge
        if leftHold { return .left }

        let rightHold = rightContactCount == 2
            && leftContactCount == 0
            && topNearLeftEdge
            && bottomNearLeftEdge
        if rightHold { return .right }

        return nil
    }

    private func updateCornerHoldGesture(
        holdSide: TrackpadSide?,
        kind: CornerHoldGestureKind,
        now: TimeInterval
    ) -> Bool {
        var state = voiceDictationGestureState
        let action = kind == .outer ? outerCornersHoldAction : innerCornersHoldAction
        let bindingId = kind == .outer ? GestureBindingID.outerCornersHold : GestureBindingID.innerCornersHold
        if let holdSide {
            if !state.holdCandidateActive || state.side != holdSide || state.kind != kind {
                stopGestureRepeatIfNeeded(state.repeatBindingId, side: state.side)
                state.holdCandidateActive = true
                state.holdDidToggle = false
                state.holdStart = now
                state.side = holdSide
                state.kind = kind
                state.repeatBindingId = nil
            } else if !state.holdDidToggle, now - state.holdStart >= gestureHoldDelay(for: action) {
                state.holdDidToggle = true
                if action.kind == .voice {
                    voiceDictationGestureState = state
                    if state.isDictating {
                        endVoiceDictationSession()
                    } else {
                        beginVoiceDictationSession()
                    }
                    state = voiceDictationGestureState
                } else {
                    if state.isDictating {
                        voiceDictationGestureState = state
                        endVoiceDictationSession()
                        state = voiceDictationGestureState
                    }
                    state.repeatBindingId = bindingId
                    performGestureAction(action, now: now, side: holdSide, bindingId: bindingId)
                }
                playHapticIfNeeded(on: holdSide)
            }
        } else {
            stopGestureRepeatIfNeeded(state.repeatBindingId, side: state.side)
            state.holdCandidateActive = false
            state.holdDidToggle = false
            state.holdStart = 0
            state.side = nil
            state.kind = .outer
            state.repeatBindingId = nil
        }
        voiceDictationGestureState = state
        updateVoiceGestureActivity()
        return state.holdCandidateActive
    }

    private func stopVoiceDictationGesture() {
        if voiceDictationGestureState.isDictating {
            endVoiceDictationSession()
        }
        voiceDictationGestureState = VoiceDictationGestureState()
        updateVoiceGestureActivity()
    }

    private func toggleVoiceDictationSession() {
        if voiceDictationGestureState.isDictating {
            endVoiceDictationSession()
        } else {
            beginVoiceDictationSession()
        }
    }

    private func beginVoiceDictationSession() {
        guard !voiceDictationGestureState.isDictating else { return }
        voiceDictationGestureState.isDictating = true
        voiceSessionChanged(true)
        updateVoiceGestureActivity()
    }

    private func endVoiceDictationSession() {
        guard voiceDictationGestureState.isDictating else { return }
        voiceDictationGestureState.isDictating = false
        voiceSessionChanged(false)
        updateVoiceGestureActivity()
    }

    private func updateVoiceGestureActivity() {
        let state = voiceDictationGestureState
        let activeHoldAction = state.kind == .outer ? outerCornersHoldAction : innerCornersHoldAction
        let isActive = state.isDictating || (activeHoldAction.kind == .voice && state.holdCandidateActive)
        guard voiceGestureActive != isActive else { return }
        voiceGestureActive = isActive
        onVoiceGestureChanged(isActive)
    }

    private func updateIntentThresholdCache() {
        guard trackpadWidthMm > 0 else {
            unitsPerMillimeter = 1
            intentMoveThresholdSquared = 0
            intentVelocityThreshold = 0
            return
        }
        unitsPerMillimeter = trackpadSize.width / trackpadWidthMm
        let moveThreshold = intentConfig.moveThresholdMm * unitsPerMillimeter
        intentMoveThresholdSquared = moveThreshold * moveThreshold
        intentVelocityThreshold = intentConfig.velocityThresholdMmPerSec * unitsPerMillimeter
    }

    private func toggleTypingMode() {
        // Gesture-only app: no typing mode.
    }

    private func isContinuousKey(_ binding: KeyBinding) -> Bool {
        guard case let .key(code, _) = binding.action else { return false }
        return code == CGKeyCode(kVK_Delete)
            || code == CGKeyCode(kVK_Space)
            || code == CGKeyCode(kVK_LeftArrow)
            || code == CGKeyCode(kVK_RightArrow)
            || code == CGKeyCode(kVK_UpArrow)
            || code == CGKeyCode(kVK_DownArrow)
    }

    private func isClickActuationSatisfied(_ pressure: Float) -> Bool {
        pressure >= clickActuationForce
    }

    private func isForceClickThresholdSatisfied(_ pressure: Float) -> Bool {
        pressure >= forceClickThreshold
    }

    private func isForceClickGestureTriggered(_ pressure: Float) -> Bool {
        isForceClickThresholdSatisfied(pressure) && isPressureWithinForceRange(pressure)
    }

    private func sendKey(
        code: CGKeyCode,
        flags: CGEventFlags,
        side: TrackpadSide?,
        combinedFlags: CGEventFlags? = nil,
        altAscii: UInt8 = 0,
        sourceSequence: UInt64? = nil
    ) {
        _ = side
        let resolvedFlags = combinedFlags ?? flags.union(currentModifierFlags())
        dispatchService.postKeyStroke(
            code: code,
            flags: resolvedFlags,
            altAscii: altAscii,
            sourceSequence: sourceSequence
        )
    }

    private func currentModifierFlags() -> CGEventFlags {
        var modifierFlags: CGEventFlags = []
        if leftShiftTouchCount > 0 || isChordShiftActive(on: .left) || isChordShiftActive(on: .right) {
            modifierFlags.insert(.maskShift)
        }
        if controlTouchCount > 0 {
            modifierFlags.insert(.maskControl)
        }
        if leftOptionTouchCount > 0 {
            modifierFlags.formUnion(KeyboardModifierFlags.leftOption)
        }
        if rightOptionTouchCount > 0 {
            modifierFlags.formUnion(KeyboardModifierFlags.rightOption)
        }
        if commandTouchCount > 0 {
            modifierFlags.insert(.maskCommand)
        }
        return modifierFlags
    }

    private func sendKey(
        binding: KeyBinding,
        touchKey: TouchKey?,
        dispatchInfo: DispatchInfo? = nil,
        pressure: Float? = nil
    ) {
        guard case let .key(code, flags) = binding.action else { return }
        if let pressure, !isPressureWithinForceRange(pressure) {
            if let touchKey {
                recordFrameDecision(
                    touchKey,
                    outcome: .rejected,
                    reason: "forceThresholdNotMet",
                    binding: binding
                )
            }
            return
        }
        #if DEBUG
        onDebugBindingDetected(binding)
#endif
        extendTypingGrace(for: binding.side, now: currentTime())
        playHapticIfNeeded(on: binding.side, touchKey: touchKey)
        sendKey(
            code: code,
            flags: flags,
            side: binding.side,
            sourceSequence: currentDispatchSourceSequence()
        )
    }

    private func playHapticIfNeeded(on side: TrackpadSide?, touchKey: TouchKey? = nil) {
        guard hapticStrength > 0 else { return }
        guard let side else { return }
        if let touchKey, disqualifiedTouches.value(for: touchKey) != nil { return }
        let now = scheduler.uptimeNanoseconds
        let last = lastHapticTimeBySide[side]
        if now &- last < Self.hapticMinIntervalNanos { return }
        lastHapticTimeBySide[side] = now
        let deviceID: String?
        switch side {
        case .left:
            deviceID = leftDeviceID
        case .right:
            deviceID = rightDeviceID
        }
        dispatchService.postHaptic(
            strength: hapticStrength,
            deviceID: deviceID,
            sourceSequence: currentDispatchSourceSequence()
        )
    }

    @discardableResult


    private func startRepeat(
        for owner: RepeatOwner,
        binding: KeyBinding,
        initialDelay: UInt64,
        interval: UInt64
    ) {
        stopRepeat(for: owner)
        guard case let .key(code, flags) = binding.action else { return }
        let dispatchService = self.dispatchService
        let repeatFlags = flags.union(currentModifierFlags())
        let sourceSequence = currentDispatchSourceSequence()
        startRepeatEntry(
            for: owner,
            initialDelay: initialDelay,
            interval: interval,
            fireInitial: {
                dispatchService.postKey(
                    code: code,
                    flags: repeatFlags,
                    keyDown: true,
                    sourceSequence: sourceSequence
                )
            },
            fire: { token in
                dispatchService.postKey(
                    code: code,
                    flags: repeatFlags,
                    keyDown: true,
                    token: token,
                    sourceSequence: sourceSequence
                )
            },
            stop: {
                dispatchService.postKey(
                    code: code,
                    flags: repeatFlags,
                    keyDown: false,
                    sourceSequence: sourceSequence
                )
            }
        )
    }

    private func startSystemKeyRepeat(
        for owner: RepeatOwner,
        systemKey: KeyEventDispatcher.SystemKey,
        initialDelay: UInt64,
        interval: UInt64
    ) {
        stopRepeat(for: owner)
        let dispatchService = self.dispatchService
        let sourceSequence = currentDispatchSourceSequence()
        startRepeatEntry(
            for: owner,
            initialDelay: initialDelay,
            interval: interval,
            fireInitial: {
                switch systemKey {
                case .volumeUp:
                    dispatchService.postVolumeUp(sourceSequence: sourceSequence)
                case .volumeDown:
                    dispatchService.postVolumeDown(sourceSequence: sourceSequence)
                case .volumeUpSmall:
                    dispatchService.postVolumeUpSmall(sourceSequence: sourceSequence)
                case .volumeDownSmall:
                    dispatchService.postVolumeDownSmall(sourceSequence: sourceSequence)
                case .brightnessUp:
                    dispatchService.postBrightnessUp(sourceSequence: sourceSequence)
                case .brightnessDown:
                    dispatchService.postBrightnessDown(sourceSequence: sourceSequence)
                case .brightnessUpSmall:
                    dispatchService.postBrightnessUpSmall(sourceSequence: sourceSequence)
                case .brightnessDownSmall:
                    dispatchService.postBrightnessDownSmall(sourceSequence: sourceSequence)
                }
            },
            fire: { _ in
                switch systemKey {
                case .volumeUp:
                    dispatchService.postVolumeUp(sourceSequence: sourceSequence)
                case .volumeDown:
                    dispatchService.postVolumeDown(sourceSequence: sourceSequence)
                case .volumeUpSmall:
                    dispatchService.postVolumeUpSmall(sourceSequence: sourceSequence)
                case .volumeDownSmall:
                    dispatchService.postVolumeDownSmall(sourceSequence: sourceSequence)
                case .brightnessUp:
                    dispatchService.postBrightnessUp(sourceSequence: sourceSequence)
                case .brightnessDown:
                    dispatchService.postBrightnessDown(sourceSequence: sourceSequence)
                case .brightnessUpSmall:
                    dispatchService.postBrightnessUpSmall(sourceSequence: sourceSequence)
                case .brightnessDownSmall:
                    dispatchService.postBrightnessDownSmall(sourceSequence: sourceSequence)
                }
            }
            ,
            stop: {}
        )
    }

    private func startRepeatEntry(
        for owner: RepeatOwner,
        initialDelay: UInt64,
        interval: UInt64,
        fireInitial: @escaping @Sendable () -> Void,
        fire: @escaping @Sendable (RepeatToken) -> Void,
        stop: @escaping @Sendable () -> Void
    ) {
        fireInitial()
        let token = RepeatToken()
        let nextFire = scheduler.uptimeNanoseconds &+ initialDelay
        repeatOrder.append(owner)
        repeatEntries[owner] = RepeatEntry(
            token: token,
            interval: interval,
            nextFire: nextFire,
            fire: fire,
            stop: stop
        )
        ensureRepeatLoop()
    }

    private func ensureRepeatLoop() {
        guard !repeatLoopScheduled else { return }
        repeatLoopScheduled = true
        scheduleNextRepeatPass()
    }

    private func scheduleNextRepeatPass() {
        let now = scheduler.uptimeNanoseconds
        guard let delay = nextRepeatDelay(now: now) else {
            repeatLoopScheduled = false
            return
        }
        repeatLoopGeneration &+= 1
        let generation = repeatLoopGeneration
        scheduler.schedule(after: Double(delay) / 1_000_000_000) { [weak self] in
            self?.runRepeatPass(generation: generation)
        }
    }

    private func runRepeatPass(generation: UInt64) {
        guard repeatLoopScheduled, repeatLoopGeneration == generation else { return }
        fireRepeats(now: scheduler.uptimeNanoseconds)
        guard repeatLoopScheduled else { return }
        scheduleNextRepeatPass()
    }

    private func nextRepeatDelay(now: UInt64) -> UInt64? {
        guard !repeatEntries.isEmpty else { return nil }
        var soonest = UInt64.max
        for entry in repeatEntries.values {
            if entry.nextFire < soonest {
                soonest = entry.nextFire
            }
        }
        return soonest <= now ? 0 : (soonest - now)
    }

    private func fireRepeats(now: UInt64) {
        guard !repeatEntries.isEmpty else { return }
        var toRemove: [RepeatOwner] = []
        for key in repeatOrder {
            guard var entry = repeatEntries[key] else { continue }
            if !entry.token.isActive {
                toRemove.append(key)
                continue
            }
            if entry.nextFire <= now {
                entry.fire(entry.token)
                var next = entry.nextFire
                while next <= now {
                    next &+= entry.interval
                }
                entry.nextFire = next
                repeatEntries[key] = entry
            }
        }
        for key in toRemove {
            repeatEntries.removeValue(forKey: key)
        }
        repeatOrder.removeAll { repeatEntries[$0] == nil }
        if repeatEntries.isEmpty {
            repeatLoopScheduled = false
            repeatLoopGeneration &+= 1
        }
    }

    private func stopRepeat(for owner: RepeatOwner) {
        repeatOrder.removeAll { $0 == owner }
        if let entry = repeatEntries.removeValue(forKey: owner) {
            entry.token.deactivate()
            entry.stop()
        }
        if repeatEntries.isEmpty {
            repeatLoopScheduled = false
            repeatLoopGeneration &+= 1
        }
    }

    private func stopRepeat(for touchKey: TouchKey) {
        stopRepeat(for: .touch(touchKey))
    }

    private func stopGestureRepeat(bindingId: String, side: TrackpadSide?) {
        stopRepeat(for: .gesture(GestureRepeatKey(bindingId: bindingId, side: side)))
    }

    private func stopGestureRepeatIfNeeded(_ bindingId: String?, side: TrackpadSide?) {
        guard let bindingId else { return }
        stopGestureRepeat(bindingId: bindingId, side: side)
    }

    private func stopAllGestureRepeats(on side: TrackpadSide? = nil) {
        let owners = repeatEntries.keys.filter { owner in
            guard case let .gesture(key) = owner else { return false }
            guard let side else { return true }
            return key.side == side
        }
        for owner in owners {
            stopRepeat(for: owner)
        }
    }

    private func stopAllGestureRepeats() {
        stopAllGestureRepeats(on: nil)
    }

    private func canRepeatGestureAction(_ action: KeyAction) -> Bool {
        switch action.kind {
        case .volumeUp, .volumeDown, .volumeUpSmall, .volumeDownSmall,
             .brightnessUp, .brightnessDown, .brightnessUpSmall, .brightnessDownSmall:
            return true
        case .key:
            let code = CGKeyCode(action.keyCode)
            if code == CGKeyCode(kVK_Function) {
                return false
            }
            return code != CGKeyCode(kVK_Shift)
                && code != CGKeyCode(kVK_RightShift)
                && code != CGKeyCode(kVK_Control)
                && code != CGKeyCode(kVK_Option)
                && code != CGKeyCode(kVK_RightOption)
                && code != CGKeyCode(kVK_Command)
        default:
            return false
        }
    }

    @discardableResult
    private func tryBeginRepeatableGestureDispatch(
        bindingId: String?,
        action: KeyAction,
        side: TrackpadSide?
    ) -> Bool {
        guard let bindingId,
              let cadenceMs = gestureRepeatCadenceMsById[bindingId],
              cadenceMs > 0,
              canRepeatGestureAction(action) else {
            return false
        }

        let owner = RepeatOwner.gesture(GestureRepeatKey(bindingId: bindingId, side: side))
        if repeatEntries[owner] != nil {
            return true
        }

        let cadenceNs = UInt64(cadenceMs) * 1_000_000
        switch action.kind {
        case .key:
            let binding = KeyBinding(rect: .zero,
                normalizedRect: NormalizedRect(x: 0, y: 0, width: 0, height: 0),
                canvasSize: .zero, label: action.label,
                action: .key(code: CGKeyCode(action.keyCode), flags: CGEventFlags(rawValue: action.flags)),
                position: nil, side: side ?? .left, holdAction: nil)
            startRepeat(for: owner, binding: binding, initialDelay: cadenceNs, interval: cadenceNs)
            return true
        case .volumeUp:
            startSystemKeyRepeat(for: owner, systemKey: .volumeUp, initialDelay: cadenceNs, interval: cadenceNs)
            return true
        case .volumeDown:
            startSystemKeyRepeat(for: owner, systemKey: .volumeDown, initialDelay: cadenceNs, interval: cadenceNs)
            return true
        case .volumeUpSmall:
            startSystemKeyRepeat(for: owner, systemKey: .volumeUpSmall, initialDelay: cadenceNs, interval: cadenceNs)
            return true
        case .volumeDownSmall:
            startSystemKeyRepeat(for: owner, systemKey: .volumeDownSmall, initialDelay: cadenceNs, interval: cadenceNs)
            return true
        case .brightnessUp:
            startSystemKeyRepeat(for: owner, systemKey: .brightnessUp, initialDelay: cadenceNs, interval: cadenceNs)
            return true
        case .brightnessDown:
            startSystemKeyRepeat(for: owner, systemKey: .brightnessDown, initialDelay: cadenceNs, interval: cadenceNs)
            return true
        case .brightnessUpSmall:
            startSystemKeyRepeat(for: owner, systemKey: .brightnessUpSmall, initialDelay: cadenceNs, interval: cadenceNs)
            return true
        case .brightnessDownSmall:
            startSystemKeyRepeat(for: owner, systemKey: .brightnessDownSmall, initialDelay: cadenceNs, interval: cadenceNs)
            return true
        default:
            return false
        }
    }

    private func postKey(binding: KeyBinding, keyDown: Bool) {
        guard case let .key(code, flags) = binding.action else { return }
#if DEBUG
        onDebugBindingDetected(binding)
#endif
        dispatchService.postKey(
            code: code,
            flags: flags,
            keyDown: keyDown,
            sourceSequence: currentDispatchSourceSequence()
        )
    }

    private func releaseHeldKeys(stopVoiceDictation: Bool = false) {

        stopAllGestureRepeats()
        chordShiftActivationCount[.left] = 0
        chordShiftActivationCount[.right] = 0
        chordShiftLastContactTime[.left] = 0
        chordShiftLastContactTime[.right] = 0
        twoFingerHoldState[.left] = MultiFingerHoldState()
        twoFingerHoldState[.right] = MultiFingerHoldState()
        threeFingerHoldState[.left] = MultiFingerHoldState()
        threeFingerHoldState[.right] = MultiFingerHoldState()
        fourFingerHoldState[.left] = MultiFingerHoldState()
        fourFingerHoldState[.right] = MultiFingerHoldState()
        if chordShiftKeyDown {
            let shiftBinding = KeyBinding(
                rect: .zero,
                normalizedRect: NormalizedRect(x: 0, y: 0, width: 0, height: 0),
                canvasSize: .zero,
                label: "Shift",
                action: .key(code: CGKeyCode(kVK_Shift), flags: []),
                position: nil,
                side: .left,
                holdAction: nil
            )
            postKey(binding: shiftBinding, keyDown: false)
            chordShiftKeyDown = false
        }

        if stopVoiceDictation { stopVoiceDictationGesture() }
        resetGestureState(for: .left)
        resetGestureState(for: .right)
        intentState = IntentState()
        updateIntentDisplayIfNeeded()

    }

    private func distanceSquared(from start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        return dx * dx + dy * dy
    }

    private func extendTypingGrace(for side: TrackpadSide?, now: TimeInterval) {
        // Keyboard typing grace removed.
    }

    private func currentTime() -> TimeInterval {
        currentProcessingTimestamp ?? scheduler.now
    }

    private func notifyContactCounts() {
        guard contactFingerCountsBySide != lastReportedContactCounts else { return }
        lastReportedContactCounts = contactFingerCountsBySide
        onContactCountChanged(contactFingerCountsBySide)
    }

    private func invalidateBindingsCache() {
        // No keyboard binding caches.
    }

    func clearVisualCaches() {
        // No keyboard binding caches.
    }


}
