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
        [Key("Esc",10,18,42,25), Key("1",63,14,22,26), Key("2",91,10,23,27), Key("3",120,8,24,27), Key("4",149,10,24,26), Key("5",179,12,24,26), Key("F1",210,9,21,23), Key("F2",234,7,21,23)],
        [Key("Tab",11,49,45,26), Key("Q",66,43,24,26), Key("W",94,40,24,26), Key("E",123,38,24,26), Key("R",152,40,24,26), Key("T",182,43,24,26), Key("Scroll Lock",210,36,21,24), Key("F3",234,34,21,23)],
        [Key("Caps Lock",11,78,23,24), Key("`",37,76,23,24), Key("A",68,72,25,28), Key("S",98,69,24,28), Key("D",127,68,24,28), Key("F",156,70,24,28), Key("G",185,73,24,28), Key("F4",234,59,21,23)],
        [Key("Shift",12,108,57,25), Key("Z",76,102,24,28), Key("X",106,100,24,28), Key("C",135,99,24,28), Key("V",164,102,24,28), Key("B",194,104,24,28), Key("F5",234,84,21,23), Key("F6",234,109,21,23)],
        [Key("Ctrl",10,138,31,24), Key("Hand",46,136,35,26), Key("Alt",86,136,34,25), Key("PageUp",124,135,25,26), Key("Back",165,144,76,28,-38)],
        [Key("Popup",8,164,27,23), Key("Insert",40,164,25,23), Key("Home",69,164,26,23), Key("End",101,164,25,23), Key("PageDown",130,164,24,23), Key("Delete",221,178,37,17)]
    ]
    static let right: [[Key]] = [
        [Key("F8",5,7,22,23), Key("F7",31,7,24,22), Key("6",59,9,25,26), Key("7",87,10,25,26), Key("8",117,12,25,25), Key("9",146,14,26,26), Key("0",176,16,24,26), Key("-",204,18,24,26), Key("=",234,20,24,26)],
        [Key("F9",7,33,23,22), Key("Num Lock",32,31,23,23), Key("Y",57,39,27,26), Key("U",86,41,27,26), Key("I",116,42,27,26), Key("O",145,45,27,26), Key("P",175,47,27,26), Key("[",204,49,27,26), Key("]",234,50,24,26)],
        [Key("F10",8,58,24,22), Key("H",58,68,27,25), Key("J",88,70,27,25), Key("K",117,71,27,25), Key("L",146,74,27,25), Key(";",177,76,27,25), Key("'",207,77,26,25), Key("\\",235,79,23,25)],
        [Key("F11",8,82,24,23), Key("N",59,96,27,26), Key("M",89,97,27,26), Key(",",118,99,27,26), Key(".",149,101,27,26), Key("/",179,104,26,26), Key("Shift",207,105,51,23)],
        [Key("F12",8,107,24,24), Key("Space",27,141,76,28,35), Key("Up",153,134,22,24), Key("Alt",180,135,25,24), Key("Hand",206,135,24,24), Key("Ctrl",233,137,25,24)],
        [Key("Ret",4,175,32,19), Key("Left",104,163,24,24), Key("Down",133,161,23,24), Key("Right",161,162,24,24), Key("Print Screen",190,163,29,24), Key("Pause",223,163,33,24)]
    ]

    static func rows(for side: TrackpadSide) -> [[Key]] { side == .left ? left : right }

    static func placeholderMapping(for label: String) -> KeyMapping? {
        guard ["Hand", "Caps Lock", "Scroll Lock", "Num Lock", "Popup", "Print Screen", "Pause"].contains(label) else { return nil }
        return KeyMapping(primary: KeyAction(label: label, keyCode: UInt16.max, flags: 0, kind: .none), hold: nil)
    }
}
