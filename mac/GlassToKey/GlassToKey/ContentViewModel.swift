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
typealias LayoutLayeredKeyMappings = [String: LayeredKeyMappings]
typealias KeyGeometryOverrides = [String: KeyGeometryOverride]
typealias LayoutKeyGeometryOverrides = [String: KeyGeometryOverrides]

enum KeyboardModifierFlags {
    static let leftControl = CGEventFlags.maskControl.union(
        CGEventFlags(rawValue: UInt64(NX_DEVICELCTLKEYMASK))
    )
    static let rightControl = CGEventFlags.maskControl.union(
        CGEventFlags(rawValue: UInt64(NX_DEVICERCTLKEYMASK))
    )
    static let leftShift = CGEventFlags.maskShift.union(
        CGEventFlags(rawValue: UInt64(NX_DEVICELSHIFTKEYMASK))
    )
    static let rightShift = CGEventFlags.maskShift.union(
        CGEventFlags(rawValue: UInt64(NX_DEVICERSHIFTKEYMASK))
    )
    static let leftCommand = CGEventFlags.maskCommand.union(
        CGEventFlags(rawValue: UInt64(NX_DEVICELCMDKEYMASK))
    )
    static let rightCommand = CGEventFlags.maskCommand.union(
        CGEventFlags(rawValue: UInt64(NX_DEVICERCMDKEYMASK))
    )
    // macOS exposes right Option as a distinct device-side modifier bit.
    static let leftOption = CGEventFlags.maskAlternate.union(
        CGEventFlags(rawValue: UInt64(NX_DEVICELALTKEYMASK))
    )
    static let rightOption = CGEventFlags.maskAlternate.union(
        CGEventFlags(rawValue: UInt64(NX_DEVICERALTKEYMASK))
    )
}

enum KeyLayerConfig {
    static let baseLayer = 0
    static let maxLayer = 3
    static let editableLayers = Array(baseLayer...maxLayer)

    static func clamped(_ layer: Int) -> Int {
        max(baseLayer, min(layer, maxLayer))
    }
}

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

struct AppLaunchActionSpec: Codable, Hashable {
    let fileName: String
    let arguments: String

    private enum CodingKeys: String, CodingKey {
        case fileName = "FileName"
        case arguments = "Arguments"
    }
}

enum AppLaunchActionHelper {
    private static let prefix = "APP:"
    private static let maxDisplayLength = 56

    static func createActionLabel(fileName: String, arguments: String? = nil) -> String? {
        let trimmedFileName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFileName.isEmpty else { return nil }
        let spec = AppLaunchActionSpec(
            fileName: trimmedFileName,
            arguments: arguments?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(spec),
              let payload = String(data: data, encoding: .utf8) else {
            return nil
        }
        return prefix + payload
    }

    static func parse(_ action: String) -> AppLaunchActionSpec? {
        let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= prefix.count,
              String(trimmed.prefix(prefix.count)).caseInsensitiveCompare(prefix) == .orderedSame else {
            return nil
        }
        let payload = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty,
              let data = payload.data(using: .utf8),
              let spec = try? JSONDecoder().decode(AppLaunchActionSpec.self, from: data) else {
            return nil
        }
        let fileName = spec.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fileName.isEmpty else { return nil }
        let arguments = spec.arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        return AppLaunchActionSpec(fileName: fileName, arguments: arguments)
    }

    static func displayLabel(for action: String, includePrefix: Bool = true) -> String {
        guard let spec = parse(action) else {
            return action.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return displayLabel(for: spec, includePrefix: includePrefix)
    }

    static func keymapDisplayLabel(for action: String) -> String {
        displayLabel(for: action, includePrefix: false)
    }

    static func displayLabel(for spec: AppLaunchActionSpec, includePrefix: Bool = true) -> String {
        let trimmedFileName = spec.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedArguments = spec.arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        var leafName = (trimmedFileName as NSString).lastPathComponent
        if leafName.isEmpty {
            leafName = trimmedFileName
        }
        var display = trimmedArguments.isEmpty
            ? leafName
            : "\(leafName) \(trimmedArguments)"
        if includePrefix {
            display = "App: \(display)"
        }
        if display.count > maxDisplayLength {
            display = String(display.prefix(maxDisplayLength - 3)) + "..."
        }
        return display
    }
}

enum ShortcutModifierVariant: String, CaseIterable, Hashable, Codable {
    case generic
    case left
    case right
}

enum ShortcutModifier: String, CaseIterable, Hashable, Codable {
    case control
    case shift
    case option
    case command

    static let ordered: [ShortcutModifier] = [.control, .shift, .option, .command]

    func buttonLabel(for variant: ShortcutModifierVariant) -> String {
        switch self {
        case .control:
            switch variant {
            case .generic:
                return "Ctrl"
            case .left:
                return "L Ctrl"
            case .right:
                return "R Ctrl"
            }
        case .shift:
            switch variant {
            case .generic:
                return "Shift"
            case .left:
                return "L Shift"
            case .right:
                return "R Shift"
            }
        case .option:
            switch variant {
            case .generic:
                return "Option"
            case .left:
                return "L Option"
            case .right:
                return "AltGr"
            }
        case .command:
            switch variant {
            case .generic:
                return "Cmd"
            case .left:
                return "L Cmd"
            case .right:
                return "R Cmd"
            }
        }
    }

    func menuLabel(for variant: ShortcutModifierVariant) -> String {
        switch self {
        case .control:
            switch variant {
            case .generic:
                return "Ctrl"
            case .left:
                return "Left Ctrl"
            case .right:
                return "Right Ctrl"
            }
        case .shift:
            switch variant {
            case .generic:
                return "Shift"
            case .left:
                return "Left Shift"
            case .right:
                return "Right Shift"
            }
        case .option:
            switch variant {
            case .generic:
                return "Option"
            case .left:
                return "Left Option"
            case .right:
                return "Right Option (AltGr)"
            }
        case .command:
            switch variant {
            case .generic:
                return "Cmd"
            case .left:
                return "Left Cmd"
            case .right:
                return "Right Cmd"
            }
        }
    }

    func displayLabel(for variant: ShortcutModifierVariant) -> String {
        switch self {
        case .control:
            switch variant {
            case .generic:
                return "Ctrl"
            case .left:
                return "Left Ctrl"
            case .right:
                return "Right Ctrl"
            }
        case .shift:
            switch variant {
            case .generic:
                return "Shift"
            case .left:
                return "Left Shift"
            case .right:
                return "Right Shift"
            }
        case .option:
            switch variant {
            case .generic:
                return "Option"
            case .left:
                return "Left Option"
            case .right:
                return "AltGr"
            }
        case .command:
            switch variant {
            case .generic:
                return "Cmd"
            case .left:
                return "Left Cmd"
            case .right:
                return "Right Cmd"
            }
        }
    }

    func serializedLabel(for variant: ShortcutModifierVariant) -> String {
        switch self {
        case .control:
            switch variant {
            case .generic:
                return "Ctrl"
            case .left:
                return "Left Ctrl"
            case .right:
                return "Right Ctrl"
            }
        case .shift:
            switch variant {
            case .generic:
                return "Shift"
            case .left:
                return "Left Shift"
            case .right:
                return "Right Shift"
            }
        case .option:
            switch variant {
            case .generic:
                return "Option"
            case .left:
                return "Left Option"
            case .right:
                return "Right Option"
            }
        case .command:
            switch variant {
            case .generic:
                return "Cmd"
            case .left:
                return "Left Cmd"
            case .right:
                return "Right Cmd"
            }
        }
    }

    func flags(for variant: ShortcutModifierVariant) -> CGEventFlags {
        switch self {
        case .control:
            switch variant {
            case .generic:
                return .maskControl
            case .left:
                return KeyboardModifierFlags.leftControl
            case .right:
                return KeyboardModifierFlags.rightControl
            }
        case .shift:
            switch variant {
            case .generic:
                return .maskShift
            case .left:
                return KeyboardModifierFlags.leftShift
            case .right:
                return KeyboardModifierFlags.rightShift
            }
        case .option:
            switch variant {
            case .generic:
                return .maskAlternate
            case .left:
                return KeyboardModifierFlags.leftOption
            case .right:
                return KeyboardModifierFlags.rightOption
            }
        case .command:
            switch variant {
            case .generic:
                return .maskCommand
            case .left:
                return KeyboardModifierFlags.leftCommand
            case .right:
                return KeyboardModifierFlags.rightCommand
            }
        }
    }

    static func parse(_ text: String) -> (modifier: ShortcutModifier, variant: ShortcutModifierVariant)? {
        switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ctrl", "control":
            return (.control, .generic)
        case "left ctrl", "left control", "lctrl", "lcontrol":
            return (.control, .left)
        case "right ctrl", "right control", "rctrl", "rcontrol":
            return (.control, .right)
        case "shift":
            return (.shift, .generic)
        case "left shift", "lshift":
            return (.shift, .left)
        case "right shift", "rshift":
            return (.shift, .right)
        case "option", "alt":
            return (.option, .generic)
        case "left option", "left alt", "lalt", "loption":
            return (.option, .left)
        case "right option", "right-option", "rightoption", "ralt", "altgr", "alt gr":
            return (.option, .right)
        case "cmd", "command", "meta", "super", "win":
            return (.command, .generic)
        case "left cmd", "left command", "left meta", "left super", "left win", "lcmd":
            return (.command, .left)
        case "right cmd", "right command", "right meta", "right super", "right win", "rcmd":
            return (.command, .right)
        default:
            return nil
        }
    }
}

struct ShortcutActionSpec: Hashable {
    let modifiers: [ShortcutModifier: ShortcutModifierVariant]
    let keyLabel: String

    private var orderedModifierSelections: [(ShortcutModifier, ShortcutModifierVariant)] {
        ShortcutModifier.ordered.compactMap { modifier in
            guard let variant = modifiers[modifier] else { return nil }
            return (modifier, variant)
        }
    }

    var flags: CGEventFlags {
        orderedModifierSelections.reduce(into: CGEventFlags()) { partialResult, selection in
            partialResult.formUnion(selection.0.flags(for: selection.1))
        }
    }

    var label: String {
        let parts = orderedModifierSelections.map { modifier, variant in
            modifier.serializedLabel(for: variant)
        } + [keyLabel]
        return parts.joined(separator: "+")
    }

