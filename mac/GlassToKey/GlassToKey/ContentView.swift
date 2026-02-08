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

    private struct ButtonInspectorSelection: Equatable {
        var button: CustomButton
    }

    private struct KeyInspectorSelection: Equatable {
        let key: SelectedGridKey
        var mapping: KeyMapping
    }

    @StateObject private var viewModel: ContentViewModel
    @State private var testText = ""
    @State private var visualsEnabled = true
    @State private var editModeEnabled = false
#if DEBUG
    @State private var tapTraceDumpInProgress = false
    @State private var tapTraceDumpStatus: String?
    @State private var tapTraceDumpStatusToken = UUID()
#endif
    @State private var columnSettings: [ColumnLayoutSettings]
    @State private var leftLayout: ContentViewModel.Layout
    @State private var rightLayout: ContentViewModel.Layout
    @State private var customButtons: [CustomButton] = []
    @State private var selectedButtonID: UUID?
    @State private var selectedColumn: Int?
    @State private var selectedGridKey: SelectedGridKey?
    @State private var columnInspectorSelection: ColumnInspectorSelection?
    @State private var buttonInspectorSelection: ButtonInspectorSelection?
    @State private var keyInspectorSelection: KeyInspectorSelection?
    @State private var keyMappingsByLayer: LayeredKeyMappings = [:]
    @State private var layoutOption: TrackpadLayoutPreset = .sixByThree
    @State private var leftGridLabelInfo: [[GridLabel]] = []
    @State private var rightGridLabelInfo: [[GridLabel]] = []
    @AppStorage(GlassToKeyDefaultsKeys.leftDeviceID) private var storedLeftDeviceID = ""
    @AppStorage(GlassToKeyDefaultsKeys.rightDeviceID) private var storedRightDeviceID = ""
    @AppStorage(GlassToKeyDefaultsKeys.visualsEnabled) private var storedVisualsEnabled = true
    @AppStorage(GlassToKeyDefaultsKeys.columnSettings) private var storedColumnSettingsData = Data()
    @AppStorage(GlassToKeyDefaultsKeys.layoutPreset) private var storedLayoutPreset = TrackpadLayoutPreset.sixByThree.rawValue
    @AppStorage(GlassToKeyDefaultsKeys.customButtons) private var storedCustomButtonsData = Data()
    @AppStorage(GlassToKeyDefaultsKeys.keyMappings) private var storedKeyMappingsData = Data()
    @AppStorage(GlassToKeyDefaultsKeys.autoResyncMissingTrackpads) private var storedAutoResyncMissingTrackpads = false
    @AppStorage(GlassToKeyDefaultsKeys.tapHoldDuration) private var tapHoldDurationMs: Double = GlassToKeySettings.tapHoldDurationMs
    @AppStorage(GlassToKeyDefaultsKeys.dragCancelDistance) private var dragCancelDistanceSetting: Double = GlassToKeySettings.dragCancelDistanceMm
    @AppStorage(GlassToKeyDefaultsKeys.forceClickCap) private var forceClickCapSetting: Double = GlassToKeySettings.forceClickCap
    @AppStorage(GlassToKeyDefaultsKeys.hapticStrength) private var hapticStrengthSetting: Double = GlassToKeySettings.hapticStrengthPercent
    @AppStorage(GlassToKeyDefaultsKeys.typingGraceMs) private var typingGraceMsSetting: Double = GlassToKeySettings.typingGraceMs
    @AppStorage(GlassToKeyDefaultsKeys.intentMoveThresholdMm)
    private var intentMoveThresholdMmSetting: Double = GlassToKeySettings.intentMoveThresholdMm
    @AppStorage(GlassToKeyDefaultsKeys.intentVelocityThresholdMmPerSec)
    private var intentVelocityThresholdMmPerSecSetting: Double = GlassToKeySettings.intentVelocityThresholdMmPerSec
    @AppStorage(GlassToKeyDefaultsKeys.autocorrectEnabled)
    private var autocorrectEnabled = GlassToKeySettings.autocorrectEnabled
    @AppStorage(GlassToKeyDefaultsKeys.tapClickEnabled)
    private var tapClickEnabled = GlassToKeySettings.tapClickEnabled
    @AppStorage(GlassToKeyDefaultsKeys.tapClickCadenceMs)
    private var tapClickCadenceMsSetting = GlassToKeySettings.tapClickCadenceMs
    @AppStorage(GlassToKeyDefaultsKeys.snapRadiusPercent)
    private var snapRadiusPercentSetting = GlassToKeySettings.snapRadiusPercent
    @AppStorage(GlassToKeyDefaultsKeys.chordalShiftEnabled)
    private var chordalShiftEnabled = GlassToKeySettings.chordalShiftEnabled
    @AppStorage(GlassToKeyDefaultsKeys.keyboardModeEnabled)
    private var keyboardModeEnabled = GlassToKeySettings.keyboardModeEnabled
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
    fileprivate static let columnScaleRange: ClosedRange<Double> = ColumnLayoutDefaults.scaleRange
    fileprivate static let columnOffsetPercentRange: ClosedRange<Double> = ColumnLayoutDefaults.offsetPercentRange
    fileprivate static let rowSpacingPercentRange: ClosedRange<Double> = ColumnLayoutDefaults.rowSpacingPercentRange
    fileprivate static let dragCancelDistanceRange: ClosedRange<Double> = 1.0...30.0
    fileprivate static let tapHoldDurationRange: ClosedRange<Double> = 50.0...500.0
    fileprivate static let forceClickCapRange: ClosedRange<Double> = 0.0...150.0
    fileprivate static let hapticStrengthRange: ClosedRange<Double> = 0.0...100.0
    fileprivate static let typingGraceRange: ClosedRange<Double> = 0.0...4000.0
    fileprivate static let twoFingerClickCadenceRange: ClosedRange<Double> = 100.0...600.0
    fileprivate static let intentMoveThresholdRange: ClosedRange<Double> = 0.5...10.0
    fileprivate static let intentVelocityThresholdRange: ClosedRange<Double> = 10.0...200.0
    fileprivate static let snapRadiusPercentRange: ClosedRange<Double> = 0.0...100.0
    private static let keyCornerRadius: CGFloat = 6.0
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
    fileprivate static let forceClickCapFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.minimum = NSNumber(value: ContentView.forceClickCapRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.forceClickCapRange.upperBound)
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
            .frame(minWidth: trackpadSize.width * 2 + 520, minHeight: trackpadSize.height + 240)
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
            }
            .onDisappear {
                persistConfig()
            }
            .onChange(of: visualsEnabled) { enabled in
                viewModel.setTouchSnapshotRecordingEnabled(enabled)
                if !enabled {
                    viewModel.clearVisualCaches()
                    editModeEnabled = false
                    selectedButtonID = nil
                    selectedColumn = nil
                    selectedGridKey = nil
                }
            }
            .onChange(of: editModeEnabled) { enabled in
                if enabled {
                    visualsEnabled = true
                } else {
                    selectedButtonID = nil
                    selectedColumn = nil
                    selectedGridKey = nil
                }
            }
            .onChange(of: columnSettings) { newValue in
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
                selectedColumn = nil
                selectedGridKey = nil
                updateGridLabelInfo()
            }
            .onChange(of: keyMappingsByLayer) { newValue in
                viewModel.updateKeyMappings(newValue)
                updateGridLabelInfo()
                refreshKeyInspectorSelection()
            }
            .onChange(of: selectedButtonID) { _ in
                refreshButtonInspectorSelection()
            }
            .onChange(of: selectedColumn) { _ in
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
            .onChange(of: forceClickCapSetting) { newValue in
                viewModel.updateForceClickCap(newValue)
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
            .onChange(of: tapClickEnabled) { newValue in
                viewModel.updateTapClickEnabled(newValue)
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
            .onChange(of: storedAutoResyncMissingTrackpads) { newValue in
                viewModel.setAutoResyncEnabled(newValue)
            }
    }

    @ViewBuilder
    private var mainLayout: some View {
        VStack(spacing: 16) {
            headerView
            contentRow
        }
    }

    @ViewBuilder
    private var headerView: some View {
#if DEBUG
        HeaderControlsView(
            editModeEnabled: $editModeEnabled,
            visualsEnabled: $visualsEnabled,
            layerToggleBinding: layerToggleBinding,
            leftContactCount: viewModel.contactFingerCountsBySide.left,
            rightContactCount: viewModel.contactFingerCountsBySide.right,
            intentDisplay: viewModel.intentDisplayBySide.left,
            voiceGestureActive: viewModel.voiceGestureActive,
            voiceDebugStatus: viewModel.voiceDebugStatus,
            tapTraceDumpInProgress: tapTraceDumpInProgress,
            tapTraceDumpStatus: tapTraceDumpStatus,
            onDumpTapTrace: dumpTapTrace
        )
#else
        HeaderControlsView(
            editModeEnabled: $editModeEnabled,
            visualsEnabled: $visualsEnabled,
            layerToggleBinding: layerToggleBinding,
            leftContactCount: viewModel.contactFingerCountsBySide.left,
            rightContactCount: viewModel.contactFingerCountsBySide.right,
            intentDisplay: viewModel.intentDisplayBySide.left,
            voiceGestureActive: viewModel.voiceGestureActive,
            voiceDebugStatus: viewModel.voiceDebugStatus,
        )
#endif
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
            leftGridLabelInfo: leftGridLabelInfo,
            rightGridLabelInfo: rightGridLabelInfo,
            leftGridLabels: leftGridLabels,
            rightGridLabels: rightGridLabels,
            customButtons: customButtons,
            editModeEnabled: $editModeEnabled,
            visualsEnabled: $visualsEnabled,
            lastHitLeft: viewModel.debugLastHitLeft,
            lastHitRight: viewModel.debugLastHitRight,
            selectedButtonID: $selectedButtonID,
            selectedColumn: $selectedColumn,
            selectedGridKey: $selectedGridKey,
            testText: $testText
        )
    }

    private var rightSidebarView: some View {
        RightSidebarView(
            viewModel: viewModel,
            autoResyncEnabled: $storedAutoResyncMissingTrackpads,
            layoutSelection: layoutSelectionBinding,
            layoutOption: layoutOption,
            columnSelection: columnInspectorSelection,
            buttonSelection: buttonInspectorSelection,
            keySelection: keyInspectorSelection,
            editModeEnabled: editModeEnabled,
            tapHoldDurationMs: $tapHoldDurationMs,
            dragCancelDistanceSetting: $dragCancelDistanceSetting,
            forceClickCapSetting: $forceClickCapSetting,
            hapticStrengthSetting: $hapticStrengthSetting,
            typingGraceMsSetting: $typingGraceMsSetting,
            intentMoveThresholdMmSetting: $intentMoveThresholdMmSetting,
            intentVelocityThresholdMmPerSecSetting: $intentVelocityThresholdMmPerSecSetting,
            autocorrectEnabled: $autocorrectEnabled,
            tapClickEnabled: $tapClickEnabled,
            tapClickCadenceMsSetting: $tapClickCadenceMsSetting,
            snapRadiusPercentSetting: $snapRadiusPercentSetting,
            chordalShiftEnabled: $chordalShiftEnabled,
            keyboardModeEnabled: $keyboardModeEnabled,
            onRefreshDevices: {
                viewModel.refreshDevicesAndListeners()
            },
            onAutoResyncChange: { newValue in
                storedAutoResyncMissingTrackpads = newValue
                viewModel.setAutoResyncEnabled(newValue)
            },
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
            onRestoreDefaults: restoreTypingTuningDefaults
        )
    }

    private struct HeaderControlsView: View {
        @Binding var editModeEnabled: Bool
        @Binding var visualsEnabled: Bool
        let layerToggleBinding: Binding<Bool>
        let leftContactCount: Int
        let rightContactCount: Int
        let intentDisplay: ContentViewModel.IntentDisplay
        let voiceGestureActive: Bool
        let voiceDebugStatus: String?
#if DEBUG
        let tapTraceDumpInProgress: Bool
        let tapTraceDumpStatus: String?
        let onDumpTapTrace: () -> Void
#endif

        var body: some View {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("GlassToKey Studio")
                        .font(.title2)
                        .bold()
                    if visualsEnabled {
                        HStack(spacing: 10) {
                            contactCountPills
                            intentBadge(intent: intentDisplay)
                            if voiceGestureActive {
                                voiceBadge(isActive: true)
                            }
                            if let voiceDebugStatus {
                                voiceStatusBadge(voiceDebugStatus)
                            }
                        }
                    }
                }
                Spacer()
#if DEBUG
                if let tapTraceDumpStatus {
                    Text(tapTraceDumpStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(tapTraceDumpInProgress ? "Dumping..." : "Dump Tap Trace") {
                    onDumpTapTrace()
                }
                .buttonStyle(.bordered)
                .disabled(tapTraceDumpInProgress)
#endif
                Toggle("Edit Keymap", isOn: $editModeEnabled)
                    .toggleStyle(SwitchToggleStyle())
                Toggle("Visuals", isOn: $visualsEnabled)
                    .toggleStyle(SwitchToggleStyle())
                HStack(spacing: 6) {
                    Text("Layer0")
                    Toggle("", isOn: layerToggleBinding)
                        .toggleStyle(SwitchToggleStyle())
                        .labelsHidden()
                    Text("Layer1")
                }
            }
        }

        private var contactCountPills: some View {
            HStack(spacing: 8) {
                labelPill(prefix: "L", value: leftContactCount)
                labelPill(prefix: "R", value: rightContactCount)
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

        private func voiceBadge(isActive: Bool) -> some View {
            HStack(spacing: 4) {
                Circle()
                    .fill(isActive ? Color.red : Color.gray)
                    .frame(width: 6, height: 6)
                Text("voice")
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

        private func voiceStatusBadge(_ text: String) -> some View {
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.04))
                )
        }
    }

    private struct TrackpadSectionView: View {
        @ObservedObject var viewModel: ContentViewModel
        let trackpadSize: CGSize
        let leftLayout: ContentViewModel.Layout
        let rightLayout: ContentViewModel.Layout
        let leftGridLabelInfo: [[GridLabel]]
        let rightGridLabelInfo: [[GridLabel]]
        let leftGridLabels: [[String]]
        let rightGridLabels: [[String]]
        let customButtons: [CustomButton]
        @Binding var editModeEnabled: Bool
        @Binding var visualsEnabled: Bool
        let lastHitLeft: ContentViewModel.DebugHit?
        let lastHitRight: ContentViewModel.DebugHit?
        @Binding var selectedButtonID: UUID?
        @Binding var selectedColumn: Int?
        @Binding var selectedGridKey: SelectedGridKey?
        @Binding var testText: String

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                TrackpadDeckView(
                    viewModel: viewModel,
                    trackpadSize: trackpadSize,
                    leftLayout: leftLayout,
                    rightLayout: rightLayout,
                    leftGridLabelInfo: leftGridLabelInfo,
                    rightGridLabelInfo: rightGridLabelInfo,
                    leftGridLabels: leftGridLabels,
                    rightGridLabels: rightGridLabels,
                    customButtons: customButtons,
                    editModeEnabled: $editModeEnabled,
                    visualsEnabled: $visualsEnabled,
                    lastHitLeft: lastHitLeft,
                    lastHitRight: lastHitRight,
                    selectedButtonID: $selectedButtonID,
                    selectedColumn: $selectedColumn,
                    selectedGridKey: $selectedGridKey
                )
                TextEditor(text: $testText)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.6), lineWidth: 1)
                    )
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.05))
            )
        }
    }

    private struct RightSidebarView: View {
        @ObservedObject var viewModel: ContentViewModel
        @Binding var autoResyncEnabled: Bool
        let layoutSelection: Binding<TrackpadLayoutPreset>
        let layoutOption: TrackpadLayoutPreset
        let columnSelection: ColumnInspectorSelection?
        let buttonSelection: ButtonInspectorSelection?
        let keySelection: KeyInspectorSelection?
        let editModeEnabled: Bool
        @Binding var tapHoldDurationMs: Double
        @Binding var dragCancelDistanceSetting: Double
        @Binding var forceClickCapSetting: Double
        @Binding var hapticStrengthSetting: Double
        @Binding var typingGraceMsSetting: Double
        @Binding var intentMoveThresholdMmSetting: Double
        @Binding var intentVelocityThresholdMmPerSecSetting: Double
        @Binding var autocorrectEnabled: Bool
        @Binding var tapClickEnabled: Bool
        @Binding var tapClickCadenceMsSetting: Double
        @Binding var snapRadiusPercentSetting: Double
        @Binding var chordalShiftEnabled: Bool
        @Binding var keyboardModeEnabled: Bool
        @State private var typingTuningExpanded = true
        let onRefreshDevices: () -> Void
        let onAutoResyncChange: (Bool) -> Void
        let onAddCustomButton: (TrackpadSide) -> Void
        let onRemoveCustomButton: (UUID) -> Void
        let onClearTouchState: () -> Void
        let onUpdateColumn: (Int, (inout ColumnLayoutSettings) -> Void) -> Void
        let onUpdateButton: (UUID, (inout CustomButton) -> Void) -> Void
        let onUpdateKeyMapping: (SelectedGridKey, (inout KeyMapping) -> Void) -> Void
        let onRestoreDefaults: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                DevicesSectionView(
                    availableDevices: viewModel.availableDevices,
                    leftDevice: viewModel.leftDevice,
                    rightDevice: viewModel.rightDevice,
                    autoResyncEnabled: $autoResyncEnabled,
                    onSelectLeft: { device in
                        viewModel.selectLeftDevice(device)
                    },
                    onSelectRight: { device in
                        viewModel.selectRightDevice(device)
                    },
                    onAutoResyncChange: onAutoResyncChange,
                    onRefresh: onRefreshDevices
                )

                if !editModeEnabled {
                    DisclosureGroup(
                        isExpanded: $typingTuningExpanded
                    ) {
                        TypingTuningSectionView(
                            tapHoldDurationMs: $tapHoldDurationMs,
                            dragCancelDistanceSetting: $dragCancelDistanceSetting,
                            forceClickCapSetting: $forceClickCapSetting,
                            hapticStrengthSetting: $hapticStrengthSetting,
                            typingGraceMsSetting: $typingGraceMsSetting,
                            intentMoveThresholdMmSetting: $intentMoveThresholdMmSetting,
                            intentVelocityThresholdMmPerSecSetting: $intentVelocityThresholdMmPerSecSetting,
                            autocorrectEnabled: $autocorrectEnabled,
                            tapClickEnabled: $tapClickEnabled,
                            tapClickCadenceMsSetting: $tapClickCadenceMsSetting,
                            snapRadiusPercentSetting: $snapRadiusPercentSetting,
                            chordalShiftEnabled: $chordalShiftEnabled,
                            keyboardModeEnabled: $keyboardModeEnabled,
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
                }

                if editModeEnabled {
                    HStack(alignment: .top, spacing: 12) {
                        ColumnTuningSectionView(
                            layoutSelection: layoutSelection,
                            layoutOption: layoutOption,
                            selection: columnSelection,
                            onUpdateColumn: onUpdateColumn
                        )
                        ButtonTuningSectionView(
                            buttonSelection: buttonSelection,
                            keySelection: keySelection,
                            onAddCustomButton: onAddCustomButton,
                            onRemoveCustomButton: onRemoveCustomButton,
                            onClearTouchState: onClearTouchState,
                            onUpdateButton: onUpdateButton,
                            onUpdateKeyMapping: onUpdateKeyMapping
                        )
                    }
                }
            }
            .frame(width: 420)
        }
    }

