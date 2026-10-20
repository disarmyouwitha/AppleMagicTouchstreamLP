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
import IOKit.hidsystem
import OpenMultitouchSupport
import QuartzCore
import SwiftUI
import os

@MainActor
final class ContentViewModel: ObservableObject {
    enum KeyBindingAction: Sendable {
        case key(code: CGKeyCode, flags: CGEventFlags)
        case appLaunch(String)
        case leftClick
        case doubleClick
        case rightClick
        case middleClick
        case volumeUp
        case volumeDown
        case volumeUpSmall
        case volumeDownSmall
        case brightnessUp
        case brightnessDown
        case brightnessUpSmall
        case brightnessDownSmall
        case voice
        case typingToggle
        case chordalShift
        case gestureTwoFingerTap
        case gestureThreeFingerTap
        case gestureFourFingerHold
        case gestureInnerCornersHold
        case gestureFiveFingerSwipeLeft
        case gestureFiveFingerSwipeRight
        case layerMomentary(Int)
        case layerToggle(Int)
        case none
    }

    struct KeyBinding: Sendable {
        let rect: CGRect
        let normalizedRect: NormalizedRect
        let hitGeometry: KeyHitGeometry
        let normalizedHitGeometry: KeyHitGeometry
        let label: String
        let action: KeyBindingAction
        let position: GridKeyPosition?
        let customButtonID: UUID?
        let side: TrackpadSide
        let holdAction: KeyAction?
        let holdForceThreshold: Float

        init(
            rect: CGRect,
            normalizedRect: NormalizedRect,
            canvasSize: CGSize,
            label: String,
            action: KeyBindingAction,
            position: GridKeyPosition?,
            customButtonID: UUID? = nil,
            side: TrackpadSide,
            holdAction: KeyAction?,
            holdForceThreshold: Float = 0
        ) {
            self.rect = rect
            self.normalizedRect = normalizedRect
            self.hitGeometry = KeyHitGeometry(normalizedRect: normalizedRect, size: canvasSize)
            self.normalizedHitGeometry = KeyHitGeometry(normalizedRect: normalizedRect)
            self.label = label
            self.action = action
            self.position = position
            self.customButtonID = customButtonID
            self.side = side
            self.holdAction = holdAction
            self.holdForceThreshold = max(0, holdForceThreshold)
        }
    }

    struct Layout {
        let keyRects: [[CGRect]]
        let normalizedKeyRects: [[NormalizedRect]]
        let allowHoldBindings: Bool

        init(
            normalizedKeyRects: [[NormalizedRect]],
            trackpadSize: CGSize,
            allowHoldBindings: Bool = true
        ) {
            self.normalizedKeyRects = normalizedKeyRects
            self.allowHoldBindings = allowHoldBindings
            self.keyRects = normalizedKeyRects.map { row in
                row.map { $0.boundingRect(in: trackpadSize) }
            }
        }

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

    struct ReplayTimelineState: Equatable {
        var sourceName: String
        var frameCount: Int
        var durationSeconds: Double
        var currentFrameIndex: Int
        var currentTimeSeconds: Double
        var isPlaying: Bool
    }

    @MainActor
    final class StatusViewModel: ObservableObject {
        @Published var contactFingerCountsBySide = SidePair(left: 0, right: 0)
        @Published var intentDisplayBySide = SidePair(left: IntentDisplay.idle, right: .idle)
    }

    nonisolated let touchRevisionUpdates: AsyncStream<UInt64>
    let statusViewModel = StatusViewModel()
    @Published var isListening: Bool = false
    @Published var isTypingEnabled: Bool = false
    @Published var keyboardModeEnabled: Bool = false
    @Published var holdRepeatEnabled: Bool = false
    @Published private(set) var replayTimelineState: ReplayTimelineState?
    @Published private(set) var activeLayer: Int = 0
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

