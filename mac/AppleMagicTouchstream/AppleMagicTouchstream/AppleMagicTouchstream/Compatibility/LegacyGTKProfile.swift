// Legacy GlassToKey profile/capture serialization only.
// These types keep old .atpcap files and saved layouts readable. Gesture, dictation,
// app-launch and GTK mode fields never configure live recognition/output.
// Haptic strength is the intentional live-feedback exception, stored as percent.
import Carbon
import CoreGraphics
import Foundation
import OpenMultitouchSupport

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

    var gestureRecognitionEnabled: Bool? = nil
    var handGestureSettings: HandGestureSettings? = nil

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
            forceClickThreshold: GlassToKeySettings.forceClickThreshold,
            hapticStrength: GlassToKeySettings.hapticStrengthPercent,
            intentMoveThresholdMm: GlassToKeySettings.intentMoveThresholdMm,
            intentVelocityThresholdMmPerSec: GlassToKeySettings.intentVelocityThresholdMmPerSec,
            autocorrectEnabled: GlassToKeySettings.autocorrectEnabled,
            tapClickCadenceMs: GlassToKeySettings.tapClickCadenceMs,
            snapRadiusPercent: GlassToKeySettings.snapRadiusPercent,
            keyboardModeEnabled: GlassToKeySettings.keyboardModeEnabled,
            holdRepeatEnabled: GlassToKeySettings.holdRepeatEnabled,
            shortcutActions: [],
            twoFingerTapGestureAction: GlassToKeySettings.twoFingerTapGestureActionLabel,
            threeFingerTapGestureAction: GlassToKeySettings.threeFingerTapGestureActionLabel,
            twoFingerHoldGestureAction: GlassToKeySettings.twoFingerHoldGestureActionLabel,
            threeFingerHoldGestureAction: GlassToKeySettings.threeFingerHoldGestureActionLabel,
            fourFingerHoldGestureAction: GlassToKeySettings.fourFingerHoldGestureActionLabel,
            outerCornersHoldGestureAction: GlassToKeySettings.outerCornersHoldGestureActionLabel,
            innerCornersHoldGestureAction: GlassToKeySettings.innerCornersHoldGestureActionLabel,
            leftEdgeUpGestureAction: GlassToKeySettings.leftEdgeUpGestureActionLabel,
            leftEdgeDownGestureAction: GlassToKeySettings.leftEdgeDownGestureActionLabel,
            rightEdgeUpGestureAction: GlassToKeySettings.rightEdgeUpGestureActionLabel,
            rightEdgeDownGestureAction: GlassToKeySettings.rightEdgeDownGestureActionLabel,
            topEdgeLeftGestureAction: GlassToKeySettings.topEdgeLeftGestureActionLabel,
            topEdgeRightGestureAction: GlassToKeySettings.topEdgeRightGestureActionLabel,
            bottomEdgeLeftGestureAction: GlassToKeySettings.bottomEdgeLeftGestureActionLabel,
            bottomEdgeRightGestureAction: GlassToKeySettings.bottomEdgeRightGestureActionLabel,
            threeFingerSwipeLeftGestureAction: GlassToKeySettings.threeFingerSwipeLeftGestureActionLabel,
            threeFingerSwipeRightGestureAction: GlassToKeySettings.threeFingerSwipeRightGestureActionLabel,
            threeFingerSwipeUpGestureAction: GlassToKeySettings.threeFingerSwipeUpGestureActionLabel,
            threeFingerSwipeDownGestureAction: GlassToKeySettings.threeFingerSwipeDownGestureActionLabel,
            fourFingerSwipeLeftGestureAction: GlassToKeySettings.fourFingerSwipeLeftGestureActionLabel,
            fourFingerSwipeRightGestureAction: GlassToKeySettings.fourFingerSwipeRightGestureActionLabel,
            fourFingerSwipeUpGestureAction: GlassToKeySettings.fourFingerSwipeUpGestureActionLabel,
            fourFingerSwipeDownGestureAction: GlassToKeySettings.fourFingerSwipeDownGestureActionLabel,
            fiveFingerSwipeLeftGestureAction: GlassToKeySettings.fiveFingerSwipeLeftGestureActionLabel,
            fiveFingerSwipeRightGestureAction: GlassToKeySettings.fiveFingerSwipeRightGestureActionLabel,
            fiveFingerSwipeUpGestureAction: GlassToKeySettings.fiveFingerSwipeUpGestureActionLabel,
            fiveFingerSwipeDownGestureAction: GlassToKeySettings.fiveFingerSwipeDownGestureActionLabel,
            topLeftCornerSwipeGestureAction: GlassToKeySettings.topLeftCornerSwipeGestureActionLabel,
            topRightCornerSwipeGestureAction: GlassToKeySettings.topRightCornerSwipeGestureActionLabel,
            bottomLeftCornerSwipeGestureAction: GlassToKeySettings.bottomLeftCornerSwipeGestureActionLabel,
            bottomRightCornerSwipeGestureAction: GlassToKeySettings.bottomRightCornerSwipeGestureActionLabel,
            topLeftTriangleGestureAction: GlassToKeySettings.topLeftTriangleGestureActionLabel,
            topRightTriangleGestureAction: GlassToKeySettings.topRightTriangleGestureActionLabel,
            bottomLeftTriangleGestureAction: GlassToKeySettings.bottomLeftTriangleGestureActionLabel,
            bottomRightTriangleGestureAction: GlassToKeySettings.bottomRightTriangleGestureActionLabel,
            upperLeftCornerClickGestureAction: GlassToKeySettings.upperLeftCornerClickGestureActionLabel,
            upperRightCornerClickGestureAction: GlassToKeySettings.upperRightCornerClickGestureActionLabel,
            lowerLeftCornerClickGestureAction: GlassToKeySettings.lowerLeftCornerClickGestureActionLabel,
            lowerRightCornerClickGestureAction: GlassToKeySettings.lowerRightCornerClickGestureActionLabel,
            threeFingerClickGestureAction: GlassToKeySettings.threeFingerClickGestureActionLabel,
            fourFingerClickGestureAction: GlassToKeySettings.fourFingerClickGestureActionLabel,
            topLeftForceClickGestureAction: GlassToKeySettings.topLeftForceClickGestureActionLabel,
            topRightForceClickGestureAction: GlassToKeySettings.topRightForceClickGestureActionLabel,
            bottomLeftForceClickGestureAction: GlassToKeySettings.bottomLeftForceClickGestureActionLabel,
            bottomRightForceClickGestureAction: GlassToKeySettings.bottomRightForceClickGestureActionLabel,
            gestureRepeatCadenceMsById: nil,
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
        let shortcutActions: [String]
        if let importedShortcutActions = settings.shortcutActions {
            var unsupportedShortcutLabels = Set<String>()
            let resolvedShortcutActions = importedShortcutActions.compactMap { label in
                resolveImportedAction(
                    label,
                    unsupportedLabels: &unsupportedShortcutLabels,
                    allowNil: true
                )?.storageLabel
            }
            guard unsupportedShortcutLabels.isEmpty else {
                throw PortableKeymapImportError.unsupportedActions(Array(unsupportedShortcutLabels))
            }
            shortcutActions = ShortcutActionLibraryStorage.normalized(resolvedShortcutActions)
        } else {
            shortcutActions = ShortcutActionLibraryStorage.normalized(currentProfile.shortcutActions)
        }

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
            forceClickThreshold: Double(
                settings.forceClickThreshold
                    ?? Int(currentProfile.forceClickThreshold)
            ),
            hapticStrength: currentProfile.hapticStrength,
            intentMoveThresholdMm: settings.intentMoveMm ?? currentProfile.intentMoveThresholdMm,
            intentVelocityThresholdMmPerSec: settings.intentVelocityMmPerSec ?? currentProfile.intentVelocityThresholdMmPerSec,
            autocorrectEnabled: settings.autocorrectEnabled ?? currentProfile.autocorrectEnabled,
            tapClickCadenceMs: currentProfile.tapClickCadenceMs,
            snapRadiusPercent: settings.snapRadiusPercent ?? currentProfile.snapRadiusPercent,
            keyboardModeEnabled: settings.keyboardModeEnabled ?? currentProfile.keyboardModeEnabled,
            holdRepeatEnabled: settings.holdRepeatEnabled ?? currentProfile.holdRepeatEnabled,
            shortcutActions: shortcutActions,
            twoFingerTapGestureAction: currentProfile.twoFingerTapGestureAction,
            threeFingerTapGestureAction: settings.threeFingerTapAction
                ?? settings.threeFingerClickAction
                ?? currentProfile.threeFingerTapGestureAction,
            twoFingerHoldGestureAction: settings.twoFingerHoldAction ?? currentProfile.twoFingerHoldGestureAction,
            threeFingerHoldGestureAction: settings.threeFingerHoldAction ?? currentProfile.threeFingerHoldGestureAction,
            fourFingerHoldGestureAction: settings.fourFingerHoldAction ?? currentProfile.fourFingerHoldGestureAction,
            outerCornersHoldGestureAction: settings.outerCornersAction ?? currentProfile.outerCornersHoldGestureAction,
            innerCornersHoldGestureAction: settings.innerCornersAction ?? currentProfile.innerCornersHoldGestureAction,
            leftEdgeUpGestureAction: settings.leftEdgeUpAction ?? currentProfile.leftEdgeUpGestureAction,
            leftEdgeDownGestureAction: settings.leftEdgeDownAction ?? currentProfile.leftEdgeDownGestureAction,
            rightEdgeUpGestureAction: settings.rightEdgeUpAction ?? currentProfile.rightEdgeUpGestureAction,
            rightEdgeDownGestureAction: settings.rightEdgeDownAction ?? currentProfile.rightEdgeDownGestureAction,
            topEdgeLeftGestureAction: settings.topEdgeLeftAction ?? currentProfile.topEdgeLeftGestureAction,
            topEdgeRightGestureAction: settings.topEdgeRightAction ?? currentProfile.topEdgeRightGestureAction,
            bottomEdgeLeftGestureAction: settings.bottomEdgeLeftAction ?? currentProfile.bottomEdgeLeftGestureAction,
            bottomEdgeRightGestureAction: settings.bottomEdgeRightAction ?? currentProfile.bottomEdgeRightGestureAction,
            threeFingerSwipeLeftGestureAction: settings.threeFingerSwipeLeftAction ?? currentProfile.threeFingerSwipeLeftGestureAction,
            threeFingerSwipeRightGestureAction: settings.threeFingerSwipeRightAction ?? currentProfile.threeFingerSwipeRightGestureAction,
            threeFingerSwipeUpGestureAction: settings.threeFingerSwipeUpAction ?? currentProfile.threeFingerSwipeUpGestureAction,
            threeFingerSwipeDownGestureAction: settings.threeFingerSwipeDownAction ?? currentProfile.threeFingerSwipeDownGestureAction,
            fourFingerSwipeLeftGestureAction: settings.fourFingerSwipeLeftAction ?? currentProfile.fourFingerSwipeLeftGestureAction,
            fourFingerSwipeRightGestureAction: settings.fourFingerSwipeRightAction ?? currentProfile.fourFingerSwipeRightGestureAction,
            fourFingerSwipeUpGestureAction: settings.fourFingerSwipeUpAction ?? currentProfile.fourFingerSwipeUpGestureAction,
            fourFingerSwipeDownGestureAction: settings.fourFingerSwipeDownAction ?? currentProfile.fourFingerSwipeDownGestureAction,
            fiveFingerSwipeLeftGestureAction: settings.fiveFingerSwipeLeftAction ?? currentProfile.fiveFingerSwipeLeftGestureAction,
            fiveFingerSwipeRightGestureAction: settings.fiveFingerSwipeRightAction ?? currentProfile.fiveFingerSwipeRightGestureAction,
            fiveFingerSwipeUpGestureAction: settings.fiveFingerSwipeUpAction ?? currentProfile.fiveFingerSwipeUpGestureAction,
            fiveFingerSwipeDownGestureAction: settings.fiveFingerSwipeDownAction ?? currentProfile.fiveFingerSwipeDownGestureAction,
            topLeftCornerSwipeGestureAction: settings.topLeftCornerSwipeAction ?? currentProfile.topLeftCornerSwipeGestureAction,
            topRightCornerSwipeGestureAction: settings.topRightCornerSwipeAction ?? currentProfile.topRightCornerSwipeGestureAction,
            bottomLeftCornerSwipeGestureAction: settings.bottomLeftCornerSwipeAction ?? currentProfile.bottomLeftCornerSwipeGestureAction,
            bottomRightCornerSwipeGestureAction: settings.bottomRightCornerSwipeAction ?? currentProfile.bottomRightCornerSwipeGestureAction,
            topLeftTriangleGestureAction: settings.topLeftTriangleAction ?? currentProfile.topLeftTriangleGestureAction,
            topRightTriangleGestureAction: settings.topRightTriangleAction ?? currentProfile.topRightTriangleGestureAction,
            bottomLeftTriangleGestureAction: settings.bottomLeftTriangleAction ?? currentProfile.bottomLeftTriangleGestureAction,
            bottomRightTriangleGestureAction: settings.bottomRightTriangleAction ?? currentProfile.bottomRightTriangleGestureAction,
            upperLeftCornerClickGestureAction: settings.upperLeftCornerClickAction ?? currentProfile.upperLeftCornerClickGestureAction,
            upperRightCornerClickGestureAction: settings.upperRightCornerClickAction ?? currentProfile.upperRightCornerClickGestureAction,
            lowerLeftCornerClickGestureAction: settings.lowerLeftCornerClickAction ?? currentProfile.lowerLeftCornerClickGestureAction,
            lowerRightCornerClickGestureAction: settings.lowerRightCornerClickAction ?? currentProfile.lowerRightCornerClickGestureAction,
            threeFingerClickGestureAction: settings.threeFingerClickAction ?? currentProfile.threeFingerClickGestureAction,
            fourFingerClickGestureAction: settings.fourFingerClickAction ?? currentProfile.fourFingerClickGestureAction,
            topLeftForceClickGestureAction: settings.topLeftForceClickAction ?? currentProfile.topLeftForceClickGestureAction,
            topRightForceClickGestureAction: settings.topRightForceClickAction ?? currentProfile.topRightForceClickGestureAction,
            bottomLeftForceClickGestureAction: settings.bottomLeftForceClickAction ?? currentProfile.bottomLeftForceClickGestureAction,
            bottomRightForceClickGestureAction: settings.bottomRightForceClickAction ?? currentProfile.bottomRightForceClickGestureAction,
            gestureRepeatCadenceMsById: GestureRepeatCadenceStorage.normalized(
                settings.gestureRepeatCadenceMsById ?? currentProfile.gestureRepeatCadenceMsById
            ),
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
                forceClickThreshold: hostExtension.forceClickThreshold ?? profile.forceClickThreshold,
                hapticStrength: hostExtension.hapticStrength ?? profile.hapticStrength,
                intentMoveThresholdMm: profile.intentMoveThresholdMm,
                intentVelocityThresholdMmPerSec: profile.intentVelocityThresholdMmPerSec,
                autocorrectEnabled: profile.autocorrectEnabled,
                tapClickCadenceMs: hostExtension.tapClickCadenceMs ?? profile.tapClickCadenceMs,
                snapRadiusPercent: profile.snapRadiusPercent,
                keyboardModeEnabled: profile.keyboardModeEnabled,
                holdRepeatEnabled: profile.holdRepeatEnabled,
                shortcutActions: profile.shortcutActions,
                twoFingerTapGestureAction: hostExtension.twoFingerTapGestureAction ?? profile.twoFingerTapGestureAction,
                threeFingerTapGestureAction: hostExtension.threeFingerTapGestureAction ?? profile.threeFingerTapGestureAction,
                twoFingerHoldGestureAction: profile.twoFingerHoldGestureAction,
                threeFingerHoldGestureAction: profile.threeFingerHoldGestureAction,
                fourFingerHoldGestureAction: profile.fourFingerHoldGestureAction,
                outerCornersHoldGestureAction: profile.outerCornersHoldGestureAction,
                innerCornersHoldGestureAction: profile.innerCornersHoldGestureAction,
                leftEdgeUpGestureAction: profile.leftEdgeUpGestureAction,
                leftEdgeDownGestureAction: profile.leftEdgeDownGestureAction,
                rightEdgeUpGestureAction: profile.rightEdgeUpGestureAction,
                rightEdgeDownGestureAction: profile.rightEdgeDownGestureAction,
                topEdgeLeftGestureAction: profile.topEdgeLeftGestureAction,
                topEdgeRightGestureAction: profile.topEdgeRightGestureAction,
                bottomEdgeLeftGestureAction: profile.bottomEdgeLeftGestureAction,
                bottomEdgeRightGestureAction: profile.bottomEdgeRightGestureAction,
                threeFingerSwipeLeftGestureAction: profile.threeFingerSwipeLeftGestureAction,
                threeFingerSwipeRightGestureAction: profile.threeFingerSwipeRightGestureAction,
                threeFingerSwipeUpGestureAction: profile.threeFingerSwipeUpGestureAction,
                threeFingerSwipeDownGestureAction: profile.threeFingerSwipeDownGestureAction,
                fourFingerSwipeLeftGestureAction: profile.fourFingerSwipeLeftGestureAction,
                fourFingerSwipeRightGestureAction: profile.fourFingerSwipeRightGestureAction,
                fourFingerSwipeUpGestureAction: profile.fourFingerSwipeUpGestureAction,
                fourFingerSwipeDownGestureAction: profile.fourFingerSwipeDownGestureAction,
                fiveFingerSwipeLeftGestureAction: profile.fiveFingerSwipeLeftGestureAction,
                fiveFingerSwipeRightGestureAction: profile.fiveFingerSwipeRightGestureAction,
                fiveFingerSwipeUpGestureAction: profile.fiveFingerSwipeUpGestureAction,
                fiveFingerSwipeDownGestureAction: profile.fiveFingerSwipeDownGestureAction,
                topLeftCornerSwipeGestureAction: profile.topLeftCornerSwipeGestureAction,
                topRightCornerSwipeGestureAction: profile.topRightCornerSwipeGestureAction,
                bottomLeftCornerSwipeGestureAction: profile.bottomLeftCornerSwipeGestureAction,
                bottomRightCornerSwipeGestureAction: profile.bottomRightCornerSwipeGestureAction,
                topLeftTriangleGestureAction: profile.topLeftTriangleGestureAction,
                topRightTriangleGestureAction: profile.topRightTriangleGestureAction,
                bottomLeftTriangleGestureAction: profile.bottomLeftTriangleGestureAction,
                bottomRightTriangleGestureAction: profile.bottomRightTriangleGestureAction,
                upperLeftCornerClickGestureAction: profile.upperLeftCornerClickGestureAction,
                upperRightCornerClickGestureAction: profile.upperRightCornerClickGestureAction,
                lowerLeftCornerClickGestureAction: profile.lowerLeftCornerClickGestureAction,
                lowerRightCornerClickGestureAction: profile.lowerRightCornerClickGestureAction,
                threeFingerClickGestureAction: profile.threeFingerClickGestureAction,
                fourFingerClickGestureAction: profile.fourFingerClickGestureAction,
                topLeftForceClickGestureAction: profile.topLeftForceClickGestureAction,
                topRightForceClickGestureAction: profile.topRightForceClickGestureAction,
                bottomLeftForceClickGestureAction: profile.bottomLeftForceClickGestureAction,
                bottomRightForceClickGestureAction: profile.bottomRightForceClickGestureAction,
                gestureRepeatCadenceMsById: profile.gestureRepeatCadenceMsById,
                keySpacingPercentByLayout: profile.keySpacingPercentByLayout,
                columnSettingsByLayout: profile.columnSettingsByLayout,
                customButtonsByLayout: profile.customButtonsByLayout,
                keyMappingsByLayout: profile.keyMappingsByLayout,
                keyGeometryByLayout: profile.keyGeometryByLayout
            )
        }

        profile.handGestureSettings = bundle.hostExtensions?["mac"]?.handGestureSettings ?? currentProfile.handGestureSettings
        if let current = currentProfile.handGestureSettings {
            profile.handGestureSettings?.left.preserveMissingRepeatBehaviors(from:current.left)
            profile.handGestureSettings?.right.preserveMissingRepeatBehaviors(from:current.right)
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
                    output[storageKey] = KeyMapping(
                        primary: primary,
                        hold: hold,
                        holdForceThreshold: hold == nil
                            ? 0
                            : KeyMapping.normalizedHoldForceThreshold(
                                portableMapping.holdForceThreshold ?? 0
                            )
                    )
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
                        holdForceThreshold: hold == nil
                            ? 0
                            : KeyMapping.normalizedHoldForceThreshold(
                                portableButton.holdForceThreshold ?? 0
                            ),
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

        var result = AppKeymapProfile(
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
            forceClickThreshold: profile.forceClickThreshold,
            hapticStrength: profile.hapticStrength,
            intentMoveThresholdMm: profile.intentMoveThresholdMm,
            intentVelocityThresholdMmPerSec: profile.intentVelocityThresholdMmPerSec,
            autocorrectEnabled: profile.autocorrectEnabled,
            tapClickCadenceMs: profile.tapClickCadenceMs,
            snapRadiusPercent: profile.snapRadiusPercent,
            keyboardModeEnabled: profile.keyboardModeEnabled,
            holdRepeatEnabled: profile.holdRepeatEnabled,
            shortcutActions: profile.shortcutActions,
            twoFingerTapGestureAction: profile.twoFingerTapGestureAction,
            threeFingerTapGestureAction: profile.threeFingerTapGestureAction,
            twoFingerHoldGestureAction: profile.twoFingerHoldGestureAction,
            threeFingerHoldGestureAction: profile.threeFingerHoldGestureAction,
            fourFingerHoldGestureAction: profile.fourFingerHoldGestureAction,
            outerCornersHoldGestureAction: profile.outerCornersHoldGestureAction,
            innerCornersHoldGestureAction: profile.innerCornersHoldGestureAction,
            leftEdgeUpGestureAction: profile.leftEdgeUpGestureAction,
            leftEdgeDownGestureAction: profile.leftEdgeDownGestureAction,
            rightEdgeUpGestureAction: profile.rightEdgeUpGestureAction,
            rightEdgeDownGestureAction: profile.rightEdgeDownGestureAction,
            topEdgeLeftGestureAction: profile.topEdgeLeftGestureAction,
            topEdgeRightGestureAction: profile.topEdgeRightGestureAction,
            bottomEdgeLeftGestureAction: profile.bottomEdgeLeftGestureAction,
            bottomEdgeRightGestureAction: profile.bottomEdgeRightGestureAction,
            threeFingerSwipeLeftGestureAction: profile.threeFingerSwipeLeftGestureAction,
            threeFingerSwipeRightGestureAction: profile.threeFingerSwipeRightGestureAction,
            threeFingerSwipeUpGestureAction: profile.threeFingerSwipeUpGestureAction,
            threeFingerSwipeDownGestureAction: profile.threeFingerSwipeDownGestureAction,
            fourFingerSwipeLeftGestureAction: profile.fourFingerSwipeLeftGestureAction,
            fourFingerSwipeRightGestureAction: profile.fourFingerSwipeRightGestureAction,
            fourFingerSwipeUpGestureAction: profile.fourFingerSwipeUpGestureAction,
            fourFingerSwipeDownGestureAction: profile.fourFingerSwipeDownGestureAction,
            fiveFingerSwipeLeftGestureAction: profile.fiveFingerSwipeLeftGestureAction,
            fiveFingerSwipeRightGestureAction: profile.fiveFingerSwipeRightGestureAction,
            fiveFingerSwipeUpGestureAction: profile.fiveFingerSwipeUpGestureAction,
            fiveFingerSwipeDownGestureAction: profile.fiveFingerSwipeDownGestureAction,
            topLeftCornerSwipeGestureAction: profile.topLeftCornerSwipeGestureAction,
            topRightCornerSwipeGestureAction: profile.topRightCornerSwipeGestureAction,
            bottomLeftCornerSwipeGestureAction: profile.bottomLeftCornerSwipeGestureAction,
            bottomRightCornerSwipeGestureAction: profile.bottomRightCornerSwipeGestureAction,
            topLeftTriangleGestureAction: profile.topLeftTriangleGestureAction,
            topRightTriangleGestureAction: profile.topRightTriangleGestureAction,
            bottomLeftTriangleGestureAction: profile.bottomLeftTriangleGestureAction,
            bottomRightTriangleGestureAction: profile.bottomRightTriangleGestureAction,
            upperLeftCornerClickGestureAction: profile.upperLeftCornerClickGestureAction,
            upperRightCornerClickGestureAction: profile.upperRightCornerClickGestureAction,
            lowerLeftCornerClickGestureAction: profile.lowerLeftCornerClickGestureAction,
            lowerRightCornerClickGestureAction: profile.lowerRightCornerClickGestureAction,
            threeFingerClickGestureAction: profile.threeFingerClickGestureAction,
            fourFingerClickGestureAction: profile.fourFingerClickGestureAction,
            topLeftForceClickGestureAction: profile.topLeftForceClickGestureAction,
            topRightForceClickGestureAction: profile.topRightForceClickGestureAction,
            bottomLeftForceClickGestureAction: profile.bottomLeftForceClickGestureAction,
            bottomRightForceClickGestureAction: profile.bottomRightForceClickGestureAction,
            gestureRepeatCadenceMsById: profile.gestureRepeatCadenceMsById,
            keySpacingPercentByLayout: profile.keySpacingPercentByLayout,
            columnSettingsByLayout: profile.columnSettingsByLayout,
            customButtonsByLayout: customButtonsByLayout,
            keyMappingsByLayout: mappingsByLayout,
            keyGeometryByLayout: geometryByLayout
        )
        result.handGestureSettings = profile.handGestureSettings
        return result
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
                        hold: pair.value.hold.map { PortableKeyAction(label: portableLabel(for: $0)) },
                        holdForceThreshold: pair.value.hold == nil ? 0 : pair.value.holdForceThreshold
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
                        holdForceThreshold: button.hold == nil ? 0 : button.holdForceThreshold,
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
        // Existing saved mappings can contain retired GTK actions. Preserve their
        // identity for round-tripping without restoring them to the live catalog.
        let retired: [String:KeyActionKind] = [
            "Voice":.voice, "VOICE":.voice,
            "BRIGHT_UP":.brightnessUp, "BRIGHT⬆️":.brightnessUp,
            "BRIGHT_DOWN":.brightnessDown, "BRIGHT⬇️":.brightnessDown,
            "BRIGHT_UP_SMALL":.brightnessUpSmall, "bright_up_small":.brightnessUpSmall,
            "BRIGHT_DOWN_SMALL":.brightnessDownSmall, "bright_down_small":.brightnessDownSmall,
            "BRI_SCRIPT_UP":.brightnessUp, "BRI_SCRIPT_DOWN":.brightnessDown,
            "VOL_UP_SMALL":.volumeUpSmall, "vol_up_small":.volumeUpSmall,
            "VOL_DOWN_SMALL":.volumeDownSmall, "vol_down_small":.volumeDownSmall,
            KeyActionCatalog.typingToggleLabel:.typingToggle, "TT":.typingToggle
        ]
        if let kind = retired[trimmed] {
            return KeyAction(label:trimmed,keyCode:0,flags:0,kind:kind)
        }
        unsupportedLabels.insert(trimmed)
        return allowNil ? nil : KeyActionCatalog.noneAction
    }

    private static func portableLayoutName(fromMac name: String) -> String {
        TrackpadLayoutPreset.resolveByName(name)?.rawValue ?? name
    }

    private static func macLayoutName(fromPortable name: String?) -> String? {
        TrackpadLayoutPreset.resolveByName(name)?.rawValue
    }

    private static func portableLabel(for action: KeyAction) -> String {
        action.storageLabel
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
        var forceClickThreshold: Double?
        var hapticStrength: Double?
        var handGestureSettings: HandGestureSettings?

        init(profile: AppKeymapProfile) {
            leftDeviceID = profile.leftDeviceID
            rightDeviceID = profile.rightDeviceID
            autoResyncMissingTrackpads = profile.autoResyncMissingTrackpads
            runAtStartupEnabled = profile.runAtStartupEnabled
            twoFingerTapGestureAction = profile.twoFingerTapGestureAction
            threeFingerTapGestureAction = profile.threeFingerTapGestureAction
            tapClickCadenceMs = profile.tapClickCadenceMs
            forceClickThreshold = profile.forceClickThreshold
            hapticStrength = profile.hapticStrength
            handGestureSettings = profile.handGestureSettings
        }

        private enum CodingKeys: String, CodingKey {
            case leftDeviceID = "LeftDeviceID"
            case rightDeviceID = "RightDeviceID"
            case autoResyncMissingTrackpads = "AutoResyncMissingTrackpads"
            case runAtStartupEnabled = "RunAtStartupEnabled"
            case twoFingerTapGestureAction = "TwoFingerTapGestureAction"
            case threeFingerTapGestureAction = "ThreeFingerTapGestureAction"
            case tapClickCadenceMs = "TapClickCadenceMs"
            case forceClickThreshold = "ForceClickThreshold"
            case hapticStrength = "HapticStrength"
            case handGestureSettings = "GestureBindings"
        }
    }

    private struct PortableSettings: Codable {
        var activeLayer: Int?
        var layoutPresetName: String?
        var keyboardModeEnabled: Bool?
        var holdRepeatEnabled: Bool?
        var autocorrectEnabled: Bool?
        var shortcutActions: [String]?
        var threeFingerTapAction: String?
        var fiveFingerSwipeLeftAction: String?
        var fiveFingerSwipeRightAction: String?
        var fiveFingerSwipeUpAction: String?
        var fiveFingerSwipeDownAction: String?
        var threeFingerSwipeLeftAction: String?
        var threeFingerSwipeRightAction: String?
        var threeFingerSwipeUpAction: String?
        var threeFingerSwipeDownAction: String?
        var fourFingerSwipeLeftAction: String?
        var fourFingerSwipeRightAction: String?
        var fourFingerSwipeUpAction: String?
        var fourFingerSwipeDownAction: String?
        var twoFingerHoldAction: String?
        var threeFingerHoldAction: String?
        var fourFingerHoldAction: String?
        var leftEdgeUpAction: String?
        var leftEdgeDownAction: String?
        var rightEdgeUpAction: String?
        var rightEdgeDownAction: String?
        var topEdgeLeftAction: String?
        var topEdgeRightAction: String?
        var bottomEdgeLeftAction: String?
        var bottomEdgeRightAction: String?
        var threeFingerClickAction: String?
        var fourFingerClickAction: String?
        var outerCornersAction: String?
        var innerCornersAction: String?
        var topLeftCornerSwipeAction: String?
        var topRightCornerSwipeAction: String?
        var bottomLeftCornerSwipeAction: String?
        var bottomRightCornerSwipeAction: String?
        var topLeftTriangleAction: String?
        var topRightTriangleAction: String?
        var bottomLeftTriangleAction: String?
        var bottomRightTriangleAction: String?
        var upperLeftCornerClickAction: String?
        var upperRightCornerClickAction: String?
        var lowerLeftCornerClickAction: String?
        var lowerRightCornerClickAction: String?
        var topLeftForceClickAction: String?
        var topRightForceClickAction: String?
        var bottomLeftForceClickAction: String?
        var bottomRightForceClickAction: String?
        var holdDurationMs: Double?
        var dragCancelMm: Double?
        var intentMoveMm: Double?
        var intentVelocityMmPerSec: Double?
        var snapRadiusPercent: Double?
        var gestureRepeatCadenceMsById: [String: Int]?
        var keyPaddingPercent: Double?
        var keyPaddingPercentByLayout: [String: Double]?
        var forceMin: Int?
        var forceCap: Int?
        var forceClickThreshold: Int?
        var columnSettingsByLayout: [String: [ColumnLayoutSettings]]?
        var columnSettings: [ColumnLayoutSettings]?

        init(profile: AppKeymapProfile) {
            activeLayer = KeyLayerConfig.clamped(profile.activeLayer ?? KeyLayerConfig.baseLayer)
            let resolvedLayout = TrackpadLayoutPreset.resolveByNameOrDefault(profile.layoutPreset)
            layoutPresetName = portableLayoutName(fromMac: profile.layoutPreset)
            keyboardModeEnabled = profile.keyboardModeEnabled
            holdRepeatEnabled = profile.holdRepeatEnabled
            autocorrectEnabled = profile.autocorrectEnabled
            shortcutActions = ShortcutActionLibraryStorage.normalized(profile.shortcutActions)
            threeFingerTapAction = profile.threeFingerTapGestureAction
            fiveFingerSwipeLeftAction = profile.fiveFingerSwipeLeftGestureAction
            fiveFingerSwipeRightAction = profile.fiveFingerSwipeRightGestureAction
            fiveFingerSwipeUpAction = profile.fiveFingerSwipeUpGestureAction
            fiveFingerSwipeDownAction = profile.fiveFingerSwipeDownGestureAction
            threeFingerSwipeLeftAction = profile.threeFingerSwipeLeftGestureAction
            threeFingerSwipeRightAction = profile.threeFingerSwipeRightGestureAction
            threeFingerSwipeUpAction = profile.threeFingerSwipeUpGestureAction
            threeFingerSwipeDownAction = profile.threeFingerSwipeDownGestureAction
            fourFingerSwipeLeftAction = profile.fourFingerSwipeLeftGestureAction
            fourFingerSwipeRightAction = profile.fourFingerSwipeRightGestureAction
            fourFingerSwipeUpAction = profile.fourFingerSwipeUpGestureAction
            fourFingerSwipeDownAction = profile.fourFingerSwipeDownGestureAction
            twoFingerHoldAction = profile.twoFingerHoldGestureAction
            threeFingerHoldAction = profile.threeFingerHoldGestureAction
            fourFingerHoldAction = profile.fourFingerHoldGestureAction
            leftEdgeUpAction = profile.leftEdgeUpGestureAction
            leftEdgeDownAction = profile.leftEdgeDownGestureAction
            rightEdgeUpAction = profile.rightEdgeUpGestureAction
            rightEdgeDownAction = profile.rightEdgeDownGestureAction
            topEdgeLeftAction = profile.topEdgeLeftGestureAction
            topEdgeRightAction = profile.topEdgeRightGestureAction
            bottomEdgeLeftAction = profile.bottomEdgeLeftGestureAction
            bottomEdgeRightAction = profile.bottomEdgeRightGestureAction
            threeFingerClickAction = profile.threeFingerClickGestureAction
            fourFingerClickAction = profile.fourFingerClickGestureAction
            outerCornersAction = profile.outerCornersHoldGestureAction
            innerCornersAction = profile.innerCornersHoldGestureAction
            topLeftCornerSwipeAction = profile.topLeftCornerSwipeGestureAction
            topRightCornerSwipeAction = profile.topRightCornerSwipeGestureAction
            bottomLeftCornerSwipeAction = profile.bottomLeftCornerSwipeGestureAction
            bottomRightCornerSwipeAction = profile.bottomRightCornerSwipeGestureAction
            topLeftTriangleAction = profile.topLeftTriangleGestureAction
            topRightTriangleAction = profile.topRightTriangleGestureAction
            bottomLeftTriangleAction = profile.bottomLeftTriangleGestureAction
            bottomRightTriangleAction = profile.bottomRightTriangleGestureAction
            upperLeftCornerClickAction = profile.upperLeftCornerClickGestureAction
            upperRightCornerClickAction = profile.upperRightCornerClickGestureAction
            lowerLeftCornerClickAction = profile.lowerLeftCornerClickGestureAction
            lowerRightCornerClickAction = profile.lowerRightCornerClickGestureAction
            topLeftForceClickAction = profile.topLeftForceClickGestureAction
            topRightForceClickAction = profile.topRightForceClickGestureAction
            bottomLeftForceClickAction = profile.bottomLeftForceClickGestureAction
            bottomRightForceClickAction = profile.bottomRightForceClickGestureAction
            holdDurationMs = profile.tapHoldDurationMs
            dragCancelMm = profile.dragCancelDistance
            intentMoveMm = profile.intentMoveThresholdMm
            intentVelocityMmPerSec = profile.intentVelocityThresholdMmPerSec
            snapRadiusPercent = profile.snapRadiusPercent
            gestureRepeatCadenceMsById = GestureRepeatCadenceStorage.normalized(
                profile.gestureRepeatCadenceMsById
            )
            keyPaddingPercent = profile.keySpacingPercentByLayout?[resolvedLayout.rawValue]
            keyPaddingPercentByLayout = profile.keySpacingPercentByLayout?.reduce(into: [:]) { result, entry in
                result[portableLayoutName(fromMac: entry.key)] = entry.value
            }
            forceMin = Int(profile.forceClickMin ?? GlassToKeySettings.forceClickMin)
            forceCap = Int(profile.forceClickCap)
            forceClickThreshold = Int(profile.forceClickThreshold)
            columnSettingsByLayout = profile.columnSettingsByLayout.reduce(into: [:]) { result, entry in
                result[portableLayoutName(fromMac: entry.key)] = entry.value
            }
            columnSettings = profile.columnSettingsByLayout[resolvedLayout.rawValue]
        }

        private enum CodingKeys: String, CodingKey {
            case activeLayer = "ActiveLayer"
            case layoutPresetName = "LayoutPresetName"
            case keyboardModeEnabled = "KeyboardModeEnabled"
            case holdRepeatEnabled = "HoldRepeatEnabled"
            case autocorrectEnabled = "AutocorrectEnabled"
            case shortcutActions = "ShortcutActions"
            case threeFingerTapAction = "ThreeFingerTapAction"
            case fiveFingerSwipeLeftAction = "FiveFingerSwipeLeftAction"
            case fiveFingerSwipeRightAction = "FiveFingerSwipeRightAction"
            case fiveFingerSwipeUpAction = "FiveFingerSwipeUpAction"
            case fiveFingerSwipeDownAction = "FiveFingerSwipeDownAction"
            case threeFingerSwipeLeftAction = "ThreeFingerSwipeLeftAction"
            case threeFingerSwipeRightAction = "ThreeFingerSwipeRightAction"
            case threeFingerSwipeUpAction = "ThreeFingerSwipeUpAction"
            case threeFingerSwipeDownAction = "ThreeFingerSwipeDownAction"
            case fourFingerSwipeLeftAction = "FourFingerSwipeLeftAction"
            case fourFingerSwipeRightAction = "FourFingerSwipeRightAction"
            case fourFingerSwipeUpAction = "FourFingerSwipeUpAction"
            case fourFingerSwipeDownAction = "FourFingerSwipeDownAction"
            case twoFingerHoldAction = "TwoFingerHoldAction"
            case threeFingerHoldAction = "ThreeFingerHoldAction"
            case fourFingerHoldAction = "FourFingerHoldAction"
            case leftEdgeUpAction = "LeftEdgeUpAction"
            case leftEdgeDownAction = "LeftEdgeDownAction"
            case rightEdgeUpAction = "RightEdgeUpAction"
            case rightEdgeDownAction = "RightEdgeDownAction"
            case topEdgeLeftAction = "TopEdgeLeftAction"
            case topEdgeRightAction = "TopEdgeRightAction"
            case bottomEdgeLeftAction = "BottomEdgeLeftAction"
            case bottomEdgeRightAction = "BottomEdgeRightAction"
            case threeFingerClickAction = "ThreeFingerClickAction"
            case fourFingerClickAction = "FourFingerClickAction"
            case outerCornersAction = "OuterCornersAction"
            case innerCornersAction = "InnerCornersAction"
            case topLeftCornerSwipeAction = "TopLeftCornerSwipeAction"
            case topRightCornerSwipeAction = "TopRightCornerSwipeAction"
            case bottomLeftCornerSwipeAction = "BottomLeftCornerSwipeAction"
            case bottomRightCornerSwipeAction = "BottomRightCornerSwipeAction"
            case topLeftTriangleAction = "TopLeftTriangleAction"
            case topRightTriangleAction = "TopRightTriangleAction"
            case bottomLeftTriangleAction = "BottomLeftTriangleAction"
            case bottomRightTriangleAction = "BottomRightTriangleAction"
            case upperLeftCornerClickAction = "UpperLeftCornerClickAction"
            case upperRightCornerClickAction = "UpperRightCornerClickAction"
            case lowerLeftCornerClickAction = "LowerLeftCornerClickAction"
            case lowerRightCornerClickAction = "LowerRightCornerClickAction"
            case topLeftForceClickAction = "TopLeftForceClickAction"
            case topRightForceClickAction = "TopRightForceClickAction"
            case bottomLeftForceClickAction = "BottomLeftForceClickAction"
            case bottomRightForceClickAction = "BottomRightForceClickAction"
            case holdDurationMs = "HoldDurationMs"
            case dragCancelMm = "DragCancelMm"
            case intentMoveMm = "IntentMoveMm"
            case intentVelocityMmPerSec = "IntentVelocityMmPerSec"
            case snapRadiusPercent = "SnapRadiusPercent"
            case gestureRepeatCadenceMsById = "GestureRepeatCadenceMsById"
            case keyPaddingPercent = "KeyPaddingPercent"
            case keyPaddingPercentByLayout = "KeyPaddingPercentByLayout"
            case forceMin = "ForceMin"
            case forceCap = "ForceCap"
            case forceClickThreshold = "ForceClickThreshold"
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
        var holdForceThreshold: Int?

        private enum CodingKeys: String, CodingKey {
            case primary = "Primary"
            case hold = "Hold"
            case holdForceThreshold = "HoldForceThreshold"
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
        var holdForceThreshold: Int?
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
            case holdForceThreshold = "HoldForceThreshold"
            case layer = "Layer"
        }

        init(
            id: String,
            side: TrackpadSide,
            rect: PortableNormalizedRect,
            primary: PortableKeyAction,
            hold: PortableKeyAction?,
            holdForceThreshold: Int,
            layer: Int
        ) {
            self.id = id
            self.side = PortableTrackpadSideValue.trackpadSide(side)
            self.rect = rect
            self.primary = primary
            self.hold = hold
            self.holdForceThreshold = hold == nil ? 0 : KeyMapping.normalizedHoldForceThreshold(holdForceThreshold)
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
