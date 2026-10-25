import AppKit
import Carbon
import Combine
import OpenMultitouchSupport
import SwiftUI
import UniformTypeIdentifiers
import os


@main
struct AppleMagicTouchstreamApp: App {
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
    private let controller: GlassToKeyController = {
        // Run before constructing the model, which reads preferences immediately.
        // Keep serialized keys unchanged and never overwrite the new domain.
        let defaults = UserDefaults.standard
        let domain = "ink.ranna.applemagictouchstream"
        let marker = "BundleIdentity.preferencesMigrated"
        if Bundle.main.bundleIdentifier == domain,
           !(defaults.persistentDomain(forName: domain)?[marker] as? Bool ?? false) {
            var values = defaults.persistentDomain(forName: "ink.ranna.glasstokey.keyboard") ?? [:]
            values.merge(defaults.persistentDomain(forName: domain) ?? [:]) { _, current in current }
            values[marker] = true
            defaults.setPersistentDomain(values, forName: domain)
        }
        return GlassToKeyController()
    }()
    private var restartTask: Task<Void, Never>?
    private let nativeTakeover = NativeTrackpadTakeover()
    private var releaseHotKey: EventHotKeyRef?
    private var releaseHotKeyHandler: EventHandlerRef?
    private var takeoverSleepObserver: NSObjectProtocol?
    private var takeoverWakeObserver: NSObjectProtocol?
    private var takeoverSelectionTask: Task<Void, Never>?
    private var takeoverQuitTask: Task<Void, Never>?
    private var statusItem: NSStatusItem?
    private var configWindow: NSWindow?
    private var replayStateCancellable: AnyCancellable?
    private static let configWindowDefaultHeight: CGFloat = 800
    private var captureMenuItem: NSMenuItem?
    private var replayMenuItem: NSMenuItem?
    private var captureInProgress = false
    private var replayInProgress = false
    private var isTerminatingApp = false
    private static let persistedConfigKeys: [String] = [
        GlassToKeyDefaultsKeys.gestureRecognitionEnabled,
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
        guard enforceSingleInstancePolicyAtLaunch() else { return }
        GlassToKeyController.seedBundledDefaultsIfNeeded()
        initializeRunAtStartupPreference()
        let shouldOpenConfigOnLaunch = !ProcessInfo.processInfo.arguments.contains("--background") &&
            (!hasSavedConfiguration() || ProcessInfo.processInfo.arguments.contains("--open-config"))
        nativeTakeover.onOwnershipChanged = { [weak self] owned in
            guard let self else { return }
            controller.viewModel.setNativeTakeoverOwnership(owned)
            controller.viewModel.gestures.updateOwnership(enabled: nativeTakeover.enabled,
                armed: nativeTakeover.outputArmed && !nativeTakeover.isReleasing,
                owned: nativeTakeover.ownedDeviceIDs)
        }
        nativeTakeover.beforeRelease = { [weak controller] in
            await controller?.viewModel.prepareNativeTakeoverRelease()
        }
        nativeTakeover.afterRelease = { [weak controller] in
            await controller?.viewModel.finishNativeTakeoverRelease()
        }
        takeoverSleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in _ = await self?.nativeTakeover.suspend("sleep") }
        }
        takeoverWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.nativeTakeover.resume("sleep") }
        }
        controller.viewModel.trackpadSelectionDidChange = { [weak self] in
            self?.reconcileTakeoverSelection()
        }
        registerReleaseTrackpadShortcut()
        controller.start()
        reconcileTakeoverSelection()
        configureStatusItem()
        observeReplayState()
        if shouldOpenConfigOnLaunch {
            openConfigWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }






    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard nativeTakeover.hasOwnership else { return .terminateNow }
        if takeoverQuitTask == nil {
            takeoverQuitTask = Task { @MainActor [self] in
                _ = await nativeTakeover.suspend("termination")
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let releaseHotKey { UnregisterEventHotKey(releaseHotKey) }
        if let releaseHotKeyHandler { RemoveEventHandler(releaseHotKeyHandler) }
        if let takeoverSleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(takeoverSleepObserver) }
        if let takeoverWakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(takeoverWakeObserver) }
        takeoverSelectionTask?.cancel()
    }

    private func reconcileTakeoverSelection() {
        takeoverSelectionTask?.cancel()
        takeoverSelectionTask = Task { @MainActor [weak self] in
            // Coalesce saved Left/Right restoration and service publications.
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            let devices = [controller.viewModel.leftDevice, controller.viewModel.rightDevice].compactMap { $0 }
            await nativeTakeover.updateSelection(deviceIDs: devices.map(\.deviceIDNumeric))
        }
    }

    @objc private func releaseTrackpads() {
        Task { await nativeTakeover.release() }
    }

    private func registerReleaseTrackpadShortcut() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue().releaseTrackpads()
            }
            return noErr
        }, 1, &event, context, &releaseHotKeyHandler)
        guard installed == noErr else { return }
        let identifier = EventHotKeyID(signature: 0x4E545250, id: 1)
        let result = RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(controlKey | optionKey), identifier,
            GetApplicationEventTarget(), 0, &releaseHotKey)
        nativeTakeover.releaseShortcutRegistered = result == noErr
        if result != noErr {
            if let releaseHotKeyHandler { RemoveEventHandler(releaseHotKeyHandler) }
            releaseHotKeyHandler = nil
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window == configWindow else {
            return
        }
        controller.viewModel.setTouchSnapshotRecordingEnabled(false)
        controller.viewModel.clearVisualCaches()
        window.delegate = nil
        window.contentView = nil
        window.contentViewController = nil
        configWindow = nil
        if nativeTakeover.hasOwnership { return }
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
        let releaseItem = NSMenuItem(title: "Release Trackpads", action: #selector(releaseTrackpads), keyEquivalent: "r")
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
            title: "Restart AppleMagicTouchstream",
            action: #selector(restartApp),
            keyEquivalent: ""
        )
        restartItem.target = self
        menu.addItem(restartItem)

        let quitItem = NSMenuItem(
            title: "Quit AppleMagicTouchstream",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
        item.button?.image = NSImage(named: "StatusHand")
        item.button?.image?.size = NSSize(width: 18, height: 20)
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "AppleMagicTouchstream"
        captureInProgress = controller.isATPCaptureActive
        replayInProgress = controller.isATPReplayActive
        refreshCaptureReplayMenuState()
    }




    private func observeReplayState() {
        replayStateCancellable = controller.viewModel.$replayTimelineState
            .map { $0 != nil }
            .removeDuplicates()
            .sink { [weak self] isReplayActive in
                Task { @MainActor [weak self] in
                    if isReplayActive { _ = await self?.nativeTakeover.suspend("replay") }
                    else { await self?.nativeTakeover.resume("replay") }
                }
                self?.replayInProgress = isReplayActive
                self?.refreshCaptureReplayMenuState()
            }
    }

    @objc private func openConfigWindow() {
        let window = configWindow ?? makeConfigWindow()
        configWindow = window
        controller.viewModel.setTouchSnapshotRecordingEnabled(true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func syncDevices() {
        Task { @MainActor in
            guard await nativeTakeover.suspend("refresh") else {
                await nativeTakeover.resume("refresh")
                return
            }
            controller.viewModel.refreshDevicesAndListeners()
            await nativeTakeover.updateSelection(deviceIDs: [controller.viewModel.leftDevice, controller.viewModel.rightDevice].compactMap { $0?.deviceIDNumeric })
            await nativeTakeover.resume("refresh")
        }
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
        alert.messageText = "AppleMagicTouchstream is already running"
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
            guard await nativeTakeover.suspend("replay") else {
                await nativeTakeover.resume("replay")
                return
            }
            try await controller.beginReplaySession(from: inputURL)
            replayInProgress = controller.isATPReplayActive
            refreshCaptureReplayMenuState()
        } catch {
            if !controller.isATPReplayActive { await nativeTakeover.resume("replay") }
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
        let contentView = ContentView(viewModel: controller.viewModel, nativeTakeover: nativeTakeover)
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
        window.title = "AppleMagicTouchstream"
        window.contentView = NSHostingView(rootView: contentView)
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }











    private func restartAppProcess(reopenConfig: Bool = true) {
        if nativeTakeover.hasOwnership {
            configWindow?.close()
            if reopenConfig { openConfigWindow() }
            return
        }
        guard !isTerminatingApp, restartTask == nil else { return }
        restartTask = Task { @MainActor [self] in
            if captureInProgress { await stopCaptureFlow() }
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
                NSLog("AppleMagicTouchstream restart failed: %@", error.localizedDescription)
            }
        }
    }
}
