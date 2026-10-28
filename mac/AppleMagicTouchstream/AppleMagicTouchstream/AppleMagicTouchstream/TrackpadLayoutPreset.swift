import CoreGraphics

enum TrackpadLayoutPreset: String, CaseIterable, Identifiable {
    case blank = "Blank"
    case sixByThree = "6x3"
    case sixByFour = "6x4"
    case fiveByThree = "5x3"
    case fiveByFour = "5x4"
    case mobileOrtho12x4 = "mobile-ortho-12x4"
    case mobile = "mobile"
    case touchstream = "TouchStream"

    static let allCases: [TrackpadLayoutPreset] = [
        .touchstream,
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
        .mobileOrtho12x4,
        .touchstream
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
        case .touchstream:
            return 9
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
        case .touchstream:
            return 6
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
        case .touchstream:
            return (0..<9).map { CGPoint(x: CGFloat($0) * 16, y: 0) }
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
        case .touchstream:
            return TouchStreamLayoutDefinition.right.map { $0.map(\.label) }
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
        case .touchstream:
            return TouchStreamLayoutDefinition.left.map { $0.map(\.label) }
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
        case .mobile, .touchstream:
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

/// Traced from LHS_TOUCHSTREAM_layout.png (1320×940) and
/// RHS_TOUCHSTREAM_layout.png (1314×936), expressed in a 260×196 coordinate space.
/// Independent sides preserve the asymmetric function/navigation/thumb clusters.
/// Rounded/oval printed keys use editable rotated rectangular hit regions.
enum TouchStreamLayoutDefinition {
    struct Key {
        let label: String
        let rect: NormalizedRect
        init(_ label: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ angle: Double = 0) {
            self.label = label
            rect = NormalizedRect(x: x / 260, y: y / 196, width: width / 260,
                                  height: height / 196, rotationDegrees: angle)
        }
    }
    // Corner keys widen inward, retaining their original top/bottom and outer edges.
    static let left: [[Key]] = [
        [Key("Esc",0.09,10.11,50.72,27.47,-1.60), Key("1",52.03,7.35,30.58,28.45,-6.50), Key("2",83.52,3.90,30.68,29.08,-3.80), Key("3",115.82,2.29,28.36,28.57,0.00), Key("4",145.48,3.72,30.79,29.12,4.70), Key("5",176.44,7.40,32.42,28.99,6.30), Key("F1",211.35,5.63,23.64,21.89,0.00), Key("F2",236.76,5.21,23.05,22.10,0.00)],
        [Key("Tab",0.15,39.78,51.73,27.17,-1.30), Key("Q",53.28,37.64,30.33,28.23,-4.60), Key("W",84.74,34.24,29.83,28.01,-3.80), Key("E",116.02,33.15,28.56,27.52,0.00), Key("R",146.74,33.99,28.56,29.82,0.00), Key("T",176.47,38.38,32.12,28.16,5.20), Key("Scroll Lock",211.55,28.98,23.44,23.14,0.00), Key("F3",236.76,29.40,23.05,22.10,0.00)],
        [Key("Caps Lock",0.39,69.64,25.80,26.27,0.00), Key("`",27.89,69.32,26.19,26.59,-0.80), Key("A",55.00,67.25,30.24,27.69,-6.50), Key("S",86.15,63.83,29.36,27.85,-4.70), Key("D",116.51,62.64,28.55,27.34,0.50), Key("F",145.78,64.73,30.71,27.56,5.30), Key("G",176.30,68.53,32.37,27.47,5.70), Key("F4",236.56,53.59,23.24,22.10,0.00)],
        [Key("Shift",0.39,98.00,55.55,27.52,0.00), Key("Z",56.87,96.58,29.92,28.27,-6.30), Key("X",87.61,92.91,29.04,28.75,-3.20), Key("C",117.98,92.16,28.17,26.69,0.00), Key("V",146.42,94.67,30.72,26.93,5.80), Key("B",176.72,98.20,31.98,27.56,5.80), Key("F5",236.56,77.57,23.24,22.10,0.00), Key("F6",236.56,101.75,23.24,22.10,0.00)],
        [Key("Ctrl",0.39,127.82,37.23,27.11,0.00), Key("Hand",39.59,128.03,35.26,27.11,0.00), Key("Alt",76.42,127.82,37.23,27.11,0.00), Key("PageUp",115.62,127.82,29.94,27.31,0.00), Key("Back",157.01,139.92,96.84,33.57,-24.80)],
        [Key("Popup",0.59,157.01,27.58,25.86,0.00), Key("Insert",29.94,157.01,27.38,25.86,0.00), Key("Home",59.09,156.80,27.18,26.06,0.00), Key("End",88.24,156.80,26.98,26.06,0.00), Key("PageDown",117.00,157.01,28.36,25.86,0.00), Key("Delete",223.23,169.04,35.22,25.20,0.00)]
    ]
    static let right: [[Key]] = [
        [Key("F8",0.00,6.28,21.96,21.57,0.00), Key("F7",23.55,6.70,22.95,21.57,0.00), Key("6",49.30,7.12,29.65,27.26,-5.20), Key("7",79.55,3.50,29.35,27.91,-4.40), Key("8",110.35,2.25,28.81,28.28,1.40), Key("9",140.23,5.09,30.42,28.10,7.50), Key("0",170.93,9.95,30.32,27.71,6.70), Key("-",202.22,12.56,28.49,27.01,0.00), Key("=",232.30,12.15,27.50,27.22,0.00)],
        [Key("F9",0.00,29.53,22.16,21.36,0.00), Key("Num Lock",23.74,29.94,22.16,21.36,0.00), Key("Y",49.84,36.18,29.60,26.84,-5.90), Key("U",79.95,32.99,29.12,26.78,-5.10), Key("I",110.14,32.46,28.60,26.47,1.60), Key("O",139.75,34.96,29.91,26.71,7.10), Key("P",170.02,39.57,30.22,26.99,6.40), Key("[",201.43,41.67,29.09,27.22,0.00), Key("]",232.10,41.67,27.70,27.22,0.00)],
        [Key("F10",0.20,52.56,22.56,21.57,0.00), Key("H",50.32,64.96,29.09,27.56,-4.40), Key("J",80.02,61.69,29.25,27.45,-5.70), Key("K",110.25,60.41,28.40,27.80,0.90), Key("L",139.57,63.66,30.32,27.29,6.80), Key(";",169.61,68.94,30.62,27.02,6.30), Key("'",201.43,70.99,28.49,27.01,0.00), Key("\\",232.30,70.99,27.50,27.22,0.00)],
        [Key("F11",0.20,76.22,22.75,21.78,0.00), Key("N",50.56,94.82,29.44,26.94,-5.90), Key("M",80.06,91.39,29.22,27.14,-6.30), Key(",",110.27,89.97,28.38,27.38,0.80), Key(".",139.63,93.37,30.64,27.48,7.00), Key("/",170.62,97.97,29.72,27.30,5.10), Key("Shift",201.65,100.01,58.26,27.34,0.50)],
        [Key("F12",0.20,99.68,22.75,22.20,0.00), Key("Space",5.04,138.54,90.83,34.10,26.60), Key("Up",140.29,130.67,27.70,25.55,0.00), Key("Alt",169.97,130.46,28.89,25.76,0.00), Key("Hand",200.84,130.67,30.47,25.55,0.00), Key("Ctrl",233.29,130.67,26.51,25.55,0.00)],
        [Key("Ret",1.44,169.08,33.32,25.15,0.00), Key("Left",111.80,157.47,26.71,26.80,0.00), Key("Down",140.49,158.10,27.90,26.18,0.00), Key("Right",170.56,158.52,28.30,25.76,0.00), Key("Print Screen",201.04,158.31,29.28,25.97,0.00), Key("Pause",232.30,158.31,27.50,26.38,0.00)]
    ]

    static func rows(for side: TrackpadSide) -> [[Key]] { side == .left ? left : right }

    static func placeholderMapping(for label: String) -> KeyMapping? {
        guard ["Hand", "Caps Lock", "Scroll Lock", "Num Lock", "Popup", "Print Screen", "Pause"].contains(label) else { return nil }
        return KeyMapping(primary: KeyAction(label: label, keyCode: UInt16.max, flags: 0, kind: .none), hold: nil)
    }
}
