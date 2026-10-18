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

/// Recovered Compact V7 integer conversions, independently checked against the
/// installed framework oracle. No private function addresses are used by the app.
struct CompactV7Scalars {
    private static func square(_ value: Int64) -> Int64 { value * value }
    private static func smallRadius(_ value: Int64, bias: UInt32) -> Int {
        let squared = UInt64(square(value * 1024 - 76800)) >> 10
        // Preserve the native36-bit coefficient and narrowing/shift order.
        let curved = UInt32(truncatingIfNeeded: (squared &* 0xfffffffd8) >> 10)
        return Int((curved &+ bias) >> 10)
    }
    static func major(_ byte: UInt8) -> Int {
        let v = Int64(byte)
        if v == 0 { return 0 }
        if v < 50 { return smallRadius(v, bias: 0xb5400) }
        if v <= 169 { return Int((UInt32(truncatingIfNeeded: v << 21) &+ 0x25800000) >> 20) }
        let curved = UInt32(truncatingIfNeeded: square(v * 1024 - 0x29800) >> 12)
        return Int((curved &+ 0xea000) >> 10)
    }
    static func minor(_ byte: UInt8) -> Int {
        let v = Int64(byte)
        if v == 0 { return 0 }
        if v < 50 { return smallRadius(v, bias: 0x9c400) }
        if v <= 149 { return Int((UInt32(truncatingIfNeeded: v << 21) &+ 0x1f400000) >> 20) }
        let curved = UInt32(truncatingIfNeeded: ((square(v * 1024 - 0x228f0) >> 10) * 0x57) >> 10)
        return Int((curved &+ 0xc50f0) >> 10)
    }
    static func total(_ byte: UInt8) -> Int {
        let v = Int64(byte)
        if v == 0 { return 0 }
        if v <= 149 { return Int((v * 0x28f5) >> 10) }
        let curved = UInt32(truncatingIfNeeded: ((square(v * 1024 - 0x1bfee) >> 10) * 0x8a) >> 10)
        return Int((curved &+ 0x14f568) >> 10)
    }
    static func pressure(_ byte: UInt8) -> Int {
        let v = Int64(byte)
        if v < 128 { return Int(v * 2) }
        let curved = UInt32(truncatingIfNeeded: square(v * 1024 - 0x1827b) >> 15)
        return Int((curved &+ 0x3827b) >> 10)
    }
    static func density(total: Int, major: Int, minor: Int) -> Int {
        // Parameters600/430 read from initialized native family0x81 state on both pads.
        let root = max(600, Int(Double(max(600, major) * max(600, minor)).squareRoot()))
        return Int(Int16(truncatingIfNeeded: total * 400 / (root - 430)))
    }
}

