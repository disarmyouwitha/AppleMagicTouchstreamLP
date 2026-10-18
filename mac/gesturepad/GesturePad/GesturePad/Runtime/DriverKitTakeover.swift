import Darwin
import AppKit
import ApplicationServices
import Combine
import Foundation
import IOKit
import OpenMultitouchSupport
import os

/// Suppress duplicate OMS ingestion only for devices being delivered by DriverKit.
final class DriverInputSourceGate: @unchecked Sendable {
    static let shared = DriverInputSourceGate()
    private let lock = OSAllocatedUnfairLock(initialState: Set<UInt64>())
    func set(_ devices: Set<UInt64>) { lock.withLock { $0 = devices } }
    func contains(_ device: UInt64) -> Bool { lock.withLock { $0.contains(device) } }
}

struct MagicTrackpadPacket {
    let contacts: [OMSRawTouch]
    let buttons: UInt8
    static func decode(_ data: Data) -> Self? {
        let b = [UInt8](data)
        guard let id = b.first else { return nil }
        let offset: Int
        switch id { case 2: offset = 12; case 0x31: offset = 4; default: return nil }
        guard b.count >= offset, (b.count - offset) % 9 == 0,
              (b.count - offset) / 9 <= 15 else { return nil }
        func signed13(_ value: Int) -> Int { value & 0x1000 == 0 ? value : value - 0x2000 }
        var contacts: [OMSRawTouch] = []
        for i in stride(from: offset, to: b.count, by: 9) {
            let x = signed13(Int(b[i]) | (Int(b[i+1] & 0x1f) << 8))
            // Keep sensor Y upward like OMS; Linux negates it for input ABS_Y.
            let y = signed13((Int(b[i+1]) >> 5) | (Int(b[i+2]) << 3) | (Int(b[i+3] & 3) << 11))
            let down = b[i+3] & 0xc0 == 0x80
            contacts.append(OMSRawTouch(id: Int32(b[i+8] & 15),
                posX: Float(x + 3678) / 7612, posY: Float(y + 2587) / 5065,
                total: Float(b[i+6]), pressure: Float(b[i+7]),
                majorAxis: Float(b[i+4]), minorAxis: Float(b[i+5]),
                angle: Float(Int(b[i+8] >> 5) - 4), density: 0,
                state: down ? .touching : .leaving))
        }
        // Tracking IDs are not anatomical finger labels: telemetry stays nil.
        return Self(contacts: contacts, buttons: b[1] & 3)
    }
}

/// Fixed-size timer-published diagnostic stream; no user-client entitlement needed.
struct DriverStreamRecord {
    let sequence: UInt64
    let timestamp: Double
    let payload: Data
    static let stride = 176
    static func decodeBatch(_ data: Data) -> [Self]? {
        guard data.count == stride * 64 else { return nil }
        func number(_ offset: Int, _ count: Int) -> UInt64 {
            (0..<count).reduce(0) { $0 | (UInt64(data[offset + $1]) << ($1 * 8)) }
        }
        var records: [Self] = []
        for offset in Swift.stride(from: 0, to: data.count, by: stride) {
            let seq = number(offset, 8)
            if seq == 0 { continue }
            let length = Int(number(offset + 16, 4))
            guard (4...148).contains(length) else { return nil }
            let payload = data.subdata(in: (offset + 24)..<(offset + 24 + length))
            guard UInt64(payload[0]) == number(offset + 20, 4) else { return nil }
            records.append(Self(sequence: seq, timestamp: Double(number(offset + 8, 8)) / 1e9, payload: payload))
        }
        return records.sorted { $0.sequence < $1.sequence }
    }
}

struct DriverStreamCursor {
    private(set) var session: UInt64 = 0
    private(set) var lastSequence: UInt64 = 0
    mutating func take(session: UInt64, records: [DriverStreamRecord]) -> (records: [DriverStreamRecord], discontinuity: Bool) {
        let changed = self.session != session
        if changed { self.session = session; lastSequence = 0 }
        let fresh = records.filter { $0.sequence > lastSequence }
        let gap = fresh.first.map { $0.sequence != lastSequence + 1 } ?? false
        if let last = fresh.last { lastSequence = last.sequence }
        return (fresh, changed || gap)
    }
}

