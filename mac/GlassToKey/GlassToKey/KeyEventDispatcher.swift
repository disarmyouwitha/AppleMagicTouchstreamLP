import Carbon
import CoreGraphics
import Foundation

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

    func postKey(
        code: CGKeyCode,
        flags: CGEventFlags,
        keyDown: Bool,
        altAscii: UInt8 = 0,
        token: RepeatToken? = nil
    ) {
        dispatcher.postKey(code: code, flags: flags, keyDown: keyDown, altAscii: altAscii, token: token)
    }

    func postLeftClick(clickCount: Int = 1) {
        dispatcher.postLeftClick(clickCount: clickCount)
    }

    func postRightClick() {
        dispatcher.postRightClick()
    }

    func postText(_ text: String) {
        dispatcher.postText(text)
    }
}

private protocol KeyDispatching: Sendable {
    func postKeyStroke(code: CGKeyCode, flags: CGEventFlags, altAscii: UInt8, token: RepeatToken?)
    func postKey(code: CGKeyCode, flags: CGEventFlags, keyDown: Bool, altAscii: UInt8, token: RepeatToken?)
    func postLeftClick(clickCount: Int)
    func postRightClick()
    func postText(_ text: String)
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
    private var eventSource: CGEventSource?

    func postKeyStroke(
        code: CGKeyCode,
        flags: CGEventFlags,
        altAscii: UInt8,
        token: RepeatToken? = nil
    ) {
        queue.async { [self] in
            if let token, !token.isActive {
                return
            }
            autoreleasepool {
                if let token, !token.isActive {
                    return
                }
                guard let source = self.eventSource
                    ?? CGEventSource(stateID: .hidSystemState) else {
                    return
                }
                self.eventSource = source
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
    }

    func postKey(
        code: CGKeyCode,
        flags: CGEventFlags,
        keyDown: Bool,
        altAscii: UInt8,
        token: RepeatToken? = nil
    ) {
        queue.async { [self] in
            if let token, !token.isActive {
                return
            }
            autoreleasepool {
                if let token, !token.isActive {
                    return
                }
                guard let source = self.eventSource
                    ?? CGEventSource(stateID: .hidSystemState) else {
                    return
                }
                self.eventSource = source
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
            autoreleasepool {
                guard let source = self.eventSource
                    ?? CGEventSource(stateID: .hidSystemState) else {
                    return
                }
                self.eventSource = source
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
    }

    func postRightClick() {
        queue.async { [self] in
            autoreleasepool {
                guard let source = self.eventSource
                    ?? CGEventSource(stateID: .hidSystemState) else {
                    return
                }
                self.eventSource = source
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
    }

    func postText(_ text: String) {
        guard !text.isEmpty else { return }
        queue.async { [self] in
            autoreleasepool {
                guard let source = self.eventSource
                    ?? CGEventSource(stateID: .hidSystemState) else {
                    return
                }
                self.eventSource = source
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
    }
}
