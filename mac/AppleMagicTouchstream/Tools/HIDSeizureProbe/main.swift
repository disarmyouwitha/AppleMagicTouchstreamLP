import Foundation
import IOKit
import IOKit.hid
import CoreGraphics
import Darwin

private func hexStatus(_ status: IOReturn) -> String {
    String(format: "0x%08x", UInt32(bitPattern: status))
}

private struct NativeCounts: Codable {
    let phase: String
    let frames: UInt64
    let withContacts: UInt64
    let lastObservedContacts: UInt64
    let maxContacts: UInt64
    init(phase: String, since start: ProbeNativeCounts) {
        let current = ProbeNativeRead()
        self.phase = phase
        frames = current.frames &- start.frames
        withContacts = current.withContacts &- start.withContacts
        lastObservedContacts = current.lastCount; maxContacts = current.maxCount
    }
    func printProgress() {
        print("NATIVE phase=\(phase), frames=\(frames), withContacts=\(withContacts), lastObservedContacts=\(lastObservedContacts), sessionMaxContacts=\(maxContacts)")
        fflush(stdout)
    }
}

private func sampleNative(phase: String, seconds: Double) -> NativeCounts {
    let counts = ProbeNativeRead()
    let began = ProcessInfo.processInfo.systemUptime
    var lastProgress = began
    print("NATIVE \(phase): \(Int(seconds)) seconds — keep moving several fingers on the selected pad.")
    fflush(stdout)
    while ProcessInfo.processInfo.systemUptime - began < seconds {
        CFRunLoopRunInMode(.defaultMode, 0.05, false)
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastProgress >= 1 {
            NativeCounts(phase: phase, since: counts).printProgress()
            lastProgress = now
        }
    }
    let result = NativeCounts(phase: phase, since: counts)
    result.printProgress()
    return result
}

private func properties(_ service: io_service_t) -> [String: Any] {
    var raw: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(service, &raw, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return [:] }
    return raw?.takeRetainedValue() as? [String: Any] ?? [:]
}

private func identity(_ service: io_service_t) -> PadIdentity {
    let p = properties(service)
    var rid: UInt64 = 0
    IORegistryEntryGetRegistryEntryID(service, &rid)
    func number(_ key: String) -> Int { (p[key] as? NSNumber)?.intValue ?? 0 }
    return PadIdentity(registryID: rid, vendorID: number(kIOHIDVendorIDKey), productID: number(kIOHIDProductIDKey),
        usagePage: number(kIOHIDPrimaryUsagePageKey), usage: number(kIOHIDPrimaryUsageKey),
        transport: p[kIOHIDTransportKey] as? String ?? "", name: p[kIOHIDProductKey] as? String ?? "",
        serial: p[kIOHIDSerialNumberKey] as? String ?? "")
}

private func matchingServices(_ matching: CFDictionary, visit: (io_service_t) -> Void) throws {
    var iterator: io_iterator_t = 0
    let status = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
    guard status == KERN_SUCCESS else { throw ProbeError("IOServiceGetMatchingServices: \(hexStatus(status))") }
    defer { IOObjectRelease(iterator) }
    while true {
        let service = IOIteratorNext(iterator)
        if service == 0 { break }
        visit(service)
        IOObjectRelease(service)
    }
}

private func takeoverIsPresent() throws -> Bool {
    var present = false
    try matchingServices(IOServiceMatching("IOUserService")) { service in
        let p = properties(service)
        if p["IOUserClass"] as? String == "AMTRawHIDReceiver" ||
            p["CFBundleIdentifier"] as? String == "ink.ranna.trackpadtakeover.driver" {
            present = true
        }
    }
    return present
}

private struct CapturedReport: Codable {
    let uptime: Double
    let reportID: UInt32
    let result: String
    let bytes: [UInt8]
    let candidate: PacketCandidate?
}

private final class Capture {
    let device: IOHIDDevice
    let pad: PadIdentity
    let buffer: UnsafeMutablePointer<UInt8>
    let capacity: Int
    var reports: [CapturedReport] = []
    var count = 0, candidates = 0, contactCandidates = 0, dropped = 0, capturedBytes = 0
    var accepting = false
    var removed = false
    var interrupted = false
    var opened = false
    var reportIDs: [UInt32: Int] = [:]
    var nativeDuring: NativeCounts?

    init(device: IOHIDDevice, pad: PadIdentity) {
        self.device = device; self.pad = pad
        let declared = (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? NSNumber)?.intValue ?? 4096
        capacity = min(max(declared, 4096), 65536)
        buffer = .allocate(capacity: capacity)
        buffer.initialize(repeating: 0, count: capacity)
    }
    deinit { buffer.deallocate() }

