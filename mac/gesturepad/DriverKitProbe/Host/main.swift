import AppKit
import SystemExtensions
import IOKit
import Darwin

@main
final class ProbeHost: NSObject, NSApplicationDelegate, OSSystemExtensionRequestDelegate {
    private let extensionID = "ink.ranna.glasstokey.gesturepad.rawhidprobe.driver"
    private var window: NSWindow!
    private let output = NSTextView()
    private var request: OSSystemExtensionRequest?
    private var managedToken: String?
    private var ownerPID: Int32 = 0
    private var watchdog: Timer?
    private var releaseObserver: NSObjectProtocol?
    private var requestedRemoval = false
    private var removalInFlight = false
    private var managedStarted = Date()
    private var activationFinished: Date?
    private var firstOpened: Date?
    private var observedOpen = false
    private var checkingRemoval = false
    private var removalCompleted = false
    private var propertiesQuery: OSSystemExtensionRequest?
    private func reportState(_ state: String) {
        guard let token = managedToken else { return }
        DistributedNotificationCenter.default().postNotificationName(.init("GesturePadDriverState"), object: token,
            userInfo: ["state": state], deliverImmediately: true)
    }
    private func beginManagedSessionIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--gesturepad-session"), args.count > index + 1,
              let pidIndex = args.firstIndex(of: "--owner-pid"), args.count > pidIndex + 1,
              let pid = Int32(args[pidIndex+1]), pid > 1 else { return }
        managedToken = args[index+1]; ownerPID = pid; managedStarted = Date()
        releaseObserver = DistributedNotificationCenter.default().addObserver(forName: .init("GesturePadDriverRelease"), object: managedToken, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.requestManagedRemoval() }
        }
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.managedTick() }
        }
        log("GesturePad-managed session: both known selected pads, active until released. This helper stays open to restore ownership if GesturePad quits.")
        activate()
    }
    private func requestManagedRemoval() {
        requestedRemoval = true
        guard request == nil, !removalInFlight else { return }
        removalInFlight = true
        reportState("restoring")
        deactivate()
    }
    private func managedTick() {
        guard managedToken != nil else { return }
        if removalCompleted { checkRemoval(); return }
        if requestedRemoval { return }
        if firstOpened == nil, let activationFinished, Date().timeIntervalSince(activationFinished) > 5 {
            log("No receiver matched within5s after activation; requesting removal.")
            requestManagedRemoval(); return
        }
        if kill(ownerPID, 0) != 0 {
            requestManagedRemoval(); return
        }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUserService"), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        var count = 0; var closed = false
        while true {
            let service = IOIteratorNext(iterator); if service == 0 { break }
            defer { IOObjectRelease(service) }
            var raw: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &raw, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let values = raw?.takeRetainedValue() as? [String: Any],
               (values["StreamBuild"] as? NSNumber)?.intValue == 6 {
                count += 1
                if (values["StreamOpened"] as? NSNumber)?.intValue != 1 { closed = true }
            }
        }
        if count > 0 {
            observedOpen = true
            if firstOpened == nil { firstOpened = Date() }
        }
        if closed || (observedOpen && count < 2 && Date().timeIntervalSince(firstOpened ?? Date()) > 2) {
            requestManagedRemoval()
        }
    }
    static func main() {
        let app = NSApplication.shared
        let delegate = ProbeHost()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 460),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "GesturePad Raw HID Driver Probe v0.6"
        let stack = NSStackView(); stack.orientation = .vertical; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let info = NSTextField(wrappingLabelWithString: "Experimental receiver: both tested selected trackpads (right USB + left Bluetooth). Opening may displace Apple's handler and affect native input. The receiver stays active until released; deactivation and a trackpad power cycle may be needed to restore native handling. Keep a mouse connected.")
        stack.addArrangedSubview(info)
        let buttons = NSStackView()
        for (title, selector) in [("Take over trackpads", #selector(activate)), ("Deactivate driver", #selector(deactivate)), ("Read results", #selector(readResults))] {
            buttons.addArrangedSubview(NSButton(title: title, target: self, action: selector))
        }
        stack.addArrangedSubview(buttons)
        output.isEditable = false; output.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        let scroll = NSScrollView(); scroll.documentView = output; scroll.hasVerticalScroller = true
        stack.addArrangedSubview(scroll)
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -16),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 250)
        ])
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        beginManagedSessionIfRequested()
        log("HOST BUILD 6. No driver is activated automatically. Read results must show ProbeBuild: 6 to identify this receiver; activation alone does not rearm a finished session.")
    }
    private func log(_ message: String) {
        output.string += message + "\n"
        output.scrollToEndOfDocument(nil)
        NSLog("GesturePadRawHIDProbe: %@", message)
    }
    @objc private func activate() {
        guard Bundle.main.bundlePath.hasPrefix("/Applications/") else {
            log("Install the signed host in /Applications before activating."); return
        }
        submit(OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: extensionID, queue: .main))
    }
    @objc private func deactivate() {
        if managedToken != nil {
            requestedRemoval = true
            guard request == nil else { log("Removal queued until pending approval finishes."); return }
            removalInFlight = true; removalCompleted = false
        }
        submit(OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: extensionID, queue: .main))
    }
    private func submit(_ next: OSSystemExtensionRequest) {
        guard request == nil else { log("An activation/deactivation request is already pending."); return }
        request = next; next.delegate = self; OSSystemExtensionManager.shared.submitRequest(next)
        log("Submitted system-extension request. Approval installs/enables the driver; Activate again does not restart a finished receiver. This version captures both selected pads until released; USB0201 once after 2 seconds, no Bluetooth mode command.")
    }
    @objc private func readResults() {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IOUserService") else { return }
        let criteria = matching as NSMutableDictionary
        criteria["IOPropertyMatch"] = ["IOUserClass": "AMTRawHIDReceiver"]
        let status = IOServiceGetMatchingServices(kIOMainPortDefault, criteria as CFDictionary, &iterator)
        guard status == KERN_SUCCESS else { log("Registry lookup failed: \(status)"); return }
        defer { IOObjectRelease(iterator) }
        var found = false
        while true {
            let service = IOIteratorNext(iterator); if service == 0 { break }
            defer { IOObjectRelease(service) }; found = true
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let values = props?.takeRetainedValue() as? [String: Any] {
                for key in ["ProbeBuild", "Callbacks", "ModeAttempted", "ModeResult", "Reports", "Bytes", "Reports13", "Reports22", "Reports31", "Reports40", "Reports8", "Reports21", "Reports30", "Reports39", "Reports48", "FirstFullLength", "Malformed", "MappingErrors", "CloseResult"] {
                    log("\(key): \(values[key].map { String(describing: $0) } ?? "pending")")
                }
                if let bytes = values["FirstFullReport"] as? Data {
                    log("First full report: " + bytes.map { String(format: "%02x", $0) }.joined())
                }
            }
        }
        if !found { log("No matched receiver service. Activation alone does not prove device matching or report access.") }
    }
    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        log("macOS requires approval in System Settings → General → Login Items & Extensions → Driver Extensions.")
        reportState("approval")
    }
    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        guard request === self.request else { return }
        log("Request completed: \(result.rawValue). Read results while active or before release; completion alone does not prove the receiver matched."); self.request = nil
        if removalInFlight {
            removalCompleted = true
            reportState("restoring")
            checkRemoval()
        } else if requestedRemoval { requestManagedRemoval() }
        else { activationFinished = Date(); reportState("activated") }
    }
    private func checkRemoval() {
        guard !checkingRemoval else { return }
        checkingRemoval = true
        let query = OSSystemExtensionRequest.propertiesRequest(forExtensionWithIdentifier: extensionID, queue: .main)
        query.delegate = self; propertiesQuery = query
        OSSystemExtensionManager.shared.submitRequest(query)
    }
    func request(_ request: OSSystemExtensionRequest, foundProperties properties: [OSSystemExtensionProperties]) {
        checkingRemoval = false; propertiesQuery = nil
        // A reboot-pending historical build1 must not masquerade as active build6.
        if !properties.contains(where: { $0.bundleVersion == "6" }) {
            reportState("removed"); watchdog?.invalidate(); watchdog = nil
            log("Verified build6 is no longer registered. Check native trackpad behavior.")
            NSApp.terminate(nil)
        } else { reportState("restoring") }
    }
    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) { let e = error as NSError
        if request === propertiesQuery {
            checkingRemoval = false; propertiesQuery = nil
            reportState("error: could not verify driver removal: \(e.localizedDescription)")
            return
        }
        log("Request failed: \(e.domain) code \(e.code): \(e.localizedDescription). Details: \(e.userInfo)")
        self.request = nil
        reportState("error: \(e.localizedDescription)")
        removalInFlight = false
        checkingRemoval = false
        if managedToken != nil { removalCompleted = true; checkRemoval() }
    }
    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction { .replace }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { managedToken == nil }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard managedToken != nil, watchdog != nil else { return .terminateNow }
        requestManagedRemoval(); window.makeKeyAndOrderFront(nil)
        log("Waiting for driver removal before quitting. Approve the macOS removal prompt.")
        return .terminateCancel
    }
}
