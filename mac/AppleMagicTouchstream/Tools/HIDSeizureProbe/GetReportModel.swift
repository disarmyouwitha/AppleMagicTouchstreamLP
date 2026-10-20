import Foundation

struct GetReportOptions {
    var address: String?
    static func parse(_ args: [String]) throws -> Self {
        if args.isEmpty || args == ["--help"] { return Self() }
        guard args.count == 3, args[0] == "--probe", args[1] == "--address",
              let address = BluetoothOptions.canonicalAddress(args[2]) else {
            throw ProbeError("Use --probe --address MAC, or --help")
        }
        return Self(address: address)
    }
    static func baselineAllowsSeizure(success: Bool, reportID: UInt32, bytes: [UInt8]) -> Bool {
        success && reportID == 0x31 && PacketCandidate.decode(reportID: reportID, payload: bytes, usb: false) != nil
    }
}