struct MagicTrackpadPacket {
    let contacts: [OMSRawTouch]
    let buttons: UInt8
    let sensorTicks: UInt32
    static func decode(_ data: Data) -> Self? {
        let b = [UInt8](data)
        guard let id = b.first else { return nil }
        let offset: Int
        switch id { case 2: offset = 12; case 0x31: offset = 4; default: return nil }
        guard b.count >= offset, (b.count - offset) % 9 == 0,
              (b.count - offset) / 9 <= 15 else { return nil }
        let header = offset - 4
        let ticks = UInt32(b[header+1] >> 3) | UInt32(b[header+2]) << 5 | UInt32(b[header+3]) << 13
        func signed13(_ value: Int) -> Int { value & 0x1000 == 0 ? value : value - 0x2000 }
        var contacts: [OMSRawTouch] = []
        for i in stride(from: offset, to: b.count, by: 9) {
            let x = signed13(Int(b[i]) | (Int(b[i+1] & 0x1f) << 8))
            let y = signed13((Int(b[i+1]) >> 5) | (Int(b[i+2]) << 3) | (Int(b[i+3] & 3) << 11))
            let state = [OMSState.notTouching, .starting, .hovering, .making,
                         .touching, .breaking, .lingering, .leaving][Int(b[i+3] >> 5)]
            // Actual Sensor Surface Descriptor bounds on both tested pads, in native 0.01 units.
            let ax = min(7869, max(-7356, x * 2)), ay = min(9956, max(-174, y * 2 + 5000))
            let px = Float(ax + 7356) / 15225, py = Float(ay + 174) / 10130
            let finger = Int32((b[i+3] >> 2) & 7)
            let telemetry = OMSTouchTelemetry(fingerID: finger == 7 ? 12 : finger, handID: 1,
                velocityX: 0, velocityY: 0, absoluteX: Float(ax) / 100,
                absoluteY: Float(ay) / 100, absoluteVelocityX: 0, absoluteVelocityY: 0,
                sourceFrame: 0, sourceTimestamp: Double(ticks) / 1000,
                driverKit: OMSDriverKitTelemetry(contactBytes: Array(b[i..<(i+9)]), velocityAvailable: false,
                    conversionVersion: 2, sensorTicks: ticks, reportBytes: b))
            let major = CompactV7Scalars.major(b[i+4]), minor = CompactV7Scalars.minor(b[i+5])
            let total = CompactV7Scalars.total(b[i+6])
            contacts.append(OMSRawTouch(id: Int32(b[i+8] & 15),
                posX: px, posY: py, total: Float(total) / 256,
                pressure: Float(CompactV7Scalars.pressure(b[i+7])),
                majorAxis: Float(major) / 100, minorAxis: Float(minor) / 100,
                angle: Float(b[i+8] >> 5) * Float.pi / 8,
                density: Float(UInt16(truncatingIfNeeded: CompactV7Scalars.density(total: total, major: major, minor: minor))) / 256,
                state: state, telemetry: telemetry))
        }
        return Self(contacts: contacts, buttons: b[1] & 3, sensorTicks: ticks)
    }
}

