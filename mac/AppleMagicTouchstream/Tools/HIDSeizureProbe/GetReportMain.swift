import Foundation
import IOKit
import IOKit.hid
import Darwin

private func code(_ status: IOReturn) -> String { String(format: "0x%08x", UInt32(bitPattern: status)) }
private var stopped = false
// Deliberately retain request memory and device through process exit: a missing
// callback must never leave a dangling buffer/context. Maximum six 4096-byte reads.
private var requests: [Request] = []
private var heldDevice: IOHIDDevice?
private final class Request {
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
    let length = UnsafeMutablePointer<CFIndex>.allocate(capacity: 1)
    var done = false, status: IOReturn = kIOReturnError
    var returnedID: UInt32 = 0, bytes: [UInt8] = []
    init() {
        buffer.initialize(repeating: 0, count: 4096); buffer[0] = 0x31
        length.initialize(to: 4096)
    }
    // Objects remain in requests until _exit, including on timeout/error.
}
private let completion: IOHIDReportCallback = { context, result, _, type, reportID, report, length in
    guard let context else { return }
    let request = Unmanaged<Request>.fromOpaque(context).takeUnretainedValue()
    guard !request.done else { return }
    request.status = result; request.returnedID = reportID
    if result == kIOReturnSuccess, type == kIOHIDReportTypeInput,
       length > 0, length <= 4096 {
        request.bytes = Array(UnsafeBufferPointer(start: report, count: length))
    }
    request.done = true
}

private func wait(_ seconds: Double) throws {
    let end = ProcessInfo.processInfo.systemUptime + seconds
    while !stopped && ProcessInfo.processInfo.systemUptime < end {
        CFRunLoopRunInMode(.defaultMode, 0.05, false)
    }
    if stopped { throw ProbeError("Interrupted") }
}
private func read(_ device: IOHIDDevice, phase: String) throws -> Request {
    if stopped { throw ProbeError("Interrupted") }
    let request = Request(); requests.append(request)
    let began = ProcessInfo.processInfo.systemUptime
    print("GET_REQUEST phase=\(phase) type=input reportID=0x31 capacity=4096 timeoutMS=1000")
    let status = IOHIDDeviceGetReportWithCallback(device, kIOHIDReportTypeInput, 0x31,
        request.buffer, request.length, 1000, completion, Unmanaged.passUnretained(request).toOpaque())
    print("GET_SUBMIT phase=\(phase) result=\(code(status))")
    guard status == kIOReturnSuccess else {
        request.status = status; request.done = true; return request
    }
    while !request.done && !stopped && ProcessInfo.processInfo.systemUptime - began < 2.5 {
        CFRunLoopRunInMode(.defaultMode, 0.05, false)
    }
    guard request.done else { throw ProbeError("Missing GET_REPORT completion or interrupted; aborting further requests") }
    let packet = PacketCandidate.decode(reportID: request.returnedID, payload: request.bytes, usb: false)
    print("GET_RESULT phase=\(phase) result=\(code(request.status)) reportID=\(request.returnedID) length=\(request.bytes.count) framed=\(packet != nil) contacts=\(packet?.contacts.count ?? 0) elapsedMS=\(Int((ProcessInfo.processInfo.systemUptime - began) * 1000))")
    print("BYTES phase=\(phase) hex=\(request.bytes.prefix(256).map { String(format: "%02x", $0) }.joined())\(request.bytes.count > 256 ? " [truncated display]" : "")")
    return request
}

private func select(_ address: String) throws -> IOHIDDevice {
    let takeover = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AMTRawHIDReceiver"))
    if takeover != 0 { IOObjectRelease(takeover); throw ProbeError("Release DriverKit takeover first") }
    // DriverKit IOUserClass instances may use IOUserService as the registry class.
    var driverIterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUserService"), &driverIterator) == KERN_SUCCESS else {
        throw ProbeError("Cannot inspect active DriverKit services")
    }
    defer { IOObjectRelease(driverIterator) }
    while true {
        let service = IOIteratorNext(driverIterator); if service == 0 { break }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, "IOUserClass" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
        if value == "AMTRawHIDReceiver" { throw ProbeError("Release DriverKit takeover first") }
    }
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDDevice"), &iterator) == KERN_SUCCESS else {
        throw ProbeError("Cannot inspect HID registry")
    }
    defer { IOObjectRelease(iterator) }
    var devices: [IOHIDDevice] = []
    while true {
        let service = IOIteratorNext(iterator); if service == 0 { break }
        defer { IOObjectRelease(service) }
        var value: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &value, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let p = value?.takeRetainedValue() as? [String: Any] else { continue }
        func number(_ key: String) -> Int { (p[key] as? NSNumber)?.intValue ?? 0 }
        var rid: UInt64 = 0; IORegistryEntryGetRegistryEntryID(service, &rid)
        let pad = PadIdentity(registryID: rid, vendorID: number("VendorID"), productID: number("ProductID"),
            usagePage: number("PrimaryUsagePage"), usage: number("PrimaryUsage"), transport: p["Transport"] as? String ?? "",
            name: p["Product"] as? String ?? "", serial: p["SerialNumber"] as? String ?? "")
        guard pad.eligible, pad.transport == "Bluetooth", BluetoothOptions.canonicalAddress(pad.serial) == address else { continue }
        if let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) { devices.append(device) }
    }
    guard devices.count == 1 else { throw ProbeError("Expected exactly one eligible connected Bluetooth pad for \(address); found \(devices.count)") }
    return devices[0]
}

