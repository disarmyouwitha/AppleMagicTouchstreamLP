//
//  ContentViewModel.swift
//  GlassToKey
//
//  Created by Takuto Nakamura on 2024/03/02.
//

import Carbon
import CoreGraphics
import Darwin
import Foundation
import OpenMultitouchSupport
import OpenMultitouchSupportXCF
import QuartzCore
import SwiftUI
import os

enum TrackpadSide: String, Codable, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }
}

typealias LayeredKeyMappings = [Int: [String: KeyMapping]]

struct SidePair<Value> {
    var left: Value
    var right: Value

    init(left: Value, right: Value) {
        self.left = left
        self.right = right
    }

    init(repeating value: Value) {
        self.left = value
        self.right = value
    }

    subscript(_ side: TrackpadSide) -> Value {
        get { side == .left ? left : right }
        set {
            if side == .left {
                left = newValue
            } else {
                right = newValue
            }
        }
    }
}

extension SidePair: Sendable where Value: Sendable {}
extension SidePair: Equatable where Value: Equatable {}

struct GridKeyPosition: Codable, Hashable {
    let side: TrackpadSide
    let row: Int
    let column: Int

    init(side: TrackpadSide, row: Int, column: Int) {
        self.side = side
        self.row = row
        self.column = column
    }

    private static let separator = ":"

    var storageKey: String {
        "\(side.rawValue)\(Self.separator)\(row)\(Self.separator)\(column)"
    }

    static func from(storageKey: String) -> GridKeyPosition? {
        guard let separatorChar = separator.first else { return nil }
        let components = storageKey.split(separator: separatorChar)
        guard components.count == 3,
              let side = TrackpadSide(rawValue: String(components[0])),
              let row = Int(components[1]),
              let column = Int(components[2]) else {
            return nil
        }
        return GridKeyPosition(side: side, row: row, column: column)
    }
}

@MainActor
final class ContentViewModel: ObservableObject {
    enum KeyBindingAction: Sendable {
        case key(code: CGKeyCode, flags: CGEventFlags)
        case typingToggle
        case layerMomentary(Int)
        case layerToggle(Int)
        case none
    }

    struct KeyBinding: Sendable {
        let rect: CGRect
        let normalizedRect: NormalizedRect
        let label: String
        let action: KeyBindingAction
        let position: GridKeyPosition?
        let side: TrackpadSide
        let holdAction: KeyAction?
    }

    struct Layout {
        let keyRects: [[CGRect]]
        let normalizedKeyRects: [[NormalizedRect]]
        let allowHoldBindings: Bool

        init(
            keyRects: [[CGRect]],
            trackpadSize: CGSize,
            allowHoldBindings: Bool = true
        ) {
            self.keyRects = keyRects
            self.allowHoldBindings = allowHoldBindings
            self.normalizedKeyRects = Layout.normalize(keyRects, trackpadSize: trackpadSize)
        }

        init(keyRects: [[CGRect]]) {
            self.init(keyRects: keyRects, trackpadSize: .zero, allowHoldBindings: true)
        }

        private static func normalize(
            _ keyRects: [[CGRect]],
            trackpadSize: CGSize
        ) -> [[NormalizedRect]] {
            guard !keyRects.isEmpty else { return [] }
            return keyRects.map { row in
                row.map { rect in
                    let x = Layout.normalize(axis: rect.minX, size: trackpadSize.width)
                    let y = Layout.normalize(axis: rect.minY, size: trackpadSize.height)
                    let width = Layout.normalizeLength(length: rect.width, size: trackpadSize.width)
                    let height = Layout.normalizeLength(length: rect.height, size: trackpadSize.height)
                    return NormalizedRect(
                        x: x,
                        y: y,
                        width: width,
                        height: height
                    ).clamped(minWidth: 0, minHeight: 0)
                }
            }
        }

        private static func normalize(axis coordinate: CGFloat, size: CGFloat) -> CGFloat {
            guard size > 0 else { return 0 }
            return min(max(coordinate / size, 0), 1)
        }

        private static func normalizeLength(length: CGFloat, size: CGFloat) -> CGFloat {
            guard size > 0 else { return 0 }
            return min(max(length / size, 0), 1)
        }

        func normalizedRect(for position: GridKeyPosition) -> NormalizedRect? {
            guard normalizedKeyRects.indices.contains(position.row),
                  normalizedKeyRects[position.row].indices.contains(position.column) else {
                return nil
            }
            return normalizedKeyRects[position.row][position.column]
        }
    }

    struct TouchSnapshot: Sendable {
        var left: [OMSTouchData] = []
        var right: [OMSTouchData] = []
        var revision: UInt64 = 0
        var hasTransitionState: Bool = false
    }

    enum IntentDisplay: String, Sendable {
        case idle
        case keyCandidate
        case typing
        case mouse
        case gesture
    }

    private struct DeviceSelection: Sendable {
        var leftIndex: Int?
        var rightIndex: Int?
    }

    nonisolated private let touchSnapshotLock = OSAllocatedUnfairLock<TouchSnapshot>(
        uncheckedState: TouchSnapshot()
    )
    private struct PendingTouchState {
        var left: [OMSTouchData] = []
        var right: [OMSTouchData] = []
        var leftDirty = false
        var rightDirty = false
        var lastLeftUpdateTime: TimeInterval = 0
        var lastRightUpdateTime: TimeInterval = 0
    }
    private struct PendingTouchSnapshot {
        let left: [OMSTouchData]
        let right: [OMSTouchData]
    }
    nonisolated private let pendingTouchLock = OSAllocatedUnfairLock<PendingTouchState>(
        uncheckedState: PendingTouchState()
    )
    private let touchCoalesceInterval: TimeInterval = 0.02
    private let snapshotQueue = DispatchQueue(
        label: "com.kyome.GlassToKey.TouchSnapshots",
        qos: .utility
    )
#if DEBUG
    private let pipelineSignposter = OSSignposter(
        subsystem: "com.kyome.GlassToKey",
        category: "InputPipeline"
    )
#endif
    nonisolated private let deviceSelectionLock = OSAllocatedUnfairLock<DeviceSelection>(
        uncheckedState: DeviceSelection()
    )
    nonisolated private let snapshotRecordingLock = OSAllocatedUnfairLock<Bool>(
        uncheckedState: true
    )
    final class ContinuationHolder: @unchecked Sendable {
        var continuation: AsyncStream<UInt64>.Continuation?
    }
    nonisolated let touchRevisionUpdates: AsyncStream<UInt64>
    nonisolated private let touchRevisionContinuationHolder: ContinuationHolder
    @Published var isListening: Bool = false
    @Published var isTypingEnabled: Bool = true
    @Published var keyboardModeEnabled: Bool = false
    @Published private(set) var activeLayer: Int = 0
    @Published private(set) var contactFingerCountsBySide = SidePair(left: 0, right: 0)
    @Published private(set) var intentDisplayBySide = SidePair(left: IntentDisplay.idle, right: .idle)
    @Published private(set) var voiceGestureActive = false
    @Published private(set) var voiceDebugStatus: String?
    private let isDragDetectionEnabled = true
    @Published var availableDevices = [OMSDeviceInfo]()
    @Published var leftDevice: OMSDeviceInfo?
    @Published var rightDevice: OMSDeviceInfo?
    @Published private(set) var hasDisconnectedTrackpads = false
    struct DebugHit: Equatable {
        let rect: CGRect
        let label: String
        let side: TrackpadSide
        let timestamp: TimeInterval
    }

    @Published private(set) var debugLastHitLeft: DebugHit?
    @Published private(set) var debugLastHitRight: DebugHit?

