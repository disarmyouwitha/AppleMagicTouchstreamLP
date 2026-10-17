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
    private var isTypingEnabled = true
    private var keyboardModeEnabled = false
    private var holdRepeatEnabled = false
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
    private var holdMinDuration: TimeInterval = 0.2
    private var forceClickMin: Float = 0
    private var forceClickCap: Float = 255
    private var forceClickThreshold: Float = Float(GlassToKeySettings.forceClickThreshold)
    private var snapRadiusFraction: Float = 0
#if DEBUG
    nonisolated(unsafe) private static var snapAttemptCount: Int64 = 0
    nonisolated(unsafe) private static var snapAcceptedCount: Int64 = 0
    nonisolated(unsafe) private static var snapRejectedCount: Int64 = 0
    nonisolated(unsafe) private static var snapOffKeyCount: Int64 = 0
#endif
    private var contactFingerCountsBySide = SidePair(left: 0, right: 0)
    private var lastReportedContactCounts = SidePair(left: -1, right: -1)

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
    private var currentFrameDeviceIndex: Int = -1
    private var currentProcessingSequence: UInt64?
    private var captureFrameDiagnosticsEnabled = false
    private var currentFrameDecisions: [TouchKey: FrameDecisionRecord] = [:]
    private var unitsPerMillimeter: CGFloat = 1.0
    private var intentMoveThresholdSquared: CGFloat = 0
    private var intentVelocityThreshold: CGFloat = 0
    private var allowMouseTakeoverDuringTyping = false
    private var typingGraceDeadline: TimeInterval?
    private var typingGraceGeneration: UInt64 = 0


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
    private var voiceDictationGestureState = VoiceDictationGestureState()
    private var voiceGestureActive = false

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
        self.leftLayout = leftLayout
        self.rightLayout = rightLayout
        self.leftLabels = leftLabels
        self.rightLabels = rightLabels
        self.trackpadSize = trackpadSize
        self.trackpadWidthMm = max(1.0, trackpadWidthMm)
        updateIntentThresholdCache()
        invalidateBindingsCache()
    }

    func updateCustomButtons(_ buttons: [CustomButton]) {
        customButtons = buttons
        rebuildCustomButtonsIndex()
        invalidateBindingsCache()
    }

    func updateKeyMappings(_ actions: LayeredKeyMappings) {
        customKeyMappingsByLayer = actions
        invalidateBindingsCache()
    }

    func setKeymapEditingEnabled(_ enabled: Bool) {
        guard keymapEditingEnabled != enabled else { return }
        keymapEditingEnabled = enabled
    }

    func setPersistentLayer(_ layer: Int) {
        let clamped = KeyLayerConfig.clamped(layer)
        persistentLayer = clamped
        updateActiveLayer()
    }

    func updateHoldThreshold(_ seconds: TimeInterval) {
        // Removed from this experiment; retained for capture/profile compatibility.
    }

    func updateDragCancelDistance(_ distance: CGFloat) {
        // Removed from this experiment; retained for capture/profile compatibility.
    }

    func updateTypingGrace(_ milliseconds: Double) {
        // Removed from this experiment; retained for capture/profile compatibility.
    }

    func updateIntentMoveThreshold(_ millimeters: Double) {
        // Removed from this experiment; retained for capture/profile compatibility.
    }

    func updateIntentVelocityThreshold(_ millimetersPerSecond: Double) {
        // Removed from this experiment; retained for capture/profile compatibility.
    }

    func updateAllowMouseTakeover(_ enabled: Bool) {
        allowMouseTakeoverDuringTyping = enabled
    }

    func updateForceClickMin(_ grams: Double) {
        // Removed from this experiment; retained for capture/profile compatibility.
    }

    func updateForceClickCap(_ grams: Double) {
        // Removed from this experiment; retained for capture/profile compatibility.
    }

    func updateForceClickThreshold(_ grams: Double) {
        forceClickThreshold = Float(min(max(grams, 130), 500))
    }

    func updateHapticStrength(_ normalized: Double) {
        // Removed from this experiment; retained for capture/profile compatibility.
    }

    func updateSnapRadiusPercent(_ percent: Double) {
        // Removed from this experiment; retained for capture/profile compatibility.
    }

    func updateTapClickCadence(_ milliseconds: Double) {
        // Removed from this experiment; retained for capture/profile compatibility.
    }

    func updateGestureActions(_ actions: GestureActionSet) {
        // Removed from this experiment; retained for capture/profile compatibility.
    }

    func updateGestureRepeatCadenceMsById(_ cadenceById: [String: Int]?) {
        // Removed from this experiment; retained for capture/profile compatibility.
    }

    func updateKeyboardModeEnabled(_ enabled: Bool) {
        keyboardModeEnabled = false
    }

    func updateHoldRepeatEnabled(_ enabled: Bool) {
        holdRepeatEnabled = false
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

    private func touchDiagnosticPhase(for touchKey: TouchKey, state: TouchState?) -> RuntimeTouchDiagnosticPhase {
        if disqualifiedTouches.value(for: touchKey) != nil {
            return .disqualified
        }
        if releaseHandledTouches.value(for: touchKey) != nil {
            return .released
        }
        guard let state else { return .none }
        switch state {
        case .pending:
            return .pending
        case .active:
            return .active
        }
    }

    private func touchTiming(
        for touchKey: TouchKey,
        state: TouchState?,
        now: TimeInterval
    ) -> (dwellMilliseconds: Int?, maxDistance: Double?) {
        switch state {
        case let .pending(pending):
            return (
                Int((now - pending.startTime) * 1000.0),
                sqrt(Double(pending.maxDistanceSquared))
            )
        case let .active(active):
            return (
                Int((now - active.startTime) * 1000.0),
                sqrt(Double(active.maxDistanceSquared))
            )
        case nil:
            if let touchInfo = intentState.touches.value(for: touchKey) {
                return (
                    Int((now - touchInfo.startTime) * 1000.0),
                    sqrt(Double(touchInfo.maxDistanceSquared))
                )
            }
            return (nil, nil)
        }
    }

    private func makeFrameDiagnostic<Touches: RandomAccessCollection>(
        deviceIndex: Int,
        touches: Touches,
        bindings: BindingIndex,
        now: TimeInterval
    ) -> RuntimeFrameDiagnostic? where Touches.Element == OMSRawTouch {
        guard captureFrameDiagnosticsEnabled,
              let sequence = currentProcessingSequence else {
            return nil
        }

        var diagnostics: [RuntimeTouchDiagnostic] = []
        diagnostics.reserveCapacity(touches.count)

        for touch in touches {
            let touchKey = Self.makeTouchKey(deviceIndex: deviceIndex, id: touch.id)
            let state = touchStates.value(for: touchKey)
            let cachedPoint = framePointCache.value(for: touchKey)
            let point = cachedPoint ?? CGPoint(
                x: CGFloat(touch.posX) * trackpadSize.width,
                y: CGFloat(1.0 - touch.posY) * trackpadSize.height
            )
            let resolvedBinding = binding(at: point, index: bindings)
            let stateBinding = binding(from: state)
            let chosenBinding = stateBinding ?? resolvedBinding
            let decision = currentFrameDecisions[touchKey]
            let timing = touchTiming(for: touchKey, state: state, now: now)
            let dwellMilliseconds = timing.dwellMilliseconds
            let forceSatisfied: Bool
            if let chosenBinding, chosenBinding.holdForceThreshold > 0 {
                forceSatisfied = Float(touch.pressure) >= chosenBinding.holdForceThreshold
            } else if let dwellMilliseconds {
                forceSatisfied = Double(dwellMilliseconds) >= (holdMinDuration * 1000.0)
            } else {
                forceSatisfied = false
            }
            let phase = touchDiagnosticPhase(for: touchKey, state: state)
            let armed = {
                guard let stateBinding else { return false }
                guard let resolvedBinding else { return true }
                return bindingsMatch(stateBinding, resolvedBinding)
            }()
            let derivedReason: String? = if let decisionReason = decision?.reason {
                decisionReason
            } else if phase == .pending && !forceSatisfied {
                "belowHoldThreshold"
            } else if chosenBinding == nil {
                "missedTarget"
            } else {
                nil
            }
            let derivedDecision: RuntimeTouchDecisionOutcome = decision?.outcome
                ?? (phase == .pending ? .pending : .none)

            diagnostics.append(
                RuntimeTouchDiagnostic(
                    id: touch.id,
                    state: String(describing: touch.state),
                    side: touchKeySide(touchKey).map { $0 == .left ? "left" : "right" },
                    x: Double(touch.posX),
                    y: Double(touch.posY),
                    pressure: Double(touch.pressure),
                    phase: phase,
                    decision: derivedDecision,
                    reason: derivedReason,
                    target: decision?.target ?? chosenBinding.map(targetSnapshot(for:)),
                    armed: armed,
                    dwellMilliseconds: dwellMilliseconds,
                    maxDistance: timing.maxDistance,
                    forceThresholdSatisfied: forceSatisfied
                )
            )
        }

        return RuntimeFrameDiagnostic(
            sequence: sequence,
            timestamp: now,
            deviceIndex: deviceIndex,
            activeLayer: activeLayer,
            leftIntent: intentDisplayBySide.left.rawValue,
            rightIntent: intentDisplayBySide.right.rawValue,
            ingress: nil,
            touches: diagnostics
        )
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
        currentFrameDeviceIndex = frame.deviceIndex
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
        let leftTouches = isLeftDevice ? touches : OMSRawTouchBufferView.empty
        let rightTouches = isRightDevice ? touches : OMSRawTouchBufferView.empty
        let leftBindings = bindings(
            for: .left,
            layout: leftLayout,
            labels: leftLabels,
            canvasSize: trackpadSize
        )
        let rightBindings = bindings(
            for: .right,
            layout: rightLayout,
            labels: rightLabels,
            canvasSize: trackpadSize
        )
        let allowTypingGlobal = updateIntent(
            leftTouches: leftTouches,
            rightTouches: rightTouches,
            leftDeviceIndex: leftDeviceIndex,
            rightDeviceIndex: rightDeviceIndex,
            now: now,
            leftBindings: leftBindings,
            rightBindings: rightBindings
        )
        let allowTypingLeft = allowTypingGlobal
        let allowTypingRight = allowTypingGlobal
        if isLeftDevice {
            processTouches(
                leftTouches,
                deviceIndex: deviceIndex,
                bindings: leftBindings,
                layout: leftLayout,
                canvasSize: trackpadSize,
                isLeftSide: true,
                now: now,
                intentAllowsTyping: allowTypingLeft
            )
        }
        if isRightDevice {
            processTouches(
                rightTouches,
                deviceIndex: deviceIndex,
                bindings: rightBindings,
                layout: rightLayout,
                canvasSize: trackpadSize,
                isLeftSide: false,
                now: now,
                intentAllowsTyping: allowTypingRight
            )
        }
        notifyContactCounts()
        return makeFrameDiagnostic(
            deviceIndex: deviceIndex,
            touches: touches,
            bindings: isLeftDevice ? leftBindings : rightBindings,
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
        currentFrameDeviceIndex = frame.deviceIndex
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
        let leftTouches = isLeftDevice ? touches : []
        let rightTouches = isRightDevice ? touches : []
        let leftBindings = bindings(
            for: .left,
            layout: leftLayout,
            labels: leftLabels,
            canvasSize: trackpadSize
        )
        let rightBindings = bindings(
            for: .right,
            layout: rightLayout,
            labels: rightLabels,
            canvasSize: trackpadSize
        )
        let allowTypingGlobal = updateIntent(
            leftTouches: leftTouches,
            rightTouches: rightTouches,
            leftDeviceIndex: leftDeviceIndex,
            rightDeviceIndex: rightDeviceIndex,
            now: now,
            leftBindings: leftBindings,
            rightBindings: rightBindings
        )
        let allowTypingLeft = allowTypingGlobal
        let allowTypingRight = allowTypingGlobal
        if isLeftDevice {
            processTouches(
                leftTouches,
                deviceIndex: deviceIndex,
                bindings: leftBindings,
                layout: leftLayout,
                canvasSize: trackpadSize,
                isLeftSide: true,
                now: now,
                intentAllowsTyping: allowTypingLeft
            )
        }
        if isRightDevice {
            processTouches(
                rightTouches,
                deviceIndex: deviceIndex,
                bindings: rightBindings,
                layout: rightLayout,
                canvasSize: trackpadSize,
                isLeftSide: false,
                now: now,
                intentAllowsTyping: allowTypingRight
            )
        }
        notifyContactCounts()
        return makeFrameDiagnostic(
            deviceIndex: deviceIndex,
            touches: touches,
            bindings: isLeftDevice ? leftBindings : rightBindings,
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

    private func rebuildCustomButtonsIndex() {
        var mapping: [Int: [TrackpadSide: [CustomButton]]] = [:]
        for button in customButtons {
            var layerMap = mapping[button.layer] ?? [:]
            var sideButtons = layerMap[button.side] ?? []
            sideButtons.append(button)
            layerMap[button.side] = sideButtons
            mapping[button.layer] = layerMap
        }
        customButtonsByLayerAndSide = mapping
    }

    private func customButtons(for layer: Int, side: TrackpadSide) -> [CustomButton] {
        customButtonsByLayerAndSide[layer]?[side] ?? []
    }

    private func processTouches<Touches: RandomAccessCollection>(
        _ touches: Touches,
        deviceIndex: Int,
        bindings: BindingIndex,
        layout: Layout,
        canvasSize: CGSize,
        isLeftSide: Bool,
        now: TimeInterval,
        intentAllowsTyping: Bool
    ) where Touches.Element == OMSRawTouch {
        let side: TrackpadSide = isLeftSide ? .left : .right
        var present = Set<TouchKey>()
        contactFingerCountsBySide[side] = touches.filter { Self.isContactState($0.state) }.count
        for touch in touches {
            let key = Self.makeTouchKey(deviceIndex: deviceIndex, id: touch.id)
            let point = CGPoint(x: CGFloat(touch.posX) * canvasSize.width,
                                y: CGFloat(1 - touch.posY) * canvasSize.height)
            if Self.isContactState(touch.state) {
                present.insert(key)
                guard disqualifiedTouches.value(for: key) == nil else { continue }
                guard intentAllowsTyping, isTypingEnabled, !keymapEditingEnabled else {
                    disqualifyTouch(key, reason: .intentMouse)
                    continue
                }
                if activeTouch(for: key) == nil, let binding = binding(at: point, index: bindings) {
                    let modifier = modifierKey(for: binding)
                    setActiveTouch(key, ActiveTouch(binding: binding, layer: activeLayer,
                        startTime: now, startPoint: point, modifierKey: modifier,
                        isContinuousKey: false, holdBinding: nil, didHold: false,
                        maxDistanceSquared: 0, modifierEngaged: modifier != nil))
                    if let modifier { handleModifierDown(modifier, binding: binding) }
                }
            } else if Self.isTerminalReleaseState(touch.state) {
                if let active = removeActiveTouch(for: key) {
                    if let modifier = active.modifierKey {
                        handleModifierUp(modifier, binding: active.binding)
                    } else if intentAllowsTyping, isTypingEnabled, !keymapEditingEnabled,
                              active.binding.hitGeometry.contains(point) {
                        triggerBinding(active.binding, touchKey: key)
                    }
                }
                disqualifiedTouches.remove(key)
            }
        }
        // Empty frames also release modifiers; mouse intent stays latched until all up.
        var missing: [TouchKey] = []
        touchStates.forEach { key, _ in
            if Self.touchKeyDeviceIndex(key) == deviceIndex && !present.contains(key) { missing.append(key) }
        }
        for key in missing {
            if let active = removeActiveTouch(for: key), let modifier = active.modifierKey {
                handleModifierUp(modifier, binding: active.binding)
            }
        }
        var lifted: [TouchKey] = []
        disqualifiedTouches.forEach { key, _ in
            if Self.touchKeyDeviceIndex(key) == deviceIndex && !present.contains(key) { lifted.append(key) }
        }
        for key in lifted { disqualifiedTouches.remove(key) }
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

    private func activeTouch(for touchKey: TouchKey) -> ActiveTouch? {
        guard let state = touchStates.value(for: touchKey),
              case let .active(active) = state else {
            return nil
        }
        return active
    }

    private func setActiveTouch(_ touchKey: TouchKey, _ active: ActiveTouch) {
        touchStates.set(touchKey, .active(active))
    }

    private func removeActiveTouch(for touchKey: TouchKey) -> ActiveTouch? {
        guard let state = touchStates.value(for: touchKey),
              case let .active(active) = state else {
            return nil
        }
        touchStates.remove(touchKey)
        return active
    }

    private func makeBindings(
        layout: Layout,
        labels: [[String]],
        customButtons: [CustomButton],
        canvasSize: CGSize,
        side: TrackpadSide
    ) -> BindingIndex {
        let keyRects = layout.keyRects
        let keyRows = max(1, keyRects.count)
        let keyCols = max(1, keyRects.first?.count ?? 1)
        var keyGrid = BindingGrid(canvasSize: canvasSize, rows: keyRows, cols: keyCols)
        let useCustomGrid = customButtons.count > 4
        var customGrid = useCustomGrid
            ? BindingGrid(
                canvasSize: canvasSize,
                rows: max(4, keyRows),
                cols: max(4, keyCols)
            )
            : nil
        let estimatedKeys = keyRects.reduce(0) { $0 + $1.count }
        var snapBindings: [KeyBinding] = []
        var snapCentersX: [Float] = []
        var snapCentersY: [Float] = []
        var snapRadiusSq: [Float] = []
        snapBindings.reserveCapacity(estimatedKeys)
        snapCentersX.reserveCapacity(estimatedKeys)
        snapCentersY.reserveCapacity(estimatedKeys)
        snapRadiusSq.reserveCapacity(estimatedKeys)
        var customBindings: [KeyBinding] = []
        customBindings.reserveCapacity(customButtons.count)

        @inline(__always)
        func appendSnapBinding(_ binding: KeyBinding) {
            guard case .key = binding.action else { return }
            snapBindings.append(binding)
            snapCentersX.append(Float(binding.hitGeometry.centerX))
            snapCentersY.append(Float(binding.hitGeometry.centerY))
            let diameter = min(binding.hitGeometry.halfWidth, binding.hitGeometry.halfHeight) * 2
            let radius = Float(diameter) * snapRadiusFraction
            snapRadiusSq.append(radius * radius)
        }

        let fallbackNormalized = NormalizedRect(x: 0, y: 0, width: 0, height: 0)
        for row in 0..<keyRects.count {
            let rowRects = keyRects[row]
            for col in 0..<rowRects.count {
                let rect = rowRects[col]
                guard row < labels.count,
                      col < labels[row].count else { continue }
                let label = labels[row][col]
                let position = GridKeyPosition(side: side, row: row, column: col)
                let normalizedRect = layout.normalizedRect(for: position) ?? fallbackNormalized
                guard let binding = bindingForLabel(
                    label,
                    rect: rect,
                    normalizedRect: normalizedRect,
                    position: position,
                    layout: layout,
                    canvasSize: canvasSize
                ) else {
                    continue
                }
                keyGrid.insert(binding)
                appendSnapBinding(binding)
            }
        }

        for button in customButtons {
            let rect = button.rect.rect(in: canvasSize)
            let action: KeyBindingAction
            switch button.action.kind {
            case .key:
                action = .key(
                    code: CGKeyCode(button.action.keyCode),
                    flags: CGEventFlags(rawValue: button.action.flags)
                )
            case .appLaunch:
                action = .appLaunch(button.action.label)
            case .leftClick:
                action = .leftClick
            case .doubleClick:
                action = .doubleClick
            case .rightClick:
                action = .rightClick
            case .middleClick:
                action = .middleClick
            case .volumeUp:
                action = .volumeUp
            case .volumeDown:
                action = .volumeDown
            case .volumeUpSmall:
                action = .volumeUpSmall
            case .volumeDownSmall:
                action = .volumeDownSmall
            case .brightnessUp:
                action = .brightnessUp
            case .brightnessDown:
                action = .brightnessDown
            case .brightnessUpSmall:
                action = .brightnessUpSmall
            case .brightnessDownSmall:
                action = .brightnessDownSmall
            case .voice:
                action = .voice
            case .typingToggle:
                action = .typingToggle
            case .chordalShift:
                action = .chordalShift
            case .gestureTwoFingerTap:
                action = .gestureTwoFingerTap
            case .gestureThreeFingerTap:
                action = .gestureThreeFingerTap
            case .gestureFourFingerHold:
                action = .gestureFourFingerHold
            case .gestureInnerCornersHold:
                action = .gestureInnerCornersHold
            case .gestureFiveFingerSwipeLeft:
                action = .gestureFiveFingerSwipeLeft
            case .gestureFiveFingerSwipeRight:
                action = .gestureFiveFingerSwipeRight
            case .layerMomentary:
                action = .layerMomentary(KeyLayerConfig.clamped(button.action.layer ?? 1))
            case .layerToggle:
                action = .layerToggle(KeyLayerConfig.clamped(button.action.layer ?? 1))
            case .none:
                action = .none
            }
            let binding = KeyBinding(
                rect: rect,
                normalizedRect: button.rect,
                canvasSize: canvasSize,
                label: button.action.label,
                action: action,
                position: nil,
                customButtonID: button.id,
                side: button.side,
                holdAction: button.hold,
                holdForceThreshold: button.hold == nil ? 0 : Float(button.holdForceThreshold)
            )
            customBindings.append(binding)
            customGrid?.insert(binding)
        }

        return BindingIndex(
            keyGrid: keyGrid,
            customGrid: customGrid,
            customBindings: customBindings,
            snapBindings: snapBindings,
            snapCentersX: snapCentersX,
            snapCentersY: snapCentersY,
            snapRadiusSq: snapRadiusSq
        )
    }

    private func bindingForLabel(
        _ label: String,
        rect: CGRect,
        normalizedRect: NormalizedRect,
        position: GridKeyPosition,
        layout: Layout,
        canvasSize: CGSize
    ) -> KeyBinding? {
        guard let action = keyAction(for: position, label: label) else { return nil }
        let holdAction = layout.allowHoldBindings
            ? holdAction(for: position, label: label)
            : nil
        let holdForceThreshold = layout.allowHoldBindings
            ? holdForceThreshold(for: position)
            : 0
        return makeBinding(
            for: action,
            rect: rect,
            normalizedRect: normalizedRect,
            canvasSize: canvasSize,
            position: position,
            side: position.side,
            holdAction: holdAction,
            holdForceThreshold: holdForceThreshold
        )
    }

    private func keyAction(for position: GridKeyPosition, label: String) -> KeyAction? {
        let layerMappings = customKeyMappingsByLayer[activeLayer] ?? [:]
        if let mapping = layerMappings[position.storageKey] {
            return mapping.primary
        }
        return KeyActionCatalog.action(for: label)
    }

    private func holdAction(for position: GridKeyPosition?, label: String) -> KeyAction? {
        let layerMappings = customKeyMappingsByLayer[activeLayer] ?? [:]
        if let position, let mapping = layerMappings[position.storageKey] {
            return mapping.hold
        }
        return KeyActionCatalog.holdAction(for: label)
    }

    private func holdForceThreshold(for position: GridKeyPosition?) -> Float {
        guard let position else { return 0 }
        let layerMappings = customKeyMappingsByLayer[activeLayer] ?? [:]
        guard let mapping = layerMappings[position.storageKey], mapping.hold != nil else {
            return 0
        }
        return Float(mapping.holdForceThreshold)
    }

    private func makeBinding(
        for action: KeyAction,
        rect: CGRect,
        normalizedRect: NormalizedRect,
        canvasSize: CGSize,
        position: GridKeyPosition?,
        customButtonID: UUID? = nil,
        side: TrackpadSide,
        holdAction: KeyAction? = nil,
        holdForceThreshold: Float = 0
    ) -> KeyBinding? {
        switch action.kind {
        case .key:
            let flags = CGEventFlags(rawValue: action.flags)
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .key(code: CGKeyCode(action.keyCode), flags: flags),
                position: position,
                customButtonID: customButtonID,
                side: side,
                holdAction: holdAction,
                holdForceThreshold: holdForceThreshold
            )
        case .appLaunch:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .appLaunch(action.label),
                position: position,
                customButtonID: customButtonID,
                side: side,
                holdAction: holdAction,
                holdForceThreshold: holdForceThreshold
            )
        case .leftClick:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .leftClick,
                position: position,
                customButtonID: customButtonID,
                side: side,
                holdAction: holdAction,
                holdForceThreshold: holdForceThreshold
            )
        case .doubleClick:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .doubleClick,
                position: position,
                customButtonID: customButtonID,
                side: side,
                holdAction: holdAction,
                holdForceThreshold: holdForceThreshold
            )
        case .rightClick:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .rightClick,
                position: position,
                customButtonID: customButtonID,
                side: side,
                holdAction: holdAction,
                holdForceThreshold: holdForceThreshold
            )
        case .middleClick:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .middleClick,
                position: position,
                customButtonID: customButtonID,
                side: side,
                holdAction: holdAction,
                holdForceThreshold: holdForceThreshold
            )
        case .volumeUp:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .volumeUp,
                position: position,
                side: side,
                holdAction: holdAction,
                holdForceThreshold: holdForceThreshold
            )
        case .volumeDown:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .volumeDown,
                position: position,
                side: side,
                holdAction: holdAction,
                holdForceThreshold: holdForceThreshold
            )
        case .volumeUpSmall:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .volumeUpSmall,
                position: position,
                side: side,
                holdAction: holdAction,
                holdForceThreshold: holdForceThreshold
            )
        case .volumeDownSmall:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .volumeDownSmall,
                position: position,
                side: side,
                holdAction: holdAction,
                holdForceThreshold: holdForceThreshold
            )
        case .brightnessUp:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .brightnessUp,
                position: position,
                side: side,
                holdAction: holdAction,
                holdForceThreshold: holdForceThreshold
            )
        case .brightnessDown:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .brightnessDown,
                position: position,
                side: side,
                holdAction: holdAction,
                holdForceThreshold: holdForceThreshold
            )
        case .brightnessUpSmall:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .brightnessUpSmall,
                position: position,
                side: side,
                holdAction: holdAction,
                holdForceThreshold: holdForceThreshold
            )
        case .brightnessDownSmall:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .brightnessDownSmall,
                position: position,
                side: side,
                holdAction: holdAction,
                holdForceThreshold: holdForceThreshold
            )
        case .voice:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .voice,
                position: position,
                side: side,
                holdAction: holdAction,
                holdForceThreshold: holdForceThreshold
            )
        case .typingToggle:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .typingToggle,
                position: position,
                side: side,
                holdAction: holdAction,
                holdForceThreshold: holdForceThreshold
            )
        case .chordalShift:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .chordalShift,
                position: position,
                side: side,
                holdAction: holdAction,
                holdForceThreshold: holdForceThreshold
            )
        case .gestureTwoFingerTap:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .gestureTwoFingerTap,
                position: position,
                side: side,
                holdAction: holdAction,
                holdForceThreshold: holdForceThreshold
            )
        case .gestureThreeFingerTap:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .gestureThreeFingerTap,
                position: position,
                side: side,
                holdAction: holdAction,
                holdForceThreshold: holdForceThreshold
            )
        case .gestureFourFingerHold:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .gestureFourFingerHold,
                position: position,
                side: side,
                holdAction: holdAction,
                holdForceThreshold: holdForceThreshold
            )
        case .gestureInnerCornersHold:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .gestureInnerCornersHold,
                position: position,
                side: side,
                holdAction: holdAction,
                holdForceThreshold: holdForceThreshold
            )
        case .gestureFiveFingerSwipeLeft:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .gestureFiveFingerSwipeLeft,
                position: position,
                side: side,
                holdAction: holdAction,
                holdForceThreshold: holdForceThreshold
            )
        case .gestureFiveFingerSwipeRight:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .gestureFiveFingerSwipeRight,
                position: position,
                side: side,
                holdAction: holdAction,
                holdForceThreshold: holdForceThreshold
            )
        case .layerMomentary:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .layerMomentary(KeyLayerConfig.clamped(action.layer ?? 1)),
                position: position,
                side: side,
                holdAction: holdAction,
                holdForceThreshold: holdForceThreshold
            )
        case .layerToggle:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .layerToggle(KeyLayerConfig.clamped(action.layer ?? 1)),
                position: position,
                side: side,
                holdAction: holdAction,
                holdForceThreshold: holdForceThreshold
            )
        case .none:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .none,
                position: position,
                side: side,
                holdAction: holdAction,
                holdForceThreshold: holdForceThreshold
            )
        }
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

    private static func isTerminalReleaseState(_ state: OMSState) -> Bool {
        switch state {
        case .breaking, .leaving, .notTouching:
            return true
        default:
            return false
        }
    }

    private func isChordShiftActive(on side: TrackpadSide) -> Bool {
        chordShiftActivationCount[side] > 0
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
        // Deliberately small baseline: key landing = typing; 3 mm travel = mouse.
        // No grace, velocity tuning, tap/hold timing, snapping, or multi-finger gestures.
        var state = intentState
        let wasMouse: Bool = if case .mouseActive = state.mode { true } else { false }
        var present = Set<TouchKey>()
        var mouse = false
        var onKey = false
        bindingCacheBySide[.left].removeAll(keepingCapacity: true)
        bindingCacheBySide[.right].removeAll(keepingCapacity: true)
        func inspect(_ touch: OMSRawTouch, device: Int, side: TrackpadSide, index: BindingIndex) {
            let key = Self.makeTouchKey(deviceIndex: device, id: touch.id)
            let active = Self.isContactState(touch.state)
            guard active || (Self.isTerminalReleaseState(touch.state) && state.touches.value(for: key) != nil) else { return }
            if active { present.insert(key) }
            let point = CGPoint(x: CGFloat(touch.posX) * trackpadSize.width,
                                y: CGFloat(1 - touch.posY) * trackpadSize.height)
            if let binding = binding(at: point, index: index) {
                onKey = true
                bindingCacheBySide[side].set(key, binding)
            }
            if var info = state.touches.value(for: key) {
                info.maxDistanceSquared = max(info.maxDistanceSquared, distanceSquared(from: info.startPoint, to: point))
                state.touches.set(key, info)
                mouse = mouse || info.maxDistanceSquared > pow(3 * unitsPerMillimeter, 2)
            } else {
                state.touches.set(key, IntentTouchInfo(startPoint: point, startTime: now,
                    lastPoint: point, lastTime: now, maxDistanceSquared: 0))
            }
        }
        if let device = leftDeviceIndex { for touch in leftTouches { inspect(touch, device: device, side: .left, index: leftBindings) } }
        if let device = rightDeviceIndex { for touch in rightTouches { inspect(touch, device: device, side: .right, index: rightBindings) } }
        // Frames arrive per device; preserve contacts from the other pad.
        let incomingDevice = currentFrameDeviceIndex
        var removed: [TouchKey] = []
        state.touches.forEach { key, _ in
            if Self.touchKeyDeviceIndex(key) == incomingDevice && !present.contains(key) { removed.append(key) }
        }
        for key in removed { state.touches.remove(key) }
        if state.touches.isEmpty { state.mode = .idle }
        else if mouse { state.mode = .mouseActive }
        else if case .mouseActive = state.mode { /* latch until all up */ }
        else if onKey { state.mode = .typingCommitted(untilAllUp: true) }
        else { state.mode = .mouseActive }
        intentState = state
        updateIntentDisplayIfNeeded()
        if mouse || wasMouse { return false }
        if case .mouseActive = state.mode { return false }
        return isTypingEnabled
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

    private var trackpadHeightMillimeters: CGFloat {
        guard unitsPerMillimeter > 0 else { return 1.0 }
        return max(1.0, trackpadSize.height / unitsPerMillimeter)
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
        let updated = !isTypingEnabled
        if updated != isTypingEnabled {
            isTypingEnabled = updated
            onTypingEnabledChanged(updated)
        }
        if !isTypingEnabled {
            releaseHeldKeys(stopVoiceDictation: false)
        }
    }

    private func modifierKey(for binding: KeyBinding) -> ModifierKey? {
        guard case let .key(code, _) = binding.action else { return nil }
        if code == CGKeyCode(kVK_Shift) {
            return .shift
        }
        if code == CGKeyCode(kVK_Control) {
            return .control
        }
        if code == CGKeyCode(kVK_Option) {
            return .option
        }
        if code == CGKeyCode(kVK_RightOption) {
            return .rightOption
        }
        if code == CGKeyCode(kVK_Command) {
            return .command
        }
        return nil
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

    @discardableResult

    private func bindingsMatch(_ lhs: KeyBinding, _ rhs: KeyBinding) -> Bool {
        if lhs.position != nil || rhs.position != nil {
            return lhs.position == rhs.position
        }
        return lhs.side == rhs.side
            && lhs.normalizedRect == rhs.normalizedRect
            && lhs.label == rhs.label
    }

    private func triggerBinding(
        _ binding: KeyBinding,
        touchKey: TouchKey?,
        dispatchInfo: DispatchInfo? = nil,
        pressure: Float? = nil
    ) {
        if let touchKey {
            recordFrameDecision(
                touchKey,
                outcome: .dispatched,
                reason: dispatchInfo?.kind == .hold ? "hold" : "tap",
                binding: binding
            )
        }
        switch binding.action {
        case let .appLaunch(actionLabel):
            dispatchService.postAppLaunch(
                actionLabel,
                sourceSequence: currentDispatchSourceSequence()
            )
        case let .layerMomentary(layer):
            guard let touchKey else { return }
            momentaryLayerTouches.set(touchKey, layer)
            updateActiveLayer()
        case let .layerToggle(layer):
            toggleLayer(to: layer)
        case .typingToggle:
            toggleTypingMode()
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
            dispatchService.postVolumeUp(sourceSequence: currentDispatchSourceSequence())
        case .volumeDown:
            dispatchService.postVolumeDown(sourceSequence: currentDispatchSourceSequence())
        case .volumeUpSmall:
            dispatchService.postVolumeUpSmall(sourceSequence: currentDispatchSourceSequence())
        case .volumeDownSmall:
            dispatchService.postVolumeDownSmall(sourceSequence: currentDispatchSourceSequence())
        case .brightnessUp:
            dispatchService.postBrightnessUp(sourceSequence: currentDispatchSourceSequence())
        case .brightnessDown:
            dispatchService.postBrightnessDown(sourceSequence: currentDispatchSourceSequence())
        case .brightnessUpSmall:
            dispatchService.postBrightnessUpSmall(sourceSequence: currentDispatchSourceSequence())
        case .brightnessDownSmall:
            dispatchService.postBrightnessDownSmall(sourceSequence: currentDispatchSourceSequence())
        case .voice:
            toggleVoiceDictationSession()
        case .chordalShift:
            break
        case .gestureTwoFingerTap:
            break
        case .gestureThreeFingerTap:
            break
        case .gestureFourFingerHold:
            break
        case .gestureInnerCornersHold:
            break
        case .gestureFiveFingerSwipeLeft:
            break
        case .gestureFiveFingerSwipeRight:
            break
        case .none:
            break
        case .key:
            sendKey(
                binding: binding,
                touchKey: touchKey,
                dispatchInfo: dispatchInfo,
                pressure: pressure
            )
        }
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

    @discardableResult


    private func handleModifierDown(_ modifierKey: ModifierKey, binding: KeyBinding) {
        switch modifierKey {
        case .shift:
            if leftShiftTouchCount == 0 {
                playHapticIfNeeded(on: binding.side)
                postKey(binding: binding, keyDown: true)
            }
            leftShiftTouchCount += 1
        case .control:
            if controlTouchCount == 0 {
                playHapticIfNeeded(on: binding.side)
                postKey(binding: binding, keyDown: true)
            }
            controlTouchCount += 1
        case .option:
            if leftOptionTouchCount == 0 {
                playHapticIfNeeded(on: binding.side)
                postKey(binding: binding, keyDown: true)
            }
            leftOptionTouchCount += 1
        case .rightOption:
            if rightOptionTouchCount == 0 {
                playHapticIfNeeded(on: binding.side)
                postKey(binding: binding, keyDown: true)
            }
            rightOptionTouchCount += 1
        case .command:
            if commandTouchCount == 0 {
                playHapticIfNeeded(on: binding.side)
                postKey(binding: binding, keyDown: true)
            }
            commandTouchCount += 1
        }
    }

    private func handleModifierUp(_ modifierKey: ModifierKey, binding: KeyBinding) {
        switch modifierKey {
        case .shift:
            leftShiftTouchCount = max(0, leftShiftTouchCount - 1)
            if leftShiftTouchCount == 0 {
                postKey(binding: binding, keyDown: false)
            }
        case .control:
            controlTouchCount = max(0, controlTouchCount - 1)
            if controlTouchCount == 0 {
                postKey(binding: binding, keyDown: false)
            }
        case .option:
            leftOptionTouchCount = max(0, leftOptionTouchCount - 1)
            if leftOptionTouchCount == 0 {
                postKey(binding: binding, keyDown: false)
            }
        case .rightOption:
            rightOptionTouchCount = max(0, rightOptionTouchCount - 1)
            if rightOptionTouchCount == 0 {
                postKey(binding: binding, keyDown: false)
            }
        case .command:
            commandTouchCount = max(0, commandTouchCount - 1)
            if commandTouchCount == 0 {
                postKey(binding: binding, keyDown: false)
            }
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
        if leftShiftTouchCount > 0 {
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
            leftShiftTouchCount = 0
        }
        if controlTouchCount > 0 {
            let controlBinding = KeyBinding(
                rect: .zero,
                normalizedRect: NormalizedRect(x: 0, y: 0, width: 0, height: 0),
                canvasSize: .zero,
                label: "Ctrl",
                action: .key(code: CGKeyCode(kVK_Control), flags: []),
                position: nil,
                side: .left,
                holdAction: nil
            )
            postKey(binding: controlBinding, keyDown: false)
            controlTouchCount = 0
        }
        if leftOptionTouchCount > 0 {
            let optionBinding = KeyBinding(
                rect: .zero,
                normalizedRect: NormalizedRect(x: 0, y: 0, width: 0, height: 0),
                canvasSize: .zero,
                label: "Option",
                action: .key(code: CGKeyCode(kVK_Option), flags: KeyboardModifierFlags.leftOption),
                position: nil,
                side: .left,
                holdAction: nil
            )
            postKey(binding: optionBinding, keyDown: false)
            leftOptionTouchCount = 0
        }
        if rightOptionTouchCount > 0 {
            let optionBinding = KeyBinding(
                rect: .zero,
                normalizedRect: NormalizedRect(x: 0, y: 0, width: 0, height: 0),
                canvasSize: .zero,
                label: KeyActionCatalog.altGrLabel,
                action: .key(code: CGKeyCode(kVK_RightOption), flags: KeyboardModifierFlags.rightOption),
                position: nil,
                side: .left,
                holdAction: nil
            )
            postKey(binding: optionBinding, keyDown: false)
            rightOptionTouchCount = 0
        }
        if commandTouchCount > 0 {
            let commandBinding = KeyBinding(
                rect: .zero,
                normalizedRect: NormalizedRect(x: 0, y: 0, width: 0, height: 0),
                canvasSize: .zero,
                label: "Cmd",
                action: .key(code: CGKeyCode(kVK_Command), flags: []),
                position: nil,
                side: .left,
                holdAction: nil
            )
            postKey(binding: commandBinding, keyDown: false)
            commandTouchCount = 0
        }

        var activeTouchKeys: [TouchKey] = []
        touchStates.forEach { key, state in
            if case .active = state {
                activeTouchKeys.append(key)
            }
        }
        touchStates.removeAll()
        disqualifiedTouches.removeAll()
        releaseHandledTouches.removeAll()
        toggleTouchStarts.removeAll()
        layerToggleTouchStarts.removeAll()
        momentaryLayerTouches.removeAll()
        touchInitialContactPoint.removeAll()
        typingGraceDeadline = nil
        typingGraceGeneration &+= 1
        updateActiveLayer()
        intentState = IntentState()
        updateIntentDisplayIfNeeded()
    }

    private func disqualifyTouch(_ touchKey: TouchKey, reason: DisqualifyReason) {
        if let active = removeActiveTouch(for: touchKey), let modifier = active.modifierKey {
            handleModifierUp(modifier, binding: active.binding)
        }
        disqualifiedTouches.set(touchKey, true)
        recordFrameDecision(touchKey, outcome: .rejected, reason: reason.rawValue)
    }

    private func distanceSquared(from start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        return dx * dx + dy * dy
    }

    private func toggleLayer(to layer: Int) {
        let clamped = KeyLayerConfig.clamped(layer)
        if persistentLayer == clamped {
            persistentLayer = KeyLayerConfig.baseLayer
        } else {
            persistentLayer = clamped
        }
        updateActiveLayer()
    }

    private func extendTypingGrace(for side: TrackpadSide?, now: TimeInterval) {
        // No typing grace in the keyboard baseline.
    }

    private func updateActiveLayer() {
        let previousMomentaryLayer = lastMomentaryLayer
        let currentMomentaryLayer = maxMomentaryLayer()
        let resolvedLayer = currentMomentaryLayer ?? persistentLayer
        if activeLayer != resolvedLayer {
            activeLayer = resolvedLayer
            invalidateBindingsCache()
            onActiveLayerChanged(resolvedLayer)
        }
        lastMomentaryLayer = currentMomentaryLayer
        if previousMomentaryLayer != nil, currentMomentaryLayer == nil {
            releaseTouchesFromMomentaryLayer(previousMomentaryLayer!)
        }
    }

    private func maxMomentaryLayer() -> Int? {
        var maxLayer: Int?
        momentaryLayerTouches.forEachLayer { layer in
            if let current = maxLayer {
                if layer > current {
                    maxLayer = layer
                }
            } else {
                maxLayer = layer
            }
        }
        return maxLayer
    }

    private func releaseTouchesFromMomentaryLayer(_ layer: Int) {
        guard layer != persistentLayer else { return }
        var toDisqualify: [TouchKey] = []
        touchStates.forEach { key, state in
            let stateLayer: Int
            switch state {
            case let .active(active):
                stateLayer = active.layer
            case let .pending(pending):
                stateLayer = pending.layer
            }
            if stateLayer == layer {
                toDisqualify.append(key)
            }
        }
        for key in toDisqualify {
            disqualifyTouch(key, reason: .momentaryLayerCancelled)
        }
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
        bindingsGeneration &+= 1
    }

    func clearVisualCaches() {
        bindingsCache = SidePair<BindingIndex?>(left: nil, right: nil)
        bindingsCacheLayer = -1
        bindingsGeneration &+= 1
        bindingsGenerationBySide = SidePair(left: -1, right: -1)
    }

    private func bindings(
        for side: TrackpadSide,
        layout: Layout,
        labels: [[String]],
        canvasSize: CGSize
    ) -> BindingIndex {
        if bindingsCacheLayer != activeLayer {
            bindingsCacheLayer = activeLayer
            invalidateBindingsCache()
        }
        let currentGeneration = bindingsGenerationBySide[side]
        if currentGeneration != bindingsGeneration || bindingsCache[side] == nil {
            bindingsCache[side] = makeBindings(
                layout: layout,
                labels: labels,
                customButtons: customButtons(for: activeLayer, side: side),
                canvasSize: canvasSize,
                side: side
            )
            bindingsGenerationBySide[side] = bindingsGeneration
        }
        return bindingsCache[side] ?? BindingIndex(
            keyGrid: BindingGrid(canvasSize: .zero, rows: 1, cols: 1),
            customGrid: nil,
            customBindings: [],
            snapBindings: [],
            snapCentersX: [],
            snapCentersY: [],
            snapRadiusSq: []
        )
    }
}