#if DEBUG
    private func dumpTapTrace() {
        tapTraceDumpInProgress = true
        tapTraceDumpStatus = nil
        let queue = DispatchQueue.global(qos: .utility)
        queue.async {
            do {
                let url = TapTrace.defaultDumpURL()
                try TapTrace.dumpJSONL(to: url)
                let path = url.path
                DispatchQueue.main.async {
                    tapTraceDumpInProgress = false
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(path, forType: .string)
                    showTapTraceStatus("Path copied to clipboard")
                }
            } catch {
                DispatchQueue.main.async {
                    tapTraceDumpInProgress = false
                    showTapTraceStatus("Dump failed")
                    NSLog("Tap trace dump failed: %@", error.localizedDescription)
                }
            }
        }
    }

    private func showTapTraceStatus(_ message: String) {
        tapTraceDumpStatus = message
        let token = UUID()
        tapTraceDumpStatusToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if tapTraceDumpStatusToken == token {
                tapTraceDumpStatus = nil
            }
        }
    }
#endif

    private struct DevicesSectionView: View {
        let availableDevices: [OMSDeviceInfo]
        let leftDevice: OMSDeviceInfo?
        let rightDevice: OMSDeviceInfo?
        @Binding var autoResyncEnabled: Bool
        let onSelectLeft: (OMSDeviceInfo?) -> Void
        let onSelectRight: (OMSDeviceInfo?) -> Void
        let onAutoResyncChange: (Bool) -> Void
        let onRefresh: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("Devices")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if availableDevices.isEmpty {
                    Text("No trackpads detected.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Left Trackpad", selection: Binding(
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
                    .pickerStyle(MenuPickerStyle())

                    Picker("Right Trackpad", selection: Binding(
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
                    .pickerStyle(MenuPickerStyle())
                }
                HStack {
                    Toggle("Auto-resync disconnected trackpads", isOn: Binding(
                        get: { autoResyncEnabled },
                        set: { newValue in
                            autoResyncEnabled = newValue
                            onAutoResyncChange(newValue)
                        }
                    ))
                    .toggleStyle(SwitchToggleStyle())
                    .help("Polls every 8 seconds to detect disconnected trackpads.")

                    Spacer()

                    Button(action: {
                        onRefresh()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .imageScale(.medium)
                    }
                    .buttonStyle(.bordered)
                    .help("Refresh trackpad list")
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
        let layoutSelection: Binding<TrackpadLayoutPreset>
        let layoutOption: TrackpadLayoutPreset
        let selection: ColumnInspectorSelection?
        let onUpdateColumn: (Int, (inout ColumnLayoutSettings) -> Void) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("Column Tuning")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Layout")
                    Spacer()
                    Picker("", selection: layoutSelection) {
                        ForEach(TrackpadLayoutPreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                if layoutOption.hasGrid {
                    if let selection {
                        Text("Selected column \(selection.index + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 14) {
                            ColumnTuningRow(
                                title: "Scale",
                                value: Binding(
                                    get: { selection.settings.scale },
                                    set: { newValue in
                                        onUpdateColumn(selection.index) { setting in
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
                                title: "X",
                                value: Binding(
                                    get: { selection.settings.offsetXPercent },
                                    set: { newValue in
                                        onUpdateColumn(selection.index) { setting in
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
                                title: "Y",
                                value: Binding(
                                    get: { selection.settings.offsetYPercent },
                                    set: { newValue in
                                        onUpdateColumn(selection.index) { setting in
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
                                title: "Pad",
                                value: Binding(
                                    get: { selection.settings.rowSpacingPercent },
                                    set: { newValue in
                                        onUpdateColumn(selection.index) { setting in
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
                        }
                    } else {
                        Text("Select a column on the trackpad to edit.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(layoutOption == .mobile
                        ? "Mobile preset uses a fixed QWERTY grid on the right trackpad; column tuning is disabled."
                        : "Layout has no grid. Pick one of the presets to show keys.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.05))
            )
        }
    }

    private struct ButtonTuningSectionView: View {
        let buttonSelection: ButtonInspectorSelection?
        let keySelection: KeyInspectorSelection?
        let onAddCustomButton: (TrackpadSide) -> Void
        let onRemoveCustomButton: (UUID) -> Void
        let onClearTouchState: () -> Void
        let onUpdateButton: (UUID, (inout CustomButton) -> Void) -> Void
        let onUpdateKeyMapping: (SelectedGridKey, (inout KeyMapping) -> Void) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("Button Tuning")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Add Left") {
                        onAddCustomButton(.left)
                    }
                    Spacer()
                    Button("Add Right") {
                        onAddCustomButton(.right)
                    }
                }
                if let selection = buttonSelection {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Action", selection: Binding(
                            get: { selection.button.action },
                            set: { newValue in
                                onUpdateButton(selection.button.id) { button in
                                    button.action = newValue
                                }
                            }
                        )) {
                            Text(KeyActionCatalog.noneLabel)
                                .tag(KeyActionCatalog.noneAction)
                            ForEach(KeyActionCatalog.holdPresets, id: \.self) { action in
                                ContentView.pickerLabel(for: action).tag(action)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        Picker("Hold Action", selection: Binding(
                            get: { selection.button.hold },
                            set: { newValue in
                                onUpdateButton(selection.button.id) { button in
                                    button.hold = newValue
                                }
                            }
                        )) {
                            Text("None").tag(nil as KeyAction?)
                            ForEach(KeyActionCatalog.holdPresets, id: \.self) { action in
                                ContentView.pickerLabel(for: action).tag(action as KeyAction?)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        VStack(alignment: .leading, spacing: 14) {
                            ColumnTuningRow(
                                title: "X",
                                value: positionBinding(for: selection.button, axis: .x),
                                formatter: ContentView.columnOffsetFormatter,
                                range: positionRange(for: selection.button, axis: .x),
                                sliderStep: 1.0,
                                buttonStep: 0.5,
                                showSlider: false
                            )
                            ColumnTuningRow(
                                title: "Y",
                                value: positionBinding(for: selection.button, axis: .y),
                                formatter: ContentView.columnOffsetFormatter,
                                range: positionRange(for: selection.button, axis: .y),
                                sliderStep: 1.0,
                                buttonStep: 0.5,
                                showSlider: false
                            )
                            ColumnTuningRow(
                                title: "Width",
                                value: sizeBinding(for: selection.button, dimension: .width),
                                formatter: ContentView.columnOffsetFormatter,
                                range: sizeRange(for: selection.button, dimension: .width),
                                sliderStep: 1.0,
                                buttonStep: 0.5,
                                showSlider: false
                            )
                            ColumnTuningRow(
                                title: "Height",
                                value: sizeBinding(for: selection.button, dimension: .height),
                                formatter: ContentView.columnOffsetFormatter,
                                range: sizeRange(for: selection.button, dimension: .height),
                                sliderStep: 1.0,
                                buttonStep: 0.5,
                                showSlider: false
                            )
                        }
                        HStack {
                            Text("Selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Delete") {
                                onRemoveCustomButton(selection.button.id)
                            }
                        }
                    }
                } else if let selection = keySelection {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Selected key: \(selection.key.label)")
                            .font(.subheadline)
                            .bold()
                        Picker("Action", selection: Binding(
                            get: { selection.mapping.primary },
                            set: { newValue in
                                onUpdateKeyMapping(selection.key) { mapping in
                                    mapping.primary = newValue
                                }
                            }
                        )) {
                            Text(KeyActionCatalog.noneLabel)
                                .tag(KeyActionCatalog.noneAction)
                            ForEach(KeyActionCatalog.holdPresets, id: \.self) { action in
                                ContentView.pickerLabel(for: action).tag(action)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        Picker("Hold Action", selection: Binding(
                            get: { selection.mapping.hold },
                            set: { newValue in
                                onUpdateKeyMapping(selection.key) { mapping in
                                    mapping.hold = newValue
                                }
                            }
                        )) {
                            Text("None").tag(nil as KeyAction?)
                            ForEach(KeyActionCatalog.holdPresets, id: \.self) { action in
                                ContentView.pickerLabel(for: action).tag(action as KeyAction?)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                } else {
                    Text("Select a button or key on the trackpad to edit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.05))
            )
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    onClearTouchState()
                }
            )
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

    private struct TypingTuningSectionView: View {
        @Binding var tapHoldDurationMs: Double
        @Binding var dragCancelDistanceSetting: Double
        @Binding var forceClickCapSetting: Double
        @Binding var hapticStrengthSetting: Double
        @Binding var typingGraceMsSetting: Double
        @Binding var intentMoveThresholdMmSetting: Double
        @Binding var intentVelocityThresholdMmPerSecSetting: Double
        @Binding var autocorrectEnabled: Bool
        @Binding var tapClickEnabled: Bool
        @Binding var tapClickCadenceMsSetting: Double
        @Binding var snapRadiusPercentSetting: Double
        @Binding var chordalShiftEnabled: Bool
        @Binding var keyboardModeEnabled: Bool
        let onRestoreDefaults: () -> Void

        private let labelWidth: CGFloat = 140
        private let valueFieldWidth: CGFloat = 50

        private var snapRadiusEnabledBinding: Binding<Bool> {
            Binding(
                get: { snapRadiusPercentSetting > 0 },
                set: { snapRadiusPercentSetting = $0 ? 100.0 : 0.0 }
            )
        }

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
                        Text("Tap/Hold (ms)")
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
                        Text("Force Cap (g)")
                            .frame(width: labelWidth, alignment: .leading)
                        TextField(
                            "0",
                            value: $forceClickCapSetting,
                            formatter: ContentView.forceClickCapFormatter
                        )
                        .frame(width: valueFieldWidth)
                        Slider(
                            value: $forceClickCapSetting,
                            in: ContentView.forceClickCapRange,
                            step: 5
                        )
                        .frame(minWidth: 120)
                        .gridCellColumns(2)
                    }
                    GridRow {
                        Text("Tap/Drag (ms)")
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
                        Text("Haptic Strength")
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
                        Text("Autocorrect")
                            .frame(width: labelWidth, alignment: .leading)
                        Toggle("", isOn: $autocorrectEnabled)
                            .toggleStyle(SwitchToggleStyle())
                            .labelsHidden()
                        Text("Tap Click")
                            .frame(width: labelWidth, alignment: .leading)
                        Toggle("", isOn: $tapClickEnabled)
                            .toggleStyle(SwitchToggleStyle())
                            .labelsHidden()
                    }
                    GridRow {
                        Text("Snap Radius")
                            .frame(width: labelWidth, alignment: .leading)
                        Toggle("", isOn: snapRadiusEnabledBinding)
                            .toggleStyle(SwitchToggleStyle())
                            .labelsHidden()
                        Text("Chordal Shift")
                            .frame(width: labelWidth, alignment: .leading)
                        Toggle("", isOn: $chordalShiftEnabled)
                            .toggleStyle(SwitchToggleStyle())
                            .labelsHidden()
                    }
                    GridRow {
                        Text("Keyboard Mode")
                            .frame(width: labelWidth, alignment: .leading)
                        Toggle("", isOn: $keyboardModeEnabled)
                            .toggleStyle(SwitchToggleStyle())
                            .labelsHidden()
                        Spacer()
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

    private struct TrackpadDeckView: View {
        @ObservedObject var viewModel: ContentViewModel
        let trackpadSize: CGSize
        let leftLayout: ContentViewModel.Layout
        let rightLayout: ContentViewModel.Layout
        let leftGridLabelInfo: [[GridLabel]]
        let rightGridLabelInfo: [[GridLabel]]
        let leftGridLabels: [[String]]
        let rightGridLabels: [[String]]
        let customButtons: [CustomButton]
        @Binding var editModeEnabled: Bool
        @Binding var visualsEnabled: Bool
        let lastHitLeft: ContentViewModel.DebugHit?
        let lastHitRight: ContentViewModel.DebugHit?
        @Binding var selectedButtonID: UUID?
        @Binding var selectedColumn: Int?
        @Binding var selectedGridKey: SelectedGridKey?
        @State private var displayLeftTouchesState = [OMSTouchData]()
        @State private var displayRightTouchesState = [OMSTouchData]()
        @State private var lastTouchRevision: UInt64 = 0
        @State private var lastDisplayUpdateTime: TimeInterval = 0
        @State private var lastDisplayedHadTouches = false

        private let trackpadSpacing: CGFloat = 16
        private var combinedWidth: CGFloat {
            (trackpadSize.width * 2) + trackpadSpacing
        }

        var body: some View {
            let leftButtons = customButtons(for: .left)
            let rightButtons = customButtons(for: .right)
            let showDetailedView = visualsEnabled || selectedButtonID != nil
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
                    CombinedTrackpadCanvas(
                        trackpadSize: trackpadSize,
                        spacing: trackpadSpacing,
                        showDetailed: showDetailedView,
                        leftLayout: leftLayout,
                        rightLayout: rightLayout,
                        leftLabelInfo: leftGridLabelInfo,
                        rightLabelInfo: rightGridLabelInfo,
                        leftCustomButtons: leftButtons,
                        rightCustomButtons: rightButtons,
                        selectedColumn: editModeEnabled ? selectedColumn : nil,
                        selectedLeftKey: editModeEnabled ? selectedLeftKey : nil,
                        selectedRightKey: editModeEnabled ? selectedRightKey : nil,
                        selectedLeftButton: selectedButton(for: leftButtons),
                        selectedRightButton: selectedButton(for: rightButtons),
                        leftTouches: visualsEnabled ? displayLeftTouches : [],
                        rightTouches: visualsEnabled ? displayRightTouches : [],
                        visualsEnabled: visualsEnabled
                    )
                    if visualsEnabled && !editModeEnabled {
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
                    if editModeEnabled {
                        customButtonsOverlay(
                            side: .left,
                            layout: leftLayout,
                            buttons: leftButtons,
                            selectedButtonID: $selectedButtonID,
                            selectedColumn: $selectedColumn,
                            selectedGridKey: $selectedGridKey,
                            gridLabels: leftGridLabels
                        )
                        .offset(x: 0, y: 0)

                        customButtonsOverlay(
                            side: .right,
                            layout: rightLayout,
                            buttons: rightButtons,
                            selectedButtonID: $selectedButtonID,
                            selectedColumn: $selectedColumn,
                            selectedGridKey: $selectedGridKey,
                            gridLabels: rightGridLabels
                        )
                        .offset(x: trackpadSize.width + trackpadSpacing, y: 0)
                    }
                }
                .frame(width: combinedWidth, height: trackpadSize.height)
                .onAppear {
                    refreshTouchSnapshot(resetRevision: true)
                }
                .onChange(of: visualsEnabled) { enabled in
                    if enabled {
                        refreshTouchSnapshot(resetRevision: true)
                    } else {
                        displayLeftTouchesState = []
                        displayRightTouchesState = []
                        lastDisplayedHadTouches = false
                    }
                    viewModel.setStatusVisualsEnabled(enabled)
                }
                .task(id: visualsEnabled) {
                    guard visualsEnabled else { return }
                    var iterator = viewModel.touchRevisionUpdates.makeAsyncIterator()
                    while !Task.isCancelled {
                        guard let _ = await iterator.next() else { break }
                        if Task.isCancelled { break }
                        refreshTouchSnapshot(resetRevision: false)
                    }
                }
            }
        }

        private func refreshTouchSnapshot(resetRevision: Bool) {
            let snapshot: ContentViewModel.TouchSnapshot
            if resetRevision {
                snapshot = viewModel.snapshotTouchData()
                lastTouchRevision = snapshot.revision
            } else if let updated = viewModel.snapshotTouchDataIfUpdated(since: lastTouchRevision) {
                snapshot = updated
                lastTouchRevision = updated.revision
            } else {
                return
            }

            let now = CACurrentMediaTime()
            if resetRevision || shouldUpdateDisplay(snapshot: snapshot, now: now) {
                displayLeftTouchesState = snapshot.left
                displayRightTouchesState = snapshot.right
                lastDisplayUpdateTime = now
                lastDisplayedHadTouches = !(snapshot.left.isEmpty && snapshot.right.isEmpty)
            }
        }

        private var displayLeftTouches: [OMSTouchData] {
            displayLeftTouchesState
        }

        private var displayRightTouches: [OMSTouchData] {
            displayRightTouchesState
        }

        private func customButtons(for side: TrackpadSide) -> [CustomButton] {
            customButtons.filter { $0.side == side && $0.layer == viewModel.activeLayer }
        }

        private func shouldUpdateDisplay(
            snapshot: ContentViewModel.TouchSnapshot,
            now: TimeInterval
        ) -> Bool {
            guard editModeEnabled else { return true }

            let hasTouches = !(snapshot.left.isEmpty && snapshot.right.isEmpty)
            if hasTouches != lastDisplayedHadTouches {
                return true
            }

            if snapshot.hasTransitionState {
                return true
            }

            let clampedHz = 20.0
            let minInterval = 1.0 / clampedHz
            return now - lastDisplayUpdateTime >= minInterval
        }

        private func customButtonsOverlay(
            side: TrackpadSide,
            layout: ContentViewModel.Layout,
            buttons: [CustomButton],
            selectedButtonID: Binding<UUID?>,
            selectedColumn: Binding<Int?>,
            selectedGridKey: Binding<SelectedGridKey?>,
            gridLabels: [[String]]
        ) -> some View {
            ZStack(alignment: .topLeading) {
                let columnRects = columnRects(for: layout.keyRects, trackpadSize: trackpadSize)
                let selectGesture = DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onEnded { value in
                        viewModel.clearTouchState()
                        let point = value.location
                        if let matched = buttons.last(where: { button in
                            button.rect.rect(in: trackpadSize).contains(point)
                        }) {
                            selectedButtonID.wrappedValue = matched.id
                            selectedColumn.wrappedValue = nil
                            selectedGridKey.wrappedValue = nil
                            return
                        }
                        selectedButtonID.wrappedValue = nil
                        if let key = gridKey(at: point, keyRects: layout.keyRects, labels: gridLabels, side: side) {
                            selectedGridKey.wrappedValue = key
                            selectedColumn.wrappedValue = key.column
                            return
                        }
                        selectedGridKey.wrappedValue = nil
                        let resolvedColumnIndex = columnIndex(for: point, columnRects: columnRects)
                        #if DEBUG
                        logColumnSelection(
                            point: point,
                            columnRects: columnRects,
                            resolvedIndex: resolvedColumnIndex
                        )
                        #endif
                        if let columnIndex = resolvedColumnIndex {
                            selectedColumn.wrappedValue = columnIndex
                        } else {
                            selectedColumn.wrappedValue = nil
                        }
                    }
                Color.clear
                    .frame(width: trackpadSize.width, height: trackpadSize.height)
                    .contentShape(Rectangle())
                    .simultaneousGesture(selectGesture)
            }
        }

        private func selectedButton(for buttons: [CustomButton]) -> CustomButton? {
            guard let selectedButtonID else { return nil }
            return buttons.first { $0.id == selectedButtonID }
        }

        private func columnRects(
            for keyRects: [[CGRect]],
            trackpadSize: CGSize
        ) -> [CGRect] {
            let columnCount = keyRects.map { $0.count }.max() ?? 0
            guard columnCount > 0 else { return [] }
            var rects = Array(repeating: CGRect.null, count: columnCount)
            for row in keyRects {
                for col in 0..<row.count {
                    rects[col] = rects[col].union(row[col])
                }
            }

            let width = trackpadSize.width
            let height = trackpadSize.height
            let sortedIndices = rects.enumerated()
                .sorted { lhs, rhs in
                    let lhsMid = lhs.element.isNull ? 0 : lhs.element.midX
                    let rhsMid = rhs.element.isNull ? 0 : rhs.element.midX
                    return lhsMid < rhsMid
                }
                .map(\.offset)

            var boundaries = Array(repeating: CGFloat.zero, count: columnCount + 1)
            boundaries[0] = 0

            for physicalIndex in 0..<max(0, sortedIndices.count - 1) {
                let current = rects[sortedIndices[physicalIndex]]
                let next = rects[sortedIndices[physicalIndex + 1]]
                let currentMid = current.isNull ? 0 : current.midX
                let nextMid = next.isNull ? width : next.midX
                boundaries[physicalIndex + 1] = (currentMid + nextMid) / 2.0
            }

            boundaries[columnCount] = width

            let columnHeight = height
            var expandedRects = rects
            for physicalIndex in 0..<sortedIndices.count {
                let colIndex = sortedIndices[physicalIndex]
                let left = boundaries[physicalIndex]
                let right = boundaries[physicalIndex + 1]
                expandedRects[colIndex] = CGRect(
                    x: left,
                    y: 0,
                    width: max(0, right - left),
                    height: columnHeight
                )
            }

            return expandedRects
        }

        private func gridKey(
            at point: CGPoint,
            keyRects: [[CGRect]],
            labels: [[String]],
            side: TrackpadSide
        ) -> SelectedGridKey? {
            for rowIndex in 0..<keyRects.count {
                guard rowIndex < labels.count else { continue }
                for colIndex in 0..<keyRects[rowIndex].count {
                    guard colIndex < labels[rowIndex].count else { continue }
                    let rect = keyRects[rowIndex][colIndex]
                    if rect.contains(point) {
                        return SelectedGridKey(
                            row: rowIndex,
                            column: colIndex,
                            label: labels[rowIndex][colIndex],
                            side: side
                        )
                    }
                }
            }
            return nil
        }

        private func columnIndex(
            for point: CGPoint,
            columnRects: [CGRect]
        ) -> Int? {
            if let index = columnRects.firstIndex(where: { $0.contains(point) }) {
                return index
            }
            let columnCount = columnRects.count
            guard trackpadSize.width > 0, columnCount > 0 else { return nil }
            let normalizedX = min(max(point.x / trackpadSize.width, 0), 1)
            var index = Int(normalizedX * CGFloat(columnCount))
            if index == columnCount {
                index = columnCount - 1
            }
            return index
        }

        private func logColumnSelection(
            point: CGPoint,
            columnRects: [CGRect],
            resolvedIndex: Int?
        ) {
        }
    }

    private struct CombinedTrackpadCanvas: View {
        let trackpadSize: CGSize
        let spacing: CGFloat
        let showDetailed: Bool
        let leftLayout: ContentViewModel.Layout
        let rightLayout: ContentViewModel.Layout
        let leftLabelInfo: [[GridLabel]]
        let rightLabelInfo: [[GridLabel]]
        let leftCustomButtons: [CustomButton]
        let rightCustomButtons: [CustomButton]
        let selectedColumn: Int?
        let selectedLeftKey: SelectedGridKey?
        let selectedRightKey: SelectedGridKey?
        let selectedLeftButton: CustomButton?
        let selectedRightButton: CustomButton?
        let leftTouches: [OMSTouchData]
        let rightTouches: [OMSTouchData]
        let visualsEnabled: Bool

        var body: some View {
            Canvas { context, _ in
                let leftOrigin = CGPoint.zero
                let rightOrigin = CGPoint(x: trackpadSize.width + spacing, y: 0)
                let leftRect = CGRect(origin: leftOrigin, size: trackpadSize)
                let rightRect = CGRect(origin: rightOrigin, size: trackpadSize)
                let borderColor = Color.secondary.opacity(0.6)
                context.stroke(
                    Path(roundedRect: leftRect, cornerRadius: ContentView.keyCornerRadius),
                    with: .color(borderColor),
                    lineWidth: 1
                )
                context.stroke(
                    Path(roundedRect: rightRect, cornerRadius: ContentView.keyCornerRadius),
                    with: .color(borderColor),
                    lineWidth: 1
                )

                guard showDetailed else { return }

                ContentView.drawTrackpadContents(
                    context: &context,
                    origin: leftOrigin,
                    layout: leftLayout,
                    labelInfo: leftLabelInfo,
                    customButtons: leftCustomButtons,
                    selectedColumn: selectedColumn,
                    selectedKey: selectedLeftKey,
                    selectedButton: selectedLeftButton,
                    touches: leftTouches,
                    trackpadSize: trackpadSize,
                    visualsEnabled: visualsEnabled
                )
                ContentView.drawTrackpadContents(
                    context: &context,
                    origin: rightOrigin,
                    layout: rightLayout,
                    labelInfo: rightLabelInfo,
                    customButtons: rightCustomButtons,
                    selectedColumn: selectedColumn,
                    selectedKey: selectedRightKey,
                    selectedButton: selectedRightButton,
                    touches: rightTouches,
                    trackpadSize: trackpadSize,
                    visualsEnabled: visualsEnabled
                )
            }
            .frame(width: (trackpadSize.width * 2) + spacing, height: trackpadSize.height)
        }
    }

    private struct LastHitHighlightLayer: View {
        let lastHit: ContentViewModel.DebugHit

        var body: some View {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { _ in
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

    private static func makeEllipse(touch: OMSTouchData, size: CGSize) -> Path {
        let x = Double(touch.position.x) * size.width
        let y = Double(1.0 - touch.position.y) * size.height
        let u = size.width / 100.0
        let w = Double(touch.axis.major) * u
        let h = Double(touch.axis.minor) * u
        return Path(ellipseIn: CGRect(x: -0.5 * w, y: -0.5 * h, width: w, height: h))
            .rotation(.radians(Double(-touch.angle)), anchor: .topLeading)
            .offset(x: x, y: y)
            .path(in: CGRect(origin: .zero, size: size))
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
        mirrored: Bool = false
    ) -> ContentViewModel.Layout {
        guard columns > 0,
              rows > 0,
              columnAnchorsMM.count == columns else {
            return ContentViewModel.Layout(keyRects: [], trackpadSize: size)
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

        let columnOffsets = resolvedSettings.map { setting in
            CGSize(
                width: size.width * CGFloat(setting.offsetXPercent / 100.0),
                height: size.height * CGFloat(setting.offsetYPercent / 100.0)
            )
        }
        if mirrored {
            let mirroredKeyRects = keyRects.map { row in
                row.map { rect in
                    CGRect(
                        x: size.width - rect.maxX,
                        y: rect.minY,
                        width: rect.width,
                        height: rect.height
                    )
                }
            }
            var adjusted = mirroredKeyRects
            let mirroredOffsets = columnOffsets.map { offset in
                CGSize(width: -offset.width, height: offset.height)
            }
            applyColumnOffsets(keyRects: &adjusted, columnOffsets: mirroredOffsets)
            return ContentViewModel.Layout(keyRects: adjusted, trackpadSize: size)
        }

        applyColumnOffsets(keyRects: &keyRects, columnOffsets: columnOffsets)
        return ContentViewModel.Layout(keyRects: keyRects, trackpadSize: size)
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
        keyRects: inout [[CGRect]],
        columnOffsets: [CGSize]
    ) {
        guard !columnOffsets.isEmpty else { return }
        for rowIndex in 0..<keyRects.count {
            for colIndex in 0..<keyRects[rowIndex].count {
                let offset = columnOffsets.indices.contains(colIndex)
                    ? columnOffsets[colIndex]
                    : .zero
                keyRects[rowIndex][colIndex] = keyRects[rowIndex][colIndex]
                    .offsetBy(dx: offset.width, dy: offset.height)
            }
        }
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
        selectedColumn = nil
        selectedGridKey = nil
        selectedButtonID = nil
        columnSettings = columnSettings(for: newLayout)
        customButtons = loadCustomButtons(for: newLayout)
        viewModel.updateCustomButtons(customButtons)
        updateGridLabelInfo()
        applyColumnSettings(columnSettings)
        saveSettings()
    }

    private func rebuildLayouts() {
        if layoutOption == .mobile {
            leftLayout = ContentViewModel.Layout(keyRects: [], trackpadSize: trackpadSize)
            rightLayout = ContentView.makeMobileKeyLayout(size: trackpadSize)
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
            columnSettings: columnSettings
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
        visualsEnabled = storedVisualsEnabled
        viewModel.setStatusVisualsEnabled(visualsEnabled)
        AutocorrectEngine.shared.setEnabled(autocorrectEnabled)
        AutocorrectEngine.shared.setMinimumWordLength(GlassToKeySettings.autocorrectMinWordLength)
        let resolvedLayout = TrackpadLayoutPreset(rawValue: storedLayoutPreset) ?? .sixByThree
        layoutOption = resolvedLayout
        selectedColumn = nil
        selectedGridKey = nil
        selectedButtonID = nil
        columnSettings = columnSettings(for: resolvedLayout)
        customButtons = loadCustomButtons(for: resolvedLayout)
        viewModel.updateCustomButtons(customButtons)
        loadKeyMappings()
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
        viewModel.updateForceClickCap(forceClickCapSetting)
        viewModel.updateHapticStrength(hapticStrengthSetting / 100.0)
        viewModel.updateTypingGraceMs(typingGraceMsSetting)
        viewModel.updateIntentMoveThresholdMm(intentMoveThresholdMmSetting)
        viewModel.updateIntentVelocityThresholdMmPerSec(intentVelocityThresholdMmPerSecSetting)
        viewModel.updateAllowMouseTakeover(true)
        viewModel.updateSnapRadiusPercent(snapRadiusPercentSetting)
        viewModel.updateChordalShiftEnabled(chordalShiftEnabled)
        viewModel.updateKeyboardModeEnabled(keyboardModeEnabled)
        viewModel.updateTapClickCadenceMs(tapClickCadenceMsSetting)
        viewModel.setTouchSnapshotRecordingEnabled(visualsEnabled)
    }

    private func restoreTypingTuningDefaults() {
        visualsEnabled = true
        tapHoldDurationMs = GlassToKeySettings.tapHoldDurationMs
        dragCancelDistanceSetting = GlassToKeySettings.dragCancelDistanceMm
        forceClickCapSetting = GlassToKeySettings.forceClickCap
        hapticStrengthSetting = GlassToKeySettings.hapticStrengthPercent
        typingGraceMsSetting = GlassToKeySettings.typingGraceMs
        intentMoveThresholdMmSetting = GlassToKeySettings.intentMoveThresholdMm
        intentVelocityThresholdMmPerSecSetting = GlassToKeySettings.intentVelocityThresholdMmPerSec
        autocorrectEnabled = GlassToKeySettings.autocorrectEnabled
        tapClickEnabled = GlassToKeySettings.tapClickEnabled
        tapClickCadenceMsSetting = GlassToKeySettings.tapClickCadenceMs
        snapRadiusPercentSetting = GlassToKeySettings.snapRadiusPercent
        chordalShiftEnabled = GlassToKeySettings.chordalShiftEnabled
        keyboardModeEnabled = GlassToKeySettings.keyboardModeEnabled
        AutocorrectEngine.shared.setMinimumWordLength(GlassToKeySettings.autocorrectMinWordLength)
    }

    private func saveSettings() {
        storedLeftDeviceID = viewModel.leftDevice?.deviceID ?? ""
        storedRightDeviceID = viewModel.rightDevice?.deviceID ?? ""
        storedVisualsEnabled = visualsEnabled
        storedLayoutPreset = layoutOption.rawValue
        saveCurrentColumnSettings()
    }

    private func persistConfig() {
        saveSettings()
        saveCustomButtons(customButtons)
        saveKeyMappings(keyMappingsByLayer)
    }

    private func columnSettings(
        for layout: TrackpadLayoutPreset
    ) -> [ColumnLayoutSettings] {
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
        if let decoded = KeyActionMappingStore.decodeNormalized(storedKeyMappingsData) {
            keyMappingsByLayer = decoded
        } else {
            keyMappingsByLayer = [0: [:], 1: [:]]
        }
        viewModel.updateKeyMappings(keyMappingsByLayer)
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

    private func saveKeyMappings(_ mappings: LayeredKeyMappings) {
        storedKeyMappingsData = KeyActionMappingStore.encode(mappings) ?? Data()
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
        if !visualsEnabled {
            visualsEnabled = true
        }
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

    private static func drawSensorGrid(
        context: inout GraphicsContext,
        size: CGSize,
        columns: Int,
        rows: Int
    ) {
        guard columns > 0, rows > 0 else { return }
        let strokeColor = Color.secondary.opacity(0.2)
        let lineWidth = CGFloat(0.5)

        let columnWidth = size.width / CGFloat(columns)
        let rowHeight = size.height / CGFloat(rows)

        for col in 0...columns {
            let x = CGFloat(col) * columnWidth
            let path = Path { path in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            context.stroke(path, with: .color(strokeColor), lineWidth: lineWidth)
        }

        for row in 0...rows {
            let y = CGFloat(row) * rowHeight
            let path = Path { path in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(strokeColor), lineWidth: lineWidth)
        }
    }

    private static func drawKeyGrid(
        context: inout GraphicsContext,
        keyRects: [[CGRect]]
    ) {
        for row in keyRects {
            for rect in row {
                let keyPath = Path(roundedRect: rect, cornerRadius: Self.keyCornerRadius)
                context.stroke(keyPath, with: .color(.secondary.opacity(0.6)), lineWidth: 1)
            }
        }
    }

    private static func drawKeySelection(
        context: inout GraphicsContext,
        keyRects: [[CGRect]],
        selectedColumn: Int?,
        selectedKey: SelectedGridKey?
    ) {
        if let selectedColumn,
           keyRects.first?.indices.contains(selectedColumn) == true {
            for row in keyRects {
                let rect = row[selectedColumn]
                let keyPath = Path(roundedRect: rect, cornerRadius: Self.keyCornerRadius)
                context.fill(keyPath, with: .color(Color.accentColor.opacity(0.12)))
                context.stroke(keyPath, with: .color(Color.accentColor.opacity(0.8)), lineWidth: 1.5)
            }
        }

        if let key = selectedKey,
           keyRects.indices.contains(key.row),
           keyRects[key.row].indices.contains(key.column) {
            let rect = keyRects[key.row][key.column]
            let keyPath = Path(roundedRect: rect, cornerRadius: Self.keyCornerRadius)
            context.fill(keyPath, with: .color(Color.accentColor.opacity(0.18)))
            context.stroke(keyPath, with: .color(Color.accentColor.opacity(0.9)), lineWidth: 1.5)
        }
    }

    private static func drawCustomButtons(
        context: inout GraphicsContext,
        buttons: [CustomButton],
        trackpadSize: CGSize
    ) {
        let primaryStyle = Font.system(size: 10, weight: .semibold, design: .monospaced)
        let holdStyle = Font.system(size: 8, weight: .semibold, design: .monospaced)
        for button in buttons {
            let rect = button.rect.rect(in: trackpadSize)
            let buttonPath = Path(roundedRect: rect, cornerRadius: Self.keyCornerRadius)
            context.fill(buttonPath, with: .color(Color.blue.opacity(0.12)))
            context.stroke(buttonPath, with: .color(.secondary.opacity(0.6)), lineWidth: 1)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let primaryText = Text(button.action.displayText)
                .font(primaryStyle)
                .foregroundColor(.secondary)
            let primaryY = center.y - (button.hold != nil ? 4 : 0)
            context.draw(primaryText, at: CGPoint(x: center.x, y: primaryY))
            if let holdLabel = button.hold?.label {
                let holdText = Text(holdLabel)
                    .font(holdStyle)
                    .foregroundColor(.secondary.opacity(0.7))
                context.draw(holdText, at: CGPoint(x: center.x, y: center.y + 6))
            }
        }
    }

    private func labelInfo(for key: SelectedGridKey) -> (primary: String, hold: String?) {
        let mapping = effectiveKeyMapping(for: key)
        return (primary: mapping.primary.displayText, hold: mapping.hold?.label)
    }

    private func refreshColumnInspectorSelection() {
        guard let selectedColumn,
              columnSettings.indices.contains(selectedColumn) else {
            columnInspectorSelection = nil
            return
        }
        columnInspectorSelection = ColumnInspectorSelection(
            index: selectedColumn,
            settings: columnSettings[selectedColumn]
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
        let allowHold = layoutOption != .mobile
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
            ? KeyActionCatalog.typingToggleDisplayLabel
            : action.label
        return Text(label)
            .multilineTextAlignment(.center)
    }

    private func effectiveKeyMapping(for key: SelectedGridKey) -> KeyMapping {
        let layerMappings = keyMappingsForActiveLayer()
        if let mapping = layerMappings[key.storageKey] {
            return mapping
        }
        if let mapping = layerMappings[key.label] {
            return mapping
        }
        return defaultKeyMapping(for: key.label) ?? KeyMapping(primary: KeyAction(label: key.label, keyCode: 0, flags: 0), hold: nil)
    }

    private func updateKeyMapping(
        for key: SelectedGridKey,
        _ update: (inout KeyMapping) -> Void
    ) {
        let layer = viewModel.activeLayer
        var layerMappings = keyMappingsByLayer[layer] ?? [:]
        var mapping = layerMappings[key.storageKey]
            ?? layerMappings[key.label]
            ?? defaultKeyMapping(for: key.label)
            ?? KeyMapping(primary: KeyAction(label: key.label, keyCode: 0, flags: 0), hold: nil)
        update(&mapping)
        if let defaultMapping = defaultKeyMapping(for: key.label),
           defaultMapping == mapping {
            layerMappings.removeValue(forKey: key.storageKey)
            layerMappings.removeValue(forKey: key.label)
            keyMappingsByLayer[layer] = layerMappings
            return
        }
        layerMappings[key.storageKey] = mapping
        layerMappings.removeValue(forKey: key.label)
        keyMappingsByLayer[layer] = layerMappings
    }

    private func updateKeyMappingAndSelection(
        key: SelectedGridKey,
        update: (inout KeyMapping) -> Void
    ) {
        updateKeyMapping(for: key, update)
        refreshKeyInspectorSelection()
    }

    private func defaultKeyMapping(for label: String) -> KeyMapping? {
        guard let primary = KeyActionCatalog.action(for: label) else { return nil }
        return KeyMapping(primary: primary, hold: KeyActionCatalog.holdAction(for: label))
    }

    private static func drawGridLabels(
        context: inout GraphicsContext,
        keyRects: [[CGRect]],
        labelInfo: [[GridLabel]]
    ) {
        let textStyle = Font.system(size: 10, weight: .semibold, design: .monospaced)

        for row in 0..<keyRects.count {
            for col in 0..<keyRects[row].count {
                guard row < labelInfo.count,
                      col < labelInfo[row].count else { continue }
                let rect = keyRects[row][col]
                let center = CGPoint(x: rect.midX, y: rect.midY)
                let info = labelInfo[row][col]
                let primaryText = Text(info.primary)
                    .font(textStyle)
                    .foregroundColor(.secondary)
                context.draw(primaryText, at: CGPoint(x: center.x, y: center.y - 4))
                if let holdLabel = info.hold {
                    let holdText = Text(holdLabel)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                    context.draw(holdText, at: CGPoint(x: center.x, y: center.y + 6))
                }
            }
        }
    }

    private static func drawTrackpadContents(
        context: inout GraphicsContext,
        origin: CGPoint,
        layout: ContentViewModel.Layout,
        labelInfo: [[GridLabel]],
        customButtons: [CustomButton],
        selectedColumn: Int?,
        selectedKey: SelectedGridKey?,
        selectedButton: CustomButton?,
        touches: [OMSTouchData],
        trackpadSize: CGSize,
        visualsEnabled: Bool
    ) {
        withTranslatedContext(context: &context, origin: origin) { innerContext in
            drawSensorGrid(
                context: &innerContext,
                size: trackpadSize,
                columns: 30,
                rows: 22
            )
            drawKeyGrid(context: &innerContext, keyRects: layout.keyRects)
            drawCustomButtons(
                context: &innerContext,
                buttons: customButtons,
                trackpadSize: trackpadSize
            )
            drawGridLabels(
                context: &innerContext,
                keyRects: layout.keyRects,
                labelInfo: labelInfo
            )
            drawKeySelection(
                context: &innerContext,
                keyRects: layout.keyRects,
                selectedColumn: selectedColumn,
                selectedKey: selectedKey
            )
            drawButtonSelection(
                context: &innerContext,
                button: selectedButton,
                trackpadSize: trackpadSize
            )
            if visualsEnabled {
                drawTrackpadTouches(
                    context: &innerContext,
                    touches: touches,
                    trackpadSize: trackpadSize
                )
            }
        }
    }

    private static func drawButtonSelection(
        context: inout GraphicsContext,
        button: CustomButton?,
        trackpadSize: CGSize
    ) {
        guard let button else { return }
        let rect = button.rect.rect(in: trackpadSize)
        let path = Path(roundedRect: rect, cornerRadius: ContentView.keyCornerRadius)
        context.fill(path, with: .color(Color.accentColor.opacity(0.08)))
        context.stroke(path, with: .color(Color.accentColor.opacity(0.9)), lineWidth: 1.5)
    }

    private static func drawTrackpadTouches(
        context: inout GraphicsContext,
        touches: [OMSTouchData],
        trackpadSize: CGSize
    ) {
        touches.forEach { touch in
            let path = makeEllipse(touch: touch, size: trackpadSize)
            context.fill(path, with: .color(.primary.opacity(Double(touch.total))))
        }
    }

    private static func withTranslatedContext(
        context: inout GraphicsContext,
        origin: CGPoint,
        draw: (inout GraphicsContext) -> Void
    ) {
        context.translateBy(x: origin.x, y: origin.y)
        draw(&context)
        context.translateBy(x: -origin.x, y: -origin.y)
    }

    private var layerToggleBinding: Binding<Bool> {
        Binding(
            get: { viewModel.activeLayer == 1 },
            set: { isOn in
                viewModel.setPersistentLayer(isOn ? 1 : 0)
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
