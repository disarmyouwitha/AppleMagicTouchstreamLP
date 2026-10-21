import Darwin
import AppKit
import Combine
import Foundation
import IOKit
import OpenMultitouchSupport
import ApplicationServices
import IOKit.hid
import IOKit.hidsystem
import os
import UniformTypeIdentifiers

struct HIDBlackholeIdentity: Hashable, Sendable, Codable {
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

    var supportsUSBMultitouchProbe: Bool {
        transport.caseInsensitiveCompare("USB") == .orderedSame && vendor == 0x05ac
            && productID == 0x0324 && usagePage == 1 && usage == 2
    }

    var isTrackpad: Bool {
        product.localizedCaseInsensitiveContains("trackpad") || (usagePage == 0x0d && usage == 0x05)
    }
    var isKeyboard: Bool { usagePage == 1 && usage == 6 }
    var label: String {
        "\(product) · \(transport) · \(serial.isEmpty ? String(location) : String(serial.suffix(8)))"
    }
}

/// Bounded storage: callback copies bytes only; encoding and disk I/O happen after release.
struct HIDRawReportBuffer {
    struct Index {
        let uptime: Double
        let reportID: UInt32
        let result: Int32
        let offset: Int
        let length: Int
    }
    struct Record: Codable, Sendable {
        let uptime: Double
        let reportID: UInt32
        let result: Int32
        let payload: Data
    }
    private(set) var bytes = Data()
    private(set) var indices: [Index] = []
    private(set) var dropped = 0
    let byteLimit: Int
    let reportLimit: Int

    init(byteLimit: Int = 2_097_152, reportLimit: Int = 8192) {
        self.byteLimit = byteLimit
        self.reportLimit = reportLimit
        bytes.reserveCapacity(byteLimit)
        indices.reserveCapacity(reportLimit)
    }

    mutating func append(uptime: Double, reportID: UInt32, result: Int32,
                         pointer: UnsafePointer<UInt8>, length: Int) {
        guard length >= 0, indices.count < reportLimit, length <= byteLimit - bytes.count else {
            dropped += 1
            return
        }
        indices.append(Index(uptime: uptime, reportID: reportID, result: result,
                             offset: bytes.count, length: length))
        bytes.append(pointer, count: length)
    }

    func records() -> [Record] {
        indices.map { Record(uptime: $0.uptime, reportID: $0.reportID, result: $0.result,
                             payload: bytes.subdata(in: $0.offset..<($0.offset + $0.length))) }
    }
}

private struct HIDRawCapture: Encodable, Sendable {
    struct Interface: Codable, Sendable {
        let identity: HIDBlackholeIdentity
        let reportDescriptor: Data?
        let droppedReports: Int
        let reportCallbackCount: UInt64
        let inputValueCallbackCount: UInt64
        let lastInputValueReportID: UInt32
        let lastInputValueResult: Int32
        let matchingInputElementCount: Int
        let declaredInputReportIDs: [UInt32]
        let reports: [HIDRawReportBuffer.Record]
    }
    let format = "GesturePad.RawHID"
    let version = 1
    let startedAt: Date
    let startedUptime: Double
    let endedUptime: Double
    let osVersion: String
    let captureMode: String
    let callbackSetup: String
    let inputMonitoringAtStart: String
    let inputMonitoringAtEnd: String
    let selectedTouchDeviceIDs: [UInt64]
    let openResults: [String]
    let endReason: String
    let interfaces: [Interface]
}

// IOHID dispatch delivery targets DispatchQueue.main. Capture state is also only
// accessed on the main thread; Sendable permits the cancel handler's lifetime hold.
private final class HIDBlackholeOpenDevice: @unchecked Sendable {
    struct Reports: Sendable {
        var count: UInt64 = 0
        var bytes: UInt64 = 0
        var lastID: UInt32 = 0
        var lastLength = 0
        var lastResult: IOReturn = kIOReturnSuccess
        var valueCount: UInt64 = 0
        var lastValueReportID: UInt32 = 0
        var lastValueResult: IOReturn = kIOReturnSuccess
    }
    let device: IOHIDDevice
    let identity: HIDBlackholeIdentity
    let reportBuffer: UnsafeMutablePointer<UInt8>
    let bufferSize: Int
    let reports = OSAllocatedUnfairLock(initialState: Reports())
    private var opened = false
    private var acceptingCallbacks = false
    private var dispatchActivated = false
    private var matchingInputElementCount = 0
    private var declaredInputReportIDs: [UInt32] = []
    private var capture: HIDRawReportBuffer?
    private var captureDescriptor: Data?

    init(device: IOHIDDevice, identity: HIDBlackholeIdentity) {
        self.device = device
        self.identity = identity
        let size = (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? NSNumber)?.intValue ?? 4096
        bufferSize = min(max(size, 4096), 1_048_576)
        reportBuffer = .allocate(capacity: bufferSize)
        reportBuffer.initialize(repeating: 0, count: bufferSize)
    }

