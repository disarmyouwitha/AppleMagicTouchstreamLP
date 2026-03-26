import AppKit
import Carbon
import CoreGraphics
import Foundation
import OpenMultitouchSupport
import os

final class KeyEventDispatcher: @unchecked Sendable {
    static let shared = KeyEventDispatcher()

    enum SystemKey: Sendable {
        case volumeUp
        case volumeDown
        case brightnessUp
        case brightnessDown

        var keyType: Int32 {
            switch self {
            case .volumeUp:
                return 0
            case .volumeDown:
                return 1
            case .brightnessUp:
                return 2
            case .brightnessDown:
                return 3
            }
        }

        var captureLabel: String {
            switch self {
            case .volumeUp:
                return "volumeUp"
            case .volumeDown:
                return "volumeDown"
            case .brightnessUp:
                return "brightnessUp"
            case .brightnessDown:
                return "brightnessDown"
            }
        }
    }

    private let dispatcher: KeyDispatching

    private init() {
        dispatcher = CGEventKeyDispatcher()
    }

    func postKeyStroke(
        code: CGKeyCode,
        flags: CGEventFlags,
        altAscii: UInt8 = 0,
        token: RepeatToken? = nil
    ) {
        dispatcher.postKeyStroke(code: code, flags: flags, altAscii: altAscii, token: token)
    }

    func postKeyStrokeImmediate(
        code: CGKeyCode,
        flags: CGEventFlags,
        altAscii: UInt8 = 0,
        token: RepeatToken? = nil
    ) {
        dispatcher.postKeyStrokeImmediate(code: code, flags: flags, altAscii: altAscii, token: token)
    }

    func postKey(
        code: CGKeyCode,
        flags: CGEventFlags,
        keyDown: Bool,
        altAscii: UInt8 = 0,
        token: RepeatToken? = nil
    ) {
        dispatcher.postKey(code: code, flags: flags, keyDown: keyDown, altAscii: altAscii, token: token)
    }

    func postKeyImmediate(
        code: CGKeyCode,
        flags: CGEventFlags,
        keyDown: Bool,
        altAscii: UInt8 = 0,
        token: RepeatToken? = nil
    ) {
        dispatcher.postKeyImmediate(
            code: code,
            flags: flags,
            keyDown: keyDown,
            altAscii: altAscii,
            token: token
        )
    }

    func postLeftClick(clickCount: Int = 1) {
        dispatcher.postLeftClick(clickCount: clickCount)
    }

    func postLeftClickImmediate(clickCount: Int = 1) {
        dispatcher.postLeftClickImmediate(clickCount: clickCount)
    }

    func postRightClick() {
        dispatcher.postRightClick()
    }

    func postRightClickImmediate() {
        dispatcher.postRightClickImmediate()
    }

    func setThreeFingerHoldDragSuppression(_ enabled: Bool) {
        dispatcher.setThreeFingerHoldDragSuppression(enabled)
    }

    func postMiddleClick() {
        dispatcher.postMiddleClick()
    }

    func postMiddleClickImmediate() {
        dispatcher.postMiddleClickImmediate()
    }

    func postText(_ text: String) {
        dispatcher.postText(text)
    }

    func postTextImmediate(_ text: String) {
        dispatcher.postTextImmediate(text)
    }

    func postSystemKey(_ key: SystemKey) {
        dispatcher.postSystemKey(key)
    }

    func postSystemKeyImmediate(_ key: SystemKey) {
        dispatcher.postSystemKeyImmediate(key)
    }
}

private protocol KeyDispatching: Sendable {
    func postKeyStroke(code: CGKeyCode, flags: CGEventFlags, altAscii: UInt8, token: RepeatToken?)
    func postKeyStrokeImmediate(code: CGKeyCode, flags: CGEventFlags, altAscii: UInt8, token: RepeatToken?)
    func postKey(code: CGKeyCode, flags: CGEventFlags, keyDown: Bool, altAscii: UInt8, token: RepeatToken?)
    func postKeyImmediate(code: CGKeyCode, flags: CGEventFlags, keyDown: Bool, altAscii: UInt8, token: RepeatToken?)
    func postLeftClick(clickCount: Int)
    func postLeftClickImmediate(clickCount: Int)
    func postRightClick()
    func postRightClickImmediate()
    func setThreeFingerHoldDragSuppression(_ enabled: Bool)
    func postMiddleClick()
    func postMiddleClickImmediate()
    func postText(_ text: String)
    func postTextImmediate(_ text: String)
    func postSystemKey(_ key: KeyEventDispatcher.SystemKey)
    func postSystemKeyImmediate(_ key: KeyEventDispatcher.SystemKey)
}

