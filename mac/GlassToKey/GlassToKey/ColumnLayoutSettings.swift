import CoreGraphics
import Foundation

struct ColumnLayoutSettings: Codable, Hashable {
    var scaleX: Double
    var scaleY: Double
    var offsetXPercent: Double
    var offsetYPercent: Double
    var rotationDegrees: Double
    var rowSpacingPercent: Double

    var scale: Double {
        get {
            abs(scaleX - scaleY) < 0.0001 ? scaleX : (scaleX + scaleY) * 0.5
        }
        set {
            scaleX = newValue
            scaleY = newValue
        }
    }

    init(
        scale: Double,
        offsetXPercent: Double,
        offsetYPercent: Double,
        rotationDegrees: Double = 0.0,
        rowSpacingPercent: Double = 0.0
    ) {
        self.scaleX = scale
        self.scaleY = scale
        self.offsetXPercent = offsetXPercent
        self.offsetYPercent = offsetYPercent
        self.rotationDegrees = rotationDegrees
        self.rowSpacingPercent = rowSpacingPercent
    }

    init(
        scaleX: Double,
        scaleY: Double,
        offsetXPercent: Double,
        offsetYPercent: Double,
        rotationDegrees: Double = 0.0,
        rowSpacingPercent: Double = 0.0
    ) {
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.offsetXPercent = offsetXPercent
        self.offsetYPercent = offsetYPercent
        self.rotationDegrees = rotationDegrees
        self.rowSpacingPercent = rowSpacingPercent
    }

    private enum CodingKeys: String, CodingKey {
        case scaleX = "ScaleX"
        case scaleY = "ScaleY"
        case scale = "Scale"
        case offsetXPercent = "OffsetXPercent"
        case offsetYPercent = "OffsetYPercent"
        case rotationDegrees = "RotationDegrees"
        case rowSpacingPercent = "RowSpacingPercent"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyScale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1.0
        scaleX = try container.decodeIfPresent(Double.self, forKey: .scaleX)
            ?? legacyScale
        scaleY = try container.decodeIfPresent(Double.self, forKey: .scaleY)
            ?? legacyScale
        offsetXPercent = try container.decodeIfPresent(Double.self, forKey: .offsetXPercent)
            ?? 0.0
        offsetYPercent = try container.decodeIfPresent(Double.self, forKey: .offsetYPercent)
            ?? 0.0
        rotationDegrees = try container.decodeIfPresent(Double.self, forKey: .rotationDegrees)
            ?? 0.0
        rowSpacingPercent = try container.decodeIfPresent(Double.self, forKey: .rowSpacingPercent)
            ?? 0.0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scaleX, forKey: .scaleX)
        try container.encode(scaleY, forKey: .scaleY)
        try container.encode(scale, forKey: .scale)
        try container.encode(offsetXPercent, forKey: .offsetXPercent)
        try container.encode(offsetYPercent, forKey: .offsetYPercent)
        try container.encode(rotationDegrees, forKey: .rotationDegrees)
        try container.encode(rowSpacingPercent, forKey: .rowSpacingPercent)
    }
}

enum LayoutColumnSettingsStorage {
    static func decode(from data: Data) -> [String: [ColumnLayoutSettings]]? {
        guard !data.isEmpty else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode([String: [ColumnLayoutSettings]].self, from: data)
    }

    static func encode(_ map: [String: [ColumnLayoutSettings]]) -> Data? {
        guard !map.isEmpty else { return nil }
        return try? JSONEncoder().encode(map)
    }

    static func settings(
        for layout: TrackpadLayoutPreset,
        from data: Data
    ) -> [ColumnLayoutSettings]? {
        guard let map = decode(from: data) else { return nil }
        guard let settings = map[layout.rawValue],
              settings.count == layout.columns else {
            return nil
        }
        return settings
    }
}

enum LayoutKeySpacingDefaults {
    static let defaultPercent: Double = 10.0
    static let percentRange: ClosedRange<Double> = 0.0...90.0

    static func normalized(_ value: Double) -> Double {
        min(max(value, percentRange.lowerBound), percentRange.upperBound)
    }
}

enum LayoutKeySpacingStorage {
    static func decode(from data: Data) -> [String: Double]? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode([String: Double].self, from: data)
    }

    static func encode(_ map: [String: Double]) -> Data? {
        guard !map.isEmpty else { return nil }
        return try? JSONEncoder().encode(map)
    }

    static func keySpacingPercent(
        for layout: TrackpadLayoutPreset,
        from data: Data
    ) -> Double {
        guard let map = decode(from: data),
              let value = map[layout.rawValue] else {
            return LayoutKeySpacingDefaults.defaultPercent
        }
        return LayoutKeySpacingDefaults.normalized(value)
    }
}

enum LayoutKeySizePresetTuning {
    static let mxKeyWidthMm: CGFloat = 19.05
    static let mxKeyHeightMm: CGFloat = 19.05