    func open(exclusive: Bool = true) -> IOReturn {
        IOHIDDeviceRegisterInputReportCallback(device, reportBuffer, bufferSize, { context, result, _, _, reportID, payload, length in
            guard let context else { return }
            let owner = Unmanaged<HIDBlackholeOpenDevice>.fromOpaque(context).takeUnretainedValue()
            guard owner.acceptingCallbacks else { return }
            owner.reports.withLock { state in
                state.count &+= 1
                state.bytes &+= UInt64(max(0, length))
                state.lastID = reportID
                state.lastLength = length
                state.lastResult = result
            }
            if length >= 0, length <= owner.bufferSize {
                owner.capture?.append(uptime: ProcessInfo.processInfo.systemUptime,
                    reportID: reportID, result: result, pointer: payload, length: length)
            }
            // Capture does not forward reports or generate output.
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceSetInputValueMatching(device, nil)
        IOHIDDeviceRegisterInputValueCallback(device, { context, result, _, value in
            guard let context else { return }
            let owner = Unmanaged<HIDBlackholeOpenDevice>.fromOpaque(context).takeUnretainedValue()
            guard owner.acceptingCallbacks else { return }
            let reportID = IOHIDElementGetReportID(IOHIDValueGetElement(value))
            owner.reports.withLock {
                $0.valueCount &+= 1
                $0.lastValueReportID = reportID
                $0.lastValueResult = result
            }
        }, Unmanaged.passUnretained(self).toOpaque())
        let options = exclusive ? kIOHIDOptionsTypeSeizeDevice : kIOHIDOptionsTypeNone
        let result = IOHIDDeviceOpen(device, IOOptionBits(options))
        guard result == kIOReturnSuccess else {
            IOHIDDeviceRegisterInputReportCallback(device, reportBuffer, bufferSize, nil,
                Unmanaged.passUnretained(self).toOpaque())
            IOHIDDeviceRegisterInputValueCallback(device, nil, Unmanaged.passUnretained(self).toOpaque())
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            return result
        }
        opened = true
        let elements = (IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement]) ?? []
        let input = elements.filter {
            let type = IOHIDElementGetType($0)
            return type == kIOHIDElementTypeInput_Misc || type == kIOHIDElementTypeInput_Button
                || type == kIOHIDElementTypeInput_Axis || type == kIOHIDElementTypeInput_ScanCodes
        }
        matchingInputElementCount = input.count
        declaredInputReportIDs = Set(input.map { IOHIDElementGetReportID($0) }).sorted()
        IOHIDDeviceSetDispatchQueue(device, DispatchQueue.main)
        // Retain callback context and its buffer until cancellation has drained
        // both internal report and input-value queues. Never synchronously wait
        // for cancellation on the main queue.
        IOHIDDeviceSetCancelHandler(device) { [self] in
            acceptingCallbacks = false
        }
        acceptingCallbacks = true
        dispatchActivated = true
        IOHIDDeviceActivate(device)
        return result
    }

    func requestUSBMultitouchMode() -> IOReturn {
        guard opened, identity.supportsUSBMultitouchProbe else { return kIOReturnUnsupported }
        // Linux hid-magicmouse: USB-C 05AC:0324 uses feature ID 02,
        // bytes 02 01. Preserve the leading report ID in the feature buffer.
        let bytes: [UInt8] = [0x02, 0x01]
        return bytes.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0x02, $0.baseAddress!, $0.count)
        }
    }

    // All callbacks and these methods run on the main thread (dispatch target: main).
    func beginCapture() {
        captureDescriptor = IOHIDDeviceGetProperty(device, kIOHIDReportDescriptorKey as CFString) as? Data
        capture = HIDRawReportBuffer()
    }

    var captureReportCount: Int { capture?.indices.count ?? 0 }
    var captureDroppedCount: Int { capture?.dropped ?? 0 }

    func finishCapture() -> HIDRawCapture.Interface? {
        guard let capture else { return nil }
        let counts = reports.withLock { $0 }
        let result = HIDRawCapture.Interface(identity: identity, reportDescriptor: captureDescriptor,
            droppedReports: capture.dropped, reportCallbackCount: counts.count,
            inputValueCallbackCount: counts.valueCount, lastInputValueReportID: counts.lastValueReportID,
            lastInputValueResult: counts.lastValueResult, matchingInputElementCount: matchingInputElementCount,
            declaredInputReportIDs: declaredInputReportIDs, reports: capture.records())
        self.capture = nil
        captureDescriptor = nil
        return result
    }

    @discardableResult
    func close() -> IOReturn {
        guard opened else { return kIOReturnSuccess }
        acceptingCallbacks = false
        let result = IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if result == kIOReturnSuccess {
            opened = false
            if dispatchActivated {
                dispatchActivated = false
                IOHIDDeviceCancel(device)
            }
        } else {
            acceptingCallbacks = true
        }
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
    struct Group: Identifiable, Sendable, Codable {
        let id: String
        let label: String
        let interfaces: [HIDBlackholeIdentity]
    }
    let pointerIdentityProbe = PointerIdentityProbe()
    let gainProbe = TrackpadGainProbe()
    let pointerControl = SelectedTrackpadEventFilter()
    @Published private(set) var nativeFilterActive = false
    @Published private(set) var nativeFilterStatus = "Off. Take over the currently selected trackpads."
    private var nativeFilterTimer: Timer?
    @Published private(set) var twoFingerMouseEnabled = false
    @Published private(set) var twoFingerMouseStatus = "Off"
    private var nativeMouseSelectedIDs: Set<UInt64> = []
    private var nativeMouseOwnedIDs: Set<UInt64> = []
    private var nativeMouseArmed = false
    private var nativeMousePermissionDenied = false

    func setTwoFingerMouseEnabled(_ enabled: Bool) {
        if enabled && !AXIsProcessTrusted() {
            nativeMousePermissionDenied = true
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            twoFingerMouseStatus = "Enable Accessibility for GesturePad, then check again."
            return
        }
        nativeMousePermissionDenied = false
        twoFingerMouseEnabled = enabled
        nativeMouseArmed = enabled
        InterpretedTrackpadPointer.shared.resetBaseline()
        updateNativeMouseOutput()
    }

    func configureNativeMouseSelection(_ ids: [UInt64]) {
        let next = Set(ids)
        if next != nativeMouseSelectedIDs {
            InterpretedTrackpadPointer.shared.resetBaseline()
            nativeMouseSelectedIDs = next
        }
        updateNativeMouseOutput()
    }

    private func pauseNativeMouseOutput() {
        nativeMouseArmed = false
        InterpretedTrackpadPointer.shared.stop()
    }

    private func updateNativeMouseOutput() {
        let trusted = !twoFingerMouseEnabled || AXIsProcessTrusted()
        let devices = NativeTwoFingerMouseGate.outputDevices(enabled: twoFingerMouseEnabled,
            armed: nativeMouseArmed, takeoverEnabled: takeoverPreference.enabled,
            trusted: trusted, selected: nativeMouseSelectedIDs, owned: nativeMouseOwnedIDs)
        if devices.isEmpty {
            InterpretedTrackpadPointer.shared.stop()
        } else {
            // Outside the input callback: refresh bounds/permissions while retaining
            // baselines for an unchanged selected native-ID set.
            InterpretedTrackpadPointer.shared.enable(devices: devices)
        }
        if !twoFingerMouseEnabled { twoFingerMouseStatus = nativeMousePermissionDenied
            ? "Enable Accessibility for GesturePad, then check again." : "Off" }
        else if !trusted { twoFingerMouseStatus = "Paused: Accessibility permission required." }
        else if !devices.isEmpty {
            twoFingerMouseStatus = "Active · 6 pt/mm · \(InterpretedTrackpadPointer.shared.postedEventCount) moves posted"
        } else { twoFingerMouseStatus = "Waiting for selected trackpads in Trackpad Takeover." }
    }

    var onNativeOwnershipChanged: ((Bool) -> Void)?

    lazy var takeoverPreference = NativeTakeoverPreference(
        defaults: .standard,
        ownedIDs: { Set((OMSManager.shared.nativeTakeoverStatus["deviceIDs"] as? [NSNumber] ?? []).map { $0.uint64Value }) },
        transition: { [weak self] ids in self?.updateNativeTakeover(deviceIDs: ids) ?? false },
        stop: { [weak self] in self?.release(reason: "Trackpad Takeover transition") }
    )

    private func updateNativeTakeover(deviceIDs: [UInt64]) -> Bool {
        guard !isActive && !isObservingHID && !pointerControl.isActive && !gainProbe.isActive else { return false }
        pauseNativeMouseOutput()
        let success = OMSManager.shared.updateNativeTakeover(deviceIDs: deviceIDs)
        nativeMouseArmed = success && twoFingerMouseEnabled
        updateNativeFilterStatus()
        if nativeFilterActive && nativeFilterTimer == nil {
            nativeFilterTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.updateNativeFilterStatus() }
            }
            if let nativeFilterTimer { RunLoop.main.add(nativeFilterTimer, forMode: .common) }
        }
        return success
    }

    private func updateNativeFilterStatus() {
        let state = OMSManager.shared.nativeTakeoverStatus
        let wasActive = nativeFilterActive
        nativeFilterActive = state["active"] as? Bool ?? false
        nativeFilterStatus = state["message"] as? String ?? "Unavailable"
        nativeMouseOwnedIDs = Set((state["deviceIDs"] as? [NSNumber] ?? []).map { $0.uint64Value })
        updateNativeMouseOutput()
        if wasActive != nativeFilterActive { onNativeOwnershipChanged?(nativeFilterActive) }
        if !nativeFilterActive {
            nativeFilterTimer?.invalidate()
            nativeFilterTimer = nil
        }
    }

    @Published private(set) var groups: [Group] = []
    @Published private(set) var singleInterfaceTestID: UInt64?
    private var usbModeRequestAt: Double?
    private var usbModeAttempted = false
    var selectedInterfaces: [HIDBlackholeIdentity] {
        groups.filter { selectedGroupIDs.contains($0.id) }.flatMap(\.interfaces).filter { !$0.isKeyboard }
    }

    @Published private(set) var isActive = false
    @Published private(set) var isObservingHID = false
    var hasOpenHIDDevices: Bool { nativeFilterActive || isActive || isObservingHID || pointerControl.isActive || gainProbe.isActive }
    private var openIsExclusive = true
    private var captureMode = "exclusive"
    @Published private(set) var secondsRemaining = 0
    @Published private(set) var isContinuous = false
    @Published private(set) var summary = "Off. Refresh HID devices, choose a trackpad, then enable the 30-second test."
    @Published private(set) var diagnostics = ""
    @Published private(set) var isCapturingHID = false
    @Published private(set) var isSavingHID = false
    @Published private(set) var captureStatus = ""
    private var captureURL: URL?
    private var captureStartedAt = Date()
    private var captureInputMonitoring = "unknown"
    private var captureStartedUptime: Double = 0
    private var captureDeadline: Double?
    @Published private(set) var selectedGroupIDs: Set<String> = []
    private var selectedTouchDeviceIDs: Set<UInt64> = []
    private var devices: [UInt64: IOHIDDevice] = [:]
    private var held: [HIDBlackholeOpenDevice] = []
    private var openResults: [String] = []
    private var deadline: Date?
    private var timer: Timer?

    func refresh() {
        guard held.isEmpty else { return }
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
    func selectTrackpads(registryEntryIDs: [UInt64], touchDeviceIDs: Set<UInt64>) {
        guard held.isEmpty else { return }
        selectedGroupIDs = []
        selectedTouchDeviceIDs = touchDeviceIDs
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

    func testSingleInterface(registryID: UInt64, requestUSBMultitouch: Bool = false) {
        guard !nativeFilterActive else { return }
        guard !isSavingHID else { return }
        release(reason: "Single-interface test starting")
        guard !hasOpenHIDDevices,
              let identity = selectedInterfaces.first(where: { $0.registryID == registryID }),
              let source = devices[registryID],
              let device = IOHIDDeviceCreate(kCFAllocatorDefault, IOHIDDeviceGetService(source)) else {
            summary = "Could not open the selected interface. Refresh trackpads and retry."
            return
        }
        guard !requestUSBMultitouch || identity.supportsUSBMultitouchProbe else {
            summary = "USB mode probe requires USB 05AC:0324, usage 0001:0002. No interface opened."
            return
        }
        InterfaceTouchEvidence.shared.start(devices: selectedTouchDeviceIDs)
        let handle = HIDBlackholeOpenDevice(device: device, identity: identity)
        // Register bounded byte storage before opening; no report bytes are
        // inserted, stripped or interpreted by this capture.
        handle.beginCapture()
        let startedAt = Date()
        let startedUptime = ProcessInfo.processInfo.systemUptime
        let result = handle.open(exclusive: true)
        openResults = ["Single-interface test: \(identity.label), \(Self.describe(identity)); seize \(Self.status(result))"]
        guard result == kIOReturnSuccess else {
            InterfaceTouchEvidence.shared.stop()
            summary = "Single-interface seize failed: \(Self.status(result))"
            diagnostics = openResults.joined(separator: "\n")
            saveSingleInterfaceResult(identity: identity, status: summary)
            return
        }
        captureURL = URL(fileURLWithPath: "/tmp/GesturePad-\(identity.transport)-HID-\(registryID)-\(Int(startedAt.timeIntervalSince1970)).json")
        captureStartedAt = startedAt
        captureStartedUptime = startedUptime
        captureInputMonitoring = Self.inputMonitoringStatus()
        captureMode = requestUSBMultitouch ? "exclusive-single-interface-usb-multitouch-request" : "exclusive-single-interface"
        usbModeAttempted = false
        usbModeRequestAt = requestUSBMultitouch ? ProcessInfo.processInfo.systemUptime + 2 : nil
        captureDeadline = nil
        isCapturingHID = true
        captureStatus = "Capturing original HID report bytes; saves automatically after release."
        held = [handle]
        singleInterfaceTestID = registryID
        if identity.supportsUSBMultitouchProbe && !requestUSBMultitouch {
            // Diagnostic handshake only: the standalone USB tool waits for this
            // new capture, then validates it again immediately before its write.
            let marker = "\(identity.serial)\n\(registryID)\n\(startedAt.timeIntervalSince1970)\n\(startedUptime)\n"
            do {
                try marker.write(toFile: "/tmp/GesturePad-active-usb-capture.txt", atomically: true, encoding: .utf8)
                openResults.append("Direct USB synchronization marker written; wall clock \(startedAt.timeIntervalSince1970), uptime \(startedUptime).")
            } catch {
                openResults.append("Direct USB synchronization unavailable: \(error.localizedDescription)")
            }
        }
        isActive = true
        openIsExclusive = true
        configureDuration(15)
    }

    private func saveSingleInterfaceResult(identity: HIDBlackholeIdentity, status: String) {
        let report: [String: Any] = ["format": "GesturePad.SingleInterfaceSeize", "status": status,
            "registryID": identity.registryID, "transport": identity.transport,
            "product": identity.product, "serial": identity.serial,
            "usagePage": identity.usagePage, "usage": identity.usage,
            "log": openResults, "contactEvidence": InterfaceTouchEvidence.shared.snapshot(),
            "note": "Only this interface was opened. Check native cursor/scroll/click behavior physically; contact evidence counts live OMS callbacks and nonempty frames. No synthetic output or cursor correction."]
        let url = URL(fileURLWithPath: "/tmp/GesturePad-interface-\(identity.registryID).json")
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func setEnabled(_ enabled: Bool) {
        if !enabled { release(reason: "Released by toggle"); return }
        startPointerControl(duration: nil)
    }

    func startTimedTest() { startPointerControl(duration: 30) }

    private func startPointerControl(duration: TimeInterval?) {
        guard !nativeFilterActive else { return }
        gainProbe.restore()
        guard !gainProbe.isActive else { return }
        guard !isCapturingHID else { return }
        pointerIdentityProbe.stop()
        if !held.isEmpty {
            release(reason: "Switching to pointer filtering")
            guard held.isEmpty else { return }
        }
        pointerControl.start(groups: groups.filter { selectedGroupIDs.contains($0.id) },
            touchDevices: selectedTouchDeviceIDs, duration: duration)
    }

    func captureHID(exclusive: Bool = true) {
        guard !nativeFilterActive else { return }
        guard !isCapturingHID, !isSavingHID, !selectedGroupIDs.isEmpty else { return }
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
            // Successful exclusive opens alone do not prove permission to receive reports.
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            guard IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted else {
                if hasOpenHIDDevices { release(reason: "Input Monitoring permission required") }
                captureStatus = "Input Monitoring access: \(Self.inputMonitoringStatus()). Enable GesturePad in System Settings → Privacy & Security → Input Monitoring, quit and reopen the app, then retry. No capture started."
                return
            }
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "GesturePad-HID-\(exclusive ? "seized" : "baseline")-\(Int(Date().timeIntervalSince1970)).json"
        panel.title = "Save 15-second raw HID capture"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        activate(testDuration: 30, allowPointer: false, exclusive: exclusive)
        guard hasOpenHIDDevices, openIsExclusive == exclusive else {
            captureStatus = "Capture failed: could not open HID interfaces in the requested ownership mode."
            return
        }
        captureMode = exclusive ? "exclusive" : "shared-baseline"
        InterpretedTrackpadPointer.shared.stop()
        captureURL = url
        captureInputMonitoring = Self.inputMonitoringStatus()
        captureStartedAt = Date()
        captureStartedUptime = ProcessInfo.processInfo.systemUptime
        captureDeadline = captureStartedUptime + 15
        for handle in held { handle.beginCapture() }
        isCapturingHID = true
        captureStatus = "Recording \(captureMode) HID for 15 seconds. Touch the selected trackpads now."
    }

    private func finishHIDCapture(reason: String, interfaces: [HIDRawCapture.Interface]) {
        guard isCapturingHID, let url = captureURL else { return }
        let document = HIDRawCapture(startedAt: captureStartedAt, startedUptime: captureStartedUptime,
            endedUptime: ProcessInfo.processInfo.systemUptime, osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            captureMode: captureMode, callbackSetup: "register-before-open; main-dispatch-queue; report-and-value-callbacks; activate-cancel",
            inputMonitoringAtStart: captureInputMonitoring, inputMonitoringAtEnd: Self.inputMonitoringStatus(),
            selectedTouchDeviceIDs: selectedTouchDeviceIDs.sorted(), openResults: openResults,
            endReason: reason, interfaces: interfaces)
        let count = interfaces.reduce(0) { $0 + $1.reports.count }
        let dropped = interfaces.reduce(0) { $0 + $1.droppedReports }
        isCapturingHID = false
        captureDeadline = nil
        captureURL = nil
        isSavingHID = true
        let modeWasRequested = usbModeAttempted
        captureStatus = "Saving \(count) raw HID reports…"
        Task {
            let failure: String? = await Task.detached(priority: .utility) {
                do {
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    encoder.outputFormatting = [.sortedKeys]
                    try encoder.encode(document).write(to: url, options: .atomic)
                    return nil
                } catch { return error.localizedDescription }
            }.value
            isSavingHID = false
            if let failure { captureStatus = "HID capture save failed: \(failure)" }
            else if count == 0 {
                let values = interfaces.reduce(UInt64(0)) { $0 + $1.inputValueCallbackCount }
                captureStatus = "No raw reports; \(values) input-value callbacks. Saved diagnostic capture: \(url.path)"
            } else { captureStatus = "Saved \(count) reports (\(dropped) dropped): \(url.path)" }
            if modeWasRequested { captureStatus += " Reconnect USB if native behavior does not recover after release." }
        }
    }

    private func activate(testDuration: TimeInterval?, allowPointer: Bool = true, exclusive: Bool = true) {
        pointerControl.stop()
        pointerIdentityProbe.stop()
        if !held.isEmpty && openIsExclusive != exclusive {
            release(reason: "HID capture ownership mode changed")
            guard held.isEmpty else { return }
        }
        if !held.isEmpty {
            configureDuration(testDuration)
            return
        }
        guard !selectedGroupIDs.isEmpty else { return }
        if allowPointer && !AXIsProcessTrusted() {
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
        let interfaces = groups.filter { selectedGroupIDs.contains($0.id) }.flatMap(\.interfaces)
        openResults.removeAll()
        openIsExclusive = exclusive
        // Never seize a keyboard interface, including a keyboard sharing a composite device.
        for identity in interfaces {
            guard !identity.isKeyboard else { openResults.append("\(Self.describe(identity)) — skipped keyboard"); continue }
            guard let source = devices[identity.registryID],
                  let device = IOHIDDeviceCreate(kCFAllocatorDefault, IOHIDDeviceGetService(source)) else {
                openResults.append("\(Self.describe(identity)) — could not create fresh device connection")
                continue
            }
            let handle = HIDBlackholeOpenDevice(device: device, identity: identity)
            let result = handle.open(exclusive: exclusive)
            openResults.append("\(Self.describe(identity)) — \(exclusive ? "seize" : "shared open") \(Self.status(result))")
            if result == kIOReturnSuccess { held.append(handle) }
        }
        isActive = exclusive && !held.isEmpty
        isObservingHID = !exclusive && !held.isEmpty
        diagnostics = openResults.joined(separator: "\n")
        guard hasOpenHIDDevices else {
            summary = "No interfaces opened. HID open errors are included in diagnostics."
            return
        }
        let eligibleCount = interfaces.filter { !$0.isKeyboard }.count
        if exclusive, allowPointer, held.count == eligibleCount, AXIsProcessTrusted() {
            InterpretedTrackpadPointer.shared.enable(devices: selectedTouchDeviceIDs)
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
        pauseNativeMouseOutput()
        OMSManager.shared.endNativeTakeover()
        updateNativeFilterStatus()
        try? FileManager.default.removeItem(atPath: "/tmp/GesturePad-active-usb-capture.txt")
        let interfaceIdentity = held.first(where: { $0.identity.registryID == singleInterfaceTestID })?.identity
        usbModeRequestAt = nil
        gainProbe.restore()
        pointerControl.stop()
        pointerIdentityProbe.stop()
        InterpretedTrackpadPointer.shared.stop()
        timer?.invalidate()
        timer = nil
        deadline = nil
        isContinuous = false
        var failed: [HIDBlackholeOpenDevice] = []
        var captured: [HIDRawCapture.Interface] = []
        for handle in held {
            let result = handle.close()
            if let snapshot = handle.finishCapture() { captured.append(snapshot) }
            let reports = handle.reports.withLock { $0 }
            openResults.append("RID \(handle.identity.registryID) — final \(reports.count) reports / \(reports.bytes) bytes, last ID \(reports.lastID), length \(reports.lastLength)")
            openResults.append("\(Self.describe(handle.identity)) — close \(Self.status(result))")
            if result != kIOReturnSuccess { failed.append(handle) }
        }
        finishHIDCapture(reason: reason, interfaces: captured)
        held = failed
        isActive = openIsExclusive && !held.isEmpty
        isObservingHID = !openIsExclusive && !held.isEmpty
        secondsRemaining = 0
        summary = hasOpenHIDDevices ? "Release failed for \(held.count) interface(s). Retry Release, or quit the app." : "Released. Normal HID ownership restored."
        diagnostics = openResults.joined(separator: "\n")
        if let interfaceIdentity {
            InterfaceTouchEvidence.shared.stop()
            saveSingleInterfaceResult(identity: interfaceIdentity, status: "\(reason). \(summary)")
        }
        if usbModeAttempted {
            captureStatus += " USB mode was requested; reconnect the USB pad if native behavior does not recover after release."
        }
        usbModeAttempted = false
        singleInterfaceTestID = nil
    }

    private func tick() {
        if let requestAt = usbModeRequestAt, ProcessInfo.processInfo.systemUptime >= requestAt {
            usbModeRequestAt = nil
            if let id = singleInterfaceTestID, let handle = held.first(where: { $0.identity.registryID == id }) {
                let before = handle.reports.withLock { $0.count }
                let time = ProcessInfo.processInfo.systemUptime - captureStartedUptime
                let result = handle.requestUSBMultitouchMode()
                usbModeAttempted = true
                openResults.append("USB multitouch feature request at +\(time)s; ID 02, bytes 02 01; before \(before) reports; result \(Self.status(result)). No reverse mode command is assumed.")
                captureStatus = "USB multitouch request: \(Self.status(result)). Recording packets regardless of result."
            }
        }
        if let captureDeadline {
            let remaining = max(0, Int(ceil(captureDeadline - ProcessInfo.processInfo.systemUptime)))
            let count = held.reduce(0) { $0 + $1.captureReportCount }
            let dropped = held.reduce(0) { $0 + $1.captureDroppedCount }
            let values = held.reduce(UInt64(0)) { total, handle in
                total + handle.reports.withLock { $0.valueCount }
            }
            captureStatus = "Recording \(captureMode) HID: \(remaining)s · \(count) reports · \(values) values · \(dropped) dropped"
            if remaining == 0 { release(reason: "15-second HID capture completed"); return }
        }
        if let deadline, Date() >= deadline {
            release(reason: singleInterfaceTestID != nil ? "15-second single-interface test ended" : "30-second test ended")
            return
        }
        updateReadout()
    }

    private func updateReadout() {
        if let id = singleInterfaceTestID, let handle = held.first(where: { $0.identity.registryID == id }) {
            secondsRemaining = max(0, Int(ceil(deadline?.timeIntervalSinceNow ?? 0)))
            summary = "ONE interface: \(handle.identity.transport) \(String(format: "%04X:%04X", handle.identity.usagePage, handle.identity.usage)) RID \(id) · release in \(secondsRemaining)s · \(handle.captureReportCount) raw reports (\(handle.captureDroppedCount) dropped) · \(InterfaceTouchEvidence.shared.summary())"
            saveSingleInterfaceResult(identity: handle.identity, status: summary)
            return
        }
        secondsRemaining = max(0, Int(ceil(deadline?.timeIntervalSinceNow ?? 0)))
        let total = groups.filter { selectedGroupIDs.contains($0.id) }.flatMap(\.interfaces).filter { !$0.isKeyboard }.count
        let timing = isContinuous ? "enabled until released" : "auto-release in \(secondsRemaining)s"
        let pointer = "Apple contact data may stop while seized; raw HID capture is available below."
        summary = openIsExclusive
            ? "Seized \(held.count)/\(total) eligible interfaces · \(timing). \(pointer)"
            : "Observing \(held.count)/\(total) interfaces · normal trackpad input remains enabled."
        let reports = held.map { handle in
            let value = handle.reports.withLock { $0 }
            return "RID \(handle.identity.registryID): \(value.count) reports / \(value.bytes) bytes · last ID \(value.lastID), length \(value.lastLength), \(Self.status(value.lastResult))"
        }
        diagnostics = (openResults + reports).joined(separator: "\n")
    }

    private static func inputMonitoringStatus() -> String {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return "granted"
        case kIOHIDAccessTypeDenied: return "denied"
        default: return "unknown"
        }
    }

    private static func describe(_ device: HIDBlackholeIdentity) -> String {
        "RID \(device.registryID) · VID \(device.vendor) PID \(device.productID) · \(device.transport) · usage \(String(format: "%04X:%04X", device.usagePage, device.usage))"
    }
    private static func status(_ result: IOReturn) -> String {
        let message = mach_error_string(result).map { String(cString: $0) } ?? "unknown"
        return String(format: "0x%08X", UInt32(bitPattern: result)) + " (" + message + ")"
    }
}

/// Bounded aggregates keep event-tap work small. Labels describe the requested
/// test phase, not an inferred device identity.
struct PointerIdentityStats: Codable, Sendable {
    struct Bucket: Codable, Sendable {
        let phase: String
        let eventType: UInt32
        let hasHIDEvent: Bool
        let senderID: UInt64
        var count: Int = 0
        var deltaX: Int64 = 0
        var deltaY: Int64 = 0
    }
    private(set) var buckets: [Bucket] = []
    private(set) var totalEvents = 0
    private(set) var overflowEvents = 0
    private(set) var missingHIDEvents = 0
    private(set) var zeroSenderEvents = 0

    static func phase(elapsed: Double) -> String {
        switch elapsed {
        case ..<10: return "left-pad"
        case ..<20: return "right-pad"
        case ..<30: return "mouse"
        case ..<40: return "mixed"
        default: return "complete"
        }
    }

    mutating func record(phase: String, type: UInt32, hasHIDEvent: Bool, senderID: UInt64,
                         dx: Int64, dy: Int64) {
        totalEvents += 1
        if !hasHIDEvent { missingHIDEvents += 1 }
        else if senderID == 0 { zeroSenderEvents += 1 }
        let index: Int
        if let match = buckets.firstIndex(where: {
            $0.phase == phase && $0.eventType == type && $0.hasHIDEvent == hasHIDEvent && $0.senderID == senderID
        }) { index = match }
        else {
            guard buckets.count < 256 else { overflowEvents += 1; return }
            index = buckets.count
            buckets.append(Bucket(phase: phase, eventType: type, hasHIDEvent: hasHIDEvent, senderID: senderID))
        }
        buckets[index].count += 1
        buckets[index].deltaX &+= dx
        buckets[index].deltaY &+= dy
    }
}

/// Observation only. This class cannot swallow or synthesize an event.
@MainActor
final class PointerIdentityProbe: ObservableObject {
    private typealias CopyHIDEvent = @convention(c) (CGEvent) -> Unmanaged<CFTypeRef>?
    private typealias GetSenderID = @convention(c) (CFTypeRef) -> UInt64
    struct RegistryNode: Codable, Sendable {
        let registryID: UInt64
        let properties: [String: String]
    }
    struct Sender: Codable, Sendable {
        let senderID: UInt64
        let ancestry: [RegistryNode]
    }
    private struct Snapshot: Encodable, Sendable {
        let format = "GesturePad.PointerIdentity"
        let version = 1
        let status: String
        let startedAt: Date
        let elapsed: Double
        let phase: String
        let osVersion: String
        let copyHIDEventAvailable: Bool
        let getSenderIDAvailable: Bool
        let tapInterruptions: Int
        let selectedTrackpads: [HIDBlackholeExperiment.Group]
        let senders: [Sender]
        let stats: PointerIdentityStats
    }

    static let outputURL = URL(fileURLWithPath: "/tmp/GesturePad-pointer-identity.json")
    @Published private(set) var isObserving = false
    @Published private(set) var status = "Pointer source test: 10s left pad, 10s right pad, 10s mouse, 10s mixed."
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var copyHIDEvent: CopyHIDEvent?
    private var getSenderID: GetSenderID?
    private var stats = PointerIdentityStats()
    private var senders: [UInt64: Sender] = [:]
    private var selectedTrackpads: [HIDBlackholeExperiment.Group] = []
    private var startedAt = Date()
    private var startedUptime: Double = 0
    private var tapInterruptions = 0
    private let writer = DispatchQueue(label: "GesturePad.PointerIdentity.export", qos: .utility)

    func start(selectedTrackpads: [HIDBlackholeExperiment.Group]) {
        guard !isObserving else { return }
        // Resolve private symbols at runtime; missing symbols are captured as a
        // diagnostic result, never replaced by timing-based device guesses.
        if let process = dlopen(nil, RTLD_NOW) {
            if let symbol = dlsym(process, "CGEventCopyIOHIDEvent") {
                copyHIDEvent = unsafeBitCast(symbol, to: CopyHIDEvent.self)
            }
            if let symbol = dlsym(process, "IOHIDEventGetSenderID") {
                getSenderID = unsafeBitCast(symbol, to: GetSenderID.self)
            }
            dlclose(process)
        }
        stats = PointerIdentityStats()
        senders = [:]
        tapInterruptions = 0
        self.selectedTrackpads = selectedTrackpads
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, context in
                if let context {
                    let owner = Unmanaged<PointerIdentityProbe>.fromOpaque(context).takeUnretainedValue()
                    MainActor.assumeIsolated { owner.receive(type: type, event: event) }
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            status = "Pointer observer could not start. Check GesturePad Input Monitoring access and relaunch."
            return
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            status = "Pointer observer could not create its event source."
            return
        }
        self.tap = tap
        self.source = source
        startedAt = Date()
        startedUptime = ProcessInfo.processInfo.systemUptime
        isObserving = true
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        tick()
    }

    private func receive(type: CGEventType, event: CGEvent) {
        guard isObserving else { return }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            tapInterruptions += 1
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - startedUptime
        guard elapsed < 40 else { return }
        let hid = copyHIDEvent?(event)?.takeRetainedValue()
        let sender = hid.flatMap { getSenderID?($0) } ?? 0
        stats.record(phase: PointerIdentityStats.phase(elapsed: elapsed), type: type.rawValue,
            hasHIDEvent: hid != nil, senderID: sender,
            dx: event.getIntegerValueField(.mouseEventDeltaX), dy: event.getIntegerValueField(.mouseEventDeltaY))
    }

    private func tick() {
        guard isObserving else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - startedUptime
        if elapsed >= 40 { stop(completed: true); return }
        let phase = PointerIdentityStats.phase(elapsed: elapsed)
        let remaining = 10 - Int(elapsed) % 10
        status = "MOVE \(phase) · \(remaining)s · \(stats.totalEvents) events · \(stats.missingHIDEvents) without HID · \(stats.zeroSenderEvents) zero sender"
        // Do registry work and file encoding outside the event-tap callback.
        export(status: "running", elapsed: elapsed)
    }

    func stop(completed: Bool = false) {
        guard isObserving else { return }
        isObserving = false
        timer?.invalidate()
        timer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        let elapsed = ProcessInfo.processInfo.systemUptime - startedUptime
        export(status: completed ? "completed" : "stopped", elapsed: elapsed)
        status = "Stopped · \(stats.totalEvents) events. Results: \(Self.outputURL.path)"
    }

    private func export(status: String, elapsed: Double) {
        for id in Set(stats.buckets.map(\.senderID)) where id != 0 && senders[id] == nil {
            senders[id] = Sender(senderID: id, ancestry: Self.registryAncestry(sender: id))
        }
        let snapshot = Snapshot(status: status, startedAt: startedAt, elapsed: elapsed,
            phase: PointerIdentityStats.phase(elapsed: elapsed), osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            copyHIDEventAvailable: copyHIDEvent != nil, getSenderIDAvailable: getSenderID != nil,
            tapInterruptions: tapInterruptions, selectedTrackpads: selectedTrackpads,
            senders: senders.values.sorted { $0.senderID < $1.senderID }, stats: stats)
        let outputURL = Self.outputURL
        writer.async { [weak self] in
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
                try encoder.encode(snapshot).write(to: outputURL, options: .atomic)
            } catch {
                let message = error.localizedDescription
                Task { @MainActor [weak self] in
                    self?.status = "Pointer results could not be written: \(message)"
                }
            }
        }
    }

    private static func registryAncestry(sender: UInt64) -> [RegistryNode] {
        var entry = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(sender))
        var nodes: [RegistryNode] = []
        while entry != 0, nodes.count < 8 {
            var id: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(entry, &id)
            var properties: [String: String] = [:]
            for key in ["Product", "Transport", "SerialNumber", "VendorID", "ProductID", "PrimaryUsagePage", "PrimaryUsage"] {
                if let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
                    properties[key] = String(describing: value)
                }
            }
            nodes.append(RegistryNode(registryID: id, properties: properties))
            var parent: io_registry_entry_t = 0
            let result = IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent)
            IOObjectRelease(entry)
            entry = result == KERN_SUCCESS ? parent : 0
        }
        if entry != 0 { IOObjectRelease(entry) }
        return nodes
    }
}

