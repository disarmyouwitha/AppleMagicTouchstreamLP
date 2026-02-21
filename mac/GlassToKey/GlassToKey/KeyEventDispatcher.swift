import Carbon
import CoreGraphics
import Foundation
import OpenMultitouchSupport
import os

final class KeyEventDispatcher: @unchecked Sendable {
    static let shared = KeyEventDispatcher()

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

    func postText(_ text: String) {
        dispatcher.postText(text)
    }

    func postTextImmediate(_ text: String) {
        dispatcher.postTextImmediate(text)
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
    func postText(_ text: String)
    func postTextImmediate(_ text: String)
}

private final class CGEventKeyDispatcher: @unchecked Sendable, KeyDispatching {
    private static let globeKeyCode = CGKeyCode(kVK_Function)
    private static let globeModifierFlag = CGEventFlags.maskSecondaryFn
    private static let emojiTriggerCode = CGKeyCode(kVK_Space)
    private static let emojiTriggerFlags: CGEventFlags = [.maskCommand, .maskControl]

    private let queue = DispatchQueue(
        label: "com.kyome.GlassToKey.KeyDispatch.CGEvent",
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
            let clampedCount = max(1, clickCount)
            mouseDown.setIntegerValueField(.mouseEventClickState, value: Int64(clampedCount))
            mouseUp.setIntegerValueField(.mouseEventClickState, value: Int64(clampedCount))
            mouseDown.post(tap: .cghidEventTap)
            mouseUp.post(tap: .cghidEventTap)
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

    private enum Command {
        case keyStroke(code: CGKeyCode, flags: CGEventFlags, altAscii: UInt8, token: RepeatToken?)
        case key(code: CGKeyCode, flags: CGEventFlags, keyDown: Bool, altAscii: UInt8, token: RepeatToken?)
        case leftClick(clickCount: Int)
        case rightClick
        case haptic(strength: Double, deviceID: String?)
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
    private let stateLock = OSAllocatedUnfairLock<State>(uncheckedState: State())
    private let dispatchQueue = DispatchQueue(
        label: "com.kyome.GlassToKey.DispatchPump",
        qos: .userInteractive
    )

    init(keyDispatcher: KeyEventDispatcher = .shared) {
        self.keyDispatcher = keyDispatcher
    }

    func postKeyStroke(
        code: CGKeyCode,
        flags: CGEventFlags,
        altAscii: UInt8 = 0,
        token: RepeatToken? = nil
    ) {
        enqueue(.keyStroke(code: code, flags: flags, altAscii: altAscii, token: token))
    }

    func postKey(
        code: CGKeyCode,
        flags: CGEventFlags,
        keyDown: Bool,
        altAscii: UInt8 = 0,
        token: RepeatToken? = nil
    ) {
        enqueue(
            .key(
                code: code,
                flags: flags,
                keyDown: keyDown,
                altAscii: altAscii,
                token: token
            )
        )
    }

    func postLeftClick(clickCount: Int = 1) {
        enqueue(.leftClick(clickCount: clickCount))
    }

    func postRightClick() {
        enqueue(.rightClick)
    }

    func postHaptic(strength: Double, deviceID: String?) {
        enqueue(.haptic(strength: strength, deviceID: deviceID))
    }

    func snapshotMetrics() -> Metrics {
        stateLock.withLockUnchecked { state in
            Metrics(queueDepth: state.queue.count, drops: state.drops)
        }
    }

    func clearQueue() {
        stateLock.withLockUnchecked { state in
            state.queue.removeAll()
        }
    }

    private func enqueue(_ command: Command) {
        var shouldSchedulePump = false
        stateLock.withLockUnchecked { state in
            guard state.queue.enqueue(command) else {
                state.drops &+= 1
                return
            }
            if !state.isPumpScheduled {
                state.isPumpScheduled = true
                shouldSchedulePump = true
            }
        }

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
        case let .keyStroke(code, flags, altAscii, token):
            keyDispatcher.postKeyStrokeImmediate(
                code: code,
                flags: flags,
                altAscii: altAscii,
                token: token
            )
        case let .key(code, flags, keyDown, altAscii, token):
            keyDispatcher.postKeyImmediate(
                code: code,
                flags: flags,
                keyDown: keyDown,
                altAscii: altAscii,
                token: token
            )
        case let .leftClick(clickCount):
            keyDispatcher.postLeftClickImmediate(clickCount: clickCount)
        case .rightClick:
            keyDispatcher.postRightClickImmediate()
        case let .haptic(strength, deviceID):
            _ = OMSManager.shared.playHapticFeedback(strength: strength, deviceID: deviceID)
        }
    }
}
