import AppKit
import Combine
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
    private let controller = GlassToKeyController()
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller.start()
        configureStatusItem()
        observeStatus()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

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
            await controller.endReplaySession()
            replayInProgress = controller.isATPReplayActive
            refreshCaptureReplayMenuState()
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
        let syncItem = NSMenuItem(
            title: "Sync devices",
            action: #selector(syncDevices),
            keyEquivalent: "s"
        )
        syncItem.target = self
        menu.addItem(syncItem)
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
        mouseEventBlocker.setBlockingEnabled(
            controller.viewModel.isTypingEnabled && controller.viewModel.keyboardModeEnabled
        )
        captureInProgress = controller.isATPCaptureActive
        replayInProgress = controller.isATPReplayActive
        refreshCaptureReplayMenuState()
    }

    private func observeStatus() {
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
            self?.mouseEventBlocker.setBlockingEnabled(isTypingEnabled && keyboardModeEnabled)
        }
        replayStateCancellable = controller.viewModel.$replayTimelineState
            .map { $0 != nil }
            .removeDuplicates()
            .sink { [weak self] isReplayActive in
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
        let color = activeLayer == 1
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
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
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
        let contentView = ContentView(viewModel: controller.viewModel)
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
