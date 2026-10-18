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
        case typingCommitted(untilAllUp: Bool)
        case mouseActive
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
        var typingGraceSeconds: TimeInterval = 0.12
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

    private enum RepeatOwner: Hashable {
        case touch(TouchKey)
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
    private let dispatchService: DispatchService
    private let onActiveLayerChanged: @Sendable (Int) -> Void
    private let onDebugBindingDetected: @Sendable (KeyBinding) -> Void
    private let onContactCountChanged: @Sendable (SidePair<Int>) -> Void
    private let onIntentStateChanged: @Sendable (SidePair<IntentDisplay>) -> Void
    private let isDragDetectionEnabled = false
    private var currentFrameDeviceIndex = -1
    private var currentFrameAllowsTyping = true
    private var isListening = false
    private var keymapEditingEnabled = false
    private let isTypingEnabled = true
    private var keyboardModeEnabled = false
    private var holdRepeatEnabled = false
    private var activeLayer: Int = 0
    private var persistentLayer: Int = 0
    private var leftDeviceIndex: Int?
    private var rightDeviceIndex: Int?
    private var hapticStrength: Double = 0
    private static let hapticMinIntervalNanos: UInt64 = 20_000_000
    private var lastHapticTimeBySide = SidePair<UInt64?>(repeating: nil)
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
    private let snapAmbiguityRatio: Float = 1.15
#if DEBUG
    nonisolated(unsafe) private static var snapAttemptCount: Int64 = 0
    nonisolated(unsafe) private static var snapAcceptedCount: Int64 = 0
    nonisolated(unsafe) private static var snapRejectedCount: Int64 = 0
    nonisolated(unsafe) private static var snapOffKeyCount: Int64 = 0
#endif
    private var contactFingerCountsBySide = SidePair(left: 0, right: 0)
    private struct ContactCountCache {
        var actual: Int
        var displayed: Int
        var timestamp: TimeInterval
    }
    private var contactCountCache = SidePair<ContactCountCache?>(left: nil, right: nil)
    private let contactCountHoldDuration: TimeInterval = 0.06
    private var touchRemovalBuffer: [TouchKey] = []
    private var lastReportedContactCounts = SidePair(left: -1, right: -1)

    private let repeatInitialDelay: UInt64 = 350_000_000
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
    private var unitsPerMillimeter: CGFloat = 1.0
    private var typingGraceDeadline: TimeInterval?
    private var typingGraceGeneration: UInt64 = 0

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
        voiceSessionChanged: @Sendable @escaping (Bool) -> Void = { _ in },
        onTypingEnabledChanged: @Sendable @escaping (Bool) -> Void,
        onActiveLayerChanged: @Sendable @escaping (Int) -> Void,
        onDebugBindingDetected: @Sendable @escaping (KeyBinding) -> Void,
        onContactCountChanged: @Sendable @escaping (SidePair<Int>) -> Void,
        onIntentStateChanged: @Sendable @escaping (SidePair<IntentDisplay>) -> Void,
        onVoiceGestureChanged: @Sendable @escaping (Bool) -> Void
    ) {
        self.scheduler = scheduler ?? LiveTouchEngineScheduler(queue: executionQueue)
        self.dispatchService = dispatchService
        self.onActiveLayerChanged = onActiveLayerChanged
        self.onDebugBindingDetected = onDebugBindingDetected
        self.onContactCountChanged = onContactCountChanged
        self.onIntentStateChanged = onIntentStateChanged
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
        updatePhysicalScale()
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
        let clamped = max(0, seconds)
        holdMinDuration = clamped
        tapMaxDuration = max(clamped, minimumTapMaxDuration)
    }

    func updateDragCancelDistance(_ distance: CGFloat) {
        // Legacy profile field: this experiment uses fixed recognition thresholds.
    }

    func updateTypingGrace(_ milliseconds: Double) {
        let clampedMs = max(0, milliseconds)
        intentConfig.typingGraceSeconds = clampedMs / 1000.0
    }

    func updateIntentMoveThreshold(_ millimeters: Double) {
        // Legacy profile field: this experiment uses fixed recognition thresholds.
    }

    func updateIntentVelocityThreshold(_ millimetersPerSecond: Double) {
        // Legacy profile field: this experiment uses fixed recognition thresholds.
    }

    func updateAllowMouseTakeover(_ enabled: Bool) {
        // Legacy configuration: the temporary classifier has fixed ownership.
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
        hapticStrength = normalized.isFinite ? min(max(normalized, 0), 1) : 0
    }

    func updateSnapRadiusPercent(_ percent: Double) {
        let clamped = min(max(percent, 0.0), 100.0)
        snapRadiusFraction = Float(clamped / 100.0)
        invalidateBindingsCache()
    }

    func updateTapClickCadence(_ milliseconds: Double) {
        // Legacy profile field: this experiment uses fixed recognition thresholds.
    }

    func updateGestureRecognitionEnabled(_ enabled: Bool) {
        // Legacy replay configuration: intentionally ignored. No GTK recognizer or effects exist.
    }

    func updateGestureActions(_ actions: GestureActionSet) {
        // Legacy replay configuration: intentionally ignored. No GTK recognizer or effects exist.
    }

    func updateGestureRepeatCadenceMsById(_ cadenceById: [String: Int]?) {
        // Legacy replay configuration: intentionally ignored. No GTK recognizer or effects exist.
    }

    func updateKeyboardModeEnabled(_ enabled: Bool) {
        keyboardModeEnabled = enabled
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
        guard isLeftDevice || isRightDevice else { return nil }
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
        currentFrameAllowsTyping = allowTypingGlobal
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
        guard isLeftDevice || isRightDevice else { return nil }
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
        currentFrameAllowsTyping = allowTypingGlobal
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
        lastHapticTimeBySide = SidePair(repeating: nil)
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
        #if DEBUG
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval(
            "ProcessTouches",
            id: signpostID
        )
        defer { signposter.endInterval("ProcessTouches", state) }
        #endif
        let dragCancelDistanceSquared = dragCancelDistance * dragCancelDistance
        let side: TrackpadSide = isLeftSide ? .left : .right
        var contactCount = 0
        var frameTouchKeys = TouchTable<Bool>(minimumCapacity: max(16, touches.count * 2))
        for touch in touches {
            if Self.isContactState(touch.state) {
                contactCount += 1
            }
            let touchKey = Self.makeTouchKey(deviceIndex: deviceIndex, id: touch.id)
            frameTouchKeys.set(touchKey, true)
            let point: CGPoint
            if let cachedPoint = framePointCache.value(for: touchKey) {
                point = cachedPoint
            } else {
                let computed = CGPoint(
                    x: CGFloat(touch.posX) * canvasSize.width,
                    y: CGFloat(1.0 - touch.posY) * canvasSize.height
                )
                framePointCache.set(touchKey, computed)
                point = computed
            }
            if Self.isContactState(touch.state) {
                releaseHandledTouches.remove(touchKey)
            } else if Self.isTerminalReleaseState(touch.state),
                      releaseHandledTouches.value(for: touchKey) != nil {
                touchInitialContactPoint.remove(touchKey)
                clearPeakPressure(for: touchKey)
                continue
            }
            var bindingAtPoint: KeyBinding?
            var didResolveBinding = false
            @inline(__always)
            func resolveBinding() -> KeyBinding? {
                if !didResolveBinding {
                    didResolveBinding = true
                    bindingAtPoint = bindingCacheBySide[side].value(for: touchKey)
                }
                return bindingAtPoint
            }
            let peakPressure = updatePeakPressure(for: touchKey, pressure: touch.pressure)

            if disqualifiedTouches.value(for: touchKey) != nil {
                switch touch.state {
                case .breaking, .leaving, .notTouching:
                    disqualifiedTouches.remove(touchKey)
                    releaseHandledTouches.set(touchKey, true)
                    touchInitialContactPoint.remove(touchKey)
                    clearPeakPressure(for: touchKey)
                case .starting, .hovering, .making, .touching, .lingering:
                    break
                @unknown default:
                    break
                }
                continue
            }
            if touchInitialContactPoint.value(for: touchKey) == nil,
               Self.isContactState(touch.state) {
                touchInitialContactPoint.set(touchKey, point)
            }

            if momentaryLayerTouches.value(for: touchKey) != nil {
                handleMomentaryLayerTouch(
                    touchKey: touchKey,
                    state: touch.state,
                    targetLayer: nil,
                    bindingRect: nil
                )
                continue
            }
            if layerToggleTouchStarts.value(for: touchKey) != nil {
                handleLayerToggleTouch(touchKey: touchKey, state: touch.state, targetLayer: nil)
                continue
            }

            if let binding = resolveBinding() {
                switch binding.action {
                case .typingToggle:
                    break
                case let .layerToggle(targetLayer):
                    handleLayerToggleTouch(touchKey: touchKey, state: touch.state, targetLayer: targetLayer)
                    continue
                case let .layerMomentary(targetLayer):
                    handleMomentaryLayerTouch(
                        touchKey: touchKey,
                        state: touch.state,
                        targetLayer: targetLayer,
                        bindingRect: binding.rect
                    )
                    continue
                case .none:
                    break
                case .appLaunch, .key, .leftClick, .doubleClick, .rightClick, .middleClick,
                     .volumeUp, .volumeDown, .volumeUpSmall, .volumeDownSmall,
                     .brightnessUp, .brightnessDown, .brightnessUpSmall, .brightnessDownSmall,
                     .chordalShift,
                     .voice,
                     .gestureTwoFingerTap, .gestureThreeFingerTap, .gestureFourFingerHold,
                     .gestureInnerCornersHold, .gestureFiveFingerSwipeLeft, .gestureFiveFingerSwipeRight:
                    break
                }
            }
            if !intentAllowsTyping, isTypingEnabled,
               disqualifiedTouches.value(for: touchKey) == nil {
                disqualifyTouch(touchKey, reason: .intentMouse)
                if Self.isTerminalReleaseState(touch.state) {
                    disqualifiedTouches.remove(touchKey)
                    releaseHandledTouches.set(touchKey, true)
                    clearPeakPressure(for: touchKey)
                }
                continue
            }
            if !isTypingEnabled && momentaryLayerTouches.isEmpty {
                let removedActive = removeActiveTouch(for: touchKey)
                _ = removePendingTouch(for: touchKey)
                if let active = removedActive {
                    if let modifierKey = active.modifierKey {
                        handleModifierUp(modifierKey, binding: active.binding)
                    } else if active.holdRepeatActive {
                        stopRepeat(for: touchKey)
                   }
                }
                disqualifiedTouches.remove(touchKey)
                touchInitialContactPoint.remove(touchKey)
                continue
            }

            switch touch.state {
            case .starting, .making, .touching:
                if var active = activeTouch(for: touchKey) {
                    let distanceSquared = distanceSquared(from: active.startPoint, to: point)
                    active.maxDistanceSquared = max(active.maxDistanceSquared, distanceSquared)
                    setActiveTouch(touchKey, active)
                    if isDragDetectionEnabled,
                       active.modifierKey == nil,
                       !active.didHold,
                       active.maxDistanceSquared > dragCancelDistanceSquared {
                        disqualifyTouch(touchKey, reason: .dragCancelled)
                        continue
                    }

                    if active.isContinuousKey,
                       !active.binding.hitGeometry.contains(point) {
                        disqualifyTouch(touchKey, reason: .leftContinuousRect)
                        continue
                    }

                    if intentAllowsTyping,
                       active.modifierKey == nil,
                       !active.didHold,
                       isHoldTriggerSatisfied(
                            for: active.binding,
                            pressure: peakPressure,
                            startTime: active.startTime,
                            now: now
                       ),
                       (!isDragDetectionEnabled || active.maxDistanceSquared <= dragCancelDistanceSquared) {
                        let dispatchInfo = makeDispatchInfo(
                            kind: .hold,
                            startTime: active.startTime,
                            maxDistanceSquared: active.maxDistanceSquared,
                            now: now
                        )
                        var updated = active
                        let holdDispatchBinding = active.holdBinding ?? active.binding
                        let dispatchPressure = holdDispatchPressure(
                            for: active.binding,
                            pressure: peakPressure
                        )
                        if beginHoldRepeat(
                                for: touchKey,
                                binding: holdDispatchBinding,
                                pressure: dispatchPressure
                            ) {
                            updated.holdRepeatActive = true
                        } else {
                            triggerBinding(
                                holdDispatchBinding,
                                touchKey: touchKey,
                                dispatchInfo: dispatchInfo,
                                pressure: dispatchPressure
                            )
                            updated.holdRepeatActive = false
                        }
                        updated.didHold = true
                        setActiveTouch(touchKey, updated)
                    }
                } else if var pending = pendingTouch(for: touchKey) {
                    let distanceSquared = distanceSquared(from: pending.startPoint, to: point)
                    pending.maxDistanceSquared = max(pending.maxDistanceSquared, distanceSquared)
                    setPendingTouch(touchKey, pending)

                    if isDragDetectionEnabled,
                       pending.maxDistanceSquared > dragCancelDistanceSquared {
                        disqualifyTouch(touchKey, reason: .pendingDragCancelled)
                        continue
                    }

                    let allowPriority = allowsPriorityTyping(for: pending.binding)
                    if pending.binding.hitGeometry.contains(point),
                       (intentAllowsTyping || allowPriority) {
                        let modifierKey = modifierKey(for: pending.binding)
                        let isContinuousKey = isContinuousKey(pending.binding)
                        let holdBinding = holdBinding(
                            for: pending.binding,
                            allowHold: layout.allowHoldBindings
                        )
                        if shouldImmediateTapWithModifiers(binding: pending.binding) {
                            let dispatchInfo = makeDispatchInfo(
                                kind: .tap,
                                startTime: pending.startTime,
                                maxDistanceSquared: pending.maxDistanceSquared,
                                now: now
                            )
                            triggerBinding(
                                pending.binding,
                                touchKey: touchKey,
                                dispatchInfo: dispatchInfo,
                                pressure: peakPressure
                            )
                            _ = removePendingTouch(for: touchKey)
                            touchInitialContactPoint.remove(touchKey)
                            disqualifiedTouches.set(touchKey, true)
                            continue
                        }
                        let active = ActiveTouch(
                            binding: pending.binding,
                            layer: pending.layer,
                            startTime: pending.startTime,
                            startPoint: pending.startPoint,
                            modifierKey: modifierKey,
                            isContinuousKey: isContinuousKey,
                            holdBinding: holdBinding,
                            didHold: false,
                            maxDistanceSquared: pending.maxDistanceSquared,
                            modifierEngaged: false
                        )
                        setActiveTouch(touchKey, active)
                        if let modifierKey {
                            handleModifierDown(modifierKey, binding: pending.binding)
                            var updated = active
                            updated.modifierEngaged = true
                            setActiveTouch(touchKey, updated)
                        }
                    } else if isDragDetectionEnabled {
                        _ = removePendingTouch(for: touchKey)
                    } else {
                        _ = removePendingTouch(for: touchKey)
                    }
                } else if let binding = resolveBinding() {
                    let modifierKey = modifierKey(for: binding)
                    let isContinuousKey = isContinuousKey(binding)
                    let holdBinding = holdBinding(
                        for: binding,
                        allowHold: layout.allowHoldBindings
                    )
                    let allowPriority = allowsPriorityTyping(for: binding)
                    let allowNow = intentAllowsTyping || allowPriority
                    if allowNow, shouldImmediateTapWithModifiers(binding: binding) {
                        let dispatchInfo = makeDispatchInfo(
                            kind: .tap,
                            startTime: now,
                            maxDistanceSquared: 0,
                            now: now
                        )
                        triggerBinding(
                            binding,
                            touchKey: touchKey,
                            dispatchInfo: dispatchInfo,
                            pressure: peakPressure
                        )
                        touchInitialContactPoint.remove(touchKey)
                        disqualifiedTouches.set(touchKey, true)
                        continue
                    }
                    if isDragDetectionEnabled, (modifierKey != nil || isContinuousKey) {
                        setPendingTouch(
                            touchKey,
                            PendingTouch(
                                binding: binding,
                                layer: activeLayer,
                                startTime: now,
                                startPoint: point,
                                maxDistanceSquared: 0
                            )
                        )
                    } else {
                        let active = ActiveTouch(
                                binding: binding,
                                layer: activeLayer,
                                startTime: now,
                                startPoint: point,
                                modifierKey: modifierKey,
                                isContinuousKey: isContinuousKey,
                                holdBinding: holdBinding,
                                didHold: false,
                                maxDistanceSquared: 0,
                                modifierEngaged: false
                            )
                        setActiveTouch(touchKey, active)
                        if allowNow, let modifierKey {
                            handleModifierDown(modifierKey, binding: binding)
                            var updated = active
                            updated.modifierEngaged = true
                            setActiveTouch(touchKey, updated)
                        }
                    }
                }
            case .breaking, .leaving:
                let releaseStartPoint = touchInitialContactPoint.remove(touchKey)
                let removedPending = removePendingTouch(for: touchKey)
                let hadPending = removedPending != nil
                if var pending = removedPending {
                    let distanceSquared = distanceSquared(from: pending.startPoint, to: point)
                    pending.maxDistanceSquared = max(pending.maxDistanceSquared, distanceSquared)
                    let sentContinuousTap = maybeSendPendingContinuousTap(
                        pending,
                        touchKey: touchKey,
                        at: point,
                        now: now,
                        pressure: peakPressure
                    )
                    if !sentContinuousTap {
                        _ = maybeDispatchReleaseTap(
                            touchKey: touchKey,
                            originalBinding: pending.binding,
                            touchInfo: intentState.touches.value(for: touchKey),
                            point: point,
                            bindings: bindings,
                            now: now,
                            pressure: peakPressure,
                            fallbackStartTime: pending.startTime,
                            fallbackMaxDistanceSquared: pending.maxDistanceSquared
                        )
                    }
                }
                if disqualifiedTouches.remove(touchKey) != nil {
                    releaseHandledTouches.set(touchKey, true)
                    clearPeakPressure(for: touchKey)
                    continue
                }
                let removedActive = removeActiveTouch(for: touchKey)
                let hadActive = removedActive != nil
                if var active = removedActive {
                    let releaseDistanceSquared = distanceSquared(
                        from: releaseStartPoint ?? active.startPoint,
                        to: point
                    )
                    active.maxDistanceSquared = max(active.maxDistanceSquared, releaseDistanceSquared)
                    if let modifierKey = active.modifierKey, active.modifierEngaged {
                        handleModifierUp(modifierKey, binding: active.binding)
                    } else if active.holdRepeatActive {
                        stopRepeat(for: touchKey)
                    } else if !active.didHold {
                        _ = maybeDispatchReleaseTap(
                            touchKey: touchKey,
                            originalBinding: active.binding,
                            touchInfo: intentState.touches.value(for: touchKey),
                            point: point,
                            bindings: bindings,
                            now: now,
                            pressure: peakPressure,
                            fallbackStartTime: active.startTime,
                            fallbackMaxDistanceSquared: active.maxDistanceSquared
                        )
                    }
                    endMomentaryHoldIfNeeded(active.holdBinding, touchKey: touchKey)
                }
                if !hadPending, !hadActive {
                    if maybeDispatchReleaseTap(
                        touchKey: touchKey,
                        originalBinding: nil,
                        touchInfo: intentState.touches.value(for: touchKey),
                        point: point,
                        bindings: bindings,
                        now: now,
                        pressure: peakPressure
                    ) {
                        clearPeakPressure(for: touchKey)
                        continue
                    }
                }
                if !hadPending, !hadActive, resolveBinding() == nil {
                    if attemptSnapOnRelease(
                        touchKey: touchKey,
                        point: point,
                        bindings: bindings,
                        pressure: peakPressure
                    ) {
                        clearPeakPressure(for: touchKey)
                        continue
                    }
                    if shouldAttemptSnap() {
                        disqualifyTouch(touchKey, reason: .offKeyNoSnap)
                        #if DEBUG
                        OSAtomicIncrement64Barrier(&Self.snapOffKeyCount)
                        #endif
                    }
                }
                releaseHandledTouches.set(touchKey, true)
                clearPeakPressure(for: touchKey)
            case .notTouching:
                let releaseStartPoint = touchInitialContactPoint.remove(touchKey)
                let removedPending = removePendingTouch(for: touchKey)
                let hadPending = removedPending != nil
                if var pending = removedPending {
                    let distanceSquared = distanceSquared(from: pending.startPoint, to: point)
                    pending.maxDistanceSquared = max(pending.maxDistanceSquared, distanceSquared)
                    let sentContinuousTap = maybeSendPendingContinuousTap(
                        pending,
                        touchKey: touchKey,
                        at: point,
                        now: now,
                        pressure: peakPressure
                    )
                    if !sentContinuousTap {
                        _ = maybeDispatchReleaseTap(
                            touchKey: touchKey,
                            originalBinding: pending.binding,
                            touchInfo: intentState.touches.value(for: touchKey),
                            point: point,
                            bindings: bindings,
                            now: now,
                            pressure: peakPressure,
                            fallbackStartTime: pending.startTime,
                            fallbackMaxDistanceSquared: pending.maxDistanceSquared
                        )
                    }
                }
                if disqualifiedTouches.remove(touchKey) != nil {
                    releaseHandledTouches.set(touchKey, true)
                    clearPeakPressure(for: touchKey)
                    continue
                }
                let removedActive = removeActiveTouch(for: touchKey)
                let hadActive = removedActive != nil
                if var active = removedActive {
                    let releaseDistanceSquared = distanceSquared(
                        from: releaseStartPoint ?? active.startPoint,
                        to: point
                    )
                    active.maxDistanceSquared = max(active.maxDistanceSquared, releaseDistanceSquared)
                    if let modifierKey = active.modifierKey, active.modifierEngaged {
                        handleModifierUp(modifierKey, binding: active.binding)
                    } else if active.holdRepeatActive {
                        stopRepeat(for: touchKey)
                    } else if !active.didHold {
                        _ = maybeDispatchReleaseTap(
                            touchKey: touchKey,
                            originalBinding: active.binding,
                            touchInfo: intentState.touches.value(for: touchKey),
                            point: point,
                            bindings: bindings,
                            now: now,
                            pressure: peakPressure,
                            fallbackStartTime: active.startTime,
                            fallbackMaxDistanceSquared: active.maxDistanceSquared
                        )
                    }
                    endMomentaryHoldIfNeeded(active.holdBinding, touchKey: touchKey)
                }
                if !hadPending, !hadActive {
                    if maybeDispatchReleaseTap(
                        touchKey: touchKey,
                        originalBinding: nil,
                        touchInfo: intentState.touches.value(for: touchKey),
                        point: point,
                        bindings: bindings,
                        now: now,
                        pressure: peakPressure
                    ) {
                        clearPeakPressure(for: touchKey)
                        continue
                    }
                }
                if !hadPending, !hadActive, resolveBinding() == nil {
                    if attemptSnapOnRelease(
                        touchKey: touchKey,
                        point: point,
                        bindings: bindings,
                        pressure: peakPressure
                    ) {
                        clearPeakPressure(for: touchKey)
                        continue
                    }
                    if shouldAttemptSnap() {
                        disqualifyTouch(touchKey, reason: .offKeyNoSnap)
                        #if DEBUG
                        OSAtomicIncrement64Barrier(&Self.snapOffKeyCount)
                        #endif
                    }
                }
                releaseHandledTouches.set(touchKey, true)
                clearPeakPressure(for: touchKey)
            case .hovering, .lingering:
                break
            @unknown default:
                break
            }
        }
        releaseStaleTouches(
            deviceIndex: deviceIndex,
            frameTouchKeys: frameTouchKeys,
            bindings: bindings,
            now: now
        )
        contactFingerCountsBySide[side] = cachedContactCount(
            for: side,
            actualCount: contactCount,
            now: now
        )
    }

    private func releaseStaleTouches(
        deviceIndex: Int,
        frameTouchKeys: TouchTable<Bool>,
        bindings: BindingIndex,
        now: TimeInterval
    ) {
        touchRemovalBuffer.removeAll(keepingCapacity: true)
        touchStates.forEach { touchKey, _ in
            guard Self.touchKeyDeviceIndex(touchKey) == deviceIndex,
                  frameTouchKeys.value(for: touchKey) == nil else {
                return
            }
            touchRemovalBuffer.append(touchKey)
        }

        for touchKey in touchRemovalBuffer {
            releaseMissingTouch(
                touchKey: touchKey,
                bindings: bindings,
                now: now
            )
        }
    }

    private func releaseMissingTouch(
        touchKey: TouchKey,
        bindings: BindingIndex,
        now: TimeInterval
    ) {
        let point = framePointCache.value(for: touchKey)
            ?? touchInitialContactPoint.value(for: touchKey)
            ?? activeTouch(for: touchKey)?.startPoint
            ?? pendingTouch(for: touchKey)?.startPoint
            ?? .zero
        let peakPressure = peakPressureByTouch.value(for: touchKey) ?? 0

        if momentaryLayerTouches.value(for: touchKey) != nil {
            handleMomentaryLayerTouch(
                touchKey: touchKey,
                state: .notTouching,
                targetLayer: nil,
                bindingRect: nil
            )
        }
        if layerToggleTouchStarts.value(for: touchKey) != nil {
            handleLayerToggleTouch(
                touchKey: touchKey,
                state: .notTouching,
                targetLayer: nil
            )
        }

        let releaseStartPoint = touchInitialContactPoint.remove(touchKey)
        let removedPending = removePendingTouch(for: touchKey)
        let hadPending = removedPending != nil
        if var pending = removedPending {
            let distanceSquared = distanceSquared(from: pending.startPoint, to: point)
            pending.maxDistanceSquared = max(pending.maxDistanceSquared, distanceSquared)
            let sentContinuousTap = maybeSendPendingContinuousTap(
                pending,
                touchKey: touchKey,
                at: point,
                now: now,
                pressure: peakPressure
            )
            if !sentContinuousTap {
                _ = maybeDispatchReleaseTap(
                    touchKey: touchKey,
                    originalBinding: pending.binding,
                    touchInfo: nil,
                    point: point,
                    bindings: bindings,
                    now: now,
                    pressure: peakPressure,
                    fallbackStartTime: pending.startTime,
                    fallbackMaxDistanceSquared: pending.maxDistanceSquared
                )
            }
        }

        if disqualifiedTouches.remove(touchKey) != nil {
            clearPeakPressure(for: touchKey)
            framePointCache.remove(touchKey)
            return
        }

        let removedActive = removeActiveTouch(for: touchKey)
        let hadActive = removedActive != nil
        if var active = removedActive {
            let releaseDistanceSquared = distanceSquared(
                from: releaseStartPoint ?? active.startPoint,
                to: point
            )
            active.maxDistanceSquared = max(active.maxDistanceSquared, releaseDistanceSquared)
            if let modifierKey = active.modifierKey, active.modifierEngaged {
                handleModifierUp(modifierKey, binding: active.binding)
            } else if active.holdRepeatActive {
                stopRepeat(for: touchKey)
            } else if !active.didHold {
                _ = maybeDispatchReleaseTap(
                    touchKey: touchKey,
                    originalBinding: active.binding,
                    touchInfo: nil,
                    point: point,
                    bindings: bindings,
                    now: now,
                    pressure: peakPressure,
                    fallbackStartTime: active.startTime,
                    fallbackMaxDistanceSquared: active.maxDistanceSquared
                )
            }
            endMomentaryHoldIfNeeded(active.holdBinding, touchKey: touchKey)
        }

        if !hadPending, !hadActive {
            _ = maybeDispatchReleaseTap(
                touchKey: touchKey,
                originalBinding: nil,
                touchInfo: nil,
                point: point,
                bindings: bindings,
                now: now,
                pressure: peakPressure
            )
        }

        clearPeakPressure(for: touchKey)
        framePointCache.remove(touchKey)
    }

    @inline(__always)
    private func forceRange() -> (min: Float, max: Float) {
        let minForce = min(forceClickMin, forceClickCap)
        let maxForce = max(forceClickMin, forceClickCap)
        return (min: minForce, max: maxForce)
    }

    @inline(__always)
    private func isPressureWithinForceRange(_ pressure: Float) -> Bool {
        let range = forceRange()
        return pressure >= range.min && pressure <= range.max
    }

    @inline(__always)
    private func updatePeakPressure(for touchKey: TouchKey, pressure: Float) -> Float {
        let pressureClamped = max(0, pressure)
        if let existing = peakPressureByTouch.value(for: touchKey) {
            let peak = max(existing, pressureClamped)
            peakPressureByTouch.set(touchKey, peak)
            return peak
        }
        peakPressureByTouch.set(touchKey, pressureClamped)
        return pressureClamped
    }

    @inline(__always)
    private func clearPeakPressure(for touchKey: TouchKey) {
        _ = peakPressureByTouch.remove(touchKey)
    }

    private func shouldImmediateTapWithModifiers(binding: KeyBinding) -> Bool {
        hasActiveModifiers() && modifierKey(for: binding) == nil
    }

    private func hasActiveModifiers() -> Bool {
        leftShiftTouchCount > 0
            || controlTouchCount > 0
            || leftOptionTouchCount > 0
            || rightOptionTouchCount > 0
            || commandTouchCount > 0
    }

    private func activeTouch(for touchKey: TouchKey) -> ActiveTouch? {
        guard let state = touchStates.value(for: touchKey),
              case let .active(active) = state else {
            return nil
        }
        return active
    }

    private func pendingTouch(for touchKey: TouchKey) -> PendingTouch? {
        guard let state = touchStates.value(for: touchKey),
              case let .pending(pending) = state else {
            return nil
        }
        return pending
    }

    private func setActiveTouch(_ touchKey: TouchKey, _ active: ActiveTouch) {
        touchStates.set(touchKey, .active(active))
    }

    private func setPendingTouch(_ touchKey: TouchKey, _ pending: PendingTouch) {
        touchStates.set(touchKey, .pending(pending))
    }

    private func removeActiveTouch(for touchKey: TouchKey) -> ActiveTouch? {
        guard let state = touchStates.value(for: touchKey),
              case let .active(active) = state else {
            return nil
        }
        touchStates.remove(touchKey)
        return active
    }

    private func removePendingTouch(for touchKey: TouchKey) -> PendingTouch? {
        guard let state = touchStates.value(for: touchKey),
              case let .pending(pending) = state else {
            return nil
        }
        touchStates.remove(touchKey)
        return pending
    }

    private func popTouchState(for touchKey: TouchKey) -> TouchState? {
        touchStates.remove(touchKey)
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
            guard let binding = makeBinding(
                for: button.action, rect: rect, normalizedRect: button.rect,
                canvasSize: canvasSize, position: nil, customButtonID: button.id,
                side: button.side, holdAction: button.hold,
                holdForceThreshold: button.hold == nil ? 0 : Float(button.holdForceThreshold)
            ) else { continue }
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
        case .typingToggle, .chordalShift, .appLaunch, .voice, .gestureTwoFingerTap, .gestureThreeFingerTap, .gestureFourFingerHold, .gestureInnerCornersHold, .gestureFiveFingerSwipeLeft, .gestureFiveFingerSwipeRight, .brightnessUp, .brightnessDown, .brightnessUpSmall, .brightnessDownSmall, .volumeUpSmall, .volumeDownSmall:
            return nil
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

    @inline(__always)
    private func shouldAttemptSnap() -> Bool {
        guard isSnapRadiusEnabled else { return false }
        switch intentState.mode {
        case .typingCommitted:
            return true
        case .mouseActive, .idle:
            return false
        }
    }

    @inline(__always)
    private func nearestSnapIndices(
        to point: CGPoint,
        in bindings: BindingIndex
    ) -> (bestIndex: Int, bestDistance: Float, secondIndex: Int, secondDistance: Float)? {
        let count = bindings.snapCentersX.count
        guard count > 0 else { return nil }
        let px = Float(point.x)
        let py = Float(point.y)
        var bestIndex = -1
        var bestDistance = Float.greatestFiniteMagnitude
        var secondIndex = -1
        var secondDistance = Float.greatestFiniteMagnitude
        for index in 0..<count {
            let dx = px - bindings.snapCentersX[index]
            let dy = py - bindings.snapCentersY[index]
            let distance = dx * dx + dy * dy
            if distance < bestDistance {
                secondDistance = bestDistance
                secondIndex = bestIndex
                bestDistance = distance
                bestIndex = index
            } else if distance < secondDistance {
                secondDistance = distance
                secondIndex = index
            }
        }
        guard bestIndex >= 0 else { return nil }
        return (bestIndex, bestDistance, secondIndex, secondDistance)
    }

    private func dispatchSnappedBinding(
        _ binding: KeyBinding,
        altBinding: KeyBinding?,
        touchKey: TouchKey,
        pressure: Float
    ) {
        guard isPressureWithinForceRange(pressure) else { return }
        guard case let .key(code, flags) = binding.action else { return }
        recordFrameDecision(
            touchKey,
            outcome: .dispatched,
            reason: "snapped",
            binding: binding
        )
        #if DEBUG
        onDebugBindingDetected(binding)
        #endif
        extendTypingGrace(for: binding.side, now: currentTime())
        playHapticIfNeeded(on: binding.side, touchKey: touchKey)

        let modifierFlags = currentModifierFlags()
        let combinedFlags = flags.union(modifierFlags)
        var altAscii: UInt8 = 0
        if let altBinding, case let .key(altCode, altFlags) = altBinding.action {
            altAscii = KeySemanticMapper.asciiForKey(
                code: altCode,
                flags: altFlags.union(modifierFlags)
            )
        }
        sendKey(
            code: code,
            flags: flags,
            side: binding.side,
            combinedFlags: combinedFlags,
            altAscii: altAscii,
            sourceSequence: currentDispatchSourceSequence()
        )
    }

    private func attemptSnapOnRelease(
        touchKey: TouchKey,
        point: CGPoint,
        bindings: BindingIndex,
        pressure: Float
    ) -> Bool {
        guard shouldAttemptSnap() else { return false }
        #if DEBUG
        OSAtomicIncrement64Barrier(&Self.snapAttemptCount)
        #endif
        guard let (bestIndex, bestDistanceSq, secondIndex, secondDistanceSq) =
            nearestSnapIndices(to: point, in: bindings) else {
            #if DEBUG
            OSAtomicIncrement64Barrier(&Self.snapRejectedCount)
            #endif
            return false
        }
        if bestDistanceSq <= bindings.snapRadiusSq[bestIndex] {
            var selectedIndex = bestIndex
            var alternateIndex: Int? = nil
            if secondIndex >= 0,
               secondDistanceSq <= bindings.snapRadiusSq[secondIndex],
               secondDistanceSq <= bestDistanceSq * snapAmbiguityRatio * snapAmbiguityRatio {
                let bestEdgeDistance = distanceSquaredToRectEdge(
                    point: point,
                    rect: bindings.snapBindings[bestIndex].rect
                )
                let secondEdgeDistance = distanceSquaredToRectEdge(
                    point: point,
                    rect: bindings.snapBindings[secondIndex].rect
                )
                if secondEdgeDistance < bestEdgeDistance {
                    selectedIndex = secondIndex
                    alternateIndex = bestIndex
                } else {
                    alternateIndex = secondIndex
                }
            }
            let binding = bindings.snapBindings[selectedIndex]
            let altBinding = alternateIndex.map { bindings.snapBindings[$0] }
            dispatchSnappedBinding(
                binding,
                altBinding: altBinding,
                touchKey: touchKey,
                pressure: pressure
            )
            // Prevent duplicate snap dispatch on subsequent release states.
            disqualifiedTouches.set(touchKey, true)
            #if DEBUG
            OSAtomicIncrement64Barrier(&Self.snapAcceptedCount)
            #endif
            return true
        }
        #if DEBUG
        OSAtomicIncrement64Barrier(&Self.snapRejectedCount)
        #endif
        return false
    }

    private func distanceSquaredToRectEdge(point: CGPoint, rect: CGRect) -> Float {
        let px = Float(point.x)
        let py = Float(point.y)
        let minX = Float(rect.minX)
        let maxX = Float(rect.maxX)
        let minY = Float(rect.minY)
        let maxY = Float(rect.maxY)
        let dx: Float
        if px < minX {
            dx = minX - px
        } else if px > maxX {
            dx = px - maxX
        } else {
            dx = 0
        }
        let dy: Float
        if py < minY {
            dy = minY - py
        } else if py > maxY {
            dy = py - maxY
        } else {
            dy = 0
        }
        return dx * dx + dy * dy
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

    private static func isTerminalReleaseState(_ state: OMSState) -> Bool {
        switch state {
        case .breaking, .leaving, .notTouching:
            return true
        default:
            return false
        }
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

        let allowsTyping = updateIntentGlobal(
            leftTouches: leftTouches, rightTouches: rightTouches,
            leftDeviceIndex: leftDeviceIndex, rightDeviceIndex: rightDeviceIndex,
            leftBindings: leftBindings, rightBindings: rightBindings, now: now,
            moveThresholdSquared: 0, velocityThreshold: 0, unitsPerMm: unitsPerMillimeter,
            bindingCacheBySide: &bindingCacheBySide)
        return allowsTyping
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
        // Keyboard dispatch stays in the original mac pipeline; only intent is replaced.
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
            framePointCache.set(key, point)
            if let binding = binding(at: point, index: index) {
                onKey = true
                bindingCacheBySide[side].set(key, binding)
            }
            if var info = state.touches.value(for: key) {
                info.maxDistanceSquared = max(info.maxDistanceSquared, distanceSquared(from: info.startPoint, to: point))
                info.lastPoint = point
                info.lastTime = now
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
        case .typingCommitted:
            return .typing
        case .mouseActive:
            return .mouse
        }
    }

    @inline(__always)
    private func isTypingGraceActive(now: TimeInterval? = nil) -> Bool {
        let currentNow = now ?? currentTime()
        if let deadline = typingGraceDeadline, currentNow < deadline {
            return true
        }
        typingGraceDeadline = nil
        return false
    }

    private func updatePhysicalScale() {
        guard trackpadWidthMm > 0 else {
            unitsPerMillimeter = 1

            return
        }
        unitsPerMillimeter = trackpadSize.width / trackpadWidthMm

    }

    private func handleLayerToggleTouch(
        touchKey: TouchKey,
        state: OMSState,
        targetLayer: Int?
    ) {
        switch state {
        case .starting, .making, .touching:
            guard isTypingEnabled else { break }
            if let targetLayer {
                layerToggleTouchStarts.set(touchKey, targetLayer)
            }
        case .breaking, .leaving:
            if let targetLayer = layerToggleTouchStarts.remove(touchKey) {
                guard isTypingEnabled else { break }
                toggleLayer(to: targetLayer)
            }
        case .notTouching:
            layerToggleTouchStarts.remove(touchKey)
        case .hovering, .lingering:
            break
        @unknown default:
            break
        }
    }

    private func handleMomentaryLayerTouch(
        touchKey: TouchKey,
        state: OMSState,
        targetLayer: Int?,
        bindingRect: CGRect?
    ) {
        switch state {
        case .starting, .making, .touching:
            guard momentaryLayerTouches.value(for: touchKey) == nil,
                  let targetLayer,
                  let rect = bindingRect,
                  let initialPoint = touchInitialContactPoint.value(for: touchKey),
                  rect.contains(initialPoint) else {
                break
            }
            momentaryLayerTouches.set(touchKey, targetLayer)
            updateActiveLayer()
        case .breaking, .leaving, .notTouching:
            if momentaryLayerTouches.remove(touchKey) != nil {
                updateActiveLayer()
            }
        case .hovering, .lingering:
            break
        @unknown default:
            break
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

    private func canHoldRepeat(binding: KeyBinding) -> Bool {
        guard case let .key(code, _) = binding.action else { return false }
        if modifierKey(for: binding) != nil {
            return false
        }
        if code == CGKeyCode(kVK_Function) {
            return false
        }
        return isContinuousKey(binding) || holdRepeatEnabled
    }

    private func isHoldTriggerSatisfied(
        for binding: KeyBinding,
        pressure: Float,
        startTime: TimeInterval,
        now: TimeInterval
    ) -> Bool {
        if binding.holdForceThreshold > 0, pressure > 0 {
            return pressure >= binding.holdForceThreshold
        }
        return now - startTime >= holdMinDuration
    }

    private func holdDispatchPressure(for binding: KeyBinding, pressure: Float) -> Float? {
        if binding.holdForceThreshold > 0, pressure > 0 {
            return nil
        }
        return pressure
    }

    private func isClickActuationSatisfied(_ pressure: Float) -> Bool {
        pressure >= clickActuationForce
    }

    private func isForceClickThresholdSatisfied(_ pressure: Float) -> Bool {
        pressure >= forceClickThreshold
    }

    private func allowsPriorityTyping(for binding: KeyBinding) -> Bool {
        let state = intentState
        let isModifier = modifierKey(for: binding) != nil
        let isContinuous = isContinuousKey(binding)
        guard isModifier || isContinuous else { return false }
        switch state.mode {
        case .typingCommitted:
            return true
        case .mouseActive:
            return isModifier
        case .idle:
            return false
        }
    }

    private func holdBinding(for binding: KeyBinding, allowHold: Bool) -> KeyBinding? {
        guard allowHold else { return nil }
        if let holdAction = binding.holdAction {
            return makeBinding(
                for: holdAction,
                rect: binding.rect,
                normalizedRect: binding.normalizedRect,
                canvasSize: trackpadSize,
                position: binding.position,
                side: binding.side,
                holdAction: binding.holdAction
            )
        }
        guard let action = holdAction(for: binding.position, label: binding.label) else { return nil }
        return makeBinding(
            for: action,
            rect: binding.rect,
            normalizedRect: binding.normalizedRect,
            canvasSize: trackpadSize,
            position: binding.position,
            side: binding.side
        )
    }

    @discardableResult
    private func maybeSendPendingContinuousTap(
        _ pending: PendingTouch,
        touchKey: TouchKey,
        at point: CGPoint,
        now: TimeInterval,
        pressure: Float
    ) -> Bool {
        let releaseDistanceSquared = distanceSquared(from: pending.startPoint, to: point)
        guard isContinuousKey(pending.binding),
              now - pending.startTime <= tapMaxDuration,
              pending.binding.hitGeometry.contains(point),
              (!isDragDetectionEnabled
               || releaseDistanceSquared <= dragCancelDistance * dragCancelDistance) else {
            return false
        }
        let dispatchInfo = makeDispatchInfo(
            kind: .tap,
            startTime: pending.startTime,
            maxDistanceSquared: pending.maxDistanceSquared,
            now: now
        )
        sendKey(
            binding: pending.binding,
            touchKey: touchKey,
            dispatchInfo: dispatchInfo,
            pressure: pressure
        )
        return true
    }

    private func maybeDispatchReleaseTap(
        touchKey: TouchKey,
        originalBinding: KeyBinding?,
        touchInfo: IntentTouchInfo?,
        point: CGPoint,
        bindings: BindingIndex,
        now: TimeInterval,
        pressure: Float,
        fallbackStartTime: TimeInterval? = nil,
        fallbackMaxDistanceSquared: CGFloat = 0
    ) -> Bool {
        guard isTapDispatchAllowedForCurrentIntent() else {
            recordFrameDecision(
                touchKey,
                outcome: .rejected,
                reason: "intentBlocked",
                binding: originalBinding
            )
            return false
        }
        let startTime = touchInfo?.startTime ?? fallbackStartTime ?? now
        let releaseStartPoint = touchInitialContactPoint.value(for: touchKey) ?? point
        let releaseDistanceSquared = distanceSquared(from: releaseStartPoint, to: point)
        let maxDistanceSquared = max(
            max(touchInfo?.maxDistanceSquared ?? 0, fallbackMaxDistanceSquared),
            releaseDistanceSquared
        )
        guard now - startTime <= tapMaxDuration else {
            recordFrameDecision(
                touchKey,
                outcome: .rejected,
                reason: "tapTimedOut",
                binding: originalBinding
            )
            return false
        }
        if isDragDetectionEnabled, releaseDistanceSquared > dragCancelDistance * dragCancelDistance {
            recordFrameDecision(
                touchKey,
                outcome: .rejected,
                reason: "movedTooFar",
                binding: originalBinding
            )
            return false
        }

        let dispatchInfo = makeDispatchInfo(
            kind: .tap,
            startTime: startTime,
            maxDistanceSquared: maxDistanceSquared,
            now: now
        )

        if let originalBinding {
            if originalBinding.hitGeometry.contains(point) {
                triggerBinding(
                    originalBinding,
                    touchKey: touchKey,
                    dispatchInfo: dispatchInfo,
                    pressure: pressure
                )
                return true
            }
            if let directBinding = binding(at: point, index: bindings) {
                guard bindingsMatch(originalBinding, directBinding) else {
                    recordFrameDecision(
                        touchKey,
                        outcome: .rejected,
                        reason: "bindingMismatch",
                        binding: originalBinding
                    )
                    return false
                }
                triggerBinding(
                    directBinding,
                    touchKey: touchKey,
                    dispatchInfo: dispatchInfo,
                    pressure: pressure
                )
                return true
            }
            let snapped = attemptSnapOnRelease(
                touchKey: touchKey,
                point: point,
                bindings: bindings,
                pressure: pressure
            )
            if !snapped {
                recordFrameDecision(
                    touchKey,
                    outcome: .rejected,
                    reason: "missedTarget",
                    binding: originalBinding
                )
            }
            return snapped
        }

        if let directBinding = binding(at: point, index: bindings) {
            triggerBinding(
                directBinding,
                touchKey: touchKey,
                dispatchInfo: dispatchInfo,
                pressure: pressure
            )
            return true
        }

        let snapped = attemptSnapOnRelease(
            touchKey: touchKey,
            point: point,
            bindings: bindings,
            pressure: pressure
        )
        if !snapped {
            recordFrameDecision(
                touchKey,
                outcome: .rejected,
                reason: "missedTarget"
            )
        }
        return snapped
    }

    private func isTapDispatchAllowedForCurrentIntent() -> Bool {
        guard currentFrameAllowsTyping else { return false }
        switch intentState.mode {
        case .mouseActive: return false
        case .idle, .typingCommitted: return true
        }
    }

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
        case let .layerMomentary(layer):
            guard let touchKey else { return }
            momentaryLayerTouches.set(touchKey, layer)
            updateActiveLayer()
        case let .layerToggle(layer):
            toggleLayer(to: layer)
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
        case .appLaunch, .chordalShift, .typingToggle, .volumeUpSmall, .volumeDownSmall,
             .brightnessUp, .brightnessDown, .brightnessUpSmall, .brightnessDownSmall, .voice, .gestureTwoFingerTap, .gestureThreeFingerTap,
             .gestureFourFingerHold, .gestureInnerCornersHold,
             .gestureFiveFingerSwipeLeft, .gestureFiveFingerSwipeRight:
            return
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
        if leftShiftTouchCount > 0 {
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

    /// Optional Apple-trackpad feedback extension; never part of gesture recognition.
    private func playHapticIfNeeded(on side: TrackpadSide?, touchKey: TouchKey? = nil) {
        guard hapticStrength > 0, let side else { return }
        if let touchKey, disqualifiedTouches.value(for: touchKey) != nil { return }
        let deviceID = side == .left ? leftDeviceID : rightDeviceID
        guard let deviceID, !deviceID.isEmpty else { return }
        let now = scheduler.uptimeNanoseconds
        if let last = lastHapticTimeBySide[side], now >= last,
           now - last < Self.hapticMinIntervalNanos { return }
        lastHapticTimeBySide[side] = now
        dispatchService.postHaptic(strength: hapticStrength, deviceID: deviceID,
                                   sourceSequence: currentDispatchSourceSequence())
    }

    private func beginHoldRepeat(
        for touchKey: TouchKey,
        binding: KeyBinding,
        pressure: Float? = nil
    ) -> Bool {
        guard canHoldRepeat(binding: binding) else { return false }
        if let pressure, !isPressureWithinForceRange(pressure) {
            recordFrameDecision(
                touchKey,
                outcome: .rejected,
                reason: "forceThresholdNotMet",
                binding: binding
            )
            return false
        }
        #if DEBUG
        onDebugBindingDetected(binding)
        #endif
        extendTypingGrace(for: binding.side, now: currentTime())
        playHapticIfNeeded(on: binding.side, touchKey: touchKey)

        recordFrameDecision(
            touchKey,
            outcome: .dispatched,
            reason: "hold",
            binding: binding
        )
        startRepeat(
            for: .touch(touchKey),
            binding: binding,
            initialDelay: repeatInitialDelay,
            interval: repeatInterval(for: binding.action)
        )
        return true
    }

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

    private func repeatInterval(for action: KeyBindingAction) -> UInt64 {
        if case let .key(code, flags) = action,
           code == CGKeyCode(kVK_Space),
           flags.isEmpty {
            return repeatInterval * spaceRepeatMultiplier
        }
        return repeatInterval
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
        for touchKey in activeTouchKeys {
            stopRepeat(for: touchKey)
        }
        touchStates.removeAll()
        disqualifiedTouches.removeAll()
        releaseHandledTouches.removeAll()

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
        let binding = binding(from: touchStates.value(for: touchKey))
        recordFrameDecision(
            touchKey,
            outcome: .rejected,
            reason: reason.rawValue,
            binding: binding
        )
        touchInitialContactPoint.remove(touchKey)
        disqualifiedTouches.set(touchKey, true)
        let state = popTouchState(for: touchKey)
        if let state, case let .active(active) = state {
            if let modifierKey = active.modifierKey, active.modifierEngaged {
                handleModifierUp(modifierKey, binding: active.binding)
            } else if active.holdRepeatActive {
                stopRepeat(for: touchKey)
            }
            endMomentaryHoldIfNeeded(active.holdBinding, touchKey: touchKey)
        }
        if reason == .dragCancelled || reason == .pendingDragCancelled {
            enterMouseIntentFromDragCancel()
        }
    }

    private func enterMouseIntentFromDragCancel() {
        typingGraceDeadline = nil
        typingGraceGeneration &+= 1
        intentState.mode = .mouseActive
        updateIntentDisplayIfNeeded()
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
        guard intentConfig.typingGraceSeconds > 0 else { return }
        let deadline = now + intentConfig.typingGraceSeconds
        typingGraceDeadline = deadline
        scheduleTypingGraceExpiry(deadline: deadline)
        if case .typingCommitted = intentState.mode {
            // Keep existing typing mode.
        } else {
            intentState.mode = .typingCommitted(untilAllUp: true)
        }
        updateIntentDisplayIfNeeded()
    }

    private func scheduleTypingGraceExpiry(deadline: TimeInterval) {
        typingGraceGeneration &+= 1
        let generation = typingGraceGeneration
        let delay = max(0, deadline - currentTime())
        scheduler.schedule(after: delay) { [weak self] in
            guard let self, self.typingGraceGeneration == generation else { return }
            self.expireTypingGraceIfNeeded(deadline: deadline)
        }
    }

    private func expireTypingGraceIfNeeded(deadline: TimeInterval) {
        guard let currentDeadline = typingGraceDeadline,
              currentDeadline == deadline,
              currentTime() >= deadline else {
            return
        }
        typingGraceDeadline = nil
        typingGraceGeneration &+= 1
        if intentState.touches.isEmpty, case .typingCommitted = intentState.mode {
            intentState.mode = .idle
        }
        updateIntentDisplayIfNeeded()
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

    private func endMomentaryHoldIfNeeded(_ binding: KeyBinding?, touchKey: TouchKey) {
        guard let binding else { return }
        switch binding.action {
        case .layerMomentary:
            if momentaryLayerTouches.remove(touchKey) != nil {
                updateActiveLayer()
            }
        default:
            break
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

    private func cachedContactCount(
        for side: TrackpadSide,
        actualCount: Int,
        now: TimeInterval
    ) -> Int {
        let previous = contactCountCache[side]
        let elapsed = previous != nil ? now - previous!.timestamp : contactCountHoldDuration
        let shouldHoldPrevious = actualCount == 0
            && (previous?.actual ?? 0) > 0
            && elapsed < contactCountHoldDuration
        let displayed = shouldHoldPrevious ? (previous?.displayed ?? actualCount) : actualCount
        let updatedCache = ContactCountCache(
            actual: actualCount,
            displayed: displayed,
            timestamp: now
        )
        contactCountCache[side] = updatedCache
        return displayed
    }

    private func makeDispatchInfo(
        kind: DispatchKind,
        startTime: TimeInterval,
        maxDistanceSquared: CGFloat,
        now: TimeInterval
    ) -> DispatchInfo {
        let durationMs = Int((now - startTime) * 1000.0)
        let maxDistance = sqrt(maxDistanceSquared)
        return DispatchInfo(kind: kind, durationMs: durationMs, maxDistance: maxDistance)
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
