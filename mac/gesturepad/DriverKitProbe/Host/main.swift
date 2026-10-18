import AppKit
import SystemExtensions
import IOKit
import Darwin
import Security

@main
final class ProbeHost: NSObject, NSApplicationDelegate, OSSystemExtensionRequestDelegate {
    private let extensionID = TakeoverConfiguration.driverBundleID
    private var request: OSSystemExtensionRequest?
    private var managedToken: String?
    private var ownerPID: Int32 = 0
    private var ownerLease = DriverOwnerLease(ownerPID: 0)
    private var ownerObserver: NSObjectProtocol?
    private var watchdog: Timer?
    private var releaseObserver: NSObjectProtocol?
    private var requestedRemoval = false
    private var removalInFlight = false
    private var managedStarted = Date()
    private var checkingRemoval = false
    private var removalCompleted = false
    private var propertiesQuery: OSSystemExtensionRequest?
    private func reportState(_ state: String) {
        guard let token = managedToken else { return }
        DistributedNotificationCenter.default().postNotificationName(.init(TakeoverConfiguration.stateNotification), object: token,
            userInfo: ["state": state, "helperPID": ProcessInfo.processInfo.processIdentifier], deliverImmediately: true)
    }
    private func beginManagedSessionIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: TakeoverConfiguration.sessionArgument), args.count > index + 1,
              let pidIndex = args.firstIndex(of: "--owner-pid"), args.count > pidIndex + 1,
              let pid = Int32(args[pidIndex+1]), pid > 1 else { return }
        guard UUID(uuidString: args[index+1]) != nil, isSignedOwner(pid) else { return }
        managedToken = args[index+1]; ownerPID = pid; managedStarted = Date()
        ownerLease = DriverOwnerLease(ownerPID: pid)
        ownerObserver = DistributedNotificationCenter.default().addObserver(forName: .init(TakeoverConfiguration.ownerNotification), object: managedToken, queue: .main) { [weak self] note in
            let action = note.userInfo?["action"] as? String
            let nonce = note.userInfo?["nonce"] as? String
            let pid = (note.userInfo?["pid"] as? NSNumber)?.int32Value
            Task { @MainActor [weak self] in
                guard let self, !self.requestedRemoval, let action, let nonce,
                      let pid, self.isSignedOwner(pid) else { return }
                switch action {
                case "prepare":
                    if self.ownerLease.prepare(pid: pid, nonce: nonce, now: Date()) {
                        self.reportState("restart-ready:\(nonce)")
                    }
                case "cancel": self.ownerLease.cancel(pid: pid, nonce: nonce)
                case "claim":
                    if self.ownerLease.claim(pid: pid, nonce: nonce, now: Date()) {
                        self.ownerPID = pid
                        self.reportState("owner:\(pid):\(nonce)")
                        self.log("Transferred live driver session to replacement GesturePad PID\(pid).")
                    }
                default: break
                }
            }
        }
        releaseObserver = DistributedNotificationCenter.default().addObserver(forName: .init(TakeoverConfiguration.releaseNotification), object: managedToken, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.requestManagedRemoval() }
        }
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.managedTick() }
        }
        log("GesturePad-managed session: all connected supported Magic Trackpads, active until released. This helper stays open to restore ownership if GesturePad quits.")
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
        if ownerLease.shouldRelease(ownerAlive: kill(ownerPID, 0) == 0, now: Date()) {
            requestManagedRemoval(); return
        }
        // Device presence is managed by the user's explicit Takeover click.
        // A pad disconnect must never remove the extension for the other pad.
    }
    private func isSignedOwner(_ pid: Int32) -> Bool {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code else { return false }
        var requirement: SecRequirement?
        let rule = "identifier \"\(TakeoverConfiguration.appBundleID)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(TakeoverConfiguration.teamID)\""
        guard SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
    static func main() {
        let app = NSApplication.shared
        let delegate = ProbeHost()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Internal background manager: no window, Dock item or independent controls.
        beginManagedSessionIfRequested()
        if managedToken == nil { NSApp.terminate(nil) }
    }
    private func log(_ message: String) { NSLog("GesturePad Driver Service: %@", message) }
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
        log("Submitted system-extension request. Approval installs/enables the driver; Activate again does not restart a finished receiver. Selected pads remain controlled until released. USB/Bluetooth multitouch initialization follows the tested model protocol.")
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
        else { reportState("activated") }
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
        // A reboot-pending historical build1 must not masquerade as active build22.
        if !properties.contains(where: { $0.bundleVersion == String(TakeoverConfiguration.driverBuild) }) {
            reportState("removed"); watchdog?.invalidate(); watchdog = nil
            log("Verified build\(TakeoverConfiguration.driverBuild) is no longer registered. Check native trackpad behavior.")
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
        requestManagedRemoval()
        log("Waiting for driver removal before quitting. Approve the macOS removal prompt.")
        return .terminateCancel
    }
}