struct SelectedTrackpadEventPolicy {
    static let interpreterTag: Int64 = 5138699878734057044
    static func matches(ancestry: [UInt64], selectedInterfaces: Set<UInt64>) -> Bool {
        ancestry.contains { selectedInterfaces.contains($0) }
    }
    static func suppress(type: UInt32, senderID: UInt64, selectedSenders: Set<UInt64>, tag: Int64) -> Bool {
        tag != interpreterTag && senderID != 0 && selectedSenders.contains(senderID)
            && (type == CGEventType.mouseMoved.rawValue || type == CGEventType.scrollWheel.rawValue)
    }
}

/// Device-specific output filtering; no HID devices are opened or seized.
@MainActor
final class SelectedTrackpadEventFilter: ObservableObject {
    private typealias CopyHIDEvent = @convention(c) (CGEvent) -> Unmanaged<CFTypeRef>?
    private typealias GetSenderID = @convention(c) (CFTypeRef) -> UInt64
    @Published private(set) var isActive = false
    @Published private(set) var status = "Off. Native movement and scrolling are enabled."
    @Published var synthesizeTwoFingerPointer = true {
        didSet {
            guard isActive else { return }
            updateInterpreter()
            updateStatus()
        }
    }
    private var touchDevices: Set<UInt64> = []
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var deadline: Double?
    private var copyHIDEvent: CopyHIDEvent?
    private var getSenderID: GetSenderID?
    private var selectedSenders: Set<UInt64> = []
    private var selectedGroups: [HIDBlackholeExperiment.Group] = []
    private var movements = 0
    private var scrolls = 0
    private var unknown = 0

