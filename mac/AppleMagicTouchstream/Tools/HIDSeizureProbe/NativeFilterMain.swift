import Foundation
import IOKit
import CoreGraphics
import Darwin

private var stopped = false
private func code(_ value: Int32) -> String { String(format: "0x%08x", UInt32(bitPattern: value)) }

private func requireNoTakeover() throws {
    let match = IOServiceMatching("IOUserService")! as NSMutableDictionary
    match["IOPropertyMatch"] = ["IOUserClass": "AMTRawHIDReceiver"]
    let service = IOServiceGetMatchingService(kIOMainPortDefault, match)
    if service != 0 { IOObjectRelease(service); throw ProbeError("Release DriverKit takeover first") }
}
private func sample(_ phase: String, seconds: Int) throws -> ProbeNativeCounts {
    let began = ProcessInfo.processInfo.systemUptime
    var last = began
    let initial = CGEvent(source: nil)?.location
    var minX = initial?.x ?? 0, maxX = initial?.x ?? 0
    var minY = initial?.y ?? 0, maxY = initial?.y ?? 0
    while !stopped && ProcessInfo.processInfo.systemUptime - began < Double(seconds) {
        CFRunLoopRunInMode(.defaultMode, 0.05, false)
        let now = ProcessInfo.processInfo.systemUptime
        if let point = CGEvent(source: nil)?.location {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        if now - last >= 1 {
            let counts = ProbeNativeRead(), position = ProbeNativeReadPosition()
            print("CONTACTS phase=\(phase) frames=\(counts.frames) withContacts=\(counts.withContacts) lastContacts=\(counts.lastCount) firstID=\(position.identifier) firstX=\(Double(position.xMillionths) / 1000000) firstY=\(Double(position.yMillionths) / 1000000)")
            last = now
        }
    }
    if stopped { throw ProbeError("Interrupted") }
    let result = ProbeNativeRead()
    print("PHASE_SUMMARY phase=\(phase) frames=\(result.frames) withContacts=\(result.withContacts) maxContacts=\(result.maxCount) cursorSpanX=\(maxX - minX) cursorSpanY=\(maxY - minY) cursorReadAvailable=\(initial != nil)")
    return result
}
@main
private enum NativeFilterMain {
    static func main() {
        setbuf(stdout, nil)
        do { try run(); _exit(0) } catch { fputs("ERROR: \(error)\n", stderr); _exit(1) }
    }
    static func run() throws {
        let options = try GetReportOptions.parse(Array(CommandLine.arguments.dropFirst()))
        guard let address = options.address else {
            print("""
            NativeFilterProbe --probe --address MAC
            Selected Bluetooth native MT client: 5s ordinary baseline, 8s FLTR, 5s ordinary recovery.
            FLTR mode is experimental and may interrupt native input. No IOHID seizure,
            Bluetooth channel open, report requests, injection, or property writes.
            Requires baseline contacts, native driver type 4, and no existing FLTR client.
            Default/--help do not access devices.
            """); return
        }
        try requireNoTakeover()
        signal(SIGALRM, SIG_DFL); alarm(35)
        defer { alarm(0) }
        defer { ProbeNativeStop(); print("FINAL_STOP status=\(code(ProbeNativeLastStopStatus()))") }
        signal(SIGTSTP, SIG_IGN); signal(SIGINT, SIG_IGN); signal(SIGTERM, SIG_IGN)
        let signals = [SIGINT, SIGTERM].map { value -> DispatchSourceSignal in
            let source = DispatchSource.makeSignalSource(signal: value, queue: .main)
            source.setEventHandler { stopped = true }; source.resume(); return source
        }
        defer { for source in signals { source.cancel() } }
        let baselineStart = ProbeNativeStart(address, "Bluetooth")
        print("BASELINE_START selected=\(address) result=\(baselineStart) nativeStatus=\(code(ProbeNativeLastStartStatus()))")
        guard baselineStart == 0 else { throw ProbeError("Cannot start selected native baseline") }
        print("BASELINE 5s — move several fingers on the selected pad and KEEP moving through FILTER and RECOVERY.")
        let before = try sample("baseline", seconds: 5)
        guard before.withContacts > 0 else { throw ProbeError("No baseline contacts; filter not attempted") }
        var owned: UInt64 = 0
        let existing = ProbeNativeFilterClients(&owned)
        print("FILTER_PRECHECK existing=\(existing) owned=\(owned)")
        guard existing == 0 else { throw ProbeError("Existing filter or inspection failure; not starting another") }
        ProbeNativeStop()
        print("BASELINE_STOP status=\(code(ProbeNativeLastStopStatus()))")
        guard ProbeNativeLastStopStatus() == 0 else { throw ProbeError("Baseline stop failed") }
        if stopped { throw ProbeError("Interrupted") }
        // Alarm remains active through MTDeviceStop, including a stalled cleanup.
        alarm(12)
        let filterStart = ProbeNativeStartFilter(address)
        print("FILTER_START mode=0x40000000 result=\(filterStart) nativeStatus=\(code(ProbeNativeLastStartStatus()))")
        guard filterStart == 0 else { throw ProbeError("Native FLTR open failed; stopped") }
        let registered = ProbeNativeFilterClients(&owned)
        print("FILTER_VERIFY total=\(registered) owned=\(owned)")
        guard registered == 1 && owned == 1 else { throw ProbeError("Cannot verify exactly one own FilterEnabled client; closing") }
        print("FILTER 8s — observe native movement/scroll (do not press down to click) and continue moving several fingers.")
        let during = try sample("filter", seconds: 8)
        ProbeNativeStop()
        print("FILTER_STOP status=\(code(ProbeNativeLastStopStatus()))")
        guard ProbeNativeLastStopStatus() == 0 else { throw ProbeError("Filter stop returned error; check recovery") }
        alarm(10)
        let recoveryStart = ProbeNativeStart(address, "Bluetooth")
        print("RECOVERY_START result=\(recoveryStart) nativeStatus=\(code(ProbeNativeLastStartStatus()))")
        guard recoveryStart == 0 else { throw ProbeError("Recovery monitor failed; check native input") }
        let remaining = ProbeNativeFilterClients(&owned)
        print("FILTER_AFTER_CLOSE total=\(remaining) owned=\(owned)")
        guard remaining == 0 else { throw ProbeError("Filter remains after close or another filter appeared") }
        print("RECOVERY 5s — native input should resume; continue moving several fingers.")
        let after = try sample("recovery", seconds: 5)
        print("SUMMARY baselineContacts=\(before.withContacts) filterContacts=\(during.withContacts) recoveryContacts=\(after.withContacts)")
        print("User observation must establish native suppression and recovery. No successful takeover is assumed.")
        guard during.withContacts > 0 && after.withContacts > 0 else { throw ProbeError("Contact continuity was not established in every phase") }
    }
}
