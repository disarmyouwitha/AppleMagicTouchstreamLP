import CoreGraphics

enum TrackpadLayoutPreset: String, CaseIterable, Identifiable {
    case blank = "Blank"
    case sixByThree = "6x3"
    case sixByFour = "6x4"
    case fiveByThree = "5x3"
    case fiveByFour = "5x4"
    case mobileOrtho12x4 = "mobile-ortho-12x4"
    case mobile = "mobile"

    static let allCases: [TrackpadLayoutPreset] = [
        .blank,
        .sixByThree,
        .sixByFour,
        .fiveByThree,
        .fiveByFour,
        .mobileOrtho12x4,
        .mobile
    ]

    static let selectableCases: [TrackpadLayoutPreset] = [
        .blank,
        .sixByThree,
        .sixByFour,
        .fiveByThree,
        .fiveByFour,
        .mobileOrtho12x4
    ]

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blank:
            return rawValue
        case .mobileOrtho12x4:
            return "Planck"
        case .mobile:
            return "Mobile"
        default:
            return rawValue
        }
    }

    var columns: Int {
        switch self {
        case .sixByThree, .sixByFour:
            return 6
        case .fiveByThree, .fiveByFour:
            return 5
        case .mobileOrtho12x4:
            return 12
        case .mobile:
            return 10
        case .blank:
            return 0
        }
    }

    var rows: Int {
        switch self {
        case .sixByThree, .fiveByThree:
            return 3
        case .sixByFour, .fiveByFour, .mobileOrtho12x4, .mobile:
            return 4
        case .blank:
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
        case .fiveByThree:
            return Self.columnAnchors5FromSixTakeFirst
        case .fiveByFour:
            return Self.columnAnchors5FromSixTakeFirst
        case .mobileOrtho12x4:
            return Self.columnAnchors12
        case .mobile:
            return Self.columnAnchors10
        case .blank:
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
        case .mobileOrtho12x4:
            return Self.rightLabels12x4
        case .mobile:
            return Self.rightLabelsMobile
        case .blank:
            return []
        }
    }

    var leftLabels: [[String]] {
        switch self {
        case .mobileOrtho12x4, .mobile:
            return []
        default:
            return Self.mirrored(rightLabels)
        }
    }

    var blankLeftSide: Bool {
        switch self {
        case .mobileOrtho12x4, .mobile:
            return true
        default:
            return false
        }
    }

    var allowsColumnSettings: Bool {
        switch self {
        case .mobile:
            return false
        default:
            return hasGrid
        }
    }

    static func resolveByName(_ name: String?) -> TrackpadLayoutPreset? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        switch trimmed.lowercased() {
        case "blank", "none":
            return .blank
        case "mobile-ortho-12x4", "mobile ortho 12x4":
            return .mobileOrtho12x4
        default:
            return allCases.first { $0.rawValue.caseInsensitiveCompare(trimmed) == .orderedSame }
        }
    }

    static func resolveByNameOrDefault(_ name: String?) -> TrackpadLayoutPreset {
        resolveByName(name) ?? .sixByThree
    }

    var allowHoldBindings: Bool {
        true
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

    private static let columnAnchors5FromSixDropFirst: [CGPoint] = Array(columnAnchors6.suffix(5))
    private static let columnAnchors5FromSixTakeFirst: [CGPoint] = Array(columnAnchors6.prefix(5))

    private static let columnAnchors12: [CGPoint] = [
        CGPoint(x: 6.0, y: 10.0),
        CGPoint(x: 18.0, y: 10.0),
        CGPoint(x: 30.0, y: 10.0),
        CGPoint(x: 42.0, y: 10.0),
        CGPoint(x: 54.0, y: 10.0),
        CGPoint(x: 66.0, y: 10.0),
        CGPoint(x: 78.0, y: 10.0),
        CGPoint(x: 90.0, y: 10.0),
        CGPoint(x: 102.0, y: 10.0),
        CGPoint(x: 114.0, y: 10.0),
        CGPoint(x: 126.0, y: 10.0),
        CGPoint(x: 138.0, y: 10.0)
    ]

    private static let columnAnchors10: [CGPoint] = [
        CGPoint(x: 8.0, y: 10.0),
        CGPoint(x: 22.0, y: 10.0),
        CGPoint(x: 36.0, y: 10.0),
        CGPoint(x: 50.0, y: 10.0),
        CGPoint(x: 64.0, y: 10.0),
        CGPoint(x: 78.0, y: 10.0),
        CGPoint(x: 92.0, y: 10.0),
        CGPoint(x: 106.0, y: 10.0),
        CGPoint(x: 120.0, y: 10.0),
        CGPoint(x: 134.0, y: 10.0)
    ]

    private static let rightLabels6x3: [[String]] = [
        ["Y", "U", "I", "O", "P", "Back"],
        ["H", "J", "K", "L", ";", "Ret"],
        ["N", "M", ",", ".", "/", "Ret"]
    ]

    private static let rightLabels6x4: [[String]] = [
        ["6", "7", "8", "9", "0", "Back"],
        ["Y", "U", "I", "O", "P", "]"],
        ["H", "J", "K", "L", ";", "Ret"],
        ["N", "M", ",", ".", "/", "Ret"]
    ]

    private static let rightLabels12x4: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "Back"],
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'", "Ret"],
        ["Z", "X", "C", "V", "B", "N", "M", ",", ".", "/", "Shift", "Space"]
    ]

    private static let rightLabelsMobile: [[String]] = [
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L", "Ret"],
        ["Z", "X", "C", "V", "B", "N", "M", ",", ".", "Back"],
        ["Space"]
    ]
}
