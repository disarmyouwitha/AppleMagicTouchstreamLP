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

@MainActor
final class DriverKitTakeover: ObservableObject {
    static let streamBuild = TakeoverConfiguration.driverBuild
    static func acceptsStream(_ properties: [String: Any]) -> Bool {
        (properties["StreamBuild"] as? NSNumber)?.intValue == streamBuild
    }
    static var helperURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/" + TakeoverConfiguration.helperAppName)
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
    private let output: (any TrackpadFrameOutput)?
    var onFrame: ((TrackpadContactFrame) async -> Void)?
    var onSessionBegan: (() -> Void)?
    var onSessionWillRelease: (() -> Void)?
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

    init(output: (any TrackpadFrameOutput)? = nil) {
        self.output = output
        observer = DistributedNotificationCenter.default().addObserver(forName: .init(TakeoverConfiguration.stateNotification), object: nil, queue: .main) { [weak self] note in
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
            status = "Run the installed /Applications/GlassToKey.app for DriverKit takeover."
            return
        }
        guard let info = Bundle(url: Self.helperURL), info.infoDictionary?["CFBundleVersion"] as? String == String(Self.streamBuild) else {
            status = "Rebuild and install GlassToKey using DriverKitProbe/install-integration.sh to include its driver service."
            return
        }
        if output != nil && !selected.isEmpty && (synthesizeTwoFingerPointer || allowClick) && !AXIsProcessTrusted() {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            status = "Grant GlassToKey Accessibility access, then retry (or turn off pointer and click output for a visual-only test)."
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
                output?.reset(device: route.id)
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
        NSLog("GlassToKey DriverKit session %@ requested", token)
        // Source gate is enabled before activation and cleared only after restoration.
        onSessionBegan?()
        DriverInputSourceGate.shared.set(Set(devices.values.map(\.id)))
        updateInterpreter()
        status = "Requesting DriverKit. Approve AMT Raw HID Receiver in Driver Extensions; touch the selected trackpad(s) once enabled."
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = [TakeoverConfiguration.sessionArgument, token, "--owner-pid", String(ProcessInfo.processInfo.processIdentifier)]
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
        output?.reset(device: device.id)
        estimator.reset(device: device.id)
    }

    private func resetStream(serial: String) {
        resetDerivedState(serial: serial)
        cursors[serial] = nil; lastFrame[serial] = nil; activeServices[serial] = nil
        disconnectedSerials.remove(serial)
    }

    private static func emptyFrame(_ route: (id: UInt64, index: Int)) -> TrackpadContactFrame {
        let now = ProcessInfo.processInfo.systemUptime
        return TrackpadContactFrame(deviceID: route.id, deviceIndex: route.index,
            timestamp: now, sourceTimestamp: now, contacts: [], buttons: 0)
    }

    private func awaitClear(route: (id: UInt64, index: Int)) {
        let sink = onFrame
        Task { await sink?(Self.emptyFrame(route)) }
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
        DistributedNotificationCenter.default().postNotificationName(.init(TakeoverConfiguration.ownerNotification), object: token,
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
                    output?.releaseButtons()
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
        onSessionWillRelease?()
        saveEvidence(reason: "release requested")
        isActive = false; isRestoring = true; restoreBegan = Date()
        output?.stop()
        output?.releaseButtons()
        status = "Releasing driver. macOS may ask for authorization; normal ownership is not confirmed yet."
        DistributedNotificationCenter.default().postNotificationName(.init(TakeoverConfiguration.releaseNotification), object: token, userInfo: nil, deliverImmediately: true)
    }

    private func saveEvidence(reason: String) {
        let evidence: [String: Any] = ["schema": 1, "session": token, "build": Self.streamBuild,
            "reason": reason, "received": received, "gaps": gaps,
            "syntheticMoves": (output?.postedPointerEvents ?? 0),
            "pads": perPad, "helperState": helperState]
        let url = URL(fileURLWithPath: "/tmp/" + TakeoverConfiguration.diagnosticPrefix + "\(token).json")
        do {
            try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
            NSLog("GlassToKey DriverKit %@: %@", reason, url.path)
        } catch { NSLog("GlassToKey DriverKit evidence failed: %@", error.localizedDescription) }
    }

    private func updateInterpreter() {
        if output?.configure(devices: Set(devices.values.map(\.id)),
            pointerEnabled: isActive && synthesizeTwoFingerPointer, clickEnabled: isActive && allowClick) == false {
            status = "Grant GlassToKey Accessibility access to enable pointer or click output."
        }
    }

    private func finishRestoration() async {
        output?.releaseButtons()
        output?.stop()
        saveEvidence(reason: "driver removed")
        task?.cancel(); task = nil
        for device in devices.values { await onFrame?(Self.emptyFrame(device)) }
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
                    await onFrame?(Self.emptyFrame(device))
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
                    await onFrame?(Self.emptyFrame(device))
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
                await onFrame?(Self.emptyFrame(device))
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
            let frame = TrackpadContactFrame(deviceID: device.id, deviceIndex: device.index,
                timestamp: now, sourceTimestamp: record.timestamp, contacts: contacts, buttons: packet.buttons)
            output?.process(frame)
            await onFrame?(frame)
        }
        if Date().timeIntervalSince(lastDiagnostic) > 5 {
            lastDiagnostic = Date()
            NSLog("GlassToKey DriverKit %@: %llu packets, %llu gaps, %llu synthetic moves", token, received, gaps,
                (output?.postedPointerEvents ?? 0))
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
            status = "DriverKit \(found.count)/\(devices.count) pads · \(received) packets · gaps \(gaps) · synthetic moves \((output?.postedPointerEvents ?? 0)) · active until released"
        } else {
            status = "DriverKit \(found.count)/\(devices.count) pads; waiting for touches. If pending, approve in Driver Extensions."
        }
    }
}
