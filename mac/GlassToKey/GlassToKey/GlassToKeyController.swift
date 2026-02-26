import OpenMultitouchSupport
import SwiftUI

enum GlassToKeySettings {
    static let tapHoldDurationMs: Double = 220.0
    static let dragCancelDistanceMm: Double = 8.0
    static let forceClickMin: Double = 0.0
    static let forceClickCap: Double = 120.0
    static let hapticStrengthPercent: Double = 40.0
    static let typingGraceMs: Double = 1000.0
    static let intentMoveThresholdMm: Double = 3.0
    static let intentVelocityThresholdMmPerSec: Double = 50.0
    static let autocorrectEnabled: Bool = true
    static let autocorrectMinWordLength: Int = 2
    static let tapClickCadenceMs: Double = 280.0
    static let snapRadiusPercent: Double = 35.0
    static let chordalShiftEnabled: Bool = true
    static let keyboardModeEnabled: Bool = false
    static let runAtStartupEnabled: Bool = false
    static let twoFingerTapGestureActionLabel = KeyActionCatalog.leftClickLabel
    static let threeFingerTapGestureActionLabel = KeyActionCatalog.rightClickLabel
    static let twoFingerHoldGestureActionLabel = KeyActionCatalog.noneLabel
    static let threeFingerHoldGestureActionLabel = KeyActionCatalog.noneLabel
    static let fourFingerHoldGestureActionLabel = KeyActionCatalog.chordalShiftLabel
    static let outerCornersHoldGestureActionLabel = KeyActionCatalog.voiceLabel
    static let innerCornersHoldGestureActionLabel = KeyActionCatalog.noneLabel
    static let fiveFingerSwipeLeftGestureActionLabel = KeyActionCatalog.typingToggleLabel
    static let fiveFingerSwipeRightGestureActionLabel = KeyActionCatalog.typingToggleLabel

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

@MainActor
final class GlassToKeyController: ObservableObject {
    private struct BundledKeymapProfile: Decodable {
        let keyMappingsByLayout: LayoutLayeredKeyMappings?
        let keyMappings: LayeredKeyMappings?
    }

    let viewModel: ContentViewModel
    private var isRunning = false

    init(viewModel: ContentViewModel = ContentViewModel()) {
        self.viewModel = viewModel
    }

    func start() {
        guard !isRunning else { return }
        OMSManager.shared.isTimestampEnabled = false
        configureFromDefaults()
        viewModel.start()
        isRunning = true
    }

    func startATPCapture(to outputURL: URL) throws {
        try viewModel.startATPCapture(to: outputURL)
    }

    func stopATPCapture() async throws -> Int {
        try await viewModel.stopATPCapture()
    }

    func replayATPCapture(from inputURL: URL) async throws -> Int {
        try await viewModel.replayATPCapture(from: inputURL)
    }

    func beginReplaySession(from inputURL: URL) async throws {
        try await viewModel.beginReplaySession(from: inputURL)
    }

    func endReplaySession() async {
        await viewModel.endReplaySession()
    }

    func scrubReplay(to timeSeconds: Double) async throws {
        try await viewModel.scrubReplay(to: timeSeconds)
    }

    func toggleReplayPlayback() {
        viewModel.toggleReplayPlayback()
    }

    var isATPCaptureActive: Bool {
        viewModel.isATPCaptureActive
    }

    var isATPReplayActive: Bool {
        viewModel.isATPReplayActive
    }

