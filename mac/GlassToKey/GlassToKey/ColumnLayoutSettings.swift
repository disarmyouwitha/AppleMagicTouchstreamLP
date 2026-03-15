import CoreGraphics
import Foundation

struct ColumnLayoutSettings: Codable, Hashable {
    var scaleX: Double
    var scaleY: Double
    var offsetXPercent: Double
    var offsetYPercent: Double
    var rowSpacingPercent: Double
    var rotationDegrees: Double

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
        rowSpacingPercent: Double = 0.0,
        rotationDegrees: Double = 0.0
    ) {
        self.scaleX = scale
        self.scaleY = scale
        self.offsetXPercent = offsetXPercent
        self.offsetYPercent = offsetYPercent
        self.rowSpacingPercent = rowSpacingPercent
        self.rotationDegrees = rotationDegrees
    }

    init(
        scaleX: Double,
        scaleY: Double,
        offsetXPercent: Double,
        offsetYPercent: Double,
        rowSpacingPercent: Double = 0.0,
        rotationDegrees: Double = 0.0
    ) {
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.offsetXPercent = offsetXPercent
        self.offsetYPercent = offsetYPercent
        self.rowSpacingPercent = rowSpacingPercent
        self.rotationDegrees = rotationDegrees
    }

    private enum CodingKeys: String, CodingKey {
        case scaleX
        case scaleY
        case scale
        case offsetXPercent
        case offsetYPercent
        case rowSpacingPercent
        case rotationDegrees
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyScale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1.0
        scaleX = try container.decodeIfPresent(Double.self, forKey: .scaleX) ?? legacyScale
        scaleY = try container.decodeIfPresent(Double.self, forKey: .scaleY) ?? legacyScale
        offsetXPercent = try container.decodeIfPresent(Double.self, forKey: .offsetXPercent) ?? 0.0
        offsetYPercent = try container.decodeIfPresent(Double.self, forKey: .offsetYPercent) ?? 0.0
        rowSpacingPercent = try container.decodeIfPresent(Double.self, forKey: .rowSpacingPercent) ?? 0.0
        rotationDegrees = try container.decodeIfPresent(Double.self, forKey: .rotationDegrees) ?? 0.0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scaleX, forKey: .scaleX)
        try container.encode(scaleY, forKey: .scaleY)
        try container.encode(scale, forKey: .scale)
        try container.encode(offsetXPercent, forKey: .offsetXPercent)
        try container.encode(offsetYPercent, forKey: .offsetYPercent)
        try container.encode(rowSpacingPercent, forKey: .rowSpacingPercent)
        try container.encode(rotationDegrees, forKey: .rotationDegrees)
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

enum LayoutKeyPaddingDefaults {
    static let defaultPercent: Double = 10.0
    static let percentRange: ClosedRange<Double> = 0.0...90.0

    static func normalized(_ value: Double) -> Double {
        min(max(value, percentRange.lowerBound), percentRange.upperBound)
    }
}

enum LayoutKeyPaddingStorage {
    static func decode(from data: Data) -> [String: Double]? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode([String: Double].self, from: data)
    }

    static func encode(_ map: [String: Double]) -> Data? {
        guard !map.isEmpty else { return nil }
        return try? JSONEncoder().encode(map)
    }

    static func keyPaddingPercent(
        for layout: TrackpadLayoutPreset,
        from data: Data
    ) -> Double {
        guard let map = decode(from: data),
              let value = map[layout.rawValue] else {
            return LayoutKeyPaddingDefaults.defaultPercent
        }
        return LayoutKeyPaddingDefaults.normalized(value)
    }
}

enum LayoutKeySizePresetTuning {
    static let mxKeyWidthMm: CGFloat = 19.05
    static let mxKeyHeightMm: CGFloat = 19.05

    static func recommendedPaddingPercentForMXPitch(
        targetKeyWidthMm: CGFloat,
        targetKeyHeightMm: CGFloat
    ) -> Double {
        guard targetKeyWidthMm > 0, targetKeyHeightMm > 0 else {
            return LayoutKeyPaddingDefaults.defaultPercent
        }
        let horizontal = max((Double(mxKeyWidthMm / targetKeyWidthMm) - 1.0) * 100.0, 0.0)
        let vertical = max((Double(mxKeyHeightMm / targetKeyHeightMm) - 1.0) * 100.0, 0.0)
        return LayoutKeyPaddingDefaults.normalized((horizontal + vertical) * 0.5)
    }