@MainActor
final class DriverKitTakeover: ObservableObject {
    static let knownSerials: Set<String> = ["J84HMA00H0B0000501", "D0:C0:50:D4:75:6C"]
    static let helperURL = URL(fileURLWithPath: "/Applications/GesturePadRawHIDProbe.app")
    @Published private(set) var isActive = false
    @Published private(set) var isRestoring = false
    @Published private(set) var status = "DriverKit ready. Takeover stays active until Release Trackpads."
    @Published var synthesizeTwoFingerPointer = true {
        didSet { updateInterpreter() }
    }
    var onContacts: ((UInt64, Int, Double, [OMSRawTouch]) async -> Void)?
    var onSessionBegan: (() -> Void)?
    var onSessionEnded: (() -> Void)?
    private var devices: [String: (id: UInt64, index: Int)] = [:]
    private var cursors: [String: DriverStreamCursor] = [:]
    private var lastFrame: [String: Double] = [:]
    private var task: Task<Void, Never>?
    private var received: UInt64 = 0
    private var perPad: [String: [String: Int]] = [:]
    private var lastDiagnostic = Date.distantPast
    private var gaps: UInt64 = 0
    private var token = ""
    private var began = Date()
    private var receivedAt: Date?
    private var helperState = ""
    private var observer: NSObjectProtocol?
    private var activeServices: [String: UInt64] = [:]
    private var restoreBegan: Date?
    var hasOwnershipRequest: Bool { isActive || isRestoring }

    init() {
        observer = DistributedNotificationCenter.default().addObserver(forName: .init("GesturePadDriverState"), object: nil, queue: .main) { [weak self] note in
            let session = note.object as? String
            let state = note.userInfo?["state"] as? String
            Task { @MainActor [weak self] in
                guard let self, session == self.token, let state else { return }
                self.helperState = state
            }
        }
    }

    func start(selected: [OMSDeviceInfo]) {
        guard !hasOwnershipRequest else { return }
        guard selected.count == 2, Set(selected.map(\.serialNumber)) == Self.knownSerials,
              selected.contains(where: { $0.serialNumber == "J84HMA00H0B0000501" && $0.transport == "USB" }),
              selected.contains(where: { $0.serialNumber == "D0:C0:50:D4:75:6C" && $0.transport == "Bluetooth" }),
              Set(selected.map(\.deviceIDNumeric)).count == 2 else {
            status = "This build requires both tested pads selected: J84HMA00H0B0000501 via USB and D0:C0:50:D4:75:6C via Bluetooth."
            return
        }
        guard let info = Bundle(url: Self.helperURL), info.infoDictionary?["CFBundleVersion"] as? String == "6" else {
            status = "Install the signed DriverKit helper v0.6 using DriverKitProbe/install-integration.sh first."
            return
        }
        if synthesizeTwoFingerPointer && !AXIsProcessTrusted() {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            status = "Grant GesturePad Accessibility access, then retry (or turn off synthetic pointer for a visual-only test)."
            return
        }
        devices = [:]
        for device in selected {
            guard let index = OMSManager.shared.deviceIndex(for: device.deviceID) else {
                status = "Refresh trackpads before starting DriverKit."; return
            }
            devices[device.serialNumber] = (device.deviceIDNumeric, index)
        }
        isActive = true; isRestoring = false; token = UUID().uuidString
        received = 0; gaps = 0; receivedAt = nil; began = Date(); helperState = ""
        cursors = [:]; lastFrame = [:]; activeServices = [:]; perPad = [:]
        NSLog("GesturePad DriverKit session %@ requested", token)
        // Source gate is enabled before activation and cleared only after restoration.
        onSessionBegan?()
        DriverInputSourceGate.shared.set(Set(devices.values.map(\.id)))
        updateInterpreter()
        status = "Requesting DriverKit. Approve AMT Raw HID Receiver in Driver Extensions; touch both pads once enabled."
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = ["--gesturepad-session", token, "--owner-pid", String(ProcessInfo.processInfo.processIdentifier)]
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Self.helperURL, configuration: config) { [weak self] _, error in
            if let error {
                Task { @MainActor [weak self] in self?.helperState = "error: \(error.localizedDescription)" }
            }
        }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.poll()
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    func release() {
        guard hasOwnershipRequest else { return }
        saveEvidence(reason: "release requested")
        isActive = false; isRestoring = true; restoreBegan = Date()
        InterpretedTrackpadPointer.shared.stop()
        status = "Releasing driver. macOS may ask for authorization; normal ownership is not confirmed yet."
        DistributedNotificationCenter.default().postNotificationName(.init("GesturePadDriverRelease"), object: token, userInfo: nil, deliverImmediately: true)
    }

    private func saveEvidence(reason: String) {
        let evidence: [String: Any] = ["schema": 1, "session": token, "build": 6,
            "reason": reason, "received": received, "gaps": gaps,
            "syntheticMoves": InterpretedTrackpadPointer.shared.postedEventCount,
            "pads": perPad, "helperState": helperState]
        let url = URL(fileURLWithPath: "/tmp/GesturePad-driverkit-session-\(token).json")
        do {
            try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
            NSLog("GesturePad DriverKit %@: %@", reason, url.path)
        } catch { NSLog("GesturePad DriverKit evidence failed: %@", error.localizedDescription) }
    }

    private func updateInterpreter() {
        if isActive && synthesizeTwoFingerPointer {
            InterpretedTrackpadPointer.shared.enable(devices: Set(devices.values.map(\.id)))
        } else { InterpretedTrackpadPointer.shared.stop() }
    }

