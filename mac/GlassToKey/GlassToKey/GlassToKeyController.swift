import OpenMultitouchSupport
import SwiftUI

enum GlassToKeySettings {
    static let tapHoldDurationMs: Double = 220.0
    static let dragCancelDistanceMm: Double = 8.0
    static let forceClickCap: Double = 120.0
    static let hapticStrengthPercent: Double = 40.0
    static let typingGraceMs: Double = 1000.0
    static let intentMoveThresholdMm: Double = 3.0
    static let intentVelocityThresholdMmPerSec: Double = 50.0
    static let autocorrectEnabled: Bool = true
    static let autocorrectMinWordLength: Int = 2
    static let tapClickEnabled: Bool = true
    static let tapClickCadenceMs: Double = 280.0
    static let snapRadiusPercent: Double = 35.0
    static let chordalShiftEnabled: Bool = true
    static let keyboardModeEnabled: Bool = false

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
        viewModel.onAppear()
        isRunning = true
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

        let keyMappings = loadKeyMappings()
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

    private func loadKeyMappings() -> LayeredKeyMappings {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: GlassToKeyDefaultsKeys.keyMappings),
           let mappings = KeyActionMappingStore.decodeNormalized(data) {
            return mappings
        }
        return [0: [:], 1: [:]]
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
        let tapClickEnabled = defaults.object(
            forKey: GlassToKeyDefaultsKeys.tapClickEnabled
        ) as? Bool ?? GlassToKeySettings.tapClickEnabled
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

        viewModel.updateHoldThreshold(tapHoldMs / 1000.0)
        viewModel.updateDragCancelDistance(CGFloat(dragDistance))
        viewModel.updateForceClickCap(forceCap)
        viewModel.updateHapticStrength(hapticStrengthPercent / 100.0)
        viewModel.updateTypingGraceMs(typingGraceMs)
        viewModel.updateIntentMoveThresholdMm(intentMoveThresholdMm)
        viewModel.updateIntentVelocityThresholdMmPerSec(intentVelocityThresholdMmPerSec)
        viewModel.updateAllowMouseTakeover(true)
        viewModel.updateTapClickEnabled(tapClickEnabled)
        viewModel.updateTapClickCadenceMs(tapClickCadenceMs)
        viewModel.updateSnapRadiusPercent(snapRadiusPercent)
        viewModel.updateChordalShiftEnabled(chordalShiftEnabled)
        viewModel.updateKeyboardModeEnabled(keyboardModeEnabled)
    }

    private func stringValue(forKey key: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? ""
    }
}
