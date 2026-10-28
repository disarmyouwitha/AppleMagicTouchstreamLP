import Foundation

struct BluetoothOptions {
    enum Mode { case help, inventory, listen, watchReconnect }
    var mode: Mode = .help
    var address: String?
    var seconds = 15
    var output: String?
    static func canonicalAddress(_ raw: String) -> String? {
        let fields = raw.uppercased().replacingOccurrences(of: "-", with: ":").split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count == 6, fields.allSatisfy({ $0.count == 2 && UInt8($0, radix: 16) != nil }) else { return nil }
        return fields.joined(separator: ":")
    }
    static func parse(_ arguments: [String]) throws -> Self {
        var options = Self(), modeSeen = false, seen = Set<String>()
        var i = 0
        while i < arguments.count {
            let arg = arguments[i]
            guard seen.insert(arg).inserted else { throw ProbeError("Duplicate option: \(arg)") }
            func value() throws -> String {
                i += 1
                guard i < arguments.count else { throw ProbeError("Missing value for \(arg)") }
                return arguments[i]
            }
            switch arg {
            case "--help", "--inventory", "--listen", "--watch-reconnect":
                guard !modeSeen else { throw ProbeError("Choose one mode") }
                modeSeen = true
                options.mode = arg == "--watch-reconnect" ? .watchReconnect : arg == "--listen" ? .listen : arg == "--inventory" ? .inventory : .help
            case "--address":
                guard let address = canonicalAddress(try value()) else { throw ProbeError("Expected six-byte Bluetooth address") }
                options.address = address
            case "--seconds":
                guard let value = Int(try value()), (1...30).contains(value) else { throw ProbeError("Duration must be 1...30 seconds") }
                options.seconds = value
            case "--output": options.output = try value()
            default: throw ProbeError("Unknown option: \(arg)")
            }
            i += 1
        }
        guard (options.mode != .listen && options.mode != .watchReconnect) || options.address != nil else {
            throw ProbeError("--listen/--watch-reconnect requires an explicit --address")
        }
        guard options.mode == .listen || options.mode == .watchReconnect || !seen.contains("--seconds") else {
            throw ProbeError("Duration requires --listen or --watch-reconnect")
        }
        guard options.mode == .listen || !seen.contains("--output") else { throw ProbeError("Capture output requires --listen") }
        guard options.mode != .help || options.address == nil else { throw ProbeError("--address requires a device mode") }
        return options
    }
}

struct BluetoothPacket: Codable {
    let hidpPrefix: Bool
    let report: PacketCandidate
    static func decode(_ bytes: [UInt8]) -> Self? {
        // Classic HIDP DATA/Input header A1, followed by the HID report ID.
        // Also recognize bare reports; retain original bytes separately.
        let prefix = bytes.first == 0xa1
        let payload = prefix ? Array(bytes.dropFirst()) : bytes
        guard payload.first == 0x31,
              let report = PacketCandidate.decode(reportID: 0x31, payload: payload, usb: false) else { return nil }
        return Self(hidpPrefix: prefix, report: report)
    }
}
