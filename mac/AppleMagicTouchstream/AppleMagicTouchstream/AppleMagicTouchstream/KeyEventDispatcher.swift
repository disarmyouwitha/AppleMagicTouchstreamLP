import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation
import OpenMultitouchSupport
import os

/// Saved profiles retain their existing level × 100 representation. Live
/// typing always uses waveform 6 and the actual bounded waveform scale.
enum TypingHapticFeedback {
    static let waveform: Int32 = 6
    static func level(_ value: Double) -> Double {
        value.isFinite ? min(2,max(0,value)) : 0
    }
    static func parameters(for value: Double) -> (waveform:Int32,level:Float)? {
        let value = level(value)
        guard value > 0 else { return nil }
        return (waveform,Float(value))
    }
}

/// Build both edges before posting. A shortcut borrows modifiers for its down;
/// its up restores the pre-shortcut state instead of leaving those flags behind.
/// This factory is also used offline: constructing events never posts input.
enum KeyboardStrokeOutput {
    struct Events { let down:CGEvent; let up:CGEvent }
    static func events(code:CGKeyCode,flags:CGEventFlags,restoringFlags:CGEventFlags,
                       source:CGEventSource? = nil) -> Events? {
        let emoji = code == CGKeyCode(kVK_Function)
        let key = emoji ? CGKeyCode(kVK_Space) : code
        guard let down = CGEvent(keyboardEventSource:source,virtualKey:key,keyDown:true),
              let up = CGEvent(keyboardEventSource:source,virtualKey:key,keyDown:false) else { return nil }
        down.flags = emoji ? [.maskCommand,.maskControl] : flags
        up.flags = restoringFlags
        return Events(down:down,up:up)
    }
}

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
        token: RepeatToken? = nil,
        heldFlags:CGEventFlags = []
    ) {
        dispatcher.postKeyStrokeImmediate(code: code, flags: flags, altAscii: altAscii, token: token, heldFlags:heldFlags)
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
    func postKeyStrokeImmediate(code: CGKeyCode, flags: CGEventFlags, altAscii: UInt8, token: RepeatToken?, heldFlags:CGEventFlags)
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
        token: RepeatToken? = nil,
        heldFlags:CGEventFlags = []
    ) {
        guard token?.isActive ?? true else { return }
        autoreleasepool {
            guard token?.isActive ?? true else { return }
            guard let source = ensureEventSource() else {
                return
            }
            let restoringFlags = CGEventSource.flagsState(.combinedSessionState).union(heldFlags)
            guard let events = KeyboardStrokeOutput.events(code:code,flags:flags,
                    restoringFlags:restoringFlags,source:source) else { return }
            let keyDown = events.down, keyUp = events.up
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            if code == Self.globeKeyCode { AutocorrectEngine.shared.invalidate(); return }
            AutocorrectEngine.shared.recordDispatchedKey(code: code, flags: flags, keyDown: true, altAscii: altAscii)
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
            AutocorrectEngine.shared.recordDispatchedKey(code: code, flags: flags, keyDown: keyDown, altAscii: altAscii)
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
        AutocorrectEngine.shared.invalidate()
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
        AutocorrectEngine.shared.invalidate()
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
        AutocorrectEngine.shared.invalidate()
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
        AutocorrectEngine.shared.invalidate()
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
        AutocorrectEngine.shared.invalidate()
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

private final class AppLaunchDispatcher: @unchecked Sendable {
    func open(_ actionLabel: String) {
        guard let spec = AppLaunchActionHelper.parse(actionLabel),
              !spec.fileName.hasPrefix("-") else { return }

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

/// Logical owners share synthetic keys without releasing another owner's key.
/// Kept pure so recording-mode tests exercise the same transitions as live output.
enum HeldGestureShortcutInput {
    static func continues<C:Collection>(time:Double,previous:Double?,contacts:C) -> Bool where C.Element == OMSRawTouch {
        guard time.isFinite, previous.map({time > $0 && time-$0 <= 0.15}) ?? true else { return false }
        var ids = SIMD16<Int32>(repeating:0), count = 0
        for touch in contacts where touch.state == .making || touch.state == .touching {
            guard count < 16, touch.posX.isFinite, touch.posY.isFinite, touch.telemetry?.fingerID != 6,
                  !(0..<count).contains(where:{ids[$0] == touch.id}) else { return false }
            ids[count] = touch.id; count += 1
        }
        return true
    }
}

enum GestureShortcutOwner:Hashable,Sendable { case pad(UInt64), corners(UInt64), coordinated }
struct GestureShortcutKeyOwnership {
    struct Edge:Equatable { var code:CGKeyCode; var flags:CGEventFlags; var down:Bool }
    private var keyboard:Set<CGKeyCode> = []
    private var owners:[GestureShortcutOwner:[CGKeyCode]] = [:]
    static func modifierFlag(_ code:CGKeyCode) -> CGEventFlags {
        switch Int(code) {
        case kVK_Shift:return KeyboardModifierFlags.leftShift
        case kVK_RightShift:return KeyboardModifierFlags.rightShift
        case kVK_Control:return KeyboardModifierFlags.leftControl
        case kVK_RightControl:return KeyboardModifierFlags.rightControl
        case kVK_Option:return KeyboardModifierFlags.leftOption
        case kVK_RightOption:return KeyboardModifierFlags.rightOption
        case kVK_Command:return KeyboardModifierFlags.leftCommand
        case kVK_RightCommand:return KeyboardModifierFlags.rightCommand
        default:return []
        }
    }
    private var gestureKeys:Set<CGKeyCode> { Set(owners.values.flatMap { $0 }) }
    var flags:CGEventFlags { gestureKeys.reduce(into:CGEventFlags()) { $0.formUnion(Self.modifierFlag($1)) } }
    private var allFlags:CGEventFlags { keyboard.reduce(into:flags) { $0.formUnion(Self.modifierFlag($1)) } }
    func owns(_ code:CGKeyCode) -> Bool { gestureKeys.contains(code) }
    mutating func keyboardEdge(code:CGKeyCode,flags:CGEventFlags,down:Bool) -> Edge? {
        if down { keyboard.insert(code) } else { keyboard.remove(code) }
        guard down || !owns(code) else { return nil }
        return Edge(code:code,flags:flags.union(self.flags),down:down)
    }
    static func keys(for action:KeyAction) -> [CGKeyCode] {
        guard action.kind == .key else { return [] }
        let spec = KeyActionCatalog.shortcutSpec(for:action)
        var keys:[CGKeyCode] = []
        for modifier in ShortcutModifier.ordered {
            let variant = spec?.modifiers[modifier]
            let generic:CGEventFlags
            let left:Int, right:Int
            switch modifier {
            case .control: generic = .maskControl; left = kVK_Control; right = kVK_RightControl
            case .shift: generic = .maskShift; left = kVK_Shift; right = kVK_RightShift
            case .option: generic = .maskAlternate; left = kVK_Option; right = kVK_RightOption
            case .command: generic = .maskCommand; left = kVK_Command; right = kVK_RightCommand
            }
            if variant != nil || CGEventFlags(rawValue:action.flags).contains(generic) {
                keys.append(CGKeyCode(variant == .right ? right : left))
            }
        }
        if spec?.keyLabel.isEmpty != true && !keys.contains(action.keyCode) { keys.append(action.keyCode) }
        return keys
    }
    mutating func begin(_ owner:GestureShortcutOwner,action:KeyAction) -> [Edge] {
        var edges = end(owner)
        let keys = Self.keys(for:action), already = gestureKeys.union(keyboard)
        owners[owner] = keys
        for code in keys where !already.contains(code) { edges.append(.init(code:code,flags:allFlags,down:true)) }
        return edges
    }
    mutating func end(_ owner:GestureShortcutOwner) -> [Edge] {
        guard let keys = owners.removeValue(forKey:owner) else { return [] }
        let retained = gestureKeys.union(keyboard)
        return keys.reversed().filter { !retained.contains($0) }.map { .init(code:$0,flags:allFlags,down:false) }
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
        case keyStroke(code: CGKeyCode, flags: CGEventFlags, altAscii: UInt8, token: RepeatToken?, heldFlags:CGEventFlags)
        case key(code: CGKeyCode, flags: CGEventFlags, keyDown: Bool, altAscii: UInt8, token: RepeatToken?)
        case appLaunch(String)
        case voiceToggle
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

    private let shortcutKeys = OSAllocatedUnfairLock(initialState:GestureShortcutKeyOwnership())
    private let appLaunchDispatcher = AppLaunchDispatcher()
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
        shortcutKeys.withLock { keys in
            let combined = flags.union(keys.flags)
            if keys.owns(code) {
                enqueue(.key(code:code,flags:combined,keyDown:true,altAscii:altAscii,token:token),sourceSequence:sourceSequence)
            } else {
                enqueue(.keyStroke(code:code,flags:combined,altAscii:altAscii,token:token,heldFlags:keys.flags),sourceSequence:sourceSequence)
            }
        }
    }

    func postKey(
        code: CGKeyCode,
        flags: CGEventFlags,
        keyDown: Bool,
        altAscii: UInt8 = 0,
        token: RepeatToken? = nil,
        sourceSequence: UInt64? = nil
    ) {
        shortcutKeys.withLock { keys in
            guard let edge = keys.keyboardEdge(code:code,flags:flags,down:keyDown) else { return }
            enqueue(.key(code:edge.code,flags:edge.flags,keyDown:edge.down,altAscii:altAscii,token:token),sourceSequence:sourceSequence)
        }
    }

    var heldGestureFlags:CGEventFlags { shortcutKeys.withLock { $0.flags } }

    func postGestureShortcut(_ assignment:GestureShortcutAssignment,owner:GestureShortcutOwner) {
        guard let action = assignment.action else { return }
        if assignment.holdUntilRelease, action.kind == .key {
            shortcutKeys.withLock { keys in
                for edge in keys.begin(owner,action:action) {
                    enqueue(.key(code:edge.code,flags:edge.flags,keyDown:edge.down,altAscii:0,token:nil),sourceSequence:nil)
                }
            }
        } else if action.kind == .appLaunch { postAppLaunch(action.label) }
        else { postKeyStroke(code:action.keyCode,flags:CGEventFlags(rawValue:action.flags)) }
    }
    func releaseGestureShortcut(_ owner:GestureShortcutOwner) {
        shortcutKeys.withLock { keys in
            for edge in keys.end(owner) {
                enqueue(.key(code:edge.code,flags:edge.flags,keyDown:edge.down,altAscii:0,token:nil),sourceSequence:nil)
            }
        }
    }

    func postVoiceToggle(sourceSequence: UInt64? = nil) {
        enqueue(.voiceToggle, sourceSequence: sourceSequence)
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

    /// Uses the existing live keyboard dispatch queue: deletion and insertion are
    /// one output batch, never interleaved with later app-generated keys.
    func performAutocorrectReplacement(_ plan: AutocorrectKeyboardReplacement, pid: pid_t,
                                       isCurrent: @escaping @Sendable () -> Bool,
                                       completion: @escaping @Sendable (AutocorrectKeyboardOutput.Outcome) -> Void) {
        guard keyDispatcher != nil else { completion(.skipped("Replay does not post keyboard output.")); return }
        dispatchQueue.async { [self] in
            guard isCurrent() else { completion(.skipped("Newer AMT input arrived.")); return }
            guard !IsSecureEventInputEnabled() else { completion(.skipped("Secure Event Input is enabled.")); return }
            guard AXIsProcessTrusted() else { completion(.skipped("Accessibility permission is required.")); return }
            guard NSRunningApplication(processIdentifier: pid)?.isActive == true else {
                completion(.skipped("The focused app changed.")); return
            }
            guard shortcutKeys.withLock({ $0.flags.isEmpty }),
                  CGEventSource.flagsState(.combinedSessionState)
                    .intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn]).isEmpty else {
                completion(.skipped("A modifier is held.")); return
            }
            guard let events = plan.events() else { completion(.skipped("Keyboard events could not be created.")); return }
            completion(AutocorrectKeyboardOutput.send(events, isCurrent: isCurrent,
                begin: { AutocorrectEngine.shared.invalidate() },
                post: { event in
                    event.timestamp = DispatchTime.now().uptimeNanoseconds
                    event.post(tap: .cghidEventTap)
                }, pause: { Thread.sleep(forTimeInterval: $0) }))
        }
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
        if keyDispatcher != nil {
            AutocorrectEngine.shared.invalidate()
            VoiceDictationOutput.cancel()
        }
        let cancelledCommands = stateLock.withLockUnchecked { state in
            let pending = state.queue.removeAll()
            // A queue reset may discard work, but must deliver already accepted
            // release edges so a held shortcut cannot leave a synthetic key down.
            return pending.filter { command in
                if case .key(_,_,false,_,_) = command.payload {
                    _ = state.queue.enqueue(command); return false
                }
                return true
            }
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
            case let .keyStroke(_, _, _, token, _), let .key(_, _, _, _, token):
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
        case let .keyStroke(code, flags, altAscii, token, heldFlags):
            keyDispatcher?.postKeyStrokeImmediate(
                code: code,
                flags: flags,
                altAscii: altAscii,
                token: token,
                heldFlags:heldFlags
            )
        case let .key(code, flags, keyDown, altAscii, token):
            keyDispatcher?.postKeyImmediate(
                code: code,
                flags: flags,
                keyDown: keyDown,
                altAscii: altAscii,
                token: token
            )
        case .voiceToggle:
            AutocorrectEngine.shared.invalidate()
            VoiceDictationOutput.toggle()
        case let .appLaunch(actionLabel):
            AutocorrectEngine.shared.invalidate()
            appLaunchDispatcher.open(actionLabel)
        case let .leftClick(clickCount):
            keyDispatcher?.postLeftClickImmediate(clickCount: clickCount)
        case .rightClick:
            keyDispatcher?.postRightClickImmediate()
        case .middleClick:
            keyDispatcher?.postMiddleClickImmediate()
        case let .systemKey(key):
            keyDispatcher?.postSystemKeyImmediate(key)
        case let .haptic(strength, deviceID):
            if let haptic = TypingHapticFeedback.parameters(for:strength) {
                _ = OMSManager.shared.triggerRawHaptic(actuationID:haptic.waveform,unknown1:0,
                    unknown2:haptic.level,unknown3:0,deviceID:deviceID)
            }
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
        case let .keyStroke(code, flags, altAscii, _, _):
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
        case .voiceToggle:
            return makeDispatchEvent(commandID: command.id, kind: .systemKey("voiceToggle"),
                status: status, sourceSequence: command.sourceSequence)
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
