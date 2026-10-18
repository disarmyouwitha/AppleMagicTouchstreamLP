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
            labels: ["A", "S", "D", "F", "G", "H", "J", "K", "L", "Ret"],
            widthMultipliers: Array(repeating: 1.0, count: 10),
            staggerOffset: -4.0
        ),
        MobileLayoutRow(
            labels: ["Z", "X", "C", "V", "B", "N", "M", ",", ".", "Back"],
            widthMultipliers: Array(repeating: 1.0, count: 10),
            staggerOffset: 4.0
        ),
        MobileLayoutRow(
            labels: ["Space"],
            widthMultipliers: [4.0],
            staggerOffset: 0.0
        )
    ]

    static var labelMatrix: [[String]] {
        rows.map { $0.labels }
    }
}
