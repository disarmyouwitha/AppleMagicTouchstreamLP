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

@MainActor
final class GlassToKeyController: ObservableObject {
    private static let portableBundledDefaultKeys: [String] = [
        GlassToKeyDefaultsKeys.layoutPreset,
        GlassToKeyDefaultsKeys.autoResyncMissingTrackpads,
        GlassToKeyDefaultsKeys.tapHoldDuration,
        GlassToKeyDefaultsKeys.dragCancelDistance,
        GlassToKeyDefaultsKeys.forceClickMin,
        GlassToKeyDefaultsKeys.forceClickCap,
        GlassToKeyDefaultsKeys.hapticStrength,
        GlassToKeyDefaultsKeys.typingGraceMs,
        GlassToKeyDefaultsKeys.intentMoveThresholdMm,
        GlassToKeyDefaultsKeys.intentVelocityThresholdMmPerSec,
        GlassToKeyDefaultsKeys.autocorrectEnabled,
        GlassToKeyDefaultsKeys.tapClickCadenceMs,
        GlassToKeyDefaultsKeys.snapRadiusPercent,
        GlassToKeyDefaultsKeys.keyboardModeEnabled,
        GlassToKeyDefaultsKeys.holdRepeatEnabled,
        GlassToKeyDefaultsKeys.twoFingerTapGestureAction,
        GlassToKeyDefaultsKeys.threeFingerTapGestureAction,
        GlassToKeyDefaultsKeys.twoFingerHoldGestureAction,
        GlassToKeyDefaultsKeys.threeFingerHoldGestureAction,
        GlassToKeyDefaultsKeys.fourFingerHoldGestureAction,
        GlassToKeyDefaultsKeys.outerCornersHoldGestureAction,
        GlassToKeyDefaultsKeys.innerCornersHoldGestureAction,
        GlassToKeyDefaultsKeys.leftEdgeUpGestureAction,
        GlassToKeyDefaultsKeys.leftEdgeDownGestureAction,
        GlassToKeyDefaultsKeys.rightEdgeUpGestureAction,
        GlassToKeyDefaultsKeys.rightEdgeDownGestureAction,
        GlassToKeyDefaultsKeys.topEdgeLeftGestureAction,
        GlassToKeyDefaultsKeys.topEdgeRightGestureAction,
        GlassToKeyDefaultsKeys.bottomEdgeLeftGestureAction,
        GlassToKeyDefaultsKeys.bottomEdgeRightGestureAction,
        GlassToKeyDefaultsKeys.threeFingerSwipeLeftGestureAction,
        GlassToKeyDefaultsKeys.threeFingerSwipeRightGestureAction,
        GlassToKeyDefaultsKeys.threeFingerSwipeUpGestureAction,
        GlassToKeyDefaultsKeys.threeFingerSwipeDownGestureAction,
        GlassToKeyDefaultsKeys.fourFingerSwipeLeftGestureAction,
        GlassToKeyDefaultsKeys.fourFingerSwipeRightGestureAction,
        GlassToKeyDefaultsKeys.fourFingerSwipeUpGestureAction,
        GlassToKeyDefaultsKeys.fourFingerSwipeDownGestureAction,
        GlassToKeyDefaultsKeys.fiveFingerSwipeLeftGestureAction,
        GlassToKeyDefaultsKeys.fiveFingerSwipeRightGestureAction,
        GlassToKeyDefaultsKeys.fiveFingerSwipeUpGestureAction,
        GlassToKeyDefaultsKeys.fiveFingerSwipeDownGestureAction,
        GlassToKeyDefaultsKeys.topLeftCornerSwipeGestureAction,
        GlassToKeyDefaultsKeys.topRightCornerSwipeGestureAction,
        GlassToKeyDefaultsKeys.bottomLeftCornerSwipeGestureAction,
        GlassToKeyDefaultsKeys.bottomRightCornerSwipeGestureAction,
        GlassToKeyDefaultsKeys.topLeftTriangleGestureAction,
        GlassToKeyDefaultsKeys.topRightTriangleGestureAction,
        GlassToKeyDefaultsKeys.bottomLeftTriangleGestureAction,
        GlassToKeyDefaultsKeys.bottomRightTriangleGestureAction,
        GlassToKeyDefaultsKeys.upperLeftCornerClickGestureAction,
        GlassToKeyDefaultsKeys.upperRightCornerClickGestureAction,
        GlassToKeyDefaultsKeys.lowerLeftCornerClickGestureAction,
        GlassToKeyDefaultsKeys.lowerRightCornerClickGestureAction,
        GlassToKeyDefaultsKeys.threeFingerClickGestureAction,
        GlassToKeyDefaultsKeys.fourFingerClickGestureAction,
        GlassToKeyDefaultsKeys.topLeftForceClickGestureAction,
        GlassToKeyDefaultsKeys.topRightForceClickGestureAction,
        GlassToKeyDefaultsKeys.bottomLeftForceClickGestureAction,
        GlassToKeyDefaultsKeys.bottomRightForceClickGestureAction,
        GlassToKeyDefaultsKeys.gestureRepeatCadenceMsById,
        GlassToKeyDefaultsKeys.keySpacingByLayout,
        GlassToKeyDefaultsKeys.columnSettings,
        GlassToKeyDefaultsKeys.customButtons,
        GlassToKeyDefaultsKeys.keyMappings,
        GlassToKeyDefaultsKeys.keyGeometry
    ]