    static func applyKeySizePreset(
        layout: TrackpadLayoutPreset,
        columnSettings: inout [ColumnLayoutSettings],
        trackpadWidthMm: CGFloat,
        baseKeyWidthMm: CGFloat,
        baseKeyHeightMm: CGFloat,
        targetKeyWidthMm: CGFloat,
        targetKeyHeightMm: CGFloat,
        keyPaddingPercent: Double
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
        let targetScaleXs = Array(repeating: CGFloat(targetScaleX), count: columnSettings.count)
        let baselineAnchorsMm = scaledColumnAnchorsMM(layout.columnAnchors, columnScaleXs: targetScaleXs)
        let targetAnchorsMm = desiredPitchAnchorsMM(
            layout.columnAnchors,
            baseKeyWidthMm: baseKeyWidthMm,
            targetKeyWidthMm: targetKeyWidthMm,
            targetScaleX: CGFloat(targetScaleX),
            keyPaddingPercent: keyPaddingPercent
        )

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

            let targetOffsetXPercent = Double(
                ((targetAnchorsMm[column].x - baselineAnchorsMm[column].x) / trackpadWidthMm) * 100.0
            )
            if abs(columnSettings[column].offsetXPercent - targetOffsetXPercent) > 0.000_01 {
                columnSettings[column].offsetXPercent = targetOffsetXPercent
                changed = true
            }
        }

        return changed
    }

    private static func desiredPitchAnchorsMM(
        _ anchors: [CGPoint],
        baseKeyWidthMm: CGFloat,
        targetKeyWidthMm: CGFloat,
        targetScaleX: CGFloat,
        keyPaddingPercent: Double
    ) -> [CGPoint] {
        guard anchors.count > 1 else { return anchors }
        let spacingScale = CGFloat(LayoutKeyPaddingDefaults.normalized(keyPaddingPercent) / 100.0)
        var resolved = anchors
        resolved[0] = anchors[0]

        for index in 1..<anchors.count {
            let baseGapMm = anchors[index].x - anchors[index - 1].x
            let desiredGapMm = (baseGapMm * targetScaleX) + (targetKeyWidthMm * spacingScale)
            resolved[index].x = resolved[index - 1].x + desiredGapMm
        }

        let baselineRightMm = anchors[anchors.count - 1].x + baseKeyWidthMm
        let baselineCenterMm = (anchors[0].x + baselineRightMm) * 0.5
        let adjustedRightMm = resolved[resolved.count - 1].x + targetKeyWidthMm
        let adjustedCenterMm = (resolved[0].x + adjustedRightMm) * 0.5
        let centerOffsetMm = baselineCenterMm - adjustedCenterMm

        return resolved.map { anchor in
            CGPoint(x: anchor.x + centerOffsetMm, y: anchor.y)
        }
    }

    private static func scaledColumnAnchorsMM(
        _ anchors: [CGPoint],
        columnScaleXs: [CGFloat]
    ) -> [CGPoint] {
        guard let originX = anchors.first?.x else { return anchors }
        return anchors.enumerated().map { index, anchor in
            let scale = columnScaleXs.indices.contains(index) ? columnScaleXs[index] : 1.0
            let offsetX = anchor.x - originX
            return CGPoint(x: originX + offsetX * scale, y: anchor.y)
        }
    }
}

enum ColumnLayoutDefaults {
    static let scaleRange: ClosedRange<Double> = 0.5...2.0
    static let offsetPercentRange: ClosedRange<Double> = -30.0...30.0
    static let rowSpacingPercentRange: ClosedRange<Double> = -20.0...40.0
    static let rotationDegreesRange: ClosedRange<Double> = 0.0...360.0

    static func defaultSettings(columns: Int) -> [ColumnLayoutSettings] {
        Array(
            repeating: ColumnLayoutSettings(
                scale: 1.0,
                offsetXPercent: 0.0,
                offsetYPercent: 0.0,
                rowSpacingPercent: 0.0,
                rotationDegrees: 0.0
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
                rowSpacingPercent: min(
                    max(setting.rowSpacingPercent, rowSpacingPercentRange.lowerBound),
                    rowSpacingPercentRange.upperBound
                ),
                rotationDegrees: min(
                    max(setting.rotationDegrees, rotationDegreesRange.lowerBound),
                    rotationDegreesRange.upperBound
                )
            )
        }
    }
}