private final class CGEventKeyDispatcher: @unchecked Sendable, KeyDispatching {
    private static let globeKeyCode = CGKeyCode(kVK_Function)
    private static let globeModifierFlag = CGEventFlags.maskSecondaryFn
    private static let emojiTriggerCode = CGKeyCode(kVK_Space)
    private static let emojiTriggerFlags: CGEventFlags = [.maskCommand, .maskControl]
    private static let mediaKeyDownState = Int32(0xA)
    private static let mediaKeyUpState = Int32(0xB)
    private static let mediaKeySubtype: Int16 = 8
    private static let mediaKeyDownFlags = NSEvent.ModifierFlags(rawValue: 0xA00)
    private static let mediaKeyUpFlags = NSEvent.ModifierFlags(rawValue: 0xB00)
    private static let mediaTapDwellSeconds: TimeInterval = 0.001

    private let queue = DispatchQueue(
        label: "ink.ranna.GlassToKey.KeyDispatch.CGEvent",
        qos: .userInteractive
    )
    private let eventSourceLock = OSAllocatedUnfairLock<CGEventSource?>(uncheckedState: nil)
    private let threeFingerHoldDragSuppressor = ThreeFingerHoldDragSuppressor()

    func postKeyStroke(
        code: CGKeyCode,
        flags: CGEventFlags,
        altAscii: UInt8,
        token: RepeatToken? = nil
    ) {
        queue.async { [self] in
            postKeyStrokeImmediate(code: code, flags: flags, altAscii: altAscii, token: token)
        }
    }

    func postKeyStrokeImmediate(
        code: CGKeyCode,
        flags: CGEventFlags,
        altAscii: UInt8,
        token: RepeatToken? = nil
    ) {
        guard token?.isActive ?? true else { return }
        autoreleasepool {
            guard token?.isActive ?? true else { return }
            guard let source = ensureEventSource() else {
                return
            }
            guard let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: code,
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: code,
                keyDown: false
            ) else {
                return
            }
            if code == Self.globeKeyCode {
                guard let emojiDown = CGEvent(
                    keyboardEventSource: source,
                    virtualKey: Self.emojiTriggerCode,
                    keyDown: true
                ),
                let emojiUp = CGEvent(
                    keyboardEventSource: source,
                    virtualKey: Self.emojiTriggerCode,
                    keyDown: false
                ) else {
                    return
                }
                AutocorrectEngine.shared.recordDispatchedKey(
                    code: Self.emojiTriggerCode,
                    flags: Self.emojiTriggerFlags,
                    keyDown: true,
                    altAscii: 0
                )
                emojiDown.flags = Self.emojiTriggerFlags
                emojiUp.flags = Self.emojiTriggerFlags
                emojiDown.post(tap: .cghidEventTap)
                emojiUp.post(tap: .cghidEventTap)
                return
            }
            AutocorrectEngine.shared.recordDispatchedKey(
                code: code,
                flags: resolvedFlags(for: code, flags: flags, keyDown: true),
                keyDown: true,
                altAscii: altAscii
            )
            configureKeyboardEvent(keyDown, code: code, keyDown: true, flags: flags)
            configureKeyboardEvent(keyUp, code: code, keyDown: false, flags: flags)
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    func postKey(
        code: CGKeyCode,
        flags: CGEventFlags,
        keyDown: Bool,
        altAscii: UInt8,
        token: RepeatToken? = nil
    ) {
        queue.async { [self] in
            postKeyImmediate(
                code: code,
                flags: flags,
                keyDown: keyDown,
                altAscii: altAscii,
                token: token
            )
        }
    }

    func postKeyImmediate(
        code: CGKeyCode,
        flags: CGEventFlags,
        keyDown: Bool,
        altAscii: UInt8,
        token: RepeatToken? = nil
    ) {
        guard token?.isActive ?? true else { return }
        autoreleasepool {
            guard token?.isActive ?? true else { return }
            guard let source = ensureEventSource() else {
                return
            }
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: code,
                keyDown: keyDown
            ) else {
                return
            }
            if keyDown {
                AutocorrectEngine.shared.recordDispatchedKey(
                    code: code,
                    flags: resolvedFlags(for: code, flags: flags, keyDown: true),
                    keyDown: true,
                    altAscii: altAscii
                )
            }
            configureKeyboardEvent(event, code: code, keyDown: keyDown, flags: flags)
            event.post(tap: .cghidEventTap)
        }
    }

