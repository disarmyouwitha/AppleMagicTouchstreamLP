import Carbon
import CoreGraphics
import Foundation

enum KeySemanticKind: UInt8 {
    case text = 1
    case boundary = 2
    case backspace = 3
    case nonText = 4
    case navigation = 5
}

struct KeySemanticEvent: Sendable {
    var timestampNs: UInt64
    var code: CGKeyCode
    var flags: CGEventFlags
    var kind: KeySemanticKind
    var ascii: UInt8
    var altAscii: UInt8

    static let empty = KeySemanticEvent(
        timestampNs: 0,
        code: 0,
        flags: [],
        kind: .nonText,
        ascii: 0,
        altAscii: 0
    )

    var boundaryLength: Int {
        kind == .boundary ? 1 : 0
    }
}

struct KeySemanticMapper {
    struct KeyStroke: Sendable {
        let code: CGKeyCode
        let flags: CGEventFlags
    }

    @inline(__always)
    private static func ascii(_ character: Character) -> UInt8 {
        guard let scalar = character.unicodeScalars.first, scalar.isASCII else { return 0 }
        return UInt8(scalar.value)
    }

    private static let unshiftedASCII: [UInt8] = {
        var map = [UInt8](repeating: 0, count: 128)
        map[Int(kVK_ANSI_A)] = ascii("a")
        map[Int(kVK_ANSI_B)] = ascii("b")
        map[Int(kVK_ANSI_C)] = ascii("c")
        map[Int(kVK_ANSI_D)] = ascii("d")
        map[Int(kVK_ANSI_E)] = ascii("e")
        map[Int(kVK_ANSI_F)] = ascii("f")
        map[Int(kVK_ANSI_G)] = ascii("g")
        map[Int(kVK_ANSI_H)] = ascii("h")
        map[Int(kVK_ANSI_I)] = ascii("i")
        map[Int(kVK_ANSI_J)] = ascii("j")
        map[Int(kVK_ANSI_K)] = ascii("k")
        map[Int(kVK_ANSI_L)] = ascii("l")
        map[Int(kVK_ANSI_M)] = ascii("m")
        map[Int(kVK_ANSI_N)] = ascii("n")
        map[Int(kVK_ANSI_O)] = ascii("o")
        map[Int(kVK_ANSI_P)] = ascii("p")
        map[Int(kVK_ANSI_Q)] = ascii("q")
        map[Int(kVK_ANSI_R)] = ascii("r")
        map[Int(kVK_ANSI_S)] = ascii("s")
        map[Int(kVK_ANSI_T)] = ascii("t")
        map[Int(kVK_ANSI_U)] = ascii("u")
        map[Int(kVK_ANSI_V)] = ascii("v")
        map[Int(kVK_ANSI_W)] = ascii("w")
        map[Int(kVK_ANSI_X)] = ascii("x")
        map[Int(kVK_ANSI_Y)] = ascii("y")
        map[Int(kVK_ANSI_Z)] = ascii("z")

        map[Int(kVK_ANSI_0)] = ascii("0")
        map[Int(kVK_ANSI_1)] = ascii("1")
        map[Int(kVK_ANSI_2)] = ascii("2")
        map[Int(kVK_ANSI_3)] = ascii("3")
        map[Int(kVK_ANSI_4)] = ascii("4")
        map[Int(kVK_ANSI_5)] = ascii("5")
        map[Int(kVK_ANSI_6)] = ascii("6")
        map[Int(kVK_ANSI_7)] = ascii("7")
        map[Int(kVK_ANSI_8)] = ascii("8")
        map[Int(kVK_ANSI_9)] = ascii("9")

        map[Int(kVK_ANSI_Minus)] = ascii("-")
        map[Int(kVK_ANSI_Equal)] = ascii("=")
        map[Int(kVK_ANSI_LeftBracket)] = ascii("[")
        map[Int(kVK_ANSI_RightBracket)] = ascii("]")
        map[Int(kVK_ANSI_Backslash)] = ascii("\\")
        map[Int(kVK_ANSI_Semicolon)] = ascii(";")
        map[Int(kVK_ANSI_Quote)] = ascii("'")
        map[Int(kVK_ANSI_Comma)] = ascii(",")
        map[Int(kVK_ANSI_Period)] = ascii(".")
        map[Int(kVK_ANSI_Slash)] = ascii("/")
        map[Int(kVK_ANSI_Grave)] = ascii("`")

        return map
    }()

