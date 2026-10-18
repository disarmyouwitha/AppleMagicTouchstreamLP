import AppKit
import SystemExtensions
import IOKit

@main
final class ProbeHost: NSObject, NSApplicationDelegate, OSSystemExtensionRequestDelegate {
    private let extensionID = "ink.ranna.glasstokey.gesturepad.rawhidprobe.driver"
    private var window: NSWindow!
    private let output = NSTextView()
    private var request: OSSystemExtensionRequest?
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
        window.title = "GesturePad Raw HID Driver Probe v0.4"
        let stack = NSStackView(); stack.orientation = .vertical; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let info = NSTextField(wrappingLabelWithString: "Experimental receiver: exact left Bluetooth trackpad only. Opening may displace Apple's handler and affect native input. The receiver closes after 15 seconds; deactivation and a trackpad power cycle may be needed to restore native handling. Keep a mouse connected.")
        stack.addArrangedSubview(info)
        let buttons = NSStackView()
        for (title, selector) in [("Activate 15-second receiver", #selector(activate)), ("Deactivate driver", #selector(deactivate)), ("Read results", #selector(readResults))] {
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
        log("HOST BUILD 4. No driver is activated automatically. Read results must show ProbeBuild: 4 to identify this receiver; activation alone does not rearm a finished session.")
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
        submit(OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: extensionID, queue: .main))
    }
    private func submit(_ next: OSSystemExtensionRequest) {
        guard request == nil else { log("An activation/deactivation request is already pending."); return }
        request = next; next.delegate = self; OSSystemExtensionManager.shared.submitRequest(next)
        log("Submitted system-extension request. Approval installs/enables the driver; Activate again does not restart a finished receiver. This version captures LEFT Bluetooth for 15 seconds without a mode command.")
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
    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) { log("macOS requires approval in System Settings → Privacy & Security.") }
    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        log("Request completed: \(result.rawValue). Read results after 15 seconds; completion alone does not prove the receiver matched."); self.request = nil
    }
    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) { let e = error as NSError
        log("Request failed: \(e.domain) code \(e.code): \(e.localizedDescription). Details: \(e.userInfo)")
        self.request = nil }
    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction { .replace }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
