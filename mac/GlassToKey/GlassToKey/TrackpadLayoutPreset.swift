import CoreGraphics

enum TrackpadLayoutPreset: String, CaseIterable, Identifiable {
    case none = "None"
    case sixByThree = "6x3"
    case sixByFour = "6x4"
    case fiveByThree = "5x3"
    case fiveByFour = "5x4"
    case mobile = "Mobile QWERTY"

    var id: String { rawValue }

    var columns: Int {
        switch self {
        case .sixByThree, .sixByFour:
            return 6
        case .fiveByThree, .fiveByFour:
            return 5
        case .mobile, .none:
            return 0
        }
    }

    var rows: Int {
        switch self {
        case .sixByThree, .fiveByThree:
            return 3
        case .sixByFour, .fiveByFour:
            return 4
        case .mobile, .none:
            return 0
        }
    }

    var hasGrid: Bool {
        columns > 0 && rows > 0
    }

    var columnAnchors: [CGPoint] {
        switch self {
        case .sixByThree, .sixByFour:
            return Self.columnAnchors6
        case .fiveByThree, .fiveByFour:
            return Self.columnAnchors5
        case .mobile, .none:
            return []
        }
    }

    var rightLabels: [[String]] {
        switch self {
        case .sixByThree:
            return Self.rightLabels6x3
        case .sixByFour:
            return Self.rightLabels6x4
        case .fiveByThree:
            return Self.rightLabels6x3.map { Array($0.prefix(self.columns)) }
        case .fiveByFour:
            return Self.rightLabels6x4.map { Array($0.prefix(self.columns)) }
        case .mobile:
            return MobileLayoutDefinition.labelMatrix
        case .none:
            return []
        }
    }

    var leftLabels: [[String]] {
        switch self {
        case .mobile:
            return []
        default:
            return Self.mirrored(rightLabels)
        }
    }

    private static func mirrored(_ labels: [[String]]) -> [[String]] {
        labels.map { Array($0.reversed()) }
    }

    private static let columnAnchors6: [CGPoint] = [
        CGPoint(x: 35.0, y: 20.9),
        CGPoint(x: 53.0, y: 19.2),
        CGPoint(x: 71.0, y: 17.5),
        CGPoint(x: 89.0, y: 19.2),
        CGPoint(x: 107.0, y: 22.6),
        CGPoint(x: 125.0, y: 22.6)
    ]

    private static let columnAnchors5: [CGPoint] = Array(columnAnchors6.prefix(5))

    private static let rightLabels6x3: [[String]] = [
        ["Y", "U", "I", "O", "P", "Back"],
        ["H", "J", "K", "L", ";", "Ret"],
        ["N", "M", ",", ".", "/", "Ret"]
    ]

    private static let rightLabels6x4: [[String]] = [
        ["Y", "U", "I", "O", "P", "Back"],
        ["H", "J", "K", "L", ";", "Ret"],
        ["N", "M", ",", ".", "/", "Ret"],
        ["Ctrl", "Option", "Cmd", "Space", "Cmd", "Option"]
    ]
}