    private static let shiftedASCII: [UInt8] = {
        var map = [UInt8](repeating: 0, count: 128)
        map[Int(kVK_ANSI_A)] = ascii("A")
        map[Int(kVK_ANSI_B)] = ascii("B")
        map[Int(kVK_ANSI_C)] = ascii("C")
        map[Int(kVK_ANSI_D)] = ascii("D")
        map[Int(kVK_ANSI_E)] = ascii("E")
        map[Int(kVK_ANSI_F)] = ascii("F")
        map[Int(kVK_ANSI_G)] = ascii("G")
        map[Int(kVK_ANSI_H)] = ascii("H")
        map[Int(kVK_ANSI_I)] = ascii("I")
        map[Int(kVK_ANSI_J)] = ascii("J")
        map[Int(kVK_ANSI_K)] = ascii("K")
        map[Int(kVK_ANSI_L)] = ascii("L")
        map[Int(kVK_ANSI_M)] = ascii("M")
        map[Int(kVK_ANSI_N)] = ascii("N")
        map[Int(kVK_ANSI_O)] = ascii("O")
        map[Int(kVK_ANSI_P)] = ascii("P")
        map[Int(kVK_ANSI_Q)] = ascii("Q")
        map[Int(kVK_ANSI_R)] = ascii("R")
        map[Int(kVK_ANSI_S)] = ascii("S")
        map[Int(kVK_ANSI_T)] = ascii("T")
        map[Int(kVK_ANSI_U)] = ascii("U")
        map[Int(kVK_ANSI_V)] = ascii("V")
        map[Int(kVK_ANSI_W)] = ascii("W")
        map[Int(kVK_ANSI_X)] = ascii("X")
        map[Int(kVK_ANSI_Y)] = ascii("Y")
        map[Int(kVK_ANSI_Z)] = ascii("Z")

        map[Int(kVK_ANSI_0)] = ascii(")")
        map[Int(kVK_ANSI_1)] = ascii("!")
        map[Int(kVK_ANSI_2)] = ascii("@")
        map[Int(kVK_ANSI_3)] = ascii("#")
        map[Int(kVK_ANSI_4)] = ascii("$")
        map[Int(kVK_ANSI_5)] = ascii("%")
        map[Int(kVK_ANSI_6)] = ascii("^")
        map[Int(kVK_ANSI_7)] = ascii("&")
        map[Int(kVK_ANSI_8)] = ascii("*")
        map[Int(kVK_ANSI_9)] = ascii("(")

        map[Int(kVK_ANSI_Minus)] = ascii("_")
        map[Int(kVK_ANSI_Equal)] = ascii("+")
        map[Int(kVK_ANSI_LeftBracket)] = ascii("{")
        map[Int(kVK_ANSI_RightBracket)] = ascii("}")
        map[Int(kVK_ANSI_Backslash)] = ascii("|")
        map[Int(kVK_ANSI_Semicolon)] = ascii(":")
        map[Int(kVK_ANSI_Quote)] = ascii("\"")
        map[Int(kVK_ANSI_Comma)] = ascii("<")
        map[Int(kVK_ANSI_Period)] = ascii(">")
        map[Int(kVK_ANSI_Slash)] = ascii("?")
        map[Int(kVK_ANSI_Grave)] = ascii("~")

        return map
    }()

    private static let boundaryASCII: [Bool] = {
        var map = [Bool](repeating: false, count: 128)
        map[Int(ascii(" "))] = true
        map[Int(ascii("."))] = true
        map[Int(ascii(","))] = true
        map[Int(ascii(";"))] = true
        map[Int(ascii(":"))] = true
        map[Int(ascii("!"))] = true
        map[Int(ascii("?"))] = true
        map[Int(ascii("("))] = true
        map[Int(ascii(")"))] = true
        map[Int(ascii("["))] = true
        map[Int(ascii("]"))] = true
        map[Int(ascii("{"))] = true
        map[Int(ascii("}"))] = true
        map[Int(ascii("<"))] = true
        map[Int(ascii(">"))] = true
        map[Int(ascii("/"))] = true
        map[Int(ascii("\\"))] = true
        map[Int(ascii("|"))] = true
        map[Int(ascii("`"))] = true
        map[Int(ascii("~"))] = true
        map[Int(ascii("="))] = true
        map[Int(ascii("+"))] = true
        map[Int(ascii("@"))] = true
        map[Int(ascii("#"))] = true
        map[Int(ascii("$"))] = true
        map[Int(ascii("%"))] = true
        map[Int(ascii("^"))] = true
        map[Int(ascii("&"))] = true
        map[Int(ascii("*"))] = true
        map[Int(ascii("\""))] = true
        return map
    }()

