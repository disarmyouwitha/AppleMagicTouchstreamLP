import AppKit
import Combine
import Carbon
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import os
import OpenMultitouchSupport


@main
struct GesturePadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static let relaunchArgument = "--relaunch"
    private let controller: GesturePadController = {
        // Run before constructing the model, which reads preferences immediately.
        // Keep serialized keys unchanged and never overwrite the new domain.
        let defaults = UserDefaults.standard
        let domain = "ink.ranna.gesturepad"
        let marker = "BundleIdentity.preferencesMigrated"
        if Bundle.main.bundleIdentifier == domain,
           !(defaults.persistentDomain(forName: domain)?[marker] as? Bool ?? false) {
            var values = defaults.persistentDomain(forName: "ink.ranna.glasstokey.gesturepad") ?? [:]
            values.merge(defaults.persistentDomain(forName: domain) ?? [:]) { _, current in current }
            values[marker] = true
            defaults.setPersistentDomain(values, forName: domain)
        }
        return GesturePadController()
    }()
    private let hidBlackhole = HIDBlackholeExperiment()
    private var releaseHotKey: EventHotKeyRef?
    private var releaseHotKeyHandler: EventHandlerRef?
    private var statusItem: NSStatusItem?
    private var configWindow: NSWindow?
    private var statusCancellable: AnyCancellable?
    private var replayStateCancellable: AnyCancellable?
    private static let configWindowDefaultHeight: CGFloat = 600
    private var captureMenuItem: NSMenuItem?
    private var replayMenuItem: NSMenuItem?
    private var captureInProgress = false
    private var replayInProgress = false
    private var isTerminatingApp = false
    private var restartTask: Task<Void, Never>?
    private var takeoverSleepObserver: NSObjectProtocol?
    private var takeoverWakeObserver: NSObjectProtocol?
    private var takeoverWakeTask: Task<Void, Never>?
    private static let persistedConfigKeys: [String] = [
        NativeTakeoverPreference.defaultsKey,
        GesturePadDefaultsKeys.leftDeviceID,
        GesturePadDefaultsKeys.rightDeviceID,
        GesturePadDefaultsKeys.autoResyncMissingTrackpads
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard enforceSingleInstancePolicyAtLaunch() else { return }
        let shouldOpenConfigOnLaunch = !ProcessInfo.processInfo.arguments.contains("--background") &&
            (!hasSavedConfiguration() || ProcessInfo.processInfo.arguments.contains("--open-config"))
        initializeRunAtStartupPreference()
        hidBlackhole.onNativeOwnershipChanged = { [weak controller] active in
            let enabled = UserDefaults.standard.bool(forKey: GesturePadDefaultsKeys.autoResyncMissingTrackpads)
            controller?.viewModel.setAutoResyncEnabled(enabled && !active)
        }
        controller.start()
        takeoverSleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.takeoverWakeTask?.cancel()
                self?.hidBlackhole.takeoverPreference.suspend("sleep")
            }
        }
        takeoverWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.takeoverWakeTask?.cancel()
                self.takeoverWakeTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled, let self else { return }
                    self.controller.viewModel.refreshDevicesAndListeners()
                    self.hidBlackhole.takeoverPreference.resume("sleep")
                }
            }
        }
        controller.viewModel.prepareDeviceRefresh = { [weak self] in
            guard let self else { return false }
            let released = self.hidBlackhole.takeoverPreference.suspend("selection")
            if !released { self.hidBlackhole.takeoverPreference.resume("selection") }
            return released
        }
        controller.viewModel.prepareDeviceSelectionChange = { [weak self] ids in
            self?.hidBlackhole.takeoverPreference.updateSelection(ids) ?? false
        }
        controller.viewModel.deviceSelectionStateDidUpdate = { [weak self] in
            self?.synchronizeTakeoverSelection()
        }
        controller.viewModel.deviceSelectionDidChange = { [weak self] in
            guard let self else { return }
            self.synchronizeTakeoverSelection()
            self.hidBlackhole.takeoverPreference.resume("selection")
        }
        configureStatusItem()
        registerReleaseHIDShortcut()
        observeStatus()
        synchronizeTakeoverSelection()
        if shouldOpenConfigOnLaunch {
            openConfigWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }




    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        hidBlackhole.release(reason: "App exiting")
        return .terminateNow
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window == configWindow else {
            return
        }
        controller.viewModel.setTouchSnapshotRecordingEnabled(false)
        controller.viewModel.setStatusVisualsEnabled(false)
        controller.viewModel.clearVisualCaches()
        window.delegate = nil
        window.contentView = nil
        window.contentViewController = nil
        configWindow = nil
        // FLTR user clients belong to this process. Keep native capture alive
        // when hiding Config; rebuilding this window must not cycle ownership.
        if hidBlackhole.nativeFilterActive || hidBlackhole.takeoverPreference.enabled { return }
        Task { @MainActor in
            if captureInProgress {
                await stopCaptureFlow()
            }
            await controller.endReplaySession()
            replayInProgress = controller.isATPReplayActive
            refreshCaptureReplayMenuState()
            restartAppProcess(reopenConfig: false)
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = ""
            button.imagePosition = .imageLeading
        }

        let menu = NSMenu()
        let configItem = NSMenuItem(
            title: "Config...",
            action: #selector(openConfigWindow),
            keyEquivalent: ","
        )
        configItem.target = self
        menu.addItem(configItem)
        let releaseItem = NSMenuItem(title: "Release Trackpads",
            action: #selector(releaseHIDNow), keyEquivalent: "r")
        releaseItem.keyEquivalentModifierMask = [.control, .option]
        releaseItem.target = self
        menu.addItem(releaseItem)
        menu.addItem(.separator())
        let captureItem = NSMenuItem(
            title: "Capture...",
            action: #selector(toggleCapture),
            keyEquivalent: ""
        )
        captureItem.target = self
        menu.addItem(captureItem)
        captureMenuItem = captureItem
        let replayItem = NSMenuItem(
            title: "Replay...",
            action: #selector(startReplay),
            keyEquivalent: ""
        )
        replayItem.target = self
        menu.addItem(replayItem)
        replayMenuItem = replayItem
        menu.addItem(.separator())

        let restartItem = NSMenuItem(
            title: "Restart GesturePad",
            action: #selector(restartApp),
            keyEquivalent: ""
        )
        restartItem.target = self
        menu.addItem(restartItem)

        let quitItem = NSMenuItem(
            title: "Quit GesturePad",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
        updateStatusIndicator(hasDisconnectedTrackpads: controller.viewModel.hasDisconnectedTrackpads)
        captureInProgress = controller.isATPCaptureActive
        replayInProgress = controller.isATPReplayActive
        refreshCaptureReplayMenuState()
    }

    @objc private func releaseHIDNow() {
        hidBlackhole.takeoverPreference.setEnabled(false)
        hidBlackhole.release(reason: "Released from menu or keyboard shortcut")
    }

    private func registerReleaseHIDShortcut() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                  eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue().releaseHIDNow()
            }
            return noErr
        }, 1, &event, context, &releaseHotKeyHandler)
        guard installed == noErr else { return }
        // Carbon hotkeys use the keyboard independently of seized trackpad interfaces.
        let identifier = EventHotKeyID(signature: 0x47504852, id: 1)
        let result = RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(controlKey | optionKey),
            identifier, GetApplicationEventTarget(), 0, &releaseHotKey)
        if result != noErr {
            if let handler = releaseHotKeyHandler { RemoveEventHandler(handler) }
            releaseHotKeyHandler = nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        takeoverWakeTask?.cancel()
        if let takeoverSleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(takeoverSleepObserver) }
        if let takeoverWakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(takeoverWakeObserver) }
        hidBlackhole.release(reason: "App quitting")
        if let releaseHotKey { UnregisterEventHotKey(releaseHotKey) }
        if let releaseHotKeyHandler { RemoveEventHandler(releaseHotKeyHandler) }
    }

    private func synchronizeTakeoverSelection() {
        hidBlackhole.takeoverPreference.updateSelection(
            [controller.viewModel.leftDevice, controller.viewModel.rightDevice]
                .compactMap { $0?.deviceIDNumeric })
    }

    private func observeStatus() {
        statusCancellable = controller.viewModel.$hasDisconnectedTrackpads
            .removeDuplicates()
            .sink { [weak self] missing in
                self?.updateStatusIndicator(hasDisconnectedTrackpads: missing)
            }
        replayStateCancellable = controller.viewModel.$replayTimelineState
            .map { $0 != nil }
            .removeDuplicates()
            .sink { [weak self] isReplayActive in
                if isReplayActive { self?.hidBlackhole.takeoverPreference.suspend("replay") }
                else { self?.hidBlackhole.takeoverPreference.resume("replay") }
                self?.replayInProgress = isReplayActive
                self?.refreshCaptureReplayMenuState()
            }
    }

    private func updateStatusIndicator(hasDisconnectedTrackpads: Bool) {
        guard let button = statusItem?.button else { return }
        button.image = statusIndicatorImage(hasWarning: hasDisconnectedTrackpads)
        button.toolTip = hasDisconnectedTrackpads ? "GesturePad – missing trackpad" : "GesturePad – raw contacts"
    }

    private func statusIndicatorImage(
        hasWarning: Bool
    ) -> NSImage {
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size)
        image.isTemplate = false
        image.lockFocus()
        let rect = NSRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(ovalIn: rect)
        NSColor.systemGreen.setFill()
        path.fill()

        if hasWarning {
            let dotRadius: CGFloat = 3.5
            let dotCenter = CGPoint(
                x: rect.maxX - dotRadius - 0.5,
                y: rect.maxY - dotRadius - 0.5
            )
            let warning = NSBezierPath()
            warning.appendArc(
                withCenter: dotCenter,
                radius: dotRadius,
                startAngle: 0,
                endAngle: 360
            )
            NSColor.systemYellow.setFill()
            warning.fill()
        }

        image.unlockFocus()
        return image
    }

    @objc private func openConfigWindow() {
        let window = configWindow ?? makeConfigWindow()
        configWindow = window
        controller.viewModel.setTouchSnapshotRecordingEnabled(true)
        controller.viewModel.setStatusVisualsEnabled(true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func syncDevices() {
        controller.viewModel.refreshDevicesAndListeners()
    }

    @objc private func toggleCapture() {
        Task { @MainActor in
            if captureInProgress {
                await stopCaptureFlow()
            } else {
                startCaptureFlow()
            }
        }
    }

    @objc private func startReplay() {
        Task { @MainActor in
            await replayFlow()
        }
    }

    @objc private func restartApp() {
        restartAppProcess()
    }

    @objc private func quitApp() {
        isTerminatingApp = true
        NSApp.terminate(nil)
    }

    private func enforceSingleInstancePolicyAtLaunch() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return true
        }

        let peerInstances = runningPeerInstances(bundleIdentifier: bundleIdentifier)
        guard !peerInstances.isEmpty else {
            return true
        }

        if ProcessInfo.processInfo.arguments.contains(Self.relaunchArgument) {
            terminateInstances(peerInstances)
            guard waitForPeerInstancesToExit(bundleIdentifier: bundleIdentifier) else {
                isTerminatingApp = true
                NSApp.terminate(nil)
                return false
            }
            return true
        }

        let existingInstance = peerInstances.min(by: { $0.processIdentifier < $1.processIdentifier })
        existingInstance?.activate(options: [.activateIgnoringOtherApps])
        presentAlreadyRunningAlert()
        isTerminatingApp = true
        NSApp.terminate(nil)
        return false
    }

    private func runningPeerInstances(bundleIdentifier: String) -> [NSRunningApplication] {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentPID }
    }

    private func terminateInstances(_ applications: [NSRunningApplication]) {
        for application in applications {
            _ = application.terminate()
        }
    }

    private func waitForPeerInstancesToExit(
        bundleIdentifier: String,
        timeout: TimeInterval = 2.0
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if runningPeerInstances(bundleIdentifier: bundleIdentifier).isEmpty {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return runningPeerInstances(bundleIdentifier: bundleIdentifier).isEmpty
    }

    private func presentAlreadyRunningAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "GesturePad is already running"
        alert.informativeText = "This extra instance will close so only one copy stays active."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func initializeRunAtStartupPreference() {
        let defaults = UserDefaults.standard
        let key = GesturePadDefaultsKeys.runAtStartupEnabled
        let manager = LaunchAtLoginManager.shared
        if defaults.object(forKey: key) == nil {
            defaults.set(manager.isEnabled, forKey: key)
            return
        }
        let desired = defaults.bool(forKey: key)
        do {
            try manager.setEnabled(desired)
            defaults.set(manager.isEnabled, forKey: key)
        } catch {
            defaults.set(manager.isEnabled, forKey: key)
        }
    }

    private func hasSavedConfiguration(defaults: UserDefaults = .standard) -> Bool {
        for key in Self.persistedConfigKeys {
            if defaults.object(forKey: key) != nil {
                return true
            }
        }
        return false
    }

    private func startCaptureFlow() {
        guard !replayInProgress else { return }
        let panel = NSSavePanel()
        panel.title = "Capture .atpcap"
        panel.nameFieldStringValue = "capture_\(captureTimestamp()).atpcap"
        panel.allowedContentTypes = [UTType(filenameExtension: "atpcap") ?? .data]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let outputURL = panel.url else {
            return
        }

        openConfigWindow()
        do {
            try controller.startATPCapture(to: outputURL)
            captureInProgress = true
            refreshCaptureReplayMenuState()
        } catch {
            presentError(
                title: "Failed to Start Capture",
                error: error
            )
        }
    }

    private func stopCaptureFlow() async {
        do {
            let frameCount = try await controller.stopATPCapture()
            captureInProgress = false
            refreshCaptureReplayMenuState()
            presentInfo(
                title: "Capture Saved",
                message: "Captured \(frameCount) frame(s)."
            )
        } catch {
            captureInProgress = controller.isATPCaptureActive
            refreshCaptureReplayMenuState()
            presentError(
                title: "Failed to Stop Capture",
                error: error
            )
        }
    }

    private func replayFlow() async {
        guard !captureInProgress, !replayInProgress else { return }
        let panel = NSOpenPanel()
        panel.title = "Replay .atpcap"
        panel.allowedContentTypes = [UTType(filenameExtension: "atpcap") ?? .data]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let inputURL = panel.url else {
            return
        }

        openConfigWindow()
        do {
            try await controller.beginReplaySession(from: inputURL)
            replayInProgress = controller.isATPReplayActive
            refreshCaptureReplayMenuState()
        } catch {
            replayInProgress = controller.isATPReplayActive
            refreshCaptureReplayMenuState()
            presentError(
                title: "Replay Failed",
                error: error
            )
        }
    }

    private func refreshCaptureReplayMenuState() {
        captureMenuItem?.title = captureInProgress ? "Stop Capture" : "Capture..."
        captureMenuItem?.isEnabled = !replayInProgress
        replayMenuItem?.isEnabled = !captureInProgress && !replayInProgress
    }

    private func captureTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }

    private func presentError(title: String, error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    private func presentInfo(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    private func makeConfigWindow() -> NSWindow {
        let contentView = ContentView(viewModel: controller.viewModel, hidBlackhole: hidBlackhole)
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: min(1560, (NSScreen.main?.visibleFrame.width ?? 1560) - 40),
                height: Self.configWindowDefaultHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "GesturePad"
        window.contentView = NSHostingView(rootView: contentView)
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }











    private func restartAppProcess(reopenConfig: Bool = true) {
        guard !isTerminatingApp, restartTask == nil else { return }
        if hidBlackhole.nativeFilterActive || hidBlackhole.takeoverPreference.enabled {
            // A process relaunch would close its native user clients. Rebuild
            // Config in place while preserving the controller and filter refs.
            configWindow?.close()
            if reopenConfig { openConfigWindow() }
            return
        }
        restartTask = Task { @MainActor [self] in
            if captureInProgress { await stopCaptureFlow() }
            hidBlackhole.release(reason: "App restart")
            guard !isTerminatingApp else { return }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-n", Bundle.main.bundlePath, "--args", Self.relaunchArgument]
            if !reopenConfig { task.arguments?.append("--background") }
            do {
                try task.run()
                isTerminatingApp = true
                NSApp.terminate(nil)
            } catch {
                restartTask = nil
                NSLog("GesturePad restart failed: %@", error.localizedDescription)
            }
        }
    }
}