    @inline(__always)
    private func configureKeyboardEvent(
        _ event: CGEvent,
        code: CGKeyCode,
        keyDown: Bool,
        flags: CGEventFlags
    ) {
        if code == Self.globeKeyCode {
            event.type = .flagsChanged
        }
        event.flags = resolvedFlags(for: code, flags: flags, keyDown: keyDown)
    }

    @inline(__always)
    private func resolvedFlags(
        for code: CGKeyCode,
        flags: CGEventFlags,
        keyDown: Bool
    ) -> CGEventFlags {
        guard code == Self.globeKeyCode else { return flags }
        var resolved = flags
        if keyDown {
            resolved.insert(Self.globeModifierFlag)
        } else {
            resolved.remove(Self.globeModifierFlag)
        }
        return resolved
    }

    func postLeftClick(clickCount: Int) {
        queue.async { [self] in
            postLeftClickImmediate(clickCount: clickCount)
        }
    }

    func postLeftClickImmediate(clickCount: Int) {
        autoreleasepool {
            guard let source = ensureEventSource() else {
                return
            }
            let location = CGEvent(source: nil)?.location ?? .zero
            let clampedCount = max(1, clickCount)
            var currentCount = 1
            while currentCount <= clampedCount {
                guard let mouseDown = CGEvent(
                    mouseEventSource: source,
                    mouseType: .leftMouseDown,
                    mouseCursorPosition: location,
                    mouseButton: .left
                ),
                let mouseUp = CGEvent(
                    mouseEventSource: source,
                    mouseType: .leftMouseUp,
                    mouseCursorPosition: location,
                    mouseButton: .left
                ) else {
                    return
                }
                mouseDown.setIntegerValueField(.mouseEventClickState, value: Int64(currentCount))
                mouseUp.setIntegerValueField(.mouseEventClickState, value: Int64(currentCount))
                mouseDown.post(tap: .cghidEventTap)
                mouseUp.post(tap: .cghidEventTap)
                currentCount += 1
            }
        }
    }

    func postRightClick() {
        queue.async { [self] in
            postRightClickImmediate()
        }
    }

    func postRightClickImmediate() {
        autoreleasepool {
            guard let source = ensureEventSource() else {
                return
            }
            let location = CGEvent(source: nil)?.location ?? .zero
            guard let mouseDown = CGEvent(
                mouseEventSource: source,
                mouseType: .rightMouseDown,
                mouseCursorPosition: location,
                mouseButton: .right
            ),
            let mouseUp = CGEvent(
                mouseEventSource: source,
                mouseType: .rightMouseUp,
                mouseCursorPosition: location,
                mouseButton: .right
            ) else {
                return
            }
            mouseDown.post(tap: .cghidEventTap)
            mouseUp.post(tap: .cghidEventTap)
        }
    }

    func setThreeFingerHoldDragSuppression(_ enabled: Bool) {
        threeFingerHoldDragSuppressor.setEnabled(enabled)
    }

    func postMiddleClick() {
        queue.async { [self] in
            postMiddleClickImmediate()
        }
    }

    func postMiddleClickImmediate() {
        autoreleasepool {
            guard let source = ensureEventSource() else {
                return
            }
            let location = CGEvent(source: nil)?.location ?? .zero
            guard let mouseDown = CGEvent(
                mouseEventSource: source,
                mouseType: .otherMouseDown,
                mouseCursorPosition: location,
                mouseButton: .center
            ),
            let mouseUp = CGEvent(
                mouseEventSource: source,
                mouseType: .otherMouseUp,
                mouseCursorPosition: location,
                mouseButton: .center
            ) else {
                return
            }
            mouseDown.post(tap: .cghidEventTap)
            mouseUp.post(tap: .cghidEventTap)
        }
    }

