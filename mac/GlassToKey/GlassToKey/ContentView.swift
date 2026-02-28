//
//  ContentView.swift
//  GlassToKey
//
//  Created by Takuto Nakamura on 2024/03/02.
//

import AppKit
import Combine
import OpenMultitouchSupport
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    private struct SelectedGridKey: Equatable {
        let row: Int
        let column: Int
        let label: String
        let side: TrackpadSide

        var position: GridKeyPosition {
            GridKeyPosition(side: side, row: row, column: column)
        }

        var storageKey: String {
            position.storageKey
        }
    }

    private struct GridLabel: Equatable {
        let primary: String
        let hold: String?
    }

    private struct ColumnInspectorSelection: Equatable {
        let index: Int
        var settings: ColumnLayoutSettings
    }

    private struct AutoSplayTouch {
        let xNorm: Double
        let yNorm: Double
    }

    private struct ButtonInspectorSelection: Equatable {
        var button: CustomButton
    }

    private struct KeyInspectorSelection: Equatable {
        let key: SelectedGridKey
        var mapping: KeyMapping
    }

    private struct KeymapProfile: Codable {
        let leftDeviceID: String
        let rightDeviceID: String
        let layoutPreset: String
        let autoResyncMissingTrackpads: Bool
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
        let columnSettingsByLayout: [String: [ColumnLayoutSettings]]
        let customButtonsByLayout: [String: [Int: [CustomButton]]]
        let keyMappingsByLayout: LayoutLayeredKeyMappings?
        let keyGeometryByLayout: LayoutKeyGeometryOverrides?
    }

    @StateObject private var viewModel: ContentViewModel
    @State private var testText = ""
    @State private var autocorrectCurrentBufferText = "<empty>"
    @State private var autocorrectLastCorrectedText = "none"
    @State private var editModeEnabled = false
    @State private var columnSettings: [ColumnLayoutSettings]
    @State private var leftLayout: ContentViewModel.Layout
    @State private var rightLayout: ContentViewModel.Layout
    @State private var customButtons: [CustomButton] = []
    @State private var selectedButtonID: UUID?
    @State private var editColumnIndex = 0
    @State private var selectedGridKey: SelectedGridKey?
    @State private var columnInspectorSelection: ColumnInspectorSelection?
    @State private var buttonInspectorSelection: ButtonInspectorSelection?
    @State private var keyInspectorSelection: KeyInspectorSelection?
    @State private var keyMappingsByLayer: LayeredKeyMappings = [:]
    @State private var keyMappingsByLayout: LayoutLayeredKeyMappings = [:]
    @State private var keyGeometryOverrides: KeyGeometryOverrides = [:]
    @State private var layoutOption: TrackpadLayoutPreset = .sixByThree
    @State private var leftGridLabelInfo: [[GridLabel]] = []
    @State private var rightGridLabelInfo: [[GridLabel]] = []
    @State private var replayScrubValue: Double = 0
    @State private var replayScrubInProgress = false
    @AppStorage(GlassToKeyDefaultsKeys.leftDeviceID) private var storedLeftDeviceID = ""
    @AppStorage(GlassToKeyDefaultsKeys.rightDeviceID) private var storedRightDeviceID = ""
    @AppStorage(GlassToKeyDefaultsKeys.columnSettings) private var storedColumnSettingsData = Data()
    @AppStorage(GlassToKeyDefaultsKeys.layoutPreset) private var storedLayoutPreset = TrackpadLayoutPreset.sixByThree.rawValue
    @AppStorage(GlassToKeyDefaultsKeys.customButtons) private var storedCustomButtonsData = Data()
    @AppStorage(GlassToKeyDefaultsKeys.keyMappings) private var storedKeyMappingsData = Data()
    @AppStorage(GlassToKeyDefaultsKeys.keyGeometry) private var storedKeyGeometryData = Data()
    @AppStorage(GlassToKeyDefaultsKeys.autoResyncMissingTrackpads) private var storedAutoResyncMissingTrackpads = false
    @AppStorage(GlassToKeyDefaultsKeys.tapHoldDuration) private var tapHoldDurationMs: Double = GlassToKeySettings.tapHoldDurationMs
    @AppStorage(GlassToKeyDefaultsKeys.dragCancelDistance) private var dragCancelDistanceSetting: Double = GlassToKeySettings.dragCancelDistanceMm
    @AppStorage(GlassToKeyDefaultsKeys.forceClickMin) private var forceClickMinSetting: Double = GlassToKeySettings.forceClickMin
    @AppStorage(GlassToKeyDefaultsKeys.forceClickCap) private var forceClickCapSetting: Double = GlassToKeySettings.forceClickCap
    @AppStorage(GlassToKeyDefaultsKeys.hapticStrength) private var hapticStrengthSetting: Double = GlassToKeySettings.hapticStrengthPercent
    @AppStorage(GlassToKeyDefaultsKeys.typingGraceMs) private var typingGraceMsSetting: Double = GlassToKeySettings.typingGraceMs
    @AppStorage(GlassToKeyDefaultsKeys.intentMoveThresholdMm)
    private var intentMoveThresholdMmSetting: Double = GlassToKeySettings.intentMoveThresholdMm
    @AppStorage(GlassToKeyDefaultsKeys.intentVelocityThresholdMmPerSec)
    private var intentVelocityThresholdMmPerSecSetting: Double = GlassToKeySettings.intentVelocityThresholdMmPerSec
    @AppStorage(GlassToKeyDefaultsKeys.autocorrectEnabled)
    private var autocorrectEnabled = GlassToKeySettings.autocorrectEnabled
    @AppStorage(GlassToKeyDefaultsKeys.tapClickCadenceMs)
    private var tapClickCadenceMsSetting = GlassToKeySettings.tapClickCadenceMs
    @AppStorage(GlassToKeyDefaultsKeys.snapRadiusPercent)
    private var snapRadiusPercentSetting = GlassToKeySettings.snapRadiusPercent
    @AppStorage(GlassToKeyDefaultsKeys.chordalShiftEnabled)
    private var chordalShiftEnabled = GlassToKeySettings.chordalShiftEnabled
    @AppStorage(GlassToKeyDefaultsKeys.keyboardModeEnabled)
    private var keyboardModeEnabled = GlassToKeySettings.keyboardModeEnabled
    @AppStorage(GlassToKeyDefaultsKeys.runAtStartupEnabled)
    private var runAtStartupEnabled = GlassToKeySettings.runAtStartupEnabled
    @AppStorage(GlassToKeyDefaultsKeys.twoFingerTapGestureAction)
    private var twoFingerTapGestureAction = GlassToKeySettings.twoFingerTapGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.threeFingerTapGestureAction)
    private var threeFingerTapGestureAction = GlassToKeySettings.threeFingerTapGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.twoFingerHoldGestureAction)
    private var twoFingerHoldGestureAction = GlassToKeySettings.twoFingerHoldGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.threeFingerHoldGestureAction)
    private var threeFingerHoldGestureAction = GlassToKeySettings.threeFingerHoldGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.fourFingerHoldGestureAction)
    private var fourFingerHoldGestureAction = GlassToKeySettings.fourFingerHoldGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.outerCornersHoldGestureAction)
    private var outerCornersHoldGestureAction = GlassToKeySettings.outerCornersHoldGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.innerCornersHoldGestureAction)
    private var innerCornersHoldGestureAction = GlassToKeySettings.innerCornersHoldGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.fiveFingerSwipeLeftGestureAction)
    private var fiveFingerSwipeLeftGestureAction = GlassToKeySettings.fiveFingerSwipeLeftGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.fiveFingerSwipeRightGestureAction)
    private var fiveFingerSwipeRightGestureAction = GlassToKeySettings.fiveFingerSwipeRightGestureActionLabel
    static let trackpadWidthMM: CGFloat = 160.0
    static let trackpadHeightMM: CGFloat = 114.9
    static let displayScale: CGFloat = 2.7
    static let baseKeyWidthMM: CGFloat = 18.0
    static let baseKeyHeightMM: CGFloat = 17.0
    private static let mobileKeyWidthMM: CGFloat = 13.0
    private static let mobileKeyHeightMM: CGFloat = 13.5
    private static let mobileKeySpacingMM: CGFloat = 1.5
    private static let mobileRowSpacingMM: CGFloat = 5.0
    private static let mobileTopInsetMM: CGFloat = 12.0
    static let minCustomButtonSize = CGSize(width: 0.05, height: 0.05)
    private static let editableLayers = KeyLayerConfig.editableLayers
    fileprivate static let columnScaleRange: ClosedRange<Double> = ColumnLayoutDefaults.scaleRange
    fileprivate static let columnOffsetPercentRange: ClosedRange<Double> = ColumnLayoutDefaults.offsetPercentRange
    fileprivate static let rowSpacingPercentRange: ClosedRange<Double> = ColumnLayoutDefaults.rowSpacingPercentRange
    fileprivate static let rotationDegreesRange: ClosedRange<Double> = ColumnLayoutDefaults.rotationDegreesRange
    fileprivate static let dragCancelDistanceRange: ClosedRange<Double> = 1.0...30.0
    fileprivate static let tapHoldDurationRange: ClosedRange<Double> = 0.0...500.0
    fileprivate static let forceClickRange: ClosedRange<Double> = 0.0...255.0
    fileprivate static let hapticStrengthRange: ClosedRange<Double> = 0.0...100.0
    fileprivate static let typingGraceRange: ClosedRange<Double> = 0.0...4000.0
    fileprivate static let twoFingerClickCadenceRange: ClosedRange<Double> = 100.0...600.0
    fileprivate static let intentMoveThresholdRange: ClosedRange<Double> = 0.5...10.0
    fileprivate static let intentVelocityThresholdRange: ClosedRange<Double> = 10.0...200.0
    fileprivate static let snapRadiusPercentRange: ClosedRange<Double> = 0.0...100.0
    private static let keyCornerRadius: CGFloat = 6.0
    private static let autoSplayTouchCount = 4
    fileprivate static let columnScaleFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.minimum = NSNumber(value: ContentView.columnScaleRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.columnScaleRange.upperBound)
        return formatter
    }()
    fileprivate static let columnOffsetFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.minimum = NSNumber(value: ContentView.columnOffsetPercentRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.columnOffsetPercentRange.upperBound)
        return formatter
    }()
    fileprivate static let rowSpacingFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.minimum = NSNumber(value: ContentView.rowSpacingPercentRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.rowSpacingPercentRange.upperBound)
        return formatter
    }()
    fileprivate static let rotationDegreesFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.minimum = NSNumber(value: ContentView.rotationDegreesRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.rotationDegreesRange.upperBound)
        return formatter
    }()
    fileprivate static let buttonGeometryPercentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.minimum = 0
        formatter.maximum = 100
        return formatter
    }()
    fileprivate static let snapRadiusPercentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.minimum = NSNumber(value: ContentView.snapRadiusPercentRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.snapRadiusPercentRange.upperBound)
        return formatter
    }()
    fileprivate static let tapHoldDurationFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.minimum = NSNumber(value: ContentView.tapHoldDurationRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.tapHoldDurationRange.upperBound)
        return formatter
    }()
    fileprivate static let dragCancelDistanceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.minimum = NSNumber(value: ContentView.dragCancelDistanceRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.dragCancelDistanceRange.upperBound)
        return formatter
    }()
    fileprivate static let forceClickFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.minimum = NSNumber(value: ContentView.forceClickRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.forceClickRange.upperBound)
        return formatter
    }()
    fileprivate static let hapticStrengthFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.minimum = NSNumber(value: 0)
        formatter.maximum = NSNumber(value: 100)
        return formatter
    }()
    fileprivate static let typingGraceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.minimum = NSNumber(value: ContentView.typingGraceRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.typingGraceRange.upperBound)
        return formatter
    }()
    fileprivate static let twoFingerClickCadenceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.minimum = NSNumber(value: ContentView.twoFingerClickCadenceRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.twoFingerClickCadenceRange.upperBound)
        return formatter
    }()
    fileprivate static let intentMoveThresholdFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        formatter.minimum = NSNumber(value: ContentView.intentMoveThresholdRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.intentMoveThresholdRange.upperBound)
        return formatter
    }()
    fileprivate static let intentVelocityThresholdFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.minimum = NSNumber(value: ContentView.intentVelocityThresholdRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.intentVelocityThresholdRange.upperBound)
        return formatter
    }()
    static let ThumbAnchorsMM: [CGRect] = [
        CGRect(x: 0, y: 75, width: 40, height: 40),
        CGRect(x: 40, y: 85, width: 40, height: 30),
        CGRect(x: 80, y: 85, width: 40, height: 30),
        CGRect(x: 120, y: 85, width: 40, height: 30)
    ]
    private let trackpadSize: CGSize
    private var layoutColumns: Int { layoutOption.columns }
    private var layoutRows: Int { layoutOption.rows }
    private var layoutColumnAnchors: [CGPoint] { layoutOption.columnAnchors }
    private var leftGridLabels: [[String]] { layoutOption.leftLabels }
    private var rightGridLabels: [[String]] { layoutOption.rightLabels }
    private var layoutSelectionBinding: Binding<TrackpadLayoutPreset> {
        Binding(
            get: { layoutOption },
            set: { handleLayoutOptionChange($0) }
        )
    }

    private func resolvedGestureAction(
        _ storedLabel: String,
        fallbackLabel: String
    ) -> KeyAction {
        KeyActionCatalog.action(for: storedLabel)
            ?? KeyActionCatalog.action(for: fallbackLabel)
            ?? KeyActionCatalog.noneAction
    }

    private func currentGestureActions(
        twoFingerTapOverride: String? = nil,
        threeFingerTapOverride: String? = nil,
        twoFingerHoldOverride: String? = nil,
        threeFingerHoldOverride: String? = nil,
        fourFingerHoldOverride: String? = nil,
        outerCornersHoldOverride: String? = nil,
        innerCornersHoldOverride: String? = nil,
        fiveFingerSwipeLeftOverride: String? = nil,
        fiveFingerSwipeRightOverride: String? = nil
    ) -> (KeyAction, KeyAction, KeyAction, KeyAction, KeyAction, KeyAction, KeyAction, KeyAction, KeyAction) {
        let two = resolvedGestureAction(
            twoFingerTapOverride ?? twoFingerTapGestureAction,
            fallbackLabel: GlassToKeySettings.twoFingerTapGestureActionLabel
        )
        let three = resolvedGestureAction(
            threeFingerTapOverride ?? threeFingerTapGestureAction,
            fallbackLabel: GlassToKeySettings.threeFingerTapGestureActionLabel
        )
        let twoHold = resolvedGestureAction(
            twoFingerHoldOverride ?? twoFingerHoldGestureAction,
            fallbackLabel: GlassToKeySettings.twoFingerHoldGestureActionLabel
        )
        let threeHold = resolvedGestureAction(
            threeFingerHoldOverride ?? threeFingerHoldGestureAction,
            fallbackLabel: GlassToKeySettings.threeFingerHoldGestureActionLabel
        )
        let four = resolvedGestureAction(
            fourFingerHoldOverride ?? fourFingerHoldGestureAction,
            fallbackLabel: GlassToKeySettings.fourFingerHoldGestureActionLabel
        )
        let outer = resolvedGestureAction(
            outerCornersHoldOverride ?? outerCornersHoldGestureAction,
            fallbackLabel: GlassToKeySettings.outerCornersHoldGestureActionLabel
        )
        let inner = resolvedGestureAction(
            innerCornersHoldOverride ?? innerCornersHoldGestureAction,
            fallbackLabel: GlassToKeySettings.innerCornersHoldGestureActionLabel
        )
        let fiveLeft = resolvedGestureAction(
            fiveFingerSwipeLeftOverride ?? fiveFingerSwipeLeftGestureAction,
            fallbackLabel: GlassToKeySettings.fiveFingerSwipeLeftGestureActionLabel
        )
        let fiveRight = resolvedGestureAction(
            fiveFingerSwipeRightOverride ?? fiveFingerSwipeRightGestureAction,
            fallbackLabel: GlassToKeySettings.fiveFingerSwipeRightGestureActionLabel
        )
        return (two, three, twoHold, threeHold, four, outer, inner, fiveLeft, fiveRight)
    }

    init(viewModel: ContentViewModel = ContentViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
        let size = CGSize(
            width: Self.trackpadWidthMM * Self.displayScale,
            height: Self.trackpadHeightMM * Self.displayScale
        )
        trackpadSize = size
        let defaultLayout = TrackpadLayoutPreset.sixByThree
        let initialColumnSettings = ColumnLayoutDefaults.defaultSettings(
            columns: defaultLayout.columns
        )
        let initialLeftLayout = ContentView.makeKeyLayout(
            size: size,
            keyWidth: Self.baseKeyWidthMM,
            keyHeight: Self.baseKeyHeightMM,
            columns: defaultLayout.columns,
            rows: defaultLayout.rows,
            trackpadWidth: Self.trackpadWidthMM,
            trackpadHeight: Self.trackpadHeightMM,
            columnAnchorsMM: defaultLayout.columnAnchors,
            columnSettings: initialColumnSettings,
            mirrored: true
        )
        let initialRightLayout = ContentView.makeKeyLayout(
            size: size,
            keyWidth: Self.baseKeyWidthMM,
            keyHeight: Self.baseKeyHeightMM,
            columns: defaultLayout.columns,
            rows: defaultLayout.rows,
            trackpadWidth: Self.trackpadWidthMM,
            trackpadHeight: Self.trackpadHeightMM,
            columnAnchorsMM: defaultLayout.columnAnchors,
            columnSettings: initialColumnSettings
        )
        _columnSettings = State(initialValue: initialColumnSettings)
        _leftLayout = State(initialValue: initialLeftLayout)
        _rightLayout = State(initialValue: initialRightLayout)
    }

    var body: some View {
        lifecycleContent(styledMainLayout)
    }

    private var styledMainLayout: some View {
        mainLayout
            .padding()
            .background(backgroundGradient)
            .frame(minWidth: trackpadSize.width * 2 + 520, minHeight: trackpadSize.height + 340)
            .frame(maxHeight: .infinity, alignment: .top)
    }

    private var backgroundGradient: RadialGradient {
        RadialGradient(
            colors: [
                Color.accentColor.opacity(0.08),
                Color.clear
            ],
            center: .topLeading,
            startRadius: 40,
            endRadius: 420
        )
    }

    private func lifecycleContent<Content: View>(_ content: Content) -> some View {
        content
            .onAppear {
                applySavedSettings()
                viewModel.setAutoResyncEnabled(storedAutoResyncMissingTrackpads)
                viewModel.setKeymapEditingEnabled(editModeEnabled)
                AutocorrectEngine.shared.setStatusUpdateHandler { snapshot in
                    DispatchQueue.main.async {
                        applyAutocorrectStatusSnapshot(snapshot)
                    }
                }
            }
            .onDisappear {
                persistConfig()
                AutocorrectEngine.shared.setStatusUpdateHandler(nil)
            }
            .onChange(of: editModeEnabled) { enabled in
                if !enabled {
                    selectedButtonID = nil
                    selectedGridKey = nil
                }
                viewModel.setStatusVisualsEnabled(!enabled)
                viewModel.setKeymapEditingEnabled(enabled)
            }
            .onChange(of: columnSettings) { newValue in
                normalizeEditColumnIndex(for: newValue.count)
                applyColumnSettings(newValue)
                refreshColumnInspectorSelection()
            }
            .onChange(of: customButtons) { newValue in
                saveCustomButtons(newValue)
                viewModel.updateCustomButtons(newValue)
                refreshButtonInspectorSelection()
            }
            .onChange(of: viewModel.activeLayer) { _ in
                selectedButtonID = nil
                selectedGridKey = nil
                updateGridLabelInfo()
            }
            .onChange(of: keyMappingsByLayer) { newValue in
                keyMappingsByLayout[layoutOption.rawValue] = KeyActionMappingStore.normalized(newValue)
                viewModel.updateKeyMappings(newValue)
                updateGridLabelInfo()
                refreshKeyInspectorSelection()
            }
            .onChange(of: keyGeometryOverrides) { newValue in
                saveKeyGeometryOverrides(newValue)
                rebuildLayouts()
                refreshKeyInspectorSelection()
            }
            .onChange(of: selectedButtonID) { _ in
                refreshButtonInspectorSelection()
            }
            .onChange(of: editColumnIndex) { _ in
                refreshColumnInspectorSelection()
            }
            .onChange(of: selectedGridKey) { _ in
                refreshKeyInspectorSelection()
            }
            .onChange(of: tapHoldDurationMs) { newValue in
                viewModel.updateHoldThreshold(newValue / 1000.0)
            }
            .onChange(of: dragCancelDistanceSetting) { newValue in
                viewModel.updateDragCancelDistance(CGFloat(newValue))
            }
            .onChange(of: forceClickMinSetting) { newValue in
                let clamped = min(max(newValue, Self.forceClickRange.lowerBound), Self.forceClickRange.upperBound)
                if clamped != newValue {
                    forceClickMinSetting = clamped
                    return
                }
                if forceClickCapSetting < clamped {
                    forceClickCapSetting = clamped
                }
                viewModel.updateForceClickMin(clamped)
            }
            .onChange(of: forceClickCapSetting) { newValue in
                let clamped = min(max(newValue, Self.forceClickRange.lowerBound), Self.forceClickRange.upperBound)
                if clamped != newValue {
                    forceClickCapSetting = clamped
                    return
                }
                if clamped < forceClickMinSetting {
                    forceClickMinSetting = clamped
                }
                viewModel.updateForceClickCap(clamped)
            }
            .onChange(of: hapticStrengthSetting) { newValue in
                viewModel.updateHapticStrength(newValue / 100.0)
            }
            .onChange(of: typingGraceMsSetting) { newValue in
                viewModel.updateTypingGraceMs(newValue)
            }
            .onChange(of: intentMoveThresholdMmSetting) { newValue in
                viewModel.updateIntentMoveThresholdMm(newValue)
            }
            .onChange(of: intentVelocityThresholdMmPerSecSetting) { newValue in
                viewModel.updateIntentVelocityThresholdMmPerSec(newValue)
            }
            .onChange(of: autocorrectEnabled) { newValue in
                AutocorrectEngine.shared.setEnabled(newValue)
            }
            .onChange(of: tapClickCadenceMsSetting) { newValue in
                viewModel.updateTapClickCadenceMs(newValue)
            }
            .onChange(of: snapRadiusPercentSetting) { newValue in
                viewModel.updateSnapRadiusPercent(newValue)
            }
            .onChange(of: chordalShiftEnabled) { newValue in
                viewModel.updateChordalShiftEnabled(newValue)
            }
            .onChange(of: keyboardModeEnabled) { newValue in
                viewModel.updateKeyboardModeEnabled(newValue)
            }
            .onChange(of: runAtStartupEnabled) { newValue in
                do {
                    try LaunchAtLoginManager.shared.setEnabled(newValue)
                    let resolved = LaunchAtLoginManager.shared.isEnabled
                    if resolved != newValue {
                        runAtStartupEnabled = resolved
                    }
                } catch {
                    runAtStartupEnabled = LaunchAtLoginManager.shared.isEnabled
                }
            }
            .onChange(of: twoFingerTapGestureAction) { newValue in
                let actions = currentGestureActions(twoFingerTapOverride: newValue)
                viewModel.updateGestureActions(
                    twoFingerTap: actions.0,
                    threeFingerTap: actions.1,
                    twoFingerHold: actions.2,
                    threeFingerHold: actions.3,
                    fourFingerHold: actions.4,
                    outerCornersHold: actions.5,
                    innerCornersHold: actions.6,
                    fiveFingerSwipeLeft: actions.7,
                    fiveFingerSwipeRight: actions.8
                )
            }
            .onChange(of: threeFingerTapGestureAction) { newValue in
                let actions = currentGestureActions(threeFingerTapOverride: newValue)
                viewModel.updateGestureActions(
                    twoFingerTap: actions.0,
                    threeFingerTap: actions.1,
                    twoFingerHold: actions.2,
                    threeFingerHold: actions.3,
                    fourFingerHold: actions.4,
                    outerCornersHold: actions.5,
                    innerCornersHold: actions.6,
                    fiveFingerSwipeLeft: actions.7,
                    fiveFingerSwipeRight: actions.8
                )
            }
            .onChange(of: twoFingerHoldGestureAction) { newValue in
                let actions = currentGestureActions(twoFingerHoldOverride: newValue)
                viewModel.updateGestureActions(
                    twoFingerTap: actions.0,
                    threeFingerTap: actions.1,
                    twoFingerHold: actions.2,
                    threeFingerHold: actions.3,
                    fourFingerHold: actions.4,
                    outerCornersHold: actions.5,
                    innerCornersHold: actions.6,
                    fiveFingerSwipeLeft: actions.7,
                    fiveFingerSwipeRight: actions.8
                )
            }
            .onChange(of: threeFingerHoldGestureAction) { newValue in
                let actions = currentGestureActions(threeFingerHoldOverride: newValue)
                viewModel.updateGestureActions(
                    twoFingerTap: actions.0,
                    threeFingerTap: actions.1,
                    twoFingerHold: actions.2,
                    threeFingerHold: actions.3,
                    fourFingerHold: actions.4,
                    outerCornersHold: actions.5,
                    innerCornersHold: actions.6,
                    fiveFingerSwipeLeft: actions.7,
                    fiveFingerSwipeRight: actions.8
                )
            }
            .onChange(of: fourFingerHoldGestureAction) { newValue in
                let actions = currentGestureActions(fourFingerHoldOverride: newValue)
                viewModel.updateGestureActions(
                    twoFingerTap: actions.0,
                    threeFingerTap: actions.1,
                    twoFingerHold: actions.2,
                    threeFingerHold: actions.3,
                    fourFingerHold: actions.4,
                    outerCornersHold: actions.5,
                    innerCornersHold: actions.6,
                    fiveFingerSwipeLeft: actions.7,
                    fiveFingerSwipeRight: actions.8
                )
            }
            .onChange(of: outerCornersHoldGestureAction) { newValue in
                let actions = currentGestureActions(outerCornersHoldOverride: newValue)
                viewModel.updateGestureActions(
                    twoFingerTap: actions.0,
                    threeFingerTap: actions.1,
                    twoFingerHold: actions.2,
                    threeFingerHold: actions.3,
                    fourFingerHold: actions.4,
                    outerCornersHold: actions.5,
                    innerCornersHold: actions.6,
                    fiveFingerSwipeLeft: actions.7,
                    fiveFingerSwipeRight: actions.8
                )
            }
            .onChange(of: innerCornersHoldGestureAction) { newValue in
                let actions = currentGestureActions(innerCornersHoldOverride: newValue)
                viewModel.updateGestureActions(
                    twoFingerTap: actions.0,
                    threeFingerTap: actions.1,
                    twoFingerHold: actions.2,
                    threeFingerHold: actions.3,
                    fourFingerHold: actions.4,
                    outerCornersHold: actions.5,
                    innerCornersHold: actions.6,
                    fiveFingerSwipeLeft: actions.7,
                    fiveFingerSwipeRight: actions.8
                )
            }
            .onChange(of: fiveFingerSwipeLeftGestureAction) { newValue in
                let actions = currentGestureActions(fiveFingerSwipeLeftOverride: newValue)
                viewModel.updateGestureActions(
                    twoFingerTap: actions.0,
                    threeFingerTap: actions.1,
                    twoFingerHold: actions.2,
                    threeFingerHold: actions.3,
                    fourFingerHold: actions.4,
                    outerCornersHold: actions.5,
                    innerCornersHold: actions.6,
                    fiveFingerSwipeLeft: actions.7,
                    fiveFingerSwipeRight: actions.8
                )
            }
            .onChange(of: fiveFingerSwipeRightGestureAction) { newValue in
                let actions = currentGestureActions(fiveFingerSwipeRightOverride: newValue)
                viewModel.updateGestureActions(
                    twoFingerTap: actions.0,
                    threeFingerTap: actions.1,
                    twoFingerHold: actions.2,
                    threeFingerHold: actions.3,
                    fourFingerHold: actions.4,
                    outerCornersHold: actions.5,
                    innerCornersHold: actions.6,
                    fiveFingerSwipeLeft: actions.7,
                    fiveFingerSwipeRight: actions.8
                )
            }
            .onChange(of: storedAutoResyncMissingTrackpads) { newValue in
                viewModel.setAutoResyncEnabled(newValue)
            }
            .onReceive(viewModel.$replayTimelineState) { state in
                if state != nil, editModeEnabled {
                    editModeEnabled = false
                }
                if let state, !replayScrubInProgress {
                    replayScrubValue = max(state.currentTimeSeconds, 0)
                }
                if state == nil {
                    replayScrubInProgress = false
                    replayScrubValue = 0
                }
            }
    }

    @ViewBuilder
    private var mainLayout: some View {
        VStack(spacing: 16) {
            headerView
            if let replayTimelineState = viewModel.replayTimelineState {
                replayTimelineView(replayTimelineState)
            }
            devicesSectionView
            contentRow
        }
    }

    @ViewBuilder
    private var headerView: some View {
        HeaderControlsView(
            editModeEnabled: $editModeEnabled,
            statusViewModel: viewModel.statusViewModel,
            replayModeEnabled: viewModel.replayTimelineState != nil,
            onImportKeymap: importKeymap,
            onExportKeymap: exportKeymap
        )
    }

    private func replayTimelineView(
        _ state: ContentViewModel.ReplayTimelineState
    ) -> some View {
        let maxTime = max(state.durationSeconds, 0)
        let maxFrameIndex = max(state.frameCount - 1, 0)
        return HStack(spacing: 12) {
            Text("Replay")
                .font(.subheadline)
                .bold()
            Text(state.sourceName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Button(state.isPlaying ? "Pause" : "Play") {
                viewModel.toggleReplayPlayback()
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.frameCount == 0)
            Slider(
                value: Binding(
                    get: { replayScrubValue },
                    set: { replayScrubValue = $0 }
                ),
                in: 0...max(maxTime, 0.001),
                step: 0.01
            ) { editing in
                replayScrubInProgress = editing
                guard !editing else { return }
                Task {
                    try? await viewModel.scrubReplay(to: replayScrubValue)
                }
            }
            .disabled(state.frameCount == 0 || state.isPlaying)
            Text("\(formatReplayTime(state.currentTimeSeconds))/\(formatReplayTime(state.durationSeconds))")
                .font(.caption.monospacedDigit())
                .frame(width: 150, alignment: .trailing)
            Text("\(max(state.currentFrameIndex, 0))/\(maxFrameIndex)")
                .font(.caption.monospacedDigit())
                .frame(width: 80, alignment: .trailing)
            Button("Exit Replay") {
                Task {
                    await viewModel.endReplaySession()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.blue.opacity(0.08))
        )
    }

    private func formatReplayTime(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let totalMilliseconds = Int((clamped * 1_000).rounded())
        let minutes = totalMilliseconds / 60_000
        let secondsComponent = (totalMilliseconds / 1_000) % 60
        let millisecondsComponent = totalMilliseconds % 1_000
        return String(
            format: "%02d:%02d.%03d",
            minutes,
            secondsComponent,
            millisecondsComponent
        )
    }

    private var devicesSectionView: some View {
        DevicesSectionView(
            availableDevices: viewModel.availableDevices,
            leftDevice: viewModel.leftDevice,
            rightDevice: viewModel.rightDevice,
            onSelectLeft: { device in
                viewModel.selectLeftDevice(device)
            },
            onSelectRight: { device in
                viewModel.selectRightDevice(device)
            },
            onRefresh: {
                viewModel.refreshDevicesAndListeners()
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var contentRow: some View {
        HStack(alignment: .top, spacing: 18) {
            trackpadSectionView
            rightSidebarView
        }
    }

    private var trackpadSectionView: some View {
            TrackpadSectionView(
                viewModel: viewModel,
                trackpadSize: trackpadSize,
                leftLayout: leftLayout,
                rightLayout: rightLayout,
                leftBaseLabels: leftGridLabels,
                rightBaseLabels: rightGridLabels,
                leftGridLabelInfo: leftGridLabelInfo,
                rightGridLabelInfo: rightGridLabelInfo,
                customButtons: customButtons,
                editModeEnabled: $editModeEnabled,
                lastHitLeft: viewModel.debugLastHitLeft,
                lastHitRight: viewModel.debugLastHitRight,
                selectedButtonID: $selectedButtonID,
                selectedGridKey: $selectedGridKey,
                testText: $testText,
                autocorrectCurrentBufferText: $autocorrectCurrentBufferText,
                autocorrectLastCorrectedText: $autocorrectLastCorrectedText
            )
    }

    private func applyAutocorrectStatusSnapshot(_ snapshot: AutocorrectEngine.StatusSnapshot) {
        if snapshot.enabled {
            autocorrectCurrentBufferText = snapshot.currentBuffer.isEmpty ? "<empty>" : snapshot.currentBuffer
        } else {
            autocorrectCurrentBufferText = "<empty>"
        }
        autocorrectLastCorrectedText = snapshot.lastCorrected
    }

    private var rightSidebarView: some View {
        RightSidebarView(
            layoutSelection: layoutSelectionBinding,
            layoutOption: layoutOption,
            columnSettings: columnSettings,
            columnSelection: columnInspectorSelection,
            editColumnIndex: $editColumnIndex,
            buttonSelection: buttonInspectorSelection,
            keySelection: keyInspectorSelection,
            editModeEnabled: editModeEnabled,
            layerSelection: layerSelectionBinding,
            tapHoldDurationMs: $tapHoldDurationMs,
            dragCancelDistanceSetting: $dragCancelDistanceSetting,
            forceClickMinSetting: $forceClickMinSetting,
            forceClickCapSetting: $forceClickCapSetting,
            hapticStrengthSetting: $hapticStrengthSetting,
            typingGraceMsSetting: $typingGraceMsSetting,
            intentMoveThresholdMmSetting: $intentMoveThresholdMmSetting,
            intentVelocityThresholdMmPerSecSetting: $intentVelocityThresholdMmPerSecSetting,
            autocorrectEnabled: $autocorrectEnabled,
            tapClickCadenceMsSetting: $tapClickCadenceMsSetting,
            snapRadiusPercentSetting: $snapRadiusPercentSetting,
            chordalShiftEnabled: $chordalShiftEnabled,
            keyboardModeEnabled: $keyboardModeEnabled,
            runAtStartupEnabled: $runAtStartupEnabled,
            twoFingerTapGestureAction: $twoFingerTapGestureAction,
            threeFingerTapGestureAction: $threeFingerTapGestureAction,
            twoFingerHoldGestureAction: $twoFingerHoldGestureAction,
            threeFingerHoldGestureAction: $threeFingerHoldGestureAction,
            fourFingerHoldGestureAction: $fourFingerHoldGestureAction,
            outerCornersHoldGestureAction: $outerCornersHoldGestureAction,
            innerCornersHoldGestureAction: $innerCornersHoldGestureAction,
            fiveFingerSwipeLeftGestureAction: $fiveFingerSwipeLeftGestureAction,
            fiveFingerSwipeRightGestureAction: $fiveFingerSwipeRightGestureAction,
            autoResyncEnabled: $storedAutoResyncMissingTrackpads,
            onAddCustomButton: { side in
                addCustomButton(side: side)
            },
            onRemoveCustomButton: { id in
                removeCustomButton(id: id)
            },
            onClearTouchState: {
                viewModel.clearTouchState()
            },
            onUpdateColumn: { index, update in
                updateColumnSettingAndSelection(index: index, update: update)
            },
            onUpdateButton: { id, update in
                updateCustomButtonAndSelection(id: id, update: update)
            },
            onUpdateKeyMapping: { key, update in
                updateKeyMappingAndSelection(key: key, update: update)
            },
            keyRotationDegrees: { key in
                keyRotationDegrees(for: key)
            },
            onUpdateKeyRotation: { key, rotationDegrees in
                updateKeyRotationAndSelection(for: key, rotationDegrees: rotationDegrees)
            },
            onRestoreDefaults: restoreTypingTuningDefaults,
            onAutoSplayColumns: applyAutoSplay,
            onEvenSpaceColumns: applyEvenColumnSpacing
        )
    }

    private struct HeaderControlsView: View {
        @Binding var editModeEnabled: Bool
        @ObservedObject var statusViewModel: ContentViewModel.StatusViewModel
        let replayModeEnabled: Bool
        let onImportKeymap: () -> Void
        let onExportKeymap: () -> Void

        var body: some View {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("GlassToKey")
                        .font(.title2)
                        .bold()
                    HStack(spacing: 10) {
                        contactCountPills
                        intentBadge(intent: statusViewModel.intentDisplayBySide.left)
                    }
                }
                Spacer()
                Button("Import keymap") {
                    onImportKeymap()
                }
                .buttonStyle(.bordered)
                Button("Export keymap") {
                    onExportKeymap()
                }
                .buttonStyle(.bordered)
                Toggle("Edit Keymap", isOn: $editModeEnabled)
                    .toggleStyle(SwitchToggleStyle())
                    .disabled(replayModeEnabled)
            }
        }

        private var contactCountPills: some View {
            HStack(spacing: 8) {
                labelPill(prefix: "L", value: statusViewModel.contactFingerCountsBySide.left)
                labelPill(prefix: "R", value: statusViewModel.contactFingerCountsBySide.right)
            }
        }

        private func labelPill(prefix: String, value: Int) -> some View {
            Text("\(prefix) \(value)")
                .font(.caption2)
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                )
        }

        private func intentBadge(intent: ContentViewModel.IntentDisplay) -> some View {
            HStack(spacing: 4) {
                Circle()
                    .fill(intentColor(intent))
                    .frame(width: 6, height: 6)
                Text(intentLabel(intent))
                .font(.caption2)
                .foregroundStyle(.primary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.06))
            )
        }

        private func intentLabel(_ intent: ContentViewModel.IntentDisplay) -> String {
            switch intent {
            case .idle:
                return "idle"
            case .keyCandidate:
                return "cand"
            case .typing:
                return "typing"
            case .mouse:
                return "mouse"
            case .gesture:
                return "gest"
            }
        }

        private func intentColor(_ intent: ContentViewModel.IntentDisplay) -> Color {
            switch intent {
            case .idle:
                return .gray
            case .keyCandidate:
                return .orange
            case .typing:
                return .green
            case .mouse:
                return .blue
            case .gesture:
                return .purple
            }
        }

    }

    private struct TrackpadSectionView: View {
        @ObservedObject var viewModel: ContentViewModel
        let trackpadSize: CGSize
        let leftLayout: ContentViewModel.Layout
        let rightLayout: ContentViewModel.Layout
        let leftBaseLabels: [[String]]
        let rightBaseLabels: [[String]]
        let leftGridLabelInfo: [[GridLabel]]
        let rightGridLabelInfo: [[GridLabel]]
        let customButtons: [CustomButton]
        @Binding var editModeEnabled: Bool
        let lastHitLeft: ContentViewModel.DebugHit?
        let lastHitRight: ContentViewModel.DebugHit?
        @Binding var selectedButtonID: UUID?
        @Binding var selectedGridKey: SelectedGridKey?
        @Binding var testText: String
        @Binding var autocorrectCurrentBufferText: String
        @Binding var autocorrectLastCorrectedText: String

        var body: some View {
            ZStack {
                VStack(alignment: .leading, spacing: 12) {
                        TrackpadDeckView(
                            viewModel: viewModel,
                            trackpadSize: trackpadSize,
                            leftLayout: leftLayout,
                            rightLayout: rightLayout,
                            leftBaseLabels: leftBaseLabels,
                            rightBaseLabels: rightBaseLabels,
                            leftGridLabelInfo: leftGridLabelInfo,
                            rightGridLabelInfo: rightGridLabelInfo,
                            customButtons: customButtons,
                            editModeEnabled: $editModeEnabled,
                            lastHitLeft: lastHitLeft,
                            lastHitRight: lastHitRight,
                            selectedButtonID: $selectedButtonID,
                            selectedGridKey: $selectedGridKey
                        )
                    TextEditor(text: $testText)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.6), lineWidth: 1)
                        )
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        HStack(spacing: 4) {
                            Text("Current buffer:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(autocorrectCurrentBufferText)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Spacer(minLength: 12)
                        HStack(spacing: 4) {
                            Text("Last corrected:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(autocorrectLastCorrectedText)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(0.05))
                )

                Button(action: clearSelection) {
                    EmptyView()
                }
                .frame(width: 0, height: 0)
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.borderless)
                .disabled(!editModeEnabled)
            }
        }

        private func clearSelection() {
            guard editModeEnabled else { return }
            selectedGridKey = nil
            selectedButtonID = nil
        }
    }

    private struct RightSidebarView: View {
        let layoutSelection: Binding<TrackpadLayoutPreset>
        let layoutOption: TrackpadLayoutPreset
        let columnSettings: [ColumnLayoutSettings]
        let columnSelection: ColumnInspectorSelection?
        @Binding var editColumnIndex: Int
        let buttonSelection: ButtonInspectorSelection?
        let keySelection: KeyInspectorSelection?
        let editModeEnabled: Bool
        let layerSelection: Binding<Int>
        @Binding var tapHoldDurationMs: Double
        @Binding var dragCancelDistanceSetting: Double
        @Binding var forceClickMinSetting: Double
        @Binding var forceClickCapSetting: Double
        @Binding var hapticStrengthSetting: Double
        @Binding var typingGraceMsSetting: Double
        @Binding var intentMoveThresholdMmSetting: Double
        @Binding var intentVelocityThresholdMmPerSecSetting: Double
        @Binding var autocorrectEnabled: Bool
        @Binding var tapClickCadenceMsSetting: Double
        @Binding var snapRadiusPercentSetting: Double
        @Binding var chordalShiftEnabled: Bool
        @Binding var keyboardModeEnabled: Bool
        @Binding var runAtStartupEnabled: Bool
        @Binding var twoFingerTapGestureAction: String
        @Binding var threeFingerTapGestureAction: String
        @Binding var twoFingerHoldGestureAction: String
        @Binding var threeFingerHoldGestureAction: String
        @Binding var fourFingerHoldGestureAction: String
        @Binding var outerCornersHoldGestureAction: String
        @Binding var innerCornersHoldGestureAction: String
        @Binding var fiveFingerSwipeLeftGestureAction: String
        @Binding var fiveFingerSwipeRightGestureAction: String
        @Binding var autoResyncEnabled: Bool
        @State private var modeTogglesExpanded = true
        @State private var typingTuningExpanded = false
        @State private var gestureTuningExpanded = false
        @State private var columnTuningExpanded = false
        @State private var keymapTuningExpanded = true
        let onAddCustomButton: (TrackpadSide) -> Void
        let onRemoveCustomButton: (UUID) -> Void
        let onClearTouchState: () -> Void
        let onUpdateColumn: (Int, (inout ColumnLayoutSettings) -> Void) -> Void
        let onUpdateButton: (UUID, (inout CustomButton) -> Void) -> Void
        let onUpdateKeyMapping: (SelectedGridKey, (inout KeyMapping) -> Void) -> Void
        let keyRotationDegrees: (SelectedGridKey) -> Double
        let onUpdateKeyRotation: (SelectedGridKey, Double) -> Void
        let onRestoreDefaults: () -> Void
        let onAutoSplayColumns: () -> Void
        let onEvenSpaceColumns: () -> Void

        var body: some View {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    if !editModeEnabled {
                        DisclosureGroup(
                            isExpanded: $typingTuningExpanded
                        ) {
                            TypingTuningSectionView(
                                tapHoldDurationMs: $tapHoldDurationMs,
                                dragCancelDistanceSetting: $dragCancelDistanceSetting,
                                forceClickMinSetting: $forceClickMinSetting,
                                forceClickCapSetting: $forceClickCapSetting,
                                hapticStrengthSetting: $hapticStrengthSetting,
                                typingGraceMsSetting: $typingGraceMsSetting,
                                intentMoveThresholdMmSetting: $intentMoveThresholdMmSetting,
                                intentVelocityThresholdMmPerSecSetting: $intentVelocityThresholdMmPerSecSetting,
                                tapClickCadenceMsSetting: $tapClickCadenceMsSetting,
                                onRestoreDefaults: onRestoreDefaults
                            )
                            .padding(.top, 8)
                        } label: {
                            Text("Typing Tuning")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.primary.opacity(0.05))
                        )

                        DisclosureGroup(
                            isExpanded: $gestureTuningExpanded
                        ) {
                            GestureTuningSectionView(
                                twoFingerTapGestureAction: $twoFingerTapGestureAction,
                                threeFingerTapGestureAction: $threeFingerTapGestureAction,
                                twoFingerHoldGestureAction: $twoFingerHoldGestureAction,
                                threeFingerHoldGestureAction: $threeFingerHoldGestureAction,
                                fourFingerHoldGestureAction: $fourFingerHoldGestureAction,
                                outerCornersHoldGestureAction: $outerCornersHoldGestureAction,
                                innerCornersHoldGestureAction: $innerCornersHoldGestureAction,
                                fiveFingerSwipeLeftGestureAction: $fiveFingerSwipeLeftGestureAction,
                                fiveFingerSwipeRightGestureAction: $fiveFingerSwipeRightGestureAction
                            )
                            .padding(.top, 8)
                        } label: {
                            Text("Gesture Tuning")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.primary.opacity(0.05))
                        )

                        DisclosureGroup(
                            isExpanded: $modeTogglesExpanded
                        ) {
                            ModeTogglesSectionView(
                                autocorrectEnabled: $autocorrectEnabled,
                                snapRadiusPercentSetting: $snapRadiusPercentSetting,
                                chordalShiftEnabled: $chordalShiftEnabled,
                                keyboardModeEnabled: $keyboardModeEnabled,
                                runAtStartupEnabled: $runAtStartupEnabled,
                                autoResyncEnabled: $autoResyncEnabled
                            )
                            .padding(.top, 8)
                        } label: {
                            Text("Mode Toggles")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.primary.opacity(0.05))
                        )
                    }

                    if editModeEnabled {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Layout")
                                Spacer()
                                Picker("", selection: layoutSelection) {
                                    ForEach(TrackpadLayoutPreset.allCases) { preset in
                                        Text(preset.displayName).tag(preset)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.primary.opacity(0.05))
                            )

                            DisclosureGroup(
                                isExpanded: $columnTuningExpanded
                            ) {
                                ColumnTuningSectionView(
                                    layoutOption: layoutOption,
                                    columnSettings: columnSettings,
                                    selection: columnSelection,
                                    editColumnIndex: $editColumnIndex,
                                    onUpdateColumn: onUpdateColumn,
                                    onAutoSplay: onAutoSplayColumns,
                                    onEvenSpacing: onEvenSpaceColumns
                                )
                                .padding(.top, 8)
                            } label: {
                                Text("Column Tuning")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.primary.opacity(0.05))
                            )

                            DisclosureGroup(
                                isExpanded: $keymapTuningExpanded
                            ) {
                                ButtonTuningSectionView(
                                    buttonSelection: buttonSelection,
                                    keySelection: keySelection,
                                    layerSelection: layerSelection,
                                    onAddCustomButton: onAddCustomButton,
                                    onRemoveCustomButton: onRemoveCustomButton,
                                    onClearTouchState: onClearTouchState,
                                    onUpdateButton: onUpdateButton,
                                    onUpdateKeyMapping: onUpdateKeyMapping,
                                    keyRotationDegrees: keyRotationDegrees,
                                    onUpdateKeyRotation: onUpdateKeyRotation
                                )
                                .padding(.top, 8)
                            } label: {
                                Text("Keymap Tuning")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.primary.opacity(0.05))
                            )
                        }
                    }
                }
                .overlay(alignment: .top) {
                    VerticalScrollViewConfigurator()
                        .frame(width: 0, height: 0)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(width: 420)
        }
    }

    private struct VerticalScrollViewConfigurator: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView {
            let view = NSView(frame: .zero)
            DispatchQueue.main.async {
                configureScrollView(from: view)
            }
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            DispatchQueue.main.async {
                configureScrollView(from: nsView)
            }
        }

        @MainActor
        private func configureScrollView(from view: NSView) {
            guard let scrollView = view.enclosingScrollView else { return }
            scrollView.hasVerticalScroller = true
            scrollView.autohidesScrollers = false
            scrollView.scrollerStyle = .legacy
            scrollView.drawsBackground = false
        }
    }

    private struct DevicesSectionView: View {
        let availableDevices: [OMSDeviceInfo]
        let leftDevice: OMSDeviceInfo?
        let rightDevice: OMSDeviceInfo?
        let onSelectLeft: (OMSDeviceInfo?) -> Void
        let onSelectRight: (OMSDeviceInfo?) -> Void
        let onRefresh: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                if availableDevices.isEmpty {
                    Text("No trackpads detected.")
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Left Trackpad")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("", selection: Binding(
                                get: { leftDevice },
                                set: { device in
                                    onSelectLeft(device)
                                }
                            )) {
                                Text("None")
                                    .tag(nil as OMSDeviceInfo?)
                                ForEach(availableDevices, id: \.self) { device in
                                    Text("\(device.deviceName) (ID: \(device.deviceID))")
                                        .tag(device as OMSDeviceInfo?)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .pickerStyle(MenuPickerStyle())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Right Trackpad")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("", selection: Binding(
                                get: { rightDevice },
                                set: { device in
                                    onSelectRight(device)
                                }
                            )) {
                                Text("None")
                                    .tag(nil as OMSDeviceInfo?)
                                ForEach(availableDevices, id: \.self) { device in
                                    Text("\(device.deviceName) (ID: \(device.deviceID))")
                                        .tag(device as OMSDeviceInfo?)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .pickerStyle(MenuPickerStyle())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button(action: {
                            onRefresh()
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .imageScale(.medium)
                        }
                        .buttonStyle(.bordered)
                        .help("Refresh trackpad list")
                        .padding(.top, 20)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.05))
            )
        }
    }

    private struct ColumnTuningSectionView: View {
        let layoutOption: TrackpadLayoutPreset
        let columnSettings: [ColumnLayoutSettings]
        let selection: ColumnInspectorSelection?
        @Binding var editColumnIndex: Int
        let onUpdateColumn: (Int, (inout ColumnLayoutSettings) -> Void) -> Void
        let onAutoSplay: () -> Void
        let onEvenSpacing: () -> Void

        private var editColumnBinding: Binding<Int> {
            Binding(
                get: {
                    guard !columnSettings.isEmpty else { return 0 }
                    return min(max(editColumnIndex, 0), columnSettings.count - 1)
                },
                set: { newValue in
                    guard !columnSettings.isEmpty else { return }
                    editColumnIndex = min(max(newValue, 0), columnSettings.count - 1)
                }
            )
        }

        private var activeColumnIndex: Int? {
            guard !columnSettings.isEmpty else { return nil }
            return editColumnBinding.wrappedValue
        }

        private var activeColumnSettings: ColumnLayoutSettings? {
            guard let index = activeColumnIndex else { return nil }
            return columnSettings[index]
        }

        private var isAutoSplaySupportedPreset: Bool {
            layoutOption.columns == 6 || layoutOption == .fiveByThree || layoutOption == .fiveByFour
        }

        private var isEvenSpacingAvailable: Bool {
            layoutOption.allowsColumnSettings &&
            layoutOption.columns >= 3 &&
            columnSettings.count >= layoutOption.columns
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                if layoutOption.hasGrid && layoutOption.allowsColumnSettings {
                    if let index = activeColumnIndex,
                       let settings = activeColumnSettings {
                        HStack {
                            Text("Edit Column")
                            Spacer()
                            Picker("", selection: editColumnBinding) {
                                ForEach(columnSettings.indices, id: \.self) { columnIndex in
                                    Text("Column \(columnIndex + 1)").tag(columnIndex)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                        VStack(alignment: .leading, spacing: 14) {
                            ColumnTuningRow(
                                title: "Column Scale (%)",
                                value: Binding(
                                    get: { settings.scale },
                                    set: { newValue in
                                        onUpdateColumn(index) { setting in
                                            setting.scale = ContentView.normalizedColumnScale(newValue)
                                        }
                                    }
                                ),
                                formatter: ContentView.columnScaleFormatter,
                                range: ContentView.columnScaleRange,
                                sliderStep: 0.05,
                                showSlider: false
                            )
                            ColumnTuningRow(
                                title: "Column Spacing (%)",
                                value: Binding(
                                    get: { settings.rowSpacingPercent },
                                    set: { newValue in
                                        onUpdateColumn(index) { setting in
                                            setting.rowSpacingPercent = ContentView.normalizedRowSpacingPercent(newValue)
                                        }
                                    }
                                ),
                                formatter: ContentView.rowSpacingFormatter,
                                range: ContentView.rowSpacingPercentRange,
                                sliderStep: 1.0,
                                buttonStep: 0.5,
                                showSlider: false
                            )
                            ColumnTuningRow(
                                title: "Column X (%)",
                                value: Binding(
                                    get: { settings.offsetXPercent },
                                    set: { newValue in
                                        onUpdateColumn(index) { setting in
                                            setting.offsetXPercent = ContentView.normalizedColumnOffsetPercent(newValue)
                                        }
                                    }
                                ),
                                formatter: ContentView.columnOffsetFormatter,
                                range: ContentView.columnOffsetPercentRange,
                                sliderStep: 1.0,
                                buttonStep: 0.5,
                                showSlider: false
                            )
                            ColumnTuningRow(
                                title: "Column Y (%)",
                                value: Binding(
                                    get: { settings.offsetYPercent },
                                    set: { newValue in
                                        onUpdateColumn(index) { setting in
                                            setting.offsetYPercent = ContentView.normalizedColumnOffsetPercent(newValue)
                                        }
                                    }
                                ),
                                formatter: ContentView.columnOffsetFormatter,
                                range: ContentView.columnOffsetPercentRange,
                                sliderStep: 1.0,
                                buttonStep: 0.5,
                                showSlider: false
                            )
                            ColumnTuningRow(
                                title: "Rotation (0-360 deg)",
                                value: Binding(
                                    get: { settings.rotationDegrees },
                                    set: { newValue in
                                        onUpdateColumn(index) { setting in
                                            setting.rotationDegrees = ContentView.normalizedRotationDegrees(newValue)
                                        }
                                    }
                                ),
                                formatter: ContentView.rotationDegreesFormatter,
                                range: ContentView.rotationDegreesRange,
                                sliderStep: 1.0,
                                buttonStep: 0.5,
                                showSlider: false
                            )
                        }
                        HStack(spacing: 8) {
                            Button("Auto Splay (4 Fingers)") {
                                onAutoSplay()
                            }
                                .buttonStyle(.bordered)
                                .disabled(!isAutoSplaySupportedPreset)
                            Spacer()
                            Button("e v e n s p a c i n g") {
                                onEvenSpacing()
                            }
                                .buttonStyle(.bordered)
                                .disabled(!isEvenSpacingAvailable)
                        }
                    } else {
                        Text("No columns available for this layout.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(layoutOption.hasGrid
                        ? "This preset uses a fixed right-side layout; column tuning is disabled."
                        : "Layout has no grid. Pick one of the presets to show keys.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private struct ButtonTuningSectionView: View {
        let buttonSelection: ButtonInspectorSelection?
        let keySelection: KeyInspectorSelection?
        let layerSelection: Binding<Int>
        let onAddCustomButton: (TrackpadSide) -> Void
        let onRemoveCustomButton: (UUID) -> Void
        let onClearTouchState: () -> Void
        let onUpdateButton: (UUID, (inout CustomButton) -> Void) -> Void
        let onUpdateKeyMapping: (SelectedGridKey, (inout KeyMapping) -> Void) -> Void
        let keyRotationDegrees: (SelectedGridKey) -> Double
        let onUpdateKeyRotation: (SelectedGridKey, Double) -> Void

        private var hasEditableSelection: Bool {
            buttonSelection != nil || keySelection != nil
        }

        private var primaryActionBinding: Binding<KeyAction> {
            Binding(
                get: {
                    if let selection = buttonSelection {
                        return selection.button.action
                    }
                    if let selection = keySelection {
                        return selection.mapping.primary
                    }
                    return KeyActionCatalog.noneAction
                },
                set: { newValue in
                    if let selection = buttonSelection {
                        onUpdateButton(selection.button.id) { button in
                            button.action = newValue
                        }
                        return
                    }
                    if let selection = keySelection {
                        onUpdateKeyMapping(selection.key) { mapping in
                            mapping.primary = newValue
                        }
                    }
                }
            )
        }

        private var holdActionBinding: Binding<KeyAction?> {
            Binding(
                get: {
                    if let selection = buttonSelection {
                        return selection.button.hold ?? KeyActionCatalog.noneAction
                    }
                    if let selection = keySelection {
                        return selection.mapping.hold ?? KeyActionCatalog.noneAction
                    }
                    return KeyActionCatalog.noneAction
                },
                set: { newValue in
                    let normalized = newValue ?? KeyActionCatalog.noneAction
                    let resolvedHold = normalized.kind == .none ? nil : normalized
                    if let selection = buttonSelection {
                        onUpdateButton(selection.button.id) { button in
                            button.hold = resolvedHold
                        }
                        return
                    }
                    if let selection = keySelection {
                        onUpdateKeyMapping(selection.key) { mapping in
                            mapping.hold = resolvedHold
                        }
                    }
                }
            )
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Layer")
                    Spacer()
                    Picker("", selection: layerSelection) {
                        ForEach(ContentView.editableLayers, id: \.self) { layer in
                            Text("Layer\(layer)").tag(layer)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .labelsHidden()
                }
                Text("Select a button or key on the trackpad to edit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Primary Action", selection: primaryActionBinding) {
                    ForEach(KeyActionCatalog.primaryActionGroups.indices, id: \.self) { index in
                        let group = KeyActionCatalog.primaryActionGroups[index]
                        ContentView.pickerGroupHeader(group.title)
                        ForEach(group.actions, id: \.self) { action in
                            ContentView.pickerLabel(for: action).tag(action)
                        }
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .disabled(!hasEditableSelection)
                Picker("Hold Action", selection: holdActionBinding) {
                    ForEach(KeyActionCatalog.holdActionGroups.indices, id: \.self) { index in
                        let group = KeyActionCatalog.holdActionGroups[index]
                        ContentView.pickerGroupHeader(group.title)
                        ForEach(group.actions, id: \.self) { action in
                            ContentView.pickerLabel(for: action).tag(action as KeyAction?)
                        }
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .disabled(!hasEditableSelection)
                if let selection = keySelection {
                    ColumnTuningRow(
                        title: "Key Rotation (0-360 deg)",
                        value: Binding(
                            get: { keyRotationDegrees(selection.key) },
                            set: { newValue in
                                onUpdateKeyRotation(
                                    selection.key,
                                    ContentView.normalizedRotationDegrees(newValue)
                                )
                            }
                        ),
                        formatter: ContentView.rotationDegreesFormatter,
                        range: ContentView.rotationDegreesRange,
                        sliderStep: 1.0,
                        buttonStep: 0.5,
                        showSlider: false
                    )
                }
                Text("Custom Buttons")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                addButtonsRow
                if let selection = buttonSelection {
                    VStack(alignment: .leading, spacing: 6) {
                        VStack(alignment: .leading, spacing: 14) {
                            ColumnTuningRow(
                                title: "X (%)",
                                value: positionBinding(for: selection.button, axis: .x),
                                formatter: ContentView.buttonGeometryPercentFormatter,
                                range: positionRange(for: selection.button, axis: .x),
                                sliderStep: 1.0,
                                buttonStep: 0.5,
                                showSlider: false
                            )
                            ColumnTuningRow(
                                title: "Y (%)",
                                value: positionBinding(for: selection.button, axis: .y),
                                formatter: ContentView.buttonGeometryPercentFormatter,
                                range: positionRange(for: selection.button, axis: .y),
                                sliderStep: 1.0,
                                buttonStep: 0.5,
                                showSlider: false
                            )
                            ColumnTuningRow(
                                title: "Width (%)",
                                value: sizeBinding(for: selection.button, dimension: .width),
                                formatter: ContentView.buttonGeometryPercentFormatter,
                                range: sizeRange(for: selection.button, dimension: .width),
                                sliderStep: 1.0,
                                buttonStep: 0.5,
                                showSlider: false
                            )
                            ColumnTuningRow(
                                title: "Height (%)",
                                value: sizeBinding(for: selection.button, dimension: .height),
                                formatter: ContentView.buttonGeometryPercentFormatter,
                                range: sizeRange(for: selection.button, dimension: .height),
                                sliderStep: 1.0,
                                buttonStep: 0.5,
                                showSlider: false
                            )
                        }
                        HStack {
                            Button("Deleted Selected Button") {
                                onRemoveCustomButton(selection.button.id)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    onClearTouchState()
                }
            )
        }

        private var addButtonsRow: some View {
            HStack(spacing: 8) {
                Button("Add Left") {
                    onAddCustomButton(.left)
                }
                Spacer()
                Button("Add Right") {
                    onAddCustomButton(.right)
                }
            }
        }

        private enum CustomButtonAxis {
            case x
            case y
        }

        private enum CustomButtonDimension {
            case width
            case height
        }

        private func positionBinding(
            for button: CustomButton,
            axis: CustomButtonAxis
        ) -> Binding<Double> {
            Binding(
                get: {
                    let value = axis == .x ? button.rect.x : button.rect.y
                    return Double(value * 100.0)
                },
                set: { newValue in
                    onUpdateButton(button.id) { updated in
                        let rect = updated.rect
                        let maxNormalized = axis == .x
                            ? (1.0 - rect.width)
                            : (1.0 - rect.height)
                        let upper = max(0.0, Double(maxNormalized))
                        let normalized = min(max(newValue / 100.0, 0.0), upper)
                        var next = rect
                        if axis == .x {
                            next.x = CGFloat(normalized)
                        } else {
                            next.y = CGFloat(normalized)
                        }
                        updated.rect = next.clamped(
                            minWidth: ContentView.minCustomButtonSize.width,
                            minHeight: ContentView.minCustomButtonSize.height
                        )
                    }
                }
            )
        }

        private func positionRange(
            for button: CustomButton,
            axis: CustomButtonAxis
        ) -> ClosedRange<Double> {
            let rect = button.rect
            let maxNormalized = axis == .x
                ? (1.0 - rect.width)
                : (1.0 - rect.height)
            let upper = max(0.0, Double(maxNormalized)) * 100.0
            return 0.0...upper
        }

        private func sizeBinding(
            for button: CustomButton,
            dimension: CustomButtonDimension
        ) -> Binding<Double> {
            Binding(
                get: {
                    let value = dimension == .width ? button.rect.width : button.rect.height
                    return Double(value * 100.0)
                },
                set: { newValue in
                    onUpdateButton(button.id) { updated in
                        let rect = updated.rect
                        let maxNormalized = dimension == .width
                            ? (1.0 - rect.x)
                            : (1.0 - rect.y)
                        let minNormalized = dimension == .width
                            ? ContentView.minCustomButtonSize.width
                            : ContentView.minCustomButtonSize.height
                        let upper = max(minNormalized, maxNormalized)
                        let normalized = min(max(newValue / 100.0, minNormalized), upper)
                        var next = rect
                        if dimension == .width {
                            next.width = CGFloat(normalized)
                        } else {
                            next.height = CGFloat(normalized)
                        }
                        updated.rect = next.clamped(
                            minWidth: ContentView.minCustomButtonSize.width,
                            minHeight: ContentView.minCustomButtonSize.height
                        )
                    }
                }
            )
        }

        private func sizeRange(
            for button: CustomButton,
            dimension: CustomButtonDimension
        ) -> ClosedRange<Double> {
            let rect = button.rect
            let maxNormalized = dimension == .width
                ? (1.0 - rect.x)
                : (1.0 - rect.y)
            let minNormalized = dimension == .width
                ? ContentView.minCustomButtonSize.width
                : ContentView.minCustomButtonSize.height
            let upper = max(minNormalized, maxNormalized) * 100.0
            let lower = minNormalized * 100.0
            return lower...upper
        }
    }

    private struct ModeTogglesSectionView: View {
        @Binding var autocorrectEnabled: Bool
        @Binding var snapRadiusPercentSetting: Double
        @Binding var chordalShiftEnabled: Bool
        @Binding var keyboardModeEnabled: Bool
        @Binding var runAtStartupEnabled: Bool
        @Binding var autoResyncEnabled: Bool

        private let labelWidth: CGFloat = 140

        private var snapRadiusEnabledBinding: Binding<Bool> {
            Binding(
                get: { snapRadiusPercentSetting > 0 },
                set: { snapRadiusPercentSetting = $0 ? 100.0 : 0.0 }
            )
        }

        var body: some View {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Keyboard/Mouse")
                        .frame(width: labelWidth, alignment: .leading)
                    Toggle("", isOn: $keyboardModeEnabled)
                        .toggleStyle(SwitchToggleStyle())
                        .labelsHidden()
                    Text("Autocorrect")
                        .frame(width: labelWidth, alignment: .leading)
                    Toggle("", isOn: $autocorrectEnabled)
                        .toggleStyle(SwitchToggleStyle())
                        .labelsHidden()
                }
                GridRow {
                    Text("Chordal Shift")
                        .frame(width: labelWidth, alignment: .leading)
                    Toggle("", isOn: $chordalShiftEnabled)
                        .toggleStyle(SwitchToggleStyle())
                        .labelsHidden()
                    Text("Snap Radius")
                        .frame(width: labelWidth, alignment: .leading)
                    Toggle("", isOn: snapRadiusEnabledBinding)
                        .toggleStyle(SwitchToggleStyle())
                        .labelsHidden()
                }
                GridRow {
                    Text("Run at Startup")
                        .frame(width: labelWidth, alignment: .leading)
                    Toggle("", isOn: $runAtStartupEnabled)
                        .toggleStyle(SwitchToggleStyle())
                        .labelsHidden()
                    Text("Auto-resync")
                        .frame(width: labelWidth, alignment: .leading)
                    Toggle("", isOn: $autoResyncEnabled)
                        .toggleStyle(SwitchToggleStyle())
                        .labelsHidden()
                        .help("Polls every 8 seconds to detect disconnected trackpads.")
                }
            }
        }
    }

    private struct TypingTuningSectionView: View {
        @Binding var tapHoldDurationMs: Double
        @Binding var dragCancelDistanceSetting: Double
        @Binding var forceClickMinSetting: Double
        @Binding var forceClickCapSetting: Double
        @Binding var hapticStrengthSetting: Double
        @Binding var typingGraceMsSetting: Double
        @Binding var intentMoveThresholdMmSetting: Double
        @Binding var intentVelocityThresholdMmPerSecSetting: Double
        @Binding var tapClickCadenceMsSetting: Double
        let onRestoreDefaults: () -> Void

        private let labelWidth: CGFloat = 140
        private let valueFieldWidth: CGFloat = 50

        private enum HapticStrengthStep: Int, CaseIterable {
            case off = 0
            case weak
            case medium
            case strong

            var percent: Double {
                switch self {
                case .off: return 0.0
                case .weak: return 40.0
                case .medium: return 60.0
                case .strong: return 100.0
                }
            }

            var label: String {
                switch self {
                case .off: return "Off"
                case .weak: return "Weak"
                case .medium: return "Medium"
                case .strong: return "Strong"
                }
            }

            static func nearest(to percent: Double) -> Self {
                allCases.min(by: { abs($0.percent - percent) < abs($1.percent - percent) })
                    ?? .off
            }
        }

        private var currentHapticStrengthStep: HapticStrengthStep {
            HapticStrengthStep.nearest(to: hapticStrengthSetting)
        }

        private var hapticStrengthIndexBinding: Binding<Double> {
            Binding(
                get: { Double(currentHapticStrengthStep.rawValue) },
                set: { newValue in
                    let index = Int(newValue.rounded())
                    let step = HapticStrengthStep(rawValue: index) ?? .off
                    hapticStrengthSetting = step.percent
                }
            )
        }

        var body: some View {
            VStack(spacing: 8) {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        Text("Hold Duration (ms)")
                            .frame(width: labelWidth, alignment: .leading)
                        TextField(
                            "200",
                            value: $tapHoldDurationMs,
                            formatter: ContentView.tapHoldDurationFormatter
                        )
                        .frame(width: valueFieldWidth)
                        Slider(
                            value: $tapHoldDurationMs,
                            in: ContentView.tapHoldDurationRange,
                            step: 10
                        )
                        .frame(minWidth: 100)
                        .gridCellColumns(2)
                    }
                    GridRow {
                        Text("Tap Cadence (ms)")
                            .frame(width: labelWidth, alignment: .leading)
                        TextField(
                            "280",
                            value: $tapClickCadenceMsSetting,
                            formatter: ContentView.twoFingerClickCadenceFormatter
                        )
                        .frame(width: valueFieldWidth)
                        Slider(
                            value: $tapClickCadenceMsSetting,
                            in: ContentView.twoFingerClickCadenceRange,
                            step: 10
                        )
                        .frame(minWidth: 120)
                        .gridCellColumns(2)
                    }
                    GridRow {
                        Text("Typing Grace (ms)")
                            .frame(width: labelWidth, alignment: .leading)
                        TextField(
                            "120",
                            value: $typingGraceMsSetting,
                            formatter: ContentView.typingGraceFormatter
                        )
                        .frame(width: valueFieldWidth)
                        Slider(
                            value: $typingGraceMsSetting,
                            in: ContentView.typingGraceRange,
                            step: 100
                        )
                        .frame(minWidth: 120)
                        .gridCellColumns(2)
                    }
                    GridRow {
                        Text("Drag Cancel (mm)")
                            .frame(width: labelWidth, alignment: .leading)
                        TextField(
                            "1",
                            value: $dragCancelDistanceSetting,
                            formatter: ContentView.dragCancelDistanceFormatter
                        )
                        .frame(width: valueFieldWidth)
                        Slider(
                            value: $dragCancelDistanceSetting,
                            in: ContentView.dragCancelDistanceRange,
                            step: 1
                        )
                        .frame(minWidth: 120)
                        .gridCellColumns(2)
                    }
                    GridRow {
                        Text("Intent Move (mm)")
                            .frame(width: labelWidth, alignment: .leading)
                        TextField(
                            "3.0",
                            value: $intentMoveThresholdMmSetting,
                            formatter: ContentView.intentMoveThresholdFormatter
                        )
                        .frame(width: valueFieldWidth)
                        Slider(
                            value: $intentMoveThresholdMmSetting,
                            in: ContentView.intentMoveThresholdRange,
                            step: 0.1
                        )
                        .frame(minWidth: 120)
                        .gridCellColumns(2)
                    }
                    GridRow {
                        Text("Intent Velocity (mm/s)")
                            .frame(width: labelWidth, alignment: .leading)
                        TextField(
                            "50",
                            value: $intentVelocityThresholdMmPerSecSetting,
                            formatter: ContentView.intentVelocityThresholdFormatter
                        )
                        .frame(width: valueFieldWidth)
                        Slider(
                            value: $intentVelocityThresholdMmPerSecSetting,
                            in: ContentView.intentVelocityThresholdRange,
                            step: 5
                        )
                        .frame(minWidth: 120)
                        .gridCellColumns(2)
                    }
                    GridRow {
                        Text("Force Min")
                            .frame(width: labelWidth, alignment: .leading)
                        TextField(
                            "0",
                            value: $forceClickMinSetting,
                            formatter: ContentView.forceClickFormatter
                        )
                        .frame(width: valueFieldWidth)
                        Slider(
                            value: $forceClickMinSetting,
                            in: ContentView.forceClickRange,
                            step: 1
                        )
                        .frame(minWidth: 120)
                        .gridCellColumns(2)
                    }
                    GridRow {
                        Text("Force Max")
                            .frame(width: labelWidth, alignment: .leading)
                        TextField(
                            "0",
                            value: $forceClickCapSetting,
                            formatter: ContentView.forceClickFormatter
                        )
                        .frame(width: valueFieldWidth)
                        Slider(
                            value: $forceClickCapSetting,
                            in: ContentView.forceClickRange,
                            step: 1
                        )
                        .frame(minWidth: 120)
                        .gridCellColumns(2)
                    }
                    GridRow {
                        Text("Haptic Strength Slider")
                            .frame(width: labelWidth, alignment: .leading)
                        Text(currentHapticStrengthStep.label)
                            .frame(width: valueFieldWidth, alignment: .leading)
                        Slider(
                            value: hapticStrengthIndexBinding,
                            in: 0...Double(HapticStrengthStep.allCases.count - 1),
                            step: 1
                        )
                        .frame(minWidth: 120)
                        .gridCellColumns(2)
                    }
                    GridRow {
                        Button("Restore Defaults") {
                            onRestoreDefaults()
                        }
                        .buttonStyle(.borderedProminent)
                        .gridCellColumns(2)
                        Spacer()
                            .gridCellColumns(2)
                    }
                }
            }
        }

    }

    private struct GestureTuningSectionView: View {
        @Binding var twoFingerTapGestureAction: String
        @Binding var threeFingerTapGestureAction: String
        @Binding var twoFingerHoldGestureAction: String
        @Binding var threeFingerHoldGestureAction: String
        @Binding var fourFingerHoldGestureAction: String
        @Binding var outerCornersHoldGestureAction: String
        @Binding var innerCornersHoldGestureAction: String
        @Binding var fiveFingerSwipeLeftGestureAction: String
        @Binding var fiveFingerSwipeRightGestureAction: String
        @State private var tapsExpanded = false
        @State private var holdsExpanded = true
        @State private var swipesExpanded = false

        private func gestureBinding(
            _ rawValue: Binding<String>,
            fallbackLabel: String
        ) -> Binding<KeyAction> {
            Binding(
                get: {
                    KeyActionCatalog.action(for: rawValue.wrappedValue)
                        ?? KeyActionCatalog.action(for: fallbackLabel)
                        ?? KeyActionCatalog.noneAction
                },
                set: { rawValue.wrappedValue = $0.label }
            )
        }

        @ViewBuilder
        private func gesturePicker(
            _ title: String,
            selection: Binding<String>,
            fallbackLabel: String
        ) -> some View {
            Picker(
                title,
                selection: gestureBinding(
                    selection,
                    fallbackLabel: fallbackLabel
                )
            ) {
                ForEach(KeyActionCatalog.primaryActionGroups.indices, id: \.self) { index in
                    let group = KeyActionCatalog.primaryActionGroups[index]
                    ContentView.pickerGroupHeader(group.title)
                    ForEach(group.actions, id: \.self) { action in
                        ContentView.pickerLabel(for: action).tag(action)
                    }
                }
            }
            .pickerStyle(MenuPickerStyle())
            .gridCellColumns(3)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                DisclosureGroup(
                    isExpanded: $tapsExpanded
                ) {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                        GridRow {
                            gesturePicker(
                                "2-finger tap",
                                selection: $twoFingerTapGestureAction,
                                fallbackLabel: GlassToKeySettings.twoFingerTapGestureActionLabel
                            )
                        }
                        GridRow {
                            gesturePicker(
                                "3-finger tap",
                                selection: $threeFingerTapGestureAction,
                                fallbackLabel: GlassToKeySettings.threeFingerTapGestureActionLabel
                            )
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Text("Taps")
                }

                DisclosureGroup(
                    isExpanded: $holdsExpanded
                ) {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                        GridRow {
                            gesturePicker(
                                "2-finger hold",
                                selection: $twoFingerHoldGestureAction,
                                fallbackLabel: GlassToKeySettings.twoFingerHoldGestureActionLabel
                            )
                        }
                        GridRow {
                            gesturePicker(
                                "3-finger hold",
                                selection: $threeFingerHoldGestureAction,
                                fallbackLabel: GlassToKeySettings.threeFingerHoldGestureActionLabel
                            )
                        }
                        GridRow {
                            gesturePicker(
                                "4-finger hold",
                                selection: $fourFingerHoldGestureAction,
                                fallbackLabel: GlassToKeySettings.fourFingerHoldGestureActionLabel
                            )
                        }
                        GridRow {
                            gesturePicker(
                                "Inner corners",
                                selection: $innerCornersHoldGestureAction,
                                fallbackLabel: GlassToKeySettings.innerCornersHoldGestureActionLabel
                            )
                        }
                        GridRow {
                            gesturePicker(
                                "Outer corners",
                                selection: $outerCornersHoldGestureAction,
                                fallbackLabel: GlassToKeySettings.outerCornersHoldGestureActionLabel
                            )
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Text("Holds")
                }

                DisclosureGroup(
                    isExpanded: $swipesExpanded
                ) {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                        GridRow {
                            gesturePicker(
                                "5-finger swipe left",
                                selection: $fiveFingerSwipeLeftGestureAction,
                                fallbackLabel: GlassToKeySettings.fiveFingerSwipeLeftGestureActionLabel
                            )
                        }
                        GridRow {
                            gesturePicker(
                                "5-finger swipe right",
                                selection: $fiveFingerSwipeRightGestureAction,
                                fallbackLabel: GlassToKeySettings.fiveFingerSwipeRightGestureActionLabel
                            )
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Text("Swipes")
                }
            }
        }
    }

    private struct TrackpadDeckView: View {
        @ObservedObject var viewModel: ContentViewModel
        let trackpadSize: CGSize
        let leftLayout: ContentViewModel.Layout
        let rightLayout: ContentViewModel.Layout
        let leftBaseLabels: [[String]]
        let rightBaseLabels: [[String]]
        let leftGridLabelInfo: [[GridLabel]]
        let rightGridLabelInfo: [[GridLabel]]
        let customButtons: [CustomButton]
        @Binding var editModeEnabled: Bool
        let lastHitLeft: ContentViewModel.DebugHit?
        let lastHitRight: ContentViewModel.DebugHit?
        @Binding var selectedButtonID: UUID?
        @Binding var selectedGridKey: SelectedGridKey?

        private let trackpadSpacing: CGFloat = 16
        private var combinedWidth: CGFloat {
            (trackpadSize.width * 2) + trackpadSpacing
        }

        var body: some View {
            let leftButtons = customButtons(for: .left)
            let rightButtons = customButtons(for: .right)
            let showDetailedView = true
            let selectedLeftKey = selectedGridKey?.side == .left ? selectedGridKey : nil
            let selectedRightKey = selectedGridKey?.side == .right ? selectedGridKey : nil

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: trackpadSpacing) {
                    Text("Left Trackpad")
                        .font(.subheadline)
                        .frame(width: trackpadSize.width, alignment: .leading)
                    Text("Right Trackpad")
                        .font(.subheadline)
                        .frame(width: trackpadSize.width, alignment: .leading)
                }
                ZStack(alignment: .topLeading) {
                    TrackpadSurfaceRepresentable(
                        snapshot: TrackpadSurfaceSnapshot(
                            trackpadSize: trackpadSize,
                            spacing: trackpadSpacing,
                            showDetailed: showDetailedView,
                            replayModeEnabled: viewModel.replayTimelineState != nil,
                            leftLayout: leftLayout,
                            rightLayout: rightLayout,
                            leftLabels: surfaceLabels(from: leftGridLabelInfo),
                            rightLabels: surfaceLabels(from: rightGridLabelInfo),
                            leftCustomButtons: leftButtons,
                            rightCustomButtons: rightButtons,
                            selectedLeftKey: editModeEnabled ? surfaceKeySelection(from: selectedLeftKey) : nil,
                            selectedRightKey: editModeEnabled ? surfaceKeySelection(from: selectedRightKey) : nil,
                            selectedLeftButtonID: editModeEnabled ? selectedButton(for: leftButtons)?.id : nil,
                            selectedRightButtonID: editModeEnabled ? selectedButton(for: rightButtons)?.id : nil
                        ),
                        viewModel: viewModel,
                        editModeEnabled: editModeEnabled,
                        selectionHandler: surfaceSelectionChanged
                    )
                    .frame(width: combinedWidth, height: trackpadSize.height)
                    if !editModeEnabled {
                        if let hit = lastHitLeft {
                            LastHitHighlightLayer(lastHit: hit)
                                .frame(width: trackpadSize.width, height: trackpadSize.height)
                                .offset(x: 0, y: 0)
                        }
                        if let hit = lastHitRight {
                            LastHitHighlightLayer(lastHit: hit)
                                .frame(width: trackpadSize.width, height: trackpadSize.height)
                                .offset(x: trackpadSize.width + trackpadSpacing, y: 0)
                        }
                    }
                }
                .frame(width: combinedWidth, height: trackpadSize.height)
            }
        }

        private func customButtons(for side: TrackpadSide) -> [CustomButton] {
            customButtons.filter { $0.side == side && $0.layer == viewModel.activeLayer }
        }

        private func selectedButton(for buttons: [CustomButton]) -> CustomButton? {
            guard let selectedButtonID else { return nil }
            return buttons.first { $0.id == selectedButtonID }
        }

        private func surfaceLabels(from labels: [[GridLabel]]) -> [[TrackpadSurfaceLabel]] {
            labels.map { row in
                row.map { label in
                    TrackpadSurfaceLabel(primary: label.primary, hold: label.hold)
                }
            }
        }

        private func surfaceKeySelection(from key: SelectedGridKey?) -> TrackpadSurfaceKeySelection? {
            guard let key else { return nil }
            return TrackpadSurfaceKeySelection(row: key.row, column: key.column)
        }

        private func surfaceSelectionChanged(_ selection: TrackpadSurfaceSelectionEvent) {
            guard editModeEnabled else { return }
            viewModel.clearTouchState()
            switch selection.target {
            case .button(let id):
                selectedButtonID = id
                selectedGridKey = nil
            case .key(let row, let column, let label):
                selectedButtonID = nil
                let labels = selection.side == .left ? leftBaseLabels : rightBaseLabels
                let resolvedLabel: String
                if labels.indices.contains(row), labels[row].indices.contains(column) {
                    resolvedLabel = labels[row][column]
                } else {
                    resolvedLabel = label
                }
                selectedGridKey = SelectedGridKey(
                    row: row,
                    column: column,
                    label: resolvedLabel,
                    side: selection.side
                )
            case .none:
                selectedButtonID = nil
                selectedGridKey = nil
            }
        }

    }

    private struct LastHitHighlightLayer: View {
        let lastHit: ContentViewModel.DebugHit

        var body: some View {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
                let age = CACurrentMediaTime() - lastHit.timestamp
                let fadeDuration: TimeInterval = 0.6
                let normalized = max(0, fadeDuration - age) / fadeDuration
                if normalized <= 0 {
                    EmptyView()
                } else {
                    Canvas { context, _ in
                        let cornerRadius = ContentView.keyCornerRadius
                        let highlightColor = Color.green.opacity(normalized * 0.95)
                        let strokePath = Path(roundedRect: lastHit.rect, cornerRadius: cornerRadius)
                        context.stroke(
                            strokePath,
                            with: .color(highlightColor),
                            lineWidth: 2.5
                        )
                    }
                }
            }
        }
    }

    static func makeKeyLayout(
        size: CGSize,
        keyWidth: CGFloat,
        keyHeight: CGFloat,
        columns: Int,
        rows: Int,
        trackpadWidth: CGFloat,
        trackpadHeight: CGFloat,
        columnAnchorsMM: [CGPoint],
        columnSettings: [ColumnLayoutSettings],
        keyGeometryOverrides: KeyGeometryOverrides = [:],
        mirrored: Bool = false
    ) -> ContentViewModel.Layout {
        guard columns > 0,
              rows > 0,
              columnAnchorsMM.count == columns else {
            return ContentViewModel.Layout(normalizedKeyRects: [], trackpadSize: size)
        }
        let scaleX = size.width / trackpadWidth
        let scaleY = size.height / trackpadHeight
        let resolvedSettings = normalizedColumnSettings(
            columnSettings,
            columns: columns
        )
        let columnScales = resolvedSettings.map { CGFloat($0.scale) }
        let adjustedAnchorsMM = scaledColumnAnchorsMM(
            columnAnchorsMM,
            columnScales: columnScales
        )

        var keyRects: [[CGRect]] = Array(
            repeating: Array(repeating: .zero, count: columns),
            count: rows
        )
        for row in 0..<rows {
            for col in 0..<columns {
                let anchorMM = adjustedAnchorsMM[col]
                let scale = columnScales[col]
                let keySize = CGSize(
                    width: keyWidth * scale * scaleX,
                    height: keyHeight * scale * scaleY
                )
                let rowSpacingPercent = resolvedSettings[col].rowSpacingPercent
                let rowSpacing = keySize.height * CGFloat(rowSpacingPercent / 100.0)
                keyRects[row][col] = CGRect(
                    x: anchorMM.x * scaleX,
                    y: anchorMM.y * scaleY + CGFloat(row) * (keySize.height + rowSpacing),
                    width: keySize.width,
                    height: keySize.height
                )
            }
        }

        var normalizedKeyRects = keyRects.map { row in
            row.map { normalizedRect(for: $0, in: size) }
        }

        let columnOffsets = resolvedSettings.map { setting in
            CGSize(
                width: size.width * CGFloat(setting.offsetXPercent / 100.0),
                height: size.height * CGFloat(setting.offsetYPercent / 100.0)
            )
        }

        applyColumnOffsets(keyRects: &normalizedKeyRects, columnOffsets: columnOffsets, size: size)
        applyColumnRotations(keyRects: &normalizedKeyRects, columnSettings: resolvedSettings)
        applyKeyGeometryOverrides(
            keyRects: &normalizedKeyRects,
            keyGeometryOverrides: keyGeometryOverrides,
            mirrored: mirrored
        )

        if mirrored {
            let mirroredKeyRects = normalizedKeyRects.map { row in
                row.map { $0.mirroredHorizontally() }
            }
            return ContentViewModel.Layout(normalizedKeyRects: mirroredKeyRects, trackpadSize: size)
        }

        return ContentViewModel.Layout(normalizedKeyRects: normalizedKeyRects, trackpadSize: size)
    }

    private static func scaledColumnAnchorsMM(
        _ anchors: [CGPoint],
        columnScales: [CGFloat]
    ) -> [CGPoint] {
        guard let originX = anchors.first?.x else { return anchors }
        return anchors.enumerated().map { index, anchor in
            let scale = columnScales.indices.contains(index) ? columnScales[index] : 1.0
            let offsetX = anchor.x - originX
            return CGPoint(x: originX + offsetX * scale, y: anchor.y)
        }
    }

    private static func applyColumnOffsets(
        keyRects: inout [[NormalizedRect]],
        columnOffsets: [CGSize],
        size: CGSize
    ) {
        guard !columnOffsets.isEmpty, size.width > 0, size.height > 0 else { return }
        for rowIndex in 0..<keyRects.count {
            for colIndex in 0..<keyRects[rowIndex].count {
                let offset = columnOffsets.indices.contains(colIndex)
                    ? columnOffsets[colIndex]
                    : .zero
                keyRects[rowIndex][colIndex].x += offset.width / size.width
                keyRects[rowIndex][colIndex].y += offset.height / size.height
            }
        }
    }

    private static func applyColumnRotations(
        keyRects: inout [[NormalizedRect]],
        columnSettings: [ColumnLayoutSettings]
    ) {
        guard !keyRects.isEmpty, let lastRow = keyRects.indices.last else { return }
        for col in keyRects[0].indices {
            guard columnSettings.indices.contains(col) else { continue }
            let rotationDegrees = -normalizedRotationDegrees(columnSettings[col].rotationDegrees)
            guard abs(rotationDegrees) >= 0.000_01 else { continue }
            let pivotX = keyRects[0][col].centerX
            let pivotY = (keyRects[0][col].centerY + keyRects[lastRow][col].centerY) * 0.5
            for row in keyRects.indices {
                keyRects[row][col] = keyRects[row][col].rotatedAround(
                    pivotX: pivotX,
                    pivotY: pivotY,
                    rotationDegrees: rotationDegrees
                )
            }
        }
    }

    private static func applyKeyGeometryOverrides(
        keyRects: inout [[NormalizedRect]],
        keyGeometryOverrides: KeyGeometryOverrides,
        mirrored: Bool
    ) {
        guard !keyGeometryOverrides.isEmpty else { return }
        let side: TrackpadSide = mirrored ? .left : .right
        for row in keyRects.indices {
            for col in keyRects[row].indices {
                let storageKey = GridKeyPosition(side: side, row: row, column: col).storageKey
                guard let geometry = keyGeometryOverrides[storageKey] else { continue }
                let rotationDegrees = -normalizedRotationDegrees(geometry.rotationDegrees)
                guard abs(rotationDegrees) >= 0.000_01 else { continue }
                let rect = keyRects[row][col]
                keyRects[row][col] = rect.rotatedAround(
                    pivotX: rect.centerX,
                    pivotY: rect.centerY,
                    rotationDegrees: rotationDegrees
                )
            }
        }
    }

    private static func normalizedRect(for rect: CGRect, in size: CGSize) -> NormalizedRect {
        guard size.width > 0, size.height > 0 else {
            return NormalizedRect(x: 0, y: 0, width: 0, height: 0)
        }
        return NormalizedRect(
            x: rect.minX / size.width,
            y: rect.minY / size.height,
            width: rect.width / size.width,
            height: rect.height / size.height
        )
    }

    private static func makeMobileKeyLayout(size: CGSize) -> ContentViewModel.Layout {
        let scaleX = size.width / Self.trackpadWidthMM
        let scaleY = size.height / Self.trackpadHeightMM
        var keyRows: [[CGRect]] = []
        var currentY = mobileTopInsetMM
        for row in MobileLayoutDefinition.rows {
            let (rowRects, rowHeight) = mobileRowRects(for: row, y: currentY)
            let scaledRects = rowRects.map { rect in
                CGRect(
                    x: rect.minX * scaleX,
                    y: rect.minY * scaleY,
                    width: rect.width * scaleX,
                    height: rect.height * scaleY
                )
            }
            keyRows.append(scaledRects)
            currentY += rowHeight + mobileRowSpacingMM
        }
        return ContentViewModel.Layout(
            keyRects: keyRows,
            trackpadSize: size,
            allowHoldBindings: false
        )
    }

    private static func mobileRowRects(
        for row: MobileLayoutRow,
        y: CGFloat
    ) -> ([CGRect], CGFloat) {
        let totalSpacing = mobileKeySpacingMM * CGFloat(max(row.widthMultipliers.count - 1, 0))
        let keyWidths = row.widthMultipliers.map { $0 * mobileKeyWidthMM }
        let totalWidth = keyWidths.reduce(0, +) + totalSpacing
        let availableSpace = max(Self.trackpadWidthMM - totalWidth, 0)
        let centeredX = availableSpace / 2 + row.staggerOffset
        let startX = min(max(centeredX, 0), availableSpace)
        var x = startX
        var rects: [CGRect] = []
        for width in keyWidths {
            rects.append(CGRect(x: x, y: y, width: width, height: mobileKeyHeightMM))
            x += width + mobileKeySpacingMM
        }
        return (rects, mobileKeyHeightMM)
    }

    private static func normalizedColumnSettings(
        _ settings: [ColumnLayoutSettings],
        columns: Int
    ) -> [ColumnLayoutSettings] {
        ColumnLayoutDefaults.normalizedSettings(settings, columns: columns)
    }

    fileprivate static func normalizedColumnScale(_ value: Double) -> Double {
        min(max(value, Self.columnScaleRange.lowerBound), Self.columnScaleRange.upperBound)
    }

    fileprivate static func normalizedColumnOffsetPercent(_ value: Double) -> Double {
        min(
            max(value, Self.columnOffsetPercentRange.lowerBound),
            Self.columnOffsetPercentRange.upperBound
        )
    }

    fileprivate static func normalizedRowSpacingPercent(_ value: Double) -> Double {
        min(max(value, Self.rowSpacingPercentRange.lowerBound), Self.rowSpacingPercentRange.upperBound)
    }

    fileprivate static func normalizedRotationDegrees(_ value: Double) -> Double {
        min(max(value, Self.rotationDegreesRange.lowerBound), Self.rotationDegreesRange.upperBound)
    }

    private func normalizeEditColumnIndex(for count: Int) {
        guard count > 0 else {
            editColumnIndex = 0
            return
        }
        editColumnIndex = min(max(editColumnIndex, 0), count - 1)
    }

    private func updateColumnSetting(
        index: Int,
        update: (inout ColumnLayoutSettings) -> Void
    ) {
        guard columnSettings.indices.contains(index) else { return }
        var setting = columnSettings[index]
        update(&setting)
        columnSettings[index] = setting
    }

    private func updateColumnSettingAndSelection(
        index: Int,
        update: (inout ColumnLayoutSettings) -> Void
    ) {
        updateColumnSetting(index: index, update: update)
        refreshColumnInspectorSelection()
    }

    private func applyAutoSplay() {
        guard layoutOption.allowsColumnSettings else { return }
        guard isAutoSplaySupportedPreset else {
            showKeymapAlert(
                title: "Auto Splay",
                message: "Auto Splay currently supports 6-column layouts plus 5x3 and 5x4."
            )
            return
        }

        let snapshot = viewModel.snapshotTouchData()
        let leftTouches = collectAutoSplayTouches(from: snapshot.left, mirrored: true)
        let rightTouches = collectAutoSplayTouches(from: snapshot.right, mirrored: false)
        let leftReady = leftTouches.count >= Self.autoSplayTouchCount
        let rightReady = rightTouches.count >= Self.autoSplayTouchCount

        guard !(leftReady && rightReady) else {
            showKeymapAlert(
                title: "Auto Splay",
                message: "Detected 4+ touches on both sides. Keep touches on only one side and retry."
            )
            return
        }

        guard leftReady || rightReady else {
            let message = leftTouches.isEmpty && rightTouches.isEmpty
                ? "Place at least 4 fingertips on one side, then click Auto Splay."
                : "Auto Splay needs at least 4 touches on one side (left: \(leftTouches.count), right: \(rightTouches.count))."
            showKeymapAlert(title: "Auto Splay", message: message)
            return
        }

        var selectedTouches = leftReady ? leftTouches : rightTouches
        if selectedTouches.count > Self.autoSplayTouchCount,
           let lowestIndex = selectedTouches.indices.max(by: { selectedTouches[$0].yNorm < selectedTouches[$1].yNorm }) {
            selectedTouches.remove(at: lowestIndex)
        }
        selectedTouches.sort { lhs, rhs in
            if lhs.xNorm == rhs.xNorm {
                return lhs.yNorm < rhs.yNorm
            }
            return lhs.xNorm < rhs.xNorm
        }
        if selectedTouches.count > Self.autoSplayTouchCount {
            selectedTouches = Array(selectedTouches.prefix(Self.autoSplayTouchCount))
        }

        guard selectedTouches.count == Self.autoSplayTouchCount else {
            showKeymapAlert(
                title: "Auto Splay",
                message: "Auto Splay requires \(Self.autoSplayTouchCount) touches."
            )
            return
        }

        let referenceRow = resolveAutoSplayReferenceRow()
        guard rightLayout.keyRects.indices.contains(referenceRow) else {
            showKeymapAlert(
                title: "Auto Splay",
                message: "Auto Splay could not resolve a valid reference row.",
                style: .warning
            )
            return
        }

        let referenceRects = rightLayout.keyRects[referenceRow]
        var updated = columnSettings

        if layoutOption.columns == 6, updated.count >= 6, referenceRects.count >= 6 {
            let leftEdgeOffsetX = updated[0].offsetXPercent - updated[1].offsetXPercent
            let rightEdgeOffsetX = updated[5].offsetXPercent - updated[4].offsetXPercent

            for index in 0..<Self.autoSplayTouchCount {
                let column = index + 1
                let center = normalizedCenter(for: referenceRects[column])
                let target = selectedTouches[index]
                updated[column].offsetXPercent = Self.normalizedColumnOffsetPercent(
                    updated[column].offsetXPercent + ((target.xNorm - center.x) * 100.0)
                )
                updated[column].offsetYPercent = Self.normalizedColumnOffsetPercent(
                    updated[column].offsetYPercent + ((target.yNorm - center.y) * 100.0)
                )
            }

            updated[0].offsetXPercent = Self.normalizedColumnOffsetPercent(updated[1].offsetXPercent + leftEdgeOffsetX)
            updated[0].offsetYPercent = updated[1].offsetYPercent
            updated[5].offsetXPercent = Self.normalizedColumnOffsetPercent(updated[4].offsetXPercent + rightEdgeOffsetX)
            updated[5].offsetYPercent = updated[4].offsetYPercent
            columnSettings = updated
            return
        }

        if isFiveColumnAutoSplayPreset, layoutOption.columns == 5, updated.count >= 5, referenceRects.count >= 5 {
            for index in 0..<Self.autoSplayTouchCount {
                let center = normalizedCenter(for: referenceRects[index])
                let target = selectedTouches[index]
                updated[index].offsetXPercent = Self.normalizedColumnOffsetPercent(
                    updated[index].offsetXPercent + ((target.xNorm - center.x) * 100.0)
                )
                updated[index].offsetYPercent = Self.normalizedColumnOffsetPercent(
                    updated[index].offsetYPercent + ((target.yNorm - center.y) * 100.0)
                )
            }

            updated[4].offsetXPercent = updated[3].offsetXPercent
            updated[4].offsetYPercent = updated[3].offsetYPercent
            columnSettings = updated
            return
        }

        showKeymapAlert(
            title: "Auto Splay",
            message: "Auto Splay could not apply to this layout configuration.",
            style: .warning
        )
    }

    private func applyEvenColumnSpacing() {
        guard layoutOption.allowsColumnSettings,
              layoutOption.columns >= 3,
              columnSettings.count >= layoutOption.columns else {
            showKeymapAlert(
                title: "Even spacing",
                message: "Even spacing requires a layout with at least 3 editable columns."
            )
            return
        }

        let referenceRow = resolveAutoSplayReferenceRow()
        guard rightLayout.keyRects.indices.contains(referenceRow),
              rightLayout.keyRects[referenceRow].count >= layoutOption.columns else {
            showKeymapAlert(
                title: "Even spacing",
                message: "Even spacing could not resolve a valid reference row."
            )
            return
        }

        let rects = rightLayout.keyRects[referenceRow]
        let lastColumn = layoutOption.columns - 1
        let firstCenter = normalizedCenter(for: rects[0]).x
        let lastCenter = normalizedCenter(for: rects[lastColumn]).x
        let step = (lastCenter - firstCenter) / Double(lastColumn)

        var updated = columnSettings
        for column in 1..<lastColumn {
            let currentCenter = normalizedCenter(for: rects[column]).x
            let targetCenter = firstCenter + (step * Double(column))
            updated[column].offsetXPercent = Self.normalizedColumnOffsetPercent(
                updated[column].offsetXPercent + ((targetCenter - currentCenter) * 100.0)
            )
        }

        columnSettings = updated
    }

    private func collectAutoSplayTouches(
        from touches: [OMSTouchData],
        mirrored: Bool
    ) -> [AutoSplayTouch] {
        var resolved: [AutoSplayTouch] = []
        resolved.reserveCapacity(touches.count)
        for touch in touches where isAutoSplayTouchState(touch.state) {
            let x = min(max(Double(touch.position.x), 0.0), 1.0)
            let y = min(max(Double(touch.position.y), 0.0), 1.0)
            let canonicalX = mirrored ? (1.0 - x) : x
            // Touch reports use bottom-origin Y; layouts are top-origin.
            let canonicalY = 1.0 - y
            resolved.append(AutoSplayTouch(xNorm: canonicalX, yNorm: canonicalY))
        }
        return resolved
    }

    private func normalizedCenter(for rect: CGRect) -> (x: Double, y: Double) {
        guard trackpadSize.width > 0, trackpadSize.height > 0 else {
            return (0.0, 0.0)
        }
        let centerX = (rect.minX + (rect.width * 0.5)) / trackpadSize.width
        let centerY = (rect.minY + (rect.height * 0.5)) / trackpadSize.height
        return (
            x: min(max(Double(centerX), 0.0), 1.0),
            y: min(max(Double(centerY), 0.0), 1.0)
        )
    }

    private var isAutoSplaySupportedPreset: Bool {
        layoutOption.columns == 6 || isFiveColumnAutoSplayPreset
    }

    private var isFiveColumnAutoSplayPreset: Bool {
        layoutOption == .fiveByThree || layoutOption == .fiveByFour
    }

    private func resolveAutoSplayReferenceRow() -> Int {
        guard layoutOption.rows > 0 else { return 0 }
        if isFiveColumnAutoSplayPreset || layoutOption == .sixByFour {
            // Keep the reference on the home row (2nd row from bottom).
            return min(max(layoutOption.rows - 2, 0), layoutOption.rows - 1)
        }
        return min(max((layoutOption.rows - 1) / 2, 0), layoutOption.rows - 1)
    }

    private func isAutoSplayTouchState(_ state: OMSState) -> Bool {
        switch state {
        case .starting, .making, .touching, .breaking, .lingering:
            return true
        case .notTouching, .hovering, .leaving:
            return false
        }
    }

    private func applyColumnSettings(_ settings: [ColumnLayoutSettings]) {
        let normalized = Self.normalizedColumnSettings(
            settings,
            columns: layoutColumns
        )
        if normalized != settings {
            columnSettings = normalized
            return
        }
        rebuildLayouts()
    }

    private func handleLayoutOptionChange(_ newLayout: TrackpadLayoutPreset) {
        layoutOption = newLayout
        storedLayoutPreset = newLayout.rawValue
        selectedGridKey = nil
        selectedButtonID = nil
        columnSettings = columnSettings(for: newLayout)
        keyGeometryOverrides = keyGeometryOverrides(for: newLayout)
        editColumnIndex = 0
        customButtons = loadCustomButtons(for: newLayout)
        keyMappingsByLayer = keyMappings(for: newLayout)
        viewModel.updateCustomButtons(customButtons)
        updateGridLabelInfo()
        applyColumnSettings(columnSettings)
        saveSettings()
    }

    private func rebuildLayouts() {
        guard layoutColumns > 0,
              layoutRows > 0,
              layoutColumnAnchors.count == layoutColumns else {
            leftLayout = ContentViewModel.Layout(keyRects: [], trackpadSize: trackpadSize)
            rightLayout = ContentViewModel.Layout(keyRects: [], trackpadSize: trackpadSize)
            viewModel.configureLayouts(
                leftLayout: leftLayout,
                rightLayout: rightLayout,
                leftLabels: leftGridLabels,
                rightLabels: rightGridLabels,
                trackpadSize: trackpadSize,
                trackpadWidthMm: Self.trackpadWidthMM
            )
            return
        }
        if layoutOption.blankLeftSide {
            leftLayout = ContentViewModel.Layout(keyRects: [], trackpadSize: trackpadSize)
            rightLayout = ContentView.makeKeyLayout(
                size: trackpadSize,
                keyWidth: Self.baseKeyWidthMM,
                keyHeight: Self.baseKeyHeightMM,
                columns: layoutColumns,
                rows: layoutRows,
                trackpadWidth: Self.trackpadWidthMM,
                trackpadHeight: Self.trackpadHeightMM,
                columnAnchorsMM: layoutColumnAnchors,
                columnSettings: columnSettings,
                keyGeometryOverrides: keyGeometryOverrides
            )
            viewModel.configureLayouts(
                leftLayout: leftLayout,
                rightLayout: rightLayout,
                leftLabels: leftGridLabels,
                rightLabels: rightGridLabels,
                trackpadSize: trackpadSize,
                trackpadWidthMm: Self.trackpadWidthMM
            )
            return
        }
        leftLayout = ContentView.makeKeyLayout(
            size: trackpadSize,
            keyWidth: Self.baseKeyWidthMM,
            keyHeight: Self.baseKeyHeightMM,
            columns: layoutColumns,
            rows: layoutRows,
            trackpadWidth: Self.trackpadWidthMM,
            trackpadHeight: Self.trackpadHeightMM,
            columnAnchorsMM: layoutColumnAnchors,
            columnSettings: columnSettings,
            keyGeometryOverrides: keyGeometryOverrides,
            mirrored: true
        )
        rightLayout = ContentView.makeKeyLayout(
            size: trackpadSize,
            keyWidth: Self.baseKeyWidthMM,
            keyHeight: Self.baseKeyHeightMM,
            columns: layoutColumns,
            rows: layoutRows,
            trackpadWidth: Self.trackpadWidthMM,
            trackpadHeight: Self.trackpadHeightMM,
            columnAnchorsMM: layoutColumnAnchors,
            columnSettings: columnSettings,
            keyGeometryOverrides: keyGeometryOverrides
        )
        viewModel.configureLayouts(
            leftLayout: leftLayout,
            rightLayout: rightLayout,
            leftLabels: leftGridLabels,
            rightLabels: rightGridLabels,
            trackpadSize: trackpadSize,
            trackpadWidthMm: Self.trackpadWidthMM
        )
    }

    private func applySavedSettings() {
        viewModel.setStatusVisualsEnabled(!editModeEnabled)
        AutocorrectEngine.shared.setEnabled(autocorrectEnabled)
        AutocorrectEngine.shared.setMinimumWordLength(GlassToKeySettings.autocorrectMinWordLength)
        let resolvedLayout = TrackpadLayoutPreset(rawValue: storedLayoutPreset) ?? .sixByThree
        layoutOption = resolvedLayout
        selectedGridKey = nil
        selectedButtonID = nil
        columnSettings = columnSettings(for: resolvedLayout)
        keyGeometryOverrides = keyGeometryOverrides(for: resolvedLayout)
        editColumnIndex = 0
        customButtons = loadCustomButtons(for: resolvedLayout)
        loadKeyMappings()
        keyMappingsByLayer = keyMappings(for: resolvedLayout)
        viewModel.updateCustomButtons(customButtons)
        updateGridLabelInfo()
        applyColumnSettings(columnSettings)
        if let leftDevice = deviceForID(storedLeftDeviceID) {
            viewModel.selectLeftDevice(leftDevice)
        }
        if let rightDevice = deviceForID(storedRightDeviceID) {
        viewModel.selectRightDevice(rightDevice)
        }
        viewModel.updateHoldThreshold(tapHoldDurationMs / 1000.0)
        viewModel.updateDragCancelDistance(CGFloat(dragCancelDistanceSetting))
        forceClickMinSetting = min(
            max(forceClickMinSetting, Self.forceClickRange.lowerBound),
            Self.forceClickRange.upperBound
        )
        forceClickCapSetting = min(
            max(forceClickCapSetting, forceClickMinSetting),
            Self.forceClickRange.upperBound
        )
        viewModel.updateForceClickMin(forceClickMinSetting)
        viewModel.updateForceClickCap(forceClickCapSetting)
        viewModel.updateHapticStrength(hapticStrengthSetting / 100.0)
        viewModel.updateTypingGraceMs(typingGraceMsSetting)
        viewModel.updateIntentMoveThresholdMm(intentMoveThresholdMmSetting)
        viewModel.updateIntentVelocityThresholdMmPerSec(intentVelocityThresholdMmPerSecSetting)
        viewModel.updateAllowMouseTakeover(true)
        viewModel.updateSnapRadiusPercent(snapRadiusPercentSetting)
        viewModel.updateChordalShiftEnabled(chordalShiftEnabled)
        viewModel.updateKeyboardModeEnabled(keyboardModeEnabled)
        runAtStartupEnabled = LaunchAtLoginManager.shared.isEnabled
        viewModel.updateTapClickCadenceMs(tapClickCadenceMsSetting)
        viewModel.updateGestureActions(
            twoFingerTap: resolvedGestureAction(twoFingerTapGestureAction, fallbackLabel: GlassToKeySettings.twoFingerTapGestureActionLabel),
            threeFingerTap: resolvedGestureAction(threeFingerTapGestureAction, fallbackLabel: GlassToKeySettings.threeFingerTapGestureActionLabel),
            twoFingerHold: resolvedGestureAction(twoFingerHoldGestureAction, fallbackLabel: GlassToKeySettings.twoFingerHoldGestureActionLabel),
            threeFingerHold: resolvedGestureAction(threeFingerHoldGestureAction, fallbackLabel: GlassToKeySettings.threeFingerHoldGestureActionLabel),
            fourFingerHold: resolvedGestureAction(fourFingerHoldGestureAction, fallbackLabel: GlassToKeySettings.fourFingerHoldGestureActionLabel),
            outerCornersHold: resolvedGestureAction(outerCornersHoldGestureAction, fallbackLabel: GlassToKeySettings.outerCornersHoldGestureActionLabel),
            innerCornersHold: resolvedGestureAction(innerCornersHoldGestureAction, fallbackLabel: GlassToKeySettings.innerCornersHoldGestureActionLabel),
            fiveFingerSwipeLeft: resolvedGestureAction(fiveFingerSwipeLeftGestureAction, fallbackLabel: GlassToKeySettings.fiveFingerSwipeLeftGestureActionLabel),
            fiveFingerSwipeRight: resolvedGestureAction(fiveFingerSwipeRightGestureAction, fallbackLabel: GlassToKeySettings.fiveFingerSwipeRightGestureActionLabel)
        )
        viewModel.setTouchSnapshotRecordingEnabled(true)
    }

    private func restoreTypingTuningDefaults() {
        tapHoldDurationMs = GlassToKeySettings.tapHoldDurationMs
        dragCancelDistanceSetting = GlassToKeySettings.dragCancelDistanceMm
        forceClickMinSetting = GlassToKeySettings.forceClickMin
        forceClickCapSetting = GlassToKeySettings.forceClickCap
        hapticStrengthSetting = GlassToKeySettings.hapticStrengthPercent
        typingGraceMsSetting = GlassToKeySettings.typingGraceMs
        intentMoveThresholdMmSetting = GlassToKeySettings.intentMoveThresholdMm
        intentVelocityThresholdMmPerSecSetting = GlassToKeySettings.intentVelocityThresholdMmPerSec
        autocorrectEnabled = GlassToKeySettings.autocorrectEnabled
        tapClickCadenceMsSetting = GlassToKeySettings.tapClickCadenceMs
        snapRadiusPercentSetting = GlassToKeySettings.snapRadiusPercent
        chordalShiftEnabled = GlassToKeySettings.chordalShiftEnabled
        keyboardModeEnabled = GlassToKeySettings.keyboardModeEnabled
        twoFingerTapGestureAction = GlassToKeySettings.twoFingerTapGestureActionLabel
        threeFingerTapGestureAction = GlassToKeySettings.threeFingerTapGestureActionLabel
        twoFingerHoldGestureAction = GlassToKeySettings.twoFingerHoldGestureActionLabel
        threeFingerHoldGestureAction = GlassToKeySettings.threeFingerHoldGestureActionLabel
        fourFingerHoldGestureAction = GlassToKeySettings.fourFingerHoldGestureActionLabel
        outerCornersHoldGestureAction = GlassToKeySettings.outerCornersHoldGestureActionLabel
        innerCornersHoldGestureAction = GlassToKeySettings.innerCornersHoldGestureActionLabel
        fiveFingerSwipeLeftGestureAction = GlassToKeySettings.fiveFingerSwipeLeftGestureActionLabel
        fiveFingerSwipeRightGestureAction = GlassToKeySettings.fiveFingerSwipeRightGestureActionLabel
        AutocorrectEngine.shared.setMinimumWordLength(GlassToKeySettings.autocorrectMinWordLength)
    }

    private func exportKeymap() {
        persistConfig()
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "GlassToKeyKeymap.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let profile = keymapProfileSnapshot()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(profile)
            try data.write(to: url, options: .atomic)
            showKeymapAlert(
                title: "Export complete",
                message: "Keymap saved to:\n\(url.path)"
            )
        } catch {
            showKeymapAlert(
                title: "Export failed",
                message: error.localizedDescription,
                style: .warning
            )
        }
    }

    private func importKeymap() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let profile = try JSONDecoder().decode(KeymapProfile.self, from: data)
            applyKeymapProfile(profile)
            showKeymapAlert(
                title: "Import complete",
                message: "Loaded keymap from:\n\(url.path)"
            )
        } catch {
            showKeymapAlert(
                title: "Import failed",
                message: error.localizedDescription,
                style: .warning
            )
        }
    }

    private func keymapProfileSnapshot() -> KeymapProfile {
        let columnSettingsByLayout = LayoutColumnSettingsStorage.decode(from: storedColumnSettingsData) ?? [:]
        let customButtonsByLayout = LayoutCustomButtonStorage.decode(from: storedCustomButtonsData) ?? [:]
        let mappings = KeyActionMappingStore.decodeLayoutNormalized(storedKeyMappingsData)
            ?? normalizedLayoutMappingsWithCurrentRuntime()
        let keyGeometryByLayout = KeyGeometryStore.decodeLayoutNormalized(storedKeyGeometryData)
            ?? normalizedLayoutKeyGeometryWithCurrentRuntime()
        return KeymapProfile(
            leftDeviceID: storedLeftDeviceID,
            rightDeviceID: storedRightDeviceID,
            layoutPreset: storedLayoutPreset,
            autoResyncMissingTrackpads: storedAutoResyncMissingTrackpads,
            tapHoldDurationMs: tapHoldDurationMs,
            dragCancelDistance: dragCancelDistanceSetting,
            forceClickMin: forceClickMinSetting,
            forceClickCap: forceClickCapSetting,
            hapticStrength: hapticStrengthSetting,
            typingGraceMs: typingGraceMsSetting,
            intentMoveThresholdMm: intentMoveThresholdMmSetting,
            intentVelocityThresholdMmPerSec: intentVelocityThresholdMmPerSecSetting,
            autocorrectEnabled: autocorrectEnabled,
            tapClickCadenceMs: tapClickCadenceMsSetting,
            snapRadiusPercent: snapRadiusPercentSetting,
            chordalShiftEnabled: chordalShiftEnabled,
            keyboardModeEnabled: keyboardModeEnabled,
            twoFingerTapGestureAction: twoFingerTapGestureAction,
            threeFingerTapGestureAction: threeFingerTapGestureAction,
            twoFingerHoldGestureAction: twoFingerHoldGestureAction,
            threeFingerHoldGestureAction: threeFingerHoldGestureAction,
            fourFingerHoldGestureAction: fourFingerHoldGestureAction,
            outerCornersHoldGestureAction: outerCornersHoldGestureAction,
            innerCornersHoldGestureAction: innerCornersHoldGestureAction,
            fiveFingerSwipeLeftGestureAction: fiveFingerSwipeLeftGestureAction,
            fiveFingerSwipeRightGestureAction: fiveFingerSwipeRightGestureAction,
            columnSettingsByLayout: columnSettingsByLayout,
            customButtonsByLayout: customButtonsByLayout,
            keyMappingsByLayout: mappings,
            keyGeometryByLayout: keyGeometryByLayout
        )
    }

    private func applyKeymapProfile(_ profile: KeymapProfile) {
        storedLeftDeviceID = profile.leftDeviceID
        storedRightDeviceID = profile.rightDeviceID
        storedLayoutPreset = profile.layoutPreset
        storedAutoResyncMissingTrackpads = profile.autoResyncMissingTrackpads
        tapHoldDurationMs = profile.tapHoldDurationMs
        dragCancelDistanceSetting = profile.dragCancelDistance
        forceClickMinSetting = profile.forceClickMin ?? GlassToKeySettings.forceClickMin
        forceClickCapSetting = profile.forceClickCap
        hapticStrengthSetting = profile.hapticStrength
        typingGraceMsSetting = profile.typingGraceMs
        intentMoveThresholdMmSetting = profile.intentMoveThresholdMm
        intentVelocityThresholdMmPerSecSetting = profile.intentVelocityThresholdMmPerSec
        autocorrectEnabled = profile.autocorrectEnabled
        tapClickCadenceMsSetting = profile.tapClickCadenceMs
        snapRadiusPercentSetting = profile.snapRadiusPercent
        chordalShiftEnabled = profile.chordalShiftEnabled
        keyboardModeEnabled = profile.keyboardModeEnabled
        twoFingerTapGestureAction = profile.twoFingerTapGestureAction ?? GlassToKeySettings.twoFingerTapGestureActionLabel
        threeFingerTapGestureAction = profile.threeFingerTapGestureAction ?? GlassToKeySettings.threeFingerTapGestureActionLabel
        twoFingerHoldGestureAction = profile.twoFingerHoldGestureAction ?? GlassToKeySettings.twoFingerHoldGestureActionLabel
        threeFingerHoldGestureAction = profile.threeFingerHoldGestureAction ?? GlassToKeySettings.threeFingerHoldGestureActionLabel
        fourFingerHoldGestureAction = profile.fourFingerHoldGestureAction ?? GlassToKeySettings.fourFingerHoldGestureActionLabel
        outerCornersHoldGestureAction = profile.outerCornersHoldGestureAction ?? GlassToKeySettings.outerCornersHoldGestureActionLabel
        innerCornersHoldGestureAction = profile.innerCornersHoldGestureAction ?? GlassToKeySettings.innerCornersHoldGestureActionLabel
        fiveFingerSwipeLeftGestureAction = profile.fiveFingerSwipeLeftGestureAction ?? GlassToKeySettings.fiveFingerSwipeLeftGestureActionLabel
        fiveFingerSwipeRightGestureAction = profile.fiveFingerSwipeRightGestureAction ?? GlassToKeySettings.fiveFingerSwipeRightGestureActionLabel
        storedColumnSettingsData = LayoutColumnSettingsStorage.encode(profile.columnSettingsByLayout) ?? Data()
        storedCustomButtonsData = LayoutCustomButtonStorage.encode(profile.customButtonsByLayout) ?? Data()
        storedKeyMappingsData = encodedLayoutKeyMappingsData(from: profile)
        storedKeyGeometryData = encodedLayoutKeyGeometryData(from: profile)
        applySavedSettings()
        viewModel.setAutoResyncEnabled(storedAutoResyncMissingTrackpads)
    }

    private func showKeymapAlert(
        title: String,
        message: String,
        style: NSAlert.Style = .informational
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func saveSettings() {
        storedLeftDeviceID = viewModel.leftDevice?.deviceID ?? ""
        storedRightDeviceID = viewModel.rightDevice?.deviceID ?? ""
        storedLayoutPreset = layoutOption.rawValue
        saveCurrentColumnSettings()
    }

    private func persistConfig() {
        saveSettings()
        saveCustomButtons(customButtons)
        saveKeyMappings(normalizedLayoutMappingsWithCurrentRuntime())
        saveLayoutKeyGeometryOverrides(normalizedLayoutKeyGeometryWithCurrentRuntime())
    }

    private func columnSettings(
        for layout: TrackpadLayoutPreset
    ) -> [ColumnLayoutSettings] {
        if !layout.allowsColumnSettings {
            return ColumnLayoutDefaults.defaultSettings(columns: layout.columns)
        }
        if let stored = LayoutColumnSettingsStorage.settings(
            for: layout,
            from: storedColumnSettingsData
        ) {
            return Self.normalizedColumnSettings(stored, columns: layout.columns)
        }
        return ColumnLayoutDefaults.defaultSettings(columns: layout.columns)
    }

    private func saveCurrentColumnSettings() {
        var map = LayoutColumnSettingsStorage.decode(from: storedColumnSettingsData) ?? [:]
        map[layoutOption.rawValue] = Self.normalizedColumnSettings(
            columnSettings,
            columns: layoutColumns
        )
        if let encoded = LayoutColumnSettingsStorage.encode(map) {
            storedColumnSettingsData = encoded
        } else {
            storedColumnSettingsData = Data()
        }
    }

    private func loadKeyMappings() {
        if let decoded = KeyActionMappingStore.decodeLayoutNormalized(storedKeyMappingsData) {
            keyMappingsByLayout = decoded
            return
        }
        if let fallback = bundledDefaultKeyMappings() {
            keyMappingsByLayout = fallback
            return
        }
        keyMappingsByLayout = KeyActionMappingStore.emptyLayoutMappings()
    }

    private func bundledDefaultKeyMappings() -> LayoutLayeredKeyMappings? {
        guard let url = Bundle.main.url(
            forResource: "GLASSTOKEY_DEFAULT_KEYMAP",
            withExtension: "json"
        ) else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let profile = try? JSONDecoder().decode(KeymapProfile.self, from: data) else {
            return nil
        }
        if let byLayout = profile.keyMappingsByLayout {
            return KeyActionMappingStore.normalized(byLayout)
        }
        return nil
    }

    private func bundledDefaultKeyGeometry() -> LayoutKeyGeometryOverrides? {
        guard let url = Bundle.main.url(
            forResource: "GLASSTOKEY_DEFAULT_KEYMAP",
            withExtension: "json"
        ) else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let profile = try? JSONDecoder().decode(KeymapProfile.self, from: data) else {
            return nil
        }
        if let byLayout = profile.keyGeometryByLayout {
            return KeyGeometryStore.normalized(byLayout)
        }
        return nil
    }

    private func keyGeometryOverrides(for layout: TrackpadLayoutPreset) -> KeyGeometryOverrides {
        if let decoded = KeyGeometryStore.decodeLayoutNormalized(storedKeyGeometryData) {
            return decoded[layout.rawValue] ?? [:]
        }
        if let bundled = bundledDefaultKeyGeometry() {
            return bundled[layout.rawValue] ?? [:]
        }
        return [:]
    }

    private func loadCustomButtons(for layout: TrackpadLayoutPreset) -> [CustomButton] {
        if let stored = LayoutCustomButtonStorage.buttons(for: layout, from: storedCustomButtonsData) {
            return stored
        }
        return CustomButtonDefaults.defaultButtons(
            trackpadWidth: Self.trackpadWidthMM,
            trackpadHeight: Self.trackpadHeightMM,
            thumbAnchorsMM: Self.ThumbAnchorsMM
        )
    }

    private func saveKeyMappings(_ mappings: LayoutLayeredKeyMappings) {
        storedKeyMappingsData = KeyActionMappingStore.encode(mappings) ?? Data()
    }

    private func saveKeyGeometryOverrides(_ overrides: KeyGeometryOverrides) {
        var byLayout = KeyGeometryStore.decodeLayoutNormalized(storedKeyGeometryData)
            ?? KeyGeometryStore.emptyLayoutOverrides()
        byLayout[layoutOption.rawValue] = overrides
        saveLayoutKeyGeometryOverrides(byLayout)
    }

    private func saveLayoutKeyGeometryOverrides(_ overrides: LayoutKeyGeometryOverrides) {
        storedKeyGeometryData = KeyGeometryStore.encode(KeyGeometryStore.normalized(overrides)) ?? Data()
    }

    private func keyMappings(for layout: TrackpadLayoutPreset) -> LayeredKeyMappings {
        let layoutKey = layout.rawValue
        if let mappings = keyMappingsByLayout[layoutKey] {
            return KeyActionMappingStore.normalized(mappings)
        }
        let empty = KeyActionMappingStore.emptyMappings()
        keyMappingsByLayout[layoutKey] = empty
        return empty
    }

    private func normalizedLayoutMappingsWithCurrentRuntime() -> LayoutLayeredKeyMappings {
        var merged = keyMappingsByLayout
        merged[layoutOption.rawValue] = keyMappingsByLayer
        return KeyActionMappingStore.normalized(merged)
    }

    private func normalizedLayoutKeyGeometryWithCurrentRuntime() -> LayoutKeyGeometryOverrides {
        var merged = KeyGeometryStore.decodeLayoutNormalized(storedKeyGeometryData)
            ?? KeyGeometryStore.emptyLayoutOverrides()
        merged[layoutOption.rawValue] = keyGeometryOverrides
        return KeyGeometryStore.normalized(merged)
    }

    private func encodedLayoutKeyMappingsData(from profile: KeymapProfile) -> Data {
        if let byLayout = profile.keyMappingsByLayout,
           let encoded = KeyActionMappingStore.encode(KeyActionMappingStore.normalized(byLayout)) {
            return encoded
        }
        return Data()
    }

    private func encodedLayoutKeyGeometryData(from profile: KeymapProfile) -> Data {
        if let byLayout = profile.keyGeometryByLayout,
           let encoded = KeyGeometryStore.encode(KeyGeometryStore.normalized(byLayout)) {
            return encoded
        }
        return Data()
    }

    private func saveCustomButtons(_ buttons: [CustomButton]) {
        var map = LayoutCustomButtonStorage.decode(from: storedCustomButtonsData) ?? [:]
        var layered = map[layoutOption.rawValue] ?? [:]
        let updated = LayoutCustomButtonStorage.layeredButtons(from: buttons)
        for (layer, layerButtons) in updated {
            layered[layer] = layerButtons
        }
        if updated[viewModel.activeLayer] == nil {
            layered[viewModel.activeLayer] = []
        }
        map[layoutOption.rawValue] = layered
        if let encoded = LayoutCustomButtonStorage.encode(map) {
            storedCustomButtonsData = encoded
        } else {
            storedCustomButtonsData = Data()
        }
    }

    private func addCustomButton(side: TrackpadSide) {
        if !editModeEnabled {
            editModeEnabled = true
        }
        let action = KeyActionCatalog.action(for: "Space") ?? KeyActionCatalog.presets.first
        guard let action else { return }
        let newButton = CustomButton(
            id: UUID(),
            side: side,
            rect: defaultNewButtonRect(),
            action: action
            ,
            hold: nil,
            layer: viewModel.activeLayer
        )
        customButtons.append(newButton)
        selectedButtonID = newButton.id
    }

    private func removeCustomButton(id: UUID) {
        customButtons.removeAll { $0.id == id }
        if selectedButtonID == id {
            selectedButtonID = nil
        }
    }

    private func updateCustomButton(id: UUID, update: (inout CustomButton) -> Void) {
        guard let index = customButtons.firstIndex(where: { $0.id == id }) else { return }
        update(&customButtons[index])
    }

    private func updateCustomButtonAndSelection(
        id: UUID,
        update: (inout CustomButton) -> Void
    ) {
        updateCustomButton(id: id, update: update)
        refreshButtonInspectorSelection()
    }

    private func defaultNewButtonRect() -> NormalizedRect {
        let width: CGFloat = 0.18
        let height: CGFloat = 0.14
        let rect = NormalizedRect(
            x: 0.5 - width / 2.0,
            y: 0.5 - height / 2.0,
            width: width,
            height: height
        )
        return rect.clamped(
            minWidth: Self.minCustomButtonSize.width,
            minHeight: Self.minCustomButtonSize.height
        )
    }

    private struct ColumnTuningRow: View {
        let title: String
        let formatter: NumberFormatter
        let range: ClosedRange<Double>
        let sliderStep: Double
        let buttonStep: Double
        let showSlider: Bool
        @Binding var value: Double

            init(
                title: String,
                value: Binding<Double>,
                formatter: NumberFormatter,
                range: ClosedRange<Double>,
                sliderStep: Double,
                buttonStep: Double? = nil,
                showSlider: Bool? = nil
            ) {
                self.title = title
                self._value = value
                self.formatter = formatter
                self.range = range
                self.sliderStep = sliderStep
                self.buttonStep = buttonStep ?? sliderStep
                self.showSlider = showSlider ?? true
            }

        var body: some View {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.semibold)
                Spacer()
                HStack(spacing: 12) {
                    if showSlider {
                        Slider(value: $value, in: range, step: sliderStep)
                            .frame(minWidth: 140, maxWidth: 220)
                    }
                    controlButtons
                }
            }
        }

        @ViewBuilder
        private var controlButtons: some View {
            HStack(spacing: 4) {
                Button {
                    adjust(-buttonStep)
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                TextField(
                    "",
                    value: $value,
                    formatter: formatter
                )
                .frame(width: 60)
                .textFieldStyle(.roundedBorder)

                Button {
                    adjust(buttonStep)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }

        private func adjust(_ delta: Double) {
            value = min(
                max(range.lowerBound, value + delta),
                range.upperBound
            )
        }
    }


    private func deviceForID(_ deviceID: String) -> OMSDeviceInfo? {
        guard !deviceID.isEmpty else { return nil }
        return viewModel.availableDevices.first { $0.deviceID == deviceID }
    }

    private func labelInfo(for key: SelectedGridKey) -> (primary: String, hold: String?) {
        let mapping = effectiveKeyMapping(for: key)
        return (primary: mapping.primary.displayText, hold: mapping.hold?.holdLabelText)
    }

    private func refreshColumnInspectorSelection() {
        guard columnSettings.indices.contains(editColumnIndex) else {
            columnInspectorSelection = nil
            return
        }
        columnInspectorSelection = ColumnInspectorSelection(
            index: editColumnIndex,
            settings: columnSettings[editColumnIndex]
        )
    }

    private func refreshButtonInspectorSelection() {
        guard let selectedButtonID,
              let button = customButtons.first(where: { $0.id == selectedButtonID }) else {
            buttonInspectorSelection = nil
            return
        }
        buttonInspectorSelection = ButtonInspectorSelection(button: button)
    }

    private func refreshKeyInspectorSelection() {
        guard let selectedGridKey else {
            keyInspectorSelection = nil
            return
        }
        let mapping = effectiveKeyMapping(for: selectedGridKey)
        keyInspectorSelection = KeyInspectorSelection(
            key: selectedGridKey,
            mapping: mapping
        )
    }

    private func updateGridLabelInfo() {
        let allowHold = layoutOption.allowHoldBindings
        leftGridLabelInfo = gridLabelInfo(for: leftGridLabels, side: .left, allowHold: allowHold)
        rightGridLabelInfo = gridLabelInfo(for: rightGridLabels, side: .right, allowHold: allowHold)
    }

    private func gridLabelInfo(
        for labels: [[String]],
        side: TrackpadSide,
        allowHold: Bool
    ) -> [[GridLabel]] {
        var output = labels.map { Array(repeating: GridLabel(primary: "", hold: nil), count: $0.count) }
        for row in 0..<labels.count {
            for col in 0..<labels[row].count {
                let key = SelectedGridKey(
                    row: row,
                    column: col,
                    label: labels[row][col],
                    side: side
                )
                let info = labelInfo(for: key)
                output[row][col] = GridLabel(
                    primary: info.primary,
                    hold: allowHold ? info.hold : nil
                )
            }
        }
        return output
    }

    fileprivate static func pickerLabel(for action: KeyAction) -> some View {
        let label = action.kind == .typingToggle
            ? KeyActionCatalog.typingToggleLabel
            : action.label
        return Text(label)
            .multilineTextAlignment(.center)
    }

    fileprivate static func pickerGroupHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .allowsHitTesting(false)
    }


    private func effectiveKeyMapping(for key: SelectedGridKey) -> KeyMapping {
        let layerMappings = keyMappingsForActiveLayer()
        let resolvedLabel = resolvedLabel(for: key)
        if let mapping = layerMappings[key.storageKey] {
            return mapping
        }
        return defaultKeyMapping(for: resolvedLabel)
            ?? KeyMapping(primary: KeyAction(label: resolvedLabel, keyCode: 0, flags: 0), hold: nil)
    }

    private func updateKeyMapping(
        for key: SelectedGridKey,
        _ update: (inout KeyMapping) -> Void
    ) {
        let layer = viewModel.activeLayer
        var layerMappings = keyMappingsByLayer[layer] ?? [:]
        let resolvedLabel = resolvedLabel(for: key)
        var mapping = layerMappings[key.storageKey]
            ?? defaultKeyMapping(for: resolvedLabel)
            ?? KeyMapping(primary: KeyAction(label: resolvedLabel, keyCode: 0, flags: 0), hold: nil)
        update(&mapping)
        if let defaultMapping = defaultKeyMapping(for: resolvedLabel),
           defaultMapping == mapping {
            layerMappings.removeValue(forKey: key.storageKey)
            keyMappingsByLayer[layer] = layerMappings
            return
        }
        layerMappings[key.storageKey] = mapping
        keyMappingsByLayer[layer] = layerMappings
    }

    private func resolvedLabel(for key: SelectedGridKey) -> String {
        let labels = key.side == .left ? leftGridLabels : rightGridLabels
        guard labels.indices.contains(key.row),
              labels[key.row].indices.contains(key.column) else {
            return key.label
        }
        return labels[key.row][key.column]
    }

    private func updateKeyMappingAndSelection(
        key: SelectedGridKey,
        update: (inout KeyMapping) -> Void
    ) {
        updateKeyMapping(for: key, update)
        refreshKeyInspectorSelection()
    }

    private func keyRotationDegrees(for key: SelectedGridKey) -> Double {
        keyGeometryOverrides[key.storageKey]?.rotationDegrees ?? 0
    }

    private func updateKeyRotation(
        for key: SelectedGridKey,
        rotationDegrees: Double
    ) {
        let normalized = Self.normalizedRotationDegrees(rotationDegrees)
        if normalized <= 0.000_01 {
            keyGeometryOverrides.removeValue(forKey: key.storageKey)
            return
        }
        keyGeometryOverrides[key.storageKey] = KeyGeometryOverride(rotationDegrees: normalized)
    }

    private func updateKeyRotationAndSelection(
        for key: SelectedGridKey,
        rotationDegrees: Double
    ) {
        updateKeyRotation(for: key, rotationDegrees: rotationDegrees)
        refreshKeyInspectorSelection()
    }

    private func defaultKeyMapping(for label: String) -> KeyMapping? {
        guard let primary = KeyActionCatalog.action(for: label) else { return nil }
        return KeyMapping(primary: primary, hold: KeyActionCatalog.holdAction(for: label))
    }

    private var layerSelectionBinding: Binding<Int> {
        Binding(
            get: { viewModel.activeLayer },
            set: { layer in
                viewModel.setPersistentLayer(layer)
            }
        )
    }

    private func keyMappingsForActiveLayer() -> [String: KeyMapping] {
        keyMappingsByLayer[viewModel.activeLayer] ?? [:]
    }
}

#Preview {
    ContentView()
}