    private var requestedLeftDeviceID: String?
    private var requestedRightDeviceID: String?
    private var requestedLeftDeviceName: String?
    private var requestedRightDeviceName: String?
    private var requestedLeftIsBuiltIn: Bool?
    private var requestedRightIsBuiltIn: Bool?
    private var autoResyncTask: Task<Void, Never>?
    private var autoResyncEnabled = false
    private var uiStatusVisualsEnabled = true
    private static let connectedResyncIntervalSeconds: TimeInterval = 10.0
    private static let disconnectedResyncIntervalSeconds: TimeInterval = 1.0
    private static let connectedResyncIntervalNanoseconds = UInt64(connectedResyncIntervalSeconds * 1_000_000_000)
    private static let disconnectedResyncIntervalNanoseconds = UInt64(disconnectedResyncIntervalSeconds * 1_000_000_000)

    private let manager = OMSManager.shared
    private var task: Task<Void, Never>?
    private let processor: TouchProcessor

    init() {
        let holder = ContinuationHolder()
        touchRevisionContinuationHolder = holder
        touchRevisionUpdates = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            holder.continuation = continuation
        }
        weak var weakSelf: ContentViewModel?
        let debugBindingHandler: @Sendable (KeyBinding) -> Void = { binding in
            Task { @MainActor in
                weakSelf?.recordDebugHit(binding)
            }
        }
        let contactCountHandler: @Sendable (SidePair<Int>) -> Void = { counts in
            Task { @MainActor in
                weakSelf?.publishContactCountsIfNeeded(counts)
            }
        }
        let intentStateHandler: @Sendable (SidePair<IntentDisplay>) -> Void = { states in
            Task { @MainActor in
                weakSelf?.publishIntentDisplayIfNeeded(states)
            }
        }
        let voiceGestureHandler: @Sendable (Bool) -> Void = { isActive in
            Task { @MainActor in
                weakSelf?.publishVoiceGestureIfNeeded(isActive)
            }
        }
        let voiceStatusHandler: @Sendable (String?) -> Void = { status in
            Task { @MainActor in
                weakSelf?.publishVoiceDebugStatus(status)
            }
        }
        VoiceDictationManager.shared.setStatusHandler(voiceStatusHandler)
        processor = TouchProcessor(
            keyDispatcher: KeyEventDispatcher.shared,
            onTypingEnabledChanged: { isEnabled in
                Task { @MainActor in
                    weakSelf?.isTypingEnabled = isEnabled
                }
            },
            onActiveLayerChanged: { layer in
                Task { @MainActor in
                    weakSelf?.activeLayer = layer
                }
            },
            onDebugBindingDetected: debugBindingHandler,
            onContactCountChanged: contactCountHandler,
            onIntentStateChanged: intentStateHandler,
            onVoiceGestureChanged: voiceGestureHandler
        )
        weakSelf = self
        loadDevices()
    }

    var leftTouches: [OMSTouchData] {
        touchSnapshotLock.withLockUnchecked { $0.left }
    }

    var rightTouches: [OMSTouchData] {
        touchSnapshotLock.withLockUnchecked { $0.right }
    }

    private func recordDebugHit(_ binding: KeyBinding) {
        let hit = DebugHit(
            rect: binding.rect,
            label: binding.label,
            side: binding.side,
            timestamp: CACurrentMediaTime()
        )
        switch binding.side {
        case .left:
            debugLastHitLeft = hit
        case .right:
            debugLastHitRight = hit
        }
    }

    func onAppear() {
        let snapshotLock = touchSnapshotLock
        let selectionLock = deviceSelectionLock
        let recordingLock = snapshotRecordingLock
        let snapshotQueue = snapshotQueue
        task = Task.detached(priority: .userInitiated) { [manager, processor, snapshotLock, selectionLock, recordingLock, snapshotQueue, self] in
            for await rawFrame in manager.rawTouchStream {
#if DEBUG
                let signpostState = pipelineSignposter.beginInterval("InputFrame")
                defer { pipelineSignposter.endInterval("InputFrame", signpostState) }
#endif
                let selection = selectionLock.withLockUnchecked { $0 }
                let deviceIndex = rawFrame.deviceIndex
                let isLeft = deviceIndex == selection.leftIndex
                let isRight = deviceIndex == selection.rightIndex
                let hasTouchData = !rawFrame.touches.isEmpty
                let shouldRecord = recordingLock.withLockUnchecked(\.self)
                var leftTouches: [OMSTouchData] = []
                var rightTouches: [OMSTouchData] = []
                if shouldRecord, hasTouchData, (isLeft || isRight) {
                    let touchData = OMSManager.buildTouchData(from: rawFrame)
                    if isLeft {
                        leftTouches = touchData
                    } else if isRight {
                        rightTouches = touchData
                    }
                }
                let now = CACurrentMediaTime()
                if shouldRecord {
                    let leftSnapshot = leftTouches
                    let rightSnapshot = rightTouches
                    snapshotQueue.async { [snapshotLock, self] in
                        let snapshotCandidate = self.updatePendingTouches(
                            hasTouchData: hasTouchData,
                            left: leftSnapshot,
                            right: rightSnapshot,
                            at: now
                        )
                    var updatedRevision: UInt64?
                    if let candidate = snapshotCandidate {
                        snapshotLock.withLockUnchecked { snapshot in
                            snapshot.left = candidate.left
                            snapshot.right = candidate.right
                            snapshot.hasTransitionState = Self.hasTransitionState(
                                left: candidate.left,
                                right: candidate.right
                            )
                            snapshot.revision &+= 1
                            updatedRevision = snapshot.revision
                        }
#if DEBUG
                        self.pipelineSignposter.emitEvent("SnapshotUpdate")
#endif
                    }
                    if let revision = updatedRevision {
                        self.touchRevisionContinuationHolder.continuation?.yield(revision)
                    }
                    }
                }
                await processor.processRawFrame(rawFrame)
                rawFrame.release()
            }
        }
    }

    func onDisappear() {
        task?.cancel()
        stop()
    }

    func start() {
        if manager.startListening() {
            isListening = true
            Task { [processor] in
                await processor.setListening(true)
            }
        }
    }

    func stop() {
        if manager.stopListening() {
            isListening = false
            Task { [processor] in
                await processor.setListening(false)
                await processor.resetState(stopVoiceDictation: true)
            }
        }
    }

    func refreshDevicesAndListeners() {
        let shouldRestart = isListening
        if shouldRestart {
            stop()
        }
        loadDevices(preserveSelection: true)
        if shouldRestart {
            start()
        }
    }
    
    func loadDevices(preserveSelection: Bool = false) {
        let previousLeftDeviceID = preserveSelection ? requestedLeftDeviceID : nil
        let previousRightDeviceID = preserveSelection ? requestedRightDeviceID : nil
        let previousLeftDeviceName = preserveSelection ? requestedLeftDeviceName : nil
        let previousRightDeviceName = preserveSelection ? requestedRightDeviceName : nil
        let previousLeftIsBuiltIn = preserveSelection ? requestedLeftIsBuiltIn : nil
        let previousRightIsBuiltIn = preserveSelection ? requestedRightIsBuiltIn : nil
        availableDevices = manager.availableDevices

        func matchByID(_ id: String?) -> OMSDeviceInfo? {
            guard let id else { return nil }
            return availableDevices.first { $0.deviceID == id }
        }

        func matchByName(
            _ name: String?,
            isBuiltIn: Bool?,
            excluding excludedIDs: Set<String>
        ) -> OMSDeviceInfo? {
            guard let name, !name.isEmpty else { return nil }
            let candidates = availableDevices.filter { candidate in
                guard !excludedIDs.contains(candidate.deviceID) else { return false }
                guard candidate.deviceName == name else { return false }
                if let isBuiltIn {
                    return candidate.isBuiltIn == isBuiltIn
                }
                return true
            }
            return candidates.count == 1 ? candidates[0] : nil
        }

        func matchSingleRemaining(excluding excludedIDs: Set<String>) -> OMSDeviceInfo? {
            let candidates = availableDevices.filter { !excludedIDs.contains($0.deviceID) }
            return candidates.count == 1 ? candidates[0] : nil
        }

        var usedIDs = Set<String>()
        let leftRequested = preserveSelection && previousLeftDeviceID != nil
        let rightRequested = preserveSelection && previousRightDeviceID != nil

        if leftRequested {
            leftDevice = matchByID(previousLeftDeviceID)
                ?? matchByName(previousLeftDeviceName, isBuiltIn: previousLeftIsBuiltIn, excluding: usedIDs)
        } else if !preserveSelection {
            leftDevice = availableDevices.first
        } else {
            leftDevice = nil
        }
        if let leftDevice {
            usedIDs.insert(leftDevice.deviceID)
        }

        let shouldFallbackRight = !preserveSelection || (preserveSelection && previousRightDeviceID != nil)
        if rightRequested {
            rightDevice = matchByID(previousRightDeviceID)
                ?? matchByName(previousRightDeviceName, isBuiltIn: previousRightIsBuiltIn, excluding: usedIDs)
        } else if shouldFallbackRight {
            rightDevice = availableDevices.first(where: { candidate in
                guard let leftID = leftDevice?.deviceID else { return true }
                return candidate.deviceID != leftID
            })
        } else {
            rightDevice = nil
        }
        if let rightDevice {
            usedIDs.insert(rightDevice.deviceID)
        }

        if leftDevice == nil, leftRequested {
            leftDevice = matchSingleRemaining(excluding: usedIDs)
            if let leftDevice {
                usedIDs.insert(leftDevice.deviceID)
            }
        }
        if rightDevice == nil, rightRequested {
            rightDevice = matchSingleRemaining(excluding: usedIDs)
            if let rightDevice {
                usedIDs.insert(rightDevice.deviceID)
            }
        }

        if !preserveSelection {
            requestedLeftDeviceID = leftDevice?.deviceID
            requestedRightDeviceID = rightDevice?.deviceID
            requestedLeftDeviceName = leftDevice?.deviceName
            requestedRightDeviceName = rightDevice?.deviceName
            requestedLeftIsBuiltIn = leftDevice?.isBuiltIn
            requestedRightIsBuiltIn = rightDevice?.isBuiltIn
        } else {
            if let leftDevice {
                requestedLeftDeviceID = leftDevice.deviceID
                requestedLeftDeviceName = leftDevice.deviceName
                requestedLeftIsBuiltIn = leftDevice.isBuiltIn
            }
            if let rightDevice {
                requestedRightDeviceID = rightDevice.deviceID
                requestedRightDeviceName = rightDevice.deviceName
                requestedRightIsBuiltIn = rightDevice.isBuiltIn
            }
        }

        updateDisconnectedTrackpadState()
        updateActiveDevices()
    }
    
    func selectLeftDevice(_ device: OMSDeviceInfo?) {
        requestedLeftDeviceID = device?.deviceID
        requestedLeftDeviceName = device?.deviceName
        requestedLeftIsBuiltIn = device?.isBuiltIn
        leftDevice = device
        updateDisconnectedTrackpadState()
        updateActiveDevices()
    }

    func selectRightDevice(_ device: OMSDeviceInfo?) {
        requestedRightDeviceID = device?.deviceID
        requestedRightDeviceName = device?.deviceName
        requestedRightIsBuiltIn = device?.isBuiltIn
        rightDevice = device
        updateDisconnectedTrackpadState()
        updateActiveDevices()
    }

    private func updateDisconnectedTrackpadState() {
        let availableIDs = Set(availableDevices.map(\.deviceID))
        var hasMissing = false
        if let leftID = requestedLeftDeviceID,
           !leftID.isEmpty,
           !availableIDs.contains(leftID) {
            hasMissing = true
        }
        if let rightID = requestedRightDeviceID,
           !rightID.isEmpty,
           !availableIDs.contains(rightID) {
            hasMissing = true
        }
        if hasDisconnectedTrackpads != hasMissing {
            hasDisconnectedTrackpads = hasMissing
        }
    }

    func setAutoResyncEnabled(_ enabled: Bool) {
        guard autoResyncEnabled != enabled else { return }
        autoResyncEnabled = enabled
        autoResyncTask?.cancel()
        autoResyncTask = nil
        if enabled {
            loadDevices(preserveSelection: true)
            autoResyncTask = Task { [weak self] in
                guard let self = self else { return }
                await self.autoResyncLoop()
            }
        }
    }

    private func autoResyncLoop() async {
        while autoResyncEnabled {
            let interval = hasDisconnectedTrackpads
                ? Self.disconnectedResyncIntervalNanoseconds
                : Self.connectedResyncIntervalNanoseconds
            do {
                try await Task.sleep(nanoseconds: interval)
            } catch {
                break
            }
            guard autoResyncEnabled else { break }
            loadDevices(preserveSelection: true)
        }
    }

    func configureLayouts(
        leftLayout: Layout,
        rightLayout: Layout,
        leftLabels: [[String]],
        rightLabels: [[String]],
        trackpadSize: CGSize,
        trackpadWidthMm: CGFloat
    ) {
        Task { [processor] in
            await processor.updateLayouts(
                leftLayout: leftLayout,
                rightLayout: rightLayout,
                leftLabels: leftLabels,
                rightLabels: rightLabels,
                trackpadSize: trackpadSize,
                trackpadWidthMm: trackpadWidthMm
            )
        }
    }

    func updateCustomButtons(_ buttons: [CustomButton]) {
        Task { [processor] in
            await processor.updateCustomButtons(buttons)
        }
    }

    func updateKeyMappings(_ actions: LayeredKeyMappings) {
        Task { [processor] in
            await processor.updateKeyMappings(actions)
        }
    }

    func snapshotTouchData() -> TouchSnapshot {
        touchSnapshotLock.withLockUnchecked { $0 }
    }

    func snapshotTouchDataIfUpdated(
        since revision: UInt64
    ) -> TouchSnapshot? {
        touchSnapshotLock.withLockUnchecked { snapshot in
            guard snapshot.revision != revision else { return nil }
            return snapshot
        }
    }

    nonisolated private static func hasTransitionState(
        left: [OMSTouchData],
        right: [OMSTouchData]
    ) -> Bool {
        for touch in left {
            switch touch.state {
            case .starting, .breaking, .leaving:
                return true
            default:
                break
            }
        }
        for touch in right {
            switch touch.state {
            case .starting, .breaking, .leaving:
                return true
            default:
                break
            }
        }
        return false
    }

    nonisolated private func updatePendingTouches(
        hasTouchData: Bool,
        left: [OMSTouchData],
        right: [OMSTouchData],
        at now: TimeInterval
    ) -> PendingTouchSnapshot? {
        pendingTouchLock.withLockUnchecked { state in
            if !hasTouchData {
                let hadPendingTouches = !state.left.isEmpty || !state.right.isEmpty
                if hadPendingTouches {
                    state.left.removeAll()
                    state.right.removeAll()
                    state.leftDirty = true
                    state.rightDirty = true
                    state.lastLeftUpdateTime = now
                    state.lastRightUpdateTime = now
                }
                if shouldEmitSnapshot(state: &state, at: now) {
                    return PendingTouchSnapshot(left: state.left, right: state.right)
                }
                return nil
            }

            var hasUpdates = false
            if !left.isEmpty {
                state.left = left
                state.leftDirty = true
                state.lastLeftUpdateTime = now
                hasUpdates = true
            }
            if !right.isEmpty {
                state.right = right
                state.rightDirty = true
                state.lastRightUpdateTime = now
                hasUpdates = true
            }

            if hasUpdates && shouldEmitSnapshot(state: &state, at: now) {
                return PendingTouchSnapshot(left: state.left, right: state.right)
            }
            return nil
        }
    }

    nonisolated private func shouldEmitSnapshot(
        state: inout PendingTouchState,
        at now: TimeInterval
    ) -> Bool {
        let leftStale = now - state.lastLeftUpdateTime >= touchCoalesceInterval
        let rightStale = now - state.lastRightUpdateTime >= touchCoalesceInterval
        if state.leftDirty && state.rightDirty {
            state.leftDirty = false
            state.rightDirty = false
            return true
        }
        if state.leftDirty && rightStale {
            state.leftDirty = false
            state.rightDirty = false
            return true
        }
        if state.rightDirty && leftStale {
            state.rightDirty = false
            state.leftDirty = false
            return true
        }
        return false
    }

    private func updateActiveDevices() {
        let devices = [leftDevice, rightDevice].compactMap { $0 }
        guard !devices.isEmpty else { return }
        if manager.setActiveDevices(devices) {
            Task { [processor] in
                await processor.resetState(stopVoiceDictation: false)
            }
        }
        let leftIndex = leftDevice.flatMap { manager.deviceIndex(for: $0.deviceID) }
        let rightIndex = rightDevice.flatMap { manager.deviceIndex(for: $0.deviceID) }
        deviceSelectionLock.withLockUnchecked { selection in
            selection.leftIndex = leftIndex
            selection.rightIndex = rightIndex
        }
        let leftDeviceID = leftDevice?.deviceID
        let rightDeviceID = rightDevice?.deviceID
        Task { [processor] in
            await processor.updateActiveDevices(
                leftIndex: leftIndex,
                rightIndex: rightIndex,
                leftDeviceID: leftDeviceID,
                rightDeviceID: rightDeviceID
            )
        }
    }
    func setPersistentLayer(_ layer: Int) {
        Task { [processor] in
            await processor.setPersistentLayer(layer)
        }
    }

    func updateHoldThreshold(_ seconds: TimeInterval) {
        Task { [processor] in
            await processor.updateHoldThreshold(seconds)
        }
    }

    func updateDragCancelDistance(_ distance: CGFloat) {
        Task { [processor] in
            await processor.updateDragCancelDistance(distance)
        }
    }

    func updateTypingGraceMs(_ milliseconds: Double) {
        Task { [processor] in
            await processor.updateTypingGrace(milliseconds)
        }
    }

    func updateIntentMoveThresholdMm(_ millimeters: Double) {
        Task { [processor] in
            await processor.updateIntentMoveThreshold(millimeters)
        }
    }

    func updateIntentVelocityThresholdMmPerSec(_ millimetersPerSecond: Double) {
        Task { [processor] in
            await processor.updateIntentVelocityThreshold(millimetersPerSecond)
        }
    }

    func updateAllowMouseTakeover(_ enabled: Bool) {
        Task { [processor] in
            await processor.updateAllowMouseTakeover(enabled)
        }
    }

    func updateForceClickCap(_ grams: Double) {
        Task { [processor] in
            await processor.updateForceClickCap(grams)
        }
    }

    func updateHapticStrength(_ normalized: Double) {
        Task { [processor] in
            await processor.updateHapticStrength(normalized)
        }
    }

    func updateSnapRadiusPercent(_ percent: Double) {
        Task { [processor] in
            await processor.updateSnapRadiusPercent(percent)
        }
    }

    func updateChordalShiftEnabled(_ enabled: Bool) {
        Task { [processor] in
            await processor.updateChordalShiftEnabled(enabled)
        }
    }

    func updateKeyboardModeEnabled(_ enabled: Bool) {
        keyboardModeEnabled = enabled
        Task { [processor] in
            await processor.updateKeyboardModeEnabled(enabled)
        }
    }

    func updateTapClickEnabled(_ enabled: Bool) {
        Task { [processor] in
            await processor.updateTapClickEnabled(enabled)
        }
    }

    func updateTapClickCadenceMs(_ milliseconds: Double) {
        Task { [processor] in
            await processor.updateTapClickCadence(milliseconds)
        }
    }

    func clearTouchState() {
        Task { [processor] in
            await processor.resetState(stopVoiceDictation: false)
        }
    }

    func clearVisualCaches() {
        Task { [processor] in
            await processor.clearVisualCaches()
        }
    }

    func setTouchSnapshotRecordingEnabled(_ enabled: Bool) {
        snapshotRecordingLock.withLockUnchecked { $0 = enabled }
        if !enabled {
            touchSnapshotLock.withLockUnchecked { $0 = TouchSnapshot() }
            pendingTouchLock.withLockUnchecked { $0 = PendingTouchState() }
        }
    }

    func setStatusVisualsEnabled(_ enabled: Bool) {
        uiStatusVisualsEnabled = enabled
        if enabled {
            Task { [processor] in
                let snapshot = await processor.statusSnapshot()
                Task { @MainActor in
                    self.contactFingerCountsBySide = snapshot.contactCounts
                    self.intentDisplayBySide = snapshot.intentDisplays
                    self.voiceGestureActive = snapshot.voiceGestureActive
                }
            }
        }
    }

    deinit {
        autoResyncTask?.cancel()
    }

    private func publishContactCountsIfNeeded(_ counts: SidePair<Int>) {
        guard uiStatusVisualsEnabled else { return }
        guard counts != contactFingerCountsBySide else { return }
        contactFingerCountsBySide = counts
    }

    private func publishIntentDisplayIfNeeded(_ display: SidePair<IntentDisplay>) {
        guard uiStatusVisualsEnabled else { return }
        guard display != intentDisplayBySide else { return }
        intentDisplayBySide = display
    }

    private func publishVoiceGestureIfNeeded(_ isActive: Bool) {
        guard uiStatusVisualsEnabled else { return }
        guard isActive != voiceGestureActive else { return }
        voiceGestureActive = isActive
    }

    private func publishVoiceDebugStatus(_ status: String?) {
        voiceDebugStatus = status
    }

    private actor TouchProcessor {
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
                let idKey = TouchProcessor.touchIDKey(from: touchKey)
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
                let idKey = TouchProcessor.touchIDKey(from: touchKey)
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
                let idKey = TouchProcessor.touchIDKey(from: touchKey)
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
                let deviceIndex = TouchProcessor.touchKeyDeviceIndex(touchKey)
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

        private let keyDispatcher: KeyEventDispatcher
        private let onTypingEnabledChanged: @Sendable (Bool) -> Void
        private let onActiveLayerChanged: @Sendable (Int) -> Void
        private let onDebugBindingDetected: @Sendable (KeyBinding) -> Void
        private let onContactCountChanged: @Sendable (SidePair<Int>) -> Void
        private let onIntentStateChanged: @Sendable (SidePair<IntentDisplay>) -> Void
        private let onVoiceGestureChanged: @Sendable (Bool) -> Void
        private let isDragDetectionEnabled = true
        private var isListening = false
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
        private var tapTraceFrameIndex: UInt64 = 0
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
        private static let hapticsQueue = DispatchQueue(
            label: "com.kyome.glasstokey.haptics",
            qos: .userInteractive
        )
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
            let voiceGestureActive: Bool
        }