    private static let keyStrokeByASCII: [KeyStroke?] = {
        var map = [KeyStroke?](repeating: nil, count: 128)
        func set(_ ascii: Character, _ code: CGKeyCode, _ flags: CGEventFlags = []) {
            guard let scalar = ascii.unicodeScalars.first, scalar.isASCII else { return }
            map[Int(scalar.value)] = KeyStroke(code: code, flags: flags)
        }

        set("a", CGKeyCode(kVK_ANSI_A))
        set("b", CGKeyCode(kVK_ANSI_B))
        set("c", CGKeyCode(kVK_ANSI_C))
        set("d", CGKeyCode(kVK_ANSI_D))
        set("e", CGKeyCode(kVK_ANSI_E))
        set("f", CGKeyCode(kVK_ANSI_F))
        set("g", CGKeyCode(kVK_ANSI_G))
        set("h", CGKeyCode(kVK_ANSI_H))
        set("i", CGKeyCode(kVK_ANSI_I))
        set("j", CGKeyCode(kVK_ANSI_J))
        set("k", CGKeyCode(kVK_ANSI_K))
        set("l", CGKeyCode(kVK_ANSI_L))
        set("m", CGKeyCode(kVK_ANSI_M))
        set("n", CGKeyCode(kVK_ANSI_N))
        set("o", CGKeyCode(kVK_ANSI_O))
        set("p", CGKeyCode(kVK_ANSI_P))
        set("q", CGKeyCode(kVK_ANSI_Q))
        set("r", CGKeyCode(kVK_ANSI_R))
        set("s", CGKeyCode(kVK_ANSI_S))
        set("t", CGKeyCode(kVK_ANSI_T))
        set("u", CGKeyCode(kVK_ANSI_U))
        set("v", CGKeyCode(kVK_ANSI_V))
        set("w", CGKeyCode(kVK_ANSI_W))
        set("x", CGKeyCode(kVK_ANSI_X))
        set("y", CGKeyCode(kVK_ANSI_Y))
        set("z", CGKeyCode(kVK_ANSI_Z))

        set("A", CGKeyCode(kVK_ANSI_A), .maskShift)
        set("B", CGKeyCode(kVK_ANSI_B), .maskShift)
        set("C", CGKeyCode(kVK_ANSI_C), .maskShift)
        set("D", CGKeyCode(kVK_ANSI_D), .maskShift)
        set("E", CGKeyCode(kVK_ANSI_E), .maskShift)
        set("F", CGKeyCode(kVK_ANSI_F), .maskShift)
        set("G", CGKeyCode(kVK_ANSI_G), .maskShift)
        set("H", CGKeyCode(kVK_ANSI_H), .maskShift)
        set("I", CGKeyCode(kVK_ANSI_I), .maskShift)
        set("J", CGKeyCode(kVK_ANSI_J), .maskShift)
        set("K", CGKeyCode(kVK_ANSI_K), .maskShift)
        set("L", CGKeyCode(kVK_ANSI_L), .maskShift)
        set("M", CGKeyCode(kVK_ANSI_M), .maskShift)
        set("N", CGKeyCode(kVK_ANSI_N), .maskShift)
        set("O", CGKeyCode(kVK_ANSI_O), .maskShift)
        set("P", CGKeyCode(kVK_ANSI_P), .maskShift)
        set("Q", CGKeyCode(kVK_ANSI_Q), .maskShift)
        set("R", CGKeyCode(kVK_ANSI_R), .maskShift)
        set("S", CGKeyCode(kVK_ANSI_S), .maskShift)
        set("T", CGKeyCode(kVK_ANSI_T), .maskShift)
        set("U", CGKeyCode(kVK_ANSI_U), .maskShift)
        set("V", CGKeyCode(kVK_ANSI_V), .maskShift)
        set("W", CGKeyCode(kVK_ANSI_W), .maskShift)
        set("X", CGKeyCode(kVK_ANSI_X), .maskShift)
        set("Y", CGKeyCode(kVK_ANSI_Y), .maskShift)
        set("Z", CGKeyCode(kVK_ANSI_Z), .maskShift)

        set("0", CGKeyCode(kVK_ANSI_0))
        set("1", CGKeyCode(kVK_ANSI_1))
        set("2", CGKeyCode(kVK_ANSI_2))
        set("3", CGKeyCode(kVK_ANSI_3))
        set("4", CGKeyCode(kVK_ANSI_4))
        set("5", CGKeyCode(kVK_ANSI_5))
        set("6", CGKeyCode(kVK_ANSI_6))
        set("7", CGKeyCode(kVK_ANSI_7))
        set("8", CGKeyCode(kVK_ANSI_8))
        set("9", CGKeyCode(kVK_ANSI_9))

        set("!", CGKeyCode(kVK_ANSI_1), .maskShift)
        set("@", CGKeyCode(kVK_ANSI_2), .maskShift)
        set("#", CGKeyCode(kVK_ANSI_3), .maskShift)
        set("$", CGKeyCode(kVK_ANSI_4), .maskShift)
        set("%", CGKeyCode(kVK_ANSI_5), .maskShift)
        set("^", CGKeyCode(kVK_ANSI_6), .maskShift)
        set("&", CGKeyCode(kVK_ANSI_7), .maskShift)
        set("*", CGKeyCode(kVK_ANSI_8), .maskShift)
        set("(", CGKeyCode(kVK_ANSI_9), .maskShift)
        set(")", CGKeyCode(kVK_ANSI_0), .maskShift)

        set("-", CGKeyCode(kVK_ANSI_Minus))
        set("_", CGKeyCode(kVK_ANSI_Minus), .maskShift)
        set("=", CGKeyCode(kVK_ANSI_Equal))
        set("+", CGKeyCode(kVK_ANSI_Equal), .maskShift)
        set("[", CGKeyCode(kVK_ANSI_LeftBracket))
        set("{", CGKeyCode(kVK_ANSI_LeftBracket), .maskShift)
        set("]", CGKeyCode(kVK_ANSI_RightBracket))
        set("}", CGKeyCode(kVK_ANSI_RightBracket), .maskShift)
        set("\\", CGKeyCode(kVK_ANSI_Backslash))
        set("|", CGKeyCode(kVK_ANSI_Backslash), .maskShift)
        set(";", CGKeyCode(kVK_ANSI_Semicolon))
        set(":", CGKeyCode(kVK_ANSI_Semicolon), .maskShift)
        set("'", CGKeyCode(kVK_ANSI_Quote))
        set("\"", CGKeyCode(kVK_ANSI_Quote), .maskShift)
        set(",", CGKeyCode(kVK_ANSI_Comma))
        set("<", CGKeyCode(kVK_ANSI_Comma), .maskShift)
        set(".", CGKeyCode(kVK_ANSI_Period))
        set(">", CGKeyCode(kVK_ANSI_Period), .maskShift)
        set("/", CGKeyCode(kVK_ANSI_Slash))
        set("?", CGKeyCode(kVK_ANSI_Slash), .maskShift)
        set("`", CGKeyCode(kVK_ANSI_Grave))
        set("~", CGKeyCode(kVK_ANSI_Grave), .maskShift)
        set(" ", CGKeyCode(kVK_Space))
        set("\n", CGKeyCode(kVK_Return))
        set("\t", CGKeyCode(kVK_Tab))

        return map
    }()

