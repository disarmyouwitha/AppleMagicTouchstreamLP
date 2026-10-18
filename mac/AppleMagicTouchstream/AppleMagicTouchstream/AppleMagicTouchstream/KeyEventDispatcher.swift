import AppKit
import Carbon
import CoreGraphics
import Foundation
import OpenMultitouchSupport
import os

enum InputMonitoringPermission {
    static func hasListenAccess() -> Bool {
        CGPreflightListenEventAccess()
    }

    @discardableResult
    static func requestListenAccessIfNeeded() -> Bool {
        guard !hasListenAccess() else { return true }
        return CGRequestListenEventAccess()
    }
}


final class KeyEventDispatcher: @unchecked Sendable {
    static let shared = KeyEventDispatcher()

    enum SystemKey: Sendable {
        case volumeUp
        case volumeDown
        case volumeUpSmall
        case volumeDownSmall
        case brightnessUp
        case brightnessDown
        case brightnessUpSmall
        case brightnessDownSmall

        var mediaKeyType: Int32? {
            switch self {
            case .volumeUp:
                return 0
            case .volumeDown:
                return 1
            case .volumeUpSmall:
                return 0
            case .volumeDownSmall:
                return 1
            case .brightnessUp:
                return 2
            case .brightnessDown:
                return 3
            case .brightnessUpSmall:
                return 2
            case .brightnessDownSmall:
                return 3
            }
        }

        var usesFineAdjustmentModifiers: Bool {
            switch self {
            case .volumeUpSmall, .volumeDownSmall, .brightnessUpSmall, .brightnessDownSmall:
                return true
            default:
                return false
            }
        }

        var captureLabel: String {
            switch self {
            case .volumeUp:
                return "volumeUp"
            case .volumeDown:
                return "volumeDown"
            case .volumeUpSmall:
                return "volumeUpSmall"
            case .volumeDownSmall:
                return "volumeDownSmall"
            case .brightnessUp:
                return "brightnessUp"
            case .brightnessDown:
                return "brightnessDown"
            case .brightnessUpSmall:
                return "brightnessUpSmall"
            case .brightnessDownSmall:
                return "brightnessDownSmall"
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
                emojiDown.flags = Self.emojiTriggerFlags
                emojiUp.flags = Self.emojiTriggerFlags
                emojiDown.post(tap: .cghidEventTap)
                emojiUp.post(tap: .cghidEventTap)
                return
            }
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
        // Legacy dispatch protocol compatibility; GTK hold-drag suppression was removed.
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
        guard let mediaKeyType = key.mediaKeyType else { return }
        let keyState = keyDown ? Self.mediaKeyDownState : Self.mediaKeyUpState
        let data1 = Int((mediaKeyType << 16) | (keyState << 8))
        var modifierFlags = keyDown ? Self.mediaKeyDownFlags : Self.mediaKeyUpFlags
        if key.usesFineAdjustmentModifiers {
            modifierFlags.formUnion([.shift, .option])
        }
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: modifierFlags,
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

final class DispatchService: @unchecked Sendable {
    struct Metrics: Sendable {
        var queueDepth: Int = 0
        var drops: UInt64 = 0
    }

    static let shared = DispatchService()

    private static let defaultQueueCapacity = 1024

    private enum CommandPayload {
        case keyStroke(code: CGKeyCode, flags: CGEventFlags, altAscii: UInt8, token: RepeatToken?)
        case key(code: CGKeyCode, flags: CGEventFlags, keyDown: Bool, altAscii: UInt8, token: RepeatToken?)
        case appLaunch(String)
        case leftClick(clickCount: Int)
        case rightClick
        case middleClick
        case systemKey(KeyEventDispatcher.SystemKey)
        case haptic(strength: Double, deviceID: String?)
    }

    private struct Command {
        let id: UInt64
        let payload: CommandPayload
        let sourceSequence: UInt64?
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

        mutating func removeAll() -> [Command] {
            guard count > 0 else {
                head = 0
                tail = 0
                return []
            }
            var removed: [Command] = []
            removed.reserveCapacity(count)
            for index in storage.indices {
                if let command = storage[index] {
                    removed.append(command)
                }
                storage[index] = nil
            }
            head = 0
            tail = 0
            count = 0
            return removed
        }
    }

    private struct State {
        var queue = RingQueue(capacity: DispatchService.defaultQueueCapacity)
        var isPumpScheduled = false
        var drops: UInt64 = 0
        var nextCommandID: UInt64 = 1
    }

    private let keyDispatcher: KeyEventDispatcher?
    private let recordingSink: ((RuntimeDispatchEvent) -> Void)?
    private let recordingScheduler: (any TouchEngineScheduler)?
    private let stateLock = OSAllocatedUnfairLock<State>(uncheckedState: State())
    private let recordedEventHandlerLock = OSAllocatedUnfairLock<((RuntimeDispatchEvent) -> Void)?>(uncheckedState: nil)
    private let dispatchQueue = DispatchQueue(
        label: "ink.ranna.GlassToKey.DispatchPump",
        qos: .userInteractive
    )

    init(keyDispatcher: KeyEventDispatcher = .shared) {
        self.keyDispatcher = keyDispatcher
        self.recordingSink = nil
        self.recordingScheduler = nil
    }

    /// Synchronous recording boundary: never posts keys, clicks, haptics, or launches apps.
    init(recordingWith scheduler: any TouchEngineScheduler,
         sink: @escaping (RuntimeDispatchEvent) -> Void) {
        self.keyDispatcher = nil
        self.recordingSink = sink
        self.recordingScheduler = scheduler
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
                token: token
            ),
            sourceSequence: sourceSequence
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
                token: token
            ),
            sourceSequence: sourceSequence
        )
    }

