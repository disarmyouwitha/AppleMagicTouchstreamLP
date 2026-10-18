import Foundation
import IOKit
import IOKit.hid
import Darwin

// Runs only when explicitly invoked, using the embedded, signed helper identity.
enum HandoffCommand {
    private static var pendingNativeSlots: Set<Int> = []
    private static var handedOffSlots: [String: Int] = [:]
    static func receivers() -> [(io_service_t, [String: Any])] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUserService"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [(io_service_t, [String: Any])] = []
        while true {
            let service = IOIteratorNext(iterator); if service == 0 { break }
            var raw: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &raw, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let p = raw?.takeRetainedValue() as? [String: Any],
               (p["StreamBuild"] as? NSNumber)?.intValue == 21,
               ((p["StreamSerial"] as? String)?.isEmpty == false ||
                (p["StreamCoordinator"] as? NSNumber)?.boolValue == true) {
                result.append((service, p))
            } else { IOObjectRelease(service) }
        }
        return result
    }
    static func runIfRequested() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--initialize-bluetooth") { return initializeBluetooth(args) }
        guard args.contains("--handoff") else { return false }
        guard args.count == 4, args[1] == "--handoff", !args[2].isEmpty, args[2].utf8.count < 128,
              ["close", "reopen", "terminate", "rematch", "retake", "status"].contains(args[3]) else {
            fputs("Usage: --handoff SERIAL close|reopen|terminate|rematch|retake|status\n", stderr); exit(2)
        }
        let entries = receivers(); defer { for (service, _) in entries { IOObjectRelease(service) } }
        var result: [String: Any] = ["time": ISO8601DateFormatter().string(from: Date()), "operation": args[3], "serial": args[2]]
        let keys = ["StreamSerial", "StreamBuild", "StreamOpened", "StreamSequence", "StreamReports", "StreamHandoffRequested", "HandoffOperation", "HandoffCloseOrOpenResult", "HandoffTerminateResult", "HandoffRematchOperation", "HandoffRematchResult", "HandoffRematchProviderID", "StreamNativeGateMask"]
        result["before"] = entries.map { _, p in p.filter { keys.contains($0.key) } }
        let commandTarget = (args[3] == "rematch" || args[3] == "retake")
            ? entries.first(where: { $0.1["StreamSerial"] as? String != args[2] })
            : entries.first(where: { $0.1["StreamSerial"] as? String == args[2] })
        guard let target = commandTarget else {
            result["error"] = "No matching build21 receiver. Enable takeover in the updated app first."
            emit(result); exit(1)
        }
        if args[3] != "status" {
            var connection: io_connect_t = 0
            let opened = IOServiceOpen(target.0, mach_task_self_, 0x414d5408, &connection)
            result["userClientOpen"] = UInt32(bitPattern: opened)
            if opened == KERN_SUCCESS {
                // Historical rematch diagnostics target the opposite transport.
                // The driver refuses this operation if providers are ambiguous.
                let targetIsBluetooth = target.1["StreamTransport"] as? String == "USB"
                let operation: UInt64 = args[3] == "retake" ? (targetIsBluetooth ? 6 : 7)
                    : args[3] == "rematch" ? (targetIsBluetooth ? 4 : 5)
                    : args[3] == "close" ? 1 : args[3] == "reopen" ? 2 : 3
                var scalar = operation
                let called = IOConnectCallScalarMethod(connection, 0, &scalar, 1, nil, nil)
                result["commandResult"] = UInt32(bitPattern: called)
                IOServiceClose(connection)
            }
        }
        // Observe only. Success of Close/Terminate does not assert native restoration.
        Thread.sleep(forTimeInterval: 1)
        let after = receivers(); defer { for (service, _) in after { IOObjectRelease(service) } }
        result["after"] = after.map { _, p in p.filter { keys.contains($0.key) } }
        emit(result)
        if let code = result["userClientOpen"] as? UInt32, code != 0 { exit(1) }
        if let code = result["commandResult"] as? UInt32, code != 0 { exit(1) }
        return true
    }
    /// One explicit repair of an already-controlled, mouse-only supported pad.
    /// macOS supplies the keyhole prefix; payload02 01 becomes wireF1 02 01.
    private static func initializeBluetooth(_ args: [String]) -> Bool {
        guard args.count == 3, args[1] == "--initialize-bluetooth" else { exit(2) }
        let entries = receivers()
        defer { for (service, _) in entries { IOObjectRelease(service) } }
        guard let target = entries.first(where: {
            $0.1["StreamSerial"] as? String == args[2] &&
            $0.1["StreamTransport"] as? String == "Bluetooth" &&
            ($0.1["StreamOpened"] as? NSNumber)?.boolValue == true &&
            ($0.1["StreamSequence"] as? NSNumber)?.uint64Value == 0
        }) else { emit(["error": "No controlled Bluetooth receiver needing initialization"]); exit(1) }
        var interface: io_registry_entry_t = 0, device: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(target.0, kIOServicePlane, &interface) == KERN_SUCCESS else { exit(1) }
        defer { IOObjectRelease(interface) }
        guard IORegistryEntryGetParentEntry(interface, kIOServicePlane, &device) == KERN_SUCCESS else { exit(1) }
        defer { IOObjectRelease(device) }
        func property(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(device, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        guard property("SerialNumber") as? String == args[2], property("Transport") as? String == "Bluetooth",
              (property("VendorID") as? NSNumber)?.intValue == 76,
              (property("ProductID") as? NSNumber)?.intValue == 804,
              (property("KeyholeReportID") as? NSNumber)?.intValue == 0xf1,
              let hid = IOHIDDeviceCreate(kCFAllocatorDefault, device) else { exit(1) }
        let payload: [UInt8] = [0x02, 0x01]
        var result = payload.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(hid, kIOHIDReportTypeFeature, 0xf1, $0.baseAddress!, $0.count)
        }
        var openResult: IOReturn?
        if result == kIOReturnNotOpen {
            let opened = IOHIDDeviceOpen(hid, IOOptionBits(kIOHIDOptionsTypeNone))
            openResult = opened
            if opened == kIOReturnSuccess {
                result = payload.withUnsafeBufferPointer {
                    IOHIDDeviceSetReport(hid, kIOHIDReportTypeFeature, 0xf1, $0.baseAddress!, $0.count)
                }
                IOHIDDeviceClose(hid, IOOptionBits(kIOHIDOptionsTypeNone))
            }
        }
        emit(["serial": args[2], "reportID": 0xf1, "payload": "0201", "expectedWire": "f10201",
              "result": UInt32(bitPattern: result), "ordinaryOpenResult": openResult.map { UInt32(bitPattern: $0) } as Any,
              "note": "No seizure, receiver close or extension change"])
        return true
    }
    /// Per-device policy; never deactivate the extension for a selector change.
    static func releaseUnselected(_ selected: Set<String>) {
        let entries = receivers()
        defer { for (service, _) in entries { IOObjectRelease(service) } }
        guard entries.contains(where: { ($0.1["StreamCoordinator"] as? NSNumber)?.boolValue == true }) else { return }
        for (service, p) in entries {
            guard let serial = p["StreamSerial"] as? String, !selected.contains(serial),
                  (p["StreamHandoffRequested"] as? NSNumber)?.boolValue != true else { continue }
            var connection: io_connect_t = 0
            guard IOServiceOpen(service, mach_task_self_, 0x414d5408, &connection) == KERN_SUCCESS else { continue }
            defer { IOServiceClose(connection) }
            var operation: UInt64 = 3
            let result = IOConnectCallScalarMethod(connection, 0, &operation, 1, nil, nil)
            if result == KERN_SUCCESS, let slot = (p["StreamSlot"] as? NSNumber)?.intValue {
                pendingNativeSlots.insert(slot)
                handedOffSlots[serial] = slot
            }
            NSLog("GesturePad selection handoff %@: 0x%x (native restoration not asserted)", serial, result)
        }
        // Wait until that receiver has actually terminated before rematching its
        // retained provider. The coordinator survives even with zero selected pads.
        let liveSlots = Set(entries.compactMap { ($0.1["StreamSlot"] as? NSNumber)?.intValue })
        if !pendingNativeSlots.isEmpty, let coordinator = entries.first(where: { ($0.1["StreamCoordinator"] as? NSNumber)?.boolValue == true }) {
            var connection: io_connect_t = 0
            if IOServiceOpen(coordinator.0, mach_task_self_, 0x414d5408, &connection) == KERN_SUCCESS {
                defer { IOServiceClose(connection) }
                for slot in pendingNativeSlots.subtracting(liveSlots) {
                    var operation = UInt64(16 + slot)
                    if IOConnectCallScalarMethod(connection, 0, &operation, 1, nil, nil) == KERN_SUCCESS {
                        pendingNativeSlots.remove(slot)
                    }
                }
            }
        }
    }
    static func syncSelection(_ selected: Set<String>) {
        releaseUnselected(selected)
        let entries = receivers()
        defer { for (service, _) in entries { IOObjectRelease(service) } }
        guard let coordinator = entries.first(where: { ($0.1["StreamCoordinator"] as? NSNumber)?.boolValue == true }) else { return }
        var connection: io_connect_t = 0
        guard IOServiceOpen(coordinator.0, mach_task_self_, 0x414d5408, &connection) == KERN_SUCCESS else { return }
        defer { IOServiceClose(connection) }
        for serial in selected {
            guard let slot = handedOffSlots[serial] else { continue }
            pendingNativeSlots.remove(slot)
            var operation = UInt64(32 + slot)
            let result = IOConnectCallScalarMethod(connection, 0, &operation, 1, nil, nil)
            NSLog("GesturePad selection retake request %@: 0x%x (ownership not asserted)", serial, result)
        }
    }
    static func emit(_ object: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) { print(text) }
    }
}