    func start(groups: [HIDBlackholeExperiment.Group], touchDevices: Set<UInt64>, duration: TimeInterval?) {
        if isActive { configureDuration(duration); return }
        guard !groups.isEmpty, !touchDevices.isEmpty else {
            status = "Select trackpads before taking control."
            return
        }
        guard AXIsProcessTrusted() else {
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            status = "Enable GesturePad in Accessibility, then retry taking control."
            return
        }
        if let process = dlopen(nil, RTLD_NOW) {
            if let symbol = dlsym(process, "CGEventCopyIOHIDEvent") {
                copyHIDEvent = unsafeBitCast(symbol, to: CopyHIDEvent.self)
            }
            if let symbol = dlsym(process, "IOHIDEventGetSenderID") {
                getSenderID = unsafeBitCast(symbol, to: GetSenderID.self)
            }
            dlclose(process)
        }
        guard copyHIDEvent != nil, getSenderID != nil else {
            status = "Device identity APIs unavailable. Native input remains enabled."
            return
        }
        selectedGroups = groups
        let routing = Self.resolveSenders(groups: groups)
        guard routing.matchedGroups == Set(groups.map(\.id)) else {
            status = "Could not identify pointer services for every selected pad. Refresh trackpads and retry."
            return
        }
        selectedSenders = routing.senders
        movements = 0; scrolls = 0; unknown = 0
        self.touchDevices = touchDevices
        let types: [CGEventType] = [.mouseMoved, .scrollWheel, .leftMouseDragged, .rightMouseDragged,
            .otherMouseDragged, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<SelectedTrackpadEventFilter>.fromOpaque(context).takeUnretainedValue()
                let suppress = MainActor.assumeIsolated { owner.shouldSuppress(type: type, event: event) }
                return suppress ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
                status = "Could not install pointer filter. Native input remains enabled."
                selectedSenders = []
                return
            }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            status = "Could not schedule pointer filter. Native input remains enabled."
            return
        }
        self.tap = tap; self.source = source
        isActive = true
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        updateInterpreter()
        configureDuration(duration)
    }

    private func updateInterpreter() {
        if isActive && synthesizeTwoFingerPointer {
            InterpretedTrackpadPointer.shared.enable(devices: touchDevices)
        } else { InterpretedTrackpadPointer.shared.stop() }
    }

    private func configureDuration(_ duration: TimeInterval?) {
        deadline = duration.map { ProcessInfo.processInfo.systemUptime + $0 }
        timer?.invalidate()
        timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        updateStatus()
    }

    private func shouldSuppress(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            stop(message: "Control stopped because the event tap was disabled. Native input restored.")
            return false
        }
        guard isActive else { return false }
        if let deadline, ProcessInfo.processInfo.systemUptime >= deadline {
            stop()
            return false
        }
        let tag = event.getIntegerValueField(.eventSourceUserData)
        if tag == SelectedTrackpadEventPolicy.interpreterTag {
            return false
        }
        // Track allowed cursor destinations, including native physical/OS drag.
        // Buttons and drag are observed only to keep the cursor anchor current.
        guard type == .mouseMoved || type == .scrollWheel else {
            return false
        }
        let hid = copyHIDEvent?(event)?.takeRetainedValue()
        let senderID = hid.flatMap { getSenderID?($0) } ?? 0
        if senderID == 0 {
            unknown += 1
            return false
        }
        let suppress = SelectedTrackpadEventPolicy.suppress(type: type.rawValue,
            senderID: senderID, selectedSenders: selectedSenders, tag: tag)
        if suppress {
            if type == .mouseMoved { movements += 1 } else { scrolls += 1 }
        }
        return suppress
    }

    private func tick() {
        guard isActive else { return }
        if let deadline, ProcessInfo.processInfo.systemUptime >= deadline { stop(); return }
        // Recheck ancestry outside the event callback. Disconnects or changed
        // service identities stop control rather than broadening its scope.
        let current = Self.resolveSenders(groups: selectedGroups)
        guard current.matchedGroups == Set(selectedGroups.map(\.id)), current.senders == selectedSenders else {
            stop(message: "Trackpad services changed. Released; refresh and enable control again.")
            return
        }
        updateStatus()
    }

    private func updateStatus() {
        let timing = deadline.map { "release in \(max(0, Int(ceil($0 - ProcessInfo.processInfo.systemUptime))))s" } ?? "until released"
        let synthesis = synthesizeTwoFingerPointer ? "2-finger synthesis ON" : "2-finger synthesis OFF"
        status = "Controlling \(selectedGroups.count) pad(s) · \(timing) · discarded \(movements) movement events (native cursor still enabled) / blocked \(scrolls) scrolls · \(unknown) unidentified passed · \(synthesis) (\(InterpretedTrackpadPointer.shared.postedEventCount) posted)"

    }

    func stop(message: String = "Released. Normal trackpad input restored.") {
        guard isActive else { return }
        isActive = false
        InterpretedTrackpadPointer.shared.stop()
        timer?.invalidate(); timer = nil; deadline = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
        selectedSenders = []; selectedGroups = []; touchDevices = []
        status = message
    }

    private static func resolveSenders(groups: [HIDBlackholeExperiment.Group]) -> (senders: Set<UInt64>, matchedGroups: Set<String>) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDEventService"), &iterator) == KERN_SUCCESS else {
            return ([], [])
        }
        defer { IOObjectRelease(iterator) }
        var senders: Set<UInt64> = [], matched: Set<String> = []
        let targets = groups.map { ($0.id, Set($0.interfaces.map(\.registryID))) }
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            var id: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &id)
            let ancestry = registryAncestry(service: service)
            for (group, interfaces) in targets where SelectedTrackpadEventPolicy.matches(ancestry: ancestry, selectedInterfaces: interfaces) {
                senders.insert(id); matched.insert(group)
                // AppleMultitouchDevice publishes the actual sender beneath the
                // HID event driver on this OS. User-client objects are excluded.
                var children: io_iterator_t = 0
                if IORegistryEntryCreateIterator(service, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &children) == KERN_SUCCESS {
                    while true {
                        let child = IOIteratorNext(children)
                        guard child != 0 else { break }
                        if IOObjectConformsTo(child, "AppleMultitouchDevice") != 0 {
                            var childID: UInt64 = 0
                            IORegistryEntryGetRegistryEntryID(child, &childID)
                            senders.insert(childID)
                        }
                        IOObjectRelease(child)
                    }
                    IOObjectRelease(children)
                }
            }
            IOObjectRelease(service)
        }
        return (senders, matched)
    }

    private static func registryAncestry(service: io_registry_entry_t) -> [UInt64] {
        IOObjectRetain(service)
        var entry = service
        var ancestry: [UInt64] = []
        while entry != 0, ancestry.count < 16 {
            var id: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(entry, &id)
            ancestry.append(id)
            var parent: io_registry_entry_t = 0
            let result = IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent)
            IOObjectRelease(entry)
            entry = result == KERN_SUCCESS ? parent : 0
        }
        if entry != 0 { IOObjectRelease(entry) }
        return ancestry
    }
}

