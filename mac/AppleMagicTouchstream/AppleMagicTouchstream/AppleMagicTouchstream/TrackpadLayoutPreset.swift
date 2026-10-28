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

/// Traced in 260×196 pixel coordinates from the supplied full_layout.gif.
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
    static let left: [[Key]] = [
        [Key("Esc",9.60,16.36,47.38,23.71,0.36), Key("1",62.14,13.28,25.00,24.13,-6.72), Key("2",92.14,9.21,24.54,24.19,-6.17), Key("3",121.52,6.56,25.06,23.90,0.64), Key("4",151.50,7.68,25.02,24.18,1.85), Key("5",180.49,9.86,24.05,24.00,2.38), Key("F1",211.53,7.78,19.00,18.74,-1.65), Key("F2",234.52,7.12,19.02,18.80,-2.87)],
        [Key("Tab",10.24,45.14,49.00,24.19,-2.22), Key("Q",64.45,41.77,24.90,24.22,-7.08), Key("W",94.38,37.67,24.43,24.34,-6.94), Key("E",123.49,35.63,25.04,23.72,1.21), Key("R",153.49,36.66,24.02,23.72,2.34), Key("T",182.30,38.68,23.20,23.65,0.55), Key("Scroll Lock",215.21,29.49,15.45,19.74,-7.16), Key("F3",234.49,29.56,19.05,18.89,0.03)],
        [Key("Caps Lock",8.72,74.77,25.01,24.19,-3.38), Key("`",38.77,73.68,24.76,23.71,0.50), Key("A",68.20,70.29,24.63,24.40,-8.11), Key("S",97.67,66.29,24.23,24.39,-8.41), Key("D",126.86,63.74,24.25,24.41,-5.87), Key("F",155.86,65.15,23.63,23.66,0.80), Key("G",184.29,67.31,23.66,23.87,-0.30), Key("F4",234.50,52.46,18.98,18.92,0.32)],
        [Key("Shift",10.74,102.41,58.31,23.95,-1.64), Key("Z",74.09,98.82,23.30,24.30,-9.12), Key("X",102.36,94.67,24.52,24.42,-8.42), Key("C",131.12,92.66,24.46,23.67,-0.07), Key("V",160.03,93.51,22.31,24.03,-2.60), Key("B",187.15,95.72,23.58,23.91,-0.46), Key("F5",234.60,75.15,18.95,18.79,-3.46), Key("F6",236.60,97.87,16.68,19.01,-5.98)],
        [Key("Ctrl",9.10,132.53,35.77,23.64,0.26), Key("Hand",50.52,132.60,32.55,23.62,1.04), Key("Alt",89.52,132.63,34.05,23.58,1.66), Key("PageUp",128.54,132.61,25.00,23.75,1.14), Key("Back",166.82,138.21,81.76,34.93,-30.49)],
        [Key("Popup",10.67,161.18,24.90,24.51,-1.92), Key("Insert",40.70,161.21,24.74,24.30,-1.53), Key("Home",71.02,161.32,24.39,24.20,-1.82), Key("End",100.61,160.55,24.94,24.79,0.43), Key("PageDown",130.61,161.19,24.54,24.33,-2.23), Key("Delete",221.04,171.53,37.48,22.70,-2.01)]
    ]
    static let right: [[Key]] = [
        [Key("F8",7.49,7.60,19.03,18.58,1.85), Key("F7",30.51,7.78,19.03,18.82,1.82), Key("6",55.52,8.81,22.87,24.23,-2.82), Key("7",83.46,7.10,23.98,24.30,-2.26), Key("8",112.51,6.62,26.05,23.98,1.81), Key("9",143.35,9.59,24.19,24.51,3.66), Key("0",172.42,14.50,24.12,24.05,3.56), Key("-",201.43,16.58,22.93,24.01,-0.26), Key("=",229.47,16.56,23.97,24.30,1.66)],
        [Key("F9",7.56,29.63,18.96,18.88,0.38), Key("Num Lock",30.19,30.52,17.57,18.22,2.42), Key("Y",56.52,37.35,21.89,24.24,-1.60), Key("U",83.48,35.88,24.91,24.41,-3.21), Key("I",113.50,35.61,25.00,23.91,0.72), Key("O",143.25,38.50,24.29,24.08,3.49), Key("P",172.47,43.39,23.50,24.04,3.98), Key("[",200.47,45.50,23.60,23.99,1.29), Key("]",229.15,45.60,23.81,24.61,3.78)],
        [Key("F10",7.51,52.52,18.99,18.90,0.48), Key("H",57.58,66.37,22.60,24.26,-2.47), Key("J",84.59,64.83,23.90,24.33,-3.46), Key("K",113.51,64.01,26.04,24.27,2.08), Key("L",143.74,67.07,23.63,24.82,0.54), Key(";",172.75,71.32,22.52,25.49,-0.39), Key("'",200.45,73.51,22.99,24.37,0.84), Key("\\",228.54,74.54,23.95,24.09,0.26)],
        [Key("F11",7.47,75.58,19.03,18.63,1.62), Key("N",58.81,95.20,22.56,24.33,-3.16), Key("M",86.36,93.61,23.77,24.40,-4.23), Key(",",114.51,92.65,25.04,24.42,1.95), Key(".",143.88,96.08,24.18,24.11,6.36), Key("/",172.75,100.28,22.52,25.49,-0.38), Key("Shift",201.52,102.86,51.04,23.74,2.43)],
        [Key("F12",7.30,98.27,17.60,17.58,-0.93), Key("Space",13.81,140.18,86.46,34.65,30.53), Key("Up",142.20,132.53,24.33,23.96,1.33), Key("Alt",171.25,132.47,24.25,23.99,0.91), Key("Hand",200.26,132.48,24.27,24.00,0.89), Key("Ctrl",229.26,132.48,24.27,24.00,0.89)],
        [Key("Ret",0.48,171.15,44.24,23.37,0.51), Key("Left",112.26,161.49,24.25,24.03,0.66), Key("Down",141.26,161.48,24.27,24.00,0.89), Key("Right",170.51,161.51,24.37,24.00,0.83), Key("Print Screen",199.51,161.51,24.37,24.00,0.83), Key("Pause",228.88,161.43,24.62,24.05,0.96)]
    ]

    static func rows(for side: TrackpadSide) -> [[Key]] { side == .left ? left : right }

    static func placeholderMapping(for label: String) -> KeyMapping? {
        guard ["Hand", "Caps Lock", "Scroll Lock", "Num Lock", "Popup", "Print Screen", "Pause"].contains(label) else { return nil }
        return KeyMapping(primary: KeyAction(label: label, keyCode: UInt16.max, flags: 0, kind: .none), hold: nil)
    }
}
