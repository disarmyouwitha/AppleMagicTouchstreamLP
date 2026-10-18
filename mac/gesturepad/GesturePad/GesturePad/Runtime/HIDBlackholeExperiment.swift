import AppKit
import Combine
import Foundation
import IOKit
import IOKit.hid
import os

struct HIDBlackholeIdentity: Hashable, Sendable {
    let registryID: UInt64
    let product: String
    let vendor: Int
    let productID: Int
    let transport: String
    let serial: String
    let location: Int
    let usagePage: Int
    let usage: Int

    var groupID: String {
        let significantSerial = serial.filter { $0.isLetter || $0.isNumber }.lowercased()
        if !significantSerial.isEmpty, significantSerial.contains(where: { $0 != "0" }) {
            return "\(vendor):\(transport.lowercased()):serial:\(significantSerial)"
        }
        if location != 0 { return "\(vendor):\(transport.lowercased()):location:\(location)" }
        return "registry:\(registryID)"
    }

    var isTrackpad: Bool {
        product.localizedCaseInsensitiveContains("trackpad") || (usagePage == 0x0d && usage == 0x05)
    }
    var isKeyboard: Bool { usagePage == 1 && usage == 6 }
    var label: String {
        "\(product) · \(transport) · \(serial.isEmpty ? String(location) : String(serial.suffix(8)))"
    }
}

private final class HIDBlackholeOpenDevice {
    struct Reports: Sendable {
        var count: UInt64 = 0
        var bytes: UInt64 = 0
        var lastID: UInt32 = 0
        var lastLength = 0
        var lastResult: IOReturn = kIOReturnSuccess
    }
    let device: IOHIDDevice
    let identity: HIDBlackholeIdentity
    let reportBuffer: UnsafeMutablePointer<UInt8>
    let bufferSize: Int
    let reports = OSAllocatedUnfairLock(initialState: Reports())
    private var opened = false

    init(device: IOHIDDevice, identity: HIDBlackholeIdentity) {
        self.device = device
        self.identity = identity
        let size = (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? NSNumber)?.intValue ?? 4096
        bufferSize = min(max(size, 4096), 1_048_576)
        reportBuffer = .allocate(capacity: bufferSize)
        reportBuffer.initialize(repeating: 0, count: bufferSize)
    }