    func postText(_ text: String) {
        guard !text.isEmpty else { return }
        queue.async { [self] in
            postTextImmediate(text)
        }
    }

    func postTextImmediate(_ text: String) {
        guard !text.isEmpty else { return }
        autoreleasepool {
            guard let source = ensureEventSource() else {
                return
            }
            guard let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0,
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0,
                keyDown: false
            ) else {
                return
            }
            let utf16 = Array(text.utf16)
            utf16.withUnsafeBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                keyDown.keyboardSetUnicodeString(
                    stringLength: buffer.count,
                    unicodeString: baseAddress
                )
                keyUp.keyboardSetUnicodeString(
                    stringLength: buffer.count,
                    unicodeString: baseAddress
                )
            }
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    func postSystemKey(_ key: KeyEventDispatcher.SystemKey) {
        queue.async { [self] in
            postSystemKeyImmediate(key)
        }
    }

    func postSystemKeyImmediate(_ key: KeyEventDispatcher.SystemKey) {
        autoreleasepool {
            postSystemEvent(key, keyDown: true)
            Thread.sleep(forTimeInterval: Self.mediaTapDwellSeconds)
            postSystemEvent(key, keyDown: false)
        }
    }

    @inline(__always)
    private func postSystemEvent(
        _ key: KeyEventDispatcher.SystemKey,
        keyDown: Bool
    ) {
        let keyState = keyDown ? Self.mediaKeyDownState : Self.mediaKeyUpState
        let data1 = Int((key.keyType << 16) | (keyState << 8))
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: keyDown ? Self.mediaKeyDownFlags : Self.mediaKeyUpFlags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: Self.mediaKeySubtype,
            data1: data1,
            data2: -1
        )?.cgEvent else {
            return
        }
        event.post(tap: .cgSessionEventTap)
    }

    @inline(__always)
    private func ensureEventSource() -> CGEventSource? {
        eventSourceLock.withLockUnchecked { source in
            if let source {
                return source
            }
            guard let created = CGEventSource(stateID: .hidSystemState) else {
                return nil
            }
            source = created
            return created
        }
    }
}

private final class ThreeFingerHoldDragSuppressor: @unchecked Sendable {
    private struct State {
        var isEnabled = false
    }

    private let stateLock = OSAllocatedUnfairLock<State>(uncheckedState: State())
    private let installLock = NSLock()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func setEnabled(_ enabled: Bool) {
        stateLock.withLockUnchecked { state in
            state.isEnabled = enabled
        }
        if enabled {
            ensureEventTap()
        }
    }

    private func ensureEventTap() {
        guard InputMonitoringPermission.hasListenAccess() else { return }
        if Thread.isMainThread {
            installEventTapIfNeeded()
            return
        }
        DispatchQueue.main.sync {
            installEventTapIfNeeded()
        }
    }

    private func installEventTapIfNeeded() {
        installLock.lock()
        defer { installLock.unlock() }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
            return
        }

        let mask = (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)

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

    private func shouldSuppress(type: CGEventType) -> Bool {
        guard Self.isSuppressible(type) else { return false }
        return stateLock.withLockUnchecked { $0.isEnabled }
    }