    private var keymapEditingEnabled = false
    private var debugHitPublishingEnabled = true
    private let debugHitMinimumPublishInterval: TimeInterval = 1.0 / 20.0
    private var lastDebugHitPublishTimeBySide = SidePair(left: 0.0, right: 0.0)

    private var uiStatusVisualsEnabled = true
    private var latestContactCounts = SidePair(left: 0, right: 0)
    private var latestIntentDisplay = SidePair(left: IntentDisplay.idle, right: .idle)

    private let manager = OMSManager.shared
    private let renderSnapshotService: RuntimeRenderSnapshotService
    private let runtimeCommandService: RuntimeCommandService
    private let runtimeLifecycleCoordinator: RuntimeLifecycleCoordinatorService
    private let captureReplayCoordinator: RuntimeCaptureReplayCoordinator
    private let deviceSessionService: RuntimeDeviceSessionService
    private var replayPlaybackTask: Task<Void, Never>?

    init() {
        let inputRuntimeService = InputRuntimeService(manager: manager)
        renderSnapshotService = RuntimeRenderSnapshotService()
        touchRevisionUpdates = renderSnapshotService.revisionUpdates
        weak var weakSelf: ContentViewModel?
        let debugBindingHandler: @Sendable (KeyBinding) -> Void = { binding in
            Task { @MainActor in
                weakSelf?.recordDebugHit(binding)
            }
        }
        let contactCountHandler: @Sendable (SidePair<Int>) -> Void = { counts in
            Task { @MainActor in
                weakSelf?.handleContactCountsChanged(counts)
            }
        }
        let intentStateHandler: @Sendable (SidePair<IntentDisplay>) -> Void = { display in
            Task { @MainActor in
                weakSelf?.handleIntentDisplayChanged(display)
            }
        }
        let runtimeEngine = RuntimeCore(
            dispatchService: PassiveOutputBoundary.shared,
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
            onIntentStateChanged: intentStateHandler
        )
        runtimeCommandService = RuntimeCommandService(runtimeEngine: runtimeEngine)
        runtimeLifecycleCoordinator = RuntimeLifecycleCoordinatorService(
            inputRuntimeService: inputRuntimeService,
            renderSnapshotService: renderSnapshotService,
            runtimeEngine: runtimeEngine,
            runtimeCommandService: runtimeCommandService
        )
        captureReplayCoordinator = RuntimeCaptureReplayCoordinator(
            inputRuntimeService: inputRuntimeService,
            runtimeLifecycleCoordinator: runtimeLifecycleCoordinator,
            runtimeEngine: runtimeEngine,
            renderSnapshotService: renderSnapshotService
        )
        deviceSessionService = RuntimeDeviceSessionService(
            manager: manager,
            runtimeEngine: runtimeEngine
        ) { state in
            weakSelf?.applyDeviceSessionState(state)
        }
        weakSelf = self
        applyDeviceSessionState(deviceSessionService.snapshot)
        loadDevices()
    }

    private func applyDeviceSessionState(_ state: RuntimeDeviceSessionService.State) {
        availableDevices = state.availableDevices
        leftDevice = state.leftDevice
        rightDevice = state.rightDevice
        hasDisconnectedTrackpads = state.hasDisconnectedTrackpads
    }

    var leftTouches: [OMSTouchData] {
        renderSnapshotService.snapshot().left
    }

    var rightTouches: [OMSTouchData] {
        renderSnapshotService.snapshot().right
    }

    private func recordDebugHit(_ binding: KeyBinding) {
        guard debugHitPublishingEnabled else { return }
        let now = CACurrentMediaTime()
        let lastPublishTime = lastDebugHitPublishTimeBySide[binding.side]
        guard now - lastPublishTime >= debugHitMinimumPublishInterval else { return }
        lastDebugHitPublishTimeBySide[binding.side] = now
        let hit = DebugHit(
            rect: binding.rect,
            label: binding.label,
            side: binding.side,
            timestamp: now
        )
        switch binding.side {
        case .left:
            debugLastHitLeft = hit
        case .right:
            debugLastHitRight = hit
        }
    }