    let viewModel: ContentViewModel
    private var isRunning = false

    init(viewModel: ContentViewModel = ContentViewModel()) {
        self.viewModel = viewModel
    }

    static func seedBundledDefaultsIfNeeded(defaults: UserDefaults = .standard) {
        guard !hasPortableBundledDefaults(defaults: defaults) else { return }
        guard let profile = bundledDefaultProfile() else { return }

        defaults.set(profile.layoutPreset, forKey: GlassToKeyDefaultsKeys.layoutPreset)
        defaults.set(profile.autoResyncMissingTrackpads, forKey: GlassToKeyDefaultsKeys.autoResyncMissingTrackpads)
        defaults.set(profile.tapHoldDurationMs, forKey: GlassToKeyDefaultsKeys.tapHoldDuration)
        defaults.set(profile.dragCancelDistance, forKey: GlassToKeyDefaultsKeys.dragCancelDistance)
        if let forceClickMin = profile.forceClickMin {
            defaults.set(forceClickMin, forKey: GlassToKeyDefaultsKeys.forceClickMin)
        }
        defaults.set(profile.forceClickCap, forKey: GlassToKeyDefaultsKeys.forceClickCap)
        defaults.set(profile.hapticStrength, forKey: GlassToKeyDefaultsKeys.hapticStrength)
        defaults.set(profile.typingGraceMs, forKey: GlassToKeyDefaultsKeys.typingGraceMs)
        defaults.set(profile.intentMoveThresholdMm, forKey: GlassToKeyDefaultsKeys.intentMoveThresholdMm)
        defaults.set(profile.intentVelocityThresholdMmPerSec, forKey: GlassToKeyDefaultsKeys.intentVelocityThresholdMmPerSec)
        defaults.set(profile.autocorrectEnabled, forKey: GlassToKeyDefaultsKeys.autocorrectEnabled)
        defaults.set(profile.tapClickCadenceMs, forKey: GlassToKeyDefaultsKeys.tapClickCadenceMs)
        defaults.set(profile.snapRadiusPercent, forKey: GlassToKeyDefaultsKeys.snapRadiusPercent)
        defaults.set(profile.keyboardModeEnabled, forKey: GlassToKeyDefaultsKeys.keyboardModeEnabled)
        defaults.set(profile.holdRepeatEnabled, forKey: GlassToKeyDefaultsKeys.holdRepeatEnabled)
        defaults.set(profile.twoFingerTapGestureAction, forKey: GlassToKeyDefaultsKeys.twoFingerTapGestureAction)
        defaults.set(profile.threeFingerTapGestureAction, forKey: GlassToKeyDefaultsKeys.threeFingerTapGestureAction)
        defaults.set(profile.twoFingerHoldGestureAction, forKey: GlassToKeyDefaultsKeys.twoFingerHoldGestureAction)
        defaults.set(profile.threeFingerHoldGestureAction, forKey: GlassToKeyDefaultsKeys.threeFingerHoldGestureAction)
        defaults.set(profile.fourFingerHoldGestureAction, forKey: GlassToKeyDefaultsKeys.fourFingerHoldGestureAction)
        defaults.set(profile.outerCornersHoldGestureAction, forKey: GlassToKeyDefaultsKeys.outerCornersHoldGestureAction)
        defaults.set(profile.innerCornersHoldGestureAction, forKey: GlassToKeyDefaultsKeys.innerCornersHoldGestureAction)
        defaults.set(profile.leftEdgeUpGestureAction, forKey: GlassToKeyDefaultsKeys.leftEdgeUpGestureAction)
        defaults.set(profile.leftEdgeDownGestureAction, forKey: GlassToKeyDefaultsKeys.leftEdgeDownGestureAction)
        defaults.set(profile.rightEdgeUpGestureAction, forKey: GlassToKeyDefaultsKeys.rightEdgeUpGestureAction)
        defaults.set(profile.rightEdgeDownGestureAction, forKey: GlassToKeyDefaultsKeys.rightEdgeDownGestureAction)
        defaults.set(profile.topEdgeLeftGestureAction, forKey: GlassToKeyDefaultsKeys.topEdgeLeftGestureAction)
        defaults.set(profile.topEdgeRightGestureAction, forKey: GlassToKeyDefaultsKeys.topEdgeRightGestureAction)
        defaults.set(profile.bottomEdgeLeftGestureAction, forKey: GlassToKeyDefaultsKeys.bottomEdgeLeftGestureAction)
        defaults.set(profile.bottomEdgeRightGestureAction, forKey: GlassToKeyDefaultsKeys.bottomEdgeRightGestureAction)
        defaults.set(profile.threeFingerSwipeLeftGestureAction, forKey: GlassToKeyDefaultsKeys.threeFingerSwipeLeftGestureAction)
        defaults.set(profile.threeFingerSwipeRightGestureAction, forKey: GlassToKeyDefaultsKeys.threeFingerSwipeRightGestureAction)
        defaults.set(profile.threeFingerSwipeUpGestureAction, forKey: GlassToKeyDefaultsKeys.threeFingerSwipeUpGestureAction)
        defaults.set(profile.threeFingerSwipeDownGestureAction, forKey: GlassToKeyDefaultsKeys.threeFingerSwipeDownGestureAction)
        defaults.set(profile.fourFingerSwipeLeftGestureAction, forKey: GlassToKeyDefaultsKeys.fourFingerSwipeLeftGestureAction)
        defaults.set(profile.fourFingerSwipeRightGestureAction, forKey: GlassToKeyDefaultsKeys.fourFingerSwipeRightGestureAction)
        defaults.set(profile.fourFingerSwipeUpGestureAction, forKey: GlassToKeyDefaultsKeys.fourFingerSwipeUpGestureAction)
        defaults.set(profile.fourFingerSwipeDownGestureAction, forKey: GlassToKeyDefaultsKeys.fourFingerSwipeDownGestureAction)
        defaults.set(profile.fiveFingerSwipeLeftGestureAction, forKey: GlassToKeyDefaultsKeys.fiveFingerSwipeLeftGestureAction)
        defaults.set(profile.fiveFingerSwipeRightGestureAction, forKey: GlassToKeyDefaultsKeys.fiveFingerSwipeRightGestureAction)
        defaults.set(profile.fiveFingerSwipeUpGestureAction, forKey: GlassToKeyDefaultsKeys.fiveFingerSwipeUpGestureAction)
        defaults.set(profile.fiveFingerSwipeDownGestureAction, forKey: GlassToKeyDefaultsKeys.fiveFingerSwipeDownGestureAction)
        defaults.set(profile.topLeftCornerSwipeGestureAction, forKey: GlassToKeyDefaultsKeys.topLeftCornerSwipeGestureAction)
        defaults.set(profile.topRightCornerSwipeGestureAction, forKey: GlassToKeyDefaultsKeys.topRightCornerSwipeGestureAction)
        defaults.set(profile.bottomLeftCornerSwipeGestureAction, forKey: GlassToKeyDefaultsKeys.bottomLeftCornerSwipeGestureAction)
        defaults.set(profile.bottomRightCornerSwipeGestureAction, forKey: GlassToKeyDefaultsKeys.bottomRightCornerSwipeGestureAction)
        defaults.set(profile.topLeftTriangleGestureAction, forKey: GlassToKeyDefaultsKeys.topLeftTriangleGestureAction)
        defaults.set(profile.topRightTriangleGestureAction, forKey: GlassToKeyDefaultsKeys.topRightTriangleGestureAction)
        defaults.set(profile.bottomLeftTriangleGestureAction, forKey: GlassToKeyDefaultsKeys.bottomLeftTriangleGestureAction)
        defaults.set(profile.bottomRightTriangleGestureAction, forKey: GlassToKeyDefaultsKeys.bottomRightTriangleGestureAction)
        defaults.set(profile.upperLeftCornerClickGestureAction, forKey: GlassToKeyDefaultsKeys.upperLeftCornerClickGestureAction)
        defaults.set(profile.upperRightCornerClickGestureAction, forKey: GlassToKeyDefaultsKeys.upperRightCornerClickGestureAction)
        defaults.set(profile.lowerLeftCornerClickGestureAction, forKey: GlassToKeyDefaultsKeys.lowerLeftCornerClickGestureAction)
        defaults.set(profile.lowerRightCornerClickGestureAction, forKey: GlassToKeyDefaultsKeys.lowerRightCornerClickGestureAction)
        defaults.set(profile.threeFingerClickGestureAction, forKey: GlassToKeyDefaultsKeys.threeFingerClickGestureAction)
        defaults.set(profile.fourFingerClickGestureAction, forKey: GlassToKeyDefaultsKeys.fourFingerClickGestureAction)
        defaults.set(profile.topLeftForceClickGestureAction, forKey: GlassToKeyDefaultsKeys.topLeftForceClickGestureAction)
        defaults.set(profile.topRightForceClickGestureAction, forKey: GlassToKeyDefaultsKeys.topRightForceClickGestureAction)
        defaults.set(profile.bottomLeftForceClickGestureAction, forKey: GlassToKeyDefaultsKeys.bottomLeftForceClickGestureAction)
        defaults.set(profile.bottomRightForceClickGestureAction, forKey: GlassToKeyDefaultsKeys.bottomRightForceClickGestureAction)
        if let encodedGestureRepeatCadence = GestureRepeatCadenceStorage.encode(
            profile.gestureRepeatCadenceMsById
        ) {
            defaults.set(encodedGestureRepeatCadence, forKey: GlassToKeyDefaultsKeys.gestureRepeatCadenceMsById)
        }
        if let encodedKeySpacing = LayoutKeySpacingStorage.encode(
            profile.keySpacingPercentByLayout ?? [:]
        ) {
            defaults.set(encodedKeySpacing, forKey: GlassToKeyDefaultsKeys.keySpacingByLayout)
        }

        if let encodedColumns = LayoutColumnSettingsStorage.encode(profile.columnSettingsByLayout) {
            defaults.set(encodedColumns, forKey: GlassToKeyDefaultsKeys.columnSettings)
        }
        if let encodedButtons = LayoutCustomButtonStorage.encode(profile.customButtonsByLayout) {
            defaults.set(encodedButtons, forKey: GlassToKeyDefaultsKeys.customButtons)
        }
        if let keyMappings = profile.keyMappingsByLayout,
           let encodedMappings = KeyActionMappingStore.encode(KeyActionMappingStore.normalized(keyMappings)) {
            defaults.set(encodedMappings, forKey: GlassToKeyDefaultsKeys.keyMappings)
        }
        if let keyGeometry = profile.keyGeometryByLayout,
           let encodedGeometry = KeyGeometryStore.encode(KeyGeometryStore.normalized(keyGeometry)) {
            defaults.set(encodedGeometry, forKey: GlassToKeyDefaultsKeys.keyGeometry)
        }
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

    private static func hasPortableBundledDefaults(defaults: UserDefaults) -> Bool {
        for key in portableBundledDefaultKeys {
            if defaults.object(forKey: key) != nil {
                return true
            }
        }
        return false
    }

    private static func bundledDefaultProfile() -> AppKeymapProfile? {
        guard let url = Bundle.main.url(
            forResource: "GLASSTOKEY_DEFAULT_KEYMAP",
            withExtension: "json"
        ) else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return PortableKeymapInterop.decodeBundledDefaultProfile(from: data)
    }

    private func configureFromDefaults() {
        viewModel.loadDevices()
        let layout = resolvedLayoutPreset()
        let columnSettings = resolvedColumnSettings(for: layout)
        let keySpacingPercent = resolvedKeySpacingPercent(for: layout)
        let keyGeometryOverrides = loadKeyGeometryOverrides(for: layout)

        let trackpadSize = CGSize(
            width: ContentView.trackpadWidthMM * ContentView.displayScale,
            height: ContentView.trackpadHeightMM * ContentView.displayScale
        )

        let leftLayout: ContentViewModel.Layout
        let rightLayout: ContentViewModel.Layout
        if layout == .mobile {
            leftLayout = ContentViewModel.Layout(keyRects: [], trackpadSize: trackpadSize)
            rightLayout = ContentView.makeMobileKeyLayout(
                size: trackpadSize,
                keyGeometryOverrides: keyGeometryOverrides
            )
        } else if layout.columns > 0, layout.rows > 0 {
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
                keySpacingPercent: keySpacingPercent,
                keyGeometryOverrides: keyGeometryOverrides,
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
                columnSettings: columnSettings,
                keySpacingPercent: keySpacingPercent,
                keyGeometryOverrides: keyGeometryOverrides
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
        if let bundled = bundledDefaultCustomButtons()?[layout.rawValue] {
            return bundled[viewModel.activeLayer] ?? []
        }
        return []
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
        guard let profile = Self.bundledDefaultProfile() else { return nil }
        if let byLayout = profile.keyMappingsByLayout {
            return KeyActionMappingStore.normalized(byLayout)
        }
        return nil
    }

    private func loadKeyGeometryOverrides(for layout: TrackpadLayoutPreset) -> KeyGeometryOverrides {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: GlassToKeyDefaultsKeys.keyGeometry),
           let overridesByLayout = KeyGeometryStore.decodeLayoutNormalized(data) {
            return overridesByLayout[layout.rawValue] ?? [:]
        }
        if let bundled = bundledDefaultKeyGeometry() {
            return bundled[layout.rawValue] ?? [:]
        }
        return [:]
    }

    private func bundledDefaultKeyGeometry() -> LayoutKeyGeometryOverrides? {
        guard let profile = Self.bundledDefaultProfile() else { return nil }
        if let byLayout = profile.keyGeometryByLayout {
            return KeyGeometryStore.normalized(byLayout)
        }
        return nil
    }

    private func bundledDefaultCustomButtons() -> [String: [Int: [CustomButton]]]? {
        Self.bundledDefaultProfile()?.customButtonsByLayout
    }

    private func resolvedLayoutPreset() -> TrackpadLayoutPreset {
        let stored = UserDefaults.standard.string(forKey: GlassToKeyDefaultsKeys.layoutPreset)
        return TrackpadLayoutPreset.resolveByNameOrDefault(stored)
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

    private func resolvedKeySpacingPercent(
        for layout: TrackpadLayoutPreset
    ) -> Double {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: GlassToKeyDefaultsKeys.keySpacingByLayout) else {
            return LayoutKeySpacingDefaults.defaultPercent
        }
        return LayoutKeySpacingStorage.keySpacingPercent(for: layout, from: data)
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
        let keyboardModeEnabled = defaults.object(
            forKey: GlassToKeyDefaultsKeys.keyboardModeEnabled
        ) as? Bool ?? GlassToKeySettings.keyboardModeEnabled
        let holdRepeatEnabled = defaults.object(
            forKey: GlassToKeyDefaultsKeys.holdRepeatEnabled
        ) as? Bool ?? GlassToKeySettings.holdRepeatEnabled
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
        viewModel.updateKeyboardModeEnabled(keyboardModeEnabled)
        viewModel.updateHoldRepeatEnabled(holdRepeatEnabled)
        viewModel.updateGestureActions(resolvedGestureActions(from: defaults))
    }

    private func stringValue(forKey key: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? ""
    }

    private func resolvedGestureAction(
        from defaults: UserDefaults,
        key: String,
        fallbackLabel: String
    ) -> KeyAction {
        let label = defaults.string(forKey: key) ?? fallbackLabel
        return KeyActionCatalog.action(for: label)
            ?? KeyActionCatalog.action(for: fallbackLabel)
            ?? KeyActionCatalog.noneAction
    }

    private func resolvedGestureActions(from defaults: UserDefaults) -> GestureActionSet {
        GestureActionSet(
            twoFingerTap: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.twoFingerTapGestureAction, fallbackLabel: GlassToKeySettings.twoFingerTapGestureActionLabel),
            threeFingerTap: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.threeFingerTapGestureAction, fallbackLabel: GlassToKeySettings.threeFingerTapGestureActionLabel),
            twoFingerHold: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.twoFingerHoldGestureAction, fallbackLabel: GlassToKeySettings.twoFingerHoldGestureActionLabel),
            threeFingerHold: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.threeFingerHoldGestureAction, fallbackLabel: GlassToKeySettings.threeFingerHoldGestureActionLabel),
            fourFingerHold: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.fourFingerHoldGestureAction, fallbackLabel: GlassToKeySettings.fourFingerHoldGestureActionLabel),
            outerCornersHold: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.outerCornersHoldGestureAction, fallbackLabel: GlassToKeySettings.outerCornersHoldGestureActionLabel),
            innerCornersHold: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.innerCornersHoldGestureAction, fallbackLabel: GlassToKeySettings.innerCornersHoldGestureActionLabel),
            leftEdgeUp: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.leftEdgeUpGestureAction, fallbackLabel: GlassToKeySettings.leftEdgeUpGestureActionLabel),
            leftEdgeDown: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.leftEdgeDownGestureAction, fallbackLabel: GlassToKeySettings.leftEdgeDownGestureActionLabel),
            rightEdgeUp: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.rightEdgeUpGestureAction, fallbackLabel: GlassToKeySettings.rightEdgeUpGestureActionLabel),
            rightEdgeDown: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.rightEdgeDownGestureAction, fallbackLabel: GlassToKeySettings.rightEdgeDownGestureActionLabel),
            topEdgeLeft: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.topEdgeLeftGestureAction, fallbackLabel: GlassToKeySettings.topEdgeLeftGestureActionLabel),
            topEdgeRight: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.topEdgeRightGestureAction, fallbackLabel: GlassToKeySettings.topEdgeRightGestureActionLabel),
            bottomEdgeLeft: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.bottomEdgeLeftGestureAction, fallbackLabel: GlassToKeySettings.bottomEdgeLeftGestureActionLabel),
            bottomEdgeRight: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.bottomEdgeRightGestureAction, fallbackLabel: GlassToKeySettings.bottomEdgeRightGestureActionLabel),
            threeFingerSwipeLeft: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.threeFingerSwipeLeftGestureAction, fallbackLabel: GlassToKeySettings.threeFingerSwipeLeftGestureActionLabel),
            threeFingerSwipeRight: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.threeFingerSwipeRightGestureAction, fallbackLabel: GlassToKeySettings.threeFingerSwipeRightGestureActionLabel),
            threeFingerSwipeUp: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.threeFingerSwipeUpGestureAction, fallbackLabel: GlassToKeySettings.threeFingerSwipeUpGestureActionLabel),
            threeFingerSwipeDown: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.threeFingerSwipeDownGestureAction, fallbackLabel: GlassToKeySettings.threeFingerSwipeDownGestureActionLabel),
            fourFingerSwipeLeft: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.fourFingerSwipeLeftGestureAction, fallbackLabel: GlassToKeySettings.fourFingerSwipeLeftGestureActionLabel),
            fourFingerSwipeRight: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.fourFingerSwipeRightGestureAction, fallbackLabel: GlassToKeySettings.fourFingerSwipeRightGestureActionLabel),
            fourFingerSwipeUp: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.fourFingerSwipeUpGestureAction, fallbackLabel: GlassToKeySettings.fourFingerSwipeUpGestureActionLabel),
            fourFingerSwipeDown: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.fourFingerSwipeDownGestureAction, fallbackLabel: GlassToKeySettings.fourFingerSwipeDownGestureActionLabel),
            fiveFingerSwipeLeft: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.fiveFingerSwipeLeftGestureAction, fallbackLabel: GlassToKeySettings.fiveFingerSwipeLeftGestureActionLabel),
            fiveFingerSwipeRight: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.fiveFingerSwipeRightGestureAction, fallbackLabel: GlassToKeySettings.fiveFingerSwipeRightGestureActionLabel),
            fiveFingerSwipeUp: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.fiveFingerSwipeUpGestureAction, fallbackLabel: GlassToKeySettings.fiveFingerSwipeUpGestureActionLabel),
            fiveFingerSwipeDown: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.fiveFingerSwipeDownGestureAction, fallbackLabel: GlassToKeySettings.fiveFingerSwipeDownGestureActionLabel),
            topLeftCornerSwipe: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.topLeftCornerSwipeGestureAction, fallbackLabel: GlassToKeySettings.topLeftCornerSwipeGestureActionLabel),
            topRightCornerSwipe: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.topRightCornerSwipeGestureAction, fallbackLabel: GlassToKeySettings.topRightCornerSwipeGestureActionLabel),
            bottomLeftCornerSwipe: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.bottomLeftCornerSwipeGestureAction, fallbackLabel: GlassToKeySettings.bottomLeftCornerSwipeGestureActionLabel),
            bottomRightCornerSwipe: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.bottomRightCornerSwipeGestureAction, fallbackLabel: GlassToKeySettings.bottomRightCornerSwipeGestureActionLabel),
            topLeftTriangle: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.topLeftTriangleGestureAction, fallbackLabel: GlassToKeySettings.topLeftTriangleGestureActionLabel),
            topRightTriangle: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.topRightTriangleGestureAction, fallbackLabel: GlassToKeySettings.topRightTriangleGestureActionLabel),
            bottomLeftTriangle: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.bottomLeftTriangleGestureAction, fallbackLabel: GlassToKeySettings.bottomLeftTriangleGestureActionLabel),
            bottomRightTriangle: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.bottomRightTriangleGestureAction, fallbackLabel: GlassToKeySettings.bottomRightTriangleGestureActionLabel),
            upperLeftCornerClick: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.upperLeftCornerClickGestureAction, fallbackLabel: GlassToKeySettings.upperLeftCornerClickGestureActionLabel),
            upperRightCornerClick: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.upperRightCornerClickGestureAction, fallbackLabel: GlassToKeySettings.upperRightCornerClickGestureActionLabel),
            lowerLeftCornerClick: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.lowerLeftCornerClickGestureAction, fallbackLabel: GlassToKeySettings.lowerLeftCornerClickGestureActionLabel),
            lowerRightCornerClick: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.lowerRightCornerClickGestureAction, fallbackLabel: GlassToKeySettings.lowerRightCornerClickGestureActionLabel),
            threeFingerClick: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.threeFingerClickGestureAction, fallbackLabel: GlassToKeySettings.threeFingerClickGestureActionLabel),
            fourFingerClick: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.fourFingerClickGestureAction, fallbackLabel: GlassToKeySettings.fourFingerClickGestureActionLabel),
            topLeftForceClick: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.topLeftForceClickGestureAction, fallbackLabel: GlassToKeySettings.topLeftForceClickGestureActionLabel),
            topRightForceClick: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.topRightForceClickGestureAction, fallbackLabel: GlassToKeySettings.topRightForceClickGestureActionLabel),
            bottomLeftForceClick: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.bottomLeftForceClickGestureAction, fallbackLabel: GlassToKeySettings.bottomLeftForceClickGestureActionLabel),
            bottomRightForceClick: resolvedGestureAction(from: defaults, key: GlassToKeyDefaultsKeys.bottomRightForceClickGestureAction, fallbackLabel: GlassToKeySettings.bottomRightForceClickGestureActionLabel)
        )
    }
}
