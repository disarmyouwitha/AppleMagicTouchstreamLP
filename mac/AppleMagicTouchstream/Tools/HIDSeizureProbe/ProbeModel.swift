import Foundation

struct ProbeError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

struct ProbeOptions {
    enum Mode: String { case help, list, observe, seize, requestAccess }
    var mode: Mode = .help
    var registryID: UInt64?
    var seconds = 15
    var initialize = false
    var nativeContacts = false
    var output: String?

    static func parse(_ arguments: [String]) throws -> Self {
        var result = Self(), selectedMode = false, seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let arg = arguments[index]
            guard seen.insert(arg).inserted else { throw ProbeError("Duplicate option: \(arg)") }
            func value() throws -> String {
                index += 1
                guard index < arguments.count else { throw ProbeError("Missing value for \(arg)") }
                return arguments[index]
            }
            switch arg {
            case "--help", "--list", "--observe", "--seize", "--request-input-access":
                guard !selectedMode else { throw ProbeError("Choose exactly one mode") }
                selectedMode = true
                result.mode = ["--help": .help, "--list": .list, "--observe": .observe,
                               "--seize": .seize, "--request-input-access": .requestAccess][arg]!
            case "--registry-id":
                let raw = try value()
                guard let id = UInt64(raw), id > 0 else { throw ProbeError("Registry ID must be a positive decimal integer") }
                result.registryID = id
            case "--seconds":
                guard let seconds = Int(try value()), (1...60).contains(seconds) else {
                    throw ProbeError("Duration must be 1...60 seconds")
                }
                result.seconds = seconds
            case "--initialize": result.initialize = true
            case "--native-contacts": result.nativeContacts = true
            case "--output": result.output = try value()
            default: throw ProbeError("Unknown option: \(arg)")
            }
            index += 1
        }
        let live = result.mode == .observe || result.mode == .seize
        guard !live || result.registryID != nil else { throw ProbeError("Live modes require --registry-id from --list") }
        guard live || seen.isDisjoint(with: ["--registry-id", "--seconds", "--initialize", "--native-contacts", "--output"]) else {
            throw ProbeError("Capture options require --observe or --seize")
        }
        guard !result.initialize || result.mode == .seize else {
            throw ProbeError("Feature initialization is allowed only with --seize")
        }
        guard !result.nativeContacts || !result.initialize else {
            throw ProbeError("Test --native-contacts without --initialize to isolate native capture")
        }
        return result
    }
}

struct PadIdentity: Codable {
    let registryID: UInt64
    let vendorID: Int
    let productID: Int
    let usagePage: Int
    let usage: Int
    let transport: String
    let name: String
    let serial: String
    var eligible: Bool {
        productID == 0x0324 && usagePage == 1 && usage == 2 && !serial.isEmpty &&
        ((vendorID == 0x05ac && transport == "USB") || (vendorID == 0x004c && transport == "Bluetooth"))
    }
}

// Diagnostic framing only. These coordinates are raw sensor integers, not the
// production decoder's calibrated OMS coordinates/pressure/velocity.
struct ContactCandidate: Codable, Equatable {
    let id: Int
    let state: Int
    let rawX: Int
    let rawY: Int
}

struct PacketCandidate: Codable {
    let reportID: Int
    let insertedReportID: Bool
    let buttons: Int
    let contacts: [ContactCandidate]

    static func decode(reportID: UInt32, payload: [UInt8], usb: Bool) -> Self? {
        let expected: UInt8 = usb ? 2 : 0x31
        let header = usb ? 12 : 4
        guard reportID == UInt32(expected) || (reportID == 0 && payload.first == expected) else { return nil }
        var bytes = payload
        let inserted: Bool
        if bytes.first == expected && bytes.count >= header && (bytes.count - header) % 9 == 0 {
            inserted = false
        } else if reportID == UInt32(expected) && bytes.count >= header - 1 && (bytes.count + 1 - header) % 9 == 0 {
            bytes.insert(expected, at: 0)
            inserted = true
        } else { return nil }
        guard (bytes.count - header) / 9 <= 15 else { return nil }
        func signed13(_ value: Int) -> Int { value & 0x1000 == 0 ? value : value - 0x2000 }
        var contacts: [ContactCandidate] = []
        for i in stride(from: header, to: bytes.count, by: 9) {
            let x = Int(bytes[i]) | (Int(bytes[i+1] & 31) << 8)
            let yLow = Int(bytes[i+1] >> 5)
            let yMiddle = Int(bytes[i+2]) << 3
            let yHigh = Int(bytes[i+3] & 3) << 11
            contacts.append(ContactCandidate(id: Int(bytes[i+8] & 15), state: Int(bytes[i+3] >> 5),
                rawX: signed13(x), rawY: signed13(yLow | yMiddle | yHigh)))
        }
        return Self(reportID: Int(expected), insertedReportID: inserted, buttons: Int(bytes[1] & 3), contacts: contacts)
    }
}
