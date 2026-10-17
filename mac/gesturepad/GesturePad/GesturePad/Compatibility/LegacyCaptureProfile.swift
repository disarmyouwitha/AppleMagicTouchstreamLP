// Legacy capture/profile data types only; never interpret these as output actions.
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

enum LegacyProfileDefaults {
    static let tapHoldDurationMs: Double = 220.0
    static let dragCancelDistanceMm: Double = 8.0
    static let forceClickMin: Double = 0.0
    static let forceClickCap: Double = 120.0
    static let forceClickThreshold: Double = 250.0
    static let hapticStrengthPercent: Double = 40.0
    static let typingGraceMs: Double = 1000.0
    static let intentMoveThresholdMm: Double = 3.0
    static let intentVelocityThresholdMmPerSec: Double = 50.0
    static let autocorrectEnabled: Bool = true
    static let autocorrectMinWordLength: Int = 2
    static let tapClickCadenceMs: Double = 280.0
    static let snapRadiusPercent: Double = 35.0
    static let keyboardModeEnabled: Bool = false
    static let holdRepeatEnabled: Bool = false
    static let runAtStartupEnabled: Bool = false
    static let twoFingerTapGestureActionLabel = KeyActionCatalog.leftClickLabel
    static let threeFingerTapGestureActionLabel = KeyActionCatalog.rightClickLabel
    static let twoFingerHoldGestureActionLabel = KeyActionCatalog.noneLabel
    static let threeFingerHoldGestureActionLabel = KeyActionCatalog.noneLabel
    static let fourFingerHoldGestureActionLabel = "Shift"
    static let outerCornersHoldGestureActionLabel = KeyActionCatalog.voiceLabel
    static let innerCornersHoldGestureActionLabel = KeyActionCatalog.noneLabel
    static let leftEdgeUpGestureActionLabel = KeyActionCatalog.noneLabel
    static let leftEdgeDownGestureActionLabel = KeyActionCatalog.noneLabel
    static let rightEdgeUpGestureActionLabel = KeyActionCatalog.noneLabel
    static let rightEdgeDownGestureActionLabel = KeyActionCatalog.noneLabel
    static let topEdgeLeftGestureActionLabel = KeyActionCatalog.noneLabel
    static let topEdgeRightGestureActionLabel = KeyActionCatalog.noneLabel
    static let bottomEdgeLeftGestureActionLabel = KeyActionCatalog.noneLabel
    static let bottomEdgeRightGestureActionLabel = KeyActionCatalog.noneLabel
    static let threeFingerSwipeLeftGestureActionLabel = KeyActionCatalog.noneLabel
    static let threeFingerSwipeRightGestureActionLabel = KeyActionCatalog.noneLabel
    static let threeFingerSwipeUpGestureActionLabel = KeyActionCatalog.noneLabel
    static let threeFingerSwipeDownGestureActionLabel = KeyActionCatalog.noneLabel
    static let fourFingerSwipeLeftGestureActionLabel = KeyActionCatalog.noneLabel
    static let fourFingerSwipeRightGestureActionLabel = KeyActionCatalog.noneLabel
    static let fourFingerSwipeUpGestureActionLabel = KeyActionCatalog.noneLabel
    static let fourFingerSwipeDownGestureActionLabel = KeyActionCatalog.noneLabel
    static let fiveFingerSwipeLeftGestureActionLabel = KeyActionCatalog.typingToggleLabel
    static let fiveFingerSwipeRightGestureActionLabel = KeyActionCatalog.typingToggleLabel
    static let fiveFingerSwipeUpGestureActionLabel = KeyActionCatalog.noneLabel
    static let fiveFingerSwipeDownGestureActionLabel = KeyActionCatalog.noneLabel
    static let topLeftCornerSwipeGestureActionLabel = KeyActionCatalog.noneLabel
    static let topRightCornerSwipeGestureActionLabel = KeyActionCatalog.noneLabel
    static let bottomLeftCornerSwipeGestureActionLabel = KeyActionCatalog.noneLabel
    static let bottomRightCornerSwipeGestureActionLabel = KeyActionCatalog.noneLabel
    static let topLeftTriangleGestureActionLabel = KeyActionCatalog.noneLabel
    static let topRightTriangleGestureActionLabel = KeyActionCatalog.noneLabel
    static let bottomLeftTriangleGestureActionLabel = KeyActionCatalog.noneLabel
    static let bottomRightTriangleGestureActionLabel = KeyActionCatalog.noneLabel
    static let upperLeftCornerClickGestureActionLabel = KeyActionCatalog.noneLabel
    static let upperRightCornerClickGestureActionLabel = KeyActionCatalog.noneLabel
    static let lowerLeftCornerClickGestureActionLabel = KeyActionCatalog.noneLabel
    static let lowerRightCornerClickGestureActionLabel = KeyActionCatalog.noneLabel
    static let threeFingerClickGestureActionLabel = KeyActionCatalog.noneLabel
    static let fourFingerClickGestureActionLabel = KeyActionCatalog.noneLabel
    static let topLeftForceClickGestureActionLabel = KeyActionCatalog.noneLabel
    static let topRightForceClickGestureActionLabel = KeyActionCatalog.noneLabel
    static let bottomLeftForceClickGestureActionLabel = KeyActionCatalog.noneLabel
    static let bottomRightForceClickGestureActionLabel = KeyActionCatalog.noneLabel