@main
private enum GetReportMain {
    static func main() {
        setbuf(stdout, nil)
        do { try run(); _exit(0) }
        catch { fputs("ERROR: \(error)\n", stderr); _exit(1) }
    }
    static func run() throws {
        let options = try GetReportOptions.parse(Array(CommandLine.arguments.dropFirst()))
        guard let address = options.address else {
            print("""
            HIDGetReportProbe --probe --address MAC
            Asks for Bluetooth input report 0x31 through GET_REPORT, not a stream callback.
            Two ordinary-open baseline requests. Only valid baseline framing allows
            a short exclusive-open phase with four requests. No SET_REPORT/mode writes.
            Missing completion aborts the test. Default/--help do not access devices.
            """); return
        }
        let device = try select(address); heldDevice = device
        var opened = false
        signal(SIGALRM, SIG_DFL); alarm(35)
        defer { alarm(0) }
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        defer {
            if opened { print("CLOSE result=\(code(IOHIDDeviceClose(device, 0)))") }
            // Keep callback source and request storage alive until immediate process
            // exit. Do not unschedule/free a potentially outstanding request.
            print("Native restoration requires your observation; reconnect the selected pad if needed.")
        }
        signal(SIGTSTP, SIG_IGN)
        signal(SIGINT, SIG_IGN); signal(SIGTERM, SIG_IGN)
        let signals = [SIGINT, SIGTERM].map { value -> DispatchSourceSignal in
            let source = DispatchSource.makeSignalSource(signal: value, queue: .main)
            source.setEventHandler { stopped = true }; source.resume(); return source
        }
        defer { for source in signals { source.cancel() } }
        let status = IOHIDDeviceOpen(device, 0)
        print("SELECTED \(address); OPEN ordinary result=\(code(status)) uid=\(getuid())")
        guard status == kIOReturnSuccess else { throw ProbeError("Ordinary open failed") }
        opened = true
        print("BASELINE: move and keep several fingers on this pad now; first request in 3 seconds.")
        try wait(3)
        for index in 1...2 {
            let request = try read(device, phase: "baseline-\(index)")
            guard GetReportOptions.baselineAllowsSeizure(success: request.status == kIOReturnSuccess,
                reportID: request.returnedID, bytes: request.bytes) else {
                print("STOP: baseline did not return known contact framing; no seizure attempted.")
                throw ProbeError("Input GET_REPORT is not established as usable on this pad")
            }
            try wait(1)
        }
        let close = IOHIDDeviceClose(device, 0)
        print("CLOSE baseline result=\(code(close))")
        guard close == kIOReturnSuccess else { throw ProbeError("Baseline close failed; aborting") }
        opened = false
        if stopped { throw ProbeError("Interrupted") }
        let seize = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        print("OPEN seize result=\(code(seize))")
        guard seize == kIOReturnSuccess else { throw ProbeError("Exclusive open failed") }
        opened = true
        print("SEIZED: keep moving several fingers; four low-rate requests, then release.")
        for index in 1...4 {
            let request = try read(device, phase: "seized-\(index)")
            guard GetReportOptions.baselineAllowsSeizure(success: request.status == kIOReturnSuccess,
                reportID: request.returnedID, bytes: request.bytes) else {
                throw ProbeError("Request failed or contact framing disappeared during seizure; releasing")
            }
            try wait(1)
        }
        print("SUMMARY: six successful framed GET_REPORT replies; inspect changing bytes/contact counts before claiming live acquisition.")
    }
}