    func postAppLaunch(_ actionLabel: String, sourceSequence: UInt64? = nil) {
        enqueue(.appLaunch(actionLabel), sourceSequence: sourceSequence)
    }

    func postLeftClick(clickCount: Int = 1, sourceSequence: UInt64? = nil) {
        enqueue(.leftClick(clickCount: clickCount), sourceSequence: sourceSequence)
    }

    func postRightClick(sourceSequence: UInt64? = nil) {
        enqueue(.rightClick, sourceSequence: sourceSequence)
    }

    func setThreeFingerHoldDragSuppression(_ enabled: Bool) {
        keyDispatcher?.setThreeFingerHoldDragSuppression(enabled)
    }

    func postMiddleClick(sourceSequence: UInt64? = nil) {
        enqueue(.middleClick, sourceSequence: sourceSequence)
    }

    func postVolumeUp(sourceSequence: UInt64? = nil) {
        enqueue(.systemKey(.volumeUp), sourceSequence: sourceSequence)
    }

    func postVolumeDown(sourceSequence: UInt64? = nil) {
        enqueue(.systemKey(.volumeDown), sourceSequence: sourceSequence)
    }

    func postVolumeUpSmall(sourceSequence: UInt64? = nil) {
        enqueue(.systemKey(.volumeUpSmall), sourceSequence: sourceSequence)
    }

    func postVolumeDownSmall(sourceSequence: UInt64? = nil) {
        enqueue(.systemKey(.volumeDownSmall), sourceSequence: sourceSequence)
    }

    func postBrightnessUp(sourceSequence: UInt64? = nil) {
        enqueue(.systemKey(.brightnessUp), sourceSequence: sourceSequence)
    }

    func postBrightnessDown(sourceSequence: UInt64? = nil) {
        enqueue(.systemKey(.brightnessDown), sourceSequence: sourceSequence)
    }

    func postBrightnessUpSmall(sourceSequence: UInt64? = nil) {
        enqueue(.systemKey(.brightnessUpSmall), sourceSequence: sourceSequence)
    }

    func postBrightnessDownSmall(sourceSequence: UInt64? = nil) {
        enqueue(.systemKey(.brightnessDownSmall), sourceSequence: sourceSequence)
    }

    func postHaptic(strength: Double, deviceID: String?, sourceSequence: UInt64? = nil) {
        enqueue(.haptic(strength: strength, deviceID: deviceID), sourceSequence: sourceSequence)
    }

    func snapshotMetrics() -> Metrics {
        stateLock.withLockUnchecked { state in
            Metrics(queueDepth: state.queue.count, drops: state.drops)
        }
    }

    func setRecordedEventHandler(_ handler: ((RuntimeDispatchEvent) -> Void)?) {
        recordedEventHandlerLock.withLockUnchecked { $0 = handler }
    }

    func clearQueue() {
        let cancelledCommands = stateLock.withLockUnchecked { state in
            state.queue.removeAll()
        }
        for command in cancelledCommands {
            emitRecordedEvent(for: command, status: .cancelled)
        }
    }