    private func finishRestoration() async {
        saveEvidence(reason: "driver removed")
        task?.cancel(); task = nil
        for device in devices.values { await onContacts?(device.id, device.index, ProcessInfo.processInfo.systemUptime, []) }
        DriverInputSourceGate.shared.set([])
        isActive = false; isRestoring = false
        status = "Driver removed. Verify normal trackpad input has returned. Received \(received) packets; stream gaps \(gaps)."
        onSessionEnded?()
    }

    private func poll() async {
        if helperState == "removed" { await finishRestoration(); return }
        if helperState.hasPrefix("error:") {
            status = helperState + " Use the helper or Driver Extensions to remove the driver."
            if isActive { release() }
            return
        }
        if isRestoring {
            if Date().timeIntervalSince(restoreBegan ?? Date()) > 10 {
                status = "Restoration pending. Authorize driver removal in the helper, or disable AMT Raw HID Receiver in Driver Extensions."
            }
            return
        }
        guard isActive else { return }
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IOUserService") else { return }
        (matching as NSMutableDictionary)["IOPropertyMatch"] = ["IOUserClass": "AMTRawHIDReceiver"]
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        var found: Set<String> = []
        var ended = false
        var frames: [(String, DriverStreamRecord)] = []
        while true {
            let service = IOIteratorNext(iterator); if service == 0 { break }
            defer { IOObjectRelease(service) }
            var raw: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &raw, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let p = raw?.takeRetainedValue() as? [String: Any],
                  (p["StreamBuild"] as? NSNumber)?.intValue == 6,
                  let serial = p["StreamSerial"] as? String, devices[serial] != nil,
                  let session = (p["StreamSession"] as? NSNumber)?.uint64Value,
                  let data = p["StreamBatch"] as? Data,
                  let records = DriverStreamRecord.decodeBatch(data) else { continue }
            var rid: UInt64 = 0; IORegistryEntryGetRegistryEntryID(service, &rid)
            if let previous = activeServices[serial], previous != rid { ended = true }
            activeServices[serial] = rid
            found.insert(serial)
            if (p["StreamOpened"] as? NSNumber)?.intValue != 1 { ended = true }
            var cursor = cursors[serial] ?? DriverStreamCursor()
            let next = cursor.take(session: session, records: records); cursors[serial] = cursor
            if next.discontinuity {
                gaps += next.records.first?.sequence == 1 ? 0 : 1
                InterpretedTrackpadPointer.shared.resetBaseline()
            }
            frames += next.records.map { (serial, $0) }
        }
        // Stop on a disappeared previously opened service, never guess device identity.
        if !Set(activeServices.keys).isSubset(of: found) { ended = true }
        for (serial, record) in frames.sorted(by: { $0.1.timestamp < $1.1.timestamp }) {
            guard isActive, let device = devices[serial], let packet = MagicTrackpadPacket.decode(record.payload) else { continue }
            let sourceNow = Double(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1e9
            guard sourceNow >= record.timestamp, sourceNow - record.timestamp < 0.15 else {
                gaps += 1; InterpretedTrackpadPointer.shared.resetBaseline(); continue
            }
            let now = ProcessInfo.processInfo.systemUptime - (sourceNow - record.timestamp)
            // Source clock is monotonic-raw; only compare intervals within that clock.
            let previous = lastFrame[serial]; lastFrame[serial] = record.timestamp
            if let previous, record.timestamp <= previous || record.timestamp - previous > 0.15 {
                InterpretedTrackpadPointer.shared.resetBaseline()
            }
            received += 1
            perPad[serial, default: [:]]["packets", default: 0] += 1
            perPad[serial, default: [:]]["maxContacts"] = max(perPad[serial]?["maxContacts"] ?? 0,
                packet.contacts.filter { $0.state == .touching }.count)
            if receivedAt == nil { receivedAt = Date() }
            InterpretedTrackpadPointer.shared.process(device: device.id, time: record.timestamp,
                contacts: packet.contacts, suppress: packet.buttons != 0)
            await onContacts?(device.id, device.index, now, packet.contacts)
        }
        if Date().timeIntervalSince(lastDiagnostic) > 5 {
            lastDiagnostic = Date()
            NSLog("GesturePad DriverKit %@: %llu packets, %llu gaps, %llu synthetic moves", token, received, gaps,
                InterpretedTrackpadPointer.shared.postedEventCount)
        }
        if ended { release(); return }
        if receivedAt != nil {
            status = "DriverKit \(found.count)/2 pads · \(received) packets · gaps \(gaps) · synthetic moves \(InterpretedTrackpadPointer.shared.postedEventCount) · active until released"
        } else {
            status = "DriverKit \(found.count)/2 pads; waiting for touches. If pending, approve in Driver Extensions."
        }
    }
}