    private func configureFromDefaults() {
        viewModel.loadDevices()
        let layout = resolvedLayoutPreset()
        let columnSettings = resolvedColumnSettings(for: layout)

        let trackpadSize = CGSize(
            width: ContentView.trackpadWidthMM * ContentView.displayScale,
            height: ContentView.trackpadHeightMM * ContentView.displayScale
        )

        let leftLayout: ContentViewModel.Layout
        let rightLayout: ContentViewModel.Layout
        if layout.columns > 0, layout.rows > 0 {
            leftLayout = ContentView.makeKeyLayout(
                size: trackpadSize,
                keyWidth: ContentView.baseKeyWidthMM,
                keyHeight: ContentView.baseKeyHeightMM,
                columns: layout.columns,
                rows: layout.rows,
                trackpadWidth: ContentView.trackpadWidthMM,
                trackpadHeight: ContentView.trackpadHeightMM,
                columnAnchorsMM: layout.columnAnchors,
                columnSettings: columnSettings,
                mirrored: true
            )
            rightLayout = ContentView.makeKeyLayout(
                size: trackpadSize,
                keyWidth: ContentView.baseKeyWidthMM,
                keyHeight: ContentView.baseKeyHeightMM,
                columns: layout.columns,
                rows: layout.rows,
                trackpadWidth: ContentView.trackpadWidthMM,
                trackpadHeight: ContentView.trackpadHeightMM,
                columnAnchorsMM: layout.columnAnchors,
                columnSettings: columnSettings
            )
        } else {
            leftLayout = ContentViewModel.Layout(keyRects: [], trackpadSize: trackpadSize)
            rightLayout = ContentViewModel.Layout(keyRects: [], trackpadSize: trackpadSize)
        }

        viewModel.configureLayouts(
            leftLayout: leftLayout,
            rightLayout: rightLayout,
            leftLabels: layout.leftLabels,
            rightLabels: layout.rightLabels,
            trackpadSize: trackpadSize,
            trackpadWidthMm: ContentView.trackpadWidthMM
        )

        let customButtons = loadCustomButtons(for: layout)
        viewModel.updateCustomButtons(customButtons)

        let keyMappings = loadKeyMappings(for: layout)
        viewModel.updateKeyMappings(keyMappings)

        applySavedInteractionSettings()
        let autocorrectEnabled = UserDefaults.standard.bool(
            forKey: GlassToKeyDefaultsKeys.autocorrectEnabled
        )
        AutocorrectEngine.shared.setEnabled(autocorrectEnabled)
        AutocorrectEngine.shared.setMinimumWordLength(GlassToKeySettings.autocorrectMinWordLength)

        let leftDeviceID = stringValue(forKey: GlassToKeyDefaultsKeys.leftDeviceID)
        let rightDeviceID = stringValue(forKey: GlassToKeyDefaultsKeys.rightDeviceID)
        if let leftDevice = deviceForID(leftDeviceID) {
            viewModel.selectLeftDevice(leftDevice)
        }
        if let rightDevice = deviceForID(rightDeviceID) {
            viewModel.selectRightDevice(rightDevice)
        }
        let autoResyncEnabled = UserDefaults.standard.bool(
            forKey: GlassToKeyDefaultsKeys.autoResyncMissingTrackpads
        )
        viewModel.setAutoResyncEnabled(autoResyncEnabled)
    }

    private func deviceForID(_ deviceID: String) -> OMSDeviceInfo? {
        guard !deviceID.isEmpty else { return nil }
        return viewModel.availableDevices.first { $0.deviceID == deviceID }
    }

    private func loadCustomButtons(for layout: TrackpadLayoutPreset) -> [CustomButton] {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: GlassToKeyDefaultsKeys.customButtons) {
            if let stored = LayoutCustomButtonStorage.buttons(for: layout, from: data) {
                return stored
            }
        }
        return CustomButtonDefaults.defaultButtons(
            trackpadWidth: ContentView.trackpadWidthMM,
            trackpadHeight: ContentView.trackpadHeightMM,
            thumbAnchorsMM: ContentView.ThumbAnchorsMM
        )
    }