    var displayLabel: String {
        let parts = orderedModifierSelections.map { modifier, variant in
            modifier.displayLabel(for: variant)
        } + [keyLabel]
        return parts.joined(separator: "+")
    }
}

enum ShortcutActionHelper {
    private static let keyEntries: [(String, CGKeyCode)] = [
        ("A", CGKeyCode(kVK_ANSI_A)),
        ("B", CGKeyCode(kVK_ANSI_B)),
        ("C", CGKeyCode(kVK_ANSI_C)),
        ("D", CGKeyCode(kVK_ANSI_D)),
        ("E", CGKeyCode(kVK_ANSI_E)),
        ("F", CGKeyCode(kVK_ANSI_F)),
        ("G", CGKeyCode(kVK_ANSI_G)),
        ("H", CGKeyCode(kVK_ANSI_H)),
        ("I", CGKeyCode(kVK_ANSI_I)),
        ("J", CGKeyCode(kVK_ANSI_J)),
        ("K", CGKeyCode(kVK_ANSI_K)),
        ("L", CGKeyCode(kVK_ANSI_L)),
        ("M", CGKeyCode(kVK_ANSI_M)),
        ("N", CGKeyCode(kVK_ANSI_N)),
        ("O", CGKeyCode(kVK_ANSI_O)),
        ("P", CGKeyCode(kVK_ANSI_P)),
        ("Q", CGKeyCode(kVK_ANSI_Q)),
        ("R", CGKeyCode(kVK_ANSI_R)),
        ("S", CGKeyCode(kVK_ANSI_S)),
        ("T", CGKeyCode(kVK_ANSI_T)),
        ("U", CGKeyCode(kVK_ANSI_U)),
        ("V", CGKeyCode(kVK_ANSI_V)),
        ("W", CGKeyCode(kVK_ANSI_W)),
        ("X", CGKeyCode(kVK_ANSI_X)),
        ("Y", CGKeyCode(kVK_ANSI_Y)),
        ("Z", CGKeyCode(kVK_ANSI_Z)),
        ("0", CGKeyCode(kVK_ANSI_0)),
        ("1", CGKeyCode(kVK_ANSI_1)),
        ("2", CGKeyCode(kVK_ANSI_2)),
        ("3", CGKeyCode(kVK_ANSI_3)),
        ("4", CGKeyCode(kVK_ANSI_4)),
        ("5", CGKeyCode(kVK_ANSI_5)),
        ("6", CGKeyCode(kVK_ANSI_6)),
        ("7", CGKeyCode(kVK_ANSI_7)),
        ("8", CGKeyCode(kVK_ANSI_8)),
        ("9", CGKeyCode(kVK_ANSI_9)),
        ("Space", CGKeyCode(kVK_Space)),
        ("Backspace", CGKeyCode(kVK_Delete)),
        ("Tab", CGKeyCode(kVK_Tab)),
        ("Enter", CGKeyCode(kVK_Return)),
        ("Esc", CGKeyCode(kVK_Escape)),
        ("Delete", CGKeyCode(kVK_ForwardDelete)),
        ("Insert", CGKeyCode(kVK_Help)),
        ("Home", CGKeyCode(kVK_Home)),
        ("End", CGKeyCode(kVK_End)),
        ("PageUp", CGKeyCode(kVK_PageUp)),
        ("PageDown", CGKeyCode(kVK_PageDown)),
        ("Left", CGKeyCode(kVK_LeftArrow)),
        ("Up", CGKeyCode(kVK_UpArrow)),
        ("Right", CGKeyCode(kVK_RightArrow)),
        ("Down", CGKeyCode(kVK_DownArrow)),
        (";", CGKeyCode(kVK_ANSI_Semicolon)),
        ("=", CGKeyCode(kVK_ANSI_Equal)),
        (",", CGKeyCode(kVK_ANSI_Comma)),
        ("-", CGKeyCode(kVK_ANSI_Minus)),
        (".", CGKeyCode(kVK_ANSI_Period)),
        ("/", CGKeyCode(kVK_ANSI_Slash)),
        ("`", CGKeyCode(kVK_ANSI_Grave)),
        ("[", CGKeyCode(kVK_ANSI_LeftBracket)),
        ("\\", CGKeyCode(kVK_ANSI_Backslash)),
        ("]", CGKeyCode(kVK_ANSI_RightBracket)),
        ("'", CGKeyCode(kVK_ANSI_Quote)),
        ("F1", CGKeyCode(kVK_F1)),
        ("F2", CGKeyCode(kVK_F2)),
        ("F3", CGKeyCode(kVK_F3)),
        ("F4", CGKeyCode(kVK_F4)),
        ("F5", CGKeyCode(kVK_F5)),
        ("F6", CGKeyCode(kVK_F6)),
        ("F7", CGKeyCode(kVK_F7)),
        ("F8", CGKeyCode(kVK_F8)),
        ("F9", CGKeyCode(kVK_F9)),
        ("F10", CGKeyCode(kVK_F10)),
        ("F11", CGKeyCode(kVK_F11)),
        ("F12", CGKeyCode(kVK_F12)),
        ("F13", CGKeyCode(kVK_F13)),
        ("F14", CGKeyCode(kVK_F14)),
        ("F15", CGKeyCode(kVK_F15)),
        ("F16", CGKeyCode(kVK_F16)),
        ("F17", CGKeyCode(kVK_F17)),
        ("F18", CGKeyCode(kVK_F18)),
        ("F19", CGKeyCode(kVK_F19)),
        ("F20", CGKeyCode(kVK_F20))
    ]

    private static let keyCodeByLabel = Dictionary(uniqueKeysWithValues: keyEntries)

    static let supportedKeyLabels: [String] = keyEntries.map(\.0)

    static func parse(_ text: String) -> ShortcutActionSpec? {
        let tokens = text.split(separator: "+").map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        guard tokens.count >= 2 else { return nil }
        guard let keyLabel = normalizeKeyLabel(tokens.last ?? "") else { return nil }
        var modifiers: [ShortcutModifier: ShortcutModifierVariant] = [:]
        for token in tokens.dropLast() {
            guard let parsed = ShortcutModifier.parse(token) else { return nil }
            modifiers[parsed.modifier] = parsed.variant
        }
        guard !modifiers.isEmpty,
              keyCodeByLabel[keyLabel] != nil else {
            return nil
        }
        return ShortcutActionSpec(modifiers: modifiers, keyLabel: keyLabel)
    }

    static func createAction(
        modifiers: [ShortcutModifier: ShortcutModifierVariant],
        keyLabel: String
    ) -> KeyAction? {
        guard !modifiers.isEmpty,
              let normalizedKeyLabel = normalizeKeyLabel(keyLabel),
              let keyCode = keyCodeByLabel[normalizedKeyLabel] else {
            return nil
        }
        let spec = ShortcutActionSpec(modifiers: modifiers, keyLabel: normalizedKeyLabel)
        return KeyAction(
            label: spec.label,
            keyCode: UInt16(keyCode),
            flags: spec.flags.rawValue
        )
    }

    static func spec(for action: KeyAction) -> ShortcutActionSpec? {
        guard action.kind == .key else { return nil }
        return parse(action.label)
    }

    static func normalizeKeyLabel(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let uppercase = trimmed.uppercased()
        if keyCodeByLabel[uppercase] != nil {
            return uppercase
        }
        switch uppercase {
        case "BACK", "BACKSPACE":
            return "Backspace"
        case "RET", "RETURN", "ENTER":
            return "Enter"
        case "ESC", "ESCAPE":
            return "Esc"
        case "SPACE":
            return "Space"
        case "DELETE":
            return "Delete"
        case "INSERT", "HELP":
            return "Insert"
        case "HOME":
            return "Home"
        case "END":
            return "End"
        case "PAGEUP":
            return "PageUp"
        case "PAGEDOWN":
            return "PageDown"
        case "LEFT":
            return "Left"
        case "UP":
            return "Up"
        case "RIGHT":
            return "Right"
        case "DOWN":
            return "Down"
        default:
            break
        }
        if uppercase.hasPrefix("F"),
           let number = Int(uppercase.dropFirst()),
           (1...20).contains(number) {
            return "F\(number)"
        }
        return keyCodeByLabel[trimmed] != nil ? trimmed : nil
    }
}

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
        case brightnessUp
        case brightnessDown
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
        let side: TrackpadSide
        let holdAction: KeyAction?

