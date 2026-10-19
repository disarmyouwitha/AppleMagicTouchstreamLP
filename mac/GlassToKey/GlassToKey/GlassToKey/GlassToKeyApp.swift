import AppKit
import Combine
import Carbon
import OpenMultitouchSupport
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import os


@main
struct GlassToKeyApp: App {
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
    private let controller = GlassToKeyController()
    private let driverControl = DriverKitTakeover()
    private var releaseHotKey: EventHotKeyRef?
    private var releaseHotKeyHandler: EventHandlerRef?
    private var restartTask: Task<Void, Never>?
    private var quitTask: Task<Void, Never>?
    private var sleepObserver: NSObjectProtocol?
    private var driverOwnershipCancellable: AnyCancellable?
    private var statusItem: NSStatusItem?
    private var configWindow: NSWindow?
    private var statusCancellable: AnyCancellable?
    private var replayStateCancellable: AnyCancellable?
    private let mouseEventBlocker = MouseEventBlocker()
    private static let configWindowDefaultHeight: CGFloat = 600
    private var captureMenuItem: NSMenuItem?
    private var replayMenuItem: NSMenuItem?
    private var captureInProgress = false
    private var replayInProgress = false
    private var isTerminatingApp = false
    private static let persistedConfigKeys: [String] = [
        GlassToKeyDefaultsKeys.leftDeviceID,
        GlassToKeyDefaultsKeys.rightDeviceID,
        GlassToKeyDefaultsKeys.columnSettings,
        GlassToKeyDefaultsKeys.customButtons,
        GlassToKeyDefaultsKeys.keyMappings,
        GlassToKeyDefaultsKeys.shortcutActions,
        GlassToKeyDefaultsKeys.tapHoldDuration,
        GlassToKeyDefaultsKeys.dragCancelDistance,
        GlassToKeyDefaultsKeys.forceClickMin,
        GlassToKeyDefaultsKeys.forceClickCap,
        GlassToKeyDefaultsKeys.hapticStrength,
        GlassToKeyDefaultsKeys.typingGraceMs,
        GlassToKeyDefaultsKeys.intentMoveThresholdMm,
        GlassToKeyDefaultsKeys.intentVelocityThresholdMmPerSec,
        GlassToKeyDefaultsKeys.tapClickCadenceMs,
        GlassToKeyDefaultsKeys.layoutPreset,
        GlassToKeyDefaultsKeys.autoResyncMissingTrackpads,
        GlassToKeyDefaultsKeys.autocorrectEnabled,
        GlassToKeyDefaultsKeys.snapRadiusPercent,
        GlassToKeyDefaultsKeys.keyboardModeEnabled,
        GlassToKeyDefaultsKeys.holdRepeatEnabled,
        GlassToKeyDefaultsKeys.twoFingerTapGestureAction,
        GlassToKeyDefaultsKeys.threeFingerTapGestureAction,
        GlassToKeyDefaultsKeys.twoFingerHoldGestureAction,
        GlassToKeyDefaultsKeys.threeFingerHoldGestureAction,
        GlassToKeyDefaultsKeys.fourFingerHoldGestureAction,
        GlassToKeyDefaultsKeys.outerCornersHoldGestureAction,
        GlassToKeyDefaultsKeys.innerCornersHoldGestureAction,
        GlassToKeyDefaultsKeys.fiveFingerSwipeLeftGestureAction,
        GlassToKeyDefaultsKeys.fiveFingerSwipeRightGestureAction,
        GlassToKeyDefaultsKeys.gestureRepeatCadenceMsById
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let resume = DriverKitTakeover.restartSnapshot(arguments: ProcessInfo.processInfo.arguments)
        if let resume { DriverKitTakeover.installInventory(resume.inventory ?? resume.devices) }
        guard enforceSingleInstancePolicyAtLaunch() else { return }
        GlassToKeyController.seedBundledDefaultsIfNeeded()
        let shouldOpenConfigOnLaunch = !ProcessInfo.processInfo.arguments.contains("--background") &&
            (!hasSavedConfiguration() || ProcessInfo.processInfo.arguments.contains("--open-config"))
        initializeRunAtStartupPreference()
        controller.start()
        normalizeKeyboardModePermissionState()
        driverControl.onFrame = { [weak controller] frame in
            await controller?.viewModel.ingestDriverContacts(device: frame.deviceID, index: frame.deviceIndex,
                timestamp: frame.timestamp, touches: frame.contacts)
        }
        driverControl.onSessionBegan = { [weak controller] in
            controller?.viewModel.setDriverOwnership(true)
        }
        driverControl.onSessionWillRelease = { [weak controller] in
            controller?.viewModel.cancelDriverOutput()
        }
        driverControl.onSessionEnded = { [weak controller] in
            controller?.viewModel.setDriverOwnership(false)
            controller?.viewModel.refreshDevicesAndListeners()
            controller?.viewModel.start()
        }
        if let resume { driverControl.adoptRestart(resume) }
        registerReleaseHIDShortcut()
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.driverControl.release() }
        }
        configureStatusItem()
        observeStatus()
        if shouldOpenConfigOnLaunch {
            openConfigWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func normalizeKeyboardModePermissionState() {
        guard controller.viewModel.keyboardModeEnabled else { return }
        guard !InputMonitoringPermission.hasListenAccess() else { return }
        UserDefaults.standard.set(false, forKey: GlassToKeyDefaultsKeys.keyboardModeEnabled)
        controller.viewModel.updateKeyboardModeEnabled(false)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let control = driverControl
        if control.isTransferringRestart || !control.hasOwnershipRequest { return .terminateNow }
        if quitTask == nil {
            driverControl.release()
            quitTask = Task { @MainActor in
                while control.hasOwnershipRequest {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }



    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window == configWindow else {
            return
        }
        mouseEventBlocker.setAllowedRect(nil)
        controller.viewModel.setTouchSnapshotRecordingEnabled(false)
        controller.viewModel.setStatusVisualsEnabled(false)
        controller.viewModel.clearVisualCaches()
        window.delegate = nil
        window.contentView = nil
        window.contentViewController = nil
        configWindow = nil
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
        menu.addItem(.separator())
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
            title: "Restart GlassToKey",
            action: #selector(restartApp),
            keyEquivalent: ""
        )
        restartItem.target = self
        menu.addItem(restartItem)

        let quitItem = NSMenuItem(
            title: "Quit GlassToKey",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
        updateStatusIndicator(
            isTypingEnabled: controller.viewModel.isTypingEnabled,
            activeLayer: controller.viewModel.activeLayer,
            hasDisconnectedTrackpads: controller.viewModel.hasDisconnectedTrackpads,
            keyboardModeEnabled: controller.viewModel.keyboardModeEnabled
        )
        updateMouseBlocking()
        captureInProgress = controller.isATPCaptureActive
        replayInProgress = controller.isATPReplayActive
        refreshCaptureReplayMenuState()
    }

    @objc private func releaseHIDNow() {
        driverControl.release()
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
        let identifier = EventHotKeyID(signature: 0x47544B52, id: 1)
        let result = RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(controlKey | optionKey),
            identifier, GetApplicationEventTarget(), 0, &releaseHotKey)
        if result != noErr {
            if let handler = releaseHotKeyHandler { RemoveEventHandler(handler) }
            releaseHotKeyHandler = nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        driverControl.release()
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        if let releaseHotKey { UnregisterEventHotKey(releaseHotKey) }
        if let releaseHotKeyHandler { RemoveEventHandler(releaseHotKeyHandler) }
    }

    private func updateMouseBlocking() {
        mouseEventBlocker.setBlockingEnabled(!driverControl.hasOwnershipRequest &&
            controller.viewModel.isTypingEnabled && controller.viewModel.keyboardModeEnabled)
    }

    private func observeStatus() {
        driverOwnershipCancellable = driverControl.$isActive.combineLatest(driverControl.$isRestoring)
            .sink { [weak self] active, restoring in
                guard let self else { return }
                self.mouseEventBlocker.setBlockingEnabled(!active && !restoring &&
                    self.controller.viewModel.isTypingEnabled && self.controller.viewModel.keyboardModeEnabled)
            }

        statusCancellable = Publishers.CombineLatest4(
            controller.viewModel.$isTypingEnabled.removeDuplicates(),
            controller.viewModel.$activeLayer.removeDuplicates(),
            controller.viewModel.$hasDisconnectedTrackpads.removeDuplicates(),
            controller.viewModel.$keyboardModeEnabled.removeDuplicates()
        )
        .sink { [weak self] isTypingEnabled, activeLayer, hasDisconnected, keyboardModeEnabled in
            self?.updateStatusIndicator(
                isTypingEnabled: isTypingEnabled,
                activeLayer: activeLayer,
                hasDisconnectedTrackpads: hasDisconnected,
                keyboardModeEnabled: keyboardModeEnabled
            )
            self?.updateMouseBlocking()
        }
        replayStateCancellable = controller.viewModel.$replayTimelineState
            .map { $0 != nil }
            .removeDuplicates()
            .sink { [weak self] isReplayActive in
                if isReplayActive { self?.driverControl.release() }
                self?.replayInProgress = isReplayActive
                self?.refreshCaptureReplayMenuState()
            }
    }

    private func updateStatusIndicator(
        isTypingEnabled: Bool,
        activeLayer: Int,
        hasDisconnectedTrackpads: Bool,
        keyboardModeEnabled: Bool
    ) {
        guard let button = statusItem?.button else { return }
        button.image = statusIndicatorImage(
            isTypingEnabled: isTypingEnabled,
            activeLayer: activeLayer,
            hasWarning: hasDisconnectedTrackpads,
            keyboardModeEnabled: keyboardModeEnabled
        )
        let modeText: String
        if isTypingEnabled {
            modeText = keyboardModeEnabled ? "Keyboard mode" : "Mixed mode"
        } else {
            modeText = "Mouse mode"
        }
        button.toolTip = hasDisconnectedTrackpads
            ? "\(modeText) – missing trackpad"
            : modeText
    }

    private func statusIndicatorImage(
        isTypingEnabled: Bool,
        activeLayer: Int,
        hasWarning: Bool,
        keyboardModeEnabled: Bool
    ) -> NSImage {
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size)
        image.isTemplate = false
        image.lockFocus()
        let rect = NSRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(ovalIn: rect)
        let color = activeLayer > KeyLayerConfig.baseLayer
            ? NSColor.systemBlue
            : (isTypingEnabled
                ? (keyboardModeEnabled ? NSColor.systemPurple : NSColor.systemGreen)
                : NSColor.systemRed)
        color.setFill()
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
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updateMouseBlockerWindowFrame(window)
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
        alert.messageText = "GlassToKey is already running"
        alert.informativeText = "This extra instance will close so only one copy stays active."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func initializeRunAtStartupPreference() {
        let defaults = UserDefaults.standard
        let key = GlassToKeyDefaultsKeys.runAtStartupEnabled
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
            driverControl.release()
            while driverControl.hasOwnershipRequest {
                try await Task.sleep(for: .milliseconds(100))
            }
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
        let contentView = ContentView(viewModel: controller.viewModel, driverControl: driverControl)
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 984,
                height: Self.configWindowDefaultHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "GlassToKey"
        window.contentView = NSHostingView(rootView: contentView)
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window == configWindow else {
            return
        }
        updateMouseBlockerWindowFrame(window)
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window == configWindow else {
            return
        }
        updateMouseBlockerWindowFrame(window)
    }

    func windowDidMiniaturize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window == configWindow else {
            return
        }
        updateMouseBlockerWindowFrame(window)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window == configWindow else {
            return
        }
        updateMouseBlockerWindowFrame(window)
    }

    private func updateMouseBlockerWindowFrame(_ window: NSWindow?) {
        guard let window,
              window == configWindow,
              window.isVisible,
              !window.isMiniaturized else {
            mouseEventBlocker.setAllowedRect(nil)
            return
        }
        mouseEventBlocker.setAllowedRect(window.frame)
    }

    private func restartAppProcess(reopenConfig: Bool = true) {
        guard !isTerminatingApp, restartTask == nil else { return }
        restartTask = Task { @MainActor [self] in
            if captureInProgress { await stopCaptureFlow() }
            if driverControl.isActive {
                await controller.viewModel.suspendDriverOutput()
                guard let transfer = await driverControl.prepareRestart() else {
                    controller.viewModel.resumeDriverOutput()
                    restartTask = nil
                    return
                }
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                task.arguments = ["-n", Bundle.main.bundlePath, "--args", Self.relaunchArgument,
                    reopenConfig ? "--open-config" : "--background", "--resume-driver", transfer.session, transfer.nonce]
                do {
                    try task.run()
                    isTerminatingApp = true
                    NSApp.terminate(nil)
                } catch {
                    driverControl.cancelRestart(nonce: transfer.nonce)
                    controller.viewModel.resumeDriverOutput()
                    restartTask = nil
                    NSLog("GlassToKey live restart failed: %@", error.localizedDescription)
                }
                return
            }
            // Keep the owning app/helper alive until removal is confirmed.
            // Launching first lets the new process cache an empty native device
            // inventory while the previous process still owns the trackpads.
            driverControl.release()
            while driverControl.hasOwnershipRequest {
                do { try await Task.sleep(for: .milliseconds(100)) }
                catch { return }
            }
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
                NSLog("GlassToKey restart failed: %@", error.localizedDescription)
            }
        }
    }
}