    private func loadKeyMappings(for layout: TrackpadLayoutPreset) -> LayeredKeyMappings {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: GlassToKeyDefaultsKeys.keyMappings),
           let mappingsByLayout = KeyActionMappingStore.decodeLayoutNormalized(data) {
            return mappingsByLayout[layout.rawValue] ?? KeyActionMappingStore.emptyMappings()
        }
        if let bundled = bundledDefaultKeyMappings() {
            return bundled[layout.rawValue] ?? KeyActionMappingStore.emptyMappings()
        }
        return KeyActionMappingStore.emptyMappings()
    }

    private func bundledDefaultKeyMappings() -> LayoutLayeredKeyMappings? {
        guard let url = Bundle.main.url(
            forResource: "GLASSTOKEY_DEFAULT_KEYMAP",
            withExtension: "json"
        ) else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let profile = try? JSONDecoder().decode(BundledKeymapProfile.self, from: data) else {
            return nil
        }
        if let byLayout = profile.keyMappingsByLayout {
            return KeyActionMappingStore.normalized(byLayout)
        }
        if let legacy = profile.keyMappings {
            return KeyActionMappingStore.legacyMappedAcrossLayouts(legacy)
        }
        return nil
    }

    private func resolvedLayoutPreset() -> TrackpadLayoutPreset {
        let stored = UserDefaults.standard.string(forKey: GlassToKeyDefaultsKeys.layoutPreset)
        return TrackpadLayoutPreset(rawValue: stored ?? "") ?? .sixByThree
    }

    private func resolvedColumnSettings(
        for layout: TrackpadLayoutPreset
    ) -> [ColumnLayoutSettings] {
        let defaults = UserDefaults.standard
        let columns = layout.columns
        if let data = defaults.data(forKey: GlassToKeyDefaultsKeys.columnSettings),
           let stored = LayoutColumnSettingsStorage.settings(
            for: layout,
            from: data
        ) {
            return ColumnLayoutDefaults.normalizedSettings(stored, columns: columns)
        }
        return ColumnLayoutDefaults.defaultSettings(columns: columns)
    }

    private func applySavedInteractionSettings() {
        let defaults = UserDefaults.standard
        let tapHoldMs = GlassToKeySettings.persistedDouble(
            forKey: GlassToKeyDefaultsKeys.tapHoldDuration,
            defaults: defaults,
            fallback: GlassToKeySettings.tapHoldDurationMs
        )
        let dragDistance = GlassToKeySettings.persistedDouble(
            forKey: GlassToKeyDefaultsKeys.dragCancelDistance,
            defaults: defaults,
            fallback: GlassToKeySettings.dragCancelDistanceMm
        )
        let forceCap = GlassToKeySettings.persistedDouble(
            forKey: GlassToKeyDefaultsKeys.forceClickCap,
            defaults: defaults,
            fallback: GlassToKeySettings.forceClickCap
        )
        let forceMin = GlassToKeySettings.persistedDouble(
            forKey: GlassToKeyDefaultsKeys.forceClickMin,
            defaults: defaults,
            fallback: GlassToKeySettings.forceClickMin
        )
        let hapticStrengthPercent = GlassToKeySettings.persistedDouble(
            forKey: GlassToKeyDefaultsKeys.hapticStrength,
            defaults: defaults,
            fallback: GlassToKeySettings.hapticStrengthPercent
        )
        let typingGraceMs = GlassToKeySettings.persistedDouble(
            forKey: GlassToKeyDefaultsKeys.typingGraceMs,
            defaults: defaults,
            fallback: GlassToKeySettings.typingGraceMs
        )
        let intentMoveThresholdMm = GlassToKeySettings.persistedDouble(
            forKey: GlassToKeyDefaultsKeys.intentMoveThresholdMm,
            defaults: defaults,
            fallback: GlassToKeySettings.intentMoveThresholdMm
        )
        let intentVelocityThresholdMmPerSec = GlassToKeySettings.persistedDouble(
            forKey: GlassToKeyDefaultsKeys.intentVelocityThresholdMmPerSec,
            defaults: defaults,
            fallback: GlassToKeySettings.intentVelocityThresholdMmPerSec
        )
        let tapClickCadenceMs = GlassToKeySettings.persistedDouble(
            forKey: GlassToKeyDefaultsKeys.tapClickCadenceMs,
            defaults: defaults,
            fallback: GlassToKeySettings.tapClickCadenceMs
        )
        let snapRadiusPercent = GlassToKeySettings.persistedDouble(
            forKey: GlassToKeyDefaultsKeys.snapRadiusPercent,
            defaults: defaults,
            fallback: GlassToKeySettings.snapRadiusPercent
        )
        let chordalShiftEnabled = defaults.object(
            forKey: GlassToKeyDefaultsKeys.chordalShiftEnabled
        ) as? Bool ?? GlassToKeySettings.chordalShiftEnabled
        let keyboardModeEnabled = defaults.object(
            forKey: GlassToKeyDefaultsKeys.keyboardModeEnabled
        ) as? Bool ?? GlassToKeySettings.keyboardModeEnabled
        let twoFingerTapGestureActionLabel = defaults.string(
            forKey: GlassToKeyDefaultsKeys.twoFingerTapGestureAction
        ) ?? GlassToKeySettings.twoFingerTapGestureActionLabel
        let threeFingerTapGestureActionLabel = defaults.string(
            forKey: GlassToKeyDefaultsKeys.threeFingerTapGestureAction
        ) ?? GlassToKeySettings.threeFingerTapGestureActionLabel
        let twoFingerHoldGestureActionLabel = defaults.string(
            forKey: GlassToKeyDefaultsKeys.twoFingerHoldGestureAction
        ) ?? GlassToKeySettings.twoFingerHoldGestureActionLabel
        let threeFingerHoldGestureActionLabel = defaults.string(
            forKey: GlassToKeyDefaultsKeys.threeFingerHoldGestureAction
        ) ?? GlassToKeySettings.threeFingerHoldGestureActionLabel
        let fourFingerHoldGestureActionLabel = defaults.string(
            forKey: GlassToKeyDefaultsKeys.fourFingerHoldGestureAction
        ) ?? GlassToKeySettings.fourFingerHoldGestureActionLabel
        let outerCornersHoldGestureActionLabel = defaults.string(
            forKey: GlassToKeyDefaultsKeys.outerCornersHoldGestureAction
        ) ?? GlassToKeySettings.outerCornersHoldGestureActionLabel
        let innerCornersHoldGestureActionLabel = defaults.string(
            forKey: GlassToKeyDefaultsKeys.innerCornersHoldGestureAction
        ) ?? GlassToKeySettings.innerCornersHoldGestureActionLabel
        let fiveFingerSwipeLeftGestureActionLabel = defaults.string(
            forKey: GlassToKeyDefaultsKeys.fiveFingerSwipeLeftGestureAction
        ) ?? GlassToKeySettings.fiveFingerSwipeLeftGestureActionLabel
        let fiveFingerSwipeRightGestureActionLabel = defaults.string(
            forKey: GlassToKeyDefaultsKeys.fiveFingerSwipeRightGestureAction
        ) ?? GlassToKeySettings.fiveFingerSwipeRightGestureActionLabel

        let twoFingerTapGestureAction = KeyActionCatalog.action(
            for: twoFingerTapGestureActionLabel
        ) ?? KeyActionCatalog.action(for: GlassToKeySettings.twoFingerTapGestureActionLabel) ?? KeyActionCatalog.noneAction
        let threeFingerTapGestureAction = KeyActionCatalog.action(
            for: threeFingerTapGestureActionLabel
        ) ?? KeyActionCatalog.action(for: GlassToKeySettings.threeFingerTapGestureActionLabel) ?? KeyActionCatalog.noneAction
        let twoFingerHoldGestureAction = KeyActionCatalog.action(
            for: twoFingerHoldGestureActionLabel
        ) ?? KeyActionCatalog.action(for: GlassToKeySettings.twoFingerHoldGestureActionLabel) ?? KeyActionCatalog.noneAction
        let threeFingerHoldGestureAction = KeyActionCatalog.action(
            for: threeFingerHoldGestureActionLabel
        ) ?? KeyActionCatalog.action(for: GlassToKeySettings.threeFingerHoldGestureActionLabel) ?? KeyActionCatalog.noneAction
        let fourFingerHoldGestureAction = KeyActionCatalog.action(
            for: fourFingerHoldGestureActionLabel
        ) ?? KeyActionCatalog.action(for: GlassToKeySettings.fourFingerHoldGestureActionLabel) ?? KeyActionCatalog.noneAction
        let outerCornersHoldGestureAction = KeyActionCatalog.action(
            for: outerCornersHoldGestureActionLabel
        ) ?? KeyActionCatalog.action(for: GlassToKeySettings.outerCornersHoldGestureActionLabel) ?? KeyActionCatalog.noneAction
        let innerCornersHoldGestureAction = KeyActionCatalog.action(
            for: innerCornersHoldGestureActionLabel
        ) ?? KeyActionCatalog.action(for: GlassToKeySettings.innerCornersHoldGestureActionLabel) ?? KeyActionCatalog.noneAction
        let fiveFingerSwipeLeftGestureAction = KeyActionCatalog.action(
            for: fiveFingerSwipeLeftGestureActionLabel
        ) ?? KeyActionCatalog.action(for: GlassToKeySettings.fiveFingerSwipeLeftGestureActionLabel) ?? KeyActionCatalog.noneAction
        let fiveFingerSwipeRightGestureAction = KeyActionCatalog.action(
            for: fiveFingerSwipeRightGestureActionLabel
        ) ?? KeyActionCatalog.action(for: GlassToKeySettings.fiveFingerSwipeRightGestureActionLabel) ?? KeyActionCatalog.noneAction

        viewModel.updateHoldThreshold(tapHoldMs / 1000.0)
        viewModel.updateDragCancelDistance(CGFloat(dragDistance))
        let clampedForceMin = max(0, min(255, forceMin))
        let clampedForceCap = max(clampedForceMin, min(255, forceCap))
        viewModel.updateForceClickMin(clampedForceMin)
        viewModel.updateForceClickCap(clampedForceCap)
        viewModel.updateHapticStrength(hapticStrengthPercent / 100.0)
        viewModel.updateTypingGraceMs(typingGraceMs)
        viewModel.updateIntentMoveThresholdMm(intentMoveThresholdMm)
        viewModel.updateIntentVelocityThresholdMmPerSec(intentVelocityThresholdMmPerSec)
        viewModel.updateAllowMouseTakeover(true)
        viewModel.updateTapClickCadenceMs(tapClickCadenceMs)
        viewModel.updateSnapRadiusPercent(snapRadiusPercent)
        viewModel.updateChordalShiftEnabled(chordalShiftEnabled)
        viewModel.updateKeyboardModeEnabled(keyboardModeEnabled)
        viewModel.updateGestureActions(
            twoFingerTap: twoFingerTapGestureAction,
            threeFingerTap: threeFingerTapGestureAction,
            twoFingerHold: twoFingerHoldGestureAction,
            threeFingerHold: threeFingerHoldGestureAction,
            fourFingerHold: fourFingerHoldGestureAction,
            outerCornersHold: outerCornersHoldGestureAction,
            innerCornersHold: innerCornersHoldGestureAction,
            fiveFingerSwipeLeft: fiveFingerSwipeLeftGestureAction,
            fiveFingerSwipeRight: fiveFingerSwipeRightGestureAction
        )
    }

    private func stringValue(forKey key: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? ""
    }
}
