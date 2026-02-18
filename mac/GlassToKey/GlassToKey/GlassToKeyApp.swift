import AppKit
import Combine
import Darwin
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
    private enum LaunchMode {
        case normal
        case replay(path: String)
    }

    private let controller = GlassToKeyController()
    private var statusItem: NSStatusItem?
    private var configWindow: NSWindow?
    private var statusCancellable: AnyCancellable?
    private var replayTask: Task<Void, Never>?
    private var shouldResumeLiveAfterReplay = false
    private let mouseEventBlocker = MouseEventBlocker()
    private static let configWindowDefaultHeight: CGFloat = 600

    func applicationDidFinishLaunching(_ notification: Notification) {
        switch Self.launchMode(from: CommandLine.arguments) {
        case let .replay(path):
            NSApp.setActivationPolicy(.prohibited)
            runHeadlessReplay(capturePath: path)
            return
        case .normal:
            break
        }
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
        replayTask?.cancel()
        replayTask = Task { [weak self] in
            guard let self else { return }
            await self.controller.viewModel.closeReplayCapture()
            if self.shouldResumeLiveAfterReplay {
                self.shouldResumeLiveAfterReplay = false
                self.controller.viewModel.start()
            }
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
        let replayItem = NSMenuItem(
            title: "Replay...",
            action: #selector(replayCaptureFile),
            keyEquivalent: "r"
        )
        replayItem.target = self
        menu.addItem(replayItem)
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

    @objc private func replayCaptureFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "atpcap")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Replay Capture"
        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }
        let wasListening = controller.viewModel.isListening
        shouldResumeLiveAfterReplay = wasListening
        if wasListening {
            controller.viewModel.stop()
        }
        controller.prepareForReplay()
        openConfigWindow()
        replayTask?.cancel()
        replayTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.controller.viewModel.loadReplayCapture(
                    capturePath: url.path
                )
            } catch {
                self.presentReplayAlert(
                    title: "Replay Failed",
                    message: error.localizedDescription
                )
                if self.shouldResumeLiveAfterReplay {
                    self.shouldResumeLiveAfterReplay = false
                    self.controller.viewModel.start()
                }
            }
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

    private func runHeadlessReplay(capturePath: String) {
        controller.prepareForReplay()
        replayTask?.cancel()
        replayTask = Task { [weak self] in
            guard let self else {
                Darwin.exit(1)
            }
            do {
                let result = try await self.controller.viewModel.runDeterministicReplay(
                    capturePath: capturePath
                )
                print(result.summary)
                Darwin.exit(result.deterministic ? 0 : 1)
            } catch {
                let text = "Replay failed: \(error.localizedDescription)\n"
                _ = text.withCString { pointer in
                    fputs(pointer, stderr)
                }
                Darwin.exit(1)
            }
        }
    }

    private func presentReplayAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func launchMode(from args: [String]) -> LaunchMode {
        guard args.count > 1 else { return .normal }
        var index = 1
        while index < args.count {
            let arg = args[index]
            if arg == "--replay", index + 1 < args.count {
                return .replay(path: args[index + 1])
            }
            index += 1
        }
        return .normal
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
