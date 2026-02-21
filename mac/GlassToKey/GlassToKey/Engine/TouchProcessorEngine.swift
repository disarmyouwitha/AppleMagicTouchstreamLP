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
        case command
    }

    private enum DisqualifyReason: String {
        case dragCancelled
        case pendingDragCancelled
        case leftContinuousRect
        case leftKeyRect
        case pendingLeftRect
        case typingDisabled
        case forceCapExceeded
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
        let initialPressure: Float
        var forceEntryTime: TimeInterval?
        var forceGuardTriggered: Bool
        var modifierEngaged: Bool

    }
    private struct PendingTouch {
        let binding: KeyBinding
        let layer: Int
        let startTime: TimeInterval
        let startPoint: CGPoint
        var maxDistanceSquared: CGFloat
        let initialPressure: Float
        var forceEntryTime: TimeInterval?
        var forceGuardTriggered: Bool

    }

    private struct RepeatEntry {
        let code: CGKeyCode
        let flags: CGEventFlags
        let token: RepeatToken
        let interval: UInt64
        var nextFire: UInt64
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
                guard binding.rect.contains(point) else { continue }
                let score = insideDistanceToRectEdge(point: point, rect: binding.rect)
                let area = binding.rect.width * binding.rect.height
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
                guard binding.normalizedRect.contains(clampedPoint) else { continue }
                let score = insideDistanceToNormalizedRectEdge(
                    point: clampedPoint,
                    rect: binding.normalizedRect
                )
                let area = binding.normalizedRect.width * binding.normalizedRect.height
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

        @inline(__always)
        private func insideDistanceToRectEdge(point: CGPoint, rect: CGRect) -> CGFloat {
            let dx = min(point.x - rect.minX, rect.maxX - point.x)
            let dy = min(point.y - rect.minY, rect.maxY - point.y)
            return min(dx, dy)
        }

        @inline(__always)
        private func insideDistanceToNormalizedRectEdge(point: CGPoint, rect: NormalizedRect) -> CGFloat {
            let minX = rect.x
            let maxX = rect.x + rect.width
            let minY = rect.y
            let maxY = rect.y + rect.height
            let dx = min(point.x - minX, maxX - point.x)
            let dy = min(point.y - minY, maxY - point.y)
            return min(dx, dy)
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
    private var leftShiftTouchCount = 0
    private var controlTouchCount = 0
    private var optionTouchCount = 0
    private var commandTouchCount = 0
    private var repeatEntries: [TouchKey: RepeatEntry] = [:]
    private var repeatLoopTask: Task<Void, Never>?
    private var toggleTouchStarts = TouchTable<TimeInterval>()
    private var layerToggleTouchStarts = TouchTable<Int>()
    private var momentaryLayerTouches = MomentaryLayerTouches()
    private var lastMomentaryLayer: Int?
    private var touchInitialContactPoint = TouchTable<CGPoint>()
    private var tapMaxDuration: TimeInterval = 0.2
    private var holdMinDuration: TimeInterval = 0.2
    private var dragCancelDistance: CGFloat = 2.5
    private var forceClickCap: Float = 0
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
    private var intentCurrentKeys = TouchTable<Bool>(minimumCapacity: 16)
    private var intentRemovalBuffer: [TouchKey] = []
    private var unitsPerMillimeter: CGFloat = 1.0
    private var intentMoveThresholdSquared: CGFloat = 0
    private var intentVelocityThreshold: CGFloat = 0
    private var allowMouseTakeoverDuringTyping = false
    private var tapClickEnabled = false
    private var typingGraceDeadline: TimeInterval?
    private var typingGraceTask: Task<Void, Never>?
    private var doubleTapDeadline: TimeInterval?
    private var awaitingSecondTap = false
    private var tapClickCadenceSeconds: TimeInterval = 0.28
    private struct TapCandidate {
        let deadline: TimeInterval
    }
    private var twoFingerTapCandidate: TapCandidate?
    private var threeFingerTapCandidate: TapCandidate?
    private struct FiveFingerSwipeState {
        var active: Bool = false
        var triggered: Bool = false
        var startTime: TimeInterval = 0
        var startX: CGFloat = 0
        var startY: CGFloat = 0
    }
    private var fiveFingerSwipeState = FiveFingerSwipeState()
    private let fiveFingerSwipeThresholdMm: CGFloat = 8.0
    private struct ChordShiftState {
        var active: Bool = false
    }
    private struct VoiceDictationGestureState {
        var holdStart: TimeInterval = 0
        var holdCandidateActive = false
        var holdDidToggle = false
        var isDictating = false
        var side: TrackpadSide?
    }
    private var chordShiftEnabled = true
    private var chordShiftState = SidePair(left: ChordShiftState(), right: ChordShiftState())
    private var chordShiftLastContactTime = SidePair(left: TimeInterval(0), right: TimeInterval(0))
    private var chordShiftKeyDown = false
    private var voiceDictationGestureState = VoiceDictationGestureState()
    private var voiceGestureActive = false
    private let voiceDictationHoldSeconds: TimeInterval = 0.35
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
        let clamped = max(0, min(layer, 1))
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

    func updateForceClickCap(_ grams: Double) {
        forceClickCap = Float(max(0, grams))
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

    func updateTapClickEnabled(_ enabled: Bool) {
        tapClickEnabled = enabled
    }

    func updateTapClickCadence(_ milliseconds: Double) {
        let clampedMs = min(max(milliseconds, 50.0), 1000.0)
        tapClickCadenceSeconds = clampedMs / 1000.0
        awaitingSecondTap = false
        doubleTapDeadline = nil
    }

    func updateKeyboardModeEnabled(_ enabled: Bool) {
        keyboardModeEnabled = enabled
    }

    func updateChordalShiftEnabled(_ enabled: Bool) {
        chordShiftEnabled = enabled
        if !enabled {
            chordShiftState[.left] = ChordShiftState()
            chordShiftState[.right] = ChordShiftState()
            chordShiftLastContactTime[.left] = 0
            chordShiftLastContactTime[.right] = 0
            updateChordShiftKeyState()
        }
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
        let now = Self.now()
        let touches = frame.touches
        let hasTouchData = !touches.isEmpty
        if !hasTouchData {
            chordShiftState[.left] = ChordShiftState()
            chordShiftState[.right] = ChordShiftState()
            chordShiftLastContactTime[.left] = 0
            chordShiftLastContactTime[.right] = 0
            updateChordShiftKeyState()
        }
        let deviceIndex = frame.deviceIndex
        let isLeftDevice = leftDeviceIndex.map { $0 == deviceIndex } ?? false
        let isRightDevice = rightDeviceIndex.map { $0 == deviceIndex } ?? false
        let leftTouches = isLeftDevice ? touches : []
        let rightTouches = isRightDevice ? touches : []
        if chordShiftEnabled {
            let leftContactCount = contactCount(in: leftTouches)
            let rightContactCount = contactCount(in: rightTouches)
            updateChordShift(for: .left, contactCount: leftContactCount, now: now)
            updateChordShift(for: .right, contactCount: rightContactCount, now: now)
            updateChordShiftKeyState()
        } else if chordShiftKeyDown {
            updateChordShiftKeyState()
        }
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
        let now = Self.now()
        let touches = frame.rawTouches
        let hasTouchData = !touches.isEmpty
        if !hasTouchData {
            chordShiftState[.left] = ChordShiftState()
            chordShiftState[.right] = ChordShiftState()
            chordShiftLastContactTime[.left] = 0
            chordShiftLastContactTime[.right] = 0
            updateChordShiftKeyState()
        }
        let deviceIndex = frame.deviceIndex
        let isLeftDevice = leftDeviceIndex.map { $0 == deviceIndex } ?? false
        let isRightDevice = rightDeviceIndex.map { $0 == deviceIndex } ?? false
        let leftTouches = isLeftDevice ? touches : []
        let rightTouches = isRightDevice ? touches : []
        if chordShiftEnabled {
            let leftContactCount = contactCount(in: leftTouches)
            let rightContactCount = contactCount(in: rightTouches)
            updateChordShift(for: .left, contactCount: leftContactCount, now: now)
            updateChordShift(for: .right, contactCount: rightContactCount, now: now)
            updateChordShiftKeyState()
        } else if chordShiftKeyDown {
            updateChordShiftKeyState()
        }
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
        let chordShiftSuppressed = chordShiftEnabled && isChordShiftActive(on: side)
        var contactCount = 0
        for touch in touches {
            if Self.isContactState(touch.state) {
                contactCount += 1
            }
            let touchKey = Self.makeTouchKey(deviceIndex: deviceIndex, id: touch.id)
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
            if chordShiftSuppressed {
                if disqualifiedTouches.value(for: touchKey) == nil {
                    disqualifyTouch(touchKey, reason: .typingDisabled)
                }
                switch touch.state {
                case .breaking, .leaving, .notTouching:
                    disqualifiedTouches.remove(touchKey)
                    touchInitialContactPoint.remove(touchKey)
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
            handleForceGuard(touchKey: touchKey, pressure: touch.pressure, now: now)

            if disqualifiedTouches.value(for: touchKey) != nil {
                switch touch.state {
                case .breaking, .leaving, .notTouching:
                    disqualifiedTouches.remove(touchKey)
                case .starting, .making, .touching, .hovering, .lingering:
                    break
                @unknown default:
                    break
                }
                continue
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
                    continue
                case .key:
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
                       !active.binding.rect.contains(point) {
                        disqualifyTouch(touchKey, reason: .leftContinuousRect)
                        continue
                    }

                    if intentAllowsTyping,
                       active.modifierKey == nil,
                       !active.didHold,
                       now - active.startTime >= holdMinDuration,
                       (!isDragDetectionEnabled || active.maxDistanceSquared <= dragCancelDistanceSquared),
                       initialContactPointIsInsideBinding(touchKey, binding: active.binding) {
                        let dispatchInfo = makeDispatchInfo(
                            kind: .hold,
                            startTime: active.startTime,
                            maxDistanceSquared: active.maxDistanceSquared,
                            now: now
                        )
                        var updated = active
                        if active.isContinuousKey {
                            triggerBinding(active.binding, touchKey: touchKey, dispatchInfo: dispatchInfo)
                            startRepeat(for: touchKey, binding: active.binding)
                            updated.holdRepeatActive = true
                        } else if let holdBinding = active.holdBinding {
                            triggerBinding(holdBinding, touchKey: touchKey, dispatchInfo: dispatchInfo)
                            if isContinuousKey(holdBinding) {
                                startRepeat(for: touchKey, binding: holdBinding)
                                updated.holdRepeatActive = true
                            } else {
                                updated.holdRepeatActive = false
                            }
                        } else {
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
                    if pending.binding.rect.contains(point),
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
                            triggerBinding(pending.binding, touchKey: touchKey, dispatchInfo: dispatchInfo)
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
                            initialPressure: pending.initialPressure,
                            forceEntryTime: pending.forceEntryTime,
                            forceGuardTriggered: pending.forceGuardTriggered,
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
                        triggerBinding(binding, touchKey: touchKey, dispatchInfo: dispatchInfo)
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
                                maxDistanceSquared: 0,
                                initialPressure: touch.pressure,
                                forceEntryTime: nil,
                                forceGuardTriggered: false
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
                                initialPressure: touch.pressure,
                                forceEntryTime: nil,
                                forceGuardTriggered: false,
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
                    if intentAllowsTyping {
                        _ = maybeSendPendingContinuousTap(
                            pending,
                            touchKey: touchKey,
                            at: point,
                            now: now
                        )
                    } else if shouldCommitTypingOnRelease(
                        touchKey: touchKey,
                        binding: pending.binding,
                        point: point,
                        side: side
                    ) {
                        _ = maybeSendPendingContinuousTap(
                            pending,
                            touchKey: touchKey,
                            at: point,
                            now: now
                        )
                    }
                }
                if disqualifiedTouches.remove(touchKey) != nil {
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
                    let guardTriggered = active.forceGuardTriggered
                    if let modifierKey = active.modifierKey, active.modifierEngaged {
                        handleModifierUp(modifierKey, binding: active.binding)
                    } else if active.holdRepeatActive {
                        stopRepeat(for: touchKey)
                    } else if !guardTriggered,
                              !active.didHold,
                              now - active.startTime <= tapMaxDuration,
                              (!isDragDetectionEnabled
                               || releaseDistanceSquared <= dragCancelDistanceSquared) {
                        if intentAllowsTyping || shouldCommitTypingOnRelease(
                            touchKey: touchKey,
                            binding: active.binding,
                            point: point,
                            side: side
                        ) {
                            let dispatchInfo = makeDispatchInfo(
                                kind: .tap,
                                startTime: active.startTime,
                                maxDistanceSquared: active.maxDistanceSquared,
                                now: now
                            )
                            triggerBinding(active.binding, touchKey: touchKey, dispatchInfo: dispatchInfo)
                        }
                    }
                    endMomentaryHoldIfNeeded(active.holdBinding, touchKey: touchKey)
                    if guardTriggered {
                        continue
                    }
                }
                if !hadPending, !hadActive, resolveBinding() == nil {
                    if attemptSnapOnRelease(
                        touchKey: touchKey,
                        point: point,
                        bindings: bindings
                    ) {
                        continue
                    }
                    if shouldAttemptSnap() {
                        disqualifyTouch(touchKey, reason: .offKeyNoSnap)
                        #if DEBUG
                        OSAtomicIncrement64Barrier(&Self.snapOffKeyCount)
                        #endif
                    }
                }
            case .notTouching:
                touchInitialContactPoint.remove(touchKey)
                let removedPending = removePendingTouch(for: touchKey)
                let hadPending = removedPending != nil
                if var pending = removedPending {
                    let distanceSquared = distanceSquared(from: pending.startPoint, to: point)
                    pending.maxDistanceSquared = max(pending.maxDistanceSquared, distanceSquared)
                    if intentAllowsTyping {
                        _ = maybeSendPendingContinuousTap(
                            pending,
                            touchKey: touchKey,
                            at: point,
                            now: now
                        )
                    } else if shouldCommitTypingOnRelease(
                        touchKey: touchKey,
                        binding: pending.binding,
                        point: point,
                        side: side
                    ) {
                        _ = maybeSendPendingContinuousTap(
                            pending,
                            touchKey: touchKey,
                            at: point,
                            now: now
                        )
                    }
                }
                if disqualifiedTouches.remove(touchKey) != nil {
                    continue
                }
                let removedActive = removeActiveTouch(for: touchKey)
                let hadActive = removedActive != nil
                if var active = removedActive {
                    let distanceSquared = distanceSquared(from: active.startPoint, to: point)
                    active.maxDistanceSquared = max(active.maxDistanceSquared, distanceSquared)
                    if let modifierKey = active.modifierKey, active.modifierEngaged {
                        handleModifierUp(modifierKey, binding: active.binding)
                    } else if active.holdRepeatActive {
                        stopRepeat(for: touchKey)
                    }
                    endMomentaryHoldIfNeeded(active.holdBinding, touchKey: touchKey)
                }
                if !hadPending, !hadActive, resolveBinding() == nil {
                    if attemptSnapOnRelease(
                        touchKey: touchKey,
                        point: point,
                        bindings: bindings
                    ) {
                        continue
                    }
                    if shouldAttemptSnap() {
                        disqualifyTouch(touchKey, reason: .offKeyNoSnap)
                        #if DEBUG
                        OSAtomicIncrement64Barrier(&Self.snapOffKeyCount)
                        #endif
                    }
                }
            case .hovering, .lingering:
                break
            @unknown default:
                break
            }
        }
        contactFingerCountsBySide[side] = cachedContactCount(
            for: side,
            actualCount: contactCount,
            now: now
        )
    }

    private func handleForceGuard(
        touchKey: TouchKey,
        pressure: Float,
        now: TimeInterval
    ) {
        guard forceClickCap > 0 else { return }
        if hasActiveModifiers() { return }

        if let active = activeTouch(for: touchKey) {
            if active.modifierKey != nil { return }
            let delta = max(0, pressure - active.initialPressure)
            if delta >= forceClickCap {
                disqualifyTouch(touchKey, reason: .forceCapExceeded)
            }
            return
        }

        if let pending = pendingTouch(for: touchKey) {
            if modifierKey(for: pending.binding) != nil { return }
            let delta = max(0, pressure - pending.initialPressure)
            if delta >= forceClickCap {
                disqualifyTouch(touchKey, reason: .forceCapExceeded)
            }
        }
    }

    private func shouldImmediateTapWithModifiers(binding: KeyBinding) -> Bool {
        hasActiveModifiers() && modifierKey(for: binding) == nil
    }

    private func hasActiveModifiers() -> Bool {
        leftShiftTouchCount > 0
            || controlTouchCount > 0
            || optionTouchCount > 0
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
            snapCentersX.append(Float(binding.rect.midX))
            snapCentersY.append(Float(binding.rect.midY))
            let radius = Float(min(binding.rect.width, binding.rect.height)) * snapRadiusFraction
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
                    layout: layout
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
            case .typingToggle:
                action = .typingToggle
            case .layerMomentary:
                action = .layerMomentary(button.action.layer ?? 1)
            case .layerToggle:
                action = .layerToggle(button.action.layer ?? 1)
            case .none:
                action = .none
            }
            let binding = KeyBinding(
                rect: rect,
                normalizedRect: button.rect,
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
        layout: Layout
    ) -> KeyBinding? {
        guard let action = keyAction(for: position, label: label) else { return nil }
        let holdAction = layout.allowHoldBindings
            ? holdAction(for: position, label: label)
            : nil
        return makeBinding(
            for: action,
            rect: rect,
            normalizedRect: normalizedRect,
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
        if let mapping = layerMappings[label] {
            return mapping.primary
        }
        return KeyActionCatalog.action(for: label)
    }

    private func holdAction(for position: GridKeyPosition?, label: String) -> KeyAction? {
        let layerMappings = customKeyMappingsByLayer[activeLayer] ?? [:]
        if let position, let mapping = layerMappings[position.storageKey] {
            if let hold = mapping.hold { return hold }
        }
        if let mapping = layerMappings[label], let hold = mapping.hold {
            return hold
        }
        return KeyActionCatalog.holdAction(for: label)
    }

    private func makeBinding(
        for action: KeyAction,
        rect: CGRect,
        normalizedRect: NormalizedRect,
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
                label: action.label,
                action: .key(code: CGKeyCode(action.keyCode), flags: flags),
                position: position,
                side: side,
                holdAction: holdAction
            )
        case .typingToggle:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                label: action.label,
                action: .typingToggle,
                position: position,
                side: side,
                holdAction: holdAction
            )
        case .layerMomentary:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                label: action.label,
                action: .layerMomentary(action.layer ?? 1),
                position: position,
                side: side,
                holdAction: holdAction
            )
        case .layerToggle:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
                label: action.label,
                action: .layerToggle(action.layer ?? 1),
                position: position,
                side: side,
                holdAction: holdAction
            )
        case .none:
            return KeyBinding(
                rect: rect,
                normalizedRect: normalizedRect,
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
            guard binding.rect.contains(point) else { continue }
            let dx = min(point.x - binding.rect.minX, binding.rect.maxX - point.x)
            let dy = min(point.y - binding.rect.minY, binding.rect.maxY - point.y)
            let score = min(dx, dy)
            let area = binding.rect.width * binding.rect.height
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

    @inline(__always)
    private func isSameKeyBinding(_ lhs: KeyBinding, _ rhs: KeyBinding) -> Bool {
        guard lhs.side == rhs.side else { return false }
        return lhs.position?.storageKey == rhs.position?.storageKey
    }

    private func nearestSnapIndexExcluding(
        _ excluded: KeyBinding,
        point: CGPoint,
        bindings: BindingIndex
    ) -> (index: Int, distance: Float)? {
        let count = bindings.snapCentersX.count
        guard count > 0 else { return nil }
        let px = Float(point.x)
        let py = Float(point.y)
        var bestIndex = -1
        var bestDistance = Float.greatestFiniteMagnitude
        for index in 0..<count {
            let candidate = bindings.snapBindings[index]
            if isSameKeyBinding(candidate, excluded) {
                continue
            }
            let dx = px - bindings.snapCentersX[index]
            let dy = py - bindings.snapCentersY[index]
            let distance = dx * dx + dy * dy
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        guard bestIndex >= 0 else { return nil }
        return (bestIndex, bestDistance)
    }

    private func dispatchSnappedBinding(
        _ binding: KeyBinding,
        altBinding: KeyBinding?,
        touchKey: TouchKey
    ) {
        guard case let .key(code, flags) = binding.action else { return }
        #if DEBUG
        onDebugBindingDetected(binding)
        #endif
        extendTypingGrace(for: binding.side, now: Self.now())
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
        bindings: BindingIndex
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
            dispatchSnappedBinding(binding, altBinding: altBinding, touchKey: touchKey)
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

    private func contactCount(in touches: [OMSRawTouch]) -> Int {
        var count = 0
        for touch in touches where Self.isChordShiftContactState(touch.state) {
            count += 1
        }
        return count
    }

    private func updateChordShift(for side: TrackpadSide, contactCount: Int, now: TimeInterval) {
        var state = chordShiftState[side]
        if contactCount > 0 {
            chordShiftLastContactTime[side] = now
        }
        if state.active {
            if contactCount == 0 {
                let elapsed = now - chordShiftLastContactTime[side]
                if elapsed >= contactCountHoldDuration {
                    state.active = false
                }
            }
            chordShiftState[side] = state
            return
        }
        if contactCount >= 4 {
            state.active = true
        }
        chordShiftState[side] = state
    }

    private func isChordShiftActive(on side: TrackpadSide) -> Bool {
        chordShiftEnabled && chordShiftState[side].active
    }

    private func updateChordShiftKeyState() {
        let shouldBeDown = chordShiftState[.left].active || chordShiftState[.right].active
        guard shouldBeDown != chordShiftKeyDown else { return }
        chordShiftKeyDown = shouldBeDown
        let shiftBinding = KeyBinding(
            rect: .zero,
            normalizedRect: NormalizedRect(x: 0, y: 0, width: 0, height: 0),
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

        if keyboardOnly {
            twoFingerTapCandidate = nil
            threeFingerTapCandidate = nil
            awaitingSecondTap = false
            doubleTapDeadline = nil
        } else if tapClickEnabled {
            if intentCurrentKeys.count == 2,
               state.touches.count == 3,
               shouldTriggerTapClick(
                state: state.touches,
                now: now,
                moveThresholdSquared: moveThresholdSquared,
                fingerCount: 3
               ) {
                threeFingerTapCandidate = TapCandidate(deadline: now + staggerWindow)
            } else if intentCurrentKeys.count == 0,
                      state.touches.count == 3,
                      shouldTriggerTapClick(
                        state: state.touches,
                        now: now,
                        moveThresholdSquared: moveThresholdSquared,
                        fingerCount: 3
                      ) {
                threeFingerTapDetected = true
                threeFingerTapCandidate = nil
            } else if intentCurrentKeys.count == 0,
                      let candidate = threeFingerTapCandidate,
                      now <= candidate.deadline {
                threeFingerTapDetected = true
                threeFingerTapCandidate = nil
            } else if intentCurrentKeys.count == 1,
                      state.touches.count == 2,
                      shouldTriggerTapClick(
                        state: state.touches,
                        now: now,
                        moveThresholdSquared: moveThresholdSquared,
                        fingerCount: 2
                      ) {
                twoFingerTapCandidate = TapCandidate(deadline: now + staggerWindow)
            } else if intentCurrentKeys.count == 0,
                      state.touches.count == 2,
                      shouldTriggerTapClick(
                        state: state.touches,
                        now: now,
                        moveThresholdSquared: moveThresholdSquared,
                        fingerCount: 2
                      ) {
                twoFingerTapDetected = true
                twoFingerTapCandidate = nil
            } else if intentCurrentKeys.count == 0,
                      let candidate = twoFingerTapCandidate,
                      now <= candidate.deadline {
                twoFingerTapDetected = true
                twoFingerTapCandidate = nil
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
        let dictationHoldSide = voiceDictationHoldSide(leftTouches: leftTouches, rightTouches: rightTouches)
        let dictationGestureEngaged = updateVoiceDictationGesture(
            holdSide: dictationHoldSide,
            now: now
        )

        let centroid: CGPoint? = contactCount > 0
            ? CGPoint(x: sumX / CGFloat(contactCount), y: sumY / CGFloat(contactCount))
            : nil
        let gestureCentroid: CGPoint? = gestureContactCount > 0
            ? CGPoint(x: gestureSumX / CGFloat(gestureContactCount), y: gestureSumY / CGFloat(gestureContactCount))
            : nil
        updateFiveFingerSwipe(
            contactCount: gestureContactCount,
            centroid: gestureCentroid,
            now: now,
            unitsPerMm: unitsPerMm
        )
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
        if dictationGestureEngaged {
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
                dispatchService.postRightClick()
            } else if wasTwoFingerTapDetected {
                if awaitingSecondTap, let deadline = doubleTapDeadline, now <= deadline {
                    dispatchService.postLeftClick(clickCount: 2)
                    awaitingSecondTap = false
                    doubleTapDeadline = nil
                } else {
                    dispatchService.postLeftClick()
                    awaitingSecondTap = true
                    doubleTapDeadline = now + tapClickCadenceSeconds
                }
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

        if dictationGestureEngaged {
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
                suppressKeyProcessing(for: intentCurrentKeys)
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
                suppressKeyProcessing(for: intentCurrentKeys)
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
                suppressKeyProcessing(for: intentCurrentKeys)
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
        let currentNow = now ?? Self.now()
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

    private func updateFiveFingerSwipe(
        contactCount: Int,
        centroid: CGPoint?,
        now: TimeInterval,
        unitsPerMm: CGFloat
    ) {
        guard contactCount >= 5, let centroid else {
            if fiveFingerSwipeState.active || fiveFingerSwipeState.triggered {
                fiveFingerSwipeState = FiveFingerSwipeState()
            }
            return
        }
        var state = fiveFingerSwipeState
        if !state.active {
            state.active = true
            state.triggered = false
            state.startTime = now
            state.startX = centroid.x
            state.startY = centroid.y
            fiveFingerSwipeState = state
            return
        }
        if state.triggered {
            return
        }
        let dx = centroid.x - state.startX
        let dy = centroid.y - state.startY
        let threshold = fiveFingerSwipeThresholdMm * unitsPerMm
        if abs(dx) >= threshold, abs(dx) >= abs(dy) {
            state.triggered = true
            fiveFingerSwipeState = state
            toggleTypingMode()
        } else {
            fiveFingerSwipeState = state
        }
    }

    private func voiceDictationHoldSide(
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

    private func updateVoiceDictationGesture(
        holdSide: TrackpadSide?,
        now: TimeInterval
    ) -> Bool {
        var state = voiceDictationGestureState
        if let holdSide {
            if !state.holdCandidateActive || state.side != holdSide {
                state.holdCandidateActive = true
                state.holdDidToggle = false
                state.holdStart = now
                state.side = holdSide
            } else if !state.holdDidToggle, now - state.holdStart >= voiceDictationHoldSeconds {
                state.holdDidToggle = true
                if state.isDictating {
                    state.isDictating = false
                    VoiceDictationManager.shared.endSession()
                } else {
                    state.isDictating = true
                    VoiceDictationManager.shared.beginSession()
                }
                playHapticIfNeeded(on: holdSide)
            }
        } else {
            state.holdCandidateActive = false
            state.holdDidToggle = false
            state.holdStart = 0
            state.side = nil
        }
        voiceDictationGestureState = state
        let isActive = state.isDictating || state.holdCandidateActive
        if voiceGestureActive != isActive {
            voiceGestureActive = isActive
            onVoiceGestureChanged(isActive)
        }
        return isActive
    }

    private func stopVoiceDictationGesture() {
        if voiceDictationGestureState.isDictating {
            VoiceDictationManager.shared.endSession()
        }
        voiceDictationGestureState = VoiceDictationGestureState()
        if voiceGestureActive {
            voiceGestureActive = false
            onVoiceGestureChanged(false)
        }
    }

    private func shouldCommitTypingOnRelease(
        touchKey: TouchKey,
        binding: KeyBinding,
        point: CGPoint,
        side _: TrackpadSide
    ) -> Bool {
        var state = intentState
        guard case .keyCandidate = state.mode else {
            return false
        }
        let maxDistanceSquared = state.touches.value(for: touchKey)?.maxDistanceSquared ?? 0
        guard maxDistanceSquared <= intentMoveThresholdSquared else { return false }
        guard binding.rect.contains(point),
              initialContactPointIsInsideBinding(touchKey, binding: binding) else {
            return false
        }
        state.mode = .typingCommitted(untilAllUp: !allowMouseTakeoverDuringTyping)
        intentState = state
        return true
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

    private func mmUnitsPerMillimeter() -> CGFloat {
        unitsPerMillimeter
    }

    private func handleTypingToggleTouch(
        touchKey: TouchKey,
        state: OpenMTState,
        point: CGPoint
    ) {
        switch state {
        case .starting, .making, .touching:
            if toggleTouchStarts.value(for: touchKey) == nil {
                toggleTouchStarts.set(touchKey, Self.now())
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
        if code == CGKeyCode(kVK_Command) {
            return .command
        }
        return nil
    }

    private func isContinuousKey(_ binding: KeyBinding) -> Bool {
        guard case let .key(code, _) = binding.action else { return false }
        return code == CGKeyCode(kVK_Delete)
            || code == CGKeyCode(kVK_LeftArrow)
            || code == CGKeyCode(kVK_RightArrow)
            || code == CGKeyCode(kVK_UpArrow)
            || code == CGKeyCode(kVK_DownArrow)
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
            position: binding.position,
            side: binding.side
        )
    }

    @discardableResult
    private func maybeSendPendingContinuousTap(
        _ pending: PendingTouch,
        touchKey: TouchKey,
        at point: CGPoint,
        now: TimeInterval
    ) -> Bool {
        let releaseDistanceSquared = distanceSquared(from: pending.startPoint, to: point)
        guard isContinuousKey(pending.binding),
              now - pending.startTime <= tapMaxDuration,
              pending.binding.rect.contains(point),
              (!isDragDetectionEnabled
               || releaseDistanceSquared <= dragCancelDistance * dragCancelDistance),
              !pending.forceGuardTriggered else {
            return false
        }
        let dispatchInfo = makeDispatchInfo(
            kind: .tap,
            startTime: pending.startTime,
            maxDistanceSquared: pending.maxDistanceSquared,
            now: now
        )
        sendKey(binding: pending.binding, touchKey: touchKey, dispatchInfo: dispatchInfo)
        return true
    }

    private func triggerBinding(
        _ binding: KeyBinding,
        touchKey: TouchKey?,
        dispatchInfo: DispatchInfo? = nil
    ) {
        switch binding.action {
        case let .layerMomentary(layer):
            guard let touchKey else { return }
            momentaryLayerTouches.set(touchKey, layer)
            updateActiveLayer()
        case let .layerToggle(layer):
            toggleLayer(to: layer)
        case .typingToggle:
            toggleTypingMode()
        case .none:
            break
        case let .key(code, flags):
#if DEBUG
            onDebugBindingDetected(binding)
#endif
            extendTypingGrace(for: binding.side, now: Self.now())
            playHapticIfNeeded(on: binding.side, touchKey: touchKey)
            sendKey(code: code, flags: flags, side: binding.side)
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
        if optionTouchCount > 0 {
            modifierFlags.insert(.maskAlternate)
        }
        if commandTouchCount > 0 {
            modifierFlags.insert(.maskCommand)
        }
        return modifierFlags
    }

    private func sendKey(binding: KeyBinding, touchKey: TouchKey?, dispatchInfo: DispatchInfo? = nil) {
        guard case let .key(code, flags) = binding.action else { return }
        #if DEBUG
        onDebugBindingDetected(binding)
#endif
        extendTypingGrace(for: binding.side, now: Self.now())
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

    private func initialContactPointIsInsideBinding(_ touchKey: TouchKey, binding: KeyBinding) -> Bool {
        guard let startPoint = touchInitialContactPoint.value(for: touchKey) else {
            return true
        }
        return binding.rect.contains(startPoint)
    }

    private func startRepeat(for touchKey: TouchKey, binding: KeyBinding) {
        stopRepeat(for: touchKey)
        guard case let .key(code, flags) = binding.action else { return }
        let repeatFlags = flags.union(currentModifierFlags())
        let initialDelay = repeatInitialDelay
        let interval = repeatInterval(for: binding.action)
        let token = RepeatToken()
        let nextFire = Self.nowUptimeNanoseconds() &+ initialDelay
        repeatEntries[touchKey] = RepeatEntry(
            code: code,
            flags: repeatFlags,
            token: token,
            interval: interval,
            nextFire: nextFire
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
        var toRemove: [TouchKey] = []
        for (key, var entry) in repeatEntries {
            if !entry.token.isActive {
                toRemove.append(key)
                continue
            }
            if entry.nextFire <= now {
                dispatchService.postKeyStroke(code: entry.code, flags: entry.flags, token: entry.token)
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

    private func stopRepeat(for touchKey: TouchKey) {
        if let entry = repeatEntries.removeValue(forKey: touchKey) {
            entry.token.deactivate()
        }
        if repeatEntries.isEmpty {
            repeatLoopTask?.cancel()
            repeatLoopTask = nil
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
            if optionTouchCount == 0 {
                playHapticIfNeeded(on: binding.side)
                postKey(binding: binding, keyDown: true)
            }
            optionTouchCount += 1
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
            optionTouchCount = max(0, optionTouchCount - 1)
            if optionTouchCount == 0 {
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
        chordShiftState[.left] = ChordShiftState()
        chordShiftState[.right] = ChordShiftState()
        if chordShiftKeyDown {
            let shiftBinding = KeyBinding(
                rect: .zero,
                normalizedRect: NormalizedRect(x: 0, y: 0, width: 0, height: 0),
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
                label: "Ctrl",
                action: .key(code: CGKeyCode(kVK_Control), flags: []),
                position: nil,
                side: .left,
                holdAction: nil
            )
            postKey(binding: controlBinding, keyDown: false)
            controlTouchCount = 0
        }
        if optionTouchCount > 0 {
            let optionBinding = KeyBinding(
                rect: .zero,
                normalizedRect: NormalizedRect(x: 0, y: 0, width: 0, height: 0),
                label: "Option",
                action: .key(code: CGKeyCode(kVK_Option), flags: []),
                position: nil,
                side: .left,
                holdAction: nil
            )
            postKey(binding: optionBinding, keyDown: false)
            optionTouchCount = 0
        }
        if commandTouchCount > 0 {
            let commandBinding = KeyBinding(
                rect: .zero,
                normalizedRect: NormalizedRect(x: 0, y: 0, width: 0, height: 0),
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
        if reason == .dragCancelled || reason == .pendingDragCancelled || reason == .forceCapExceeded {
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
        let clamped = max(0, min(layer, 1))
        if persistentLayer == clamped {
            persistentLayer = 0
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
        let delay = max(0, deadline - Self.now())
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
              Self.now() >= deadline else {
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

    private static func now() -> TimeInterval {
        CACurrentMediaTime()
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
