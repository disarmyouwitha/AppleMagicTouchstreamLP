import CoreGraphics

struct MobileLayoutRow {
    let labels: [String]
    let widthMultipliers: [CGFloat]
    let staggerOffset: CGFloat
}

enum MobileLayoutDefinition {
    static let rows: [MobileLayoutRow] = [
        MobileLayoutRow(
            labels: ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
            widthMultipliers: Array(repeating: 1.0, count: 10),
            staggerOffset: 0.0
        ),
        MobileLayoutRow(
            labels: ["A", "S", "D", "F", "G", "H", "J", "K", "L", ";"],
            widthMultipliers: Array(repeating: 1.0, count: 10),
            staggerOffset: -4.0
        ),
        MobileLayoutRow(
            labels: ["Z", "X", "C", "V", "B", "N", "M", ",", ".", "/"],
            widthMultipliers: Array(repeating: 1.0, count: 10),
            staggerOffset: 4.0
        ),
        MobileLayoutRow(
            labels: ["Shift", "Space", "Return"],
            widthMultipliers: [1.5, 4.0, 1.5],
            staggerOffset: 0.0
        )
    ]

    static var labelMatrix: [[String]] {
        rows.map { $0.labels }
    }
}