/// Read-only system preference status, matching the reference GTK indicator.
enum GesturePadThreeFingerDragStatus {
    static func detected() -> Bool? {
        let candidates: [(String, CFString, CFString)] = [
            ("com.apple.trackpad.threeFingerDragGesture", kCFPreferencesAnyApplication, kCFPreferencesCurrentHost),
            ("TrackpadThreeFingerDrag", "com.apple.driver.AppleBluetoothMultitouch.trackpad" as CFString, kCFPreferencesAnyHost),
            ("TrackpadThreeFingerDrag", "com.apple.AppleMultitouchTrackpad" as CFString, kCFPreferencesAnyHost)
        ]
        for (key, domain, host) in candidates {
            if let value = CFPreferencesCopyValue(key as CFString, domain, kCFPreferencesCurrentUser, host),
               let result = parse(value) { return result }
        }
        return nil
    }
    static func parse(_ value: Any) -> Bool? {
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "on", "1": return true
            case "false", "no", "off", "0": return false
            default: break
            }
        }
        return nil
    }
}

/// Timed per-service gain experiment. Never writes defaults or global properties.
@MainActor
final class TrackpadGainProbe: ObservableObject {
    private typealias Create = @convention(c) (CFAllocator?, UInt32, CFDictionary?) -> Unmanaged<CFTypeRef>?
    private typealias Services = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias Copy = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    private typealias SetProperty = @convention(c) (CFTypeRef, CFString, CFTypeRef) -> Bool
    private typealias RegistryID = @convention(c) (CFTypeRef) -> Unmanaged<CFTypeRef>?
    private struct Original {
        let service: CFTypeRef
        let id: UInt64
        let value: NSNumber
    }
    @Published private(set) var isActive = false
    @Published private(set) var status = "Minimum-gain test: selected pads only, synthesis off, restores after 15s."
    private let key = "HIDPointerAccelerationMultiplier" as CFString
    private var originals: [Original] = []
    private var client: CFTypeRef?
    private var setter: SetProperty?
    private var copy: Copy?
    private var timer: Timer?
    private var deadline: Double = 0
    private var lastSampleSecond = -1
    private var log: [String] = []