/// Reconstruct the native quantized binary velocity using the sensor clock.
/// Monotonic arrival time remains a safety guard, not the velocity denominator.
struct DriverContactEstimator {
    private struct Sample { let absoluteX: Float; let absoluteY: Float; let time: Double; let state: OMSState }
    private struct Clock { var ticks: UInt32; var wraps: UInt64 = 0 }
    private var clocks: [UInt64: Clock] = [:]
    private var previous: [UInt64: [Int32: Sample]] = [:]
    mutating func reset() { previous.removeAll(keepingCapacity: true); clocks.removeAll(keepingCapacity: true) }
    mutating func reset(device: UInt64) { previous[device] = nil; clocks[device] = nil }
    mutating func process(device: UInt64, time: Double, sequence: UInt64, contacts: [OMSRawTouch], sensorTicks: UInt32? = nil) -> [OMSRawTouch] {
        let old = previous[device] ?? [:]
        var next: [Int32: Sample] = [:]
        let ticks = sensorTicks ?? contacts.first?.telemetry?.driverKit?.sensorTicks
        var sensorTime: Double?
        if let ticks {
            var clock = clocks[device] ?? Clock(ticks: ticks)
            if ticks < clock.ticks { clock.wraps += 0x200000 }
            clock.ticks = ticks; clocks[device] = clock
            sensorTime = Double(clock.wraps + UInt64(ticks)) / 1000
        }
        let result = contacts.map { c -> OMSRawTouch in
            guard let t = c.telemetry, let raw = t.driverKit else { return c }
            let sourceTime = sensorTime ?? time
            let p = old[c.id]
            let dt = sourceTime - (p?.time ?? sourceTime)
            let activeVelocity = c.state == .touching || c.state == .breaking || c.state == .lingering
            let extra = raw.contactBytes.count == 9 && raw.contactBytes[8] & 16 != 0
            var ix = 0, iy = 0
            let available = p != nil && dt > 0 && dt < 0.15 && activeVelocity && !extra
            if available, let p {
                func quantize(_ delta: Float) -> Int {
                    let value = Double(delta * 8) / dt
                    return value.isFinite ? min(32767, max(-32768, Int(value.rounded(.towardZero)))) : 0
                }
                // Native velocity uses the current un-clipped binary position against
                // the previous clipped callback position, including at sensor edges.
                let b = raw.contactBytes
                func signed13(_ value: Int) -> Int { value & 4096 == 0 ? value : value - 8192 }
                let x = signed13(Int(b[0]) | Int(b[1] & 31) << 8)
                let y = signed13(Int(b[1] >> 5) | Int(b[2]) << 3 | Int(b[3] & 3) << 11)
                ix = quantize(Float(x * 2) / 100 - p.absoluteX)
                iy = quantize(Float(y * 2 + 5000) / 100 - p.absoluteY)
                // Native zero-vector sentinel avoidance is observable in the OMS callback.
                if ix == 0 && iy == 0 { ix = 1 }
            }
            let state: OMSState = c.state == .notTouching && p != nil && dt < 0.04 && dt >= 0
                && (p?.state == .making || p?.state == .touching) ? .leaving : c.state
            if state != .notTouching && state != .leaving {
                next[c.id] = Sample(absoluteX: t.absoluteX, absoluteY: t.absoluteY, time: sourceTime, state: state)
            }
            let avx = Float(ix) * 0.125, avy = Float(iy) * 0.125
            // Match native float32 -> float64 -> float32 operation order.
            let vx = Float(Double(Float(ix * 2) / 160) * 1000 / 15225)
            let vy = Float(Double(Float(iy * 2) / 160) * 1000 / 10130)
            let telemetry = OMSTouchTelemetry(fingerID: t.fingerID, handID: t.handID,
                velocityX: vx, velocityY: vy, absoluteX: t.absoluteX, absoluteY: t.absoluteY,
                absoluteVelocityX: avx, absoluteVelocityY: avy,
                sourceFrame: Int32(truncatingIfNeeded: sequence), sourceTimestamp: sourceTime,
                driverKit: OMSDriverKitTelemetry(contactBytes: raw.contactBytes, velocityAvailable: available,
                    conversionVersion: 2, sensorTicks: raw.sensorTicks, reportBytes: raw.reportBytes))
            return OMSRawTouch(id: c.id, posX: c.posX, posY: c.posY, total: c.total,
                pressure: c.pressure, majorAxis: c.majorAxis, minorAxis: c.minorAxis,
                angle: c.angle, density: c.density, state: state, telemetry: telemetry)
        }
        previous[device] = next
        return result
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

/// Merge physical button state across selected pads. A new/reset source must
/// report buttons-up before it can press, so enabling mid-click cannot click.
struct DriverButtonChange: Equatable {
    let mask: UInt8
    let down: Bool
}
struct DriverClickTracker {
    private var buttons: [UInt64: UInt8] = [:]
    private var armed: Set<UInt64> = []
    private var combined: UInt8 { buttons.values.reduce(0, |) }
    private func changes(from old: UInt8) -> [DriverButtonChange] {
        let next = combined
        guard old != next else { return [] }
        return [UInt8(1), 2].compactMap { mask in
            guard old & mask != next & mask else { return nil }
            return DriverButtonChange(mask: mask, down: next & mask != 0)
        }
    }
    mutating func update(device: UInt64, buttons value: UInt8) -> [DriverButtonChange] {
        let value = value & 3
        if value == 0 { armed.insert(device) }
        guard armed.contains(device) else { return [] }
        let old = combined
        buttons[device] = value
        return changes(from: old)
    }
    mutating func reset(device: UInt64) -> [DriverButtonChange] {
        let old = combined
        buttons[device] = nil; armed.remove(device)
        return changes(from: old)
    }
    mutating func reset() -> [DriverButtonChange] {
        let old = combined
        buttons.removeAll(keepingCapacity: true); armed.removeAll(keepingCapacity: true)
        return changes(from: old)
    }
}

@MainActor
final class DriverKitTakeover: ObservableObject {
    static let streamBuild = 22
    static func acceptsStream(_ properties: [String: Any]) -> Bool {
        (properties["StreamBuild"] as? NSNumber)?.intValue == streamBuild
    }
    static var helperURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/GesturePadDriverService.app")
    }
    @Published private(set) var isActive = false
    @Published private(set) var isRestoring = false
    @Published private(set) var status = "DriverKit ready. Takeover stays active until Release Trackpads."
    @Published var synthesizeTwoFingerPointer = true {
        didSet { updateInterpreter() }
    }
    @Published var allowClick = true {
        didSet { updateInterpreter() }
    }
    private var clickTracker = DriverClickTracker()
    var onContacts: ((UInt64, Int, Double, [OMSRawTouch]) async -> Void)?
    var onSessionBegan: (() -> Void)?
    var onSessionEnded: (() -> Void)?
    private var devices: [String: (id: UInt64, index: Int)] = [:]
    private var deviceMetadata: [DriverSessionDevice] = []
    private var inventoryMetadata: [DriverSessionDevice] = []
    private var helperPID: Int32 = 0
    private(set) var isTransferringRestart = false
    private var disconnectedSerials: Set<String> = []
    private var cursors: [String: DriverStreamCursor] = [:]
    private var lastFrame: [String: Double] = [:]
    private var task: Task<Void, Never>?
    private var received: UInt64 = 0
    private var perPad: [String: [String: Int]] = [:]
    private var lastDiagnostic = Date.distantPast
    private var gaps: UInt64 = 0
    private var estimator = DriverContactEstimator()
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
            let pid = (note.userInfo?["helperPID"] as? NSNumber)?.int32Value
            Task { @MainActor [weak self] in
                guard let self, session == self.token, let state else { return }
                self.helperState = state
                if let pid { self.helperPID = pid }
            }
        }
    }

    static func selectionError(selected: [(serial: String, transport: String, id: UInt64)],
                               connectedSerials: Set<String>) -> String? {
        guard selected.count <= 2, Set(selected.map(\.id)).count == selected.count,
              Set(selected.map(\.serial)).count == selected.count,
              selected.allSatisfy({ !$0.serial.isEmpty && $0.serial.utf8.count < 128 &&
                  $0.id > 0 && ["USB", "Bluetooth"].contains($0.transport) }) else {
            return "Select up to two distinct external Magic Trackpads with device identities."
        }
        return nil
    }

    func start(selected: [OMSDeviceInfo]) {
        guard !isRestoring else { return }
        if let error = Self.selectionError(
            selected: selected.map { ($0.serialNumber, $0.transport, $0.deviceIDNumeric) },
            connectedSerials: Set(OMSManager.shared.availableDevices.map(\.serialNumber))) {
            status = error
            return
        }
        guard Bundle.main.bundlePath.hasPrefix("/Applications/") else {
            status = "Run the installed /Applications/GesturePad.app for DriverKit takeover."
            return
        }
        guard let info = Bundle(url: Self.helperURL), info.infoDictionary?["CFBundleVersion"] as? String == String(Self.streamBuild) else {
            status = "Rebuild and install GesturePad using DriverKitProbe/install-integration.sh to include its driver service."
            return
        }
        if !selected.isEmpty && (synthesizeTwoFingerPointer || allowClick) && !AXIsProcessTrusted() {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            status = "Grant GesturePad Accessibility access, then retry (or turn off pointer and click output for a visual-only test)."
            return
        }
        var resolved: [String: (id: UInt64, index: Int)] = [:]
        for device in selected {
            guard isActive || Self.hasVerifiedSurface(device) else {
                status = "Native telemetry calibration did not match this pad. Release/refresh before retrying; no takeover started."
                return
            }
            guard let index = OMSManager.shared.deviceIndex(for: device.deviceID) else {
                status = "Refresh trackpads before starting DriverKit."; return
            }
            resolved[device.serialNumber] = (device.deviceIDNumeric, index)
        }
        if isActive {
            // Clear/reset only changed or disconnected routes. A healthy pad's
            // cursor, sensor clock and motion baseline survive another pad's Sync.
            let previous = devices
            for (serial, route) in previous where resolved[serial]?.id != route.id || resolved[serial]?.index != route.index {
                awaitClear(route: route)
                resetStream(serial: serial)
            }
            for (serial, route) in resolved where previous[serial]?.id != route.id ||
                previous[serial]?.index != route.index || disconnectedSerials.contains(serial) {
                resetStream(serial: serial)
                InterpretedTrackpadPointer.shared.resetBaseline(device: route.id)
                estimator.reset(device: route.id)
            }
            devices = resolved
            rememberMetadata(selected)
            DriverInputSourceGate.shared.set(Set(devices.values.map(\.id)))
            updateInterpreter()
            status = "Synced visualization routes. All supported connected pads remain controlled until Release Trackpads."
            return
        }
        devices = resolved
        rememberMetadata(selected)
        isActive = true; isRestoring = false; token = UUID().uuidString
        received = 0; gaps = 0; receivedAt = nil; began = Date(); helperState = ""
        disconnectedSerials = []; cursors = [:]; lastFrame = [:]; activeServices = [:]; perPad = [:]; estimator.reset()
        NSLog("GesturePad DriverKit session %@ requested", token)
        // Source gate is enabled before activation and cleared only after restoration.
        onSessionBegan?()
        DriverInputSourceGate.shared.set(Set(devices.values.map(\.id)))
        updateInterpreter()
        status = "Requesting DriverKit. Approve AMT Raw HID Receiver in Driver Extensions; touch the selected trackpad(s) once enabled."
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = ["--gesturepad-session", token, "--owner-pid", String(ProcessInfo.processInfo.processIdentifier)]
        config.createsNewApplicationInstance = true
        config.activates = false
        config.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: Self.helperURL, configuration: config) { [weak self] _, error in
            if let error {
                Task { @MainActor [weak self] in self?.helperState = "error: \(error.localizedDescription)" }
            }
        }
        beginPolling()
    }

    private func beginPolling() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.poll()
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func resetDerivedState(serial: String) {
        guard let device = devices[serial] else { return }
        postClicks(clickTracker.reset(device: device.id))
        estimator.reset(device: device.id)
        InterpretedTrackpadPointer.shared.resetBaseline(device: device.id)
    }

    private func resetStream(serial: String) {
        resetDerivedState(serial: serial)
        cursors[serial] = nil; lastFrame[serial] = nil; activeServices[serial] = nil
        disconnectedSerials.remove(serial)
    }

    private func awaitClear(route: (id: UInt64, index: Int)) {
        let sink = onContacts
        Task { await sink?(route.id, route.index, ProcessInfo.processInfo.systemUptime, []) }
    }

    private func rememberMetadata(_ selected: [OMSDeviceInfo]) {
        deviceMetadata = selected.compactMap { device in
            guard let route = devices[device.serialNumber] else { return nil }
            return DriverSessionDevice(serial: device.serialNumber, transport: device.transport,
                id: route.id, index: route.index, registryID: device.registryEntryID, name: device.deviceName)
        }
        // Capturing an unselected pad removes its native OMS service too. Keep
        // the full pre-takeover inventory available for later selector changes.
        var inventory = Dictionary(uniqueKeysWithValues: inventoryMetadata.map { ($0.id, $0) })
        for device in OMSManager.shared.availableDevices {
            guard !device.serialNumber.isEmpty, ["USB", "Bluetooth"].contains(device.transport),
                  let index = OMSManager.shared.deviceIndex(for: device.deviceID) else { continue }
            inventory[device.deviceIDNumeric] = DriverSessionDevice(serial: device.serialNumber,
                transport: device.transport, id: device.deviceIDNumeric, index: index,
                registryID: device.registryEntryID, name: device.deviceName)
        }
        inventoryMetadata = inventory.values.sorted { $0.index < $1.index }
        Self.installInventory(inventoryMetadata)
    }

    static func installInventory(_ metadata: [DriverSessionDevice]) {
        OMSManager.shared.setDriverInventory(metadata.map {
            OMSDeviceInfo(driverDeviceName: $0.name, deviceID: $0.id, registryEntryID: $0.registryID,
                serialNumber: $0.serial, transport: $0.transport, deviceIndex: $0.index)
        })
    }

    private func ownerMessage(_ action: String, nonce: String) {
        DistributedNotificationCenter.default().postNotificationName(.init("GesturePadDriverOwner"), object: token,
            userInfo: ["action": action, "nonce": nonce, "pid": ProcessInfo.processInfo.processIdentifier], deliverImmediately: true)
    }

    func prepareRestart() async -> DriverRestartSnapshot? {
        guard isActive, !isRestoring, helperPID > 1 else {
            status = "Restart postponed: wait for the driver service to acknowledge activation or finish release."
            return nil
        }
        isTransferringRestart = true
        let nonce = UUID().uuidString
        ownerMessage("prepare", nonce: nonce)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline && isActive {
            if helperState == "restart-ready:\(nonce)" {
                let snapshot = DriverRestartSnapshot(session: token, nonce: nonce, helperPID: helperPID,
                    ownerPID: ProcessInfo.processInfo.processIdentifier, expiresAt: Date().addingTimeInterval(15),
                    devices: deviceMetadata, synthesize: synthesizeTwoFingerPointer, inventory: inventoryMetadata, allowClick: allowClick)
                if let data = try? JSONEncoder().encode(snapshot) {
                    UserDefaults.standard.set(data, forKey: DriverRestartSnapshot.defaultsKey)
                    UserDefaults.standard.synchronize() // Replacement is a different process starting immediately.
                    postClicks(clickTracker.reset())
                    return snapshot
                }
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        cancelRestart(nonce: nonce)
        status = "Restart postponed: the driver service did not acknowledge session transfer. Takeover remains active."
        return nil
    }

    func cancelRestart(nonce: String) {
        ownerMessage("cancel", nonce: nonce)
        isTransferringRestart = false
        UserDefaults.standard.removeObject(forKey: DriverRestartSnapshot.defaultsKey)
    }

    static func restartSnapshot(arguments: [String]) -> DriverRestartSnapshot? {
        UserDefaults.standard.synchronize()
        guard let i = arguments.firstIndex(of: "--resume-driver"), arguments.count > i + 2,
              let data = UserDefaults.standard.data(forKey: DriverRestartSnapshot.defaultsKey),
              let snapshot = try? JSONDecoder().decode(DriverRestartSnapshot.self, from: data),
              snapshot.isValid(session: arguments[i+1], nonce: arguments[i+2], now: Date()),
              kill(snapshot.helperPID, 0) == 0 else { return nil }
        return snapshot
    }

    func adoptRestart(_ snapshot: DriverRestartSnapshot) {
        token = snapshot.session; helperPID = snapshot.helperPID
        deviceMetadata = snapshot.devices
        inventoryMetadata = snapshot.inventory ?? snapshot.devices
        Self.installInventory(inventoryMetadata)
        devices = Dictionary(uniqueKeysWithValues: snapshot.devices.map { ($0.serial, (id: $0.id, index: $0.index)) })
        synthesizeTwoFingerPointer = snapshot.synthesize
        allowClick = snapshot.allowClick ?? true
        isActive = true; began = Date(); helperState = ""
        onSessionBegan?()
        DriverInputSourceGate.shared.set(Set(devices.values.map(\.id)))
        status = "Resuming live driver session after Restart."
        ownerMessage("claim", nonce: snapshot.nonce)
        Task { [weak self] in
            let deadline = Date().addingTimeInterval(5)
            while let self, Date() < deadline, self.isActive {
                if self.helperState == "owner:\(ProcessInfo.processInfo.processIdentifier):\(snapshot.nonce)" {
                    UserDefaults.standard.removeObject(forKey: DriverRestartSnapshot.defaultsKey)
                    self.updateInterpreter(); self.beginPolling()
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard let self else { return }
            self.status = "Driver session transfer was not confirmed; requesting release."
            self.release(); self.beginPolling()
        }
    }

    private static func hasVerifiedSurface(_ device: OMSDeviceInfo) -> Bool {
        let match = IORegistryEntryIDMatching(device.registryEntryID)
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, match)
        guard entry != 0 else { return false }
        defer { IOObjectRelease(entry) }
        let expected: [UInt8] = [0xf0,0x3c,0,0,0x20,0x2b,0,0,0x44,0xe3,0x52,0xff,0xbd,0x1e,0xe4,0x26]
        // Selected OMS service is AppleMultitouchDevice; parent-search supports its service alias.
        guard let raw = IORegistryEntrySearchCFProperty(entry, kIOServicePlane,
                "Sensor Surface Descriptor" as CFString, kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)) as? Data else { return false }
        return raw == Data(expected)
    }

    func release() {
        guard hasOwnershipRequest, !isTransferringRestart else { return }
        saveEvidence(reason: "release requested")
        isActive = false; isRestoring = true; restoreBegan = Date()
        InterpretedTrackpadPointer.shared.stop()
        postClicks(clickTracker.reset())
        status = "Releasing driver. macOS may ask for authorization; normal ownership is not confirmed yet."
        DistributedNotificationCenter.default().postNotificationName(.init("GesturePadDriverRelease"), object: token, userInfo: nil, deliverImmediately: true)
    }

    private func saveEvidence(reason: String) {
        let evidence: [String: Any] = ["schema": 1, "session": token, "build": Self.streamBuild,
            "reason": reason, "received": received, "gaps": gaps,
            "syntheticMoves": InterpretedTrackpadPointer.shared.postedEventCount,
            "pads": perPad, "helperState": helperState]
        let url = URL(fileURLWithPath: "/tmp/GesturePad-driverkit-session-\(token).json")
        do {
            try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
            NSLog("GesturePad DriverKit %@: %@", reason, url.path)
        } catch { NSLog("GesturePad DriverKit evidence failed: %@", error.localizedDescription) }
    }

    private func postClicks(_ changes: [DriverButtonChange]) {
        guard !changes.isEmpty, let location = CGEvent(source: nil)?.location else { return }
        for change in changes {
            let right = change.mask == 2
            let type: CGEventType = right ? (change.down ? .rightMouseDown : .rightMouseUp)
                : (change.down ? .leftMouseDown : .leftMouseUp)
            guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                mouseCursorPosition: location, mouseButton: right ? .right : .left) else { continue }
            event.setIntegerValueField(.eventSourceUserData, value: SelectedTrackpadEventPolicy.interpreterTag)
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.post(tap: .cghidEventTap)
        }
    }

    private func updateInterpreter() {
        if !isActive || !allowClick { postClicks(clickTracker.reset()) }
        guard !isActive || !(synthesizeTwoFingerPointer || allowClick) || AXIsProcessTrusted() else {
            InterpretedTrackpadPointer.shared.stop()
            postClicks(clickTracker.reset())
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            status = "Grant GesturePad Accessibility access to enable pointer or click output."
            return
        }
        if isActive && synthesizeTwoFingerPointer {
            InterpretedTrackpadPointer.shared.enable(devices: Set(devices.values.map(\.id)))
        } else { InterpretedTrackpadPointer.shared.stop() }
    }

    private func finishRestoration() async {
        postClicks(clickTracker.reset())
        InterpretedTrackpadPointer.shared.stop()
        saveEvidence(reason: "driver removed")
        task?.cancel(); task = nil
        for device in devices.values { await onContacts?(device.id, device.index, ProcessInfo.processInfo.systemUptime, []) }
        DriverInputSourceGate.shared.set([])
        OMSManager.shared.setDriverInventory([])
        UserDefaults.standard.removeObject(forKey: DriverRestartSnapshot.defaultsKey)
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
        var coordinatorSeen = false
        var frames: [(String, DriverStreamRecord)] = []
        while true {
            let service = IOIteratorNext(iterator); if service == 0 { break }
            defer { IOObjectRelease(service) }
            var raw: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &raw, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let p = raw?.takeRetainedValue() as? [String: Any],
                  Self.acceptsStream(p) else { continue }
            if (p["StreamCoordinator"] as? NSNumber)?.boolValue == true {
                coordinatorSeen = true
                continue
            }
            guard let serial = p["StreamSerial"] as? String, devices[serial] != nil,
                  let session = (p["StreamSession"] as? NSNumber)?.uint64Value,
                  let data = p["StreamBatch"] as? Data,
                  let records = DriverStreamRecord.decodeBatch(data) else { continue }
            var rid: UInt64 = 0; IORegistryEntryGetRegistryEntryID(service, &rid)
            // Reconnection is explicit. Keep ignoring replacement streams until
            // the user verifies the selectors and clicks DriverKit Takeover.
            if disconnectedSerials.contains(serial) { continue }
            if let previous = activeServices[serial], previous != rid {
                disconnectedSerials.insert(serial)
                cursors[serial] = nil; lastFrame[serial] = nil
                resetDerivedState(serial: serial)
                if let device = devices[serial] {
                    await onContacts?(device.id, device.index, ProcessInfo.processInfo.systemUptime, [])
                }
                continue
            }
            activeServices[serial] = rid
            found.insert(serial)
            if (p["StreamOpened"] as? NSNumber)?.intValue != 1 {
                disconnectedSerials.insert(serial)
                cursors[serial] = nil; lastFrame[serial] = nil
                resetDerivedState(serial: serial)
                if let device = devices[serial] {
                    await onContacts?(device.id, device.index, ProcessInfo.processInfo.systemUptime, [])
                }
                continue
            }
            var cursor = cursors[serial] ?? DriverStreamCursor()
            let next = cursor.take(session: session, records: records); cursors[serial] = cursor
            if next.discontinuity {
                gaps += next.records.first?.sequence == 1 ? 0 : 1
                resetDerivedState(serial: serial)
            }
            frames += next.records.map { (serial, $0) }
        }
        let missing = Set(activeServices.keys).subtracting(found)
        for serial in missing where !disconnectedSerials.contains(serial) {
            disconnectedSerials.insert(serial)
            cursors[serial] = nil; lastFrame[serial] = nil
            resetDerivedState(serial: serial)
            if let device = devices[serial] {
                await onContacts?(device.id, device.index, ProcessInfo.processInfo.systemUptime, [])
            }
        }
        for (serial, record) in frames.sorted(by: { $0.1.timestamp < $1.1.timestamp }) {
            guard isActive, !disconnectedSerials.contains(serial), let device = devices[serial], let packet = MagicTrackpadPacket.decode(record.payload) else { continue }
            let sourceNow = Double(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1e9
            guard sourceNow >= record.timestamp, sourceNow - record.timestamp < 0.15 else {
                gaps += 1; resetDerivedState(serial: serial); continue
            }
            let now = ProcessInfo.processInfo.systemUptime - (sourceNow - record.timestamp)
            // Source clock is monotonic-raw; only compare intervals within that clock.
            let previous = lastFrame[serial]; lastFrame[serial] = record.timestamp
            if let previous, record.timestamp <= previous || record.timestamp - previous > 0.15 {
                resetDerivedState(serial: serial)
            }
            let contacts = estimator.process(device: device.id, time: record.timestamp,
                sequence: record.sequence, contacts: packet.contacts, sensorTicks: packet.sensorTicks)
            received += 1
            perPad[serial, default: [:]]["packets", default: 0] += 1
            perPad[serial, default: [:]]["maxContacts"] = max(perPad[serial]?["maxContacts"] ?? 0,
                packet.contacts.filter { $0.state == .touching }.count)
            if receivedAt == nil { receivedAt = Date() }
            if allowClick && AXIsProcessTrusted() {
                postClicks(clickTracker.update(device: device.id, buttons: packet.buttons))
            }
            InterpretedTrackpadPointer.shared.process(device: device.id, time: record.timestamp,
                contacts: contacts, suppress: packet.buttons != 0)
            await onContacts?(device.id, device.index, now, contacts)
        }
        if Date().timeIntervalSince(lastDiagnostic) > 5 {
            lastDiagnostic = Date()
            NSLog("GesturePad DriverKit %@: %llu packets, %llu gaps, %llu synthetic moves", token, received, gaps,
                InterpretedTrackpadPointer.shared.postedEventCount)
        }
        if !coordinatorSeen && Date().timeIntervalSince(began) > 5 && helperState != "approval" {
            status = "Driver coordinator not found. Release Trackpads and report this state; Driver activation is not confirmed."
        } else if devices.isEmpty && coordinatorSeen {
            status = "Driver enabled · no trackpads selected. All supported connected pads remain captured; Sync Trackpads applies visualization selections."
        } else if !disconnectedSerials.isEmpty {
            status = "Trackpad stream changed. Verify Left/Right Trackpad selections, then click Sync Trackpads. Other pads stay controlled."
        } else if found.count < devices.count && Date().timeIntervalSince(began) > 5 && coordinatorSeen {
            status = "Driver enabled · \(found.count)/\(devices.count) selected streams. Verify selections and Sync. A pad still using native input may need its own reconnect; other pads remain controlled."
        } else if receivedAt != nil {
            status = "DriverKit \(found.count)/\(devices.count) pads · \(received) packets · gaps \(gaps) · synthetic moves \(InterpretedTrackpadPointer.shared.postedEventCount) · active until released"
        } else {
            status = "DriverKit \(found.count)/\(devices.count) pads; waiting for touches. If pending, approve in Driver Extensions."
        }
    }
}
