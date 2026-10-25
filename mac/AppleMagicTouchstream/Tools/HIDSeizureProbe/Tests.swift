import Foundation

@main
enum Tests {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1
        }
        func rejected(_ args: [String]) {
            do { _ = try ProbeOptions.parse(args); preconditionFailure("Unexpectedly accepted: \(args)") }
            catch { checks += 1 }
        }
        let defaults = try ProbeOptions.parse([])
        check(defaults.mode == .help, "Default must not touch hardware")
        rejected(["--seize"])
        rejected(["--observe", "--registry-id", "0"])
        rejected(["--seize", "--registry-id", "12", "--seconds", "61"])
        rejected(["--seize", "--registry-id", "12", "--seconds", "0"])
        rejected(["--list", "--seize", "--registry-id", "12"])
        rejected(["--list", "--initialize"])
        rejected(["--observe", "--registry-id", "12", "--initialize"])
        rejected(["--seize", "--registry-id", "12", "--registry-id", "13"])
        rejected(["--initialize"])
        rejected(["--list", "--output", "/tmp/unused"])
        rejected(["--list", "--native-contacts"])
        rejected(["--seize", "--registry-id", "12", "--native-contacts", "--initialize"])
        let native = try ProbeOptions.parse(["--seize", "--registry-id", "12", "--native-contacts"])
        check(native.nativeContacts && !native.initialize, "Native counts require no feature writes")
        let options = try ProbeOptions.parse(["--seize", "--registry-id", "12", "--seconds", "15", "--initialize"])
        check(options.registryID == 12 && options.seconds == 15 && options.initialize, "Explicit capture options")
        func pad(vendor: Int = 0x05ac, product: Int = 0x0324, usage: Int = 2,
                 transport: String = "USB", serial: String = "fixture") -> PadIdentity {
            PadIdentity(registryID: 12, vendorID: vendor, productID: product, usagePage: 1,
                        usage: usage, transport: transport, name: "fixture", serial: serial)
        }
        check(pad().eligible, "USB model0324")
        check(pad(vendor: 0x4c, transport: "Bluetooth").eligible, "Bluetooth model0324")
        check(!pad(usage: 6).eligible, "Never keyboard")
        check(!pad(product: 0x030e).eligible, "Never other model")
        check(!pad(serial: "").eligible, "Require physical identity")
        check(!pad(vendor: 0x4c).eligible, "Vendor must match transport")
        // One contact: x=-1, y=-1, state=4, contactID=5.
        let contact: [UInt8] = [255, 255, 255, 131, 0, 0, 0, 0, 5]
        let usb = [UInt8(2)] + Array(repeating: UInt8(0), count: 11) + contact
        let full = PacketCandidate.decode(reportID: 2, payload: usb, usb: true)!
        check(full.contacts == [ContactCandidate(id: 5, state: 4, rawX: -1, rawY: -1)], "Signed sensor coordinates")
        check(!full.insertedReportID, "Preserve report ID when present")
        let omitted = PacketCandidate.decode(reportID: 2, payload: Array(usb.dropFirst()), usb: true)!
        check(omitted.insertedReportID && omitted.contacts == full.contacts, "Normalize omitted callback report ID")
        let bluetooth = [UInt8(0x31), 0, 0, 0] + contact
        check(PacketCandidate.decode(reportID: 0x31, payload: bluetooth, usb: false)?.contacts == full.contacts, "Bluetooth framing")
        check(PacketCandidate.decode(reportID: 0x31, payload: Array(bluetooth.dropFirst()), usb: false)?.insertedReportID == true, "Bluetooth omitted ID")
        check(PacketCandidate.decode(reportID: 2, payload: usb, usb: false) == nil, "Reject transport mismatch")
        check(PacketCandidate.decode(reportID: 2, payload: Array(usb.dropLast(2)), usb: true) == nil, "Reject nonaligned contact payload")
        check(PacketCandidate.decode(reportID: 2, payload: [2] + Array(repeating: 0, count: 11 + 16 * 9), usb: true) == nil, "Bound contact count")
        check(PacketCandidate.decode(reportID: 99, payload: usb, usb: true) == nil, "Reject unknown report ID")
        check(BluetoothOptions.canonicalAddress("d0-c0-50-d5-69-55") == "D0:C0:50:D5:69:55", "Normalize Bluetooth address")
        check(BluetoothOptions.canonicalAddress("D0:C0:50:D5:69") == nil, "Reject incomplete address")
        check(BluetoothOptions.canonicalAddress("GG:C0:50:D5:69:55") == nil, "Reject nonhex address")
        let btDefault = try BluetoothOptions.parse([])
        check(btDefault.mode == .help, "Bluetooth defaults to no access")
        for args in [["--listen"], ["--listen", "--address", "D0:C0:50:D5:69:55", "--seconds", "31"],
                     ["--inventory", "--seconds", "5"], ["--inventory", "--listen"],
                     ["--listen", "--address", "D0:C0:50:D5:69:55", "--psm", "17"]] {
            do { _ = try BluetoothOptions.parse(args); preconditionFailure("Unexpected Bluetooth arguments accepted") }
            catch { checks += 1 }
        }
        let bt = try BluetoothOptions.parse(["--listen", "--address", "D0:C0:50:D5:69:55"])
        check(bt.seconds == 15, "Bounded Bluetooth duration")
        check(BluetoothPacket.decode([0xa1] + bluetooth)?.report.contacts == full.contacts, "HIDP Bluetooth contact framing")
        check(BluetoothPacket.decode(bluetooth)?.hidpPrefix == false, "Bare Bluetooth contact framing")
        check(BluetoothPacket.decode([0xa2] + bluetooth) == nil, "Reject HIDP output packets")
        check(BluetoothPacket.decode([0xa1, 0x31]) == nil, "Reject truncated Bluetooth data")
        let watch = try BluetoothOptions.parse(["--watch-reconnect", "--address", "D0:C0:50:D5:69:55", "--seconds", "30"])
        check(watch.mode == .watchReconnect && watch.seconds == 30, "Explicit bounded reconnect observer")
        for args in [["--watch-reconnect"],
                     ["--watch-reconnect", "--address", "D0:C0:50:D5:69:55", "--output", "/tmp/unused"],
                     ["--watch-reconnect", "--address", "D0:C0:50:D5:69:55", "--seconds", "31"],
                     ["--watch-reconnect", "--listen", "--address", "D0:C0:50:D5:69:55"]] {
            do { _ = try BluetoothOptions.parse(args); preconditionFailure("Unexpected observer arguments accepted") }
            catch { checks += 1 }
        }
        let getReportHelp = try GetReportOptions.parse([])
        check(getReportHelp.address == nil, "GET_REPORT defaults to help")
        let getReportExplicit = try GetReportOptions.parse(["--probe", "--address", "d0-c0-50-d5-69-55"])
        check(getReportExplicit.address == "D0:C0:50:D5:69:55", "Exact GET_REPORT address")
        for args in [["--probe"], ["--probe", "--address", "bad"], ["--probe", "--address", "D0:C0:50:D5:69:55", "--initialize"]] {
            do { _ = try GetReportOptions.parse(args); preconditionFailure("Unexpected GET_REPORT args accepted") }
            catch { checks += 1 }
        }
        check(GetReportOptions.baselineAllowsSeizure(success: true, reportID: 0x31, bytes: bluetooth), "Valid baseline permits experiment")
        check(!GetReportOptions.baselineAllowsSeizure(success: false, reportID: 0x31, bytes: bluetooth), "Failed request never permits seizure")
        check(!GetReportOptions.baselineAllowsSeizure(success: true, reportID: 2, bytes: usb), "Wrong report never permits seizure")
        check(!GetReportOptions.baselineAllowsSeizure(success: true, reportID: 0x31, bytes: [0x31]), "Truncated reply never permits seizure")
        print("\(checks) offline checks passed. No IOKit calls, permission requests or device access.")
    }
}