    func start() {
        let started = runtimeLifecycleCoordinator.start()
        if started {
            isListening = true
        }
    }

    func stop() {
        let stopped = runtimeLifecycleCoordinator.stop(stopVoiceDictation: true)
        if stopped {
            isListening = false
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
        deviceSessionService.loadDevices(preserveSelection: preserveSelection)
        applyDeviceSessionState(deviceSessionService.snapshot)
    }

    func selectLeftDevice(_ device: OMSDeviceInfo?) {
        deviceSessionService.selectLeftDevice(device)
        applyDeviceSessionState(deviceSessionService.snapshot)
    }

    func selectRightDevice(_ device: OMSDeviceInfo?) {
        deviceSessionService.selectRightDevice(device)
        applyDeviceSessionState(deviceSessionService.snapshot)
    }

    func setAutoResyncEnabled(_ enabled: Bool) {
        deviceSessionService.setAutoResyncEnabled(enabled)
    }

    func configureLayouts(
        leftLayout: Layout,
        rightLayout: Layout,
        leftLabels: [[String]],
        rightLabels: [[String]],
        trackpadSize: CGSize,
        trackpadWidthMm: CGFloat
    ) {
        runtimeCommandService.updateLayouts(
            leftLayout: leftLayout,
            rightLayout: rightLayout,
            leftLabels: leftLabels,
            rightLabels: rightLabels,
            trackpadSize: trackpadSize,
            trackpadWidthMm: trackpadWidthMm
        )
    }

    func updateCustomButtons(_ buttons: [CustomButton]) {
        runtimeCommandService.updateCustomButtons(buttons)
    }

    func updateKeyMappings(_ actions: LayeredKeyMappings) {
        runtimeCommandService.updateKeyMappings(actions)
    }

    func snapshotTouchData() -> TouchSnapshot {
        Self.mapTouchSnapshot(renderSnapshotService.snapshot())
    }

    func snapshotTouchDataIfUpdated(
        since revision: UInt64
    ) -> TouchSnapshot? {
        renderSnapshotService.snapshotIfUpdated(since: revision).map(Self.mapTouchSnapshot)
    }

    private nonisolated static func mapTouchSnapshot(_ snapshot: RuntimeTouchSnapshot) -> TouchSnapshot {
        TouchSnapshot(
            left: snapshot.left,
            right: snapshot.right,
            revision: snapshot.revision,
            hasTransitionState: snapshot.hasTransitionState
        )
    }

    func setPersistentLayer(_ layer: Int) {
        runtimeCommandService.setPersistentLayer(layer)
    }

    func updateHoldThreshold(_ seconds: TimeInterval) {
        runtimeCommandService.updateHoldThreshold(seconds)
    }

    func updateDragCancelDistance(_ distance: CGFloat) {
        runtimeCommandService.updateDragCancelDistance(distance)
    }

    func updateTypingGraceMs(_ milliseconds: Double) {
        runtimeCommandService.updateTypingGrace(milliseconds)
    }

    func updateIntentMoveThresholdMm(_ millimeters: Double) {
        runtimeCommandService.updateIntentMoveThreshold(millimeters)
    }

    func updateIntentVelocityThresholdMmPerSec(_ millimetersPerSecond: Double) {
        runtimeCommandService.updateIntentVelocityThreshold(millimetersPerSecond)
    }

    func updateAllowMouseTakeover(_ enabled: Bool) {
        runtimeCommandService.updateAllowMouseTakeover(enabled)
    }

    func updateForceClickCap(_ grams: Double) {
        runtimeCommandService.updateForceClickCap(grams)
    }

    func updateForceClickMin(_ grams: Double) {
        runtimeCommandService.updateForceClickMin(grams)
    }

    func updateForceClickThreshold(_ grams: Double) {
        runtimeCommandService.updateForceClickThreshold(grams)
    }

    func updateHapticStrength(_ normalized: Double) {
        runtimeCommandService.updateHapticStrength(normalized)
    }

    func updateSnapRadiusPercent(_ percent: Double) {
        runtimeCommandService.updateSnapRadiusPercent(percent)
    }

    func updateKeyboardModeEnabled(_ enabled: Bool) {
        keyboardModeEnabled = false
        runtimeCommandService.updateKeyboardModeEnabled(false)
    }

    func updateHoldRepeatEnabled(_ enabled: Bool) {
        holdRepeatEnabled = enabled
        runtimeCommandService.updateHoldRepeatEnabled(enabled)
    }

    func updateGestureActions(_ actions: GestureActionSet) {
        runtimeCommandService.updateGestureActions(actions)
    }

    func updateGestureRepeatCadenceMsById(_ cadenceById: [String: Int]?) {
        runtimeCommandService.updateGestureRepeatCadenceMsById(
            GestureRepeatCadenceStorage.normalized(cadenceById)
        )
    }

    func setKeymapEditingEnabled(_ enabled: Bool) {
        guard keymapEditingEnabled != enabled else { return }
        keymapEditingEnabled = enabled
        debugHitPublishingEnabled = !enabled
        if enabled {
            debugLastHitLeft = nil
            debugLastHitRight = nil
        }
        runtimeCommandService.setKeymapEditingEnabled(enabled)
    }

    func updateTapClickCadenceMs(_ milliseconds: Double) {
        runtimeCommandService.updateTapClickCadence(milliseconds)
    }

    func clearTouchState() {
        runtimeCommandService.reset(stopVoiceDictation: false)
    }

    func clearVisualCaches() {
        runtimeCommandService.clearVisualCaches()
    }

    deinit {
        replayPlaybackTask?.cancel()
    }

    func startATPCapture(to outputURL: URL) throws {
        try captureReplayCoordinator.startCapture(
            to: outputURL,
            configuration: captureProfileSnapshot()
        )
    }

    func stopATPCapture() async throws -> Int {
        try await captureReplayCoordinator.stopCapture()
    }

    func replayATPCapture(from inputURL: URL) async throws -> Int {
        let info = try await captureReplayCoordinator.beginReplaySession(from: inputURL)
        replayTimelineState = ReplayTimelineState(
            sourceName: info.sourceName,
            frameCount: info.frameCount,
            durationSeconds: info.durationSeconds,
            currentFrameIndex: info.currentFrameIndex,
            currentTimeSeconds: info.currentTimeSeconds,
            isPlaying: false
        )
        let finalPosition = try await captureReplayCoordinator.playReplay()
        replayTimelineState?.currentFrameIndex = finalPosition.frameIndex
        replayTimelineState?.currentTimeSeconds = finalPosition.timeSeconds
        replayTimelineState?.isPlaying = false
        try await captureReplayCoordinator.endReplaySession()
        replayTimelineState = nil
        return info.frameCount
    }

    private func captureProfileSnapshot() -> AppKeymapProfile {
        let defaults = UserDefaults.standard
        let fallback = AppKeymapProfile.defaultProfile()

        let leftDeviceID = leftDevice?.deviceID
            ?? defaults.string(forKey: GesturePadDefaultsKeys.leftDeviceID)
            ?? fallback.leftDeviceID
        let rightDeviceID = rightDevice?.deviceID
            ?? defaults.string(forKey: GesturePadDefaultsKeys.rightDeviceID)
            ?? fallback.rightDeviceID
        let layoutPreset = defaults.string(forKey: GesturePadDefaultsKeys.layoutPreset)
            ?? fallback.layoutPreset
        let shortcutActions = ShortcutActionLibraryStorage.decode(
            from: defaults.data(forKey: GesturePadDefaultsKeys.shortcutActions) ?? Data()
        ) ?? fallback.shortcutActions
        let keySpacingByLayout = LayoutKeySpacingStorage.decode(
            from: defaults.data(forKey: GesturePadDefaultsKeys.keySpacingByLayout) ?? Data()
        ) ?? fallback.keySpacingPercentByLayout ?? [:]
        let columnSettingsByLayout = LayoutColumnSettingsStorage.decode(
            from: defaults.data(forKey: GesturePadDefaultsKeys.columnSettings) ?? Data()
        ) ?? fallback.columnSettingsByLayout
        let customButtonsByLayout = LayoutCustomButtonStorage.decode(
            from: defaults.data(forKey: GesturePadDefaultsKeys.customButtons) ?? Data()
        ) ?? fallback.customButtonsByLayout
        let keyMappingsByLayout = KeyActionMappingStore.decodeLayoutNormalized(
            defaults.data(forKey: GesturePadDefaultsKeys.keyMappings) ?? Data()
        ) ?? fallback.keyMappingsByLayout
        let keyGeometryByLayout = KeyGeometryStore.decodeLayoutNormalized(
            defaults.data(forKey: GesturePadDefaultsKeys.keyGeometry) ?? Data()
        ) ?? fallback.keyGeometryByLayout

        return AppKeymapProfile(
            leftDeviceID: leftDeviceID,
            rightDeviceID: rightDeviceID,
            layoutPreset: layoutPreset,
            activeLayer: activeLayer,
            autoResyncMissingTrackpads: defaults.object(forKey: GesturePadDefaultsKeys.autoResyncMissingTrackpads) as? Bool
                ?? fallback.autoResyncMissingTrackpads,
            runAtStartupEnabled: defaults.object(forKey: GesturePadDefaultsKeys.runAtStartupEnabled) as? Bool
                ?? fallback.runAtStartupEnabled,
            tapHoldDurationMs: defaults.object(forKey: GesturePadDefaultsKeys.tapHoldDuration) as? Double
                ?? fallback.tapHoldDurationMs,
            dragCancelDistance: defaults.object(forKey: GesturePadDefaultsKeys.dragCancelDistance) as? Double
                ?? fallback.dragCancelDistance,
            forceClickMin: defaults.object(forKey: GesturePadDefaultsKeys.forceClickMin) as? Double
                ?? fallback.forceClickMin,
            forceClickCap: defaults.object(forKey: GesturePadDefaultsKeys.forceClickCap) as? Double
                ?? fallback.forceClickCap,
            forceClickThreshold: defaults.object(forKey: GesturePadDefaultsKeys.forceClickThreshold) as? Double
                ?? fallback.forceClickThreshold,
            hapticStrength: defaults.object(forKey: GesturePadDefaultsKeys.hapticStrength) as? Double
                ?? fallback.hapticStrength,
            typingGraceMs: defaults.object(forKey: GesturePadDefaultsKeys.typingGraceMs) as? Double
                ?? fallback.typingGraceMs,
            intentMoveThresholdMm: defaults.object(forKey: GesturePadDefaultsKeys.intentMoveThresholdMm) as? Double
                ?? fallback.intentMoveThresholdMm,
            intentVelocityThresholdMmPerSec: defaults.object(forKey: GesturePadDefaultsKeys.intentVelocityThresholdMmPerSec) as? Double
                ?? fallback.intentVelocityThresholdMmPerSec,
            autocorrectEnabled: defaults.object(forKey: GesturePadDefaultsKeys.autocorrectEnabled) as? Bool
                ?? fallback.autocorrectEnabled,
            tapClickCadenceMs: defaults.object(forKey: GesturePadDefaultsKeys.tapClickCadenceMs) as? Double
                ?? fallback.tapClickCadenceMs,
            snapRadiusPercent: defaults.object(forKey: GesturePadDefaultsKeys.snapRadiusPercent) as? Double
                ?? fallback.snapRadiusPercent,
            keyboardModeEnabled: defaults.object(forKey: GesturePadDefaultsKeys.keyboardModeEnabled) as? Bool
                ?? keyboardModeEnabled,
            holdRepeatEnabled: defaults.object(forKey: GesturePadDefaultsKeys.holdRepeatEnabled) as? Bool
                ?? holdRepeatEnabled,
            shortcutActions: shortcutActions,
            twoFingerTapGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.twoFingerTapGestureAction)
                ?? fallback.twoFingerTapGestureAction,
            threeFingerTapGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.threeFingerTapGestureAction)
                ?? fallback.threeFingerTapGestureAction,
            twoFingerHoldGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.twoFingerHoldGestureAction)
                ?? fallback.twoFingerHoldGestureAction,
            threeFingerHoldGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.threeFingerHoldGestureAction)
                ?? fallback.threeFingerHoldGestureAction,
            fourFingerHoldGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.fourFingerHoldGestureAction)
                ?? fallback.fourFingerHoldGestureAction,
            outerCornersHoldGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.outerCornersHoldGestureAction)
                ?? fallback.outerCornersHoldGestureAction,
            innerCornersHoldGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.innerCornersHoldGestureAction)
                ?? fallback.innerCornersHoldGestureAction,
            leftEdgeUpGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.leftEdgeUpGestureAction)
                ?? fallback.leftEdgeUpGestureAction,
            leftEdgeDownGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.leftEdgeDownGestureAction)
                ?? fallback.leftEdgeDownGestureAction,
            rightEdgeUpGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.rightEdgeUpGestureAction)
                ?? fallback.rightEdgeUpGestureAction,
            rightEdgeDownGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.rightEdgeDownGestureAction)
                ?? fallback.rightEdgeDownGestureAction,
            topEdgeLeftGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.topEdgeLeftGestureAction)
                ?? fallback.topEdgeLeftGestureAction,
            topEdgeRightGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.topEdgeRightGestureAction)
                ?? fallback.topEdgeRightGestureAction,
            bottomEdgeLeftGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.bottomEdgeLeftGestureAction)
                ?? fallback.bottomEdgeLeftGestureAction,
            bottomEdgeRightGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.bottomEdgeRightGestureAction)
                ?? fallback.bottomEdgeRightGestureAction,
            threeFingerSwipeLeftGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.threeFingerSwipeLeftGestureAction)
                ?? fallback.threeFingerSwipeLeftGestureAction,
            threeFingerSwipeRightGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.threeFingerSwipeRightGestureAction)
                ?? fallback.threeFingerSwipeRightGestureAction,
            threeFingerSwipeUpGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.threeFingerSwipeUpGestureAction)
                ?? fallback.threeFingerSwipeUpGestureAction,
            threeFingerSwipeDownGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.threeFingerSwipeDownGestureAction)
                ?? fallback.threeFingerSwipeDownGestureAction,
            fourFingerSwipeLeftGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.fourFingerSwipeLeftGestureAction)
                ?? fallback.fourFingerSwipeLeftGestureAction,
            fourFingerSwipeRightGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.fourFingerSwipeRightGestureAction)
                ?? fallback.fourFingerSwipeRightGestureAction,
            fourFingerSwipeUpGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.fourFingerSwipeUpGestureAction)
                ?? fallback.fourFingerSwipeUpGestureAction,
            fourFingerSwipeDownGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.fourFingerSwipeDownGestureAction)
                ?? fallback.fourFingerSwipeDownGestureAction,
            fiveFingerSwipeLeftGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.fiveFingerSwipeLeftGestureAction)
                ?? fallback.fiveFingerSwipeLeftGestureAction,
            fiveFingerSwipeRightGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.fiveFingerSwipeRightGestureAction)
                ?? fallback.fiveFingerSwipeRightGestureAction,
            fiveFingerSwipeUpGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.fiveFingerSwipeUpGestureAction)
                ?? fallback.fiveFingerSwipeUpGestureAction,
            fiveFingerSwipeDownGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.fiveFingerSwipeDownGestureAction)
                ?? fallback.fiveFingerSwipeDownGestureAction,
            topLeftCornerSwipeGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.topLeftCornerSwipeGestureAction)
                ?? fallback.topLeftCornerSwipeGestureAction,
            topRightCornerSwipeGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.topRightCornerSwipeGestureAction)
                ?? fallback.topRightCornerSwipeGestureAction,
            bottomLeftCornerSwipeGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.bottomLeftCornerSwipeGestureAction)
                ?? fallback.bottomLeftCornerSwipeGestureAction,
            bottomRightCornerSwipeGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.bottomRightCornerSwipeGestureAction)
                ?? fallback.bottomRightCornerSwipeGestureAction,
            topLeftTriangleGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.topLeftTriangleGestureAction)
                ?? fallback.topLeftTriangleGestureAction,
            topRightTriangleGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.topRightTriangleGestureAction)
                ?? fallback.topRightTriangleGestureAction,
            bottomLeftTriangleGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.bottomLeftTriangleGestureAction)
                ?? fallback.bottomLeftTriangleGestureAction,
            bottomRightTriangleGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.bottomRightTriangleGestureAction)
                ?? fallback.bottomRightTriangleGestureAction,
            upperLeftCornerClickGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.upperLeftCornerClickGestureAction)
                ?? fallback.upperLeftCornerClickGestureAction,
            upperRightCornerClickGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.upperRightCornerClickGestureAction)
                ?? fallback.upperRightCornerClickGestureAction,
            lowerLeftCornerClickGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.lowerLeftCornerClickGestureAction)
                ?? fallback.lowerLeftCornerClickGestureAction,
            lowerRightCornerClickGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.lowerRightCornerClickGestureAction)
                ?? fallback.lowerRightCornerClickGestureAction,
            threeFingerClickGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.threeFingerClickGestureAction)
                ?? fallback.threeFingerClickGestureAction,
            fourFingerClickGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.fourFingerClickGestureAction)
                ?? fallback.fourFingerClickGestureAction,
            topLeftForceClickGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.topLeftForceClickGestureAction)
                ?? fallback.topLeftForceClickGestureAction,
            topRightForceClickGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.topRightForceClickGestureAction)
                ?? fallback.topRightForceClickGestureAction,
            bottomLeftForceClickGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.bottomLeftForceClickGestureAction)
                ?? fallback.bottomLeftForceClickGestureAction,
            bottomRightForceClickGestureAction: defaults.string(forKey: GesturePadDefaultsKeys.bottomRightForceClickGestureAction)
                ?? fallback.bottomRightForceClickGestureAction,
            gestureRepeatCadenceMsById: GestureRepeatCadenceStorage.decode(
                from: defaults.data(forKey: GesturePadDefaultsKeys.gestureRepeatCadenceMsById) ?? Data()
            ) ?? fallback.gestureRepeatCadenceMsById,
            keySpacingPercentByLayout: keySpacingByLayout,
            columnSettingsByLayout: columnSettingsByLayout,
            customButtonsByLayout: customButtonsByLayout,
            keyMappingsByLayout: keyMappingsByLayout,
            keyGeometryByLayout: keyGeometryByLayout
        )
    }

    func beginReplaySession(from inputURL: URL) async throws {
        await cancelReplayPlaybackTaskAndAwaitCompletion()
        let info = try await captureReplayCoordinator.beginReplaySession(from: inputURL)
        replayTimelineState = ReplayTimelineState(
            sourceName: info.sourceName,
            frameCount: info.frameCount,
            durationSeconds: info.durationSeconds,
            currentFrameIndex: info.currentFrameIndex,
            currentTimeSeconds: info.currentTimeSeconds,
            isPlaying: false
        )
    }

    func endReplaySession() async {
        await cancelReplayPlaybackTaskAndAwaitCompletion()
        do {
            try await captureReplayCoordinator.endReplaySession()
        } catch {
            // Keep UI responsive even if restore fails; AppDelegate surfaces errors when needed.
        }
        replayTimelineState = nil
    }

    func scrubReplay(to timeSeconds: Double) async throws {
        await cancelReplayPlaybackTaskAndAwaitCompletion()
        let position = try await captureReplayCoordinator.setReplayTimeSeconds(timeSeconds)
        replayTimelineState?.currentFrameIndex = position.frameIndex
        replayTimelineState?.currentTimeSeconds = position.timeSeconds
        replayTimelineState?.isPlaying = false
    }

    func toggleReplayPlayback() {
        guard var replayState = replayTimelineState else { return }
        if replayState.isPlaying {
            replayPlaybackTask?.cancel()
            replayPlaybackTask = nil
            replayState.isPlaying = false
            replayTimelineState = replayState
            return
        }

        let shouldRestartFromBeginning = replayState.frameCount > 0 &&
            replayState.currentTimeSeconds >= replayState.durationSeconds
        replayState.isPlaying = true
        replayTimelineState = replayState
        replayPlaybackTask = Task { [weak self] in
            guard let self else { return }
            do {
                if shouldRestartFromBeginning {
                    let restartPosition = try await self.captureReplayCoordinator.setReplayTimeSeconds(0)
                    await MainActor.run { [weak self] in
                        self?.replayTimelineState?.currentFrameIndex = restartPosition.frameIndex
                        self?.replayTimelineState?.currentTimeSeconds = restartPosition.timeSeconds
                    }
                }

                let finalPosition = try await self.captureReplayCoordinator.playReplay { progress in
                    Task { @MainActor [weak self] in
                        self?.replayTimelineState?.currentFrameIndex = progress.frameIndex
                        self?.replayTimelineState?.currentTimeSeconds = progress.timeSeconds
                    }
                }
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.replayTimelineState?.currentFrameIndex = finalPosition.frameIndex
                    self.replayTimelineState?.currentTimeSeconds = finalPosition.timeSeconds
                    self.replayTimelineState?.isPlaying = false
                    self.replayPlaybackTask = nil
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.replayTimelineState?.isPlaying = false
                    self.replayPlaybackTask = nil
                }
            }
        }
    }

    private func cancelReplayPlaybackTaskAndAwaitCompletion() async {
        guard let task = replayPlaybackTask else {
            return
        }
        replayPlaybackTask = nil
        task.cancel()
        await task.value
    }

    var isATPCaptureActive: Bool {
        captureReplayCoordinator.isCaptureActive
    }

    var isATPReplayActive: Bool {
        captureReplayCoordinator.isReplayActive
    }

    func setTouchSnapshotRecordingEnabled(_ enabled: Bool) {
        renderSnapshotService.setRecordingEnabled(enabled)
    }

    func setStatusVisualsEnabled(_ enabled: Bool) {
        uiStatusVisualsEnabled = enabled
        guard enabled else { return }
        publishContactCountsIfNeeded(latestContactCounts)
        publishIntentDisplayIfNeeded(latestIntentDisplay)
    }

    private func publishContactCountsIfNeeded(_ counts: SidePair<Int>) {
        guard uiStatusVisualsEnabled else { return }
        guard counts != statusViewModel.contactFingerCountsBySide else { return }
        statusViewModel.contactFingerCountsBySide = counts
    }

    private func publishIntentDisplayIfNeeded(_ display: SidePair<IntentDisplay>) {
        guard uiStatusVisualsEnabled else { return }
        guard display != statusViewModel.intentDisplayBySide else { return }
        statusViewModel.intentDisplayBySide = display
    }

    private func handleContactCountsChanged(_ counts: SidePair<Int>) {
        latestContactCounts = counts
        publishContactCountsIfNeeded(counts)
    }

    private func handleIntentDisplayChanged(_ display: SidePair<IntentDisplay>) {
        latestIntentDisplay = display
        publishIntentDisplayIfNeeded(display)
    }

}