    static func semanticEvent(
        code: CGKeyCode,
        flags: CGEventFlags,
        timestampNs: UInt64,
        altAscii: UInt8 = 0
    ) -> KeySemanticEvent? {
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            return KeySemanticEvent(
                timestampNs: timestampNs,
                code: code,
                flags: flags,
                kind: .nonText,
                ascii: 0,
                altAscii: 0
            )
        }

        if isLeftRightArrow(code) {
            return KeySemanticEvent(
                timestampNs: timestampNs,
                code: code,
                flags: flags,
                kind: .navigation,
                ascii: 0,
                altAscii: 0
            )
        }

        if code == CGKeyCode(kVK_Delete) {
            return KeySemanticEvent(
                timestampNs: timestampNs,
                code: code,
                flags: flags,
                kind: .backspace,
                ascii: 0,
                altAscii: 0
            )
        }

        if code == CGKeyCode(kVK_Return) {
            return KeySemanticEvent(
                timestampNs: timestampNs,
                code: code,
                flags: flags,
                kind: .boundary,
                ascii: ascii("\n"),
                altAscii: 0
            )
        }

        if code == CGKeyCode(kVK_Tab) {
            return KeySemanticEvent(
                timestampNs: timestampNs,
                code: code,
                flags: flags,
                kind: .boundary,
                ascii: ascii("\t"),
                altAscii: 0
            )
        }