private final class MouseEventBlocker {
    private struct State {
        var isBlocking = false
        var allowedRect: CGRect?
    }

    private let stateLock = OSAllocatedUnfairLock<State>(uncheckedState: State())
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func setBlockingEnabled(_ enabled: Bool) {
        stateLock.withLockUnchecked { $0.isBlocking = enabled }
        if enabled {
            ensureEventTap()
        }
    }

    func setAllowedRect(_ rect: CGRect?) {
        stateLock.withLockUnchecked { $0.allowedRect = rect }
    }

    private func ensureEventTap() {
        guard InputMonitoringPermission.hasListenAccess() else { return }
        guard eventTap == nil else {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }

        let mask = (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.rightMouseUp.rawValue)
            | (1 << CGEventType.rightMouseDragged.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
            | (1 << CGEventType.otherMouseUp.rawValue)
            | (1 << CGEventType.otherMouseDragged.rawValue)

        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: Self.eventTapCallback,
            userInfo: refcon
        ) else {
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        eventTap = tap
        runLoopSource = source
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func shouldAllow(event: CGEvent) -> Bool {
        let state = stateLock.withLockUnchecked { $0 }
        guard state.isBlocking else { return true }
        if let rect = state.allowedRect, rect.contains(event.location) {
            return true
        }
        return false
    }

    private func reenableIfNeeded(for type: CGEventType) {
        guard type == .tapDisabledByTimeout || type == .tapDisabledByUserInput else { return }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let blocker = Unmanaged<MouseEventBlocker>.fromOpaque(refcon).takeUnretainedValue()
        blocker.reenableIfNeeded(for: type)

        if blocker.shouldAllow(event: event) {
            return Unmanaged.passUnretained(event)
        }
        return nil
    }
}
