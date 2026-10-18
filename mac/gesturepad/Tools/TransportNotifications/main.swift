import Foundation
import IOKit

// Read-only probe: no IOServiceOpen, writes, feature reports or takeover commands.
final class Observer {
    struct Receiver {
        let service: io_service_t
        let notification: io_object_t
        let registryID: UInt64
        let serial: String
        var initialSequence: UInt64
        var finalSequence: UInt64
        var messageCounts: [String: Int] = [:]
        var propertyChanges = 0
    }
    let port: IONotificationPortRef
    var receivers: [Receiver] = []
    var sampleTimer: Timer?
    let started = Date()
    init?() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault),
              let source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() else { return nil }
        self.port = port
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
    }
    func number(_ service: io_service_t, _ key: String) -> UInt64 {
        (IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.uint64Value ?? 0
    }
    func attach() {
        let match = IOServiceMatching("IOUserService")!
        (match as NSMutableDictionary)["IOPropertyMatch"] = ["IOUserClass": "AMTRawHIDReceiver"]
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            guard number(service, "StreamCoordinator") == 0,
                  let serial = IORegistryEntryCreateCFProperty(service, "StreamSerial" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String else {
                IOObjectRelease(service); continue
            }
            var notification: io_object_t = 0
            let result = IOServiceAddInterestNotification(port, service, kIOGeneralInterest, { context, service, message, _ in
                guard let context else { return }
                Unmanaged<Observer>.fromOpaque(context).takeUnretainedValue().received(service, message)
            }, Unmanaged.passUnretained(self).toOpaque(), &notification)
            var registryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &registryID)
            guard result == KERN_SUCCESS else {
                print(String(format: "Interest registration failed: 0x%08x", result))
                IOObjectRelease(service); continue
            }
            let sequence = number(service, "StreamSequence")
            receivers.append(Receiver(service: service, notification: notification, registryID: registryID,
                serial: serial, initialSequence: sequence, finalSequence: sequence))
        }
        sampleTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.sample() }
    }
    func received(_ service: io_service_t, _ message: UInt32) {
        guard let index = receivers.firstIndex(where: { $0.service == service }) else { return }
        let key = String(format: "0x%08x", message)
        receivers[index].messageCounts[key, default: 0] += 1
        // iokit_common_msg(0x130), from the public IOKit/IOMessage.h.
        if message == 0xe0000130 { receivers[index].propertyChanges += 1 }
    }
    func sample() {
        for index in receivers.indices {
            receivers[index].finalSequence = number(receivers[index].service, "StreamSequence")
        }
    }
    func finish(output: URL) throws {
        sample(); sampleTimer?.invalidate()
        let rows: [[String: Any]] = receivers.map {
            ["registryID": $0.registryID, "serial": $0.serial,
             "initialSequence": $0.initialSequence, "finalSequence": $0.finalSequence,
             "reportsAdvanced": $0.finalSequence >= $0.initialSequence ? $0.finalSequence - $0.initialSequence : 0,
             "messages": $0.messageCounts, "propertyChangeCallbacks": $0.propertyChanges]
        }
        let report: [String: Any] = ["schema": 1, "started": ISO8601DateFormatter().string(from: started),
            "durationSeconds": Date().timeIntervalSince(started), "receivers": rows,
            "scope": "Read-only general-interest observer. Slow sequence polling proves activity; it is not the candidate notification transport or a latency/CPU benchmark."]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output)
        for receiver in receivers {
            IOObjectRelease(receiver.notification); IOObjectRelease(receiver.service)
        }
        receivers.removeAll()
        IONotificationPortDestroy(port)
        print("Saved: \(output.path)")
        print(String(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
let args = ProcessInfo.processInfo.arguments
let seconds = args.count > 1 ? (Double(args[1]) ?? 15) : 15
let output = URL(fileURLWithPath: args.count > 2 ? args[2] : "/tmp/GesturePad-notification-observer.json")
guard seconds > 0 && seconds <= 120 else { fatalError("Duration must be1..120seconds") }
guard let observer = Observer() else { fatalError("Notification port unavailable") }
observer.attach()
guard !observer.receivers.isEmpty else { print("No active raw receivers. Enable Takeover Trackpads first; nothing changed."); exit(2) }
print("READY: observing \(observer.receivers.count) receivers for \(seconds)s. Move fingers on the controlled pads. No settings or driver state are changed.")
fflush(stdout)
RunLoop.current.run(until: Date().addingTimeInterval(seconds))
try observer.finish(output: output)