    private func reenableIfNeeded(for type: CGEventType) {
        guard type == .tapDisabledByTimeout || type == .tapDisabledByUserInput else { return }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private static func isSuppressible(_ type: CGEventType) -> Bool {
        switch type {
        case .leftMouseDown,
             .leftMouseUp,
             .leftMouseDragged:
            return true
        default:
            return false
        }
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let suppressor = Unmanaged<ThreeFingerHoldDragSuppressor>.fromOpaque(refcon).takeUnretainedValue()
        suppressor.reenableIfNeeded(for: type)
        if suppressor.shouldSuppress(type: type) {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}

private final class AppLaunchDispatcher: @unchecked Sendable {
    func open(_ actionLabel: String) {
        guard let spec = AppLaunchActionHelper.parse(actionLabel) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = launchArguments(for: spec)
        try? process.run()
    }

    private func launchArguments(for spec: AppLaunchActionSpec) -> [String] {
        var arguments = [spec.fileName]
        let appArguments = tokenizeArguments(spec.arguments)
        if !appArguments.isEmpty {
            arguments.append("--args")
            arguments.append(contentsOf: appArguments)
        }
        return arguments
    }

    private func tokenizeArguments(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var arguments: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false

        for character in trimmed {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }

            if character == "\\" {
                escaped = true
                continue
            }

            if let activeQuote = quote {
                if character == activeQuote {
                    self.flushCurrentArgumentIfNeeded(into: &arguments, current: &current)
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }

            if character == "\"" || character == "'" {
                quote = character
                continue
            }

            if character.isWhitespace {
                flushCurrentArgumentIfNeeded(into: &arguments, current: &current)
                continue
            }

            current.append(character)
        }

        flushCurrentArgumentIfNeeded(into: &arguments, current: &current)
        return arguments
    }

    private func flushCurrentArgumentIfNeeded(into arguments: inout [String], current: inout String) {
        guard !current.isEmpty else { return }
        arguments.append(current)
        current.removeAll(keepingCapacity: true)
    }
}

final class DispatchService: @unchecked Sendable {
    struct Metrics: Sendable {
        var queueDepth: Int = 0
        var drops: UInt64 = 0
    }

    static let shared = DispatchService()

    private static let defaultQueueCapacity = 1024

    private enum Command {
        case keyStroke(code: CGKeyCode, flags: CGEventFlags, altAscii: UInt8, token: RepeatToken?, sourceSequence: UInt64?)
        case key(code: CGKeyCode, flags: CGEventFlags, keyDown: Bool, altAscii: UInt8, token: RepeatToken?, sourceSequence: UInt64?)
        case appLaunch(String, sourceSequence: UInt64?)
        case leftClick(clickCount: Int, sourceSequence: UInt64?)
        case rightClick(sourceSequence: UInt64?)
        case middleClick(sourceSequence: UInt64?)
        case systemKey(KeyEventDispatcher.SystemKey, sourceSequence: UInt64?)
        case haptic(strength: Double, deviceID: String?, sourceSequence: UInt64?)
    }

    private struct RingQueue {
        private var storage: [Command?]
        private(set) var head: Int = 0
        private(set) var tail: Int = 0
        private(set) var count: Int = 0

        init(capacity: Int) {
            storage = Array(repeating: nil, count: max(16, capacity))
        }

        mutating func enqueue(_ command: Command) -> Bool {
            guard count < storage.count else { return false }
            storage[tail] = command
            tail = (tail + 1) % storage.count
            count += 1
            return true
        }

        mutating func dequeue() -> Command? {
            guard count > 0, let command = storage[head] else {
                return nil
            }
            storage[head] = nil
            head = (head + 1) % storage.count
            count -= 1
            return command
        }

        mutating func removeAll() {
            guard count > 0 else {
                head = 0
                tail = 0
                return
            }
            for index in storage.indices {
                storage[index] = nil
            }
            head = 0
            tail = 0
            count = 0
        }
    }

    private struct State {
        var queue = RingQueue(capacity: DispatchService.defaultQueueCapacity)
        var isPumpScheduled = false
        var drops: UInt64 = 0
    }

    private let keyDispatcher: KeyEventDispatcher
    private let appLaunchDispatcher = AppLaunchDispatcher()
    private let stateLock = OSAllocatedUnfairLock<State>(uncheckedState: State())
    private let recordedEventHandlerLock = OSAllocatedUnfairLock<((RuntimeDispatchEvent) -> Void)?>(uncheckedState: nil)
    private let captureEventHandlerLock = OSAllocatedUnfairLock<((RuntimeDispatchEvent) -> Void)?>(uncheckedState: nil)
    private let dispatchQueue = DispatchQueue(
        label: "ink.ranna.GlassToKey.DispatchPump",
        qos: .userInteractive
    )

    init(keyDispatcher: KeyEventDispatcher = .shared) {
        self.keyDispatcher = keyDispatcher
    }

    func postKeyStroke(
        code: CGKeyCode,
        flags: CGEventFlags,
        altAscii: UInt8 = 0,
        token: RepeatToken? = nil,
        sourceSequence: UInt64? = nil
    ) {
        enqueue(
            .keyStroke(
                code: code,
                flags: flags,
                altAscii: altAscii,
                token: token,
                sourceSequence: sourceSequence
            )
        )
    }

    func postKey(
        code: CGKeyCode,
        flags: CGEventFlags,
        keyDown: Bool,
        altAscii: UInt8 = 0,
        token: RepeatToken? = nil,
        sourceSequence: UInt64? = nil
    ) {
        enqueue(
            .key(
                code: code,
                flags: flags,
                keyDown: keyDown,
                altAscii: altAscii,
                token: token,
                sourceSequence: sourceSequence
            )
        )
    }

    func postAppLaunch(_ actionLabel: String, sourceSequence: UInt64? = nil) {
        enqueue(.appLaunch(actionLabel, sourceSequence: sourceSequence))
    }

    func postLeftClick(clickCount: Int = 1, sourceSequence: UInt64? = nil) {
        enqueue(.leftClick(clickCount: clickCount, sourceSequence: sourceSequence))
    }

    func postRightClick(sourceSequence: UInt64? = nil) {
        enqueue(.rightClick(sourceSequence: sourceSequence))
    }

    func setThreeFingerHoldDragSuppression(_ enabled: Bool) {
        keyDispatcher.setThreeFingerHoldDragSuppression(enabled)
    }

    func postMiddleClick(sourceSequence: UInt64? = nil) {
        enqueue(.middleClick(sourceSequence: sourceSequence))
    }

    func postVolumeUp(sourceSequence: UInt64? = nil) {
        enqueue(.systemKey(.volumeUp, sourceSequence: sourceSequence))
    }

    func postVolumeDown(sourceSequence: UInt64? = nil) {
        enqueue(.systemKey(.volumeDown, sourceSequence: sourceSequence))
    }

    func postBrightnessUp(sourceSequence: UInt64? = nil) {
        enqueue(.systemKey(.brightnessUp, sourceSequence: sourceSequence))
    }

    func postBrightnessDown(sourceSequence: UInt64? = nil) {
        enqueue(.systemKey(.brightnessDown, sourceSequence: sourceSequence))
    }

    func postHaptic(strength: Double, deviceID: String?, sourceSequence: UInt64? = nil) {
        enqueue(.haptic(strength: strength, deviceID: deviceID, sourceSequence: sourceSequence))
    }

    func snapshotMetrics() -> Metrics {
        stateLock.withLockUnchecked { state in
            Metrics(queueDepth: state.queue.count, drops: state.drops)
        }
    }

    func setCaptureEventHandler(_ handler: ((RuntimeDispatchEvent) -> Void)?) {
        captureEventHandlerLock.withLockUnchecked { $0 = handler }
    }

    func setRecordedEventHandler(_ handler: ((RuntimeDispatchEvent) -> Void)?) {
        recordedEventHandlerLock.withLockUnchecked { $0 = handler }
    }

    func clearQueue() {
        stateLock.withLockUnchecked { state in
            state.queue.removeAll()
        }
    }

    private func enqueue(_ command: Command) {
        var shouldSchedulePump = false
        var didEnqueue = false
        stateLock.withLockUnchecked { state in
            guard state.queue.enqueue(command) else {
                state.drops &+= 1
                return
            }
            didEnqueue = true
            if !state.isPumpScheduled {
                state.isPumpScheduled = true
                shouldSchedulePump = true
            }
        }

        guard didEnqueue else { return }
        emitRecordedEvent(for: command)
        guard shouldSchedulePump else { return }
        dispatchQueue.async { [weak self] in
            self?.drainQueue()
        }
    }

    private func drainQueue() {
        while let command = popNextCommand() {
            dispatch(command)
        }
    }

    private func popNextCommand() -> Command? {
        stateLock.withLockUnchecked { state in
            guard let command = state.queue.dequeue() else {
                state.isPumpScheduled = false
                return nil
            }
            return command
        }
    }

    private func dispatch(_ command: Command) {
        switch command {
        case let .keyStroke(code, flags, altAscii, token, sourceSequence):
            keyDispatcher.postKeyStrokeImmediate(
                code: code,
                flags: flags,
                altAscii: altAscii,
                token: token
            )
            emitCaptureEvent(
                kind: .keyStroke(code: code, flags: flags, altAscii: altAscii),
                sourceSequence: sourceSequence
            )
        case let .key(code, flags, keyDown, altAscii, token, sourceSequence):
            keyDispatcher.postKeyImmediate(
                code: code,
                flags: flags,
                keyDown: keyDown,
                altAscii: altAscii,
                token: token
            )
            emitCaptureEvent(
                kind: .key(
                    code: code,
                    flags: flags,
                    keyDown: keyDown,
                    altAscii: altAscii
                ),
                sourceSequence: sourceSequence
            )
        case let .appLaunch(actionLabel, sourceSequence):
            appLaunchDispatcher.open(actionLabel)
            emitCaptureEvent(
                kind: .appLaunch(actionLabel),
                sourceSequence: sourceSequence
            )
        case let .leftClick(clickCount, sourceSequence):
            keyDispatcher.postLeftClickImmediate(clickCount: clickCount)
            emitCaptureEvent(
                kind: .leftClick(clickCount: clickCount),
                sourceSequence: sourceSequence
            )
        case let .rightClick(sourceSequence):
            keyDispatcher.postRightClickImmediate()
            emitCaptureEvent(kind: .rightClick, sourceSequence: sourceSequence)
        case let .middleClick(sourceSequence):
            keyDispatcher.postMiddleClickImmediate()
            emitCaptureEvent(kind: .middleClick, sourceSequence: sourceSequence)
        case let .systemKey(key, sourceSequence):
            keyDispatcher.postSystemKeyImmediate(key)
            emitCaptureEvent(
                kind: .systemKey(key.captureLabel),
                sourceSequence: sourceSequence
            )
        case let .haptic(strength, deviceID, sourceSequence):
            _ = OMSManager.shared.playHapticFeedback(strength: strength, deviceID: deviceID)
            emitCaptureEvent(
                kind: .haptic(strength: strength, deviceID: deviceID),
                sourceSequence: sourceSequence
            )
        }
    }

    private func emitRecordedEvent(for command: Command) {
        guard let handler = recordedEventHandlerLock.withLockUnchecked({ $0 }) else { return }
        handler(recordedEvent(for: command))
    }

    private func recordedEvent(for command: Command) -> RuntimeDispatchEvent {
        switch command {
        case let .keyStroke(code, flags, altAscii, _, sourceSequence):
            return makeDispatchEvent(
                kind: .keyStroke(code: code, flags: flags, altAscii: altAscii),
                sourceSequence: sourceSequence
            )
        case let .key(code, flags, keyDown, altAscii, _, sourceSequence):
            return makeDispatchEvent(
                kind: .key(code: code, flags: flags, keyDown: keyDown, altAscii: altAscii),
                sourceSequence: sourceSequence
            )
        case let .appLaunch(actionLabel, sourceSequence):
            return makeDispatchEvent(
                kind: .appLaunch(actionLabel),
                sourceSequence: sourceSequence
            )
        case let .leftClick(clickCount, sourceSequence):
            return makeDispatchEvent(
                kind: .leftClick(clickCount: clickCount),
                sourceSequence: sourceSequence
            )
        case let .rightClick(sourceSequence):
            return makeDispatchEvent(kind: .rightClick, sourceSequence: sourceSequence)
        case let .middleClick(sourceSequence):
            return makeDispatchEvent(kind: .middleClick, sourceSequence: sourceSequence)
        case let .systemKey(key, sourceSequence):
            return makeDispatchEvent(
                kind: .systemKey(key.captureLabel),
                sourceSequence: sourceSequence
            )
        case let .haptic(strength, deviceID, sourceSequence):
            return makeDispatchEvent(
                kind: .haptic(strength: strength, deviceID: deviceID),
                sourceSequence: sourceSequence
            )
        }
    }

    private func emitCaptureEvent(
        kind: RuntimeDispatchEventKind,
        sourceSequence: UInt64?
    ) {
        guard let handler = captureEventHandlerLock.withLockUnchecked({ $0 }) else { return }
        handler(makeDispatchEvent(kind: kind, sourceSequence: sourceSequence))
    }

    private func makeDispatchEvent(
        kind: RuntimeDispatchEventKind,
        sourceSequence: UInt64?
    ) -> RuntimeDispatchEvent {
        RuntimeDispatchEvent(
            kind: kind,
            timestamp: ProcessInfo.processInfo.systemUptime,
            uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
            sourceSequence: sourceSequence
        )
    }
}