    static func applyKeySizePreset(
        layout: TrackpadLayoutPreset,
        columnSettings: inout [ColumnLayoutSettings],
        trackpadWidthMm: CGFloat,
        baseKeyWidthMm: CGFloat,
        baseKeyHeightMm: CGFloat,
        targetKeyWidthMm: CGFloat,
        targetKeyHeightMm: CGFloat,
        columnSpacingPercent: Double
    ) -> Bool {
        guard layout.allowsColumnSettings,
              !columnSettings.isEmpty,
              layout.columnAnchors.count == columnSettings.count,
              trackpadWidthMm > 0,
              baseKeyWidthMm > 0,
              baseKeyHeightMm > 0 else {
            return false
        }

        let targetScaleX = Double(targetKeyWidthMm / baseKeyWidthMm)
        let targetScaleY = Double(targetKeyHeightMm / baseKeyHeightMm)
        let spacingScale = clampedColumnSpacingPercent(columnSpacingPercent) / 100.0
        var changed = false
        for column in columnSettings.indices {
            if abs(columnSettings[column].scaleX - targetScaleX) > 0.000_01 {
                columnSettings[column].scaleX = targetScaleX
                changed = true
            }
            if abs(columnSettings[column].scaleY - targetScaleY) > 0.000_01 {
                columnSettings[column].scaleY = targetScaleY
                changed = true
            }

            let targetOffsetXPercent = computeHorizontalPitchOffsetPercent(
                layout: layout,
                column: column,
                trackpadWidthMm: trackpadWidthMm,
                baseKeyWidthMm: baseKeyWidthMm,
                targetKeyWidthMm: targetKeyWidthMm,
                spacingScale: spacingScale
            )
            if abs(columnSettings[column].offsetXPercent - targetOffsetXPercent) > 0.000_01 {
                columnSettings[column].offsetXPercent = targetOffsetXPercent
                changed = true
            }
        }

        return changed
    }

    private static func computeHorizontalPitchOffsetPercent(
        layout: TrackpadLayoutPreset,
        column: Int,
        trackpadWidthMm: CGFloat,
        baseKeyWidthMm: CGFloat,
        targetKeyWidthMm: CGFloat,
        spacingScale: Double
    ) -> Double {
        let anchors = layout.columnAnchors
        guard column >= 0,
              column < anchors.count,
              anchors.count > 1 else {
            return 0.0
        }
        let scaleX = Double(targetKeyWidthMm / baseKeyWidthMm)
        var targetAnchorsMm = Array(repeating: CGFloat.zero, count: anchors.count)
        targetAnchorsMm[0] = anchors[0].x
        for index in 1..<anchors.count {
            let baseGapMm = anchors[index].x - anchors[index - 1].x
            let desiredGapMm = (baseGapMm * CGFloat(scaleX)) + (targetKeyWidthMm * CGFloat(spacingScale))
            targetAnchorsMm[index] = targetAnchorsMm[index - 1] + desiredGapMm
        }

        let baselineRightMm = anchors[anchors.count - 1].x + baseKeyWidthMm
        let baselineCenterMm = (anchors[0].x + baselineRightMm) * 0.5
        let adjustedRightMm = targetAnchorsMm[targetAnchorsMm.count - 1] + targetKeyWidthMm
        let adjustedCenterMm = (targetAnchorsMm[0] + adjustedRightMm) * 0.5
        let centerOffsetMm = baselineCenterMm - adjustedCenterMm
        let targetAnchorMm = targetAnchorsMm[column] + centerOffsetMm
        return Double(((targetAnchorMm - anchors[column].x) / trackpadWidthMm) * 100.0)
    }

    private static func clampedColumnSpacingPercent(_ value: Double) -> Double {
        min(
            max(value, 0.0),
            200.0
        )
    }
}

enum ColumnLayoutDefaults {
    static let scaleRange: ClosedRange<Double> = 0.5...2.0
    static let offsetPercentRange: ClosedRange<Double> = -30.0...30.0
    static let rotationDegreesRange: ClosedRange<Double> = 0.0...360.0

    static func defaultSettings(columns: Int) -> [ColumnLayoutSettings] {
        Array(
            repeating: ColumnLayoutSettings(
                scale: 1.0,
                offsetXPercent: 0.0,
                offsetYPercent: 0.0,
                rotationDegrees: 0.0,
                rowSpacingPercent: 0.0
            ),
            count: columns
        )
    }

    static func normalizedSettings(
        _ settings: [ColumnLayoutSettings],
        columns: Int
    ) -> [ColumnLayoutSettings] {
        var resolved = settings
        if resolved.count != columns {
            resolved = defaultSettings(columns: columns)
        }
        return resolved.map { setting in
            ColumnLayoutSettings(
                scaleX: min(max(setting.scaleX, scaleRange.lowerBound), scaleRange.upperBound),
                scaleY: min(max(setting.scaleY, scaleRange.lowerBound), scaleRange.upperBound),
                offsetXPercent: min(
                    max(setting.offsetXPercent, offsetPercentRange.lowerBound),
                    offsetPercentRange.upperBound
                ),
                offsetYPercent: min(
                    max(setting.offsetYPercent, offsetPercentRange.lowerBound),
                    offsetPercentRange.upperBound
                ),
                rotationDegrees: min(
                    max(setting.rotationDegrees, rotationDegreesRange.lowerBound),
                    rotationDegreesRange.upperBound
                ),
                rowSpacingPercent: setting.rowSpacingPercent
            )
        }
    }
}