    func start(groups: [HIDBlackholeExperiment.Group]) {
        guard !isActive, !groups.isEmpty, let process = dlopen(nil, RTLD_NOW) else { return }
        defer { dlclose(process) }
        guard let createSymbol = dlsym(process, "IOHIDEventSystemClientCreateWithType"),
              let servicesSymbol = dlsym(process, "IOHIDEventSystemClientCopyServices"),
              let copySymbol = dlsym(process, "IOHIDServiceClientCopyProperty"),
              let setSymbol = dlsym(process, "IOHIDServiceClientSetProperty"),
              let idSymbol = dlsym(process, "IOHIDServiceClientGetRegistryID") else {
            status = "Per-service property APIs unavailable. No values changed."
            return
        }
        let create = unsafeBitCast(createSymbol, to: Create.self)
        let services = unsafeBitCast(servicesSymbol, to: Services.self)
        let copy = unsafeBitCast(copySymbol, to: Copy.self)
        let setter = unsafeBitCast(setSymbol, to: SetProperty.self)
        let registryID = unsafeBitCast(idSymbol, to: RegistryID.self)
        guard let client = create(kCFAllocatorDefault, 2, nil)?.takeRetainedValue(),
              let available = services(client)?.takeRetainedValue() as? [AnyObject] else {
            status = "Could not enumerate pointer services. No values changed."
            return
        }
        log = ["Precheck: \(groups.count) selected pad(s); multiplier fixed-point value 1 for 15s"]
        let targets = groups.map { ($0.id, Set($0.interfaces.map(\.registryID))) }
        var matched: Set<String> = []
        var candidates: [Original] = []
        for service in available {
            // GetRegistryID returns a borrowed CFNumber, not a raw UInt64.
            guard let number = registryID(service)?.takeUnretainedValue() as? NSNumber else { continue }
            let id = number.uint64Value
            let path = Self.ancestry(id)
            for (group, interfaces) in targets where SelectedTrackpadEventPolicy.matches(ancestry: path, selectedInterfaces: interfaces) {
                // Only alter services with an existing numeric value, so exact
                // restoration never depends on a guessed default or deletion.
                let value = copy(service, key)?.takeRetainedValue() as? NSNumber
                log.append("Matched selected group \(group), service RID \(id), original multiplier \(value?.description ?? "missing")")
                if let value {
                    candidates.append(Original(service: service, id: id, value: value))
                    matched.insert(group)
                }
            }
        }
        guard matched == Set(groups.map(\.id)), !candidates.isEmpty else {
            let missing = groups.filter { !matched.contains($0.id) }.map(\.label).joined(separator: "; ")
            status = "No restorable multiplier for: \(missing). No values changed."
            save()
            return
        }
        self.client = client; self.setter = setter; self.copy = copy
        log.append("Property: HIDPointerAccelerationMultiplier; proposed fixed-point value: 1; duration: 15s")
        for original in candidates {
            originals.append(original) // Retain original before attempting write.
            let accepted = setter(original.service, key, NSNumber(value: 1))
            let readback = copy(original.service, key)?.takeRetainedValue() as? NSNumber
            log.append("RID \(original.id): original \(original.value), write accepted \(accepted), readback \(readback?.description ?? "missing")")
            guard accepted else {
                restore()
                status = isActive
                    ? "Minimum-gain write rejected; restoration needs retry. Use Restore pointer gain."
                    : "Minimum-gain write rejected; original readbacks match after restoration."
                save()
                return
            }
        }
        isActive = true
        lastSampleSecond = -1
        deadline = ProcessInfo.processInfo.systemUptime + 15
        timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        tick()
    }

