import Foundation

struct ColumnLayoutSettings: Codable, Hashable {
    var scale: Double
    var offsetXPercent: Double
    var offsetYPercent: Double
    var rowSpacingPercent: Double

    init(
        scale: Double,
        offsetXPercent: Double,
        offsetYPercent: Double,
        rowSpacingPercent: Double = 0.0
    ) {
        self.scale = scale
        self.offsetXPercent = offsetXPercent
        self.offsetYPercent = offsetYPercent
        self.rowSpacingPercent = rowSpacingPercent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scale = try container.decode(Double.self, forKey: .scale)
        offsetXPercent = try container.decode(Double.self, forKey: .offsetXPercent)
        offsetYPercent = try container.decode(Double.self, forKey: .offsetYPercent)
        rowSpacingPercent = try container.decodeIfPresent(Double.self, forKey: .rowSpacingPercent) ?? 0.0
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

enum ColumnLayoutDefaults {
    static let scaleRange: ClosedRange<Double> = 0.5...2.0
    static let offsetPercentRange: ClosedRange<Double> = -30.0...30.0
    static let rowSpacingPercentRange: ClosedRange<Double> = -20.0...40.0

    static func defaultSettings(columns: Int) -> [ColumnLayoutSettings] {
        Array(
            repeating: ColumnLayoutSettings(
                scale: 1.0,
                offsetXPercent: 0.0,
                offsetYPercent: 0.0,
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
                scale: min(max(setting.scale, scaleRange.lowerBound), scaleRange.upperBound),
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
                )
            )
        }
    }
}