    func receive(result: IOReturn, reportID: UInt32, bytes: UnsafeMutablePointer<UInt8>, length: Int) {
        guard accepting else { return }
        count += 1; reportIDs[reportID, default: 0] += 1
        guard length >= 0, length <= capacity else { dropped += 1; return }
        let payload = Array(UnsafeBufferPointer(start: bytes, count: length))
        let candidate = result == kIOReturnSuccess ? PacketCandidate.decode(reportID: reportID, payload: payload, usb: pad.transport == "USB") : nil
        if let candidate { candidates += 1; if !candidate.contacts.isEmpty { contactCandidates += 1 } }
        guard reports.count < 4096, capturedBytes + length <= 1_048_576 else { dropped += 1; return }
        capturedBytes += length
        reports.append(CapturedReport(uptime: ProcessInfo.processInfo.systemUptime, reportID: reportID,
            result: hexStatus(result), bytes: payload, candidate: candidate))
    }

    func run(_ options: ProbeOptions) throws -> IOReturn {
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, capacity, { context, result, _, _, reportID, bytes, length in
            guard let context else { return }
            Unmanaged<Capture>.fromOpaque(context).takeUnretainedValue().receive(result: result, reportID: reportID, bytes: bytes, length: length)
        }, context)
        IOHIDDeviceRegisterRemovalCallback(device, { context, _, _ in
            guard let context else { return }
            Unmanaged<Capture>.fromOpaque(context).takeUnretainedValue().removed = true
        }, context)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        defer {
            accepting = false
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceRegisterInputReportCallback(device, buffer, capacity, nil, nil)
            IOHIDDeviceRegisterRemovalCallback(device, nil, nil)
        }
        // Arm before Open/SetReport as well: synchronous HID calls can stall.
        signal(SIGALRM, SIG_DFL); alarm(UInt32(options.seconds + 3))
        defer { alarm(0) }
        let flags = options.mode == .seize ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice) : IOOptionBits(kIOHIDOptionsTypeNone)
        let status = IOHIDDeviceOpen(device, flags)
        print("OPEN \(options.mode.rawValue): \(hexStatus(status)); pid=\(getpid()); uid=\(getuid())")
        guard status == kIOReturnSuccess else {
            throw ProbeError("Device open failed. No feature report sent. Permission denial and exclusive-access errors are findings, not evidence of capture.")
        }
        opened = true; accepting = true
        let nativeAtOpen = ProbeNativeRead()
        // POSIX alarm remains effective if the run loop stalls. Process exit
        // releases the kernel device handle. No launch daemon is installed.
        let oldStop = signal(SIGTSTP, SIG_IGN)
        defer { signal(SIGTSTP, oldStop) }
        signal(SIGINT, SIG_IGN); signal(SIGTERM, SIG_IGN)
        let signals = [SIGINT, SIGTERM].map { value -> DispatchSourceSignal in
            let source = DispatchSource.makeSignalSource(signal: value, queue: .main)
            source.setEventHandler { [weak self] in self?.interrupted = true }
            source.resume(); return source
        }
        defer { for source in signals { source.cancel() }; signal(SIGINT, SIG_DFL); signal(SIGTERM, SIG_DFL) }
        if options.initialize {
            let payload: [UInt8] = [0x02, 0x01]
            let reportID = pad.transport == "USB" ? 2 : 0xf1
            let result = payload.withUnsafeBufferPointer {
                IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, reportID, $0.baseAddress!, $0.count)
            }
            print("FEATURE reportID=\(reportID), payload=0201: \(hexStatus(result))")
        }
        let start = ProcessInfo.processInfo.systemUptime
        var lastProgress = start
        while !removed && !interrupted && ProcessInfo.processInfo.systemUptime - start < Double(options.seconds) {
            CFRunLoopRunInMode(.defaultMode, 0.05, false)
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastProgress >= 1 {
                print("REPORTS \(count), framed=\(candidates), withContacts=\(contactCandidates), captureDropped=\(dropped)")
                if options.nativeContacts { NativeCounts(phase: options.mode.rawValue, since: nativeAtOpen).printProgress() }
                fflush(stdout); lastProgress = now
            }
        }
        accepting = false
        if options.nativeContacts {
            nativeDuring = NativeCounts(phase: options.mode.rawValue, since: nativeAtOpen)
            nativeDuring?.printProgress()
        }
        let close = IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        opened = false
        print("CLOSE: \(hexStatus(close)); reason=\(removed ? "disconnect" : interrupted ? "signal" : "timeout")")
        print("SUMMARY reports=\(count), framed=\(candidates), withContacts=\(contactCandidates), ids=\(reportIDs), captureDropped=\(dropped)")
        print("Native pointer/click/gesture restoration requires your observation; close success alone does not prove restoration.")
        return close
    }
}