    private func tick() {
        let remaining = max(0, Int(ceil(deadline - ProcessInfo.processInfo.systemUptime)))
        if remaining == 0 { restore(); return }
        let elapsed = 15 - remaining
        if elapsed != lastSampleSecond, let copy {
            lastSampleSecond = elapsed
            for original in originals {
                let value = copy(original.service, key)?.takeRetainedValue() as? NSNumber
                log.append("After \(elapsed)s, RID \(original.id): readback \(value?.description ?? "missing") (accepted write remains under physical test)")
            }
        }
        status = "Accepted minimum-gain writes · \(remaining)s · effect unverified: move one finger; check contacts and mouse."
        save()
    }

    func restore() {
        timer?.invalidate(); timer = nil
        guard !originals.isEmpty, let setter, let copy else { return }
        for original in originals {
            let value = copy(original.service, key)?.takeRetainedValue() as? NSNumber
            log.append("Before restore, RID \(original.id): final test readback \(value?.description ?? "missing")")
        }
        var failures: [Original] = []
        for original in originals {
            let accepted = setter(original.service, key, original.value)
            let readback = copy(original.service, key)?.takeRetainedValue() as? NSNumber
            let verified = accepted && readback == original.value
            log.append("RID \(original.id): restore accepted \(accepted), readback \(readback?.description ?? "missing"), verified \(verified)")
            if !verified { failures.append(original) }
        }
        originals = failures
        isActive = !failures.isEmpty
        status = failures.isEmpty ? "Original pointer multipliers restored. Normal native movement enabled."
            : "Could not verify restoration for \(failures.count) service(s). Retry Release Trackpads."
        if failures.isEmpty { client = nil }
        save()
    }

    private func save() {
        let report: [String: Any] = ["format": "GesturePad.TrackpadGainProbe", "active": isActive,
            "status": status, "log": log, "note": "Readback is not proof of physical suppression. No synthesis, cursor correction or global changes."]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/GesturePad-gain-probe.json"), options: .atomic)
        }
    }

    private static func ancestry(_ id: UInt64) -> [UInt64] {
        var entry = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(id))
        var path: [UInt64] = []
        while entry != 0, path.count < 16 {
            var current: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(entry, &current); path.append(current)
            var parent: io_registry_entry_t = 0
            let result = IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent)
            IOObjectRelease(entry); entry = result == KERN_SUCCESS ? parent : 0
        }
        if entry != 0 { IOObjectRelease(entry) }
        return path
    }
}

/// Lock-protected evidence at the live ingestion boundary, independent of output.
final class InterfaceTouchEvidence: @unchecked Sendable {
    static let shared = InterfaceTouchEvidence()
    private struct State {
        var active = false
        var devices: Set<UInt64> = []
        var frames: [UInt64: Int] = [:]
        var nonempty: [UInt64: Int] = [:]
    }
    private let lock = OSAllocatedUnfairLock(initialState: State())
    func start(devices: Set<UInt64>) {
        lock.withLock { $0 = State(active: true, devices: devices) }
    }
    func stop() { lock.withLock { $0.active = false } }
    func record(_ frame: OMSRawTouchFrame) {
        lock.withLock {
            guard $0.active, $0.devices.contains(frame.deviceIDNumeric) else { return }
            $0.frames[frame.deviceIDNumeric, default: 0] += 1
            if !frame.touches.isEmpty { $0.nonempty[frame.deviceIDNumeric, default: 0] += 1 }
        }
    }
    func snapshot() -> [[String: String]] {
        lock.withLock { state in state.devices.sorted().map {
            ["deviceID": String($0), "frames": String(state.frames[$0, default: 0]),
             "nonemptyFrames": String(state.nonempty[$0, default: 0])]
        } }
    }
    func summary() -> String {
        lock.withLock { state in
            "OMS: \(state.frames.values.reduce(0,+)) frames / \(state.nonempty.values.reduce(0,+)) with contacts"
        }
    }
}