    static func persistedDouble(
        forKey key: String,
        defaults: UserDefaults = .standard,
        fallback: Double
    ) -> Double {
        if let value = defaults.object(forKey: key) as? Double {
            return value
        }
        return fallback
    }
}

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
        case "left ctrl", "left control", "lctrl", "lcontrol", "l ctl":
            return (.control, .left)
        case "right ctrl", "right control", "rctrl", "rcontrol", "r ctl":
            return (.control, .right)
        case "shift":
            return (.shift, .generic)
        case "left shift", "lshift", "l shift":
            return (.shift, .left)
        case "right shift", "rshift", "r shift":
            return (.shift, .right)
        case "option", "alt":
            return (.option, .generic)
        case "left option", "left alt", "lalt", "loption", "l option":
            return (.option, .left)
        case "right option", "right-option", "rightoption", "roption", "ralt", "altgr", "alt gr", "r option":
            return (.option, .right)
        case "cmd", "command", "meta", "super", "win":
            return (.command, .generic)
        case "left cmd", "left command", "left meta", "left super", "left win",
             "lcmd", "lwin", "lmeta", "lsuper", "l cmd":
            return (.command, .left)
        case "right cmd", "right command", "right meta", "right super", "right win",
             "rcmd", "rwin", "rmeta", "rsuper", "r cmd":
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

enum ShortcutActionLibraryStorage {
    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()

    static func normalized(_ actions: [String]?) -> [String] {
        guard let actions else { return [] }

        var normalized: [String] = []
        var seen = Set<String>()

        for actionLabel in actions {
            guard let action = KeyActionCatalog.action(for: actionLabel),
                  action.kind != .none else {
                continue
            }

            let canonicalLabel = action.label
            let dedupeKey = canonicalLabel.lowercased()
            guard seen.insert(dedupeKey).inserted else { continue }
            normalized.append(canonicalLabel)
        }

        return normalized
    }

    static func decode(from data: Data) -> [String]? {
        guard !data.isEmpty else { return [] }
        guard let decoded = try? decoder.decode([String].self, from: data) else {
            return nil
        }
        return normalized(decoded)
    }