@main
private enum Main {
    static func main() {
        do { try run() } catch {
            fputs("ERROR: \(error)\n", stderr)
            exit(1)
        }
    }
    static func run() throws {
        let options = try ProbeOptions.parse(Array(CommandLine.arguments.dropFirst()))
        switch options.mode {
        case .help:
            print("""
            HIDSeizureProbe — standalone, no DriverKit extension or event output.
              --list                                    Read-only supported HID interface inventory
              --request-input-access                    Request macOS Input Monitoring permission
              --observe --registry-id ID [--seconds 15]  Shared raw-report baseline
              --seize --registry-id ID [--seconds 15]     Exclusive raw-report experiment
              [--initialize]                            Optional USB 02/Bluetooth F1 feature payload 02 01 (seize only)
              [--native-contacts]                        Count native contacts before/during/after capture (adds 10s)
              [--output PATH]                           New private JSONL capture; refuses overwrite
            Maximum session: 60 seconds. Ctrl-C releases. No automatic sudo or device selection.
            Use --help/--list separately; capture options require a live mode.
            """)
            return
        case .requestAccess:
            print("Input Monitoring request result: \(CGRequestListenEventAccess())"); return
        case .list:
            try matchingServices(IOServiceMatching("IOHIDDevice")) { service in
                let pad = identity(service)
                guard pad.eligible else { return }
                let data = try! JSONEncoder().encode(pad)
                print(String(decoding: data, as: UTF8.self))
            }
            return
        case .observe, .seize: break
        }
        guard try !takeoverIsPresent() else { throw ProbeError("Release Trackpad Takeover and wait for driver removal before using this probe") }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(options.registryID!))
        guard service != 0 else { throw ProbeError("Registry ID disappeared; run --list again") }
        defer { IOObjectRelease(service) }
        let pad = identity(service)
        guard pad.eligible, IOObjectConformsTo(service, "IOHIDDevice") != 0,
              let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) else {
            throw ProbeError("Selection is not an eligible model0324 USB/Bluetooth mouse interface")
        }
        guard !IOHIDDeviceConformsTo(device, 1, 6), !IOHIDDeviceConformsTo(device, 1, 7) else {
            throw ProbeError("Refusing a keyboard/keypad collection")
        }
        var file: FileHandle?
        if let path = options.output {
            let fd = Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
            guard fd >= 0 else { throw ProbeError("Cannot create new private capture file: \(String(cString: strerror(errno)))") }
            file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        }
        defer { try? file?.close() }
        func write<T: Encodable>(_ value: T) throws {
            guard let file else { return }
            var data = try JSONEncoder().encode(value); data.append(10); try file.write(contentsOf: data)
        }
        try write(pad)
        print("SELECTED \(pad.name), \(pad.transport), registryID=\(pad.registryID), duration=\(options.seconds)s")
        print("Input Monitoring preflight: \(CGPreflightListenEventAccess()); permissions are not requested automatically.")
        if options.nativeContacts {
            let status = pad.serial.withCString { serial in
                pad.transport.withCString { transport in ProbeNativeStart(serial, transport) }
            }
            guard status == 0 else {
                throw ProbeError("Native contact monitor failed (\(status)); no HID interface opened. 1=API unavailable, 2=no serial/transport match, 3=ambiguous, 4=running, 5=start failed")
            }
        }
        defer { if options.nativeContacts { ProbeNativeStop() } }
        if options.nativeContacts { try write(sampleNative(phase: "before-open", seconds: 5)) }
        let capture = Capture(device: device, pad: pad)
        let close = try capture.run(options)
        if let during = capture.nativeDuring { try write(during) }
        if options.nativeContacts && close == kIOReturnSuccess { try write(sampleNative(phase: "after-close", seconds: 5)) }
        // Persist after releasing the device; callback memory is bounded.
        for report in capture.reports { try write(report) }
        try write(["event": "summary", "reports": "\(capture.count)", "framed": "\(capture.candidates)",
                   "withContacts": "\(capture.contactCandidates)", "dropped": "\(capture.dropped)", "closeResult": hexStatus(close)])
        guard close == kIOReturnSuccess else { throw ProbeError("Close returned \(hexStatus(close)); process exit will release remaining handles") }
    }
}