// Shared tracker/output used by the opt-in native FLTR mouse test and legacy diagnostics.
/// Experimental two-contact relative pointer; per-device baselines never cross pads.
struct TwoFingerPointerTracker {
    struct Baseline { let first: Int32; let second: Int32; let point: CGPoint; let time: Double }
    private var baselines: [UInt64: Baseline] = Dictionary(minimumCapacity: 2)
    mutating func reset() { baselines.removeAll(keepingCapacity: true) }
    mutating func reset(device: UInt64) { baselines[device] = nil }
    mutating func process(device: UInt64, time: Double, touches: OMSRawTouchBufferView) -> CGPoint? {
        process(device: device, time: time, contacts: touches)
    }
    mutating func process<C: Collection>(device: UInt64, time: Double, contacts: C) -> CGPoint? where C.Element == OMSRawTouch {
        var first: OMSRawTouch?, second: OMSRawTouch?
        var count = 0
        for touch in contacts where touch.state == .making || touch.state == .touching {
            count += 1
            if count > 2 || touch.telemetry?.fingerID == 6 {
                baselines.removeValue(forKey: device); return nil
            }
            if first == nil { first = touch } else { second = touch }
        }
        guard count == 2, let a = first, let b = second,
              a.id != b.id, time.isFinite,
              a.posX.isFinite, a.posY.isFinite, b.posX.isFinite, b.posY.isFinite else {
            baselines.removeValue(forKey: device); return nil
        }
        let point = CGPoint(x: Double(a.posX + b.posX) / 2, y: Double(a.posY + b.posY) / 2)
        let next = Baseline(first: min(a.id, b.id), second: max(a.id, b.id), point: point, time: time)
        let old = baselines.updateValue(next, forKey: device)
        guard let old, old.first == next.first, old.second == next.second,
              time > old.time, time - old.time < 0.15 else { return nil }
        // Provisional constant gain: 6 screen points per mm on a 160 x 114.9 mm pad.
        let delta = CGPoint(x: (point.x - old.point.x) * 160 * 6,
                            y: -(point.y - old.point.y) * 114.9 * 6)
        guard abs(delta.x) < 150, abs(delta.y) < 150 else { return nil }
        return delta
    }
}

final class InterpretedTrackpadPointer: @unchecked Sendable {
    static let shared = InterpretedTrackpadPointer()
    private struct State {
        var devices: Set<UInt64> = []
        var tracker = TwoFingerPointerTracker()
        var displayBounds: [CGRect] = []
        var postedEvents: UInt64 = 0
    }
    private let lock = OSAllocatedUnfairLock(initialState: State())
    func enable(devices: Set<UInt64>) {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        let bounds: [CGRect]
        if CGGetActiveDisplayList(16, &displays, &count) == .success {
            bounds = displays.prefix(Int(count)).map { CGDisplayBounds($0) }
        } else { bounds = [] }
        lock.withLock { state in
            for device in state.devices.symmetricDifference(devices) { state.tracker.reset(device: device) }
            state.devices = devices; state.displayBounds = bounds
        }
    }
    var postedEventCount: UInt64 { lock.withLock { $0.postedEvents } }
    func stop() { lock.withLock { $0.devices.removeAll(keepingCapacity: true); $0.tracker.reset() } }
    func resetBaseline() { lock.withLock { $0.tracker.reset() } }
    func resetBaseline(device: UInt64) { lock.withLock { $0.tracker.reset(device: device) } }
    func process(_ frame: OMSRawTouchFrame) {
        process(device: frame.deviceIDNumeric, time: frame.timestamp, contacts: frame.touches)
    }
    func process<C: Collection & Sendable>(device: UInt64, time: Double, contacts: C, suppress: Bool = false) where C.Element == OMSRawTouch {
        lock.withLock { state in
            guard state.devices.contains(device) else { return }
            // Native click-and-drag remains in charge while a mouse button is held.
            if suppress || CGEventSource.buttonState(.combinedSessionState, button: .left)
                || CGEventSource.buttonState(.combinedSessionState, button: .right)
                || CGEventSource.buttonState(.combinedSessionState, button: .center) {
                state.tracker.reset()
                return
            }
            guard
                  let delta = state.tracker.process(device: device,
                    time: time, contacts: contacts),
                  delta.x != 0 || delta.y != 0,
                  let current = CGEvent(source: nil)?.location else { return }
            var location = CGPoint(x: current.x + delta.x, y: current.y + delta.y)
            // Clamp to the nearest actual display, including negative-origin displays.
            var closest: CGPoint?; var distance = Double.infinity
            for bounds in state.displayBounds {
                let candidate = CGPoint(x: min(max(location.x, bounds.minX), bounds.maxX - 1),
                                        y: min(max(location.y, bounds.minY), bounds.maxY - 1))
                let dx = candidate.x - location.x, dy = candidate.y - location.y
                let d = dx * dx + dy * dy
                if d < distance { distance = d; closest = candidate }
            }
            if let closest { location = closest }
            guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                       mouseCursorPosition: location, mouseButton: .left) else { return }
            event.setIntegerValueField(.eventSourceUserData, value: SelectedTrackpadEventPolicy.interpreterTag)
            event.setDoubleValueField(.mouseEventDeltaX, value: delta.x)
            event.setDoubleValueField(.mouseEventDeltaY, value: delta.y)
            event.post(tap: .cghidEventTap)
            state.postedEvents &+= 1
        }
    }
}


/// Process-owned preference and selection reconciliation. No hardware is opened by init.
/// A failed transition is retried only after a selection/preference/explicit refresh change.
@MainActor
final class NativeTakeoverPreference: ObservableObject {
    static let defaultsKey = "GesturePad.nativeTrackpadTakeoverEnabled"
    @Published private(set) var enabled: Bool
    private let defaults: UserDefaults
    private let ownedIDs: () -> Set<UInt64>
    private let transition: ([UInt64]) -> Bool
    private let stop: () -> Void
    private var selection: Set<UInt64> = []
    private var attemptedSelection: Set<UInt64>?
    private var suspensions: Set<String> = []

    init(defaults: UserDefaults, ownedIDs: @escaping () -> Set<UInt64>,
         transition: @escaping ([UInt64]) -> Bool, stop: @escaping () -> Void) {
        self.defaults = defaults
        self.ownedIDs = ownedIDs
        self.transition = transition
        self.stop = stop
        enabled = defaults.bool(forKey: Self.defaultsKey)
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        defaults.set(value, forKey: Self.defaultsKey)
        attemptedSelection = nil
        if !value { stop() }
        reconcile()
    }

    @discardableResult
    func updateSelection(_ ids: [UInt64]) -> Bool {
        let next = Set(ids)
        guard selection != next || attemptedSelection == nil else { return true }
        guard reconcile(target: enabled ? next : []) else { return false }
        selection = next
        return true
    }

    @discardableResult
    func suspend(_ reason: String) -> Bool {
        suspensions.insert(reason)
        attemptedSelection = nil
        if !ownedIDs().isEmpty { stop() }
        return ownedIDs().isEmpty
    }

    func resume(_ reason: String) {
        suspensions.remove(reason)
        reconcile()
    }

    @discardableResult
    private func reconcile() -> Bool {
        reconcile(target: enabled ? selection : [])
    }

    private func reconcile(target: Set<UInt64>) -> Bool {
        guard suspensions.isEmpty else { return true }
        if ownedIDs() == target { return true }
        guard attemptedSelection != target else { return false }
        attemptedSelection = target
        if target.isEmpty {
            stop()
            return ownedIDs().isEmpty
        }
        return transition(target.sorted())
    }
}


/// Pure eligibility check; a failed transition's extra owned IDs are never output sources.
enum NativeTwoFingerMouseGate {
    static func outputDevices(enabled: Bool, armed: Bool, takeoverEnabled: Bool,
                              trusted: Bool, selected: Set<UInt64>, owned: Set<UInt64>) -> Set<UInt64> {
        guard enabled, armed, takeoverEnabled, trusted else { return [] }
        return selected.intersection(owned)
    }
}
