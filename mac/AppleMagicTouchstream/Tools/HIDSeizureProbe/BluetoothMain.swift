import Foundation
import IOBluetooth
import IOKit
import Darwin

private func statusText(_ status: IOReturn) -> String { String(format: "0x%08x", UInt32(bitPattern: status)) }
private func registryPads() throws -> [PadIdentity] {
    var iterator: io_iterator_t = 0
    let status = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDDevice"), &iterator)
    guard status == KERN_SUCCESS else { throw ProbeError("Registry inventory failed: \(statusText(status))") }
    defer { IOObjectRelease(iterator) }
    var result: [PadIdentity] = []
    while true {
        let service = IOIteratorNext(iterator); if service == 0 { break }
        defer { IOObjectRelease(service) }
        var value: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &value, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let p = value?.takeRetainedValue() as? [String: Any] else { continue }
        var rid: UInt64 = 0; IORegistryEntryGetRegistryEntryID(service, &rid)
        let pad = PadIdentity(registryID: rid, vendorID: (p["VendorID"] as? NSNumber)?.intValue ?? 0,
            productID: (p["ProductID"] as? NSNumber)?.intValue ?? 0,
            usagePage: (p["PrimaryUsagePage"] as? NSNumber)?.intValue ?? 0,
            usage: (p["PrimaryUsage"] as? NSNumber)?.intValue ?? 0,
            transport: p["Transport"] as? String ?? "", name: p["Product"] as? String ?? "",
            serial: p["SerialNumber"] as? String ?? "")
        if pad.eligible && pad.transport == "Bluetooth" { result.append(pad) }
    }
    return result
}

// Deliberately does not implement the data-delegate protocol. These callbacks
// observe public notifications; they never attach a delegate or close a channel.
private final class ReconnectWatcher: NSObject {
    let address: String
    let began = ProcessInfo.processInfo.systemUptime
    var connects = 0, control = 0, interrupt = 0
    var stopped = false
    init(address: String) { self.address = address }
    private func matches(_ device: IOBluetoothDevice?) -> Bool {
        guard let value = device?.addressString else { return false }
        return BluetoothOptions.canonicalAddress(value) == address
    }
    private func elapsed() -> String {
        String(format: "%.3f", ProcessInfo.processInfo.systemUptime - began)
    }
    @objc func connected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard !stopped, matches(device) else { return }
        connects += 1
        print("CONNECT t=\(elapsed()) address=\(address)")
    }
    @objc func opened(_ notification: IOBluetoothUserNotification, channel: IOBluetoothL2CAPChannel) {
        guard !stopped, matches(channel.device) else { return }
        let psm = channel.psm
        if psm == 0x11 { control += 1 }
        else if psm == 0x13 { interrupt += 1 }
        else { return }
        print(String(format: "CHANNEL_OPEN t=%@ psm=0x%04x direction=%@ localCID=0x%04x remoteCID=0x%04x",
            elapsed(), psm, channel.isIncoming() ? "incoming" : "outgoing", channel.localChannelID, channel.remoteChannelID))
        // Do not retain the notified channel, query/set its delegate, or close it.
    }
}

private func watchReconnect(_ options: BluetoothOptions) throws {
    guard let address = options.address else { throw ProbeError("Missing exact address") }
    let watcher = ReconnectWatcher(address: address)
    var notifications: [IOBluetoothUserNotification] = []
    defer {
        watcher.stopped = true
        for notification in notifications { notification.unregister() }
        withExtendedLifetime(watcher) {}
    }
    guard let connection = IOBluetoothDevice.register(forConnectNotifications: watcher,
        selector: #selector(ReconnectWatcher.connected(_:device:))) else {
        throw ProbeError("Connect notification registration failed")
    }
    notifications.append(connection)
    for psm: BluetoothL2CAPPSM in [0x11, 0x13] {
        guard let channel = IOBluetoothL2CAPChannel.register(forChannelOpenNotifications: watcher,
            selector: #selector(ReconnectWatcher.opened(_:channel:)), withPSM: psm,
            direction: kIOBluetoothUserNotificationChannelDirectionAny) else {
            throw ProbeError(String(format: "Channel notification registration failed for PSM 0x%04x", psm))
        }
        notifications.append(channel)
    }
    signal(SIGINT, SIG_IGN); signal(SIGTERM, SIG_IGN)
    let signals = [SIGINT, SIGTERM].map { value -> DispatchSourceSignal in
        let source = DispatchSource.makeSignalSource(signal: value, queue: .main)
        source.setEventHandler { watcher.stopped = true }
        source.resume(); return source
    }
    defer {
        for source in signals { source.cancel() }
        signal(SIGINT, SIG_DFL); signal(SIGTERM, SIG_DFL)
    }
    print("WATCHING address=\(address) seconds=\(options.seconds) — turn the selected pad ON now.")
    print("Notifications only. No channel open, data listener, mode write, seizure or close is requested.")
    let began = ProcessInfo.processInfo.systemUptime
    while !watcher.stopped && ProcessInfo.processInfo.systemUptime - began < Double(options.seconds) {
        CFRunLoopRunInMode(.defaultMode, 0.05, false)
    }
    print("SUMMARY connectNotifications=\(watcher.connects) controlNotifications=\(watcher.control) interruptNotifications=\(watcher.interrupt)")
    print("Notifications do not prove ownership or contact delivery. Check native input still works.")
}

@main
private enum BluetoothMain {
    static func main() {
        do { try run() } catch { fputs("ERROR: \(error)\n", stderr); exit(1) }
    }
    static func run() throws {
        setbuf(stdout, nil)
        let options = try BluetoothOptions.parse(Array(CommandLine.arguments.dropFirst()))
        if options.mode == .help {
            print("""
            BluetoothChannelProbe — reconnect notification experiment
              --inventory [--address MAC]  IORegistry properties only; no Bluetooth framework calls
              --watch-reconnect --address MAC [--seconds 30]  Observe public notifications only
              --listen --address MAC      Disabled after failed hardware test; no channel access
            The former private l2capChannels accessor caused connection attempts.
            No channel open, delegate replacement, close, or mode write is available here.
            """)
            return
        }
        if options.mode == .watchReconnect { try watchReconnect(options); return }
        guard options.mode == .inventory else {
            throw ProbeError("Bluetooth listening is disabled: the previous channel-enumeration API had connection side effects. No Bluetooth access attempted. See README.md for the archived Bluetooth test result.")
        }
        let pads = try registryPads().filter {
            options.address == nil || BluetoothOptions.canonicalAddress($0.serial) == options.address
        }
        guard !pads.isEmpty else { throw ProbeError("No matching connected model0324 Bluetooth pad in HID registry") }
        for pad in pads {
            print("PAD \(pad.serial), registryID=\(pad.registryID), transport=\(pad.transport); registry properties only")
        }
    }
}