#if DEBUG
        private let signposter = OSSignposter(
            subsystem: "com.kyome.GlassToKey",
            category: "TouchProcessing"
        )
#endif

        init(
            keyDispatcher: KeyEventDispatcher,
            onTypingEnabledChanged: @Sendable @escaping (Bool) -> Void,
            onActiveLayerChanged: @Sendable @escaping (Int) -> Void,
            onDebugBindingDetected: @Sendable @escaping (KeyBinding) -> Void,
            onContactCountChanged: @Sendable @escaping (SidePair<Int>) -> Void,
            onIntentStateChanged: @Sendable @escaping (SidePair<IntentDisplay>) -> Void,
            onVoiceGestureChanged: @Sendable @escaping (Bool) -> Void
        ) {
            self.keyDispatcher = keyDispatcher
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
            StatusSnapshot(
                contactCounts: contactFingerCountsBySide,
                intentDisplays: intentDisplayBySide,
                voiceGestureActive: voiceGestureActive
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
#if DEBUG
            tapTraceFrameIndex &+= 1
#endif
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

        func resetState(stopVoiceDictation: Bool = false) {
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
                    let removedPending = removePendingTouch(for: touchKey)
                    if let active = removedActive {
                        if let modifierKey = active.modifierKey {
                            handleModifierUp(modifierKey, binding: active.binding)
                        } else if active.holdRepeatActive {
                            stopRepeat(for: touchKey)
                       }
                    }
                    #if DEBUG
                    let traceBinding = removedActive?.binding ?? removedPending?.binding
                    recordTapTrace(
                        .disqualified,
                        touchKey: touchKey,
                        binding: traceBinding,
                        reason: .typingDisabled
                    )
                    #endif
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
                        var didDispatch = false
                        if intentAllowsTyping {
                            didDispatch = maybeSendPendingContinuousTap(
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
                            didDispatch = maybeSendPendingContinuousTap(
                                pending,
                                touchKey: touchKey,
                                at: point,
                                now: now
                            )
                        }
                        #if DEBUG
                        let elapsed = now - pending.startTime
                        if !didDispatch && elapsed > tapMaxDuration {
                            recordTapTrace(
                                .expired,
                                touchKey: touchKey,
                                binding: pending.binding,
                                reason: .timeout
                            )
                        } else {
                            recordTapTrace(.finalized, touchKey: touchKey, binding: pending.binding)
                        }
                        #endif
                    }
                    if disqualifiedTouches.remove(touchKey) != nil {
                        continue
                    }
                    let removedActive = removeActiveTouch(for: touchKey)
                    let hadActive = removedActive != nil
                    if var active = removedActive {
                        var didDispatch = false
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
                                didDispatch = true
                            }
                        }
                        endMomentaryHoldIfNeeded(active.holdBinding, touchKey: touchKey)
                        if guardTriggered {
                            continue
                        }
                        #if DEBUG
                        let elapsed = now - active.startTime
                        if !didDispatch && elapsed > tapMaxDuration {
                            recordTapTrace(
                                .expired,
                                touchKey: touchKey,
                                binding: active.binding,
                                reason: .timeout
                            )
                        } else {
                            recordTapTrace(.finalized, touchKey: touchKey, binding: active.binding)
                        }
                        #endif
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
                        var didDispatch = false
                        if intentAllowsTyping {
                            didDispatch = maybeSendPendingContinuousTap(
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
                            didDispatch = maybeSendPendingContinuousTap(
                                pending,
                                touchKey: touchKey,
                                at: point,
                                now: now
                            )
                        }
                        #if DEBUG
                        let elapsed = now - pending.startTime
                        if !didDispatch && elapsed > tapMaxDuration {
                            recordTapTrace(
                                .expired,
                                touchKey: touchKey,
                                binding: pending.binding,
                                reason: .timeout
                            )
                        } else {
                            recordTapTrace(.finalized, touchKey: touchKey, binding: pending.binding)
                        }
                        #endif
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
                        #if DEBUG
                        let elapsed = now - active.startTime
                        if elapsed > tapMaxDuration {
                            recordTapTrace(
                                .expired,
                                touchKey: touchKey,
                                binding: active.binding,
                                reason: .timeout
                            )
                        } else {
                            recordTapTrace(.finalized, touchKey: touchKey, binding: active.binding)
                        }
                        #endif
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
            #if DEBUG
            let event: TapTraceEventType = touchStates.value(for: touchKey) == nil ? .created : .updated
            recordTapTrace(event, touchKey: touchKey, binding: active.binding)
            #endif
            touchStates.set(touchKey, .active(active))
        }

        private func setPendingTouch(_ touchKey: TouchKey, _ pending: PendingTouch) {
            #if DEBUG
            let event: TapTraceEventType = touchStates.value(for: touchKey) == nil ? .created : .updated
            recordTapTrace(event, touchKey: touchKey, binding: pending.binding)
            #endif
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
            #if DEBUG
            recordTapTrace(
                .dispatched,
                touchKey: touchKey,
                binding: binding,
                char: traceCharScalar(from: binding.label),
                reason: .snapAccepted
            )
            #endif
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
                    #if DEBUG
                    let bestBinding = bindings.snapBindings[bestIndex]
                    let secondBinding = bindings.snapBindings[secondIndex]
                    let keyCell = traceKeyCell(for: bestBinding)
                    TapTrace.record(
                        .snapAmbiguity,
                        frame: tapTraceFrameIndex,
                        touchKey: touchKey,
                        keyRow: keyCell.row,
                        keyCol: keyCell.col,
                        keyCode: traceKeyCode(for: bestBinding),
                        char: traceCharScalar(from: bestBinding.label),
                        auxChar: traceCharScalar(from: secondBinding.label),
                        aux0: bestDistanceSq,
                        aux1: secondDistanceSq,
                        aux2: bestEdgeDistance,
                        aux3: secondEdgeDistance,
                        reason: .snapAmbiguity
                    )
                    #endif
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
                    keyDispatcher.postRightClick()
                } else if wasTwoFingerTapDetected {
                    if awaitingSecondTap, let deadline = doubleTapDeadline, now <= deadline {
                        keyDispatcher.postLeftClick(clickCount: 2)
                        awaitingSecondTap = false
                        doubleTapDeadline = nil
                    } else {
                        keyDispatcher.postLeftClick()
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
                #if DEBUG
                if let touchKey {
                    recordTapTrace(
                        .dispatched,
                        touchKey: touchKey,
                        binding: binding,
                        char: traceCharScalar(from: binding.label)
                    )
                }
                #endif
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
            keyDispatcher.postKeyStroke(code: code, flags: resolvedFlags, altAscii: altAscii)
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
            #if DEBUG
            if let touchKey {
                recordTapTrace(
                    .dispatched,
                    touchKey: touchKey,
                    binding: binding,
                    char: traceCharScalar(from: binding.label)
                )
            }
            #endif
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
            let strength = hapticStrength
            Self.hapticsQueue.async {
                _ = OMSManager.shared.playHapticFeedback(strength: strength, deviceID: deviceID)
            }
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
                    keyDispatcher.postKeyStroke(code: entry.code, flags: entry.flags, token: entry.token)
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
            keyDispatcher.postKey(code: code, flags: flags, keyDown: keyDown)
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
            #if DEBUG
            let binding: KeyBinding?
            switch state {
            case let .active(active):
                binding = active.binding
            case let .pending(pending):
                binding = pending.binding
            case .none:
                binding = nil
            }
            recordTapTrace(
                .disqualified,
                touchKey: touchKey,
                binding: binding,
                reason: traceReason(for: reason)
            )
            #endif
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

        #if DEBUG
        @inline(__always)
        private func recordTapTrace(
            _ type: TapTraceEventType,
            touchKey: TouchKey,
            binding: KeyBinding?,
            char: UInt32 = 0,
            reason: TapTraceReasonCode = .none
        ) {
            let keyCell = traceKeyCell(for: binding)
            let keyCode = traceKeyCode(for: binding)
            TapTrace.record(
                type,
                frame: tapTraceFrameIndex,
                touchKey: touchKey,
                keyRow: keyCell.row,
                keyCol: keyCell.col,
                keyCode: keyCode,
                char: char,
                reason: reason
            )
        }

        @inline(__always)
        private func traceKeyCell(for binding: KeyBinding?) -> (row: Int16, col: Int16) {
            guard let position = binding?.position else { return (-1, -1) }
            let row = Int16(clamping: position.row)
            let col = Int16(clamping: position.column)
            return (row, col)
        }

        @inline(__always)
        private func traceCharScalar(from label: String) -> UInt32 {
            guard label.unicodeScalars.count == 1, let scalar = label.unicodeScalars.first else {
                return 0
            }
            return scalar.value
        }

        @inline(__always)
        private func traceKeyCode(for binding: KeyBinding?) -> Int16 {
            guard let binding else { return -1 }
            switch binding.action {
            case let .key(code, _):
                return Int16(truncatingIfNeeded: code)
            default:
                return -1
            }
        }

        @inline(__always)
        private func traceReason(for reason: DisqualifyReason) -> TapTraceReasonCode {
            switch reason {
            case .dragCancelled:
                return .dragCancelled
            case .pendingDragCancelled:
                return .pendingDragCancelled
            case .leftContinuousRect:
                return .leftContinuousRect
            case .leftKeyRect, .pendingLeftRect:
                return .disqualifiedMove
            case .typingDisabled:
                return .typingDisabled
            case .forceCapExceeded:
                return .forceCapExceeded
            case .intentMouse:
                return .intentMouse
            case .offKeyNoSnap:
                return .offKeyNoSnap
            case .momentaryLayerCancelled:
                return .momentaryLayerCancelled
            }
        }
        #endif

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
}

final class RepeatToken: @unchecked Sendable {
    private let isActiveLock = OSAllocatedUnfairLock<Bool>(uncheckedState: true)

    var isActive: Bool {
        isActiveLock.withLockUnchecked(\.self)
    }

    func deactivate() {
        isActiveLock.withLockUnchecked { $0 = false }
    }
}

struct NormalizedRect: Codable, Hashable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    func rect(in size: CGSize) -> CGRect {
        CGRect(
            x: x * size.width,
            y: y * size.height,
            width: width * size.width,
            height: height * size.height
        )
    }

    func clamped(minWidth: CGFloat, minHeight: CGFloat) -> NormalizedRect {
        var updated = self
        updated.width = max(minWidth, min(updated.width, 1.0))
        updated.height = max(minHeight, min(updated.height, 1.0))
        updated.x = min(max(updated.x, 0.0), 1.0 - updated.width)
        updated.y = min(max(updated.y, 0.0), 1.0 - updated.height)
        return updated
    }

    func mirroredHorizontally() -> NormalizedRect {
        NormalizedRect(
            x: 1.0 - x - width,
            y: y,
            width: width,
            height: height
        )
    }

    func contains(_ point: CGPoint) -> Bool {
        let maxX = x + width
        let maxY = y + height
        return point.x >= x && point.x <= maxX && point.y >= y && point.y <= maxY
    }
}

enum KeyActionKind: String, Codable {
    case key
    case typingToggle
    case layerMomentary
    case layerToggle
    case none
}

    struct KeyAction: Codable, Hashable {
        var label: String
        var keyCode: UInt16
        var flags: UInt64
        var kind: KeyActionKind
        var layer: Int?
        var displayText: String {
            switch kind {
            case .none:
                return ""
            case .typingToggle:
                return KeyActionCatalog.typingToggleDisplayLabel
            default:
                return label
            }
        }

    private enum CodingKeys: String, CodingKey {
        case label
        case keyCode
        case flags
        case kind
        case layer
    }

    init(
        label: String,
        keyCode: UInt16,
        flags: UInt64,
        kind: KeyActionKind = .key,
        layer: Int? = nil
    ) {
        self.label = label
        self.keyCode = keyCode
        self.flags = flags
        self.kind = kind
        self.layer = layer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        flags = try container.decode(UInt64.self, forKey: .flags)
        kind = try container.decodeIfPresent(KeyActionKind.self, forKey: .kind) ?? .key
        layer = try container.decodeIfPresent(Int.self, forKey: .layer)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(label, forKey: .label)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(flags, forKey: .flags)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(layer, forKey: .layer)
    }
}

struct KeyMapping: Codable, Hashable {
    var primary: KeyAction
    var hold: KeyAction?
}

struct CustomButton: Identifiable, Codable, Hashable {
    var id: UUID
    var side: TrackpadSide
    var rect: NormalizedRect
    var action: KeyAction
    var hold: KeyAction?
    var layer: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case side
        case rect
        case action
        case hold
        case layer
    }

    init(
        id: UUID,
        side: TrackpadSide,
        rect: NormalizedRect,
        action: KeyAction,
        hold: KeyAction?,
        layer: Int = 0
    ) {
        self.id = id
        self.side = side
        self.rect = rect
        self.action = action
        self.hold = hold
        self.layer = layer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        side = try container.decode(TrackpadSide.self, forKey: .side)
        rect = try container.decode(NormalizedRect.self, forKey: .rect)
        action = try container.decode(KeyAction.self, forKey: .action)
        hold = try container.decodeIfPresent(KeyAction.self, forKey: .hold)
        layer = try container.decodeIfPresent(Int.self, forKey: .layer) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(side, forKey: .side)
        try container.encode(rect, forKey: .rect)
        try container.encode(action, forKey: .action)
        try container.encodeIfPresent(hold, forKey: .hold)
        try container.encode(layer, forKey: .layer)
    }
}

enum CustomButtonDefaults {
    static func defaultButtons(
        trackpadWidth: CGFloat,
        trackpadHeight: CGFloat,
        thumbAnchorsMM: [CGRect]
    ) -> [CustomButton] {
        let leftActions = [
            KeyActionCatalog.action(for: "Backspace"),
            KeyActionCatalog.action(for: "Space")
        ].compactMap { $0 }
        let rightActions = [
            KeyActionCatalog.action(for: "Space"),
            KeyActionCatalog.action(for: "Space"),
            KeyActionCatalog.action(for: "Space"),
            KeyActionCatalog.action(for: "Return")
        ].compactMap { $0 }

        func normalize(_ rect: CGRect) -> NormalizedRect {
            NormalizedRect(
                x: rect.minX / trackpadWidth,
                y: rect.minY / trackpadHeight,
                width: rect.width / trackpadWidth,
                height: rect.height / trackpadHeight
            )
        }

        var buttons: [CustomButton] = []
        for (index, rect) in thumbAnchorsMM.enumerated() {
            let normalized = normalize(rect)
            if index < leftActions.count {
                buttons.append(CustomButton(
                    id: UUID(),
                    side: .left,
                    rect: normalized.mirroredHorizontally(),
                    action: leftActions[index]
                    ,
                    hold: nil,
                    layer: 0
                ))
            }
            if index < rightActions.count {
                buttons.append(CustomButton(
                    id: UUID(),
                    side: .right,
                    rect: normalized,
                    action: rightActions[index]
                    ,
                    hold: nil,
                    layer: 0
                ))
            }
        }
        return buttons
    }
}

enum LayoutCustomButtonStorage {
    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()

    static func decode(from data: Data) -> [String: [Int: [CustomButton]]]? {
        guard !data.isEmpty else { return nil }
        return try? decoder.decode([String: [Int: [CustomButton]]].self, from: data)
    }

    static func buttons(
        for layout: TrackpadLayoutPreset,
        from data: Data
    ) -> [CustomButton]? {
        guard let map = decode(from: data) else { return nil }
        guard let layered = map[layout.rawValue] else { return nil }
        return allButtons(from: layered) ?? []
    }

    static func encode(_ map: [String: [Int: [CustomButton]]]) -> Data? {
        guard !map.isEmpty else { return nil }
        return try? encoder.encode(map)
    }

    static func layeredButtons(from buttons: [CustomButton]) -> [Int: [CustomButton]] {
        var layered: [Int: [CustomButton]] = [:]
        for button in buttons {
            layered[button.layer, default: []].append(button)
        }
        return layered
    }

    private static func allButtons(from map: [Int: [CustomButton]]?) -> [CustomButton]? {
        guard let map, !map.isEmpty else { return nil }
        return map.values.flatMap { $0 }
    }
}

enum KeyActionCatalog {
    static let typingToggleLabel = "Typing Toggle"
    static let typingToggleDisplayLabel = "Typing\nToggle"
    static let momentaryLayer1Label = "MO(1)"
    static let toggleLayer1Label = "TO(1)"
    static let noneLabel = "None"
    static var noneAction: KeyAction {
        KeyAction(
            label: noneLabel,
            keyCode: UInt16.max,
            flags: 0,
            kind: .none
        )
    }
    static let holdBindingsByLabel: [String: (CGKeyCode, CGEventFlags)] = [
        "Esc": (CGKeyCode(kVK_Escape), []),
        "Q": (CGKeyCode(kVK_ANSI_LeftBracket), []),
        "W": (CGKeyCode(kVK_ANSI_RightBracket), []),
        "E": (CGKeyCode(kVK_ANSI_LeftBracket), .maskShift),
        "R": (CGKeyCode(kVK_ANSI_RightBracket), .maskShift),
        "T": (CGKeyCode(kVK_ANSI_Quote), []),
        "Y": (CGKeyCode(kVK_ANSI_Minus), []),
        "U": (CGKeyCode(kVK_ANSI_7), .maskShift),
        "I": (CGKeyCode(kVK_ANSI_8), .maskShift),
        "O": (CGKeyCode(kVK_ANSI_F), .maskCommand),
        "P": (CGKeyCode(kVK_ANSI_R), .maskCommand),
        "A": (CGKeyCode(kVK_ANSI_A), .maskCommand),
        "S": (CGKeyCode(kVK_ANSI_S), .maskCommand),
        "D": (CGKeyCode(kVK_ANSI_9), .maskShift),
        "F": (CGKeyCode(kVK_ANSI_0), .maskShift),
        "G": (CGKeyCode(kVK_ANSI_Quote), .maskShift),
        "H": (CGKeyCode(kVK_ANSI_Minus), .maskShift),
        "J": (CGKeyCode(kVK_ANSI_1), .maskShift),
        "K": (CGKeyCode(kVK_ANSI_3), .maskShift),
        "L": (CGKeyCode(kVK_ANSI_Grave), .maskShift),
        "Z": (CGKeyCode(kVK_ANSI_Z), .maskCommand),
        "X": (CGKeyCode(kVK_ANSI_X), .maskCommand),
        "C": (CGKeyCode(kVK_ANSI_C), .maskCommand),
        "V": (CGKeyCode(kVK_ANSI_V), .maskCommand),
        //"B": (CGKeyCode(kVK_Control), []),
        "N": (CGKeyCode(kVK_ANSI_Equal), []),
        "M": (CGKeyCode(kVK_ANSI_2), .maskShift),
        ",": (CGKeyCode(kVK_ANSI_4), .maskShift),
        ".": (CGKeyCode(kVK_ANSI_6), .maskShift),
        "/": (CGKeyCode(kVK_ANSI_Backslash), [])
    ]
    static let bindingsByLabel: [String: (CGKeyCode, CGEventFlags)] = [
        "Esc": (CGKeyCode(kVK_Escape), []),
        "Tab": (CGKeyCode(kVK_Tab), []),
        "`": (CGKeyCode(kVK_ANSI_Grave), []),
        "1": (CGKeyCode(kVK_ANSI_1), []),
        "2": (CGKeyCode(kVK_ANSI_2), []),
        "3": (CGKeyCode(kVK_ANSI_3), []),
        "4": (CGKeyCode(kVK_ANSI_4), []),
        "5": (CGKeyCode(kVK_ANSI_5), []),
        "6": (CGKeyCode(kVK_ANSI_6), []),
        "7": (CGKeyCode(kVK_ANSI_7), []),
        "8": (CGKeyCode(kVK_ANSI_8), []),
        "9": (CGKeyCode(kVK_ANSI_9), []),
        "0": (CGKeyCode(kVK_ANSI_0), []),
        "-": (CGKeyCode(kVK_ANSI_Minus), []),
        "—": (CGKeyCode(kVK_ANSI_Minus), [.maskShift, .maskAlternate]),
        "=": (CGKeyCode(kVK_ANSI_Equal), []),
        "Q": (CGKeyCode(kVK_ANSI_Q), []),
        "W": (CGKeyCode(kVK_ANSI_W), []),
        "E": (CGKeyCode(kVK_ANSI_E), []),
        "R": (CGKeyCode(kVK_ANSI_R), []),
        "T": (CGKeyCode(kVK_ANSI_T), []),
        "Option": (CGKeyCode(kVK_Option), []),
        "Shift": (CGKeyCode(kVK_Shift), []),
        "A": (CGKeyCode(kVK_ANSI_A), []),
        "S": (CGKeyCode(kVK_ANSI_S), []),
        "D": (CGKeyCode(kVK_ANSI_D), []),
        "F": (CGKeyCode(kVK_ANSI_F), []),
        "G": (CGKeyCode(kVK_ANSI_G), []),
        "Ctrl": (CGKeyCode(kVK_Control), []),
        "Cmd": (CGKeyCode(kVK_Command), []),
        "Z": (CGKeyCode(kVK_ANSI_Z), []),
        "X": (CGKeyCode(kVK_ANSI_X), []),
        "C": (CGKeyCode(kVK_ANSI_C), []),
        "V": (CGKeyCode(kVK_ANSI_V), []),
        "B": (CGKeyCode(kVK_ANSI_B), []),
        "Y": (CGKeyCode(kVK_ANSI_Y), []),
        "U": (CGKeyCode(kVK_ANSI_U), []),
        "I": (CGKeyCode(kVK_ANSI_I), []),
        "O": (CGKeyCode(kVK_ANSI_O), []),
        "P": (CGKeyCode(kVK_ANSI_P), []),
        "[": (CGKeyCode(kVK_ANSI_LeftBracket), []),
        "]": (CGKeyCode(kVK_ANSI_RightBracket), []),
        "\\": (CGKeyCode(kVK_ANSI_Backslash), []),
        "Back": (CGKeyCode(kVK_Delete), []),
        "Left": (CGKeyCode(kVK_LeftArrow), []),
        "Right": (CGKeyCode(kVK_RightArrow), []),
        "Up": (CGKeyCode(kVK_UpArrow), []),
        "Down": (CGKeyCode(kVK_DownArrow), []),
        "H": (CGKeyCode(kVK_ANSI_H), []),
        "J": (CGKeyCode(kVK_ANSI_J), []),
        "K": (CGKeyCode(kVK_ANSI_K), []),
        "L": (CGKeyCode(kVK_ANSI_L), []),
        ";": (CGKeyCode(kVK_ANSI_Semicolon), []),
        "'": (CGKeyCode(kVK_ANSI_Quote), []),
        "Ret": (CGKeyCode(kVK_Return), []),
        "N": (CGKeyCode(kVK_ANSI_N), []),
        "M": (CGKeyCode(kVK_ANSI_M), []),
        ",": (CGKeyCode(kVK_ANSI_Comma), []),
        ".": (CGKeyCode(kVK_ANSI_Period), []),
        "/": (CGKeyCode(kVK_ANSI_Slash), []),
        "!": (CGKeyCode(kVK_ANSI_1), .maskShift),
        "@": (CGKeyCode(kVK_ANSI_2), .maskShift),
        "#": (CGKeyCode(kVK_ANSI_3), .maskShift),
        "$": (CGKeyCode(kVK_ANSI_4), .maskShift),
        "%": (CGKeyCode(kVK_ANSI_5), .maskShift),
        "^": (CGKeyCode(kVK_ANSI_6), .maskShift),
        "&": (CGKeyCode(kVK_ANSI_7), .maskShift),
        "*": (CGKeyCode(kVK_ANSI_8), .maskShift),
        "(": (CGKeyCode(kVK_ANSI_9), .maskShift),
        ")": (CGKeyCode(kVK_ANSI_0), .maskShift),
        "_": (CGKeyCode(kVK_ANSI_Minus), .maskShift),
        "+": (CGKeyCode(kVK_ANSI_Equal), .maskShift),
        "{": (CGKeyCode(kVK_ANSI_LeftBracket), .maskShift),
        "}": (CGKeyCode(kVK_ANSI_RightBracket), .maskShift),
        "|": (CGKeyCode(kVK_ANSI_Backslash), .maskShift),
        ":": (CGKeyCode(kVK_ANSI_Semicolon), .maskShift),
        "\"": (CGKeyCode(kVK_ANSI_Quote), .maskShift),
        "<": (CGKeyCode(kVK_ANSI_Comma), .maskShift),
        ">": (CGKeyCode(kVK_ANSI_Period), .maskShift),
        "?": (CGKeyCode(kVK_ANSI_Slash), .maskShift),
        "~": (CGKeyCode(kVK_ANSI_Grave), .maskShift),
        "Space": (CGKeyCode(kVK_Space), [])
    ]

    private struct ActionIdentifier: Hashable {
        let keyCode: UInt16
        let flags: UInt64
    }

    private static let duplicateLabelOverrides: [String: String] = [
        "Escape": "Esc",
        "Return": "Ret"
    ]

    private static func uniqueActions(from entries: [String: (CGKeyCode, CGEventFlags)]) -> [KeyAction] {
        var actionsById: [ActionIdentifier: KeyAction] = [:]
        for label in entries.keys.sorted() {
            guard let binding = entries[label] else { continue }
            let identifier = ActionIdentifier(
                keyCode: UInt16(binding.0),
                flags: binding.1.rawValue
            )
            guard actionsById[identifier] == nil else { continue }
            let displayLabel = duplicateLabelOverrides[label] ?? label
            actionsById[identifier] = KeyAction(
                label: displayLabel,
                keyCode: identifier.keyCode,
                flags: identifier.flags
            )
        }
        return actionsById.values.sorted { $0.label < $1.label }
    }

    static let holdLabelOverridesByLabel: [String: String] = [
        "Q": "[",
        "W": "]",
        "E": "{",
        "R": "}",
        "T": "'",
        "Y": "-",
        "U": "&",
        "I": "*",
        "O": "Cmd+F",
        "P": "Cmd+R",
        "A": "Cmd+A",
        "S": "Cmd+S",
        "D": "(",
        "F": ")",
        "G": "\"",
        "H": "_",
        "J": "!",
        "K": "#",
        "L": "~",
        "Z": "Cmd+Z",
        "X": "Cmd+X",
        "C": "Cmd+C",
        "V": "Cmd+V",
        "N": "=",
        "M": "@",
        ",": "$",
        ".": "^",
        "/": "\\"
    ]

    static let presets: [KeyAction] = {
        var items = uniqueActions(from: bindingsByLabel)
        items.append(KeyAction(
            label: typingToggleLabel,
            keyCode: 0,
            flags: 0,
            kind: .typingToggle
        ))
        items.append(contentsOf: layerActions)
        return items.sorted { $0.label < $1.label }
    }()

    static let holdPresets: [KeyAction] = {
        var actions = uniqueActions(from: bindingsByLabel)
        var identifiers = Set(actions.map { ActionIdentifier(keyCode: $0.keyCode, flags: $0.flags) })
        for (label, binding) in holdBindingsByLabel {
            let identifier = ActionIdentifier(
                keyCode: UInt16(binding.0),
                flags: binding.1.rawValue
            )
            guard !identifiers.contains(identifier) else { continue }
            let holdLabel = holdLabelOverridesByLabel[label] ?? "Hold \(label)"
            actions.append(KeyAction(
                label: holdLabel,
                keyCode: identifier.keyCode,
                flags: identifier.flags
            ))
            identifiers.insert(identifier)
        }
        actions.append(KeyAction(
            label: typingToggleLabel,
            keyCode: 0,
            flags: 0,
            kind: .typingToggle
        ))
        actions.append(contentsOf: layerActions)
        return actions.sorted { $0.label < $1.label }
    }()

    static func action(for label: String) -> KeyAction? {
        if label == noneLabel {
            return noneAction
        }
        if label == typingToggleLabel {
            return KeyAction(
                label: typingToggleLabel,
                keyCode: 0,
                flags: 0,
                kind: .typingToggle
            )
        }
        if label == momentaryLayer1Label {
            return KeyAction(
                label: momentaryLayer1Label,
                keyCode: 0,
                flags: 0,
                kind: .layerMomentary,
                layer: 1
            )
        }
        if label == toggleLayer1Label {
            return KeyAction(
                label: toggleLayer1Label,
                keyCode: 0,
                flags: 0,
                kind: .layerToggle,
                layer: 1
            )
        }
        guard let binding = bindingsByLabel[label] else { return nil }
        return KeyAction(
            label: label,
            keyCode: UInt16(binding.0),
            flags: binding.1.rawValue
        )
    }
    static func holdAction(for label: String) -> KeyAction? {
        guard let binding = holdBindingsByLabel[label] else { return nil }
        if let preset = action(
            forCode: UInt16(binding.0),
            flags: binding.1
        ) {
            return preset
        }
        let holdLabel = holdLabelOverridesByLabel[label] ?? "Hold \(label)"
        return KeyAction(
            label: holdLabel,
            keyCode: UInt16(binding.0),
            flags: binding.1.rawValue
        )
    }

    static func action(
        forCode keyCode: UInt16,
        flags: CGEventFlags
    ) -> KeyAction? {
        presets.first { $0.keyCode == keyCode && $0.flags == flags.rawValue }
    }

    private static var layerActions: [KeyAction] {
        [
            KeyAction(
                label: momentaryLayer1Label,
                keyCode: 0,
                flags: 0,
                kind: .layerMomentary,
                layer: 1
            ),
            KeyAction(
                label: toggleLayer1Label,
                keyCode: 0,
                flags: 0,
                kind: .layerToggle,
                layer: 1
            )
        ]
    }
}

enum KeyActionMappingStore {
    static func decode(_ data: Data) -> LayeredKeyMappings? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(LayeredKeyMappings.self, from: data)
    }

    static func decodeNormalized(_ data: Data) -> LayeredKeyMappings? {
        guard let layered = decode(data) else { return nil }
        return normalized(layered)
    }

    static func encode(_ mappings: LayeredKeyMappings) -> Data? {
        guard !mappings.isEmpty else { return nil }
        do {
            return try JSONEncoder().encode(mappings)
        } catch {
            return nil
        }
    }

    static func normalized(_ mappings: LayeredKeyMappings) -> LayeredKeyMappings {
        let layer0 = mappings[0] ?? [:]
        let layer1 = mappings[1] ?? layer0
        return [0: layer0, 1: layer1]
    }
}
