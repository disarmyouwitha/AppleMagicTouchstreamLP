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

private struct CompactAssignmentMenuKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var compactAssignmentMenu: Bool {
        get { self[CompactAssignmentMenuKey.self] }
        set { self[CompactAssignmentMenuKey.self] = newValue }
    }
}

struct ContentView: View {
    @ObservedObject var nativeTakeover: NativeTrackpadTakeover
    @State private var inspectorTab = "Keyboard"
    @AppStorage(WorkspaceColumnSizing.menuWidthKey) private var menuColumnWidth = WorkspaceColumnSizing.defaultMenuWidth
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

    @StateObject private var viewModel: ContentViewModel
    @State private var testText = ""
    @State private var autocorrectCurrentBufferText = "<empty>"
    @State private var autocorrectLastCorrectedText = "none"
    @State private var columnSettings: [ColumnLayoutSettings]
    @State private var leftLayout: ContentViewModel.Layout
    @State private var rightLayout: ContentViewModel.Layout
    @State private var keySpacingPercent = LayoutKeySpacingDefaults.defaultPercent
    @State private var customButtons: [CustomButton] = []
    @State private var selectedButtonID: UUID?
    @State private var editColumnIndex = 0
    @State private var selectedGridKey: SelectedGridKey?
    @State private var columnInspectorSelection: ColumnInspectorSelection?
    @State private var buttonInspectorSelection: ButtonInspectorSelection?
    @State private var keyInspectorSelection: KeyInspectorSelection?
    @State private var inspectorSelectionRevision = 0
    @State private var primaryActionGroups = KeyActionCatalog.primaryActionGroups
    @State private var holdActionGroups = KeyActionCatalog.holdActionGroups
    @State private var gestureActionGroups = KeyActionCatalog.primaryActionGroups
    @State private var keyMappingsByLayer: LayeredKeyMappings = [:]
    @State private var keyMappingsByLayout: LayoutLayeredKeyMappings = [:]
    @State private var keyGeometryOverrides: KeyGeometryOverrides = [:]
    @State private var layoutOption: TrackpadLayoutPreset = .sixByThree
    @State private var leftGridLabelInfo: [[GridLabel]] = []
    @State private var rightGridLabelInfo: [[GridLabel]] = []
    @State private var replayScrubValue: Double = 0
    @State private var replayScrubInProgress = false
    @State private var systemThreeFingerDragEnabled = false
    @AppStorage(GlassToKeyDefaultsKeys.gestureRecognitionEnabled)
    private var gestureRecognitionEnabled = false
    @AppStorage(GlassToKeyDefaultsKeys.leftDeviceID) private var storedLeftDeviceID = ""
    @AppStorage(GlassToKeyDefaultsKeys.rightDeviceID) private var storedRightDeviceID = ""
    @AppStorage(GlassToKeyDefaultsKeys.columnSettings) private var storedColumnSettingsData = Data()
    @AppStorage(GlassToKeyDefaultsKeys.keySpacingByLayout) private var storedKeySpacingByLayoutData = Data()
    @AppStorage(GlassToKeyDefaultsKeys.layoutPreset) private var storedLayoutPreset = TrackpadLayoutPreset.sixByThree.rawValue
    @AppStorage(GlassToKeyDefaultsKeys.customButtons) private var storedCustomButtonsData = Data()
    @AppStorage(GlassToKeyDefaultsKeys.keyMappings) private var storedKeyMappingsData = Data()
    @AppStorage(GlassToKeyDefaultsKeys.keyGeometry) private var storedKeyGeometryData = Data()
    @AppStorage(GlassToKeyDefaultsKeys.shortcutActions) private var storedShortcutActionsData = Data()
    @AppStorage(GlassToKeyDefaultsKeys.autoResyncMissingTrackpads) private var storedAutoResyncMissingTrackpads = false
    @AppStorage(GlassToKeyDefaultsKeys.tapHoldDuration) private var tapHoldDurationMs: Double = GlassToKeySettings.tapHoldDurationMs
    @AppStorage(GlassToKeyDefaultsKeys.dragCancelDistance) private var dragCancelDistanceSetting: Double = GlassToKeySettings.dragCancelDistanceMm
    @AppStorage(GlassToKeyDefaultsKeys.forceClickMin) private var forceClickMinSetting: Double = GlassToKeySettings.forceClickMin
    @AppStorage(GlassToKeyDefaultsKeys.forceClickCap) private var forceClickCapSetting: Double = GlassToKeySettings.forceClickCap
    @AppStorage(GlassToKeyDefaultsKeys.forceClickThreshold) private var forceClickThresholdSetting: Double = GlassToKeySettings.forceClickThreshold
    @AppStorage(GlassToKeyDefaultsKeys.hapticStrength) private var hapticStrengthSetting: Double = GlassToKeySettings.hapticStrengthPercent
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
    @AppStorage(GlassToKeyDefaultsKeys.keyboardModeEnabled)
    private var keyboardModeEnabled = GlassToKeySettings.keyboardModeEnabled
    @AppStorage(GlassToKeyDefaultsKeys.holdRepeatEnabled)
    private var holdRepeatEnabled = GlassToKeySettings.holdRepeatEnabled
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
    @AppStorage(GlassToKeyDefaultsKeys.leftEdgeUpGestureAction)
    private var leftEdgeUpGestureAction = GlassToKeySettings.leftEdgeUpGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.leftEdgeDownGestureAction)
    private var leftEdgeDownGestureAction = GlassToKeySettings.leftEdgeDownGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.rightEdgeUpGestureAction)
    private var rightEdgeUpGestureAction = GlassToKeySettings.rightEdgeUpGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.rightEdgeDownGestureAction)
    private var rightEdgeDownGestureAction = GlassToKeySettings.rightEdgeDownGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.topEdgeLeftGestureAction)
    private var topEdgeLeftGestureAction = GlassToKeySettings.topEdgeLeftGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.topEdgeRightGestureAction)
    private var topEdgeRightGestureAction = GlassToKeySettings.topEdgeRightGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.bottomEdgeLeftGestureAction)
    private var bottomEdgeLeftGestureAction = GlassToKeySettings.bottomEdgeLeftGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.bottomEdgeRightGestureAction)
    private var bottomEdgeRightGestureAction = GlassToKeySettings.bottomEdgeRightGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.threeFingerSwipeLeftGestureAction)
    private var threeFingerSwipeLeftGestureAction = GlassToKeySettings.threeFingerSwipeLeftGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.threeFingerSwipeRightGestureAction)
    private var threeFingerSwipeRightGestureAction = GlassToKeySettings.threeFingerSwipeRightGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.threeFingerSwipeUpGestureAction)
    private var threeFingerSwipeUpGestureAction = GlassToKeySettings.threeFingerSwipeUpGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.threeFingerSwipeDownGestureAction)
    private var threeFingerSwipeDownGestureAction = GlassToKeySettings.threeFingerSwipeDownGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.fourFingerSwipeLeftGestureAction)
    private var fourFingerSwipeLeftGestureAction = GlassToKeySettings.fourFingerSwipeLeftGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.fourFingerSwipeRightGestureAction)
    private var fourFingerSwipeRightGestureAction = GlassToKeySettings.fourFingerSwipeRightGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.fourFingerSwipeUpGestureAction)
    private var fourFingerSwipeUpGestureAction = GlassToKeySettings.fourFingerSwipeUpGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.fourFingerSwipeDownGestureAction)
    private var fourFingerSwipeDownGestureAction = GlassToKeySettings.fourFingerSwipeDownGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.fiveFingerSwipeLeftGestureAction)
    private var fiveFingerSwipeLeftGestureAction = GlassToKeySettings.fiveFingerSwipeLeftGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.fiveFingerSwipeRightGestureAction)
    private var fiveFingerSwipeRightGestureAction = GlassToKeySettings.fiveFingerSwipeRightGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.fiveFingerSwipeUpGestureAction)
    private var fiveFingerSwipeUpGestureAction = GlassToKeySettings.fiveFingerSwipeUpGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.fiveFingerSwipeDownGestureAction)
    private var fiveFingerSwipeDownGestureAction = GlassToKeySettings.fiveFingerSwipeDownGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.topLeftCornerSwipeGestureAction)
    private var topLeftCornerSwipeGestureAction = GlassToKeySettings.topLeftCornerSwipeGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.topRightCornerSwipeGestureAction)
    private var topRightCornerSwipeGestureAction = GlassToKeySettings.topRightCornerSwipeGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.bottomLeftCornerSwipeGestureAction)
    private var bottomLeftCornerSwipeGestureAction = GlassToKeySettings.bottomLeftCornerSwipeGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.bottomRightCornerSwipeGestureAction)
    private var bottomRightCornerSwipeGestureAction = GlassToKeySettings.bottomRightCornerSwipeGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.topLeftTriangleGestureAction)
    private var topLeftTriangleGestureAction = GlassToKeySettings.topLeftTriangleGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.topRightTriangleGestureAction)
    private var topRightTriangleGestureAction = GlassToKeySettings.topRightTriangleGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.bottomLeftTriangleGestureAction)
    private var bottomLeftTriangleGestureAction = GlassToKeySettings.bottomLeftTriangleGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.bottomRightTriangleGestureAction)
    private var bottomRightTriangleGestureAction = GlassToKeySettings.bottomRightTriangleGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.upperLeftCornerClickGestureAction)
    private var upperLeftCornerClickGestureAction = GlassToKeySettings.upperLeftCornerClickGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.upperRightCornerClickGestureAction)
    private var upperRightCornerClickGestureAction = GlassToKeySettings.upperRightCornerClickGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.lowerLeftCornerClickGestureAction)
    private var lowerLeftCornerClickGestureAction = GlassToKeySettings.lowerLeftCornerClickGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.lowerRightCornerClickGestureAction)
    private var lowerRightCornerClickGestureAction = GlassToKeySettings.lowerRightCornerClickGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.threeFingerClickGestureAction)
    private var threeFingerClickGestureAction = GlassToKeySettings.threeFingerClickGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.fourFingerClickGestureAction)
    private var fourFingerClickGestureAction = GlassToKeySettings.fourFingerClickGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.topLeftForceClickGestureAction)
    private var topLeftForceClickGestureAction = GlassToKeySettings.topLeftForceClickGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.topRightForceClickGestureAction)
    private var topRightForceClickGestureAction = GlassToKeySettings.topRightForceClickGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.bottomLeftForceClickGestureAction)
    private var bottomLeftForceClickGestureAction = GlassToKeySettings.bottomLeftForceClickGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.bottomRightForceClickGestureAction)
    private var bottomRightForceClickGestureAction = GlassToKeySettings.bottomRightForceClickGestureActionLabel
    @AppStorage(GlassToKeyDefaultsKeys.gestureRepeatCadenceMsById)
    private var storedGestureRepeatCadenceData = Data()
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
    fileprivate static let columnScalePercentRange: ClosedRange<Double> =
        (ColumnLayoutDefaults.scaleRange.lowerBound * 100.0)...(ColumnLayoutDefaults.scaleRange.upperBound * 100.0)
    fileprivate static let columnOffsetPercentRange: ClosedRange<Double> = ColumnLayoutDefaults.offsetPercentRange
    fileprivate static let columnSpacingPercentRange: ClosedRange<Double> = LayoutKeySpacingDefaults.percentRange
    fileprivate static let rotationDegreesRange: ClosedRange<Double> = ColumnLayoutDefaults.rotationDegreesRange
    fileprivate static let dragCancelDistanceRange: ClosedRange<Double> = 1.0...30.0
    fileprivate static let tapHoldDurationRange: ClosedRange<Double> = 0.0...500.0
    fileprivate static let forceClickRange: ClosedRange<Double> = 0.0...255.0
    fileprivate static let forceClickThresholdRange: ClosedRange<Double> = 130.0...500.0
    fileprivate static let twoFingerClickCadenceRange: ClosedRange<Double> = 100.0...600.0
    fileprivate static let intentMoveThresholdRange: ClosedRange<Double> = 0.5...10.0
    fileprivate static let intentVelocityThresholdRange: ClosedRange<Double> = 10.0...200.0
    fileprivate static let snapRadiusPercentRange: ClosedRange<Double> = 0.0...100.0
    private static let keyCornerRadius: CGFloat = 6.0
    private static let autoSplayTouchCount = 4
    fileprivate static let columnScalePercentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.minimum = NSNumber(value: ContentView.columnScalePercentRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.columnScalePercentRange.upperBound)
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
    fileprivate static let columnSpacingFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.minimum = NSNumber(value: ContentView.columnSpacingPercentRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.columnSpacingPercentRange.upperBound)
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

    private func normalizedGestureActionLabel(
        _ storedLabel: String,
        fallbackLabel: String
    ) -> String {
        resolvedGestureAction(storedLabel, fallbackLabel: fallbackLabel).pickerText
    }

    private func currentGestureActions() -> GestureActionSet {
        let resolvedThreeFingerSwipeLeft = systemThreeFingerDragEnabled
            ? KeyActionCatalog.noneAction
            : resolvedGestureAction(threeFingerSwipeLeftGestureAction, fallbackLabel: GlassToKeySettings.threeFingerSwipeLeftGestureActionLabel)
        let resolvedThreeFingerSwipeRight = systemThreeFingerDragEnabled
            ? KeyActionCatalog.noneAction
            : resolvedGestureAction(threeFingerSwipeRightGestureAction, fallbackLabel: GlassToKeySettings.threeFingerSwipeRightGestureActionLabel)
        let resolvedThreeFingerSwipeUp = systemThreeFingerDragEnabled
            ? KeyActionCatalog.noneAction
            : resolvedGestureAction(threeFingerSwipeUpGestureAction, fallbackLabel: GlassToKeySettings.threeFingerSwipeUpGestureActionLabel)
        let resolvedThreeFingerSwipeDown = systemThreeFingerDragEnabled
            ? KeyActionCatalog.noneAction
            : resolvedGestureAction(threeFingerSwipeDownGestureAction, fallbackLabel: GlassToKeySettings.threeFingerSwipeDownGestureActionLabel)
        return GestureActionSet(
            twoFingerTap: resolvedGestureAction(twoFingerTapGestureAction, fallbackLabel: GlassToKeySettings.twoFingerTapGestureActionLabel),
            threeFingerTap: resolvedGestureAction(threeFingerTapGestureAction, fallbackLabel: GlassToKeySettings.threeFingerTapGestureActionLabel),
            twoFingerHold: resolvedGestureAction(twoFingerHoldGestureAction, fallbackLabel: GlassToKeySettings.twoFingerHoldGestureActionLabel),
            threeFingerHold: resolvedGestureAction(threeFingerHoldGestureAction, fallbackLabel: GlassToKeySettings.threeFingerHoldGestureActionLabel),
            fourFingerHold: resolvedGestureAction(fourFingerHoldGestureAction, fallbackLabel: GlassToKeySettings.fourFingerHoldGestureActionLabel),
            outerCornersHold: resolvedGestureAction(outerCornersHoldGestureAction, fallbackLabel: GlassToKeySettings.outerCornersHoldGestureActionLabel),
            innerCornersHold: resolvedGestureAction(innerCornersHoldGestureAction, fallbackLabel: GlassToKeySettings.innerCornersHoldGestureActionLabel),
            leftEdgeUp: resolvedGestureAction(leftEdgeUpGestureAction, fallbackLabel: GlassToKeySettings.leftEdgeUpGestureActionLabel),
            leftEdgeDown: resolvedGestureAction(leftEdgeDownGestureAction, fallbackLabel: GlassToKeySettings.leftEdgeDownGestureActionLabel),
            rightEdgeUp: resolvedGestureAction(rightEdgeUpGestureAction, fallbackLabel: GlassToKeySettings.rightEdgeUpGestureActionLabel),
            rightEdgeDown: resolvedGestureAction(rightEdgeDownGestureAction, fallbackLabel: GlassToKeySettings.rightEdgeDownGestureActionLabel),
            topEdgeLeft: resolvedGestureAction(topEdgeLeftGestureAction, fallbackLabel: GlassToKeySettings.topEdgeLeftGestureActionLabel),
            topEdgeRight: resolvedGestureAction(topEdgeRightGestureAction, fallbackLabel: GlassToKeySettings.topEdgeRightGestureActionLabel),
            bottomEdgeLeft: resolvedGestureAction(bottomEdgeLeftGestureAction, fallbackLabel: GlassToKeySettings.bottomEdgeLeftGestureActionLabel),
            bottomEdgeRight: resolvedGestureAction(bottomEdgeRightGestureAction, fallbackLabel: GlassToKeySettings.bottomEdgeRightGestureActionLabel),
            threeFingerSwipeLeft: resolvedThreeFingerSwipeLeft,
            threeFingerSwipeRight: resolvedThreeFingerSwipeRight,
            threeFingerSwipeUp: resolvedThreeFingerSwipeUp,
            threeFingerSwipeDown: resolvedThreeFingerSwipeDown,
            fourFingerSwipeLeft: resolvedGestureAction(fourFingerSwipeLeftGestureAction, fallbackLabel: GlassToKeySettings.fourFingerSwipeLeftGestureActionLabel),
            fourFingerSwipeRight: resolvedGestureAction(fourFingerSwipeRightGestureAction, fallbackLabel: GlassToKeySettings.fourFingerSwipeRightGestureActionLabel),
            fourFingerSwipeUp: resolvedGestureAction(fourFingerSwipeUpGestureAction, fallbackLabel: GlassToKeySettings.fourFingerSwipeUpGestureActionLabel),
            fourFingerSwipeDown: resolvedGestureAction(fourFingerSwipeDownGestureAction, fallbackLabel: GlassToKeySettings.fourFingerSwipeDownGestureActionLabel),
            fiveFingerSwipeLeft: resolvedGestureAction(fiveFingerSwipeLeftGestureAction, fallbackLabel: GlassToKeySettings.fiveFingerSwipeLeftGestureActionLabel),
            fiveFingerSwipeRight: resolvedGestureAction(fiveFingerSwipeRightGestureAction, fallbackLabel: GlassToKeySettings.fiveFingerSwipeRightGestureActionLabel),
            fiveFingerSwipeUp: resolvedGestureAction(fiveFingerSwipeUpGestureAction, fallbackLabel: GlassToKeySettings.fiveFingerSwipeUpGestureActionLabel),
            fiveFingerSwipeDown: resolvedGestureAction(fiveFingerSwipeDownGestureAction, fallbackLabel: GlassToKeySettings.fiveFingerSwipeDownGestureActionLabel),
            topLeftCornerSwipe: resolvedGestureAction(topLeftCornerSwipeGestureAction, fallbackLabel: GlassToKeySettings.topLeftCornerSwipeGestureActionLabel),
            topRightCornerSwipe: resolvedGestureAction(topRightCornerSwipeGestureAction, fallbackLabel: GlassToKeySettings.topRightCornerSwipeGestureActionLabel),
            bottomLeftCornerSwipe: resolvedGestureAction(bottomLeftCornerSwipeGestureAction, fallbackLabel: GlassToKeySettings.bottomLeftCornerSwipeGestureActionLabel),
            bottomRightCornerSwipe: resolvedGestureAction(bottomRightCornerSwipeGestureAction, fallbackLabel: GlassToKeySettings.bottomRightCornerSwipeGestureActionLabel),
            topLeftTriangle: resolvedGestureAction(topLeftTriangleGestureAction, fallbackLabel: GlassToKeySettings.topLeftTriangleGestureActionLabel),
            topRightTriangle: resolvedGestureAction(topRightTriangleGestureAction, fallbackLabel: GlassToKeySettings.topRightTriangleGestureActionLabel),
            bottomLeftTriangle: resolvedGestureAction(bottomLeftTriangleGestureAction, fallbackLabel: GlassToKeySettings.bottomLeftTriangleGestureActionLabel),
            bottomRightTriangle: resolvedGestureAction(bottomRightTriangleGestureAction, fallbackLabel: GlassToKeySettings.bottomRightTriangleGestureActionLabel),
            upperLeftCornerClick: resolvedGestureAction(upperLeftCornerClickGestureAction, fallbackLabel: GlassToKeySettings.upperLeftCornerClickGestureActionLabel),
            upperRightCornerClick: resolvedGestureAction(upperRightCornerClickGestureAction, fallbackLabel: GlassToKeySettings.upperRightCornerClickGestureActionLabel),
            lowerLeftCornerClick: resolvedGestureAction(lowerLeftCornerClickGestureAction, fallbackLabel: GlassToKeySettings.lowerLeftCornerClickGestureActionLabel),
            lowerRightCornerClick: resolvedGestureAction(lowerRightCornerClickGestureAction, fallbackLabel: GlassToKeySettings.lowerRightCornerClickGestureActionLabel),
            threeFingerClick: resolvedGestureAction(threeFingerClickGestureAction, fallbackLabel: GlassToKeySettings.threeFingerClickGestureActionLabel),
            fourFingerClick: resolvedGestureAction(fourFingerClickGestureAction, fallbackLabel: GlassToKeySettings.fourFingerClickGestureActionLabel),
            topLeftForceClick: resolvedGestureAction(topLeftForceClickGestureAction, fallbackLabel: GlassToKeySettings.topLeftForceClickGestureActionLabel),
            topRightForceClick: resolvedGestureAction(topRightForceClickGestureAction, fallbackLabel: GlassToKeySettings.topRightForceClickGestureActionLabel),
            bottomLeftForceClick: resolvedGestureAction(bottomLeftForceClickGestureAction, fallbackLabel: GlassToKeySettings.bottomLeftForceClickGestureActionLabel),
            bottomRightForceClick: resolvedGestureAction(bottomRightForceClickGestureAction, fallbackLabel: GlassToKeySettings.bottomRightForceClickGestureActionLabel)
        )
    }

    private var gestureSettingsSignature: String {
        [
            twoFingerTapGestureAction,
            threeFingerTapGestureAction,
            twoFingerHoldGestureAction,
            threeFingerHoldGestureAction,
            fourFingerHoldGestureAction,
            outerCornersHoldGestureAction,
            innerCornersHoldGestureAction,
            leftEdgeUpGestureAction,
            leftEdgeDownGestureAction,
            rightEdgeUpGestureAction,
            rightEdgeDownGestureAction,
            topEdgeLeftGestureAction,
            topEdgeRightGestureAction,
            bottomEdgeLeftGestureAction,
            bottomEdgeRightGestureAction,
            threeFingerSwipeLeftGestureAction,
            threeFingerSwipeRightGestureAction,
            threeFingerSwipeUpGestureAction,
            threeFingerSwipeDownGestureAction,
            fourFingerSwipeLeftGestureAction,
            fourFingerSwipeRightGestureAction,
            fourFingerSwipeUpGestureAction,
            fourFingerSwipeDownGestureAction,
            fiveFingerSwipeLeftGestureAction,
            fiveFingerSwipeRightGestureAction,
            fiveFingerSwipeUpGestureAction,
            fiveFingerSwipeDownGestureAction,
            topLeftCornerSwipeGestureAction,
            topRightCornerSwipeGestureAction,
            bottomLeftCornerSwipeGestureAction,
            bottomRightCornerSwipeGestureAction,
            topLeftTriangleGestureAction,
            topRightTriangleGestureAction,
            bottomLeftTriangleGestureAction,
            bottomRightTriangleGestureAction,
            upperLeftCornerClickGestureAction,
            upperRightCornerClickGestureAction,
            lowerLeftCornerClickGestureAction,
            lowerRightCornerClickGestureAction,
            threeFingerClickGestureAction,
            fourFingerClickGestureAction,
            topLeftForceClickGestureAction,
            topRightForceClickGestureAction,
            bottomLeftForceClickGestureAction,
            bottomRightForceClickGestureAction,
            systemThreeFingerDragEnabled ? "1" : "0"
        ].joined(separator: "\u{1F}")
    }

    init(viewModel: ContentViewModel = ContentViewModel(), nativeTakeover: NativeTrackpadTakeover = NativeTrackpadTakeover()) {
        self.nativeTakeover = nativeTakeover
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
        let initialKeySpacingPercent = LayoutKeySpacingDefaults.defaultPercent
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
            keySpacingPercent: initialKeySpacingPercent,
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
            columnSettings: initialColumnSettings,
            keySpacingPercent: initialKeySpacingPercent
        )
        _columnSettings = State(initialValue: initialColumnSettings)
        _keySpacingPercent = State(initialValue: initialKeySpacingPercent)
        _leftLayout = State(initialValue: initialLeftLayout)
        _rightLayout = State(initialValue: initialRightLayout)
    }

    var body: some View {
        lifecycleContent(styledMainLayout)
    }

    private var styledMainLayout: some View {
        mainLayout
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
                refreshActionGroupCaches()
                viewModel.gestures.refreshPermission()
                viewModel.setAutoResyncEnabled(storedAutoResyncMissingTrackpads)

            }
            .onDisappear {
                persistConfig()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                viewModel.gestures.refreshPermission()
            }
            .onChange(of: columnSettings) { newValue in
                normalizeEditColumnIndex(for: newValue.count)
                applyColumnSettings(newValue)
                refreshColumnInspectorSelection()
            }
            .onChange(of: keySpacingPercent) { newValue in
                let normalized = LayoutKeySpacingDefaults.normalized(newValue)
                if abs(normalized - newValue) > 0.000_01 {
                    keySpacingPercent = normalized
                    return
                }
                rebuildLayouts()
            }
            .onChange(of: customButtons) { newValue in
                saveCustomButtons(newValue)
                viewModel.updateCustomButtons(newValue)
                refreshButtonInspectorSelection()
                refreshActionGroupCaches()
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
                refreshActionGroupCaches()
            }
            .onChange(of: keyMappingsByLayout) { _ in
                refreshActionGroupCaches()
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
            .onChange(of: forceClickThresholdSetting) { newValue in
                let clamped = min(max(newValue, Self.forceClickThresholdRange.lowerBound), Self.forceClickThresholdRange.upperBound)
                if clamped != newValue {
                    forceClickThresholdSetting = clamped
                    return
                }
                viewModel.updateForceClickThreshold(clamped)
            }
            .onChange(of: hapticStrengthSetting) { newValue in
                viewModel.updateHapticStrength(newValue / 100.0)
            }
            .onChange(of: intentMoveThresholdMmSetting) { newValue in
                viewModel.updateIntentMoveThresholdMm(newValue)
            }
            .onChange(of: intentVelocityThresholdMmPerSecSetting) { newValue in
                viewModel.updateIntentVelocityThresholdMmPerSec(newValue)
            }

            .onChange(of: tapClickCadenceMsSetting) { newValue in
                viewModel.updateTapClickCadenceMs(newValue)
            }
            .onChange(of: snapRadiusPercentSetting) { newValue in
                viewModel.updateSnapRadiusPercent(newValue)
            }
            .onChange(of: autocorrectEnabled) { newValue in
                AutocorrectEngine.shared.setEnabled(newValue)
            }

            .onChange(of: holdRepeatEnabled) { newValue in
                viewModel.updateHoldRepeatEnabled(newValue)
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
            .onChange(of: storedCustomButtonsData) { _ in
                refreshActionGroupCaches()
            }
            .onChange(of: storedShortcutActionsData) { _ in
                normalizeStoredShortcutActions()
                refreshActionGroupCaches()
            }
            .onChange(of: storedAutoResyncMissingTrackpads) { newValue in
                viewModel.setAutoResyncEnabled(newValue)
            }
            .onReceive(viewModel.$replayTimelineState) { state in
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
        VStack(spacing:0) {
            HStack {
                Text("AppleMagicTouchstream").font(.headline)
                Spacer()
                EqualWidthInspectorPicker(selection:$inspectorTab).frame(width:260)
            }
            .padding(.horizontal,20).padding(.vertical,12)
            Divider()
            devicesSectionView.padding(.horizontal,20).padding(.vertical,12)
            Divider()
            if inspectorTab == "Gestures" {
                GestureInspectorPanel(controller:viewModel.gestures,takeover:nativeTakeover)
            } else {
                GeometryReader { viewport in
                    let width = WorkspaceColumnSizing.menu(menuColumnWidth,available:viewport.size.width,reserved:0)
                    HStack(alignment:.top,spacing:0) {
                        ScrollView([.horizontal,.vertical]) {
                            VStack(alignment:.leading,spacing:16) {
                                if let state = viewModel.replayTimelineState { replayTimelineView(state) }
                                trackpadSectionView
                            }
                            .frame(width:trackpadSize.width * 2 + 40,alignment:.leading)
                            .padding(20)
                            .frame(minWidth:max(0,viewport.size.width-width-WorkspaceColumnSizing.dividerWidth),minHeight:viewport.size.height,alignment:.topLeading)
                        }
                        WorkspaceColumnDivider(width:Binding(get:{width},set:{menuColumnWidth = $0}),
                            minimum:WorkspaceColumnSizing.minimumMenu,
                            maximum:WorkspaceColumnSizing.menuMaximum(available:viewport.size.width,reserved:0),
                            trailingColumn:true,label:"Keyboard settings width")
                        rightSidebarView
                            .environment(\.compactAssignmentMenu, width < WorkspaceColumnSizing.compactMenuBreakpoint)
                            .padding(16).frame(width:width)
                    }
                }
            }
        }
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
                changeTrackpadSelection(left: device, right: viewModel.rightDevice)
            },
            onSelectRight: { device in
                changeTrackpadSelection(left: viewModel.leftDevice, right: device)
            },
            onRefresh: {
                Task { @MainActor in
                    guard await nativeTakeover.suspend("refresh") else {
                        await nativeTakeover.resume("refresh")
                        return
                    }
                    viewModel.refreshDevicesAndListeners()
                    await nativeTakeover.updateSelection(deviceIDs: [viewModel.leftDevice, viewModel.rightDevice].compactMap { $0?.deviceIDNumeric })
                    await nativeTakeover.resume("refresh")
                }
            },
            nativeTakeover: nativeTakeover,
            replayActive: viewModel.replayTimelineState != nil
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func changeTrackpadSelection(left: OMSDeviceInfo?, right: OMSDeviceInfo?) {
        guard !nativeTakeover.isReleasing, viewModel.replayTimelineState == nil else { return }
        Task { @MainActor in
            await nativeTakeover.updateSelection(deviceIDs: [left, right].compactMap { $0?.deviceIDNumeric }) {
                viewModel.commitTrackpadSelection(left: left, right: right)
                storedLeftDeviceID = left?.deviceID ?? ""
                storedRightDeviceID = right?.deviceID ?? ""
            }
        }
    }

    private var trackpadSectionView: some View {
            TrackpadSectionView(
                viewModel: viewModel,
                showTouchStreamReference: layoutOption == .touchstream,
                trackpadSize: trackpadSize,
                leftLayout: leftLayout,
                rightLayout: rightLayout,
                leftBaseLabels: leftGridLabels,
                rightBaseLabels: rightGridLabels,
                leftGridLabelInfo: leftGridLabelInfo,
                rightGridLabelInfo: rightGridLabelInfo,
                customButtons: customButtons,
                lastHitLeft: viewModel.debugLastHitLeft,
                lastHitRight: viewModel.debugLastHitRight,
                selectedButtonID: $selectedButtonID,
                selectedGridKey: $selectedGridKey,
                onSelectionInteraction: {
                    inspectorSelectionRevision += 1
                },
                testText: $testText,
                autocorrectCurrentBufferText: $autocorrectCurrentBufferText,
                autocorrectLastCorrectedText: $autocorrectLastCorrectedText
            )
    }

    private var rightSidebarView: some View {
        RightSidebarView(
            onImportKeymap: importKeymap,
            onExportKeymap: exportKeymap,
            layoutSelection: layoutSelectionBinding,
            layoutOption: layoutOption,
            columnSettings: columnSettings,
            columnSelection: columnInspectorSelection,
            columnSpacingPercent: $keySpacingPercent,
            primaryActionGroups: primaryActionGroups,
            holdActionGroups: holdActionGroups,
            gestureActionGroups: gestureActionGroups,
            editColumnIndex: $editColumnIndex,
            buttonSelection: buttonInspectorSelection,
            keySelection: keyInspectorSelection,
            selectionRevision: inspectorSelectionRevision,
            layerSelection: layerSelectionBinding,
            tapHoldDurationMs: $tapHoldDurationMs,
            dragCancelDistanceSetting: $dragCancelDistanceSetting,
            forceClickMinSetting: $forceClickMinSetting,
            forceClickCapSetting: $forceClickCapSetting,
            forceClickThresholdSetting: $forceClickThresholdSetting,
            hapticStrengthSetting: $hapticStrengthSetting,
            intentMoveThresholdMmSetting: $intentMoveThresholdMmSetting,
            intentVelocityThresholdMmPerSecSetting: $intentVelocityThresholdMmPerSecSetting,
            autocorrectEnabled: $autocorrectEnabled,
            tapClickCadenceMsSetting: $tapClickCadenceMsSetting,
            snapRadiusPercentSetting: $snapRadiusPercentSetting,
            keyboardModeEnabled: $keyboardModeEnabled,
            holdRepeatEnabled: $holdRepeatEnabled,
            runAtStartupEnabled: $runAtStartupEnabled,
            twoFingerTapGestureAction: $twoFingerTapGestureAction,
            threeFingerTapGestureAction: $threeFingerTapGestureAction,
            twoFingerHoldGestureAction: $twoFingerHoldGestureAction,
            threeFingerHoldGestureAction: $threeFingerHoldGestureAction,
            fourFingerHoldGestureAction: $fourFingerHoldGestureAction,
            outerCornersHoldGestureAction: $outerCornersHoldGestureAction,
            innerCornersHoldGestureAction: $innerCornersHoldGestureAction,
            leftEdgeUpGestureAction: $leftEdgeUpGestureAction,
            leftEdgeDownGestureAction: $leftEdgeDownGestureAction,
            rightEdgeUpGestureAction: $rightEdgeUpGestureAction,
            rightEdgeDownGestureAction: $rightEdgeDownGestureAction,
            topEdgeLeftGestureAction: $topEdgeLeftGestureAction,
            topEdgeRightGestureAction: $topEdgeRightGestureAction,
            bottomEdgeLeftGestureAction: $bottomEdgeLeftGestureAction,
            bottomEdgeRightGestureAction: $bottomEdgeRightGestureAction,
            threeFingerSwipeLeftGestureAction: $threeFingerSwipeLeftGestureAction,
            threeFingerSwipeRightGestureAction: $threeFingerSwipeRightGestureAction,
            threeFingerSwipeUpGestureAction: $threeFingerSwipeUpGestureAction,
            threeFingerSwipeDownGestureAction: $threeFingerSwipeDownGestureAction,
            fourFingerSwipeLeftGestureAction: $fourFingerSwipeLeftGestureAction,
            fourFingerSwipeRightGestureAction: $fourFingerSwipeRightGestureAction,
            fourFingerSwipeUpGestureAction: $fourFingerSwipeUpGestureAction,
            fourFingerSwipeDownGestureAction: $fourFingerSwipeDownGestureAction,
            fiveFingerSwipeLeftGestureAction: $fiveFingerSwipeLeftGestureAction,
            fiveFingerSwipeRightGestureAction: $fiveFingerSwipeRightGestureAction,
            fiveFingerSwipeUpGestureAction: $fiveFingerSwipeUpGestureAction,
            fiveFingerSwipeDownGestureAction: $fiveFingerSwipeDownGestureAction,
            topLeftCornerSwipeGestureAction: $topLeftCornerSwipeGestureAction,
            topRightCornerSwipeGestureAction: $topRightCornerSwipeGestureAction,
            bottomLeftCornerSwipeGestureAction: $bottomLeftCornerSwipeGestureAction,
            bottomRightCornerSwipeGestureAction: $bottomRightCornerSwipeGestureAction,
            topLeftTriangleGestureAction: $topLeftTriangleGestureAction,
            topRightTriangleGestureAction: $topRightTriangleGestureAction,
            bottomLeftTriangleGestureAction: $bottomLeftTriangleGestureAction,
            bottomRightTriangleGestureAction: $bottomRightTriangleGestureAction,
            upperLeftCornerClickGestureAction: $upperLeftCornerClickGestureAction,
            upperRightCornerClickGestureAction: $upperRightCornerClickGestureAction,
            lowerLeftCornerClickGestureAction: $lowerLeftCornerClickGestureAction,
            lowerRightCornerClickGestureAction: $lowerRightCornerClickGestureAction,
            threeFingerClickGestureAction: $threeFingerClickGestureAction,
            fourFingerClickGestureAction: $fourFingerClickGestureAction,
            topLeftForceClickGestureAction: $topLeftForceClickGestureAction,
            topRightForceClickGestureAction: $topRightForceClickGestureAction,
            bottomLeftForceClickGestureAction: $bottomLeftForceClickGestureAction,
            bottomRightForceClickGestureAction: $bottomRightForceClickGestureAction,
            gestureRepeatCadenceData: $storedGestureRepeatCadenceData,
            autoResyncEnabled: $storedAutoResyncMissingTrackpads,
            systemThreeFingerDragEnabled: $systemThreeFingerDragEnabled,
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
            onSaveShortcutLibraryAction: saveShortcutLibraryAction,
            onRestoreDefaults: restoreTypingTuningDefaults,
            onApplyMxSpacing: {
                applyKeySizePreset(
                    targetKeyWidthMm: LayoutKeySizePresetTuning.mxKeyWidthMm,
                    targetKeyHeightMm: LayoutKeySizePresetTuning.mxKeyHeightMm
                )
            },
            onApplyChocSpacing: {
                applyKeySizePreset(
                    targetKeyWidthMm: Self.baseKeyWidthMM,
                    targetKeyHeightMm: Self.baseKeyHeightMM
                )
            },
            onAutoSplayColumns: applyAutoSplay,
            onEvenSpaceColumns: applyEvenColumnSpacing
        )
    }

    private func refreshActionGroupCaches() {
        primaryActionGroups = mergedActionGroups(baseGroups: KeyActionCatalog.primaryActionGroups)
        holdActionGroups = mergedActionGroups(baseGroups: KeyActionCatalog.holdActionGroups)
        gestureActionGroups = mergedActionGroups(baseGroups: KeyActionCatalog.primaryActionGroups)
    }

    private func mergedActionGroups(
        baseGroups: [KeyActionCatalog.ActionGroup]
    ) -> [KeyActionCatalog.ActionGroup] {
        let shortcutActions = shortcutLibraryActions()
        let customActions = collectedCustomActions(
            excluding: baseGroups,
            excludingActions: Set(shortcutActions)
        )

        var groups = baseGroups
        if !shortcutActions.isEmpty {
            groups.append(KeyActionCatalog.ActionGroup(title: "Shortcuts", actions: shortcutActions))
        }
        if !customActions.isEmpty {
            groups.append(
                KeyActionCatalog.ActionGroup(
                    title: "Saved Custom Actions",
                    actions: customActions
                )
            )
        }
        return groups
    }

    private func collectedCustomActions(
        excluding groups: [KeyActionCatalog.ActionGroup],
        excludingActions: Set<KeyAction> = []
    ) -> [KeyAction] {
        var actions = Set<KeyAction>()

        func add(_ action: KeyAction?) {
            guard let action, action.kind != .none else { return }
            guard !excludingActions.contains(action) else { return }
            let existsInBaseGroups = groups.contains { group in
                group.actions.contains(action)
            }
            guard !existsInBaseGroups else { return }
            actions.insert(action)
        }

        for layeredMappings in keyMappingsByLayout.values {
            for mappings in layeredMappings.values {
                for mapping in mappings.values {
                    add(mapping.primary)
                    add(mapping.hold)
                }
            }
        }

        for mappings in keyMappingsByLayer.values {
            for mapping in mappings.values {
                add(mapping.primary)
                add(mapping.hold)
            }
        }

        if let storedButtonsByLayout = LayoutCustomButtonStorage.decode(from: storedCustomButtonsData) {
            for layeredButtons in storedButtonsByLayout.values {
                for buttons in layeredButtons.values {
                    for button in buttons {
                        add(button.action)
                        add(button.hold)
                    }
                }
            }
        }

        for button in customButtons {
            add(button.action)
            add(button.hold)
        }

        add(KeyActionCatalog.action(for: twoFingerTapGestureAction))
        add(KeyActionCatalog.action(for: threeFingerTapGestureAction))
        add(KeyActionCatalog.action(for: twoFingerHoldGestureAction))
        add(KeyActionCatalog.action(for: threeFingerHoldGestureAction))
        add(KeyActionCatalog.action(for: fourFingerHoldGestureAction))
        add(KeyActionCatalog.action(for: outerCornersHoldGestureAction))
        add(KeyActionCatalog.action(for: innerCornersHoldGestureAction))
        add(KeyActionCatalog.action(for: leftEdgeUpGestureAction))
        add(KeyActionCatalog.action(for: leftEdgeDownGestureAction))
        add(KeyActionCatalog.action(for: rightEdgeUpGestureAction))
        add(KeyActionCatalog.action(for: rightEdgeDownGestureAction))
        add(KeyActionCatalog.action(for: topEdgeLeftGestureAction))
        add(KeyActionCatalog.action(for: topEdgeRightGestureAction))
        add(KeyActionCatalog.action(for: bottomEdgeLeftGestureAction))
        add(KeyActionCatalog.action(for: bottomEdgeRightGestureAction))
        add(KeyActionCatalog.action(for: threeFingerSwipeLeftGestureAction))
        add(KeyActionCatalog.action(for: threeFingerSwipeRightGestureAction))
        add(KeyActionCatalog.action(for: threeFingerSwipeUpGestureAction))
        add(KeyActionCatalog.action(for: threeFingerSwipeDownGestureAction))
        add(KeyActionCatalog.action(for: fourFingerSwipeLeftGestureAction))
        add(KeyActionCatalog.action(for: fourFingerSwipeRightGestureAction))
        add(KeyActionCatalog.action(for: fourFingerSwipeUpGestureAction))
        add(KeyActionCatalog.action(for: fourFingerSwipeDownGestureAction))
        add(KeyActionCatalog.action(for: fiveFingerSwipeLeftGestureAction))
        add(KeyActionCatalog.action(for: fiveFingerSwipeRightGestureAction))
        add(KeyActionCatalog.action(for: fiveFingerSwipeUpGestureAction))
        add(KeyActionCatalog.action(for: fiveFingerSwipeDownGestureAction))
        add(KeyActionCatalog.action(for: topLeftCornerSwipeGestureAction))
        add(KeyActionCatalog.action(for: topRightCornerSwipeGestureAction))
        add(KeyActionCatalog.action(for: bottomLeftCornerSwipeGestureAction))
        add(KeyActionCatalog.action(for: bottomRightCornerSwipeGestureAction))
        add(KeyActionCatalog.action(for: topLeftTriangleGestureAction))
        add(KeyActionCatalog.action(for: topRightTriangleGestureAction))
        add(KeyActionCatalog.action(for: bottomLeftTriangleGestureAction))
        add(KeyActionCatalog.action(for: bottomRightTriangleGestureAction))
        add(KeyActionCatalog.action(for: upperLeftCornerClickGestureAction))
        add(KeyActionCatalog.action(for: upperRightCornerClickGestureAction))
        add(KeyActionCatalog.action(for: lowerLeftCornerClickGestureAction))
        add(KeyActionCatalog.action(for: lowerRightCornerClickGestureAction))
        add(KeyActionCatalog.action(for: threeFingerClickGestureAction))
        add(KeyActionCatalog.action(for: fourFingerClickGestureAction))
        add(KeyActionCatalog.action(for: topLeftForceClickGestureAction))
        add(KeyActionCatalog.action(for: topRightForceClickGestureAction))
        add(KeyActionCatalog.action(for: bottomLeftForceClickGestureAction))
        add(KeyActionCatalog.action(for: bottomRightForceClickGestureAction))

        return actions.sorted {
            $0.pickerText.localizedCaseInsensitiveCompare($1.pickerText) == .orderedAscending
        }
    }

    private func shortcutLibraryActions() -> [KeyAction] {
        ShortcutActionLibraryStorage.decode(from: storedShortcutActionsData)?
            .compactMap(KeyActionCatalog.action(for:))
            ?? []
    }

    private struct TrackpadSectionView: View {
        @ObservedObject var viewModel: ContentViewModel
        let showTouchStreamReference: Bool
        let trackpadSize: CGSize
        let leftLayout: ContentViewModel.Layout
        let rightLayout: ContentViewModel.Layout
        let leftBaseLabels: [[String]]
        let rightBaseLabels: [[String]]
        let leftGridLabelInfo: [[GridLabel]]
        let rightGridLabelInfo: [[GridLabel]]
        let customButtons: [CustomButton]
        let lastHitLeft: ContentViewModel.DebugHit?
        let lastHitRight: ContentViewModel.DebugHit?
        @Binding var selectedButtonID: UUID?
        @Binding var selectedGridKey: SelectedGridKey?
        let onSelectionInteraction: () -> Void
        @Binding var testText: String
        @Binding var autocorrectCurrentBufferText: String
        @Binding var autocorrectLastCorrectedText: String

        var body: some View {
            ZStack {
                VStack(alignment: .leading, spacing: 12) {
                        TrackpadDeckView(
                            viewModel: viewModel,
                            showTouchStreamReference: showTouchStreamReference,
                            trackpadSize: trackpadSize,
                            leftLayout: leftLayout,
                            rightLayout: rightLayout,
                            leftBaseLabels: leftBaseLabels,
                            rightBaseLabels: rightBaseLabels,
                            leftGridLabelInfo: leftGridLabelInfo,
                            rightGridLabelInfo: rightGridLabelInfo,
                            customButtons: customButtons,
                            lastHitLeft: lastHitLeft,
                            lastHitRight: lastHitRight,
                            selectedButtonID: $selectedButtonID,
                            selectedGridKey: $selectedGridKey,
                            onSelectionInteraction: onSelectionInteraction
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

                Button(action: clearSelection) {
                    EmptyView()
                }
                .frame(width: 0, height: 0)
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.borderless)
                .disabled(selectedButtonID == nil && selectedGridKey == nil)
            }
        }

        private func clearSelection() {
            selectedGridKey = nil
            selectedButtonID = nil
        }
    }

    private struct RightSidebarView: View {
        @Environment(\.compactAssignmentMenu) private var compact
        let onImportKeymap: () -> Void
        let onExportKeymap: () -> Void
        let layoutSelection: Binding<TrackpadLayoutPreset>
        let layoutOption: TrackpadLayoutPreset
        let columnSettings: [ColumnLayoutSettings]
        let columnSelection: ColumnInspectorSelection?
        @Binding var columnSpacingPercent: Double
        let primaryActionGroups: [KeyActionCatalog.ActionGroup]
        let holdActionGroups: [KeyActionCatalog.ActionGroup]
        let gestureActionGroups: [KeyActionCatalog.ActionGroup]
        @Binding var editColumnIndex: Int
        let buttonSelection: ButtonInspectorSelection?
        let keySelection: KeyInspectorSelection?
        let selectionRevision: Int
        let layerSelection: Binding<Int>
        @Binding var tapHoldDurationMs: Double
        @Binding var dragCancelDistanceSetting: Double
        @Binding var forceClickMinSetting: Double
        @Binding var forceClickCapSetting: Double
        @Binding var forceClickThresholdSetting: Double
        @Binding var hapticStrengthSetting: Double
        @Binding var intentMoveThresholdMmSetting: Double
        @Binding var intentVelocityThresholdMmPerSecSetting: Double
        @Binding var autocorrectEnabled: Bool
        @Binding var tapClickCadenceMsSetting: Double
        @Binding var snapRadiusPercentSetting: Double
        @Binding var keyboardModeEnabled: Bool
        @Binding var holdRepeatEnabled: Bool
        @Binding var runAtStartupEnabled: Bool
        @Binding var twoFingerTapGestureAction: String
        @Binding var threeFingerTapGestureAction: String
        @Binding var twoFingerHoldGestureAction: String
        @Binding var threeFingerHoldGestureAction: String
        @Binding var fourFingerHoldGestureAction: String
        @Binding var outerCornersHoldGestureAction: String
        @Binding var innerCornersHoldGestureAction: String
        @Binding var leftEdgeUpGestureAction: String
        @Binding var leftEdgeDownGestureAction: String
        @Binding var rightEdgeUpGestureAction: String
        @Binding var rightEdgeDownGestureAction: String
        @Binding var topEdgeLeftGestureAction: String
        @Binding var topEdgeRightGestureAction: String
        @Binding var bottomEdgeLeftGestureAction: String
        @Binding var bottomEdgeRightGestureAction: String
        @Binding var threeFingerSwipeLeftGestureAction: String
        @Binding var threeFingerSwipeRightGestureAction: String
        @Binding var threeFingerSwipeUpGestureAction: String
        @Binding var threeFingerSwipeDownGestureAction: String
        @Binding var fourFingerSwipeLeftGestureAction: String
        @Binding var fourFingerSwipeRightGestureAction: String
        @Binding var fourFingerSwipeUpGestureAction: String
        @Binding var fourFingerSwipeDownGestureAction: String
        @Binding var fiveFingerSwipeLeftGestureAction: String
        @Binding var fiveFingerSwipeRightGestureAction: String
        @Binding var fiveFingerSwipeUpGestureAction: String
        @Binding var fiveFingerSwipeDownGestureAction: String
        @Binding var topLeftCornerSwipeGestureAction: String
        @Binding var topRightCornerSwipeGestureAction: String
        @Binding var bottomLeftCornerSwipeGestureAction: String
        @Binding var bottomRightCornerSwipeGestureAction: String
        @Binding var topLeftTriangleGestureAction: String
        @Binding var topRightTriangleGestureAction: String
        @Binding var bottomLeftTriangleGestureAction: String
        @Binding var bottomRightTriangleGestureAction: String
        @Binding var upperLeftCornerClickGestureAction: String
        @Binding var upperRightCornerClickGestureAction: String
        @Binding var lowerLeftCornerClickGestureAction: String
        @Binding var lowerRightCornerClickGestureAction: String
        @Binding var threeFingerClickGestureAction: String
        @Binding var fourFingerClickGestureAction: String
        @Binding var topLeftForceClickGestureAction: String
        @Binding var topRightForceClickGestureAction: String
        @Binding var bottomLeftForceClickGestureAction: String
        @Binding var bottomRightForceClickGestureAction: String
        @Binding var gestureRepeatCadenceData: Data
        @Binding var autoResyncEnabled: Bool
        @Binding var systemThreeFingerDragEnabled: Bool
        @State private var modeTogglesExpanded = true
        @State private var typingTuningExpanded = false
        @State private var gestureTuningExpanded = false
        @State private var columnTuningExpanded = false
        @State private var keymapTuningExpanded = false
        let onAddCustomButton: (TrackpadSide) -> Void
        let onRemoveCustomButton: (UUID) -> Void
        let onClearTouchState: () -> Void
        let onUpdateColumn: (Int, (inout ColumnLayoutSettings) -> Void) -> Void
        let onUpdateButton: (UUID, (inout CustomButton) -> Void) -> Void
        let onUpdateKeyMapping: (SelectedGridKey, (inout KeyMapping) -> Void) -> Void
        let keyRotationDegrees: (SelectedGridKey) -> Double
        let onUpdateKeyRotation: (SelectedGridKey, Double) -> Void
        let onSaveShortcutLibraryAction: (KeyAction) -> Void
        let onRestoreDefaults: () -> Void
        let onApplyMxSpacing: () -> Void
        let onApplyChocSpacing: () -> Void
        let onAutoSplayColumns: () -> Void
        let onEvenSpaceColumns: () -> Void

        var body: some View {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    EqualSplitFormRow {
                        Text("Layout")
                    } field: {
                        Picker("", selection: layoutSelection) {
                            ForEach(TrackpadLayoutPreset.selectableCases.filter { $0 != .mobile && $0 != .mobileOrtho12x4 }) { preset in
                                Text(preset.displayName).tag(preset)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.primary.opacity(0.05))
                    )

                    CollapsibleSection(
                        isExpanded: $columnTuningExpanded
                    ) {
                        ColumnTuningSectionView(
                            layoutOption: layoutOption,
                            columnSettings: columnSettings,
                            selection: columnSelection,
                            columnSpacingPercent: $columnSpacingPercent,
                            editColumnIndex: $editColumnIndex,
                            onUpdateColumn: onUpdateColumn,
                            onApplyMxSpacing: onApplyMxSpacing,
                            onApplyChocSpacing: onApplyChocSpacing,
                            onAutoSplay: onAutoSplayColumns,
                            onEvenSpacing: onEvenSpaceColumns
                        )
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

                    CollapsibleSection(
                        isExpanded: $keymapTuningExpanded
                    ) {
                        ButtonTuningSectionView(
                            buttonSelection: buttonSelection,
                            keySelection: keySelection,
                            selectionRevision: selectionRevision,
                            primaryActionGroups: primaryActionGroups,
                            holdActionGroups: holdActionGroups,
                            layerSelection: layerSelection,
                            onAddCustomButton: onAddCustomButton,
                            onRemoveCustomButton: onRemoveCustomButton,
                            onClearTouchState: onClearTouchState,
                            onUpdateButton: onUpdateButton,
                            onUpdateKeyMapping: onUpdateKeyMapping,
                            keyRotationDegrees: keyRotationDegrees,
                            onUpdateKeyRotation: onUpdateKeyRotation,
                            onSaveShortcutLibraryAction: onSaveShortcutLibraryAction
                        )
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

                    CollapsibleSection(
                        isExpanded: $typingTuningExpanded
                    ) {
                        TypingTuningSectionView(
                            tapHoldDurationMs: $tapHoldDurationMs,
                            dragCancelDistanceSetting: $dragCancelDistanceSetting,
                            forceClickMinSetting: $forceClickMinSetting,
                            forceClickCapSetting: $forceClickCapSetting,
                            hapticStrengthSetting: $hapticStrengthSetting,
                            intentMoveThresholdMmSetting: $intentMoveThresholdMmSetting,
                            intentVelocityThresholdMmPerSecSetting: $intentVelocityThresholdMmPerSecSetting,
                            tapClickCadenceMsSetting: $tapClickCadenceMsSetting,
                            onRestoreDefaults: onRestoreDefaults
                        )
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

                    CollapsibleSection(
                        isExpanded: $modeTogglesExpanded
                    ) {
                        ModeTogglesSectionView(
                            autocorrectEnabled: $autocorrectEnabled,
                            snapRadiusPercentSetting: $snapRadiusPercentSetting,
                            keyboardModeEnabled: $keyboardModeEnabled,
                            holdRepeatEnabled: $holdRepeatEnabled,
                            runAtStartupEnabled: $runAtStartupEnabled,
                            autoResyncEnabled: $autoResyncEnabled,
                            systemThreeFingerDragEnabled: $systemThreeFingerDragEnabled
                        )
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
                    (compact ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))) {
                        Button(action: onImportKeymap) {
                            Text("Import Settings").frame(maxWidth: .infinity)
                        }
                        Button(action: onExportKeymap) {
                            Text("Export Settings").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .overlay(alignment: .top) {
                    VerticalScrollViewConfigurator()
                        .frame(width: 0, height: 0)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: keySelection?.key.storageKey) { newValue in
                guard newValue != nil else { return }
                keymapTuningExpanded = true
            }
        }
    }

    private struct VerticalScrollViewConfigurator: NSViewRepresentable {
        func makeNSView(context: Context) -> ScrollViewConfiguratorNSView {
            ScrollViewConfiguratorNSView(frame: .zero)
        }

        func updateNSView(_ nsView: ScrollViewConfiguratorNSView, context: Context) {
            nsView.refreshScrollViewConfiguration()
        }
    }

    private final class ScrollViewConfiguratorNSView: NSView {
        private var documentFrameObserver: NSObjectProtocol?
        private var clipBoundsObserver: NSObjectProtocol?
        private weak var observedScrollView: NSScrollView?

        override func viewWillMove(toSuperview newSuperview: NSView?) {
            if newSuperview == nil {
                removeObservers()
                observedScrollView = nil
            }
            super.viewWillMove(toSuperview: newSuperview)
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            refreshScrollViewConfiguration()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            refreshScrollViewConfiguration()
        }

        override func layout() {
            super.layout()
            refreshScrollViewConfiguration()
        }

        func refreshScrollViewConfiguration() {
            guard let scrollView = enclosingScrollView else {
                removeObservers()
                observedScrollView = nil
                return
            }

            if observedScrollView !== scrollView {
                observeScrollView(scrollView)
            }

            let documentHeight = scrollView.documentView?.frame.height ?? 0
            let viewportHeight = scrollView.contentView.bounds.height
            let hasVerticalOverflow = documentHeight > viewportHeight + 1

            scrollView.hasVerticalScroller = true
            scrollView.scrollerStyle = .legacy
            scrollView.autohidesScrollers = false
            scrollView.verticalScroller?.isHidden = !hasVerticalOverflow
            scrollView.drawsBackground = false
        }

        private func observeScrollView(_ scrollView: NSScrollView) {
            removeObservers()
            observedScrollView = scrollView

            if let documentView = scrollView.documentView {
                documentView.postsFrameChangedNotifications = true
                documentFrameObserver = NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: documentView,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.refreshScrollViewConfiguration()
                    }
                }
            }

            scrollView.contentView.postsBoundsChangedNotifications = true
            clipBoundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshScrollViewConfiguration()
                }
            }
        }

        private func removeObservers() {
            if let documentFrameObserver {
                NotificationCenter.default.removeObserver(documentFrameObserver)
                self.documentFrameObserver = nil
            }
            if let clipBoundsObserver {
                NotificationCenter.default.removeObserver(clipBoundsObserver)
                self.clipBoundsObserver = nil
            }
        }
    }

    private struct DevicesSectionView: View {


        let availableDevices: [OMSDeviceInfo]
        let leftDevice: OMSDeviceInfo?
        let rightDevice: OMSDeviceInfo?
        let onSelectLeft: (OMSDeviceInfo?) -> Void
        let onSelectRight: (OMSDeviceInfo?) -> Void
        let onRefresh: () -> Void
        @ObservedObject var nativeTakeover: NativeTrackpadTakeover
        let replayActive: Bool

        private var takeoverControls: some View {
            NativeTakeoverControls(control: nativeTakeover, unavailable: replayActive)
        }

        private var refreshButton: some View {
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise").imageScale(.medium)
            }
            .buttonStyle(.bordered)
            .disabled(nativeTakeover.isReleasing || replayActive)
            .help("Refresh the trackpad list")
        }


        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                if availableDevices.isEmpty {
                    HStack {
                        Text("No trackpads detected.").foregroundStyle(.secondary)
                        refreshButton
                    }
                    takeoverControls
                } else {
                    HStack(alignment: .top, spacing: 10) {
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
                                    Text(device.selectionLabel)
                                        .tag(device as OMSDeviceInfo?)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .pickerStyle(MenuPickerStyle())
                            .disabled(nativeTakeover.isReleasing || replayActive)
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
                                    Text(device.selectionLabel)
                                        .tag(device as OMSDeviceInfo?)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .pickerStyle(MenuPickerStyle())
                            .disabled(nativeTakeover.isReleasing || replayActive)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        refreshButton
                        .padding(.top, 20)
                    }
                    takeoverControls
                }

            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.05))
            )
        }
    }

    private struct CollapsibleSection<Label: View, Content: View>: View {
        @Binding var isExpanded: Bool
        let topSpacing: CGFloat
        let content: () -> Content
        let label: () -> Label

        init(
            isExpanded: Binding<Bool>,
            topSpacing: CGFloat = 8,
            @ViewBuilder content: @escaping () -> Content,
            @ViewBuilder label: @escaping () -> Label
        ) {
            _isExpanded = isExpanded
            self.topSpacing = topSpacing
            self.content = content
            self.label = label
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                        label()
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)

                if isExpanded {
                    content()
                        .padding(.top, topSpacing)
                }
            }
        }
    }

    private struct ColumnTuningSectionView: View {
        let layoutOption: TrackpadLayoutPreset
        let columnSettings: [ColumnLayoutSettings]
        let selection: ColumnInspectorSelection?
        @Binding var columnSpacingPercent: Double
        @Binding var editColumnIndex: Int
        let onUpdateColumn: (Int, (inout ColumnLayoutSettings) -> Void) -> Void
        let onApplyMxSpacing: () -> Void
        let onApplyChocSpacing: () -> Void
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
                        EqualSplitFormRow {
                            Text("Edit Column")
                        } field: {
                            Picker("", selection: editColumnBinding) {
                                ForEach(columnSettings.indices, id: \.self) { columnIndex in
                                    Text("Column \(columnIndex + 1)").tag(columnIndex)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        VStack(alignment: .leading, spacing: 14) {
                            ColumnTuningRow(
                                title: "Column Spacing (%)",
                                value: Binding(
                                    get: { columnSpacingPercent },
                                    set: { newValue in
                                        columnSpacingPercent = LayoutKeySpacingDefaults.normalized(newValue)
                                    }
                                ),
                                formatter: ContentView.columnSpacingFormatter,
                                range: ContentView.columnSpacingPercentRange,
                                sliderStep: 1.0,
                                buttonStep: 0.5,
                                showSlider: false,
                                fillFieldWidth: true
                            )
                            ColumnTuningRow(
                                title: "Column Scale X (%)",
                                value: Binding(
                                    get: { settings.scaleX * 100.0 },
                                    set: { newValue in
                                        onUpdateColumn(index) { setting in
                                            setting.scaleX = ContentView.normalizedColumnScale(newValue / 100.0)
                                        }
                                    }
                                ),
                                formatter: ContentView.columnScalePercentFormatter,
                                range: ContentView.columnScalePercentRange,
                                sliderStep: 5.0,
                                showSlider: false,
                                fillFieldWidth: true
                            )
                            ColumnTuningRow(
                                title: "Column Scale Y (%)",
                                value: Binding(
                                    get: { settings.scaleY * 100.0 },
                                    set: { newValue in
                                        onUpdateColumn(index) { setting in
                                            setting.scaleY = ContentView.normalizedColumnScale(newValue / 100.0)
                                        }
                                    }
                                ),
                                formatter: ContentView.columnScalePercentFormatter,
                                range: ContentView.columnScalePercentRange,
                                sliderStep: 5.0,
                                showSlider: false,
                                fillFieldWidth: true
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
                                showSlider: false,
                                fillFieldWidth: true
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
                                showSlider: false,
                                fillFieldWidth: true
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
                                showSlider: false,
                                fillFieldWidth: true
                            )
                        }
                        HStack(spacing: 8) {

                            Button {
                                onEvenSpacing()
                            } label: {
                                Text("e v e n s p a c i n g")
                                    .frame(maxWidth: .infinity)
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
                        ? (layoutOption == .touchstream
                            ? "TouchStream uses traced left/right key positions. Select a key to edit its size, rotation, and action."
                            : "This preset uses a fixed right-side layout; column tuning is disabled.")
                        : "Layout has no grid. Pick one of the presets to show keys.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private struct ButtonTuningSectionView: View {
        private enum ActionBuilderTarget: String, CaseIterable, Identifiable {
            case primary = "Primary"
            case hold = "Hold"
            case dropdown = "Shortcuts"

            var id: String { rawValue }
        }

        private struct ActionChooserState: Identifiable {
            let id = UUID()
            let title: String
            let actionGroups: [KeyActionCatalog.ActionGroup]
            let selection: Binding<KeyAction>
        }

        private struct ActionChooserSheet: View {
            let title:String
            let actionGroups:[KeyActionCatalog.ActionGroup]
            let selection:Binding<KeyAction>
            var body:some View {
                SearchableActionSheet(title:title,groups:actionGroups.map { .init(title:$0.title,actions:$0.actions) },
                    selected:selection.wrappedValue,label:{$0.pickerText},searchLabel:{$0.label + " " + $0.pickerText}) { selection.wrappedValue = $0 }
            }
        }

        let buttonSelection: ButtonInspectorSelection?
        let keySelection: KeyInspectorSelection?
        let selectionRevision: Int
        let primaryActionGroups: [KeyActionCatalog.ActionGroup]
        let holdActionGroups: [KeyActionCatalog.ActionGroup]
        let layerSelection: Binding<Int>
        let onAddCustomButton: (TrackpadSide) -> Void
        let onRemoveCustomButton: (UUID) -> Void
        let onClearTouchState: () -> Void
        let onUpdateButton: (UUID, (inout CustomButton) -> Void) -> Void
        let onUpdateKeyMapping: (SelectedGridKey, (inout KeyMapping) -> Void) -> Void
        let keyRotationDegrees: (SelectedGridKey) -> Double
        let onUpdateKeyRotation: (SelectedGridKey, Double) -> Void
        let onSaveShortcutLibraryAction: (KeyAction) -> Void
        @State private var actionBuilderTarget: ActionBuilderTarget = .primary
        @State private var managingShortcuts = false
        @State private var activeActionChooser: ActionChooserState?

        private var hasEditableSelection: Bool {
            buttonSelection != nil || keySelection != nil
        }

        private var canEditActionBuilder: Bool {
            hasEditableSelection || actionBuilderTarget == .dropdown
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
                            if resolvedHold == nil {
                                button.holdForceThreshold = 0
                            }
                        }
                        return
                    }
                    if let selection = keySelection {
                        onUpdateKeyMapping(selection.key) { mapping in
                            mapping.hold = resolvedHold
                            if resolvedHold == nil {
                                mapping.holdForceThreshold = 0
                            }
                        }
                    }
                }
            )
        }

        private var holdActionMenuBinding: Binding<KeyAction> {
            Binding(
                get: { holdActionBinding.wrappedValue ?? KeyActionCatalog.noneAction },
                set: { holdActionBinding.wrappedValue = $0 }
            )
        }

        private var holdForceThresholdBinding: Binding<Double> {
            Binding(
                get: {
                    if let selection = buttonSelection {
                        return Double(selection.button.holdForceThreshold)
                    }
                    if let selection = keySelection {
                        return Double(selection.mapping.holdForceThreshold)
                    }
                    return 0
                },
                set: { newValue in
                    let clamped = KeyMapping.normalizedHoldForceThreshold(
                        Int(
                            min(
                                max(newValue, ContentView.forceClickRange.lowerBound),
                                ContentView.forceClickRange.upperBound
                            ).rounded()
                        )
                    )
                    if let selection = buttonSelection {
                        onUpdateButton(selection.button.id) { button in
                            button.holdForceThreshold = button.hold == nil ? 0 : clamped
                        }
                        return
                    }
                    if let selection = keySelection {
                        onUpdateKeyMapping(selection.key) { mapping in
                            mapping.holdForceThreshold = mapping.hold == nil ? 0 : clamped
                        }
                    }
                }
            )
        }

        private var selectionIdentity: String {
            if let selection = buttonSelection {
                return "button:\(selection.button.id.uuidString)"
            }
            if let selection = keySelection {
                return "key:\(selection.key.storageKey)"
            }
            return "none"
        }

        private var keyRotationBinding: Binding<Double> {
            Binding(
                get: {
                    guard let selection = keySelection else { return 0.0 }
                    return keyRotationDegrees(selection.key)
                },
                set: { newValue in
                    guard let selection = keySelection else { return }
                    onUpdateKeyRotation(
                        selection.key,
                        ContentView.normalizedRotationDegrees(newValue)
                    )
                }
            )
        }

        private var selectedPrimaryAction: KeyAction {
            primaryActionBinding.wrappedValue
        }

        private var selectedHoldAction: KeyAction {
            holdActionBinding.wrappedValue ?? KeyActionCatalog.noneAction
        }

        private var targetAction: KeyAction {
            switch actionBuilderTarget {
            case .primary, .dropdown:
                return selectedPrimaryAction
            case .hold:
                return selectedHoldAction
            }
        }

        private func actionGroups(for action: KeyAction, hold: Bool) -> [KeyActionCatalog.ActionGroup] {
            var groups = hold ? holdActionGroups : primaryActionGroups
            let containsAction = groups.contains { group in
                group.actions.contains(action)
            }
            if action.kind != .none && !containsAction {
                groups.insert(
                    KeyActionCatalog.ActionGroup(
                        title: "Current Custom Action",
                        actions: [action]
                    ),
                    at: 0
                )
            }
            return groups
        }

        private func applyBuiltAction(_ action:KeyAction) {
            switch actionBuilderTarget {
            case .primary: primaryActionBinding.wrappedValue = action
            case .hold: holdActionBinding.wrappedValue = action
            case .dropdown: onSaveShortcutLibraryAction(action)
            }
        }

        private func subsectionHeader(_ title: String) -> some View {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Rectangle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1)
            }
            .padding(.top, 10)
            .padding(.bottom, 6)
        }

        @ViewBuilder
        private func actionChooserButton(
            title: String,
            selection: Binding<KeyAction>,
            actionGroups: [KeyActionCatalog.ActionGroup]
        ) -> some View {
            let currentAction = selection.wrappedValue
            Button {
                activeActionChooser = ActionChooserState(
                    title: title,
                    actionGroups: actionGroups,
                    selection: selection
                )
            } label: {
                HStack(spacing: 8) {
                    Text(currentAction.pickerText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(!hasEditableSelection)
            .opacity(hasEditableSelection ? 1.0 : 0.65)
        }

        var body: some View {
            let primaryGroups = actionGroups(for: selectedPrimaryAction, hold: false)
            let holdGroups = actionGroups(for: selectedHoldAction, hold: true)

            VStack(alignment: .leading, spacing: 10) {
                EqualSplitFormRow {
                    Text("Layer")
                } field: {
                    Picker("", selection: layerSelection) {
                        ForEach(ContentView.editableLayers, id: \.self) { layer in
                            Text("Layer\(layer)").tag(layer)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                EqualSplitFormRow {
                    Text("Primary Action")
                } field: {
                    actionChooserButton(
                        title: "Primary Action",
                        selection: primaryActionBinding,
                        actionGroups: primaryGroups
                    )
                }
                EqualSplitFormRow {
                    Text("Hold Action")
                } field: {
                    actionChooserButton(
                        title: "Hold Action",
                        selection: holdActionMenuBinding,
                        actionGroups: holdGroups
                    )
                }
                EqualSplitFormRow {
                    Text("Force Instead of Hold")
                } field: {
                    TextField(
                        "",
                        value: holdForceThresholdBinding,
                        formatter: ContentView.forceClickFormatter
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .disabled(!hasEditableSelection)
                    .help("0 keeps timed hold. When this is above 0 and force data is present, hold fires only after this force threshold is reached.")
                }
                EqualSplitFormRow {
                    Text("Key Rotation (0-360 deg)")
                } field: {
                    TextField("", value: keyRotationBinding, formatter: ContentView.rotationDegreesFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .disabled(keySelection == nil)
                }
                Divider().padding(.vertical,4)
                VStack(alignment:.leading,spacing:8) {
                    HStack(spacing:8) {
                        Picker("",selection:$actionBuilderTarget) {
                            ForEach(ActionBuilderTarget.allCases) { target in Text(target.rawValue).tag(target) }
                        }.pickerStyle(.segmented).labelsHidden()
                        Button { managingShortcuts = true } label: { Image(systemName:"slider.horizontal.3") }
                            .help("Manage Shortcuts…").accessibilityLabel("Manage Shortcuts")
                    }
                    .sheet(isPresented:$managingShortcuts) { ShortcutLibraryManager() }
                    ShortcutActionBuilder(action:actionBuilderTarget == .dropdown ? nil : targetAction,
                        enabled:canEditActionBuilder) { action,_ in applyBuiltAction(action) }
                        .id("\(actionBuilderTarget.rawValue).\(actionBuilderTarget == .dropdown ? "library" : selectionIdentity)")
                }
                subsectionHeader("Custom Buttons")
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
            .sheet(item: $activeActionChooser) { chooser in
                ActionChooserSheet(
                    title: chooser.title,
                    actionGroups: chooser.actionGroups,
                    selection: chooser.selection
                )
            }
        }

        private var addButtonsRow: some View {
            HStack(spacing: 8) {
                Button {
                    onAddCustomButton(.left)
                } label: {
                    Text("Add Left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    onAddCustomButton(.right)
                } label: {
                    Text("Add Right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
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
        @Binding var keyboardModeEnabled: Bool
        @Binding var holdRepeatEnabled: Bool
        @Binding var runAtStartupEnabled: Bool
        @Binding var autoResyncEnabled: Bool
        @Binding var systemThreeFingerDragEnabled: Bool
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Autocorrect", isOn: $autocorrectEnabled)
                    .help("Corrects completed words using macOS spellchecking in supported editable fields.")
                Toggle("Snap Radius", isOn: Binding(
                    get: { snapRadiusPercentSetting > 0 },
                    set: { snapRadiusPercentSetting = $0 ? 100 : 0 }
                ))
                    .help("Rescues near-miss typing taps by choosing the nearest key. Does not change gesture activation.")
                Toggle("Run at Startup", isOn: $runAtStartupEnabled)
                Toggle("Hold Repeat", isOn: $holdRepeatEnabled)
                    .help("Repeats hold-enabled key actions while the touch stays held.")
                Toggle("Auto-resync", isOn: $autoResyncEnabled)
                    .help("Polls every 8000 ms to detect disconnected trackpads.")
            }
            .toggleStyle(.switch)
        }
    }

    private struct TypingTuningSectionView: View {
        @Binding var tapHoldDurationMs: Double
        @Binding var dragCancelDistanceSetting: Double
        @Binding var forceClickMinSetting: Double
        @Binding var forceClickCapSetting: Double
        @Binding var hapticStrengthSetting: Double
        @Binding var intentMoveThresholdMmSetting: Double
        @Binding var intentVelocityThresholdMmPerSecSetting: Double
        @Binding var tapClickCadenceMsSetting: Double
        let onRestoreDefaults: () -> Void

        private let labelWidth: CGFloat = 140
        private let valueFieldWidth: CGFloat = 50

        private var hapticLevelBinding: Binding<Double> {
            Binding(
                get: { TypingHapticFeedback.level(hapticStrengthSetting / 100) },
                set: { hapticStrengthSetting = TypingHapticFeedback.level($0) * 100 }
            )
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Hold Duration (ms)")
                    Spacer(minLength: 4)
                    TextField("200", value: $tapHoldDurationMs,
                              formatter: ContentView.tapHoldDurationFormatter)
                        .frame(width: valueFieldWidth)
                }
                Slider(value: $tapHoldDurationMs, in: ContentView.tapHoldDurationRange, step: 10)
                HStack {
                    Text("Haptic Strength")
                    Spacer(minLength: 4)
                    Text(String(format: "%.2f", hapticLevelBinding.wrappedValue))
                }
                Slider(value: hapticLevelBinding, in: 0...2, step: 0.01)
                Button("Restore Defaults", action: onRestoreDefaults)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private struct TrackpadDeckView: View {
        @ObservedObject var viewModel: ContentViewModel
        let showTouchStreamReference: Bool
        let trackpadSize: CGSize
        let leftLayout: ContentViewModel.Layout
        let rightLayout: ContentViewModel.Layout
        let leftBaseLabels: [[String]]
        let rightBaseLabels: [[String]]
        let leftGridLabelInfo: [[GridLabel]]
        let rightGridLabelInfo: [[GridLabel]]
        let customButtons: [CustomButton]
        let lastHitLeft: ContentViewModel.DebugHit?
        let lastHitRight: ContentViewModel.DebugHit?
        @Binding var selectedButtonID: UUID?
        @Binding var selectedGridKey: SelectedGridKey?
        let onSelectionInteraction: () -> Void
        @State private var leftPeakPressure = 0
        @State private var rightPeakPressure = 0


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
                    pressureHeader(title: "Left Trackpad", peakPressure: leftPeakPressure)
                        .frame(width: trackpadSize.width, alignment: .leading)
                    pressureHeader(title: "Right Trackpad", peakPressure: rightPeakPressure)
                        .frame(width: trackpadSize.width, alignment: .leading)
                }
                ZStack(alignment: .topLeading) {
                    TrackpadSurfaceRepresentable(
                        snapshot: TrackpadSurfaceSnapshot(
                            trackpadSize: trackpadSize,
                            spacing: trackpadSpacing,
                            showDetailed: showDetailedView,
                            showTouchTelemetry: true,
                            showTouchStreamReference: showTouchStreamReference,
                            showContactPaths: true,
                            replayModeEnabled: viewModel.replayTimelineState != nil,
                            leftLayout: leftLayout,
                            rightLayout: rightLayout,
                            leftLabels: surfaceLabels(from: leftGridLabelInfo),
                            rightLabels: surfaceLabels(from: rightGridLabelInfo),
                            leftCustomButtons: leftButtons,
                            rightCustomButtons: rightButtons,
                            selectedLeftKey: surfaceKeySelection(from: selectedLeftKey),
                            selectedRightKey: surfaceKeySelection(from: selectedRightKey),
                            selectedLeftButtonID: selectedButton(for: leftButtons)?.id,
                            selectedRightButtonID: selectedButton(for: rightButtons)?.id
                        ),
                        viewModel: viewModel,
                        selectionHandler: surfaceSelectionChanged,
                        peakPressureHandler: { leftPeakPressure, rightPeakPressure in
                            self.leftPeakPressure = leftPeakPressure
                            self.rightPeakPressure = rightPeakPressure
                        }
                    )
                    .frame(width: combinedWidth, height: trackpadSize.height)
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

        @ViewBuilder
        private func pressureHeader(title: String, peakPressure: Int) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.subheadline)
                Text("Peak: \(peakPressure)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
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
            viewModel.clearTouchState()
            onSelectionInteraction()
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
        keySpacingPercent: Double = LayoutKeySpacingDefaults.defaultPercent,
        keyGeometryOverrides: KeyGeometryOverrides = [:],
        mirrored: Bool = false
    ) -> ContentViewModel.Layout {
        guard columns > 0,
              rows > 0,
              columnAnchorsMM.count == columns else {
            return ContentViewModel.Layout(normalizedKeyRects: [], trackpadSize: size)
        }
        let viewScaleX = size.width / trackpadWidth
        let viewScaleY = size.height / trackpadHeight
        let resolvedSettings = normalizedColumnSettings(
            columnSettings,
            columns: columns
        )
        let columnScaleXs = resolvedSettings.map { CGFloat($0.scaleX) }
        let columnScaleYs = resolvedSettings.map { CGFloat($0.scaleY) }
        let spacingScale = CGFloat(LayoutKeySpacingDefaults.normalized(keySpacingPercent) / 100.0)

        var keyRects: [[CGRect]] = Array(
            repeating: Array(repeating: .zero, count: columns),
            count: rows
        )
        for row in 0..<rows {
            for col in 0..<columns {
                let anchorMM = columnAnchorsMM[col]
                let columnScaleX = columnScaleXs[col]
                let columnScaleY = columnScaleYs[col]
                let keySize = CGSize(
                    width: keyWidth * columnScaleX * viewScaleX,
                    height: keyHeight * columnScaleY * viewScaleY
                )
                let keySpacingY = keySize.height * spacingScale
                let rowSpacingY = keySize.height * CGFloat(resolvedSettings[col].rowSpacingPercent / 100.0)
                keyRects[row][col] = CGRect(
                    x: anchorMM.x * viewScaleX,
                    y: anchorMM.y * viewScaleY + CGFloat(row) * (keySize.height + keySpacingY + rowSpacingY),
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
                let widthScale = max(geometry.widthScale, 0.05)
                let heightScale = max(geometry.heightScale, 0.05)
                let rect = keyRects[row][col]
                let scaledWidth = min(max(rect.width * CGFloat(widthScale), 0.001), 1.0)
                let scaledHeight = min(max(rect.height * CGFloat(heightScale), 0.001), 1.0)
                let scaledRect = NormalizedRect(
                    x: rect.centerX - (scaledWidth * 0.5),
                    y: rect.centerY - (scaledHeight * 0.5),
                    width: scaledWidth,
                    height: scaledHeight
                ).clamped(minWidth: 0.001, minHeight: 0.001)
                keyRects[row][col] = scaledRect.rotatedAround(
                    pivotX: scaledRect.centerX,
                    pivotY: scaledRect.centerY,
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

    static func makeTouchStreamKeyLayout(
        size: CGSize, side: TrackpadSide, keyGeometryOverrides: KeyGeometryOverrides = [:]
    ) -> ContentViewModel.Layout {
        var rects = TouchStreamLayoutDefinition.rows(for: side).map { $0.map(\.rect) }
        for row in rects.indices {
            for column in rects[row].indices {
                let key = GridKeyPosition(side: side, row: row, column: column).storageKey
                guard let edit = keyGeometryOverrides[key] else { continue }
                let original = rects[row][column]
                let width = min(1, max(0.001, original.width * CGFloat(edit.widthScale)))
                let height = min(1, max(0.001, original.height * CGFloat(edit.heightScale)))
                rects[row][column] = NormalizedRect(x: original.centerX - width / 2,
                    y: original.centerY - height / 2, width: width, height: height,
                    rotationDegrees: original.rotationDegrees - edit.rotationDegrees)
            }
        }
        return ContentViewModel.Layout(normalizedKeyRects: rects, trackpadSize: size)
    }

    static func makeMobileKeyLayout(
        size: CGSize,
        keyGeometryOverrides: KeyGeometryOverrides = [:]
    ) -> ContentViewModel.Layout {
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

        var normalizedKeyRects = keyRows.map { row in
            row.map { normalizedRect(for: $0, in: size) }
        }
        applyKeyGeometryOverrides(
            keyRects: &normalizedKeyRects,
            keyGeometryOverrides: keyGeometryOverrides,
            mirrored: false
        )
        return ContentViewModel.Layout(
            normalizedKeyRects: normalizedKeyRects,
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

    private func handleLayoutOptionChange(_ requestedLayout: TrackpadLayoutPreset) {
        let newLayout: TrackpadLayoutPreset = (requestedLayout == .mobile || requestedLayout == .mobileOrtho12x4) ? .sixByThree : requestedLayout
        if newLayout != layoutOption {
            saveSettings()
        }
        layoutOption = newLayout
        storedLayoutPreset = newLayout.rawValue
        selectedGridKey = nil
        selectedButtonID = nil
        columnSettings = columnSettings(for: newLayout)
        keySpacingPercent = keySpacingPercent(for: newLayout)
        keyGeometryOverrides = keyGeometryOverrides(for: newLayout)
        editColumnIndex = 0
        customButtons = loadCustomButtons(for: newLayout)
        keyMappingsByLayer = keyMappings(for: newLayout)
        viewModel.updateCustomButtons(customButtons)
        updateGridLabelInfo()
        applyColumnSettings(columnSettings)
    }

    private func rebuildLayouts() {
        if layoutOption == .touchstream {
            leftLayout = Self.makeTouchStreamKeyLayout(size: trackpadSize, side: .left, keyGeometryOverrides: keyGeometryOverrides)
            rightLayout = Self.makeTouchStreamKeyLayout(size: trackpadSize, side: .right, keyGeometryOverrides: keyGeometryOverrides)
            viewModel.configureLayouts(leftLayout: leftLayout, rightLayout: rightLayout,
                leftLabels: leftGridLabels, rightLabels: rightGridLabels,
                trackpadSize: trackpadSize, trackpadWidthMm: Self.trackpadWidthMM)
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
        if layoutOption == .mobile {
            leftLayout = ContentViewModel.Layout(keyRects: [], trackpadSize: trackpadSize)
            rightLayout = ContentView.makeMobileKeyLayout(
                size: trackpadSize,
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
                keySpacingPercent: keySpacingPercent,
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
            keySpacingPercent: keySpacingPercent,
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
            keySpacingPercent: keySpacingPercent,
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
        normalizeStoredShortcutActions()
        let storedLayout = TrackpadLayoutPreset.resolveByNameOrDefault(storedLayoutPreset)
        let resolvedLayout: TrackpadLayoutPreset = (storedLayout == .mobile || storedLayout == .mobileOrtho12x4) ? .sixByThree : storedLayout
        layoutOption = resolvedLayout
        selectedGridKey = nil
        selectedButtonID = nil
        columnSettings = columnSettings(for: resolvedLayout)
        keySpacingPercent = keySpacingPercent(for: resolvedLayout)
        keyGeometryOverrides = keyGeometryOverrides(for: resolvedLayout)
        editColumnIndex = 0
        customButtons = loadCustomButtons(for: resolvedLayout)
        loadKeyMappings()
        keyMappingsByLayer = keyMappings(for: resolvedLayout)
        viewModel.updateCustomButtons(customButtons)
        updateGridLabelInfo()
        applyColumnSettings(columnSettings)
        if UserDefaults.standard.object(forKey: GlassToKeyDefaultsKeys.leftDeviceID) != nil {
            viewModel.selectLeftDevice(deviceForID(storedLeftDeviceID))
        }
        if UserDefaults.standard.object(forKey: GlassToKeyDefaultsKeys.rightDeviceID) != nil {
            viewModel.selectRightDevice(deviceForID(storedRightDeviceID))
        }
        normalizeGestureSettings()
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
        forceClickThresholdSetting = min(
            max(forceClickThresholdSetting, Self.forceClickThresholdRange.lowerBound),
            Self.forceClickThresholdRange.upperBound
        )
        viewModel.updateForceClickMin(forceClickMinSetting)
        viewModel.updateForceClickCap(forceClickCapSetting)
        viewModel.updateForceClickThreshold(forceClickThresholdSetting)
        viewModel.updateHapticStrength(hapticStrengthSetting / 100.0)
        viewModel.updateIntentMoveThresholdMm(intentMoveThresholdMmSetting)
        viewModel.updateIntentVelocityThresholdMmPerSec(intentVelocityThresholdMmPerSecSetting)
        viewModel.updateAllowMouseTakeover(true)
        viewModel.updateSnapRadiusPercent(snapRadiusPercentSetting)
        AutocorrectEngine.shared.setEnabled(autocorrectEnabled)
        viewModel.updateHoldRepeatEnabled(holdRepeatEnabled)
        runAtStartupEnabled = LaunchAtLoginManager.shared.isEnabled
        viewModel.updateTapClickCadenceMs(tapClickCadenceMsSetting)
        viewModel.setTouchSnapshotRecordingEnabled(true)
    }

    private func restoreTypingTuningDefaults() {
        tapHoldDurationMs = GlassToKeySettings.tapHoldDurationMs
        dragCancelDistanceSetting = GlassToKeySettings.dragCancelDistanceMm
        forceClickMinSetting = GlassToKeySettings.forceClickMin
        forceClickCapSetting = GlassToKeySettings.forceClickCap
        forceClickThresholdSetting = GlassToKeySettings.forceClickThreshold
        hapticStrengthSetting = GlassToKeySettings.hapticStrengthPercent
        intentMoveThresholdMmSetting = GlassToKeySettings.intentMoveThresholdMm
        intentVelocityThresholdMmPerSecSetting = GlassToKeySettings.intentVelocityThresholdMmPerSec
        autocorrectEnabled = GlassToKeySettings.autocorrectEnabled
        tapClickCadenceMsSetting = GlassToKeySettings.tapClickCadenceMs
        snapRadiusPercentSetting = GlassToKeySettings.snapRadiusPercent
        keyboardModeEnabled = GlassToKeySettings.keyboardModeEnabled
        holdRepeatEnabled = GlassToKeySettings.holdRepeatEnabled
        twoFingerTapGestureAction = GlassToKeySettings.twoFingerTapGestureActionLabel
        threeFingerTapGestureAction = GlassToKeySettings.threeFingerTapGestureActionLabel
        twoFingerHoldGestureAction = GlassToKeySettings.twoFingerHoldGestureActionLabel
        threeFingerHoldGestureAction = GlassToKeySettings.threeFingerHoldGestureActionLabel
        fourFingerHoldGestureAction = GlassToKeySettings.fourFingerHoldGestureActionLabel
        outerCornersHoldGestureAction = GlassToKeySettings.outerCornersHoldGestureActionLabel
        innerCornersHoldGestureAction = GlassToKeySettings.innerCornersHoldGestureActionLabel
        leftEdgeUpGestureAction = GlassToKeySettings.leftEdgeUpGestureActionLabel
        leftEdgeDownGestureAction = GlassToKeySettings.leftEdgeDownGestureActionLabel
        rightEdgeUpGestureAction = GlassToKeySettings.rightEdgeUpGestureActionLabel
        rightEdgeDownGestureAction = GlassToKeySettings.rightEdgeDownGestureActionLabel
        topEdgeLeftGestureAction = GlassToKeySettings.topEdgeLeftGestureActionLabel
        topEdgeRightGestureAction = GlassToKeySettings.topEdgeRightGestureActionLabel
        bottomEdgeLeftGestureAction = GlassToKeySettings.bottomEdgeLeftGestureActionLabel
        bottomEdgeRightGestureAction = GlassToKeySettings.bottomEdgeRightGestureActionLabel
        threeFingerSwipeLeftGestureAction = GlassToKeySettings.threeFingerSwipeLeftGestureActionLabel
        threeFingerSwipeRightGestureAction = GlassToKeySettings.threeFingerSwipeRightGestureActionLabel
        threeFingerSwipeUpGestureAction = GlassToKeySettings.threeFingerSwipeUpGestureActionLabel
        threeFingerSwipeDownGestureAction = GlassToKeySettings.threeFingerSwipeDownGestureActionLabel
        fourFingerSwipeLeftGestureAction = GlassToKeySettings.fourFingerSwipeLeftGestureActionLabel
        fourFingerSwipeRightGestureAction = GlassToKeySettings.fourFingerSwipeRightGestureActionLabel
        fourFingerSwipeUpGestureAction = GlassToKeySettings.fourFingerSwipeUpGestureActionLabel
        fourFingerSwipeDownGestureAction = GlassToKeySettings.fourFingerSwipeDownGestureActionLabel
        fiveFingerSwipeLeftGestureAction = GlassToKeySettings.fiveFingerSwipeLeftGestureActionLabel
        fiveFingerSwipeRightGestureAction = GlassToKeySettings.fiveFingerSwipeRightGestureActionLabel
        fiveFingerSwipeUpGestureAction = GlassToKeySettings.fiveFingerSwipeUpGestureActionLabel
        fiveFingerSwipeDownGestureAction = GlassToKeySettings.fiveFingerSwipeDownGestureActionLabel
        topLeftCornerSwipeGestureAction = GlassToKeySettings.topLeftCornerSwipeGestureActionLabel
        topRightCornerSwipeGestureAction = GlassToKeySettings.topRightCornerSwipeGestureActionLabel
        bottomLeftCornerSwipeGestureAction = GlassToKeySettings.bottomLeftCornerSwipeGestureActionLabel
        bottomRightCornerSwipeGestureAction = GlassToKeySettings.bottomRightCornerSwipeGestureActionLabel
        topLeftTriangleGestureAction = GlassToKeySettings.topLeftTriangleGestureActionLabel
        topRightTriangleGestureAction = GlassToKeySettings.topRightTriangleGestureActionLabel
        bottomLeftTriangleGestureAction = GlassToKeySettings.bottomLeftTriangleGestureActionLabel
        bottomRightTriangleGestureAction = GlassToKeySettings.bottomRightTriangleGestureActionLabel
        upperLeftCornerClickGestureAction = GlassToKeySettings.upperLeftCornerClickGestureActionLabel
        upperRightCornerClickGestureAction = GlassToKeySettings.upperRightCornerClickGestureActionLabel
        lowerLeftCornerClickGestureAction = GlassToKeySettings.lowerLeftCornerClickGestureActionLabel
        lowerRightCornerClickGestureAction = GlassToKeySettings.lowerRightCornerClickGestureActionLabel
        threeFingerClickGestureAction = GlassToKeySettings.threeFingerClickGestureActionLabel
        fourFingerClickGestureAction = GlassToKeySettings.fourFingerClickGestureActionLabel
        topLeftForceClickGestureAction = GlassToKeySettings.topLeftForceClickGestureActionLabel
        topRightForceClickGestureAction = GlassToKeySettings.topRightForceClickGestureActionLabel
        bottomLeftForceClickGestureAction = GlassToKeySettings.bottomLeftForceClickGestureActionLabel
        bottomRightForceClickGestureAction = GlassToKeySettings.bottomRightForceClickGestureActionLabel
        storedGestureRepeatCadenceData = Data()
    }

    private func normalizeGestureSettings() {
        twoFingerTapGestureAction = normalizedGestureActionLabel(twoFingerTapGestureAction, fallbackLabel: GlassToKeySettings.twoFingerTapGestureActionLabel)
        threeFingerTapGestureAction = normalizedGestureActionLabel(threeFingerTapGestureAction, fallbackLabel: GlassToKeySettings.threeFingerTapGestureActionLabel)
        twoFingerHoldGestureAction = normalizedGestureActionLabel(twoFingerHoldGestureAction, fallbackLabel: GlassToKeySettings.twoFingerHoldGestureActionLabel)
        threeFingerHoldGestureAction = normalizedGestureActionLabel(threeFingerHoldGestureAction, fallbackLabel: GlassToKeySettings.threeFingerHoldGestureActionLabel)
        fourFingerHoldGestureAction = normalizedGestureActionLabel(fourFingerHoldGestureAction, fallbackLabel: GlassToKeySettings.fourFingerHoldGestureActionLabel)
        outerCornersHoldGestureAction = normalizedGestureActionLabel(outerCornersHoldGestureAction, fallbackLabel: GlassToKeySettings.outerCornersHoldGestureActionLabel)
        innerCornersHoldGestureAction = normalizedGestureActionLabel(innerCornersHoldGestureAction, fallbackLabel: GlassToKeySettings.innerCornersHoldGestureActionLabel)
        leftEdgeUpGestureAction = normalizedGestureActionLabel(leftEdgeUpGestureAction, fallbackLabel: GlassToKeySettings.leftEdgeUpGestureActionLabel)
        leftEdgeDownGestureAction = normalizedGestureActionLabel(leftEdgeDownGestureAction, fallbackLabel: GlassToKeySettings.leftEdgeDownGestureActionLabel)
        rightEdgeUpGestureAction = normalizedGestureActionLabel(rightEdgeUpGestureAction, fallbackLabel: GlassToKeySettings.rightEdgeUpGestureActionLabel)
        rightEdgeDownGestureAction = normalizedGestureActionLabel(rightEdgeDownGestureAction, fallbackLabel: GlassToKeySettings.rightEdgeDownGestureActionLabel)
        topEdgeLeftGestureAction = normalizedGestureActionLabel(topEdgeLeftGestureAction, fallbackLabel: GlassToKeySettings.topEdgeLeftGestureActionLabel)
        topEdgeRightGestureAction = normalizedGestureActionLabel(topEdgeRightGestureAction, fallbackLabel: GlassToKeySettings.topEdgeRightGestureActionLabel)
        bottomEdgeLeftGestureAction = normalizedGestureActionLabel(bottomEdgeLeftGestureAction, fallbackLabel: GlassToKeySettings.bottomEdgeLeftGestureActionLabel)
        bottomEdgeRightGestureAction = normalizedGestureActionLabel(bottomEdgeRightGestureAction, fallbackLabel: GlassToKeySettings.bottomEdgeRightGestureActionLabel)
        threeFingerSwipeLeftGestureAction = normalizedGestureActionLabel(threeFingerSwipeLeftGestureAction, fallbackLabel: GlassToKeySettings.threeFingerSwipeLeftGestureActionLabel)
        threeFingerSwipeRightGestureAction = normalizedGestureActionLabel(threeFingerSwipeRightGestureAction, fallbackLabel: GlassToKeySettings.threeFingerSwipeRightGestureActionLabel)
        threeFingerSwipeUpGestureAction = normalizedGestureActionLabel(threeFingerSwipeUpGestureAction, fallbackLabel: GlassToKeySettings.threeFingerSwipeUpGestureActionLabel)
        threeFingerSwipeDownGestureAction = normalizedGestureActionLabel(threeFingerSwipeDownGestureAction, fallbackLabel: GlassToKeySettings.threeFingerSwipeDownGestureActionLabel)
        fourFingerSwipeLeftGestureAction = normalizedGestureActionLabel(fourFingerSwipeLeftGestureAction, fallbackLabel: GlassToKeySettings.fourFingerSwipeLeftGestureActionLabel)
        fourFingerSwipeRightGestureAction = normalizedGestureActionLabel(fourFingerSwipeRightGestureAction, fallbackLabel: GlassToKeySettings.fourFingerSwipeRightGestureActionLabel)
        fourFingerSwipeUpGestureAction = normalizedGestureActionLabel(fourFingerSwipeUpGestureAction, fallbackLabel: GlassToKeySettings.fourFingerSwipeUpGestureActionLabel)
        fourFingerSwipeDownGestureAction = normalizedGestureActionLabel(fourFingerSwipeDownGestureAction, fallbackLabel: GlassToKeySettings.fourFingerSwipeDownGestureActionLabel)
        fiveFingerSwipeLeftGestureAction = normalizedGestureActionLabel(fiveFingerSwipeLeftGestureAction, fallbackLabel: GlassToKeySettings.fiveFingerSwipeLeftGestureActionLabel)
        fiveFingerSwipeRightGestureAction = normalizedGestureActionLabel(fiveFingerSwipeRightGestureAction, fallbackLabel: GlassToKeySettings.fiveFingerSwipeRightGestureActionLabel)
        fiveFingerSwipeUpGestureAction = normalizedGestureActionLabel(fiveFingerSwipeUpGestureAction, fallbackLabel: GlassToKeySettings.fiveFingerSwipeUpGestureActionLabel)
        fiveFingerSwipeDownGestureAction = normalizedGestureActionLabel(fiveFingerSwipeDownGestureAction, fallbackLabel: GlassToKeySettings.fiveFingerSwipeDownGestureActionLabel)
        topLeftCornerSwipeGestureAction = normalizedGestureActionLabel(topLeftCornerSwipeGestureAction, fallbackLabel: GlassToKeySettings.topLeftCornerSwipeGestureActionLabel)
        topRightCornerSwipeGestureAction = normalizedGestureActionLabel(topRightCornerSwipeGestureAction, fallbackLabel: GlassToKeySettings.topRightCornerSwipeGestureActionLabel)
        bottomLeftCornerSwipeGestureAction = normalizedGestureActionLabel(bottomLeftCornerSwipeGestureAction, fallbackLabel: GlassToKeySettings.bottomLeftCornerSwipeGestureActionLabel)
        bottomRightCornerSwipeGestureAction = normalizedGestureActionLabel(bottomRightCornerSwipeGestureAction, fallbackLabel: GlassToKeySettings.bottomRightCornerSwipeGestureActionLabel)
        topLeftTriangleGestureAction = normalizedGestureActionLabel(topLeftTriangleGestureAction, fallbackLabel: GlassToKeySettings.topLeftTriangleGestureActionLabel)
        topRightTriangleGestureAction = normalizedGestureActionLabel(topRightTriangleGestureAction, fallbackLabel: GlassToKeySettings.topRightTriangleGestureActionLabel)
        bottomLeftTriangleGestureAction = normalizedGestureActionLabel(bottomLeftTriangleGestureAction, fallbackLabel: GlassToKeySettings.bottomLeftTriangleGestureActionLabel)
        bottomRightTriangleGestureAction = normalizedGestureActionLabel(bottomRightTriangleGestureAction, fallbackLabel: GlassToKeySettings.bottomRightTriangleGestureActionLabel)
        upperLeftCornerClickGestureAction = normalizedGestureActionLabel(upperLeftCornerClickGestureAction, fallbackLabel: GlassToKeySettings.upperLeftCornerClickGestureActionLabel)
        upperRightCornerClickGestureAction = normalizedGestureActionLabel(upperRightCornerClickGestureAction, fallbackLabel: GlassToKeySettings.upperRightCornerClickGestureActionLabel)
        lowerLeftCornerClickGestureAction = normalizedGestureActionLabel(lowerLeftCornerClickGestureAction, fallbackLabel: GlassToKeySettings.lowerLeftCornerClickGestureActionLabel)
        lowerRightCornerClickGestureAction = normalizedGestureActionLabel(lowerRightCornerClickGestureAction, fallbackLabel: GlassToKeySettings.lowerRightCornerClickGestureActionLabel)
        threeFingerClickGestureAction = normalizedGestureActionLabel(threeFingerClickGestureAction, fallbackLabel: GlassToKeySettings.threeFingerClickGestureActionLabel)
        fourFingerClickGestureAction = normalizedGestureActionLabel(fourFingerClickGestureAction, fallbackLabel: GlassToKeySettings.fourFingerClickGestureActionLabel)
        topLeftForceClickGestureAction = normalizedGestureActionLabel(topLeftForceClickGestureAction, fallbackLabel: GlassToKeySettings.topLeftForceClickGestureActionLabel)
        topRightForceClickGestureAction = normalizedGestureActionLabel(topRightForceClickGestureAction, fallbackLabel: GlassToKeySettings.topRightForceClickGestureActionLabel)
        bottomLeftForceClickGestureAction = normalizedGestureActionLabel(bottomLeftForceClickGestureAction, fallbackLabel: GlassToKeySettings.bottomLeftForceClickGestureActionLabel)
        bottomRightForceClickGestureAction = normalizedGestureActionLabel(bottomRightForceClickGestureAction, fallbackLabel: GlassToKeySettings.bottomRightForceClickGestureActionLabel)
    }

    private func exportKeymap() {
        persistConfig()
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "GlassToKey-mac-settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let profile = keymapProfileSnapshot()
            let data = try PortableKeymapInterop.exportBundle(from: profile)
            try data.write(to: url, options: .atomic)
            showKeymapAlert(
                title: "Export complete",
                message: "Settings bundle saved to:\n\(url.path)"
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
            let profile = try PortableKeymapInterop.importProfile(
                from: data,
                currentProfile: keymapProfileSnapshot()
            )
            applyKeymapProfile(profile)
            showKeymapAlert(
                title: "Import complete",
                message: "Loaded settings bundle from:\n\(url.path)"
            )
        } catch {
            showKeymapAlert(
                title: "Import failed",
                message: error.localizedDescription,
                style: .warning
            )
        }
    }

    private func keymapProfileSnapshot() -> AppKeymapProfile {
        let keySpacingPercentByLayout = LayoutKeySpacingStorage.decode(from: storedKeySpacingByLayoutData)
            ?? [:]
        let columnSettingsByLayout = LayoutColumnSettingsStorage.decode(from: storedColumnSettingsData) ?? [:]
        let customButtonsByLayout = LayoutCustomButtonStorage.decode(from: storedCustomButtonsData) ?? [:]
        let shortcutActions = ShortcutActionLibraryStorage.decode(from: storedShortcutActionsData) ?? []
        let mappings = KeyActionMappingStore.decodeLayoutNormalized(storedKeyMappingsData)
            ?? normalizedLayoutMappingsWithCurrentRuntime()
        let keyGeometryByLayout = KeyGeometryStore.decodeLayoutNormalized(storedKeyGeometryData)
            ?? normalizedLayoutKeyGeometryWithCurrentRuntime()
        return AppKeymapProfile(
            leftDeviceID: storedLeftDeviceID,
            rightDeviceID: storedRightDeviceID,
            layoutPreset: storedLayoutPreset,
            activeLayer: viewModel.activeLayer,
            autoResyncMissingTrackpads: storedAutoResyncMissingTrackpads,
            runAtStartupEnabled: runAtStartupEnabled,
            tapHoldDurationMs: tapHoldDurationMs,
            dragCancelDistance: dragCancelDistanceSetting,
            forceClickMin: forceClickMinSetting,
            forceClickCap: forceClickCapSetting,
            forceClickThreshold: forceClickThresholdSetting,
            hapticStrength: hapticStrengthSetting,
            intentMoveThresholdMm: intentMoveThresholdMmSetting,
            intentVelocityThresholdMmPerSec: intentVelocityThresholdMmPerSecSetting,
            autocorrectEnabled: autocorrectEnabled,
            tapClickCadenceMs: tapClickCadenceMsSetting,
            snapRadiusPercent: snapRadiusPercentSetting,
            keyboardModeEnabled: keyboardModeEnabled,
            holdRepeatEnabled: holdRepeatEnabled,
            shortcutActions: shortcutActions,
            twoFingerTapGestureAction: twoFingerTapGestureAction,
            threeFingerTapGestureAction: threeFingerTapGestureAction,
            twoFingerHoldGestureAction: twoFingerHoldGestureAction,
            threeFingerHoldGestureAction: threeFingerHoldGestureAction,
            fourFingerHoldGestureAction: fourFingerHoldGestureAction,
            outerCornersHoldGestureAction: outerCornersHoldGestureAction,
            innerCornersHoldGestureAction: innerCornersHoldGestureAction,
            leftEdgeUpGestureAction: leftEdgeUpGestureAction,
            leftEdgeDownGestureAction: leftEdgeDownGestureAction,
            rightEdgeUpGestureAction: rightEdgeUpGestureAction,
            rightEdgeDownGestureAction: rightEdgeDownGestureAction,
            topEdgeLeftGestureAction: topEdgeLeftGestureAction,
            topEdgeRightGestureAction: topEdgeRightGestureAction,
            bottomEdgeLeftGestureAction: bottomEdgeLeftGestureAction,
            bottomEdgeRightGestureAction: bottomEdgeRightGestureAction,
            threeFingerSwipeLeftGestureAction: threeFingerSwipeLeftGestureAction,
            threeFingerSwipeRightGestureAction: threeFingerSwipeRightGestureAction,
            threeFingerSwipeUpGestureAction: threeFingerSwipeUpGestureAction,
            threeFingerSwipeDownGestureAction: threeFingerSwipeDownGestureAction,
            fourFingerSwipeLeftGestureAction: fourFingerSwipeLeftGestureAction,
            fourFingerSwipeRightGestureAction: fourFingerSwipeRightGestureAction,
            fourFingerSwipeUpGestureAction: fourFingerSwipeUpGestureAction,
            fourFingerSwipeDownGestureAction: fourFingerSwipeDownGestureAction,
            fiveFingerSwipeLeftGestureAction: fiveFingerSwipeLeftGestureAction,
            fiveFingerSwipeRightGestureAction: fiveFingerSwipeRightGestureAction,
            fiveFingerSwipeUpGestureAction: fiveFingerSwipeUpGestureAction,
            fiveFingerSwipeDownGestureAction: fiveFingerSwipeDownGestureAction,
            topLeftCornerSwipeGestureAction: topLeftCornerSwipeGestureAction,
            topRightCornerSwipeGestureAction: topRightCornerSwipeGestureAction,
            bottomLeftCornerSwipeGestureAction: bottomLeftCornerSwipeGestureAction,
            bottomRightCornerSwipeGestureAction: bottomRightCornerSwipeGestureAction,
            topLeftTriangleGestureAction: topLeftTriangleGestureAction,
            topRightTriangleGestureAction: topRightTriangleGestureAction,
            bottomLeftTriangleGestureAction: bottomLeftTriangleGestureAction,
            bottomRightTriangleGestureAction: bottomRightTriangleGestureAction,
            upperLeftCornerClickGestureAction: upperLeftCornerClickGestureAction,
            upperRightCornerClickGestureAction: upperRightCornerClickGestureAction,
            lowerLeftCornerClickGestureAction: lowerLeftCornerClickGestureAction,
            lowerRightCornerClickGestureAction: lowerRightCornerClickGestureAction,
            threeFingerClickGestureAction: threeFingerClickGestureAction,
            fourFingerClickGestureAction: fourFingerClickGestureAction,
            topLeftForceClickGestureAction: topLeftForceClickGestureAction,
            topRightForceClickGestureAction: topRightForceClickGestureAction,
            bottomLeftForceClickGestureAction: bottomLeftForceClickGestureAction,
            bottomRightForceClickGestureAction: bottomRightForceClickGestureAction,
            gestureRepeatCadenceMsById: GestureRepeatCadenceStorage.decode(
                from: storedGestureRepeatCadenceData
            ),
            keySpacingPercentByLayout: keySpacingPercentByLayout,
            columnSettingsByLayout: columnSettingsByLayout,
            customButtonsByLayout: customButtonsByLayout,
            keyMappingsByLayout: mappings,
            keyGeometryByLayout: keyGeometryByLayout,
            gestureRecognitionEnabled: gestureRecognitionEnabled,
            handGestureSettings: viewModel.gestures.settings
        )
    }

    private func applyKeymapProfile(_ profile: AppKeymapProfile) {
        if let gestures = profile.handGestureSettings { viewModel.gestures.applyImportedSettings(gestures) }
        gestureRecognitionEnabled = profile.gestureRecognitionEnabled ?? false
        storedLeftDeviceID = profile.leftDeviceID
        storedRightDeviceID = profile.rightDeviceID
        storedLayoutPreset = profile.layoutPreset
        storedAutoResyncMissingTrackpads = profile.autoResyncMissingTrackpads
        if let runAtStartupEnabled = profile.runAtStartupEnabled {
            do {
                try LaunchAtLoginManager.shared.setEnabled(runAtStartupEnabled)
            } catch {
                showKeymapAlert(
                    title: "Run at startup update failed",
                    message: error.localizedDescription,
                    style: .warning
                )
            }
            self.runAtStartupEnabled = LaunchAtLoginManager.shared.isEnabled
        }

        tapHoldDurationMs = profile.tapHoldDurationMs
        dragCancelDistanceSetting = profile.dragCancelDistance
        forceClickMinSetting = profile.forceClickMin ?? GlassToKeySettings.forceClickMin
        forceClickCapSetting = profile.forceClickCap
        forceClickThresholdSetting = profile.forceClickThreshold
        hapticStrengthSetting = profile.hapticStrength
        intentMoveThresholdMmSetting = profile.intentMoveThresholdMm
        intentVelocityThresholdMmPerSecSetting = profile.intentVelocityThresholdMmPerSec
        autocorrectEnabled = profile.autocorrectEnabled
        tapClickCadenceMsSetting = profile.tapClickCadenceMs
        snapRadiusPercentSetting = profile.snapRadiusPercent
        keyboardModeEnabled = profile.keyboardModeEnabled
        holdRepeatEnabled = profile.holdRepeatEnabled
        storedShortcutActionsData = ShortcutActionLibraryStorage.encode(profile.shortcutActions) ?? Data()
        twoFingerTapGestureAction = profile.twoFingerTapGestureAction ?? GlassToKeySettings.twoFingerTapGestureActionLabel
        threeFingerTapGestureAction = profile.threeFingerTapGestureAction ?? GlassToKeySettings.threeFingerTapGestureActionLabel
        twoFingerHoldGestureAction = profile.twoFingerHoldGestureAction ?? GlassToKeySettings.twoFingerHoldGestureActionLabel
        threeFingerHoldGestureAction = profile.threeFingerHoldGestureAction ?? GlassToKeySettings.threeFingerHoldGestureActionLabel
        fourFingerHoldGestureAction = profile.fourFingerHoldGestureAction ?? GlassToKeySettings.fourFingerHoldGestureActionLabel
        outerCornersHoldGestureAction = profile.outerCornersHoldGestureAction ?? GlassToKeySettings.outerCornersHoldGestureActionLabel
        innerCornersHoldGestureAction = profile.innerCornersHoldGestureAction ?? GlassToKeySettings.innerCornersHoldGestureActionLabel
        leftEdgeUpGestureAction = profile.leftEdgeUpGestureAction ?? GlassToKeySettings.leftEdgeUpGestureActionLabel
        leftEdgeDownGestureAction = profile.leftEdgeDownGestureAction ?? GlassToKeySettings.leftEdgeDownGestureActionLabel
        rightEdgeUpGestureAction = profile.rightEdgeUpGestureAction ?? GlassToKeySettings.rightEdgeUpGestureActionLabel
        rightEdgeDownGestureAction = profile.rightEdgeDownGestureAction ?? GlassToKeySettings.rightEdgeDownGestureActionLabel
        topEdgeLeftGestureAction = profile.topEdgeLeftGestureAction ?? GlassToKeySettings.topEdgeLeftGestureActionLabel
        topEdgeRightGestureAction = profile.topEdgeRightGestureAction ?? GlassToKeySettings.topEdgeRightGestureActionLabel
        bottomEdgeLeftGestureAction = profile.bottomEdgeLeftGestureAction ?? GlassToKeySettings.bottomEdgeLeftGestureActionLabel
        bottomEdgeRightGestureAction = profile.bottomEdgeRightGestureAction ?? GlassToKeySettings.bottomEdgeRightGestureActionLabel
        threeFingerSwipeLeftGestureAction = profile.threeFingerSwipeLeftGestureAction ?? GlassToKeySettings.threeFingerSwipeLeftGestureActionLabel
        threeFingerSwipeRightGestureAction = profile.threeFingerSwipeRightGestureAction ?? GlassToKeySettings.threeFingerSwipeRightGestureActionLabel
        threeFingerSwipeUpGestureAction = profile.threeFingerSwipeUpGestureAction ?? GlassToKeySettings.threeFingerSwipeUpGestureActionLabel
        threeFingerSwipeDownGestureAction = profile.threeFingerSwipeDownGestureAction ?? GlassToKeySettings.threeFingerSwipeDownGestureActionLabel
        fourFingerSwipeLeftGestureAction = profile.fourFingerSwipeLeftGestureAction ?? GlassToKeySettings.fourFingerSwipeLeftGestureActionLabel
        fourFingerSwipeRightGestureAction = profile.fourFingerSwipeRightGestureAction ?? GlassToKeySettings.fourFingerSwipeRightGestureActionLabel
        fourFingerSwipeUpGestureAction = profile.fourFingerSwipeUpGestureAction ?? GlassToKeySettings.fourFingerSwipeUpGestureActionLabel
        fourFingerSwipeDownGestureAction = profile.fourFingerSwipeDownGestureAction ?? GlassToKeySettings.fourFingerSwipeDownGestureActionLabel
        fiveFingerSwipeLeftGestureAction = profile.fiveFingerSwipeLeftGestureAction ?? GlassToKeySettings.fiveFingerSwipeLeftGestureActionLabel
        fiveFingerSwipeRightGestureAction = profile.fiveFingerSwipeRightGestureAction ?? GlassToKeySettings.fiveFingerSwipeRightGestureActionLabel
        fiveFingerSwipeUpGestureAction = profile.fiveFingerSwipeUpGestureAction ?? GlassToKeySettings.fiveFingerSwipeUpGestureActionLabel
        fiveFingerSwipeDownGestureAction = profile.fiveFingerSwipeDownGestureAction ?? GlassToKeySettings.fiveFingerSwipeDownGestureActionLabel
        topLeftCornerSwipeGestureAction = profile.topLeftCornerSwipeGestureAction ?? GlassToKeySettings.topLeftCornerSwipeGestureActionLabel
        topRightCornerSwipeGestureAction = profile.topRightCornerSwipeGestureAction ?? GlassToKeySettings.topRightCornerSwipeGestureActionLabel
        bottomLeftCornerSwipeGestureAction = profile.bottomLeftCornerSwipeGestureAction ?? GlassToKeySettings.bottomLeftCornerSwipeGestureActionLabel
        bottomRightCornerSwipeGestureAction = profile.bottomRightCornerSwipeGestureAction ?? GlassToKeySettings.bottomRightCornerSwipeGestureActionLabel
        topLeftTriangleGestureAction = profile.topLeftTriangleGestureAction ?? GlassToKeySettings.topLeftTriangleGestureActionLabel
        topRightTriangleGestureAction = profile.topRightTriangleGestureAction ?? GlassToKeySettings.topRightTriangleGestureActionLabel
        bottomLeftTriangleGestureAction = profile.bottomLeftTriangleGestureAction ?? GlassToKeySettings.bottomLeftTriangleGestureActionLabel
        bottomRightTriangleGestureAction = profile.bottomRightTriangleGestureAction ?? GlassToKeySettings.bottomRightTriangleGestureActionLabel
        upperLeftCornerClickGestureAction = profile.upperLeftCornerClickGestureAction ?? GlassToKeySettings.upperLeftCornerClickGestureActionLabel
        upperRightCornerClickGestureAction = profile.upperRightCornerClickGestureAction ?? GlassToKeySettings.upperRightCornerClickGestureActionLabel
        lowerLeftCornerClickGestureAction = profile.lowerLeftCornerClickGestureAction ?? GlassToKeySettings.lowerLeftCornerClickGestureActionLabel
        lowerRightCornerClickGestureAction = profile.lowerRightCornerClickGestureAction ?? GlassToKeySettings.lowerRightCornerClickGestureActionLabel
        threeFingerClickGestureAction = profile.threeFingerClickGestureAction ?? GlassToKeySettings.threeFingerClickGestureActionLabel
        fourFingerClickGestureAction = profile.fourFingerClickGestureAction ?? GlassToKeySettings.fourFingerClickGestureActionLabel
        topLeftForceClickGestureAction = profile.topLeftForceClickGestureAction ?? GlassToKeySettings.topLeftForceClickGestureActionLabel
        topRightForceClickGestureAction = profile.topRightForceClickGestureAction ?? GlassToKeySettings.topRightForceClickGestureActionLabel
        bottomLeftForceClickGestureAction = profile.bottomLeftForceClickGestureAction ?? GlassToKeySettings.bottomLeftForceClickGestureActionLabel
        bottomRightForceClickGestureAction = profile.bottomRightForceClickGestureAction ?? GlassToKeySettings.bottomRightForceClickGestureActionLabel
        normalizeGestureSettings()
        storedGestureRepeatCadenceData = GestureRepeatCadenceStorage.encode(
            profile.gestureRepeatCadenceMsById
        ) ?? Data()
        storedKeySpacingByLayoutData = LayoutKeySpacingStorage.encode(
            profile.keySpacingPercentByLayout ?? [:]
        ) ?? Data()
        storedColumnSettingsData = LayoutColumnSettingsStorage.encode(
            profile.columnSettingsByLayout
        ) ?? Data()
        storedCustomButtonsData = LayoutCustomButtonStorage.encode(profile.customButtonsByLayout) ?? Data()
        storedKeyMappingsData = encodedLayoutKeyMappingsData(from: profile)
        storedKeyGeometryData = encodedLayoutKeyGeometryData(from: profile)
        applySavedSettings()
        viewModel.setAutoResyncEnabled(storedAutoResyncMissingTrackpads)
        if let activeLayer = profile.activeLayer {
            viewModel.setPersistentLayer(activeLayer)
        }
    }

    private func normalizeStoredShortcutActions() {
        let normalized = ShortcutActionLibraryStorage.decode(from: storedShortcutActionsData) ?? []
        let encoded = ShortcutActionLibraryStorage.encode(normalized) ?? Data()
        guard encoded != storedShortcutActionsData else { return }
        storedShortcutActionsData = encoded
    }

    private func saveShortcutLibraryAction(_ action: KeyAction) {
        var actions = ShortcutActionLibraryStorage.decode(from: storedShortcutActionsData) ?? []
        actions.append(action.storageLabel)
        storedShortcutActionsData = ShortcutActionLibraryStorage.encode(actions) ?? Data()
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
        saveCurrentKeySpacing()
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

    private func keySpacingPercent(
        for layout: TrackpadLayoutPreset
    ) -> Double {
        LayoutKeySpacingStorage.keySpacingPercent(
            for: layout,
            from: storedKeySpacingByLayoutData
        )
    }

    private func saveCurrentKeySpacing() {
        var map = LayoutKeySpacingStorage.decode(from: storedKeySpacingByLayoutData) ?? [:]
        map[layoutOption.rawValue] = LayoutKeySpacingDefaults.normalized(keySpacingPercent)
        storedKeySpacingByLayoutData = LayoutKeySpacingStorage.encode(map) ?? Data()
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

    private func applyKeySizePreset(
        targetKeyWidthMm: CGFloat,
        targetKeyHeightMm: CGFloat
    ) {
        guard layoutOption.allowsColumnSettings else { return }
        var updated = columnSettings
        let layoutChanged = LayoutKeySizePresetTuning.applyKeySizePreset(
            layout: layoutOption,
            columnSettings: &updated,
            trackpadWidthMm: Self.trackpadWidthMM,
            baseKeyWidthMm: Self.baseKeyWidthMM,
            baseKeyHeightMm: Self.baseKeyHeightMM,
            targetKeyWidthMm: targetKeyWidthMm,
            targetKeyHeightMm: targetKeyHeightMm,
            columnSpacingPercent: keySpacingPercent
        )
        if layoutChanged {
            columnSettings = updated
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
        guard let profile = PortableKeymapInterop.decodeBundledDefaultProfile(from: data) else {
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
        guard let profile = PortableKeymapInterop.decodeBundledDefaultProfile(from: data) else {
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

    private func bundledDefaultCustomButtons() -> [String: [Int: [CustomButton]]]? {
        guard let url = Bundle.main.url(
            forResource: "GLASSTOKEY_DEFAULT_KEYMAP",
            withExtension: "json"
        ) else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let profile = PortableKeymapInterop.decodeBundledDefaultProfile(from: data) else {
            return nil
        }
        return profile.customButtonsByLayout
    }

    private func loadCustomButtons(for layout: TrackpadLayoutPreset) -> [CustomButton] {
        if let stored = LayoutCustomButtonStorage.buttons(for: layout, from: storedCustomButtonsData) {
            return stored
        }
        if let bundled = bundledDefaultCustomButtons()?[layout.rawValue] {
            return bundled[viewModel.activeLayer] ?? []
        }
        return []
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

    private func encodedLayoutKeyMappingsData(from profile: AppKeymapProfile) -> Data {
        if let byLayout = profile.keyMappingsByLayout,
           let encoded = KeyActionMappingStore.encode(KeyActionMappingStore.normalized(byLayout)) {
            return encoded
        }
        return Data()
    }

    private func encodedLayoutKeyGeometryData(from profile: AppKeymapProfile) -> Data {
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
        @Environment(\.compactAssignmentMenu) private var compact
        let title: String
        let formatter: NumberFormatter
        let range: ClosedRange<Double>
        let sliderStep: Double
        let buttonStep: Double
        let showSlider: Bool
        let fillFieldWidth: Bool
        @Binding var value: Double

            init(
                title: String,
                value: Binding<Double>,
                formatter: NumberFormatter,
                range: ClosedRange<Double>,
                sliderStep: Double,
                buttonStep: Double? = nil,
                showSlider: Bool? = nil,
                fillFieldWidth: Bool = false
            ) {
                self.title = title
                self._value = value
                self.formatter = formatter
                self.range = range
                self.sliderStep = sliderStep
                self.buttonStep = buttonStep ?? sliderStep
                self.showSlider = showSlider ?? true
                self.fillFieldWidth = fillFieldWidth
            }

        var body: some View {
            EqualSplitFormRow {
                Text(title)
                    .font(.callout)
                    .fontWeight(.semibold)
            } field: {
                (compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 12))) {
                    if showSlider {
                        Slider(value: $value, in: range, step: sliderStep)
                            .frame(minWidth: 40, maxWidth: .infinity)
                    }
                    controlButtons
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
                .frame(minWidth: fillFieldWidth ? 0 : 60, maxWidth: fillFieldWidth ? .infinity : 60)
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

    private struct EqualSplitFormRow<Label: View, Field: View>: View {
        @Environment(\.compactAssignmentMenu) private var compact
        let label: Label
        let field: Field
        let spacing: CGFloat

        init(
            spacing: CGFloat = 12,
            @ViewBuilder label: () -> Label,
            @ViewBuilder field: () -> Field
        ) {
            self.label = label()
            self.field = field()
            self.spacing = spacing
        }

        var body: some View {
            (compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .center, spacing: spacing))) {
                label
                    .frame(maxWidth: .infinity, alignment: .leading)
                field
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
        return Text(action.pickerText)
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
            let existing = keyGeometryOverrides[key.storageKey]
            let widthScale = existing?.widthScale ?? 1.0
            let heightScale = existing?.heightScale ?? 1.0
            if abs(widthScale - 1.0) <= 0.000_01 && abs(heightScale - 1.0) <= 0.000_01 {
                keyGeometryOverrides.removeValue(forKey: key.storageKey)
            } else {
                keyGeometryOverrides[key.storageKey] = KeyGeometryOverride(
                    rotationDegrees: 0.0,
                    widthScale: widthScale,
                    heightScale: heightScale
                )
            }
            return
        }
        let existing = keyGeometryOverrides[key.storageKey]
        keyGeometryOverrides[key.storageKey] = KeyGeometryOverride(
            rotationDegrees: normalized,
            widthScale: existing?.widthScale ?? 1.0,
            heightScale: existing?.heightScale ?? 1.0
        )
    }

    private func updateKeyRotationAndSelection(
        for key: SelectedGridKey,
        rotationDegrees: Double
    ) {
        updateKeyRotation(for: key, rotationDegrees: rotationDegrees)
        refreshKeyInspectorSelection()
    }

    private func defaultKeyMapping(for label: String) -> KeyMapping? {
        if layoutOption == .touchstream, let placeholder = TouchStreamLayoutDefinition.placeholderMapping(for: label) {
            return placeholder
        }
        guard let primary = KeyActionCatalog.action(for: label) else { return nil }
        return KeyMapping(primary: primary, hold: nil)
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

/// Native segmented control with an explicit equal split across the inspector.
private struct EqualWidthInspectorPicker: NSViewRepresentable {
    @Binding var selection: String
    private static let options = ["Gestures", "Keyboard"]

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: Self.options, trackingMode: .selectOne,
            target: context.coordinator, action: #selector(Coordinator.select(_:)))
        control.segmentDistribution = .fillEqually
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setAccessibilityLabel("Gestures or Keyboard")
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        control.selectedSegment = Self.options.firstIndex(of: selection) ?? 0
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<String>
        init(selection: Binding<String>) { self.selection = selection }
        @objc func select(_ control: NSSegmentedControl) {
            guard EqualWidthInspectorPicker.options.indices.contains(control.selectedSegment) else { return }
            selection.wrappedValue = EqualWidthInspectorPicker.options[control.selectedSegment]
        }
    }
}
