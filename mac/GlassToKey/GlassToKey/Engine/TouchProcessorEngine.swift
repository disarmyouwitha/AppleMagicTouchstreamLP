import Carbon
import CoreGraphics
import Darwin
import Foundation
import OpenMultitouchSupport
import OpenMultitouchSupportXCF
import QuartzCore
import os

actor TouchProcessorEngine {
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

    private static func nowUptimeNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
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

    private let dispatchService: DispatchService
    private let onTypingEnabledChanged: @Sendable (Bool) -> Void
    private let onActiveLayerChanged: @Sendable (Int) -> Void
    private let onDebugBindingDetected: @Sendable (KeyBinding) -> Void
    private let onContactCountChanged: @Sendable (SidePair<Int>) -> Void
    private let onIntentStateChanged: @Sendable (SidePair<IntentDisplay>) -> Void
    private let onVoiceGestureChanged: @Sendable (Bool) -> Void
    private let isDragDetectionEnabled = true
    private var isListening = false
    private var keymapEditingEnabled = false
    private var isTypingEnabled = true
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
    private var repeatLoopTask: Task<Void, Never>?
    private var toggleTouchStarts = TouchTable<TimeInterval>()
    private var layerToggleTouchStarts = TouchTable<Int>()
    private var momentaryLayerTouches = MomentaryLayerTouches()
    private var lastMomentaryLayer: Int?
    private var touchInitialContactPoint = TouchTable<CGPoint>()
    private var tapMaxDuration: TimeInterval = 0.2
    private var holdMinDuration: TimeInterval = 0.2
    private var dragCancelDistance: CGFloat = 2.5
    private var forceClickMin: Float = 0
    private var forceClickCap: Float = 255
    private var snapRadiusFraction: Float = 0.35
    private let snapAmbiguityRatio: Float = 1.15
#if DEBUG
    nonisolated(unsafe) private static var snapAttemptCount: Int64 = 0
    nonisolated(unsafe) private static var snapAcceptedCount: Int64 = 0
    nonisolated(unsafe) private static var snapRejectedCount: Int64 = 0
    nonisolated(unsafe) private static var snapOffKeyCount: Int64 = 0
#endif
    private var contactFingerCountsBySide = SidePair(left: 0, right: 0)
    private var lastReportedContactCounts = SidePair(left: -1, right: -1)
    private struct ContactCountCache {
        var actual: Int
        var displayed: Int
        var timestamp: TimeInterval
    }
    private var contactCountCache = SidePair<ContactCountCache?>(left: nil, right: nil)
    private let contactCountHoldDuration: TimeInterval = 0.06
    private let holdGestureMoveCancelMm: CGFloat = 1.0
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
    private var intentCurrentKeys = TouchTable<Bool>(minimumCapacity: 16)
    private var intentRemovalBuffer: [TouchKey] = []
    private var unitsPerMillimeter: CGFloat = 1.0
    private var intentMoveThresholdSquared: CGFloat = 0
    private var intentVelocityThreshold: CGFloat = 0
    private var allowMouseTakeoverDuringTyping = false
    private var typingGraceDeadline: TimeInterval?
    private var typingGraceTask: Task<Void, Never>?
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
    private let edgeSlideStartThreshold: CGFloat = 0.03
    private let edgeSlideStayThreshold: CGFloat = 0.08
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
    private let cornerClickForceThreshold: Float = 125.0
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

    struct StatusSnapshot: Sendable {
        let contactCounts: SidePair<Int>
        let intentDisplays: SidePair<IntentDisplay>
        let typingEnabled: Bool
        let keyboardModeEnabled: Bool
        let voiceGestureActive: Bool
        let dispatchQueueDepth: Int
        let dispatchDrops: UInt64
    }

#if DEBUG
    private let signposter = OSSignposter(
        subsystem: "com.kyome.GlassToKey",
        category: "TouchProcessing"
    )
#endif

    init(
        dispatchService: DispatchService,
        onTypingEnabledChanged: @Sendable @escaping (Bool) -> Void,
        onActiveLayerChanged: @Sendable @escaping (Int) -> Void,
        onDebugBindingDetected: @Sendable @escaping (KeyBinding) -> Void,
        onContactCountChanged: @Sendable @escaping (SidePair<Int>) -> Void,
        onIntentStateChanged: @Sendable @escaping (SidePair<IntentDisplay>) -> Void,
        onVoiceGestureChanged: @Sendable @escaping (Bool) -> Void
    ) {
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

    func statusSnapshot() -> StatusSnapshot {
        let dispatchMetrics = dispatchService.snapshotMetrics()
        return StatusSnapshot(
            contactCounts: contactFingerCountsBySide,
            intentDisplays: intentDisplayBySide,
            typingEnabled: isTypingEnabled,
            keyboardModeEnabled: keyboardModeEnabled,
            voiceGestureActive: voiceGestureActive,
            dispatchQueueDepth: dispatchMetrics.queueDepth,
            dispatchDrops: dispatchMetrics.drops
        )
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
        let clamped = max(0, seconds)
        holdMinDuration = clamped
        tapMaxDuration = clamped
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
        keyboardModeEnabled = enabled
    }

    func updateHoldRepeatEnabled(_ enabled: Bool) {
        holdRepeatEnabled = enabled
    }

    func processRawFrame(_ frame: OMSRawTouchFrame) {
        guard isListening,
              let leftLayout,
              let rightLayout else {
            return
        }
        if leftDeviceIndex == nil && rightDeviceIndex == nil {
            return
        }
        let now = frame.timestamp
        currentProcessingTimestamp = now
        defer { currentProcessingTimestamp = nil }
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
        let allowTypingLeft = allowTypingGlobal || isChordShiftActive(on: .right)
        let allowTypingRight = allowTypingGlobal || isChordShiftActive(on: .left)
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
    }

    func processRuntimeRawFrame(_ frame: RuntimeRawFrame) {
        guard isListening,
              let leftLayout,
              let rightLayout else {
            return
        }
        if leftDeviceIndex == nil && rightDeviceIndex == nil {
            return
        }
        let now = frame.timestamp
        currentProcessingTimestamp = now
        defer { currentProcessingTimestamp = nil }
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
        let allowTypingLeft = allowTypingGlobal || isChordShiftActive(on: .right)
        let allowTypingRight = allowTypingGlobal || isChordShiftActive(on: .left)
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

    private func processTouches(
        _ touches: [OMSRawTouch],
        deviceIndex: Int,
        bindings: BindingIndex,
        layout: Layout,
        canvasSize: CGSize,
        isLeftSide: Bool,
        now: TimeInterval,
        intentAllowsTyping: Bool
    ) {
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
        let chordShiftSuppressed = isChordShiftActive(on: side)
        let cornersHoldEngaged = voiceDictationGestureState.holdCandidateActive
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
            if chordShiftSuppressed {
                if disqualifiedTouches.value(for: touchKey) == nil {
                    disqualifyTouch(touchKey, reason: .typingDisabled)
                }
                switch touch.state {
                case .breaking, .leaving, .notTouching:
                    disqualifiedTouches.remove(touchKey)
                    touchInitialContactPoint.remove(touchKey)
                    clearPeakPressure(for: touchKey)
                case .starting, .hovering, .making, .touching, .lingering:
                    break
                @unknown default:
                    break
                }
                continue
            }
            if cornersHoldEngaged {
                var isCustomTouch = false
                var isContinuousTouch = false
                if let binding = resolveBinding(), binding.position == nil {
                    isCustomTouch = true
                    if isContinuousKey(binding) {
                        isContinuousTouch = true
                    }
                } else if let active = activeTouch(for: touchKey), active.binding.position == nil {
                    isCustomTouch = true
                    if active.isContinuousKey {
                        isContinuousTouch = true
                    }
                } else if let pending = pendingTouch(for: touchKey), pending.binding.position == nil {
                    isCustomTouch = true
                    if isContinuousKey(pending.binding) {
                        isContinuousTouch = true
                    }
                } else {
                    if let binding = resolveBinding(), isContinuousKey(binding) {
                        isContinuousTouch = true
                    } else if let active = activeTouch(for: touchKey), active.isContinuousKey {
                        isContinuousTouch = true
                    } else if let pending = pendingTouch(for: touchKey),
                              isContinuousKey(pending.binding) {
                        isContinuousTouch = true
                    }
                }
                if isCustomTouch || isContinuousTouch {
                    if disqualifiedTouches.value(for: touchKey) == nil {
                        disqualifyTouch(touchKey, reason: .typingDisabled)
                    }
                    switch touch.state {
                    case .breaking, .leaving, .notTouching:
                        disqualifiedTouches.remove(touchKey)
                        touchInitialContactPoint.remove(touchKey)
                        clearPeakPressure(for: touchKey)
                    case .starting, .hovering, .making, .touching, .lingering:
                        break
                    @unknown default:
                        break
                    }
                    continue
                }
            }
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
            if toggleTouchStarts.value(for: touchKey) != nil {
                handleTypingToggleTouch(
                    touchKey: touchKey,
                    state: touch.state,
                    point: point
                )
                continue
            }
            if let binding = resolveBinding() {
                switch binding.action {
                case .typingToggle:
                    handleTypingToggleTouch(
                        touchKey: touchKey,
                        state: touch.state,
                        point: point
                    )
                    continue
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
                     .volumeUp, .volumeDown, .brightnessUp, .brightnessDown,
                     .chordalShift,
                     .voice,
                     .gestureTwoFingerTap, .gestureThreeFingerTap, .gestureFourFingerHold,
                     .gestureInnerCornersHold, .gestureFiveFingerSwipeLeft, .gestureFiveFingerSwipeRight:
                    break
                }
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
                       now - active.startTime >= holdMinDuration,
                       (!isDragDetectionEnabled || active.maxDistanceSquared <= dragCancelDistanceSquared) {
                        let dispatchInfo = makeDispatchInfo(
                            kind: .hold,
                            startTime: active.startTime,
                            maxDistanceSquared: active.maxDistanceSquared,
                            now: now
                        )
                        var updated = active
                        let holdDispatchBinding = active.holdBinding ?? active.binding
                        if beginHoldRepeat(
                                for: touchKey,
                                binding: holdDispatchBinding,
                                pressure: peakPressure
                            ) {
                            updated.holdRepeatActive = true
                        } else {
                            triggerBinding(
                                holdDispatchBinding,
                                touchKey: touchKey,
                                dispatchInfo: dispatchInfo,
                                pressure: peakPressure
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
        intentRemovalBuffer.removeAll(keepingCapacity: true)
        touchStates.forEach { touchKey, _ in
            guard Self.touchKeyDeviceIndex(touchKey) == deviceIndex,
                  frameTouchKeys.value(for: touchKey) == nil else {
                return
            }
            intentRemovalBuffer.append(touchKey)
        }

        for touchKey in intentRemovalBuffer {
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
        if toggleTouchStarts.value(for: touchKey) != nil {
            handleTypingToggleTouch(
                touchKey: touchKey,
                state: .notTouching,
                point: point
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
            || isChordShiftActive(on: .left)
            || isChordShiftActive(on: .right)
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
            case .brightnessUp:
                action = .brightnessUp
            case .brightnessDown:
                action = .brightnessDown
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
                side: button.side,
                holdAction: button.hold
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
        return makeBinding(
            for: action,
            rect: rect,
            normalizedRect: normalizedRect,
            canvasSize: canvasSize,
            position: position,
            side: position.side,
            holdAction: holdAction
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

    private func makeBinding(
        for action: KeyAction,
        rect: CGRect,
        normalizedRect: NormalizedRect,
        canvasSize: CGSize,
        position: GridKeyPosition?,
        side: TrackpadSide,
        holdAction: KeyAction? = nil
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
                side: side,
                holdAction: holdAction
            )
        case .appLaunch:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .appLaunch(action.label),
                position: position,
                side: side,
                holdAction: holdAction
            )
        case .leftClick:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .leftClick,
                position: position,
                side: side,
                holdAction: holdAction
            )
        case .doubleClick:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .doubleClick,
                position: position,
                side: side,
                holdAction: holdAction
            )
        case .rightClick:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .rightClick,
                position: position,
                side: side,
                holdAction: holdAction
            )
        case .middleClick:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                canvasSize: canvasSize,
                label: action.label,
                action: .middleClick,
                position: position,
                side: side,
                holdAction: holdAction
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
                holdAction: holdAction
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
                holdAction: holdAction
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
                holdAction: holdAction
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
                holdAction: holdAction
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
                holdAction: holdAction
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
                holdAction: holdAction
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
                holdAction: holdAction
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
                holdAction: holdAction
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
                holdAction: holdAction
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
                holdAction: holdAction
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
                holdAction: holdAction
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
                holdAction: holdAction
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
                holdAction: holdAction
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
                holdAction: holdAction
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
                holdAction: holdAction
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
                holdAction: holdAction
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
        case .typingCommitted, .keyCandidate:
            return true
        case .mouseActive, .mouseCandidate, .gestureCandidate, .idle:
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
            altAscii: altAscii
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

    private static func isContactState(_ state: OpenMTState) -> Bool {
        switch state {
        case .starting, .making, .touching:
            return true
        default:
            return false
        }
    }

    private static func isIntentContactState(_ state: OpenMTState) -> Bool {
        switch state {
        case .starting, .making, .touching, .breaking, .leaving:
            return true
        default:
            return false
        }
    }

    private static func isTerminalReleaseState(_ state: OpenMTState) -> Bool {
        switch state {
        case .breaking, .leaving, .notTouching:
            return true
        default:
            return false
        }
    }

    private static func isChordShiftContactState(_ state: OpenMTState) -> Bool {
        switch state {
        case .starting, .making, .touching, .breaking, .leaving, .lingering:
            return true
        default:
            return false
        }
    }

    private static func isDictationContactState(_ state: OpenMTState) -> Bool {
        switch state {
        case .starting, .making, .touching, .lingering:
            return true
        default:
            return false
        }
    }

    private func gestureContactSummary(in touches: [OMSRawTouch]) -> GestureContactSummary {
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

    private func updateSideGestures(for side: TrackpadSide, touches: [OMSRawTouch], now: TimeInterval) {
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

    private func updateIntent(
        leftTouches: [OMSRawTouch],
        rightTouches: [OMSRawTouch],
        leftDeviceIndex: Int?,
        rightDeviceIndex: Int?,
        now: TimeInterval,
        leftBindings: BindingIndex,
        rightBindings: BindingIndex
    ) -> Bool {
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

    private func updateIntentGlobal(
        leftTouches: [OMSRawTouch],
        rightTouches: [OMSRawTouch],
        leftDeviceIndex: Int?,
        rightDeviceIndex: Int?,
        leftBindings: BindingIndex,
        rightBindings: BindingIndex,
        now: TimeInterval,
        moveThresholdSquared: CGFloat,
        velocityThreshold: CGFloat,
        unitsPerMm: CGFloat,
        bindingCacheBySide: inout SidePair<TouchTable<KeyBinding>>
    ) -> Bool {
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

            let binding = binding(at: point, index: bindings)
            if let binding {
                bindingCacheBySide[side].set(touchKey, binding)
                onKeyCount += 1
                if firstOnKeyTouchKey == nil {
                    firstOnKeyTouchKey = touchKey
                }
                if modifierKey(for: binding) != nil || isContinuousKey(binding) {
                    hasKeyboardAnchor = true
                }
            } else {
                offKeyCount += 1
            }

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

        let centroid: CGPoint? = contactCount > 0
            ? CGPoint(x: sumX / CGFloat(contactCount), y: sumY / CGFloat(contactCount))
            : nil
        let _: CGPoint? = gestureContactCount > 0
            ? CGPoint(x: gestureSumX / CGFloat(gestureContactCount), y: gestureSumY / CGFloat(gestureContactCount))
            : nil
        let previousContactCount = state.lastContactCount
        let secondFingerAppeared = contactCount > 1 && contactCount > previousContactCount
        let anyOnKey = onKeyCount > 0
        let anyOffKey = offKeyCount > 0
        var centroidMoved = false
        if case let .keyCandidate(_, _, startCentroid) = state.mode,
           let centroid {
            centroidMoved = distanceSquared(from: startCentroid, to: centroid) > moveThresholdSquared
        }
        let velocitySignal = maxVelocity > velocityThreshold
            && maxDistanceSquared > (moveThresholdSquared * 0.25)
        let mouseSignal = maxDistanceSquared > moveThresholdSquared
            || velocitySignal
            || (secondFingerAppeared && anyOffKey)
            || centroidMoved

        let wasTwoFingerTapDetected = twoFingerTapDetected
        let isTypingCommitted: Bool
        if case .typingCommitted = state.mode {
            isTypingCommitted = true
        } else {
            isTypingCommitted = false
        }
        let suppressTapClicks = isTypingEnabled && (graceActive || isTypingCommitted)
        if cornerHoldGestureEngaged {
            twoFingerTapCandidate = nil
            threeFingerTapCandidate = nil
            twoFingerTapDetected = false
            threeFingerTapDetected = false
            awaitingSecondTap = false
            doubleTapDeadline = nil
        }
        guard contactCount > 0 else {
            state.touches.removeAll()
            if gestureContactCount == 0, !momentaryLayerTouches.isEmpty {
                momentaryLayerTouches.removeAll()
                updateActiveLayer()
            }
            if suppressTapClicks {
                awaitingSecondTap = false
                doubleTapDeadline = nil
            } else if threeFingerTapDetected {
                performGestureAction(
                    threeFingerTapAction,
                    now: now,
                    side: nil,
                    bindingId: GestureBindingID.threeFingerTap
                )
            } else if wasTwoFingerTapDetected {
                performTwoFingerTapAction(now: now)
            }
            if graceActive {
                state.mode = .typingCommitted(untilAllUp: true)
                intentState = state
                updateIntentDisplayIfNeeded()
                return true
            }
            state.mode = .idle
            intentState = state
            updateIntentDisplayIfNeeded()
            return true
        }

        if cornerHoldGestureEngaged {
            state.lastContactCount = contactCount
            state.mode = .gestureCandidate(start: voiceDictationGestureState.holdStart > 0 ? voiceDictationGestureState.holdStart : now)
            suppressKeyProcessing(for: intentCurrentKeys)
            intentState = state
            updateIntentDisplayIfNeeded()
            return false
        }

        if keyboardOnly {
            state.lastContactCount = contactCount
            state.mode = .typingCommitted(untilAllUp: true)
            intentState = state
            updateIntentDisplayIfNeeded()
            return true
        }

        if let gestureStart = gestureCandidateStartTime(
            for: state,
            contactCount: contactCount,
            previousContactCount: previousContactCount
        ) {
            state.mode = .gestureCandidate(start: gestureStart)
            intentState = state
            updateIntentDisplayIfNeeded()
            return false
        }
        if case .gestureCandidate = state.mode,
           contactCount < 2 {
            state.mode = .idle
        }

        state.lastContactCount = contactCount

        // While typing grace is active, keep typing committed and skip mouse intent checks.
        if graceActive {
            state.mode = .typingCommitted(untilAllUp: !allowMouseTakeoverDuringTyping)
            intentState = state
            updateIntentDisplayIfNeeded()
            return true
        }

        let typingAnchorActive = hasKeyboardAnchor && contactCount <= 1
        let allowTyping: Bool
        switch state.mode {
        case .idle:
            if graceActive || typingAnchorActive {
                state.mode = .typingCommitted(untilAllUp: !allowMouseTakeoverDuringTyping)
                intentState = state
                updateIntentDisplayIfNeeded()
                return true
            }
            if anyOnKey && !mouseSignal, let touchKey = firstOnKeyTouchKey, let centroid {
                state.mode = .keyCandidate(start: now, touchKey: touchKey, centroid: centroid)
                allowTyping = false
            } else {
                state.mode = .mouseCandidate(start: now)
                allowTyping = false
            }
        case let .keyCandidate(start, _, _):
            if graceActive || typingAnchorActive {
                state.mode = .typingCommitted(untilAllUp: !allowMouseTakeoverDuringTyping)
                intentState = state
                updateIntentDisplayIfNeeded()
                return true
            }
            if mouseSignal {
                state.mode = .mouseCandidate(start: now)
                allowTyping = false
            } else if now - start >= intentConfig.keyBufferSeconds {
                state.mode = .typingCommitted(untilAllUp: !allowMouseTakeoverDuringTyping)
                allowTyping = true
            } else {
                allowTyping = false
            }
        case let .typingCommitted(untilAllUp):
            if graceActive || typingAnchorActive {
                state.mode = .typingCommitted(untilAllUp: untilAllUp)
                allowTyping = true
            } else if untilAllUp {
                allowTyping = true
            } else if mouseSignal {
                state.mode = .mouseActive
                allowTyping = false
            } else {
                allowTyping = true
            }
        case let .mouseCandidate(start):
            if graceActive || typingAnchorActive {
                state.mode = .typingCommitted(untilAllUp: !allowMouseTakeoverDuringTyping)
                intentState = state
                updateIntentDisplayIfNeeded()
                return true
            }
            if mouseSignal || now - start >= intentConfig.keyBufferSeconds {
                state.mode = .mouseActive
                allowTyping = false
            } else {
                allowTyping = false
            }
        case .mouseActive:
            if graceActive || typingAnchorActive {
                state.mode = .typingCommitted(untilAllUp: !allowMouseTakeoverDuringTyping)
                allowTyping = true
            } else {
                allowTyping = false
            }
        case .gestureCandidate:
            allowTyping = false
        }

        intentState = state
        updateIntentDisplayIfNeeded()
        return allowTyping
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


    @inline(__always)
    private func isTypingGraceActive(now: TimeInterval? = nil) -> Bool {
        let currentNow = now ?? currentTime()
        if let deadline = typingGraceDeadline, currentNow < deadline {
            return true
        }
        typingGraceDeadline = nil
        return false
    }

    private func suppressKeyProcessing(for touchKeys: TouchTable<Bool>) {
        if isTypingGraceActive() {
            return
        }
        touchKeys.forEach { touchKey, _ in
            if momentaryLayerTouches.value(for: touchKey) != nil {
                return
            }
            disqualifyTouch(touchKey, reason: .intentMouse)
            toggleTouchStarts.remove(touchKey)
            layerToggleTouchStarts.remove(touchKey)
        }
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

    private func updateSingleTouchShapeGestures(
        for side: TrackpadSide,
        touches: [OMSRawTouch],
        now: TimeInterval
    ) {
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
           pressure >= cornerClickForceThreshold {
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
               cornerForceClickOverrideAction(for: state.corner).kind == .none,
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
            state.forceArmed = touch.pressure >= cornerClickForceThreshold
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
        state.forceArmed = state.forceArmed || state.peakPressure >= cornerClickForceThreshold
        state.lastX = point.x
        state.lastY = point.y
        state.maxDistanceMm = max(state.maxDistanceMm, normalizedDistanceMm(from: CGPoint(x: state.startX, y: state.startY), to: point))
        if state.maxDistanceMm > dragCancelDistance
            || now - state.startTime > cornerClickMaxDuration
            || classifyCorner(point, threshold: cornerClickZoneThreshold) != state.corner
            || cornerForceClickOverrideAction(for: state.corner).kind != .none && isPressureWithinForceRange(state.peakPressure) {
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
           isPressureWithinForceRange(state.peakPressure),
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
                dispatchService.postLeftClick(clickCount: 2)
                awaitingSecondTap = false
                doubleTapDeadline = nil
            } else {
                dispatchService.postLeftClick()
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
            dispatchService.postAppLaunch(action.label)
        case .leftClick:
            dispatchService.postLeftClick()
        case .doubleClick:
            dispatchService.postLeftClick(clickCount: 2)
        case .rightClick:
            dispatchService.postRightClick()
        case .middleClick:
            dispatchService.postMiddleClick()
        case .volumeUp:
            if tryBeginRepeatableGestureDispatch(bindingId: bindingId, action: action, side: side) {
                return
            }
            dispatchService.postVolumeUp()
        case .volumeDown:
            if tryBeginRepeatableGestureDispatch(bindingId: bindingId, action: action, side: side) {
                return
            }
            dispatchService.postVolumeDown()
        case .brightnessUp:
            if tryBeginRepeatableGestureDispatch(bindingId: bindingId, action: action, side: side) {
                return
            }
            dispatchService.postBrightnessUp()
        case .brightnessDown:
            if tryBeginRepeatableGestureDispatch(bindingId: bindingId, action: action, side: side) {
                return
            }
            dispatchService.postBrightnessDown()
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
        case .key, .layerMomentary, .layerToggle:
            guard let binding = makeBinding(
                for: action,
                rect: .zero,
                normalizedRect: NormalizedRect(x: 0, y: 0, width: 0, height: 0),
                canvasSize: .zero,
                position: nil,
                side: side ?? .left
            ) else {
                return
            }
            if tryBeginRepeatableGestureDispatch(bindingId: bindingId, action: action, side: side) {
                return
            }
            triggerBinding(binding, touchKey: nil)
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

    private func outerCornersHoldSide(
        leftTouches: [OMSRawTouch],
        rightTouches: [OMSRawTouch]
    ) -> TrackpadSide? {
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

    private func innerCornersHoldSide(
        leftTouches: [OMSRawTouch],
        rightTouches: [OMSRawTouch]
    ) -> TrackpadSide? {
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
        VoiceDictationManager.shared.beginSession()
        updateVoiceGestureActivity()
    }

    private func endVoiceDictationSession() {
        guard voiceDictationGestureState.isDictating else { return }
        voiceDictationGestureState.isDictating = false
        VoiceDictationManager.shared.endSession()
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

    private func handleTypingToggleTouch(
        touchKey: TouchKey,
        state: OpenMTState,
        point: CGPoint
    ) {
        switch state {
        case .starting, .making, .touching:
            if toggleTouchStarts.value(for: touchKey) == nil {
                toggleTouchStarts.set(touchKey, currentTime())
            }
        case .breaking, .leaving:
            let didStart = toggleTouchStarts.remove(touchKey)
            if didStart != nil {
                let maxDistance = dragCancelDistance * dragCancelDistance
                let initialPoint = touchInitialContactPoint.value(for: touchKey)
                let distance = initialPoint
                    .map { distanceSquared(from: $0, to: point) } ?? 0
                if distance <= maxDistance {
                    toggleTypingMode()
                }
            }
            touchInitialContactPoint.remove(touchKey)
        case .notTouching:
            toggleTouchStarts.remove(touchKey)
            touchInitialContactPoint.remove(touchKey)
        case .hovering, .lingering:
            break
        @unknown default:
            break
        }
    }

    private func handleLayerToggleTouch(
        touchKey: TouchKey,
        state: OpenMTState,
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
        state: OpenMTState,
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

    private func allowsPriorityTyping(for binding: KeyBinding) -> Bool {
        let state = intentState
        let isModifier = modifierKey(for: binding) != nil
        let isContinuous = isContinuousKey(binding)
        guard isModifier || isContinuous else { return false }
        switch state.mode {
        case .keyCandidate, .mouseCandidate, .typingCommitted:
            return true
        case .mouseActive:
            return isModifier
        case .gestureCandidate:
            return false
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
        guard isTapDispatchAllowedForCurrentIntent() else { return false }
        let startTime = touchInfo?.startTime ?? fallbackStartTime ?? now
        let releaseStartPoint = touchInitialContactPoint.value(for: touchKey) ?? point
        let releaseDistanceSquared = distanceSquared(from: releaseStartPoint, to: point)
        let maxDistanceSquared = max(
            max(touchInfo?.maxDistanceSquared ?? 0, fallbackMaxDistanceSquared),
            releaseDistanceSquared
        )
        guard now - startTime <= tapMaxDuration else { return false }
        if isDragDetectionEnabled, releaseDistanceSquared > dragCancelDistance * dragCancelDistance {
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
            return attemptSnapOnRelease(
                touchKey: touchKey,
                point: point,
                bindings: bindings,
                pressure: pressure
            )
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

        return attemptSnapOnRelease(
            touchKey: touchKey,
            point: point,
            bindings: bindings,
            pressure: pressure
        )
    }

    private func isTapDispatchAllowedForCurrentIntent() -> Bool {
        switch intentState.mode {
        case .gestureCandidate:
            return false
        case .idle, .keyCandidate, .typingCommitted, .mouseCandidate, .mouseActive:
            return true
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
        switch binding.action {
        case let .appLaunch(actionLabel):
            dispatchService.postAppLaunch(actionLabel)
        case let .layerMomentary(layer):
            guard let touchKey else { return }
            momentaryLayerTouches.set(touchKey, layer)
            updateActiveLayer()
        case let .layerToggle(layer):
            toggleLayer(to: layer)
        case .typingToggle:
            toggleTypingMode()
        case .leftClick:
            dispatchService.postLeftClick()
        case .doubleClick:
            dispatchService.postLeftClick(clickCount: 2)
        case .rightClick:
            dispatchService.postRightClick()
        case .middleClick:
            dispatchService.postMiddleClick()
        case .volumeUp:
            dispatchService.postVolumeUp()
        case .volumeDown:
            dispatchService.postVolumeDown()
        case .brightnessUp:
            dispatchService.postBrightnessUp()
        case .brightnessDown:
            dispatchService.postBrightnessDown()
        case .voice:
            toggleVoiceDictationSession()
        case .chordalShift:
            break
        case .gestureTwoFingerTap:
            triggerGestureSlot(.twoFingerTap, side: binding.side, bindingId: nil, visited: [])
        case .gestureThreeFingerTap:
            triggerGestureSlot(.threeFingerTap, side: binding.side, bindingId: nil, visited: [])
        case .gestureFourFingerHold:
            triggerGestureSlot(.fourFingerHold, side: binding.side, bindingId: nil, visited: [])
        case .gestureInnerCornersHold:
            triggerGestureSlot(.innerCornersHold, side: binding.side, bindingId: nil, visited: [])
        case .gestureFiveFingerSwipeLeft:
            triggerGestureSlot(.fiveFingerSwipeLeft, side: binding.side, bindingId: nil, visited: [])
        case .gestureFiveFingerSwipeRight:
            triggerGestureSlot(.fiveFingerSwipeRight, side: binding.side, bindingId: nil, visited: [])
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
        altAscii: UInt8 = 0
    ) {
        let resolvedFlags = combinedFlags ?? flags.union(currentModifierFlags())
        dispatchService.postKeyStroke(code: code, flags: resolvedFlags, altAscii: altAscii)
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
            return
        }
        #if DEBUG
        onDebugBindingDetected(binding)
#endif
        extendTypingGrace(for: binding.side, now: currentTime())
        playHapticIfNeeded(on: binding.side, touchKey: touchKey)
        sendKey(code: code, flags: flags, side: binding.side)
    }

    private func playHapticIfNeeded(on side: TrackpadSide?, touchKey: TouchKey? = nil) {
        guard hapticStrength > 0 else { return }
        guard let side else { return }
        if let touchKey, disqualifiedTouches.value(for: touchKey) != nil { return }
        let now = Self.nowUptimeNanoseconds()
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
        dispatchService.postHaptic(strength: hapticStrength, deviceID: deviceID)
    }

    @discardableResult
    private func beginHoldRepeat(
        for touchKey: TouchKey,
        binding: KeyBinding,
        pressure: Float? = nil
    ) -> Bool {
        guard canHoldRepeat(binding: binding) else { return false }
        if let pressure, !isPressureWithinForceRange(pressure) {
            return false
        }
        #if DEBUG
        onDebugBindingDetected(binding)
        #endif
        extendTypingGrace(for: binding.side, now: currentTime())
        playHapticIfNeeded(on: binding.side, touchKey: touchKey)
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
        startRepeatEntry(
            for: owner,
            initialDelay: initialDelay,
            interval: interval,
            fireInitial: {
                dispatchService.postKey(code: code, flags: repeatFlags, keyDown: true)
            },
            fire: { token in
                dispatchService.postKey(code: code, flags: repeatFlags, keyDown: true, token: token)
            },
            stop: {
                dispatchService.postKey(code: code, flags: repeatFlags, keyDown: false)
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
        startRepeatEntry(
            for: owner,
            initialDelay: initialDelay,
            interval: interval,
            fireInitial: {
                switch systemKey {
                case .volumeUp:
                    dispatchService.postVolumeUp()
                case .volumeDown:
                    dispatchService.postVolumeDown()
                case .brightnessUp:
                    dispatchService.postBrightnessUp()
                case .brightnessDown:
                    dispatchService.postBrightnessDown()
                }
            },
            fire: { _ in
                switch systemKey {
                case .volumeUp:
                    dispatchService.postVolumeUp()
                case .volumeDown:
                    dispatchService.postVolumeDown()
                case .brightnessUp:
                    dispatchService.postBrightnessUp()
                case .brightnessDown:
                    dispatchService.postBrightnessDown()
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
        let nextFire = Self.nowUptimeNanoseconds() &+ initialDelay
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
        guard repeatLoopTask == nil else { return }
        repeatLoopTask = Task.detached(priority: .userInitiated) { [weak self] in
            await self?.repeatLoop()
        }
    }

    private func repeatLoop() async {
        while !Task.isCancelled {
            let now = Self.nowUptimeNanoseconds()
            guard let delay = nextRepeatDelay(now: now) else {
                repeatLoopTask = nil
                return
            }
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            await fireRepeats(now: Self.nowUptimeNanoseconds())
        }
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

    private func fireRepeats(now: UInt64) async {
        guard !repeatEntries.isEmpty else { return }
        var toRemove: [RepeatOwner] = []
        for (key, var entry) in repeatEntries {
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
        if repeatEntries.isEmpty {
            repeatLoopTask?.cancel()
            repeatLoopTask = nil
        }
    }

    private func stopRepeat(for owner: RepeatOwner) {
        if let entry = repeatEntries.removeValue(forKey: owner) {
            entry.token.deactivate()
            entry.stop()
        }
        if repeatEntries.isEmpty {
            repeatLoopTask?.cancel()
            repeatLoopTask = nil
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
        case .volumeUp, .volumeDown, .brightnessUp, .brightnessDown:
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
            guard let binding = makeBinding(
                for: action,
                rect: .zero,
                normalizedRect: NormalizedRect(x: 0, y: 0, width: 0, height: 0),
                canvasSize: .zero,
                position: nil,
                side: side ?? .left
            ) else {
                return false
            }
            startRepeat(for: owner, binding: binding, initialDelay: cadenceNs, interval: cadenceNs)
            return true
        case .volumeUp:
            startSystemKeyRepeat(for: owner, systemKey: .volumeUp, initialDelay: cadenceNs, interval: cadenceNs)
            return true
        case .volumeDown:
            startSystemKeyRepeat(for: owner, systemKey: .volumeDown, initialDelay: cadenceNs, interval: cadenceNs)
            return true
        case .brightnessUp:
            startSystemKeyRepeat(for: owner, systemKey: .brightnessUp, initialDelay: cadenceNs, interval: cadenceNs)
            return true
        case .brightnessDown:
            startSystemKeyRepeat(for: owner, systemKey: .brightnessDown, initialDelay: cadenceNs, interval: cadenceNs)
            return true
        default:
            return false
        }
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
        dispatchService.postKey(code: code, flags: flags, keyDown: keyDown)
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
        if stopVoiceDictation {
            stopVoiceDictationGesture()
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
        toggleTouchStarts.removeAll()
        layerToggleTouchStarts.removeAll()
        momentaryLayerTouches.removeAll()
        touchInitialContactPoint.removeAll()
        typingGraceDeadline = nil
        typingGraceTask?.cancel()
        typingGraceTask = nil
        updateActiveLayer()
        intentState = IntentState()
        updateIntentDisplayIfNeeded()
    }

    private func disqualifyTouch(_ touchKey: TouchKey, reason: DisqualifyReason) {
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
        typingGraceTask?.cancel()
        typingGraceTask = nil
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
        typingGraceTask?.cancel()
        let delay = max(0, deadline - currentTime())
        let nanoseconds = UInt64(delay * 1_000_000_000)
        typingGraceTask = Task { [weak self] in
            if nanoseconds > 0 {
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
            await self?.expireTypingGraceIfNeeded(deadline: deadline)
        }
    }

    private func expireTypingGraceIfNeeded(deadline: TimeInterval) {
        guard let currentDeadline = typingGraceDeadline,
              currentDeadline == deadline,
              currentTime() >= deadline else {
            return
        }
        typingGraceDeadline = nil
        typingGraceTask = nil
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
        currentProcessingTimestamp ?? CACurrentMediaTime()
    }

    private func notifyContactCounts() {
        guard contactFingerCountsBySide != lastReportedContactCounts else { return }
        lastReportedContactCounts = contactFingerCountsBySide
        onContactCountChanged(contactFingerCountsBySide)
    }

    private func gestureCandidateStartTime(
        for state: IntentState,
        contactCount: Int,
        previousContactCount: Int
    ) -> TimeInterval? {
        if contactCount >= 3 {
            guard previousContactCount != 2 else { return nil }
            var minTime = TimeInterval.greatestFiniteMagnitude
            var maxTime: TimeInterval = 0
            var count = 0
            state.touches.forEach { _, info in
                count += 1
                minTime = min(minTime, info.startTime)
                maxTime = max(maxTime, info.startTime)
            }
            guard count >= 3,
                  maxTime - minTime <= intentConfig.keyBufferSeconds else {
                return nil
            }
            return minTime
        }
        guard contactCount >= 2,
              previousContactCount <= 1 else {
            return nil
        }
        var minTime = TimeInterval.greatestFiniteMagnitude
        var maxTime: TimeInterval = 0
        var count = 0
        state.touches.forEach { _, info in
            count += 1
            minTime = min(minTime, info.startTime)
            maxTime = max(maxTime, info.startTime)
        }
        guard count >= 2,
              maxTime - minTime <= intentConfig.keyBufferSeconds else {
            return nil
        }
        return minTime
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