        if code == CGKeyCode(kVK_Space) {
            return KeySemanticEvent(
                timestampNs: timestampNs,
                code: code,
                flags: flags,
                kind: .boundary,
                ascii: ascii(" "),
                altAscii: 0
            )
        }

        let index = Int(code)
        guard index >= 0 && index < unshiftedASCII.count else {
            return nil
        }

        let ascii = (flags.contains(.maskShift) || flags.contains(.maskAlphaShift))
            ? shiftedASCII[index]
            : unshiftedASCII[index]
        guard ascii != 0 else {
            if isCancelKey(code) {
                return KeySemanticEvent(
                    timestampNs: timestampNs,
                    code: code,
                    flags: flags,
                    kind: .nonText,
                    ascii: 0,
                    altAscii: 0
                )
            }
            return nil
        }

        let kind: KeySemanticKind = boundaryASCII[Int(ascii)] ? .boundary : .text
        return KeySemanticEvent(
            timestampNs: timestampNs,
            code: code,
            flags: flags,
            kind: kind,
            ascii: ascii,
            altAscii: kind == .text && altAscii != 0 && altAscii != ascii ? altAscii : 0
        )
    }

    static func asciiForKey(code: CGKeyCode, flags: CGEventFlags) -> UInt8 {
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            return 0
        }

        if code == CGKeyCode(kVK_Delete)
            || code == CGKeyCode(kVK_Return)
            || code == CGKeyCode(kVK_Tab)
            || code == CGKeyCode(kVK_Space) {
            return 0
        }

        let index = Int(code)
        guard index >= 0 && index < unshiftedASCII.count else {
            return 0
        }
        let ascii = (flags.contains(.maskShift) || flags.contains(.maskAlphaShift))
            ? shiftedASCII[index]
            : unshiftedASCII[index]
        guard ascii != 0 else { return 0 }
        if boundaryASCII[Int(ascii)] {
            return 0
        }
        return ascii
    }

    static func canTypeASCII(_ text: String) -> Bool {
        for byte in text.utf8 {
            if byte >= 128 { return false }
            if keyStrokeByASCII[Int(byte)] == nil { return false }
        }
        return true
    }

    static func keyStrokes(for text: String) -> [KeyStroke]? {
        var strokes: [KeyStroke] = []
        strokes.reserveCapacity(text.utf8.count)
        for byte in text.utf8 {
            guard byte < 128, let stroke = keyStrokeByASCII[Int(byte)] else {
                return nil
            }
            strokes.append(stroke)
        }
        return strokes
    }

    private static func isCancelKey(_ code: CGKeyCode) -> Bool {
        switch code {
        case CGKeyCode(kVK_UpArrow),
             CGKeyCode(kVK_DownArrow),
             CGKeyCode(kVK_Escape),
             CGKeyCode(kVK_Home),
             CGKeyCode(kVK_End),
             CGKeyCode(kVK_PageUp),
             CGKeyCode(kVK_PageDown):
            return true
        default:
            return false
        }
    }

    private static func isLeftRightArrow(_ code: CGKeyCode) -> Bool {
        switch code {
        case CGKeyCode(kVK_LeftArrow),
             CGKeyCode(kVK_RightArrow):
            return true
        default:
            return false
        }
    }
}