    private func enqueue(_ payload: CommandPayload, sourceSequence: UInt64?) {
        if let recordingSink {
            let command = stateLock.withLockUnchecked { state in
                let command = Command(id: state.nextCommandID, payload: payload, sourceSequence: sourceSequence)
                state.nextCommandID &+= 1
                return command
            }
            // Match cancellation semantics of the native key dispatcher.
            switch payload {
            case let .keyStroke(_, _, _, token), let .key(_, _, _, _, token):
                if let token, !token.isActive { return }
            default: break
            }
            recordingSink(recordedEvent(for: command, status: .posted))
            return
        }
        var shouldSchedulePump = false
        var enqueuedCommand: Command?
        stateLock.withLockUnchecked { state in
            let command = Command(
                id: state.nextCommandID,
                payload: payload,
                sourceSequence: sourceSequence
            )
            state.nextCommandID &+= 1
            guard state.queue.enqueue(command) else {
                state.drops &+= 1
                return
            }
            enqueuedCommand = command
            if !state.isPumpScheduled {
                state.isPumpScheduled = true
                shouldSchedulePump = true
            }
        }

        guard let enqueuedCommand else { return }
        emitRecordedEvent(for: enqueuedCommand, status: .accepted)
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
        switch command.payload {
        case let .keyStroke(code, flags, altAscii, token):
            keyDispatcher?.postKeyStrokeImmediate(
                code: code,
                flags: flags,
                altAscii: altAscii,
                token: token
            )
        case let .key(code, flags, keyDown, altAscii, token):
            keyDispatcher?.postKeyImmediate(
                code: code,
                flags: flags,
                keyDown: keyDown,
                altAscii: altAscii,
                token: token
            )
        case .appLaunch:
            // Retained solely for legacy capture decoding; GTK app launching is unsupported.
            break
        case let .leftClick(clickCount):
            keyDispatcher?.postLeftClickImmediate(clickCount: clickCount)
        case .rightClick:
            keyDispatcher?.postRightClickImmediate()
        case .middleClick:
            keyDispatcher?.postMiddleClickImmediate()
        case let .systemKey(key):
            keyDispatcher?.postSystemKeyImmediate(key)
        case let .haptic(strength, deviceID):
            _ = OMSManager.shared.playHapticFeedback(strength: strength, deviceID: deviceID)
        }
        emitRecordedEvent(for: command, status: .posted)
    }

    private func emitRecordedEvent(for command: Command, status: RuntimeDispatchEventStatus) {
        guard let handler = recordedEventHandlerLock.withLockUnchecked({ $0 }) else { return }
        handler(recordedEvent(for: command, status: status))
    }

    private func recordedEvent(
        for command: Command,
        status: RuntimeDispatchEventStatus
    ) -> RuntimeDispatchEvent {
        switch command.payload {
        case let .keyStroke(code, flags, altAscii, _):
            return makeDispatchEvent(
                commandID: command.id,
                kind: .keyStroke(code: code, flags: flags, altAscii: altAscii),
                status: status,
                sourceSequence: command.sourceSequence
            )
        case let .key(code, flags, keyDown, altAscii, _):
            return makeDispatchEvent(
                commandID: command.id,
                kind: .key(code: code, flags: flags, keyDown: keyDown, altAscii: altAscii),
                status: status,
                sourceSequence: command.sourceSequence
            )
        case let .appLaunch(actionLabel):
            return makeDispatchEvent(
                commandID: command.id,
                kind: .appLaunch(actionLabel),
                status: status,
                sourceSequence: command.sourceSequence
            )
        case let .leftClick(clickCount):
            return makeDispatchEvent(
                commandID: command.id,
                kind: .leftClick(clickCount: clickCount),
                status: status,
                sourceSequence: command.sourceSequence
            )
        case .rightClick:
            return makeDispatchEvent(
                commandID: command.id,
                kind: .rightClick,
                status: status,
                sourceSequence: command.sourceSequence
            )
        case .middleClick:
            return makeDispatchEvent(
                commandID: command.id,
                kind: .middleClick,
                status: status,
                sourceSequence: command.sourceSequence
            )
        case let .systemKey(key):
            return makeDispatchEvent(
                commandID: command.id,
                kind: .systemKey(key.captureLabel),
                status: status,
                sourceSequence: command.sourceSequence
            )
        case let .haptic(strength, deviceID):
            return makeDispatchEvent(
                commandID: command.id,
                kind: .haptic(strength: strength, deviceID: deviceID),
                status: status,
                sourceSequence: command.sourceSequence
            )
        }
    }

    private func makeDispatchEvent(
        commandID: UInt64,
        kind: RuntimeDispatchEventKind,
        status: RuntimeDispatchEventStatus,
        sourceSequence: UInt64?
    ) -> RuntimeDispatchEvent {
        RuntimeDispatchEvent(
            commandID: commandID,
            kind: kind,
            status: status,
            timestamp: recordingScheduler?.now ?? ProcessInfo.processInfo.systemUptime,
            uptimeNanoseconds: recordingScheduler?.uptimeNanoseconds ?? DispatchTime.now().uptimeNanoseconds,
            sourceSequence: sourceSequence
        )
    }
}
