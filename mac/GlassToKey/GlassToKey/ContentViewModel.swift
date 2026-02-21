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

    nonisolated let touchRevisionUpdates: AsyncStream<UInt64>
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

    private var keymapEditingEnabled = false
    private var debugHitPublishingEnabled = true

    private var uiStatusVisualsEnabled = true

    private let manager = OMSManager.shared
    private let renderSnapshotService: RuntimeRenderSnapshotService
    private let runtimeCommandService: RuntimeCommandService
    private let runtimeLifecycleCoordinator: RuntimeLifecycleCoordinatorService
    private let statusVisualsService: RuntimeStatusVisualsService
    private let deviceSessionService: RuntimeDeviceSessionService

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
        let contactCountHandler: @Sendable (SidePair<Int>) -> Void = { _ in }
        let intentStateHandler: @Sendable (SidePair<IntentDisplay>) -> Void = { _ in }
        let voiceGestureHandler: @Sendable (Bool) -> Void = { _ in }
        let voiceStatusHandler: @Sendable (String?) -> Void = { status in
            Task { @MainActor in
                weakSelf?.publishVoiceDebugStatus(status)
            }
        }
        VoiceDictationManager.shared.setStatusHandler(voiceStatusHandler)
        let runtimeEngine = EngineActor(
            dispatchService: DispatchService.shared,
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
        runtimeCommandService = RuntimeCommandService(runtimeEngine: runtimeEngine)
        runtimeLifecycleCoordinator = RuntimeLifecycleCoordinatorService(
            inputRuntimeService: inputRuntimeService,
            renderSnapshotService: renderSnapshotService,
            runtimeEngine: runtimeEngine,
            runtimeCommandService: runtimeCommandService
        )
        statusVisualsService = RuntimeStatusVisualsService(
            runtimeEngine: runtimeEngine
        ) { snapshot in
            weakSelf?.applyRuntimeStatusSnapshot(snapshot)
        }
        deviceSessionService = RuntimeDeviceSessionService(
            manager: manager,
            runtimeEngine: runtimeEngine
        ) { state in
            weakSelf?.applyDeviceSessionState(state)
        }
        weakSelf = self
        applyDeviceSessionState(deviceSessionService.snapshot)
        statusVisualsService.startPolling()
        loadDevices()
    }

    private func applyDeviceSessionState(_ state: RuntimeDeviceSessionService.State) {
        availableDevices = state.availableDevices
        leftDevice = state.leftDevice
        rightDevice = state.rightDevice
        hasDisconnectedTrackpads = state.hasDisconnectedTrackpads
    }

    private func applyRuntimeStatusSnapshot(_ snapshot: RuntimeStatusSnapshot) {
        guard uiStatusVisualsEnabled else { return }
        publishContactCountsIfNeeded(snapshot.contactCountBySide)
        publishIntentDisplayIfNeeded(Self.mapIntentDisplay(snapshot.intentBySide))
        publishVoiceGestureIfNeeded(false)
    }

    var leftTouches: [OMSTouchData] {
        renderSnapshotService.snapshot().left
    }

    var rightTouches: [OMSTouchData] {
        renderSnapshotService.snapshot().right
    }

    private func recordDebugHit(_ binding: KeyBinding) {
        guard debugHitPublishingEnabled else { return }
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

    nonisolated private static func mapIntentDisplay(_ intent: RuntimeIntentMode) -> IntentDisplay {
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

    nonisolated private static func mapIntentDisplay(_ intent: SidePair<RuntimeIntentMode>) -> SidePair<IntentDisplay> {
        SidePair(
            left: mapIntentDisplay(intent.left),
            right: mapIntentDisplay(intent.right)
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

    func updateHapticStrength(_ normalized: Double) {
        runtimeCommandService.updateHapticStrength(normalized)
    }

    func updateSnapRadiusPercent(_ percent: Double) {
        runtimeCommandService.updateSnapRadiusPercent(percent)
    }

    func updateChordalShiftEnabled(_ enabled: Bool) {
        runtimeCommandService.updateChordalShiftEnabled(enabled)
    }

    func updateKeyboardModeEnabled(_ enabled: Bool) {
        keyboardModeEnabled = enabled
        runtimeCommandService.updateKeyboardModeEnabled(enabled)
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

    func updateTapClickEnabled(_ enabled: Bool) {
        runtimeCommandService.updateTapClickEnabled(enabled)
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

    func setTouchSnapshotRecordingEnabled(_ enabled: Bool) {
        renderSnapshotService.setRecordingEnabled(enabled)
    }

    func setStatusVisualsEnabled(_ enabled: Bool) {
        uiStatusVisualsEnabled = enabled
        statusVisualsService.setVisualsEnabled(enabled)
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
        "Emoji": (CGKeyCode(kVK_Function), []),
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
        if label == "Globe", let emojiBinding = bindingsByLabel["Emoji"] {
            return KeyAction(
                label: "Emoji",
                keyCode: UInt16(emojiBinding.0),
                flags: emojiBinding.1.rawValue
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