    static func encode(_ actions: [String]?) -> Data? {
        try? encoder.encode(normalized(actions))
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
                if KeyActionCatalog.isScreenshotShortcutLabel(label) {
                    return KeyActionCatalog.screenshotLabel
                }
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
                if KeyActionCatalog.isScreenshotShortcutLabel(label) {
                    return KeyActionCatalog.screenshotLabel
                }
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
        if kind == .chordalShift || KeyActionCatalog.isChordalShiftAlias(label) {
            if let normalized = KeyActionCatalog.action(for: KeyActionCatalog.chordalShiftLabel) {
                self = normalized
            }
        }
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

struct GestureActionSet {
    var twoFingerTap: KeyAction
    var threeFingerTap: KeyAction
    var twoFingerHold: KeyAction
    var threeFingerHold: KeyAction
    var fourFingerHold: KeyAction
    var outerCornersHold: KeyAction
    var innerCornersHold: KeyAction
    var leftEdgeUp: KeyAction
    var leftEdgeDown: KeyAction
    var rightEdgeUp: KeyAction
    var rightEdgeDown: KeyAction
    var topEdgeLeft: KeyAction
    var topEdgeRight: KeyAction
    var bottomEdgeLeft: KeyAction
    var bottomEdgeRight: KeyAction
    var threeFingerSwipeLeft: KeyAction
    var threeFingerSwipeRight: KeyAction
    var threeFingerSwipeUp: KeyAction
    var threeFingerSwipeDown: KeyAction
    var fourFingerSwipeLeft: KeyAction
    var fourFingerSwipeRight: KeyAction
    var fourFingerSwipeUp: KeyAction
    var fourFingerSwipeDown: KeyAction
    var fiveFingerSwipeLeft: KeyAction
    var fiveFingerSwipeRight: KeyAction
    var fiveFingerSwipeUp: KeyAction
    var fiveFingerSwipeDown: KeyAction
    var topLeftCornerSwipe: KeyAction
    var topRightCornerSwipe: KeyAction
    var bottomLeftCornerSwipe: KeyAction
    var bottomRightCornerSwipe: KeyAction
    var topLeftTriangle: KeyAction
    var topRightTriangle: KeyAction
    var bottomLeftTriangle: KeyAction
    var bottomRightTriangle: KeyAction
    var upperLeftCornerClick: KeyAction
    var upperRightCornerClick: KeyAction
    var lowerLeftCornerClick: KeyAction
    var lowerRightCornerClick: KeyAction
    var threeFingerClick: KeyAction
    var fourFingerClick: KeyAction
    var topLeftForceClick: KeyAction
    var topRightForceClick: KeyAction
    var bottomLeftForceClick: KeyAction
    var bottomRightForceClick: KeyAction
}

enum GestureBindingID {
    static let twoFingerTap = "two_finger_tap"
    static let threeFingerTap = "three_finger_tap"
    static let twoFingerHold = "two_finger_hold"
    static let threeFingerHold = "three_finger_hold"
    static let fourFingerHold = "four_finger_hold"
    static let outerCornersHold = "outer_corners"
    static let innerCornersHold = "inner_corners"
    static let leftEdgeUp = "left_edge_up"
    static let leftEdgeDown = "left_edge_down"
    static let rightEdgeUp = "right_edge_up"
    static let rightEdgeDown = "right_edge_down"
    static let topEdgeLeft = "top_edge_left"
    static let topEdgeRight = "top_edge_right"
    static let bottomEdgeLeft = "bottom_edge_left"
    static let bottomEdgeRight = "bottom_edge_right"
    static let threeFingerSwipeLeft = "three_finger_swipe_left"
    static let threeFingerSwipeRight = "three_finger_swipe_right"
    static let threeFingerSwipeUp = "three_finger_swipe_up"
    static let threeFingerSwipeDown = "three_finger_swipe_down"
    static let fourFingerSwipeLeft = "four_finger_swipe_left"
    static let fourFingerSwipeRight = "four_finger_swipe_right"
    static let fourFingerSwipeUp = "four_finger_swipe_up"
    static let fourFingerSwipeDown = "four_finger_swipe_down"
    static let fiveFingerSwipeLeft = "five_finger_swipe_left"
    static let fiveFingerSwipeRight = "five_finger_swipe_right"
    static let fiveFingerSwipeUp = "five_finger_swipe_up"
    static let fiveFingerSwipeDown = "five_finger_swipe_down"
    static let topLeftCornerSwipe = "top_left_corner_swipe"
    static let topRightCornerSwipe = "top_right_corner_swipe"
    static let bottomLeftCornerSwipe = "bottom_left_corner_swipe"
    static let bottomRightCornerSwipe = "bottom_right_corner_swipe"
    static let topLeftTriangle = "top_left_triangle"
    static let topRightTriangle = "top_right_triangle"
    static let bottomLeftTriangle = "bottom_left_triangle"
    static let bottomRightTriangle = "bottom_right_triangle"
    static let upperLeftCornerClick = "upper_left_corner_click"
    static let upperRightCornerClick = "upper_right_corner_click"
    static let lowerLeftCornerClick = "lower_left_corner_click"
    static let lowerRightCornerClick = "lower_right_corner_click"
    static let threeFingerClick = "three_finger_click"
    static let fourFingerClick = "four_finger_click"
    static let topLeftForceClick = "top_left_force_click"
    static let topRightForceClick = "top_right_force_click"
    static let bottomLeftForceClick = "bottom_left_force_click"
    static let bottomRightForceClick = "bottom_right_force_click"

    static let windowsRepeatCadenceBindingIDs: Set<String> = [
        threeFingerTap,
        twoFingerHold,
        threeFingerHold,
        fourFingerHold,
        outerCornersHold,
        innerCornersHold,
        leftEdgeUp,
        leftEdgeDown,
        rightEdgeUp,
        rightEdgeDown,
        topEdgeLeft,
        topEdgeRight,
        bottomEdgeLeft,
        bottomEdgeRight,
        threeFingerSwipeLeft,
        threeFingerSwipeRight,
        threeFingerSwipeUp,
        threeFingerSwipeDown,
        fourFingerSwipeLeft,
        fourFingerSwipeRight,
        fourFingerSwipeUp,
        fourFingerSwipeDown,
        fiveFingerSwipeLeft,
        fiveFingerSwipeRight,
        fiveFingerSwipeUp,
        fiveFingerSwipeDown,
        topLeftCornerSwipe,
        topRightCornerSwipe,
        bottomLeftCornerSwipe,
        bottomRightCornerSwipe,
        topLeftTriangle,
        topRightTriangle,
        bottomLeftTriangle,
        bottomRightTriangle,
        upperLeftCornerClick,
        upperRightCornerClick,
        lowerLeftCornerClick,
        lowerRightCornerClick,
        threeFingerClick,
        fourFingerClick,
        topLeftForceClick,
        topRightForceClick,
        bottomLeftForceClick,
        bottomRightForceClick
    ]
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
    var holdForceThreshold: Int

    private enum CodingKeys: String, CodingKey {
        case primary
        case hold
        case holdForceThreshold
    }

    init(
        primary: KeyAction,
        hold: KeyAction?,
        holdForceThreshold: Int = 0
    ) {
        self.primary = primary
        self.hold = hold
        self.holdForceThreshold = Self.normalizedHoldForceThreshold(holdForceThreshold)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primary = try container.decode(KeyAction.self, forKey: .primary)
        hold = try container.decodeIfPresent(KeyAction.self, forKey: .hold)
        let decodedThreshold = try container.decodeIfPresent(Int.self, forKey: .holdForceThreshold) ?? 0
        holdForceThreshold = hold == nil ? 0 : Self.normalizedHoldForceThreshold(decodedThreshold)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(primary, forKey: .primary)
        try container.encodeIfPresent(hold, forKey: .hold)
        if hold != nil {
            try container.encode(holdForceThreshold, forKey: .holdForceThreshold)
        }
    }

    static func normalizedHoldForceThreshold(_ value: Int) -> Int {
        min(max(value, 0), 255)
    }
}

struct CustomButton: Identifiable, Codable, Hashable {
    var id: UUID
    var side: TrackpadSide
    var rect: NormalizedRect
    var action: KeyAction
    var hold: KeyAction?
    var holdForceThreshold: Int
    var layer: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case side
        case rect
        case action
        case hold
        case holdForceThreshold
        case layer
    }

    init(
        id: UUID,
        side: TrackpadSide,
        rect: NormalizedRect,
        action: KeyAction,
        hold: KeyAction?,
        holdForceThreshold: Int = 0,
        layer: Int = 0
    ) {
        self.id = id
        self.side = side
        self.rect = rect
        self.action = action
        self.hold = hold
        self.holdForceThreshold = hold == nil ? 0 : KeyMapping.normalizedHoldForceThreshold(holdForceThreshold)
        self.layer = layer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        side = try container.decode(TrackpadSide.self, forKey: .side)
        rect = try container.decode(NormalizedRect.self, forKey: .rect)
        action = try container.decode(KeyAction.self, forKey: .action)
        hold = try container.decodeIfPresent(KeyAction.self, forKey: .hold)
        let decodedThreshold = try container.decodeIfPresent(Int.self, forKey: .holdForceThreshold) ?? 0
        holdForceThreshold = hold == nil ? 0 : KeyMapping.normalizedHoldForceThreshold(decodedThreshold)
        layer = try container.decodeIfPresent(Int.self, forKey: .layer) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(side, forKey: .side)
        try container.encode(rect, forKey: .rect)
        try container.encode(action, forKey: .action)
        try container.encodeIfPresent(hold, forKey: .hold)
        if hold != nil {
            try container.encode(holdForceThreshold, forKey: .holdForceThreshold)
        }
        try container.encode(layer, forKey: .layer)
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
    static let screenshotLabel = "Screenshot"
    static let screenshotShortcutLabel = "Shift+Cmd+4"
    static let noneLabel = "None"
    static let leftClickLabel = "Left Click"
    static let doubleClickLabel = "Double Click"
    static let rightClickLabel = "Right Click"
    static let middleClickLabel = "Middle Click"
    static let volumeUpLabel = "VOL_UP"
    static let volumeDownLabel = "VOL_DOWN"
    static let volumeUpSmallLabel = "VOL_UP_SMALL"
    static let volumeDownSmallLabel = "VOL_DOWN_SMALL"
    static let brightnessUpLabel = "BRIGHT_UP"
    static let brightnessDownLabel = "BRIGHT_DOWN"
    static let brightnessUpSmallLabel = "BRIGHT_UP_SMALL"
    static let brightnessDownSmallLabel = "BRIGHT_DOWN_SMALL"
    static let brightnessScriptUpLabel = "BRI_SCRIPT_UP"
    static let brightnessScriptDownLabel = "BRI_SCRIPT_DOWN"
    static let chordalShiftLabel = "Chordal Shift"
    static let gestureTwoFingerTapLabel = "2-finger tap"
    static let gestureThreeFingerTapLabel = "3-finger tap"
    static let gestureFourFingerHoldLabel = "4-finger hold"
    static let gestureInnerCornersHoldLabel = "Inner corners hold"
    static let gestureFiveFingerSwipeLeftLabel = "5-finger left"
    static let gestureFiveFingerSwipeRightLabel = "5-finger right"
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
        KeyAction(label: volumeUpSmallLabel, keyCode: 0, flags: 0, kind: .volumeUpSmall),
        KeyAction(label: volumeDownSmallLabel, keyCode: 0, flags: 0, kind: .volumeDownSmall),
        KeyAction(label: brightnessUpLabel, keyCode: 0, flags: 0, kind: .brightnessUp),
        KeyAction(label: brightnessDownLabel, keyCode: 0, flags: 0, kind: .brightnessDown),
        KeyAction(label: brightnessUpSmallLabel, keyCode: 0, flags: 0, kind: .brightnessUpSmall),
        KeyAction(label: brightnessDownSmallLabel, keyCode: 0, flags: 0, kind: .brightnessDownSmall),
        KeyAction(label: brightnessScriptUpLabel, keyCode: 0, flags: 0, kind: .brightnessUp),
        KeyAction(label: brightnessScriptDownLabel, keyCode: 0, flags: 0, kind: .brightnessDown)
    ]

    private static let modeActions: [KeyAction] = [
        KeyAction(label: typingToggleLabel, keyCode: 0, flags: 0, kind: .typingToggle)
    ]

    static func isScreenshotShortcutLabel(_ label: String) -> Bool {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(screenshotShortcutLabel) == .orderedSame
    }

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
                volumeUpLabel,
                volumeDownLabel,
                volumeUpSmallLabel,
                volumeDownSmallLabel,
                brightnessUpLabel,
                brightnessDownLabel,
                brightnessUpSmallLabel,
                brightnessDownSmallLabel
            ]),
            (dashedHeader("Modifiers & Modes"), [
                "Shift",
                "Ctrl",
                "Option",
                altGrLabel,
                "Cmd",
                "Emoji",
                screenshotShortcutLabel,
                voiceLabel,
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

    fileprivate static func isChordalShiftAlias(_ label: String) -> Bool {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.caseInsensitiveCompare(chordalShiftLabel) == .orderedSame
            || trimmed.caseInsensitiveCompare("Chord Shift") == .orderedSame
            || trimmed.caseInsensitiveCompare("ChordShift") == .orderedSame
    }

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
        case "Ctrl", "LCtrl", "RCtrl", "LeftCtrl", "RightCtrl":
            normalizedLabel = "Ctrl"
        case "Shift", "LShift", "RShift", "LeftShift", "RightShift":
            normalizedLabel = "Shift"
        case "Alt", "LeftAlt", "LAlt", "LeftOption", "LOption":
            normalizedLabel = "Option"
        case "TT":
            normalizedLabel = typingToggleLabel
        case "EMOJI":
            normalizedLabel = "Emoji"
        case "VOICE":
            normalizedLabel = voiceLabel
        case "Win", "Meta", "Super", "Cmd", "Command",
             "LWin", "LMeta", "LSuper", "LCmd", "LeftWin", "LeftMeta", "LeftSuper", "LeftCmd",
             "RWin", "RMeta", "RSuper", "RCmd", "RightWin", "RightMeta", "RightSuper", "RightCmd":
            normalizedLabel = "Cmd"
        case "Right Option", "RightOption", "ROption", "RAlt":
            normalizedLabel = altGrLabel
        case "VOL_UP", "VOL⬆️":
            normalizedLabel = volumeUpLabel
        case "VOL_DOWN", "VOL⬇️":
            normalizedLabel = volumeDownLabel
        case "VOL_UP_SMALL", "vol_up_small":
            normalizedLabel = volumeUpSmallLabel
        case "VOL_DOWN_SMALL", "vol_down_small":
            normalizedLabel = volumeDownSmallLabel
        case "BRIGHT_UP", "BRIGHT⬆️":
            normalizedLabel = brightnessUpLabel
        case "BRIGHT_DOWN", "BRIGHT⬇️":
            normalizedLabel = brightnessDownLabel
        case "BRIGHT_UP_SMALL", "bright_up_small":
            normalizedLabel = brightnessUpSmallLabel
        case "BRIGHT_DOWN_SMALL", "bright_down_small":
            normalizedLabel = brightnessDownSmallLabel
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
                label: normalizedLabel,
                keyCode: 0,
                flags: 0,
                kind: .volumeUp
            )
        }
        if normalizedLabel == volumeDownLabel {
            return KeyAction(
                label: normalizedLabel,
                keyCode: 0,
                flags: 0,
                kind: .volumeDown
            )
        }
        if normalizedLabel == volumeUpSmallLabel {
            return KeyAction(
                label: normalizedLabel,
                keyCode: 0,
                flags: 0,
                kind: .volumeUpSmall
            )
        }
        if normalizedLabel == volumeDownSmallLabel {
            return KeyAction(
                label: normalizedLabel,
                keyCode: 0,
                flags: 0,
                kind: .volumeDownSmall
            )
        }
        if normalizedLabel == brightnessUpLabel {
            return KeyAction(
                label: normalizedLabel,
                keyCode: 0,
                flags: 0,
                kind: .brightnessUp
            )
        }
        if normalizedLabel == brightnessUpSmallLabel {
            return KeyAction(
                label: normalizedLabel,
                keyCode: 0,
                flags: 0,
                kind: .brightnessUpSmall
            )
        }
        if normalizedLabel == brightnessScriptUpLabel {
            return KeyAction(
                label: label,
                keyCode: 0,
                flags: 0,
                kind: .brightnessUp
            )
        }
        if normalizedLabel == brightnessDownLabel {
            return KeyAction(
                label: normalizedLabel,
                keyCode: 0,
                flags: 0,
                kind: .brightnessDown
            )
        }
        if normalizedLabel == brightnessDownSmallLabel {
            return KeyAction(
                label: normalizedLabel,
                keyCode: 0,
                flags: 0,
                kind: .brightnessDownSmall
            )
        }
        if normalizedLabel == brightnessScriptDownLabel {
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
        if isChordalShiftAlias(normalizedLabel) {
            return action(for: "Shift")
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

enum GestureRepeatCadenceStorage {
    private static let maxRepeatCadenceMs = 5000

    static func decode(from data: Data) -> [String: Int]? {
        guard !data.isEmpty,
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data) else { return nil }
        return normalized(decoded)
    }

    static func encode(_ cadenceById: [String: Int]?) -> Data? {
        guard let normalized = normalized(cadenceById),
              !normalized.isEmpty,
              let encoded = try? JSONEncoder().encode(normalized) else { return nil }
        return encoded
    }

    static func normalized(_ cadenceById: [String: Int]?) -> [String: Int]? {
        guard let cadenceById, !cadenceById.isEmpty else { return nil }

        var normalized: [String: Int] = [:]
        for (bindingId, cadenceMs) in cadenceById {
            let trimmedBindingId = bindingId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedBindingId.isEmpty else { continue }

            let clampedCadenceMs = min(max(cadenceMs, 0), maxRepeatCadenceMs)
            guard clampedCadenceMs > 0 else { continue }
            normalized[trimmedBindingId] = clampedCadenceMs
        }

        return normalized.isEmpty ? nil : normalized
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
    let forceClickThreshold: Double
    let hapticStrength: Double
    let typingGraceMs: Double
    let intentMoveThresholdMm: Double
    let intentVelocityThresholdMmPerSec: Double
    let autocorrectEnabled: Bool
    let tapClickCadenceMs: Double
    let snapRadiusPercent: Double
    let keyboardModeEnabled: Bool
    let holdRepeatEnabled: Bool
    let shortcutActions: [String]
    let twoFingerTapGestureAction: String?
    let threeFingerTapGestureAction: String?
    let twoFingerHoldGestureAction: String?
    let threeFingerHoldGestureAction: String?
    let fourFingerHoldGestureAction: String?
    let outerCornersHoldGestureAction: String?
    let innerCornersHoldGestureAction: String?
    let leftEdgeUpGestureAction: String?
    let leftEdgeDownGestureAction: String?
    let rightEdgeUpGestureAction: String?
    let rightEdgeDownGestureAction: String?
    let topEdgeLeftGestureAction: String?
    let topEdgeRightGestureAction: String?
    let bottomEdgeLeftGestureAction: String?
    let bottomEdgeRightGestureAction: String?
    let threeFingerSwipeLeftGestureAction: String?
    let threeFingerSwipeRightGestureAction: String?
    let threeFingerSwipeUpGestureAction: String?
    let threeFingerSwipeDownGestureAction: String?
    let fourFingerSwipeLeftGestureAction: String?
    let fourFingerSwipeRightGestureAction: String?
    let fourFingerSwipeUpGestureAction: String?
    let fourFingerSwipeDownGestureAction: String?
    let fiveFingerSwipeLeftGestureAction: String?
    let fiveFingerSwipeRightGestureAction: String?
    let fiveFingerSwipeUpGestureAction: String?
    let fiveFingerSwipeDownGestureAction: String?
    let topLeftCornerSwipeGestureAction: String?
    let topRightCornerSwipeGestureAction: String?
    let bottomLeftCornerSwipeGestureAction: String?
    let bottomRightCornerSwipeGestureAction: String?
    let topLeftTriangleGestureAction: String?
    let topRightTriangleGestureAction: String?
    let bottomLeftTriangleGestureAction: String?
    let bottomRightTriangleGestureAction: String?
    let upperLeftCornerClickGestureAction: String?
    let upperRightCornerClickGestureAction: String?
    let lowerLeftCornerClickGestureAction: String?
    let lowerRightCornerClickGestureAction: String?
    let threeFingerClickGestureAction: String?
    let fourFingerClickGestureAction: String?
    let topLeftForceClickGestureAction: String?
    let topRightForceClickGestureAction: String?
    let bottomLeftForceClickGestureAction: String?
    let bottomRightForceClickGestureAction: String?
    let gestureRepeatCadenceMsById: [String: Int]?
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
            runAtStartupEnabled: LegacyProfileDefaults.runAtStartupEnabled,
            tapHoldDurationMs: LegacyProfileDefaults.tapHoldDurationMs,
            dragCancelDistance: LegacyProfileDefaults.dragCancelDistanceMm,
            forceClickMin: LegacyProfileDefaults.forceClickMin,
            forceClickCap: LegacyProfileDefaults.forceClickCap,
            forceClickThreshold: LegacyProfileDefaults.forceClickThreshold,
            hapticStrength: LegacyProfileDefaults.hapticStrengthPercent,
            typingGraceMs: LegacyProfileDefaults.typingGraceMs,
            intentMoveThresholdMm: LegacyProfileDefaults.intentMoveThresholdMm,
            intentVelocityThresholdMmPerSec: LegacyProfileDefaults.intentVelocityThresholdMmPerSec,
            autocorrectEnabled: LegacyProfileDefaults.autocorrectEnabled,
            tapClickCadenceMs: LegacyProfileDefaults.tapClickCadenceMs,
            snapRadiusPercent: LegacyProfileDefaults.snapRadiusPercent,
            keyboardModeEnabled: LegacyProfileDefaults.keyboardModeEnabled,
            holdRepeatEnabled: LegacyProfileDefaults.holdRepeatEnabled,
            shortcutActions: [],
            twoFingerTapGestureAction: LegacyProfileDefaults.twoFingerTapGestureActionLabel,
            threeFingerTapGestureAction: LegacyProfileDefaults.threeFingerTapGestureActionLabel,
            twoFingerHoldGestureAction: LegacyProfileDefaults.twoFingerHoldGestureActionLabel,
            threeFingerHoldGestureAction: LegacyProfileDefaults.threeFingerHoldGestureActionLabel,
            fourFingerHoldGestureAction: LegacyProfileDefaults.fourFingerHoldGestureActionLabel,
            outerCornersHoldGestureAction: LegacyProfileDefaults.outerCornersHoldGestureActionLabel,
            innerCornersHoldGestureAction: LegacyProfileDefaults.innerCornersHoldGestureActionLabel,
            leftEdgeUpGestureAction: LegacyProfileDefaults.leftEdgeUpGestureActionLabel,
            leftEdgeDownGestureAction: LegacyProfileDefaults.leftEdgeDownGestureActionLabel,
            rightEdgeUpGestureAction: LegacyProfileDefaults.rightEdgeUpGestureActionLabel,
            rightEdgeDownGestureAction: LegacyProfileDefaults.rightEdgeDownGestureActionLabel,
            topEdgeLeftGestureAction: LegacyProfileDefaults.topEdgeLeftGestureActionLabel,
            topEdgeRightGestureAction: LegacyProfileDefaults.topEdgeRightGestureActionLabel,
            bottomEdgeLeftGestureAction: LegacyProfileDefaults.bottomEdgeLeftGestureActionLabel,
            bottomEdgeRightGestureAction: LegacyProfileDefaults.bottomEdgeRightGestureActionLabel,
            threeFingerSwipeLeftGestureAction: LegacyProfileDefaults.threeFingerSwipeLeftGestureActionLabel,
            threeFingerSwipeRightGestureAction: LegacyProfileDefaults.threeFingerSwipeRightGestureActionLabel,
            threeFingerSwipeUpGestureAction: LegacyProfileDefaults.threeFingerSwipeUpGestureActionLabel,
            threeFingerSwipeDownGestureAction: LegacyProfileDefaults.threeFingerSwipeDownGestureActionLabel,
            fourFingerSwipeLeftGestureAction: LegacyProfileDefaults.fourFingerSwipeLeftGestureActionLabel,
            fourFingerSwipeRightGestureAction: LegacyProfileDefaults.fourFingerSwipeRightGestureActionLabel,
            fourFingerSwipeUpGestureAction: LegacyProfileDefaults.fourFingerSwipeUpGestureActionLabel,
            fourFingerSwipeDownGestureAction: LegacyProfileDefaults.fourFingerSwipeDownGestureActionLabel,
            fiveFingerSwipeLeftGestureAction: LegacyProfileDefaults.fiveFingerSwipeLeftGestureActionLabel,
            fiveFingerSwipeRightGestureAction: LegacyProfileDefaults.fiveFingerSwipeRightGestureActionLabel,
            fiveFingerSwipeUpGestureAction: LegacyProfileDefaults.fiveFingerSwipeUpGestureActionLabel,
            fiveFingerSwipeDownGestureAction: LegacyProfileDefaults.fiveFingerSwipeDownGestureActionLabel,
            topLeftCornerSwipeGestureAction: LegacyProfileDefaults.topLeftCornerSwipeGestureActionLabel,
            topRightCornerSwipeGestureAction: LegacyProfileDefaults.topRightCornerSwipeGestureActionLabel,
            bottomLeftCornerSwipeGestureAction: LegacyProfileDefaults.bottomLeftCornerSwipeGestureActionLabel,
            bottomRightCornerSwipeGestureAction: LegacyProfileDefaults.bottomRightCornerSwipeGestureActionLabel,
            topLeftTriangleGestureAction: LegacyProfileDefaults.topLeftTriangleGestureActionLabel,
            topRightTriangleGestureAction: LegacyProfileDefaults.topRightTriangleGestureActionLabel,
            bottomLeftTriangleGestureAction: LegacyProfileDefaults.bottomLeftTriangleGestureActionLabel,
            bottomRightTriangleGestureAction: LegacyProfileDefaults.bottomRightTriangleGestureActionLabel,
            upperLeftCornerClickGestureAction: LegacyProfileDefaults.upperLeftCornerClickGestureActionLabel,
            upperRightCornerClickGestureAction: LegacyProfileDefaults.upperRightCornerClickGestureActionLabel,
            lowerLeftCornerClickGestureAction: LegacyProfileDefaults.lowerLeftCornerClickGestureActionLabel,
            lowerRightCornerClickGestureAction: LegacyProfileDefaults.lowerRightCornerClickGestureActionLabel,
            threeFingerClickGestureAction: LegacyProfileDefaults.threeFingerClickGestureActionLabel,
            fourFingerClickGestureAction: LegacyProfileDefaults.fourFingerClickGestureActionLabel,
            topLeftForceClickGestureAction: LegacyProfileDefaults.topLeftForceClickGestureActionLabel,
            topRightForceClickGestureAction: LegacyProfileDefaults.topRightForceClickGestureActionLabel,
            bottomLeftForceClickGestureAction: LegacyProfileDefaults.bottomLeftForceClickGestureActionLabel,
            bottomRightForceClickGestureAction: LegacyProfileDefaults.bottomRightForceClickGestureActionLabel,
            gestureRepeatCadenceMsById: nil,
            keySpacingPercentByLayout: [:],
            columnSettingsByLayout: [:],
            customButtonsByLayout: [:],
            keyMappingsByLayout: KeyActionMappingStore.emptyLayoutMappings(),
            keyGeometryByLayout: KeyGeometryStore.emptyLayoutOverrides()
        )
    }
}