    func open() -> IOReturn {
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        guard result == kIOReturnSuccess else {
            // Some failure paths still establish a user-client connection; close it too.
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            return result
        }
        opened = true
        IOHIDDeviceRegisterInputReportCallback(device, reportBuffer, bufferSize, { context, result, _, _, reportID, _, length in
            guard let context else { return }
            let owner = Unmanaged<HIDBlackholeOpenDevice>.fromOpaque(context).takeUnretainedValue()
            owner.reports.withLock { state in
                state.count &+= 1
                state.bytes &+= UInt64(max(0, length))
                state.lastID = reportID
                state.lastLength = length
                state.lastResult = result
            }
            // Deliberately discard the report. Do not synthesize or forward any input.
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        return result
    }

    @discardableResult
    func close() -> IOReturn {
        guard opened else { return kIOReturnSuccess }
        IOHIDDeviceRegisterInputReportCallback(device, reportBuffer, bufferSize, nil, nil)
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if result == kIOReturnSuccess { opened = false }
        return result
    }

    deinit {
        close()
        reportBuffer.deinitialize(count: bufferSize)
        reportBuffer.deallocate()
    }
}

/// Explicit, temporary exclusive-open experiment. It never installs a CGEvent tap.
@MainActor
final class HIDBlackholeExperiment: ObservableObject {
    struct Group: Identifiable, Sendable {
        let id: String
        let label: String
        let interfaces: [HIDBlackholeIdentity]
    }
    @Published private(set) var groups: [Group] = []
    @Published private(set) var isActive = false
    @Published private(set) var secondsRemaining = 0
    @Published private(set) var isContinuous = false
    @Published private(set) var summary = "Off. Refresh HID devices, choose a trackpad, then enable the 30-second test."
    @Published private(set) var diagnostics = ""
    @Published private(set) var selectedGroupIDs: Set<String> = []
    private var devices: [UInt64: IOHIDDevice] = [:]
    private var held: [HIDBlackholeOpenDevice] = []
    private var openResults: [String] = []
    private var deadline: Date?
    private var timer: Timer?

    func refresh() {
        guard !isActive else { return }
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDDevice"), &iterator)
        guard result == KERN_SUCCESS else { summary = "HID enumeration failed: \(Self.status(result))"; return }
        defer { IOObjectRelease(iterator) }
        var entries: [HIDBlackholeIdentity] = []
        devices.removeAll()
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) else { continue }
            func string(_ key: String) -> String { IOHIDDeviceGetProperty(device, key as CFString) as? String ?? "" }
            func number(_ key: String) -> Int { (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0 }
            var registryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &registryID)
            let identity = HIDBlackholeIdentity(registryID: registryID, product: string(kIOHIDProductKey),
                vendor: number(kIOHIDVendorIDKey), productID: number(kIOHIDProductIDKey),
                transport: string(kIOHIDTransportKey), serial: string(kIOHIDSerialNumberKey),
                location: number(kIOHIDLocationIDKey), usagePage: number(kIOHIDPrimaryUsagePageKey), usage: number(kIOHIDPrimaryUsageKey))
            entries.append(identity)
            devices[registryID] = device
        }
        // Include sibling collections even if their product name/usage differs from the touch interface.
        let trackpadGroups = Set(entries.filter(\.isTrackpad).map(\.groupID))
        let related = entries.filter { trackpadGroups.contains($0.groupID) }
        groups = Dictionary(grouping: related, by: \.groupID).map { id, interfaces in
            let sorted = interfaces.sorted { $0.registryID < $1.registryID }
            return Group(id: id, label: (sorted.first(where: \.isTrackpad) ?? sorted[0]).label, interfaces: sorted)
        }.sorted { $0.id < $1.id }
        selectedGroupIDs.formIntersection(groups.map(\.id))
        diagnostics = groups.flatMap { $0.interfaces.map { Self.describe($0) } }.joined(separator: "\n")
        summary = groups.isEmpty ? "No trackpad HID interfaces found. Connect the trackpad and refresh." : "Found \(groups.count) trackpad(s), \(related.count) related HID interfaces. No device has been opened."
    }

    /// Link every selected physical trackpad, deduplicating shared selections.
    func selectTrackpads(registryEntryIDs: [UInt64]) {
        guard !isActive else { return }
        selectedGroupIDs = []
        guard !registryEntryIDs.isEmpty else {
            summary = "Select trackpads above to enable the 30-second test."
            return
        }
        let paths = registryEntryIDs.map { Self.registryPath(startingAt: $0) }
        guard let matches = Self.matchingGroupIDs(registryPaths: paths, groups: groups) else {
            summary = "Could not link every selected trackpad. Refresh trackpads after connecting or changing transport."
            return
        }
        selectedGroupIDs = matches
        summary = "Linked to \(matches.count) selected trackpad(s). Blackhole is off."
    }

    nonisolated static func matchingGroupIDs(registryPaths: [[UInt64]], groups: [Group]) -> Set<String>? {
        guard !registryPaths.isEmpty else { return nil }
        var matches: Set<String> = []
        for path in registryPaths {
            guard let match = matchingGroupID(registryPath: path, groups: groups) else { return nil }
            matches.insert(match)
        }
        return matches
    }

    nonisolated static func matchingGroupID(registryPath: [UInt64], groups: [Group]) -> String? {
        for registryID in registryPath {
            let matches = Set(groups.filter { group in group.interfaces.contains { $0.registryID == registryID } }.map(\.id))
            if matches.count > 1 { return nil }
            if let match = matches.first { return match }
        }
        return nil
    }