        init(
            rect: CGRect,
            normalizedRect: NormalizedRect,
            canvasSize: CGSize,
            label: String,
            action: KeyBindingAction,
            position: GridKeyPosition?,
            side: TrackpadSide,
            holdAction: KeyAction?
        ) {
            self.rect = rect
            self.normalizedRect = normalizedRect
            self.hitGeometry = KeyHitGeometry(normalizedRect: normalizedRect, size: canvasSize)
            self.normalizedHitGeometry = KeyHitGeometry(normalizedRect: normalizedRect)
            self.label = label
            self.action = action
            self.position = position
            self.side = side
            self.holdAction = holdAction
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
    @Published var isTypingEnabled: Bool = true
    @Published var keyboardModeEnabled: Bool = false
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

    private let manager = OMSManager.shared
    private let renderSnapshotService: RuntimeRenderSnapshotService
    private let runtimeCommandService: RuntimeCommandService
    private let runtimeLifecycleCoordinator: RuntimeLifecycleCoordinatorService
    private let captureReplayCoordinator: RuntimeCaptureReplayCoordinator
    private let statusVisualsService: RuntimeStatusVisualsService
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
        let contactCountHandler: @Sendable (SidePair<Int>) -> Void = { _ in }
        let intentStateHandler: @Sendable (SidePair<IntentDisplay>) -> Void = { _ in }
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

    func updateForceClickMin(_ grams: Double) {
        runtimeCommandService.updateForceClickMin(grams)
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

    func updateGestureActions(
        twoFingerTap: KeyAction,
        threeFingerTap: KeyAction,
        twoFingerHold: KeyAction,
        threeFingerHold: KeyAction,
        fourFingerHold: KeyAction,
        outerCornersHold: KeyAction,
        innerCornersHold: KeyAction,
        fiveFingerSwipeLeft: KeyAction,
        fiveFingerSwipeRight: KeyAction
    ) {
        runtimeCommandService.updateGestureActions(
            twoFingerTap: twoFingerTap,
            threeFingerTap: threeFingerTap,
            twoFingerHold: twoFingerHold,
            threeFingerHold: threeFingerHold,
            fourFingerHold: fourFingerHold,
            outerCornersHold: outerCornersHold,
            innerCornersHold: innerCornersHold,
            fiveFingerSwipeLeft: fiveFingerSwipeLeft,
            fiveFingerSwipeRight: fiveFingerSwipeRight
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
        try captureReplayCoordinator.startCapture(to: outputURL)
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
        statusVisualsService.setVisualsEnabled(enabled)
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

struct KeyHitGeometry: Sendable, Hashable {
    let centerX: CGFloat
    let centerY: CGFloat
    let halfWidth: CGFloat
    let halfHeight: CGFloat
    let cosValue: CGFloat
    let sinValue: CGFloat
    let minX: CGFloat
    let maxX: CGFloat
    let minY: CGFloat
    let maxY: CGFloat
    let area: CGFloat
    let isRotated: Bool

    init(rect: CGRect) {
        self.init(
            centerX: rect.midX,
            centerY: rect.midY,
            width: rect.width,
            height: rect.height,
            rotationDegrees: 0
        )
    }

    init(normalizedRect: NormalizedRect) {
        self.init(
            centerX: normalizedRect.centerX,
            centerY: normalizedRect.centerY,
            width: normalizedRect.width,
            height: normalizedRect.height,
            rotationDegrees: normalizedRect.rotationDegrees
        )
    }

    init(normalizedRect: NormalizedRect, size: CGSize) {
        self.init(
            centerX: normalizedRect.centerX * size.width,
            centerY: normalizedRect.centerY * size.height,
            width: normalizedRect.width * size.width,
            height: normalizedRect.height * size.height,
            rotationDegrees: normalizedRect.rotationDegrees
        )
    }

    private init(
        centerX: CGFloat,
        centerY: CGFloat,
        width: CGFloat,
        height: CGFloat,
        rotationDegrees: Double
    ) {
        let halfWidth = width * 0.5
        let halfHeight = height * 0.5
        let area = width * height
        let normalizedRotation = NormalizedRect.normalizeDegrees(rotationDegrees)
        let isRotated = abs(normalizedRotation) >= 0.000_01

        if !isRotated {
            self.centerX = centerX
            self.centerY = centerY
            self.halfWidth = halfWidth
            self.halfHeight = halfHeight
            self.cosValue = 1
            self.sinValue = 0
            self.minX = centerX - halfWidth
            self.maxX = centerX + halfWidth
            self.minY = centerY - halfHeight
            self.maxY = centerY + halfHeight
            self.area = area
            self.isRotated = false
            return
        }

        let radians = CGFloat(-(normalizedRotation * .pi / 180.0))
        let cosValue = cos(radians)
        let sinValue = sin(radians)

        func rotatedCorner(localX: CGFloat, localY: CGFloat) -> CGPoint {
            CGPoint(
                x: centerX + (localX * cosValue) - (localY * -sinValue),
                y: centerY + (localX * -sinValue) + (localY * cosValue)
            )
        }

        let corners = [
            rotatedCorner(localX: -halfWidth, localY: -halfHeight),
            rotatedCorner(localX: halfWidth, localY: -halfHeight),
            rotatedCorner(localX: halfWidth, localY: halfHeight),
            rotatedCorner(localX: -halfWidth, localY: halfHeight)
        ]
        var minX = corners[0].x
        var maxX = corners[0].x
        var minY = corners[0].y
        var maxY = corners[0].y
        for corner in corners.dropFirst() {
            minX = min(minX, corner.x)
            maxX = max(maxX, corner.x)
            minY = min(minY, corner.y)
            maxY = max(maxY, corner.y)
        }

        self.centerX = centerX
        self.centerY = centerY
        self.halfWidth = halfWidth
        self.halfHeight = halfHeight
        self.cosValue = cosValue
        self.sinValue = sinValue
        self.minX = minX
        self.maxX = maxX
        self.minY = minY
        self.maxY = maxY
        self.area = area
        self.isRotated = true
    }

    @inline(__always)
    func contains(_ point: CGPoint) -> Bool {
        guard point.x >= minX, point.x <= maxX, point.y >= minY, point.y <= maxY else {
            return false
        }
        guard isRotated else { return true }
        let translatedX = point.x - centerX
        let translatedY = point.y - centerY
        let localX = (translatedX * cosValue) - (translatedY * sinValue)
        let localY = (translatedX * sinValue) + (translatedY * cosValue)
        return abs(localX) <= halfWidth && abs(localY) <= halfHeight
    }

    @inline(__always)
    func distanceToEdge(from point: CGPoint) -> CGFloat {
        let translatedX = point.x - centerX
        let translatedY = point.y - centerY
        let localX: CGFloat
        let localY: CGFloat
        if isRotated {
            localX = (translatedX * cosValue) - (translatedY * sinValue)
            localY = (translatedX * sinValue) + (translatedY * cosValue)
        } else {
            localX = translatedX
            localY = translatedY
        }
        let dx = halfWidth - abs(localX)
        let dy = halfHeight - abs(localY)
        return min(dx, dy)
    }
}

struct NormalizedRect: Codable, Hashable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    var rotationDegrees: Double = 0

    private enum CodingKeys: String, CodingKey {
        case x
        case y
        case width
        case height
        case rotationDegrees
    }

    var centerX: CGFloat {
        x + (width * 0.5)
    }

    var centerY: CGFloat {
        y + (height * 0.5)
    }

    init(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        rotationDegrees: Double = 0
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.rotationDegrees = Self.normalizeDegrees(rotationDegrees)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try container.decode(CGFloat.self, forKey: .x)
        y = try container.decode(CGFloat.self, forKey: .y)
        width = try container.decode(CGFloat.self, forKey: .width)
        height = try container.decode(CGFloat.self, forKey: .height)
        rotationDegrees = Self.normalizeDegrees(
            try container.decodeIfPresent(Double.self, forKey: .rotationDegrees) ?? 0
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        if abs(rotationDegrees) > 0.000_01 {
            try container.encode(rotationDegrees, forKey: .rotationDegrees)
        }
    }

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
        updated.rotationDegrees = Self.normalizeDegrees(updated.rotationDegrees)
        return updated
    }

    func mirroredHorizontally() -> NormalizedRect {
        NormalizedRect(
            x: 1.0 - x - width,
            y: y,
            width: width,
            height: height,
            rotationDegrees: -rotationDegrees
        )
    }

    func contains(_ point: CGPoint) -> Bool {
        if abs(rotationDegrees) < 0.000_01 {
            let maxX = x + width
            let maxY = y + height
            return point.x >= x && point.x <= maxX && point.y >= y && point.y <= maxY
        }

        let radians = CGFloat(-(rotationDegrees * .pi / 180.0))
        let cosValue = cos(radians)
        let sinValue = sin(radians)
        let localX = point.x - centerX
        let localY = point.y - centerY
        let rotatedX = (localX * cosValue) - (localY * sinValue)
        let rotatedY = (localX * sinValue) + (localY * cosValue)
        return abs(rotatedX) <= width * 0.5 && abs(rotatedY) <= height * 0.5
    }

    func distanceToEdge(from point: CGPoint) -> CGFloat {
        let radians = CGFloat(-(rotationDegrees * .pi / 180.0))
        let cosValue = cos(radians)
        let sinValue = sin(radians)
        let localX = point.x - centerX
        let localY = point.y - centerY
        let rotatedX = (localX * cosValue) - (localY * sinValue)
        let rotatedY = (localX * sinValue) + (localY * cosValue)
        let dx = (width * 0.5) - abs(rotatedX)
        let dy = (height * 0.5) - abs(rotatedY)
        return min(dx, dy)
    }

    func rotatedAround(
        pivotX: CGFloat,
        pivotY: CGFloat,
        rotationDegrees: Double
    ) -> NormalizedRect {
        guard abs(rotationDegrees) >= 0.000_01 else { return self }
        let radians = CGFloat(rotationDegrees * .pi / 180.0)
        let cosValue = cos(radians)
        let sinValue = sin(radians)
        let localX = centerX - pivotX
        let localY = centerY - pivotY
        let rotatedCenterX = pivotX + (localX * cosValue) - (localY * sinValue)
        let rotatedCenterY = pivotY + (localX * sinValue) + (localY * cosValue)
        return NormalizedRect(
            x: rotatedCenterX - (width * 0.5),
            y: rotatedCenterY - (height * 0.5),
            width: width,
            height: height,
            rotationDegrees: Self.normalizeDegrees(self.rotationDegrees + rotationDegrees)
        )
    }

    func corners(in size: CGSize) -> [CGPoint] {
        let rect = rect(in: size)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]
        guard abs(rotationDegrees) >= 0.000_01 else { return corners }

        let radians = CGFloat(rotationDegrees * .pi / 180.0)
        let cosValue = cos(radians)
        let sinValue = sin(radians)
        return corners.map { corner in
            let localX = corner.x - center.x
            let localY = corner.y - center.y
            return CGPoint(
                x: center.x + (localX * cosValue) - (localY * sinValue),
                y: center.y + (localX * sinValue) + (localY * cosValue)
            )
        }
    }

    func boundingRect(in size: CGSize) -> CGRect {
        let points = corners(in: size)
        guard let first = points.first else { return .zero }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func normalizeDegrees(_ value: Double) -> Double {
        var normalized = value.truncatingRemainder(dividingBy: 360.0)
        if normalized <= -180.0 {
            normalized += 360.0
        } else if normalized > 180.0 {
            normalized -= 360.0
        }
        return normalized
    }
}

struct KeyGeometryOverride: Codable, Hashable {
    var rotationDegrees: Double
    var widthScale: Double
    var heightScale: Double

    private enum CodingKeys: String, CodingKey {
        case rotationDegrees
        case widthScale
        case heightScale
    }

    init(
        rotationDegrees: Double = 0,
        widthScale: Double = 1.0,
        heightScale: Double = 1.0
    ) {
        self.rotationDegrees = min(max(rotationDegrees, 0.0), 360.0)
        self.widthScale = Self.normalizedScale(widthScale)
        self.heightScale = Self.normalizedScale(heightScale)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rotationDegrees = min(
            max(try container.decodeIfPresent(Double.self, forKey: .rotationDegrees) ?? 0.0, 0.0),
            360.0
        )
        widthScale = Self.normalizedScale(
            try container.decodeIfPresent(Double.self, forKey: .widthScale) ?? 1.0
        )
        heightScale = Self.normalizedScale(
            try container.decodeIfPresent(Double.self, forKey: .heightScale) ?? 1.0
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if rotationDegrees > 0.000_01 {
            try container.encode(rotationDegrees, forKey: .rotationDegrees)
        }
        if abs(widthScale - 1.0) > 0.000_01 {
            try container.encode(widthScale, forKey: .widthScale)
        }
        if abs(heightScale - 1.0) > 0.000_01 {
            try container.encode(heightScale, forKey: .heightScale)
        }
    }

    private static func normalizedScale(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 1.0 }
        return min(max(value, 0.05), 10.0)
    }
}

enum KeyActionKind: String, Codable {
    case key
    case appLaunch
    case leftClick
    case doubleClick
    case rightClick
    case middleClick
    case volumeUp
    case volumeDown
    case brightnessUp
    case brightnessDown
    case voice
    case typingToggle
    case chordalShift
    case gestureTwoFingerTap
    case gestureThreeFingerTap
    case gestureFourFingerHold
    case gestureInnerCornersHold
    case gestureFiveFingerSwipeLeft
    case gestureFiveFingerSwipeRight
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
                return KeyActionCatalog.noneLabel
            case .typingToggle:
                return KeyActionCatalog.typingToggleDisplayLabel
            case .appLaunch:
                return AppLaunchActionHelper.keymapDisplayLabel(for: label)
            default:
                if let spec = KeyActionCatalog.shortcutSpec(for: self) {
                    return spec.displayLabel
                }
                return label
            }
        }

        var pickerText: String {
            switch kind {
            case .typingToggle:
                return KeyActionCatalog.typingToggleLabel
            case .appLaunch:
                return AppLaunchActionHelper.displayLabel(for: label)
            default:
                if let spec = KeyActionCatalog.shortcutSpec(for: self) {
                    return spec.displayLabel
                }
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

extension KeyAction {
    var holdLabelText: String? {
        let display = displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard kind != .none,
              !display.isEmpty,
              display != KeyActionCatalog.noneLabel else {
            return nil
        }
        return displayText
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
    static let altGrLabel = "AltGr"
    static let voiceLabel = "Voice"
    static let typingToggleLabel = "Typing Toggle"
    static let typingToggleDisplayLabel = "Typing\nToggle"
    static let noneLabel = "None"
    static let leftClickLabel = "Left Click"
    static let doubleClickLabel = "Double Click"
    static let rightClickLabel = "Right Click"
    static let middleClickLabel = "Middle Click"
    static let volumeUpLabel = "VOL⬆️"
    static let volumeDownLabel = "VOL⬇️"
    static let brightnessUpLabel = "BRIGHT⬆️"
    static let brightnessDownLabel = "BRIGHT⬇️"
    static let chordalShiftLabel = "Chordal Shift"
    static let gestureTwoFingerTapLabel = "2-finger tap"
    static let gestureThreeFingerTapLabel = "3-finger tap"
    static let gestureFourFingerHoldLabel = "4-finger hold"
    static let gestureInnerCornersHoldLabel = "Inner corners hold"
    static let gestureFiveFingerSwipeLeftLabel = "5-finger swipe left"
    static let gestureFiveFingerSwipeRightLabel = "5-finger swipe right"
    static var noneAction: KeyAction {
        KeyAction(
            label: noneLabel,
            keyCode: UInt16.max,
            flags: 0,
            kind: .none
        )
    }
    static let shortcutKeyLabels = ShortcutActionHelper.supportedKeyLabels

    static func shortcutAction(
        modifiers: [ShortcutModifier: ShortcutModifierVariant],
        keyLabel: String
    ) -> KeyAction? {
        ShortcutActionHelper.createAction(modifiers: modifiers, keyLabel: keyLabel)
    }

    static func shortcutSpec(for action: KeyAction) -> ShortcutActionSpec? {
        ShortcutActionHelper.spec(for: action)
    }

    static func appLaunchAction(
        fileName: String,
        arguments: String? = nil
    ) -> KeyAction? {
        guard let label = AppLaunchActionHelper.createActionLabel(
            fileName: fileName,
            arguments: arguments
        ) else {
            return nil
        }
        return KeyAction(label: label, keyCode: 0, flags: 0, kind: .appLaunch)
    }

    static func appLaunchSpec(for action: KeyAction) -> AppLaunchActionSpec? {
        guard action.kind == .appLaunch else { return nil }
        return AppLaunchActionHelper.parse(action.label)
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
        "Option": (CGKeyCode(kVK_Option), KeyboardModifierFlags.leftOption),
        altGrLabel: (CGKeyCode(kVK_RightOption), KeyboardModifierFlags.rightOption),
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
        "Delete": (CGKeyCode(kVK_ForwardDelete), []),
        "Insert": (CGKeyCode(kVK_Help), []),
        "Home": (CGKeyCode(kVK_Home), []),
        "End": (CGKeyCode(kVK_End), []),
        "PageUp": (CGKeyCode(kVK_PageUp), []),
        "PageDown": (CGKeyCode(kVK_PageDown), []),
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

    private static let mouseActions: [KeyAction] = [
        KeyAction(label: leftClickLabel, keyCode: 0, flags: 0, kind: .leftClick),
        KeyAction(label: doubleClickLabel, keyCode: 0, flags: 0, kind: .doubleClick),
        KeyAction(label: rightClickLabel, keyCode: 0, flags: 0, kind: .rightClick),
        KeyAction(label: middleClickLabel, keyCode: 0, flags: 0, kind: .middleClick)
    ]

    private static let systemActions: [KeyAction] = [
        KeyAction(label: volumeUpLabel, keyCode: 0, flags: 0, kind: .volumeUp),
        KeyAction(label: volumeDownLabel, keyCode: 0, flags: 0, kind: .volumeDown),
        KeyAction(label: brightnessUpLabel, keyCode: 0, flags: 0, kind: .brightnessUp),
        KeyAction(label: brightnessDownLabel, keyCode: 0, flags: 0, kind: .brightnessDown)
    ]

    private static let modeActions: [KeyAction] = [
        KeyAction(label: typingToggleLabel, keyCode: 0, flags: 0, kind: .typingToggle),
        KeyAction(label: chordalShiftLabel, keyCode: 0, flags: 0, kind: .chordalShift)
    ]

    static let presets: [KeyAction] = {
        var items = uniqueActions(from: bindingsByLabel)
        items.append(contentsOf: mouseActions)
        items.append(contentsOf: systemActions)
        items.append(contentsOf: modeActions)
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
        actions.append(contentsOf: mouseActions)
        actions.append(contentsOf: systemActions)
        actions.append(contentsOf: modeActions)
        actions.append(contentsOf: layerActions)
        return actions.sorted { $0.label < $1.label }
    }()

    struct ActionGroup: Identifiable {
        let title: String
        let actions: [KeyAction]
        var id: String { title }
    }

    private static func makeActionGroup(
        title: String,
        labels: [String],
        resolver: (String) -> KeyAction?
    ) -> ActionGroup? {
        let actions = labels.compactMap(resolver)
        guard !actions.isEmpty else { return nil }
        return ActionGroup(title: title, actions: actions)
    }

    private static func dashedHeader(_ title: String) -> String {
        "\u{2014}\u{2014}\(title)\u{2014}\u{2014}"
    }

    private static let groupDefinitions: [(title: String, labels: [String])] = {
        let letters = (65...90)
            .compactMap { UnicodeScalar($0) }
            .map(String.init)
        let numbers = (0...9).map { String($0) }
        return [
            (dashedHeader("General"), [noneLabel]),
            (dashedHeader("Letters A-Z"), letters),
            (dashedHeader("Numbers 0-9"), numbers),
            (dashedHeader("Navigation & Editing"), [
                "Space",
                "Tab",
                "Enter",
                "Back",
                "Esc",
                "Delete",
                "Insert",
                "Home",
                "End",
                "PageUp",
                "PageDown",
                "Left",
                "Right",
                "Up",
                "Down"
            ]),
            (dashedHeader("Mouse Actions"), [
                leftClickLabel,
                doubleClickLabel,
                rightClickLabel,
                middleClickLabel
            ]),
            (dashedHeader("System Controls"), [
                "VOL_UP",
                volumeUpLabel,
                "VOL_DOWN",
                volumeDownLabel,
                "BRIGHT_UP",
                brightnessUpLabel,
                "BRIGHT_DOWN",
                brightnessDownLabel
            ]),
            (dashedHeader("Modifiers & Modes"), [
                "Shift",
                "Ctrl",
                "Option",
                altGrLabel,
                "Cmd",
                "Emoji",
                voiceLabel,
                chordalShiftLabel,
                typingToggleLabel
            ]),
            (dashedHeader("Symbols & Punctuation"), [
                "!",
                "@",
                "#",
                "$",
                "%",
                "^",
                "&",
                "*",
                "(",
                ")",
                "~",
                ";",
                ":",
                "'",
                "\"",
                ",",
                "<",
                ".",
                ">",
                "/",
                "?",
                "\\",
                "|",
                "[",
                "{",
                "]",
                "}",
                "-",
                "_",
                "+",
                "=",
                "`",
                "—"
            ])
        ]
    }()

    private static func buildActionGroups(
        using resolver: (String) -> KeyAction?
    ) -> [ActionGroup] {
        var groups: [ActionGroup] = groupDefinitions.compactMap { definition in
            makeActionGroup(title: definition.title, labels: definition.labels, resolver: resolver)
        }
        let layerGroup = ActionGroup(title: dashedHeader("Layers"), actions: layerActions)
        if !layerGroup.actions.isEmpty {
            groups.append(layerGroup)
        }
        return groups
    }

    private static let sharedActionGroups: [ActionGroup] = buildActionGroups(using: action)

    static let primaryActionGroups: [ActionGroup] = sharedActionGroups
    static let holdActionGroups: [ActionGroup] = sharedActionGroups

    static func action(for label: String) -> KeyAction? {
        if let spec = AppLaunchActionHelper.parse(label) {
            return KeyAction(
                label: AppLaunchActionHelper.createActionLabel(
                    fileName: spec.fileName,
                    arguments: spec.arguments
                ) ?? label,
                keyCode: 0,
                flags: 0,
                kind: .appLaunch
            )
        }
        if let shortcut = ShortcutActionHelper.parse(label),
           let action = ShortcutActionHelper.createAction(
            modifiers: shortcut.modifiers,
            keyLabel: shortcut.keyLabel
           ) {
            return action
        }
        let normalizedLabel: String
        switch label {
        case "Escape":
            normalizedLabel = "Esc"
        case "Enter":
            normalizedLabel = "Ret"
        case "Backspace":
            normalizedLabel = "Back"
        case "Alt", "LeftAlt", "LAlt":
            normalizedLabel = "Option"
        case "TT":
            normalizedLabel = typingToggleLabel
        case "EMOJI":
            normalizedLabel = "Emoji"
        case "VOICE":
            normalizedLabel = voiceLabel
        case "Win", "Meta", "Super", "LeftWin", "LeftMeta", "LeftSuper",
             "RightWin", "RightMeta", "RightSuper":
            normalizedLabel = "Cmd"
        case "Right Option", "RightOption", "RAlt":
            normalizedLabel = altGrLabel
        case "VOL_UP":
            normalizedLabel = volumeUpLabel
        case "VOL_DOWN":
            normalizedLabel = volumeDownLabel
        case "BRIGHT_UP":
            normalizedLabel = brightnessUpLabel
        case "BRIGHT_DOWN":
            normalizedLabel = brightnessDownLabel
        case "EmDash":
            normalizedLabel = "—"
        default:
            normalizedLabel = label
        }

        if let commandAlias = controlChordAlias(normalizedLabel) {
            return commandAlias
        }
        if label == noneLabel {
            return noneAction
        }
        if normalizedLabel == voiceLabel {
            return KeyAction(
                label: label,
                keyCode: 0,
                flags: 0,
                kind: .voice
            )
        }
        if normalizedLabel == leftClickLabel {
            return KeyAction(
                label: label,
                keyCode: 0,
                flags: 0,
                kind: .leftClick
            )
        }
        if normalizedLabel == doubleClickLabel {
            return KeyAction(
                label: label,
                keyCode: 0,
                flags: 0,
                kind: .doubleClick
            )
        }
        if normalizedLabel == rightClickLabel {
            return KeyAction(
                label: label,
                keyCode: 0,
                flags: 0,
                kind: .rightClick
            )
        }
        if normalizedLabel == middleClickLabel {
            return KeyAction(
                label: label,
                keyCode: 0,
                flags: 0,
                kind: .middleClick
            )
        }
        if normalizedLabel == volumeUpLabel {
            return KeyAction(
                label: label,
                keyCode: 0,
                flags: 0,
                kind: .volumeUp
            )
        }
        if normalizedLabel == volumeDownLabel {
            return KeyAction(
                label: label,
                keyCode: 0,
                flags: 0,
                kind: .volumeDown
            )
        }
        if normalizedLabel == brightnessUpLabel {
            return KeyAction(
                label: label,
                keyCode: 0,
                flags: 0,
                kind: .brightnessUp
            )
        }
        if normalizedLabel == brightnessDownLabel {
            return KeyAction(
                label: label,
                keyCode: 0,
                flags: 0,
                kind: .brightnessDown
            )
        }
        if normalizedLabel == typingToggleLabel {
            return KeyAction(
                label: label,
                keyCode: 0,
                flags: 0,
                kind: .typingToggle
            )
        }
        if normalizedLabel == chordalShiftLabel {
            return KeyAction(
                label: label,
                keyCode: 0,
                flags: 0,
                kind: .chordalShift
            )
        }
        if normalizedLabel == gestureInnerCornersHoldLabel {
            return KeyAction(
                label: label,
                keyCode: 0,
                flags: 0,
                kind: .gestureInnerCornersHold
            )
        }
        if let layer = layer(from: normalizedLabel, prefix: "MO", allowBaseLayer: false) {
            return makeLayerAction(kind: .layerMomentary, layer: layer)
        }
        if let layer = layer(from: normalizedLabel, prefix: "TO", allowBaseLayer: true) {
            return makeLayerAction(kind: .layerToggle, layer: layer)
        }
        if normalizedLabel == "Globe", let emojiBinding = bindingsByLabel["Emoji"] {
            return KeyAction(
                label: "Emoji",
                keyCode: UInt16(emojiBinding.0),
                flags: emojiBinding.1.rawValue
            )
        }
        guard let binding = bindingsByLabel[normalizedLabel] else { return nil }
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
        var actions = [makeLayerAction(kind: .layerToggle, layer: KeyLayerConfig.baseLayer)]
        actions.append(
            contentsOf: (KeyLayerConfig.baseLayer + 1...KeyLayerConfig.maxLayer).flatMap { layer in
                [
                    makeLayerAction(kind: .layerMomentary, layer: layer),
                    makeLayerAction(kind: .layerToggle, layer: layer)
                ]
            }
        )
        return actions
    }

    private static func makeLayerAction(kind: KeyActionKind, layer: Int) -> KeyAction {
        let clampedLayer = KeyLayerConfig.clamped(layer)
        let prefix = kind == .layerMomentary ? "MO" : "TO"
        return KeyAction(
            label: "\(prefix)(\(clampedLayer))",
            keyCode: 0,
            flags: 0,
            kind: kind,
            layer: clampedLayer
        )
    }

    private static func layer(from label: String, prefix: String, allowBaseLayer: Bool) -> Int? {
        let expectedPrefix = "\(prefix)("
        guard label.hasPrefix(expectedPrefix), label.hasSuffix(")") else { return nil }
        let start = label.index(label.startIndex, offsetBy: expectedPrefix.count)
        let end = label.index(before: label.endIndex)
        let numberText = label[start..<end]
        guard let parsed = Int(numberText) else { return nil }
        let clamped = KeyLayerConfig.clamped(parsed)
        guard clamped == parsed else { return nil }
        if !allowBaseLayer, clamped == KeyLayerConfig.baseLayer {
            return nil
        }
        return clamped
    }

    private static func controlChordAlias(_ label: String) -> KeyAction? {
        let keyCode: CGKeyCode
        switch label {
        case "Ctrl+F":
            keyCode = CGKeyCode(kVK_ANSI_F)
        case "Ctrl+R":
            keyCode = CGKeyCode(kVK_ANSI_R)
        case "Ctrl+X":
            keyCode = CGKeyCode(kVK_ANSI_X)
        case "Ctrl+C":
            keyCode = CGKeyCode(kVK_ANSI_C)
        case "Ctrl+V":
            keyCode = CGKeyCode(kVK_ANSI_V)
        case "Ctrl+A":
            keyCode = CGKeyCode(kVK_ANSI_A)
        case "Ctrl+S":
            keyCode = CGKeyCode(kVK_ANSI_S)
        case "Ctrl+Z":
            keyCode = CGKeyCode(kVK_ANSI_Z)
        default:
            return nil
        }
        return KeyAction(
            label: label,
            keyCode: UInt16(keyCode),
            flags: CGEventFlags.maskCommand.rawValue
        )
    }
}

enum KeyActionMappingStore {
    private static var allLayoutRawValues: [String] {
        TrackpadLayoutPreset.allCases.map(\.rawValue)
    }

    private static func storageOnly(_ mappings: [String: KeyMapping]) -> [String: KeyMapping] {
        mappings.filter { GridKeyPosition.from(storageKey: $0.key) != nil }
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
        var normalizedMappings: LayeredKeyMappings = [:]
        for layer in KeyLayerConfig.editableLayers {
            normalizedMappings[layer] = storageOnly(mappings[layer] ?? [:])
        }
        return normalizedMappings
    }

    static func emptyMappings() -> LayeredKeyMappings {
        var mappings: LayeredKeyMappings = [:]
        for layer in KeyLayerConfig.editableLayers {
            mappings[layer] = [:]
        }
        return mappings
    }

    static func decodeLayoutNormalized(_ data: Data) -> LayoutLayeredKeyMappings? {
        guard !data.isEmpty else { return nil }
        if let decoded = try? JSONDecoder().decode(LayoutLayeredKeyMappings.self, from: data) {
            return normalized(decoded)
        }
        return nil
    }

    static func encode(_ mappings: LayoutLayeredKeyMappings) -> Data? {
        guard !mappings.isEmpty else { return nil }
        do {
            return try JSONEncoder().encode(mappings)
        } catch {
            return nil
        }
    }

    static func normalized(_ mappings: LayoutLayeredKeyMappings) -> LayoutLayeredKeyMappings {
        var normalizedMappings: LayoutLayeredKeyMappings = [:]
        for layoutRawValue in allLayoutRawValues {
            let mapping = mappings[layoutRawValue] ?? emptyMappings()
            normalizedMappings[layoutRawValue] = normalized(mapping)
        }
        return normalizedMappings
    }

    static func emptyLayoutMappings() -> LayoutLayeredKeyMappings {
        var mappings: LayoutLayeredKeyMappings = [:]
        for layoutRawValue in allLayoutRawValues {
            mappings[layoutRawValue] = emptyMappings()
        }
        return mappings
    }

}

enum KeyGeometryStore {
    private static var allLayoutRawValues: [String] {
        TrackpadLayoutPreset.allCases.map(\.rawValue)
    }

    private static func storageOnly(_ overrides: KeyGeometryOverrides) -> KeyGeometryOverrides {
        overrides.reduce(into: [:]) { result, entry in
            guard GridKeyPosition.from(storageKey: entry.key) != nil else { return }
            let rotationDegrees = min(max(entry.value.rotationDegrees, 0.0), 360.0)
            let widthScale = min(max(entry.value.widthScale, 0.05), 10.0)
            let heightScale = min(max(entry.value.heightScale, 0.05), 10.0)
            let hasRotation = rotationDegrees > 0.000_01
            let hasWidthScale = abs(widthScale - 1.0) > 0.000_01
            let hasHeightScale = abs(heightScale - 1.0) > 0.000_01
            guard hasRotation || hasWidthScale || hasHeightScale else { return }
            result[entry.key] = KeyGeometryOverride(
                rotationDegrees: rotationDegrees,
                widthScale: widthScale,
                heightScale: heightScale
            )
        }
    }

    static func decodeLayoutNormalized(_ data: Data) -> LayoutKeyGeometryOverrides? {
        guard !data.isEmpty else { return nil }
        guard let decoded = try? JSONDecoder().decode(LayoutKeyGeometryOverrides.self, from: data) else {
            return nil
        }
        return normalized(decoded)
    }

    static func encode(_ overrides: LayoutKeyGeometryOverrides) -> Data? {
        guard !overrides.isEmpty else { return nil }
        return try? JSONEncoder().encode(overrides)
    }

    static func normalized(_ overrides: LayoutKeyGeometryOverrides) -> LayoutKeyGeometryOverrides {
        var normalizedOverrides: LayoutKeyGeometryOverrides = [:]
        for layoutRawValue in allLayoutRawValues {
            normalizedOverrides[layoutRawValue] = storageOnly(overrides[layoutRawValue] ?? [:])
        }
        return normalizedOverrides
    }

    static func emptyLayoutOverrides() -> LayoutKeyGeometryOverrides {
        var overrides: LayoutKeyGeometryOverrides = [:]
        for layoutRawValue in allLayoutRawValues {
            overrides[layoutRawValue] = [:]
        }
        return overrides
    }
}

struct AppKeymapProfile: Codable {
    let leftDeviceID: String
    let rightDeviceID: String
    let layoutPreset: String
    let activeLayer: Int?
    let autoResyncMissingTrackpads: Bool
    let runAtStartupEnabled: Bool?
    let tapHoldDurationMs: Double
    let dragCancelDistance: Double
    let forceClickMin: Double?
    let forceClickCap: Double
    let hapticStrength: Double
    let typingGraceMs: Double
    let intentMoveThresholdMm: Double
    let intentVelocityThresholdMmPerSec: Double
    let autocorrectEnabled: Bool
    let tapClickCadenceMs: Double
    let snapRadiusPercent: Double
    let chordalShiftEnabled: Bool
    let keyboardModeEnabled: Bool
    let twoFingerTapGestureAction: String?
    let threeFingerTapGestureAction: String?
    let twoFingerHoldGestureAction: String?
    let threeFingerHoldGestureAction: String?
    let fourFingerHoldGestureAction: String?
    let outerCornersHoldGestureAction: String?
    let innerCornersHoldGestureAction: String?
    let fiveFingerSwipeLeftGestureAction: String?
    let fiveFingerSwipeRightGestureAction: String?
    let keySpacingPercentByLayout: [String: Double]?
    let columnSettingsByLayout: [String: [ColumnLayoutSettings]]
    let customButtonsByLayout: [String: [Int: [CustomButton]]]
    let keyMappingsByLayout: LayoutLayeredKeyMappings?
    let keyGeometryByLayout: LayoutKeyGeometryOverrides?

    static func defaultProfile() -> AppKeymapProfile {
        AppKeymapProfile(
            leftDeviceID: "",
            rightDeviceID: "",
            layoutPreset: TrackpadLayoutPreset.sixByThree.rawValue,
            activeLayer: KeyLayerConfig.baseLayer,
            autoResyncMissingTrackpads: false,
            runAtStartupEnabled: GlassToKeySettings.runAtStartupEnabled,
            tapHoldDurationMs: GlassToKeySettings.tapHoldDurationMs,
            dragCancelDistance: GlassToKeySettings.dragCancelDistanceMm,
            forceClickMin: GlassToKeySettings.forceClickMin,
            forceClickCap: GlassToKeySettings.forceClickCap,
            hapticStrength: GlassToKeySettings.hapticStrengthPercent,
            typingGraceMs: GlassToKeySettings.typingGraceMs,
            intentMoveThresholdMm: GlassToKeySettings.intentMoveThresholdMm,
            intentVelocityThresholdMmPerSec: GlassToKeySettings.intentVelocityThresholdMmPerSec,
            autocorrectEnabled: GlassToKeySettings.autocorrectEnabled,
            tapClickCadenceMs: GlassToKeySettings.tapClickCadenceMs,
            snapRadiusPercent: GlassToKeySettings.snapRadiusPercent,
            chordalShiftEnabled: GlassToKeySettings.chordalShiftEnabled,
            keyboardModeEnabled: GlassToKeySettings.keyboardModeEnabled,
            twoFingerTapGestureAction: GlassToKeySettings.twoFingerTapGestureActionLabel,
            threeFingerTapGestureAction: GlassToKeySettings.threeFingerTapGestureActionLabel,
            twoFingerHoldGestureAction: GlassToKeySettings.twoFingerHoldGestureActionLabel,
            threeFingerHoldGestureAction: GlassToKeySettings.threeFingerHoldGestureActionLabel,
            fourFingerHoldGestureAction: GlassToKeySettings.fourFingerHoldGestureActionLabel,
            outerCornersHoldGestureAction: GlassToKeySettings.outerCornersHoldGestureActionLabel,
            innerCornersHoldGestureAction: GlassToKeySettings.innerCornersHoldGestureActionLabel,
            fiveFingerSwipeLeftGestureAction: GlassToKeySettings.fiveFingerSwipeLeftGestureActionLabel,
            fiveFingerSwipeRightGestureAction: GlassToKeySettings.fiveFingerSwipeRightGestureActionLabel,
            keySpacingPercentByLayout: [:],
            columnSettingsByLayout: [:],
            customButtonsByLayout: [:],
            keyMappingsByLayout: KeyActionMappingStore.emptyLayoutMappings(),
            keyGeometryByLayout: KeyGeometryStore.emptyLayoutOverrides()
        )
    }
}

enum PortableKeymapImportError: LocalizedError {
    case invalidFormat
    case invalidBundle
    case invalidKeymap
    case unsupportedActions([String])

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Import file is not a supported GlassToKey bundle or keymap JSON."
        case .invalidBundle:
            return "Expected a GlassToKey settings export with both settings and keymap data."
        case .invalidKeymap:
            return "Keymap section is invalid."
        case .unsupportedActions(let labels):
            let joined = labels.sorted().joined(separator: ", ")
            return "The import uses action labels this mac build cannot resolve: \(joined)"
        }
    }
}

enum PortableKeymapInterop {
    private static let bundleVersion = 1
    private static let keymapVersion = 2
    private static let minCustomButtonSize = CGSize(width: 0.05, height: 0.05)

    static func exportBundle(from profile: AppKeymapProfile) throws -> Data {
        let bundle = PortableProfileBundle(
            version: bundleVersion,
            settings: PortableSettings(profile: profile),
            keymapJson: try encodePortableKeymap(from: profile),
            hostExtensions: ["mac": MacHostProfileExtension(profile: profile)]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(bundle)
    }

    static func importProfile(from data: Data, currentProfile: AppKeymapProfile) throws -> AppKeymapProfile {
        let decoder = JSONDecoder()
        if let bundle = try? decoder.decode(PortableProfileBundle.self, from: data),
           let keymapJson = bundle.keymapJson,
           !keymapJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try importBundle(bundle, currentProfile: currentProfile)
        }

        if let keymap = try? decoder.decode(PortableKeymapStore.self, from: data) {
            return try applyPortableKeymap(keymap, to: currentProfile)
        }

        if let legacy = try? decoder.decode(AppKeymapProfile.self, from: data) {
            return legacy
        }

        throw PortableKeymapImportError.invalidFormat
    }

    static func decodeBundledDefaultProfile(from data: Data) -> AppKeymapProfile? {
        try? importProfile(from: data, currentProfile: AppKeymapProfile.defaultProfile())
    }

    private static func importBundle(
        _ bundle: PortableProfileBundle,
        currentProfile: AppKeymapProfile
    ) throws -> AppKeymapProfile {
        guard let settings = bundle.settings,
              let keymapJson = bundle.keymapJson,
              let keymapData = keymapJson.data(using: .utf8),
              let keymap = try? JSONDecoder().decode(PortableKeymapStore.self, from: keymapData) else {
            throw PortableKeymapImportError.invalidBundle
        }

        var profile = currentProfile
        let resolvedLayout = macLayoutName(fromPortable: settings.layoutPresetName) ?? currentProfile.layoutPreset
        let activeLayer = KeyLayerConfig.clamped(settings.activeLayer ?? currentProfile.activeLayer ?? KeyLayerConfig.baseLayer)

        var keySpacingByLayout = currentProfile.keySpacingPercentByLayout ?? [:]
        if let importedSpacingByLayout = settings.keyPaddingPercentByLayout {
            for (layoutName, value) in importedSpacingByLayout {
                guard let macLayout = macLayoutName(fromPortable: layoutName) else { continue }
                keySpacingByLayout[macLayout] = LayoutKeySpacingDefaults.normalized(value)
            }
        }
        if let activeSpacing = settings.keyPaddingPercent {
            keySpacingByLayout[resolvedLayout] = LayoutKeySpacingDefaults.normalized(activeSpacing)
        }

        var columnSettingsByLayout = currentProfile.columnSettingsByLayout
        if let importedColumnsByLayout = settings.columnSettingsByLayout {
            for (layoutName, values) in importedColumnsByLayout {
                guard let macLayout = macLayoutName(fromPortable: layoutName) else { continue }
                columnSettingsByLayout[macLayout] = values
            }
        }
        if let activeColumns = settings.columnSettings {
            columnSettingsByLayout[resolvedLayout] = activeColumns
        }

        profile = AppKeymapProfile(
            leftDeviceID: currentProfile.leftDeviceID,
            rightDeviceID: currentProfile.rightDeviceID,
            layoutPreset: resolvedLayout,
            activeLayer: activeLayer,
            autoResyncMissingTrackpads: currentProfile.autoResyncMissingTrackpads,
            runAtStartupEnabled: currentProfile.runAtStartupEnabled,
            tapHoldDurationMs: settings.holdDurationMs ?? currentProfile.tapHoldDurationMs,
            dragCancelDistance: settings.dragCancelMm ?? currentProfile.dragCancelDistance,
            forceClickMin: Double(settings.forceMin ?? Int(currentProfile.forceClickMin ?? GlassToKeySettings.forceClickMin)),
            forceClickCap: Double(settings.forceCap ?? Int(currentProfile.forceClickCap)),
            hapticStrength: currentProfile.hapticStrength,
            typingGraceMs: settings.typingGraceMs ?? currentProfile.typingGraceMs,
            intentMoveThresholdMm: settings.intentMoveMm ?? currentProfile.intentMoveThresholdMm,
            intentVelocityThresholdMmPerSec: settings.intentVelocityMmPerSec ?? currentProfile.intentVelocityThresholdMmPerSec,
            autocorrectEnabled: settings.autocorrectEnabled ?? currentProfile.autocorrectEnabled,
            tapClickCadenceMs: currentProfile.tapClickCadenceMs,
            snapRadiusPercent: settings.snapRadiusPercent ?? currentProfile.snapRadiusPercent,
            chordalShiftEnabled: settings.chordShiftEnabled ?? currentProfile.chordalShiftEnabled,
            keyboardModeEnabled: settings.keyboardModeEnabled ?? currentProfile.keyboardModeEnabled,
            twoFingerTapGestureAction: currentProfile.twoFingerTapGestureAction,
            threeFingerTapGestureAction: settings.threeFingerClickAction ?? currentProfile.threeFingerTapGestureAction,
            twoFingerHoldGestureAction: settings.twoFingerHoldAction ?? currentProfile.twoFingerHoldGestureAction,
            threeFingerHoldGestureAction: settings.threeFingerHoldAction ?? currentProfile.threeFingerHoldGestureAction,
            fourFingerHoldGestureAction: settings.fourFingerHoldAction ?? currentProfile.fourFingerHoldGestureAction,
            outerCornersHoldGestureAction: settings.outerCornersAction ?? currentProfile.outerCornersHoldGestureAction,
            innerCornersHoldGestureAction: settings.innerCornersAction ?? currentProfile.innerCornersHoldGestureAction,
            fiveFingerSwipeLeftGestureAction: settings.fiveFingerSwipeLeftAction ?? currentProfile.fiveFingerSwipeLeftGestureAction,
            fiveFingerSwipeRightGestureAction: settings.fiveFingerSwipeRightAction ?? currentProfile.fiveFingerSwipeRightGestureAction,
            keySpacingPercentByLayout: keySpacingByLayout,
            columnSettingsByLayout: columnSettingsByLayout,
            customButtonsByLayout: currentProfile.customButtonsByLayout,
            keyMappingsByLayout: currentProfile.keyMappingsByLayout,
            keyGeometryByLayout: currentProfile.keyGeometryByLayout
        )

        if let hostExtension = bundle.hostExtensions?["mac"] {
            profile = AppKeymapProfile(
                leftDeviceID: hostExtension.leftDeviceID ?? profile.leftDeviceID,
                rightDeviceID: hostExtension.rightDeviceID ?? profile.rightDeviceID,
                layoutPreset: profile.layoutPreset,
                activeLayer: profile.activeLayer,
                autoResyncMissingTrackpads: hostExtension.autoResyncMissingTrackpads ?? profile.autoResyncMissingTrackpads,
                runAtStartupEnabled: hostExtension.runAtStartupEnabled ?? profile.runAtStartupEnabled,
                tapHoldDurationMs: profile.tapHoldDurationMs,
                dragCancelDistance: profile.dragCancelDistance,
                forceClickMin: profile.forceClickMin,
                forceClickCap: profile.forceClickCap,
                hapticStrength: hostExtension.hapticStrength ?? profile.hapticStrength,
                typingGraceMs: profile.typingGraceMs,
                intentMoveThresholdMm: profile.intentMoveThresholdMm,
                intentVelocityThresholdMmPerSec: profile.intentVelocityThresholdMmPerSec,
                autocorrectEnabled: profile.autocorrectEnabled,
                tapClickCadenceMs: hostExtension.tapClickCadenceMs ?? profile.tapClickCadenceMs,
                snapRadiusPercent: profile.snapRadiusPercent,
                chordalShiftEnabled: profile.chordalShiftEnabled,
                keyboardModeEnabled: profile.keyboardModeEnabled,
                twoFingerTapGestureAction: hostExtension.twoFingerTapGestureAction ?? profile.twoFingerTapGestureAction,
                threeFingerTapGestureAction: hostExtension.threeFingerTapGestureAction ?? profile.threeFingerTapGestureAction,
                twoFingerHoldGestureAction: profile.twoFingerHoldGestureAction,
                threeFingerHoldGestureAction: profile.threeFingerHoldGestureAction,
                fourFingerHoldGestureAction: profile.fourFingerHoldGestureAction,
                outerCornersHoldGestureAction: profile.outerCornersHoldGestureAction,
                innerCornersHoldGestureAction: profile.innerCornersHoldGestureAction,
                fiveFingerSwipeLeftGestureAction: profile.fiveFingerSwipeLeftGestureAction,
                fiveFingerSwipeRightGestureAction: profile.fiveFingerSwipeRightGestureAction,
                keySpacingPercentByLayout: profile.keySpacingPercentByLayout,
                columnSettingsByLayout: profile.columnSettingsByLayout,
                customButtonsByLayout: profile.customButtonsByLayout,
                keyMappingsByLayout: profile.keyMappingsByLayout,
                keyGeometryByLayout: profile.keyGeometryByLayout
            )
        }

        return try applyPortableKeymap(keymap, to: profile)
    }

    private static func applyPortableKeymap(
        _ keymap: PortableKeymapStore,
        to profile: AppKeymapProfile
    ) throws -> AppKeymapProfile {
        guard keymap.layouts != nil else {
            throw PortableKeymapImportError.invalidKeymap
        }

        var unsupportedLabels = Set<String>()
        var mappingsByLayout = KeyActionMappingStore.emptyLayoutMappings()
        var customButtonsByLayout: [String: [Int: [CustomButton]]] = [:]
        var geometryByLayout = KeyGeometryStore.emptyLayoutOverrides()

        for (portableLayoutName, layoutData) in keymap.layouts ?? [:] {
            guard let macLayoutName = macLayoutName(fromPortable: portableLayoutName) else { continue }

            var mappedLayers = KeyActionMappingStore.emptyMappings()
            for (layer, mappings) in layoutData.mappings ?? [:] {
                let clampedLayer = KeyLayerConfig.clamped(layer)
                var output: [String: KeyMapping] = [:]
                for (storageKey, portableMapping) in mappings {
                    guard GridKeyPosition.from(storageKey: storageKey) != nil else { continue }
                    let primary = resolveImportedAction(
                        portableMapping.primary?.label,
                        unsupportedLabels: &unsupportedLabels
                    ) ?? KeyActionCatalog.noneAction
                    let hold = resolveImportedAction(
                        portableMapping.hold?.label,
                        unsupportedLabels: &unsupportedLabels,
                        allowNil: true
                    )
                    output[storageKey] = KeyMapping(primary: primary, hold: hold)
                }
                mappedLayers[clampedLayer] = output
            }
            mappingsByLayout[macLayoutName] = KeyActionMappingStore.normalized(mappedLayers)

            var buttonsByLayer: [Int: [CustomButton]] = [:]
            for (layer, buttons) in layoutData.customButtons ?? [:] {
                let clampedLayer = KeyLayerConfig.clamped(layer)
                let converted = buttons.compactMap { portableButton -> CustomButton? in
                    let primary = resolveImportedAction(
                        portableButton.primary?.label,
                        unsupportedLabels: &unsupportedLabels
                    ) ?? KeyActionCatalog.noneAction
                    let hold = resolveImportedAction(
                        portableButton.hold?.label,
                        unsupportedLabels: &unsupportedLabels,
                        allowNil: true
                    )
                    guard let side = portableButton.trackpadSide else { return nil }
                    let rect = portableButton.rect.normalizedRect.clamped(
                        minWidth: minCustomButtonSize.width,
                        minHeight: minCustomButtonSize.height
                    )
                    return CustomButton(
                        id: portableButton.uuid,
                        side: side,
                        rect: rect,
                        action: primary,
                        hold: hold,
                        layer: clampedLayer
                    )
                }
                buttonsByLayer[clampedLayer] = converted
            }
            customButtonsByLayout[macLayoutName] = buttonsByLayer

            var geometry: KeyGeometryOverrides = [:]
            for (storageKey, portableGeometry) in layoutData.keyGeometry ?? [:] {
                guard GridKeyPosition.from(storageKey: storageKey) != nil else { continue }
                geometry[storageKey] = KeyGeometryOverride(
                    rotationDegrees: portableGeometry.rotationDegrees ?? 0.0,
                    widthScale: portableGeometry.widthScale ?? 1.0,
                    heightScale: portableGeometry.heightScale ?? 1.0
                )
            }
            geometryByLayout[macLayoutName] = geometry
        }

        guard unsupportedLabels.isEmpty else {
            throw PortableKeymapImportError.unsupportedActions(Array(unsupportedLabels))
        }

        return AppKeymapProfile(
            leftDeviceID: profile.leftDeviceID,
            rightDeviceID: profile.rightDeviceID,
            layoutPreset: profile.layoutPreset,
            activeLayer: profile.activeLayer,
            autoResyncMissingTrackpads: profile.autoResyncMissingTrackpads,
            runAtStartupEnabled: profile.runAtStartupEnabled,
            tapHoldDurationMs: profile.tapHoldDurationMs,
            dragCancelDistance: profile.dragCancelDistance,
            forceClickMin: profile.forceClickMin,
            forceClickCap: profile.forceClickCap,
            hapticStrength: profile.hapticStrength,
            typingGraceMs: profile.typingGraceMs,
            intentMoveThresholdMm: profile.intentMoveThresholdMm,
            intentVelocityThresholdMmPerSec: profile.intentVelocityThresholdMmPerSec,
            autocorrectEnabled: profile.autocorrectEnabled,
            tapClickCadenceMs: profile.tapClickCadenceMs,
            snapRadiusPercent: profile.snapRadiusPercent,
            chordalShiftEnabled: profile.chordalShiftEnabled,
            keyboardModeEnabled: profile.keyboardModeEnabled,
            twoFingerTapGestureAction: profile.twoFingerTapGestureAction,
            threeFingerTapGestureAction: profile.threeFingerTapGestureAction,
            twoFingerHoldGestureAction: profile.twoFingerHoldGestureAction,
            threeFingerHoldGestureAction: profile.threeFingerHoldGestureAction,
            fourFingerHoldGestureAction: profile.fourFingerHoldGestureAction,
            outerCornersHoldGestureAction: profile.outerCornersHoldGestureAction,
            innerCornersHoldGestureAction: profile.innerCornersHoldGestureAction,
            fiveFingerSwipeLeftGestureAction: profile.fiveFingerSwipeLeftGestureAction,
            fiveFingerSwipeRightGestureAction: profile.fiveFingerSwipeRightGestureAction,
            keySpacingPercentByLayout: profile.keySpacingPercentByLayout,
            columnSettingsByLayout: profile.columnSettingsByLayout,
            customButtonsByLayout: customButtonsByLayout,
            keyMappingsByLayout: mappingsByLayout,
            keyGeometryByLayout: geometryByLayout
        )
    }

    private static func encodePortableKeymap(from profile: AppKeymapProfile) throws -> String {
        var layouts: [String: PortableLayoutKeymapData] = [:]
        let mappingsByLayout = KeyActionMappingStore.normalized(
            profile.keyMappingsByLayout ?? KeyActionMappingStore.emptyLayoutMappings()
        )
        let geometryByLayout = KeyGeometryStore.normalized(
            profile.keyGeometryByLayout ?? KeyGeometryStore.emptyLayoutOverrides()
        )

        for preset in TrackpadLayoutPreset.allCases {
            let macLayoutName = preset.rawValue
            let portableLayoutName = portableLayoutName(fromMac: macLayoutName)
            let layerMappings = mappingsByLayout[macLayoutName] ?? KeyActionMappingStore.emptyMappings()
            let portableMappings = layerMappings.reduce(into: [Int: [String: PortableKeyMapping]]()) { result, entry in
                result[entry.key] = entry.value.reduce(into: [:]) { mappingResult, pair in
                    mappingResult[pair.key] = PortableKeyMapping(
                        primary: PortableKeyAction(label: portableLabel(for: pair.value.primary)),
                        hold: pair.value.hold.map { PortableKeyAction(label: portableLabel(for: $0)) }
                    )
                }
            }

            let layeredButtons = profile.customButtonsByLayout[macLayoutName] ?? [:]
            let portableButtons = layeredButtons.reduce(into: [Int: [PortableCustomButton]]()) { result, entry in
                result[entry.key] = entry.value.map { button in
                    PortableCustomButton(
                        id: button.id.uuidString,
                        side: button.side,
                        rect: PortableNormalizedRect(normalizedRect: button.rect),
                        primary: PortableKeyAction(label: portableLabel(for: button.action)),
                        hold: button.hold.map { PortableKeyAction(label: portableLabel(for: $0)) },
                        layer: entry.key
                    )
                }
            }

            let portableGeometry = (geometryByLayout[macLayoutName] ?? [:]).reduce(into: [String: PortableKeyGeometryOverride]()) { result, entry in
                result[entry.key] = PortableKeyGeometryOverride(
                    rotationDegrees: entry.value.rotationDegrees,
                    widthScale: entry.value.widthScale,
                    heightScale: entry.value.heightScale
                )
            }

            layouts[portableLayoutName] = PortableLayoutKeymapData(
                mappings: portableMappings,
                customButtons: portableButtons,
                keyGeometry: portableGeometry
            )
        }

        let encoder = JSONEncoder()
        let data = try encoder.encode(PortableKeymapStore(version: keymapVersion, layouts: layouts))
        guard let json = String(data: data, encoding: .utf8) else {
            throw PortableKeymapImportError.invalidKeymap
        }
        return json
    }

    private static func resolveImportedAction(
        _ label: String?,
        unsupportedLabels: inout Set<String>,
        allowNil: Bool = false
    ) -> KeyAction? {
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return allowNil ? nil : KeyActionCatalog.noneAction
        }
        if let action = KeyActionCatalog.action(for: trimmed) {
            return action
        }
        unsupportedLabels.insert(trimmed)
        return allowNil ? nil : KeyActionCatalog.noneAction
    }

    private static func portableLayoutName(fromMac name: String) -> String {
        switch name {
        case TrackpadLayoutPreset.none.rawValue:
            return "Blank"
        case TrackpadLayoutPreset.mobileOrtho12x4.rawValue:
            return "mobile-ortho-12x4"
        default:
            return name
        }
    }

    private static func macLayoutName(fromPortable name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        let normalized = trimmed.lowercased()
        switch normalized {
        case "blank":
            return TrackpadLayoutPreset.none.rawValue
        case "mobile-ortho-12x4":
            return TrackpadLayoutPreset.mobileOrtho12x4.rawValue
        default:
            return TrackpadLayoutPreset(rawValue: trimmed)?.rawValue
        }
    }

    private static func portableLabel(for action: KeyAction) -> String {
        if let shortcut = ShortcutActionHelper.parse(action.label) {
            return portableShortcutLabel(for: shortcut)
        }

        switch action.label {
        case "Option":
            return "Alt"
        case KeyActionCatalog.altGrLabel:
            return "AltGr"
        case "Cmd":
            return "Win"
        case "Back":
            return "Backspace"
        case "Ret":
            return "Enter"
        case "Emoji":
            return "EMOJI"
        case KeyActionCatalog.voiceLabel:
            return "VOICE"
        case KeyActionCatalog.volumeUpLabel:
            return "VOL_UP"
        case KeyActionCatalog.volumeDownLabel:
            return "VOL_DOWN"
        case KeyActionCatalog.brightnessUpLabel:
            return "BRIGHT_UP"
        case KeyActionCatalog.brightnessDownLabel:
            return "BRIGHT_DOWN"
        default:
            return action.label
        }
    }

    private static func portableShortcutLabel(for shortcut: ShortcutActionSpec) -> String {
        let parts = ShortcutModifier.ordered.compactMap { modifier -> String? in
            guard let variant = shortcut.modifiers[modifier] else { return nil }
            switch modifier {
            case .control:
                switch variant {
                case .generic: return "Ctrl"
                case .left: return "LeftCtrl"
                case .right: return "RightCtrl"
                }
            case .shift:
                switch variant {
                case .generic: return "Shift"
                case .left: return "LeftShift"
                case .right: return "RightShift"
                }
            case .option:
                switch variant {
                case .generic: return "Alt"
                case .left: return "LeftAlt"
                case .right: return "AltGr"
                }
            case .command:
                switch variant {
                case .generic: return "Win"
                case .left: return "LeftWin"
                case .right: return "RightWin"
                }
            }
        }
        return (parts + [portableKeyLabel(for: shortcut.keyLabel)]).joined(separator: "+")
    }

    private static func portableKeyLabel(for label: String) -> String {
        switch label {
        case "Backspace", "Back":
            return "Backspace"
        case "Enter", "Ret":
            return "Enter"
        case "Esc", "Escape":
            return "Esc"
        default:
            return label
        }
    }

    private struct PortableProfileBundle: Codable {
        var version: Int
        var settings: PortableSettings?
        var keymapJson: String?
        var hostExtensions: [String: MacHostProfileExtension]?

        private enum CodingKeys: String, CodingKey {
            case version = "Version"
            case settings = "Settings"
            case keymapJson = "KeymapJson"
            case hostExtensions = "HostExtensions"
        }
    }

    private struct MacHostProfileExtension: Codable {
        var leftDeviceID: String?
        var rightDeviceID: String?
        var autoResyncMissingTrackpads: Bool?
        var runAtStartupEnabled: Bool?
        var twoFingerTapGestureAction: String?
        var threeFingerTapGestureAction: String?
        var tapClickCadenceMs: Double?
        var hapticStrength: Double?

        init(profile: AppKeymapProfile) {
            leftDeviceID = profile.leftDeviceID
            rightDeviceID = profile.rightDeviceID
            autoResyncMissingTrackpads = profile.autoResyncMissingTrackpads
            runAtStartupEnabled = profile.runAtStartupEnabled
            twoFingerTapGestureAction = profile.twoFingerTapGestureAction
            threeFingerTapGestureAction = profile.threeFingerTapGestureAction
            tapClickCadenceMs = profile.tapClickCadenceMs
            hapticStrength = profile.hapticStrength
        }

        private enum CodingKeys: String, CodingKey {
            case leftDeviceID = "LeftDeviceID"
            case rightDeviceID = "RightDeviceID"
            case autoResyncMissingTrackpads = "AutoResyncMissingTrackpads"
            case runAtStartupEnabled = "RunAtStartupEnabled"
            case twoFingerTapGestureAction = "TwoFingerTapGestureAction"
            case threeFingerTapGestureAction = "ThreeFingerTapGestureAction"
            case tapClickCadenceMs = "TapClickCadenceMs"
            case hapticStrength = "HapticStrength"
        }
    }

    private struct PortableSettings: Codable {
        var activeLayer: Int?
        var layoutPresetName: String?
        var keyboardModeEnabled: Bool?
        var autocorrectEnabled: Bool?
        var chordShiftEnabled: Bool?
        var fiveFingerSwipeLeftAction: String?
        var fiveFingerSwipeRightAction: String?
        var twoFingerHoldAction: String?
        var threeFingerHoldAction: String?
        var fourFingerHoldAction: String?
        var threeFingerClickAction: String?
        var outerCornersAction: String?
        var innerCornersAction: String?
        var holdDurationMs: Double?
        var dragCancelMm: Double?
        var typingGraceMs: Double?
        var intentMoveMm: Double?
        var intentVelocityMmPerSec: Double?
        var snapRadiusPercent: Double?
        var keyPaddingPercent: Double?
        var keyPaddingPercentByLayout: [String: Double]?
        var forceMin: Int?
        var forceCap: Int?
        var columnSettingsByLayout: [String: [ColumnLayoutSettings]]?
        var columnSettings: [ColumnLayoutSettings]?

        init(profile: AppKeymapProfile) {
            activeLayer = KeyLayerConfig.clamped(profile.activeLayer ?? KeyLayerConfig.baseLayer)
            let resolvedLayout = TrackpadLayoutPreset(rawValue: profile.layoutPreset) ?? .sixByThree
            layoutPresetName = portableLayoutName(fromMac: profile.layoutPreset)
            keyboardModeEnabled = profile.keyboardModeEnabled
            autocorrectEnabled = profile.autocorrectEnabled
            chordShiftEnabled = profile.chordalShiftEnabled
            fiveFingerSwipeLeftAction = profile.fiveFingerSwipeLeftGestureAction
            fiveFingerSwipeRightAction = profile.fiveFingerSwipeRightGestureAction
            twoFingerHoldAction = profile.twoFingerHoldGestureAction
            threeFingerHoldAction = profile.threeFingerHoldGestureAction
            fourFingerHoldAction = profile.fourFingerHoldGestureAction
            threeFingerClickAction = profile.threeFingerTapGestureAction
            outerCornersAction = profile.outerCornersHoldGestureAction
            innerCornersAction = profile.innerCornersHoldGestureAction
            holdDurationMs = profile.tapHoldDurationMs
            dragCancelMm = profile.dragCancelDistance
            typingGraceMs = profile.typingGraceMs
            intentMoveMm = profile.intentMoveThresholdMm
            intentVelocityMmPerSec = profile.intentVelocityThresholdMmPerSec
            snapRadiusPercent = profile.snapRadiusPercent
            keyPaddingPercent = profile.keySpacingPercentByLayout?[resolvedLayout.rawValue]
            keyPaddingPercentByLayout = profile.keySpacingPercentByLayout?.reduce(into: [:]) { result, entry in
                result[portableLayoutName(fromMac: entry.key)] = entry.value
            }
            forceMin = Int(profile.forceClickMin ?? GlassToKeySettings.forceClickMin)
            forceCap = Int(profile.forceClickCap)
            columnSettingsByLayout = profile.columnSettingsByLayout.reduce(into: [:]) { result, entry in
                result[portableLayoutName(fromMac: entry.key)] = entry.value
            }
            columnSettings = profile.columnSettingsByLayout[resolvedLayout.rawValue]
        }

        private enum CodingKeys: String, CodingKey {
            case activeLayer = "ActiveLayer"
            case layoutPresetName = "LayoutPresetName"
            case keyboardModeEnabled = "KeyboardModeEnabled"
            case autocorrectEnabled = "AutocorrectEnabled"
            case chordShiftEnabled = "ChordShiftEnabled"
            case fiveFingerSwipeLeftAction = "FiveFingerSwipeLeftAction"
            case fiveFingerSwipeRightAction = "FiveFingerSwipeRightAction"
            case twoFingerHoldAction = "TwoFingerHoldAction"
            case threeFingerHoldAction = "ThreeFingerHoldAction"
            case fourFingerHoldAction = "FourFingerHoldAction"
            case threeFingerClickAction = "ThreeFingerClickAction"
            case outerCornersAction = "OuterCornersAction"
            case innerCornersAction = "InnerCornersAction"
            case holdDurationMs = "HoldDurationMs"
            case dragCancelMm = "DragCancelMm"
            case typingGraceMs = "TypingGraceMs"
            case intentMoveMm = "IntentMoveMm"
            case intentVelocityMmPerSec = "IntentVelocityMmPerSec"
            case snapRadiusPercent = "SnapRadiusPercent"
            case keyPaddingPercent = "KeyPaddingPercent"
            case keyPaddingPercentByLayout = "KeyPaddingPercentByLayout"
            case forceMin = "ForceMin"
            case forceCap = "ForceCap"
            case columnSettingsByLayout = "ColumnSettingsByLayout"
            case columnSettings = "ColumnSettings"
        }
    }

    private struct PortableKeymapStore: Codable {
        var version: Int?
        var layouts: [String: PortableLayoutKeymapData]?

        private enum CodingKeys: String, CodingKey {
            case version = "Version"
            case layouts = "Layouts"
        }
    }

    private struct PortableLayoutKeymapData: Codable {
        var mappings: [Int: [String: PortableKeyMapping]]?
        var customButtons: [Int: [PortableCustomButton]]?
        var keyGeometry: [String: PortableKeyGeometryOverride]?

        private enum CodingKeys: String, CodingKey {
            case mappings = "Mappings"
            case customButtons = "CustomButtons"
            case keyGeometry = "KeyGeometry"
        }
    }

    private struct PortableKeyMapping: Codable {
        var primary: PortableKeyAction?
        var hold: PortableKeyAction?

        private enum CodingKeys: String, CodingKey {
            case primary = "Primary"
            case hold = "Hold"
        }
    }

    private struct PortableKeyAction: Codable {
        var label: String

        private enum CodingKeys: String, CodingKey {
            case label = "Label"
        }
    }

    private struct PortableCustomButton: Codable {
        var id: String
        var side: PortableTrackpadSideValue
        var rect: PortableNormalizedRect
        var primary: PortableKeyAction?
        var hold: PortableKeyAction?
        var layer: Int?

        var uuid: UUID {
            UUID(uuidString: id) ?? UUID()
        }

        var trackpadSide: TrackpadSide? {
            side.trackpadSide
        }

        private enum CodingKeys: String, CodingKey {
            case id = "Id"
            case side = "Side"
            case rect = "Rect"
            case primary = "Primary"
            case hold = "Hold"
            case layer = "Layer"
        }

        init(
            id: String,
            side: TrackpadSide,
            rect: PortableNormalizedRect,
            primary: PortableKeyAction,
            hold: PortableKeyAction?,
            layer: Int
        ) {
            self.id = id
            self.side = PortableTrackpadSideValue.trackpadSide(side)
            self.rect = rect
            self.primary = primary
            self.hold = hold
            self.layer = layer
        }
    }

    private enum PortableTrackpadSideValue: Codable {
        case int(Int)
        case string(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let intValue = try? container.decode(Int.self) {
                self = .int(intValue)
                return
            }
            self = .string(try container.decode(String.self))
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .int(let value):
                try container.encode(value)
            case .string(let value):
                try container.encode(value)
            }
        }

        var trackpadSide: TrackpadSide? {
            switch self {
            case .int(let value):
                switch value {
                case 0:
                    return .left
                case 1:
                    return .right
                default:
                    return nil
                }
            case .string(let value):
                return TrackpadSide(rawValue: value.lowercased())
            }
        }

        static func trackpadSide(_ side: TrackpadSide) -> PortableTrackpadSideValue {
            switch side {
            case .left:
                return .int(0)
            case .right:
                return .int(1)
            }
        }
    }

    private struct PortableNormalizedRect: Codable {
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat
        var rotationDegrees: Double?

        init(normalizedRect: NormalizedRect) {
            x = normalizedRect.x
            y = normalizedRect.y
            width = normalizedRect.width
            height = normalizedRect.height
            rotationDegrees = abs(normalizedRect.rotationDegrees) > 0.000_01
                ? normalizedRect.rotationDegrees
                : nil
        }

        var normalizedRect: NormalizedRect {
            NormalizedRect(
                x: x,
                y: y,
                width: width,
                height: height,
                rotationDegrees: rotationDegrees ?? 0.0
            )
        }

        private enum CodingKeys: String, CodingKey {
            case x = "X"
            case y = "Y"
            case width = "Width"
            case height = "Height"
            case rotationDegrees = "RotationDegrees"
        }
    }

    private struct PortableKeyGeometryOverride: Codable {
        var rotationDegrees: Double?
        var widthScale: Double?
        var heightScale: Double?

        private enum CodingKeys: String, CodingKey {
            case rotationDegrees = "RotationDegrees"
            case widthScale = "WidthScale"
            case heightScale = "HeightScale"
        }
    }
}