    private static func registryPath(startingAt registryID: UInt64) -> [UInt64] {
        var entry = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(registryID))
        var path: [UInt64] = []
        while entry != 0, path.count < 64 {
            var currentID: UInt64 = 0
            if IORegistryEntryGetRegistryEntryID(entry, &currentID) == KERN_SUCCESS { path.append(currentID) }
            var parent: io_registry_entry_t = 0
            let result = IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent)
            IOObjectRelease(entry)
            entry = result == KERN_SUCCESS ? parent : 0
        }
        if entry != 0 { IOObjectRelease(entry) }
        return path
    }

    func setEnabled(_ enabled: Bool) {
        if !enabled { release(reason: "Released by toggle"); return }
        activate(testDuration: nil)
    }

    func startTimedTest() {
        activate(testDuration: 30)
    }

    private func activate(testDuration: TimeInterval?) {
        if isActive {
            configureDuration(testDuration)
            return
        }
        guard !selectedGroupIDs.isEmpty else { return }
        let interfaces = groups.filter { selectedGroupIDs.contains($0.id) }.flatMap(\.interfaces)
        openResults.removeAll()
        // Never seize a keyboard interface, including a keyboard sharing a composite device.
        for identity in interfaces {
            guard !identity.isKeyboard else { openResults.append("\(Self.describe(identity)) — skipped keyboard"); continue }
            guard let device = devices[identity.registryID] else { continue }
            let handle = HIDBlackholeOpenDevice(device: device, identity: identity)
            let result = handle.open()
            openResults.append("\(Self.describe(identity)) — seize \(Self.status(result))")
            if result == kIOReturnSuccess { held.append(handle) }
        }
        isActive = !held.isEmpty
        diagnostics = openResults.joined(separator: "\n")
        guard isActive else {
            summary = "No interfaces seized. Review the exact errors below; permission/privilege or an existing owner may prevent opening."
            return
        }
        configureDuration(testDuration)
    }

    private func configureDuration(_ duration: TimeInterval?) {
        timer?.invalidate()
        timer = nil
        isContinuous = duration == nil
        deadline = duration.map { Date().addingTimeInterval($0) }
        updateReadout()
        timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func release(reason: String = "Released") {
        timer?.invalidate()
        timer = nil
        deadline = nil
        isContinuous = false
        var failed: [HIDBlackholeOpenDevice] = []
        for handle in held {
            let result = handle.close()
            let reports = handle.reports.withLock { $0 }
            openResults.append("RID \(handle.identity.registryID) — final \(reports.count) reports / \(reports.bytes) bytes, last ID \(reports.lastID), length \(reports.lastLength)")
            openResults.append("\(Self.describe(handle.identity)) — close \(Self.status(result))")
            if result != kIOReturnSuccess { failed.append(handle) }
        }
        held = failed
        isActive = !held.isEmpty
        secondsRemaining = 0
        summary = isActive ? "Release failed for \(held.count) interface(s). Retry Release, or quit the app." : "\(reason). Normal HID ownership restored for successfully closed interfaces."
        diagnostics = openResults.joined(separator: "\n")
    }

    private func tick() {
        if let deadline, Date() >= deadline { release(reason: "30-second test ended"); return }
        updateReadout()
    }

    private func updateReadout() {
        secondsRemaining = max(0, Int(ceil(deadline?.timeIntervalSinceNow ?? 0)))
        let total = groups.filter { selectedGroupIDs.contains($0.id) }.flatMap(\.interfaces).filter { !$0.isKeyboard }.count
        let timing = isContinuous ? "enabled until released" : "auto-release in \(secondsRemaining)s"
        summary = "Seized \(held.count)/\(total) eligible interfaces · \(timing)."
        let reports = held.map { handle in
            let value = handle.reports.withLock { $0 }
            return "RID \(handle.identity.registryID): \(value.count) reports / \(value.bytes) bytes · last ID \(value.lastID), length \(value.lastLength), \(Self.status(value.lastResult))"
        }
        diagnostics = (openResults + reports).joined(separator: "\n")
    }

    private static func describe(_ device: HIDBlackholeIdentity) -> String {
        "RID \(device.registryID) · VID \(device.vendor) PID \(device.productID) · \(device.transport) · usage \(String(format: "%04X:%04X", device.usagePage, device.usage))"
    }
    private static func status(_ result: IOReturn) -> String {
        let message = mach_error_string(result).map { String(cString: $0) } ?? "unknown"
        return String(format: "0x%08X", UInt32(bitPattern: result)) + " (" + message + ")"
    }
}
