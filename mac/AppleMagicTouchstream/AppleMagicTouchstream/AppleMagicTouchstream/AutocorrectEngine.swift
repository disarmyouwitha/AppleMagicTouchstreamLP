import AppKit
import ApplicationServices
import Carbon
import Combine
import Dispatch
import os

enum AutocorrectTextAccess {
    static func enqueue(_ action: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.async(execute: action)
    }
}

/// Session-only diagnostics: never persisted, exported or logged with typed text.
@MainActor final class AutocorrectStatus: ObservableObject {
    static let shared = AutocorrectStatus()
    @Published private(set) var activity = "Waiting for a completed word."
    @Published private(set) var lastReplacement: String?
    @Published private(set) var lastMethod: String?
    @Published private(set) var issue: String?

    func report(_ message: String) { activity = message; issue = nil }
    func reportIssue(_ message: String) { activity = message; issue = message }
    func sent(word: String, correction: String, method: String) {
        activity = "Replacement sent."; issue = nil
        lastReplacement = "“\(word)” → “\(correction)”"
        lastMethod = method
    }
}

/// Recovered from GlassToKey's word/context and alternate-key correction logic.
/// Pure state: only committed keyboard output enters here, never raw contacts.
struct AutocorrectSession {
    struct Candidate: Equatable, Sendable {
        let word: String
        let alternatives: [UInt8]
        let context: String
        let range: NSRange
        let boundary: UInt8

        func acceptsAlternative(_ guess: String) -> Bool {
            let original = Array(word.utf8), proposed = Array(guess.utf8)
            guard proposed.count == original.count, alternatives.count == original.count,
                  proposed != original, alternatives.contains(where: { $0 != 0 }) else { return false }
            return proposed.indices.allSatisfy {
                proposed[$0] == original[$0] || (alternatives[$0] != 0 && proposed[$0] == alternatives[$0])
            }
        }
    }

    private var word: [UInt8] = []
    private var alternatives: [UInt8] = []
    private var context: [UInt8] = []
    private var overflowed = false
    var isStartingWord: Bool { word.isEmpty && !overflowed }

    init() {
        word.reserveCapacity(64); alternatives.reserveCapacity(64); context.reserveCapacity(1024)
    }

    mutating func reset() {
        word.removeAll(keepingCapacity: true)
        alternatives.removeAll(keepingCapacity: true)
        context.removeAll(keepingCapacity: true)
        overflowed = false
    }

    mutating func consume(_ event: KeySemanticEvent) -> Candidate? {
        switch event.kind {
        case .text:
            guard !overflowed else { return nil }
            guard word.count < 64 else { reset(); overflowed = true; return nil }
            word.append(event.ascii); alternatives.append(event.altAscii)
            appendContext(event.ascii)
        case .backspace:
            // Once a word boundary is erased we no longer know the whole word.
            guard !overflowed, !word.isEmpty else { reset(); overflowed = true; return nil }
            word.removeLast(); alternatives.removeLast()
            if !context.isEmpty { context.removeLast() }
        case .boundary:
            defer {
                word.removeAll(keepingCapacity: true); alternatives.removeAll(keepingCapacity: true)
                overflowed = false
                appendContext(event.ascii)
            }
            guard !overflowed, Self.shouldConsider(word, alternatives: alternatives),
                  let text = String(bytes: word, encoding: .ascii),
                  let surrounding = String(bytes: context, encoding: .ascii) else { return nil }
            return Candidate(word: text, alternatives: alternatives, context: surrounding,
                             range: NSRange(location: context.count - word.count, length: word.count),
                             boundary: event.ascii)
        case .navigation, .nonText:
            reset()
        }
        return nil
    }

    private mutating func appendContext(_ byte: UInt8) {
        if context.count == 1024 { context.removeFirst() }
        context.append(byte)
    }

    private static func shouldConsider(_ bytes: [UInt8], alternatives: [UInt8]) -> Bool {
        guard bytes.count >= 2 else { return false }
        // Preserve GlassToKey's short-word/identifier/all-caps exclusions.
        if bytes.count == 2 && !alternatives.contains(where: { $0 != 0 }) { return false }
        guard bytes.contains(where: { (97...122).contains($0) }),
              !bytes.contains(where: { (48...57).contains($0) || $0 == 95 }) else { return false }
        return true
    }
}

/// Bounded publication and cancellation gate, shared by the live worker and tests.
struct AutocorrectInputBuffer {
    struct Entry { let event: KeySemanticEvent; let generation: UInt64 }
    private(set) var enabled = false
    private(set) var generation: UInt64 = 0
    private var entries: [Entry?]
    private var head = 0
    private(set) var count = 0
    private var resetPending = true

    init(capacity: Int = 2048) { entries = [Entry?](repeating: nil, count: max(1, capacity)) }
    mutating func setEnabled(_ enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled; clear()
    }
    mutating func clear() {
        while count > 0 {
            entries[head] = nil; head = (head + 1) % entries.count; count -= 1
        }
        resetPending = true; generation &+= 1
    }
    mutating func enqueue(_ event: KeySemanticEvent) {
        guard enabled else { return }
        if count == entries.count { clear() }
        generation &+= 1
        entries[(head + count) % entries.count] = Entry(event: event, generation: generation)
        count += 1
    }
    mutating func pop() -> (reset: Bool, entry: Entry?) {
        let reset = resetPending; resetPending = false
        guard count > 0 else { return (reset, nil) }
        let entry = entries[head]
        entries[head] = nil; head = (head + 1) % entries.count; count -= 1
        return (reset, entry)
    }
    func isCurrent(_ generation: UInt64) -> Bool { enabled && self.generation == generation }
}

/// Spellchecking runs on a worker. Accessibility calls run asynchronously on
/// the main thread: AX can enter this app's own NSTextView directly.
final class AutocorrectEngine: @unchecked Sendable {
    static let shared = AutocorrectEngine()
    private let state = OSAllocatedUnfairLock(initialState: AutocorrectInputBuffer())
    private let queue = DispatchQueue(label: "ink.ranna.applemagictouchstream.autocorrect", qos: .utility)
    private let wake: DispatchSourceUserDataAdd
    private var session = AutocorrectSession()
    private struct Target: @unchecked Sendable {
        let pid: pid_t
        let element: AXUIElement?
    }
    private static let log = Logger(subsystem: "ink.ranna.applemagictouchstream", category: "Autocorrect")
    @MainActor private var activationMonitor: NSObjectProtocol?
    @MainActor private var target: Target?
    private var checker: NSSpellChecker?
    private var documentTag: Int?

    private init() {
        wake = DispatchSource.makeUserDataAddSource(queue: queue)
        wake.setEventHandler { [weak self] in self?.drain() }
        wake.resume()
    }

    func setEnabled(_ enabled: Bool) {
        state.withLock { $0.setEnabled(enabled) }
        wake.add(data: 1)
        AutocorrectTextAccess.enqueue { self.updateFocusObserver(enabled: enabled) }
    }

    @MainActor private func updateFocusObserver(enabled: Bool) {
        if !enabled {
            if let activationMonitor { NSWorkspace.shared.notificationCenter.removeObserver(activationMonitor) }
            activationMonitor = nil
            return
        }
        guard activationMonitor == nil else { return }
        // Track focus only. Do not listen to physical keyboard/mouse input.
        activationMonitor = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.invalidate() }
    }

    @MainActor private static func captureTarget() -> Target? {
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled(),
              let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              pid != 0 else { return nil }
        let element = VerifiedAutocorrectReplacement.focusedElement()
        guard !VerifiedAutocorrectReplacement.isSecure(element) else { return nil }
        return Target(pid: pid, element: element)
    }

    @MainActor private static func matches(_ target: Target) -> Bool {
        guard let current = captureTarget(), current.pid == target.pid else { return false }
        switch (target.element, current.element) {
        case let (a?, b?): return CFEqual(a, b)
        case (nil, nil): return true
        default: return false
        }
    }

    func invalidate() {
        let enabled = state.withLock { value in
            guard value.enabled else { return false }
            value.clear(); return true
        }
        if enabled { wake.add(data: 1) }
    }

    func recordDispatchedKey(code: CGKeyCode, flags: CGEventFlags, keyDown: Bool, altAscii: UInt8 = 0) {
        guard keyDown else { return }
        let queued = state.withLock { value in
            guard value.enabled else { return false }
            // Unknown keys also invalidate context (function keys, input-mode switches, etc.).
            let event = KeySemanticMapper.semanticEvent(code: code, flags: flags,
                timestampNs: DispatchTime.now().uptimeNanoseconds, altAscii: altAscii) ?? .empty
            value.enqueue(event)
            return true
        }
        if queued { wake.add(data: 1) }
    }

    private func isCurrent(_ generation: UInt64) -> Bool {
        state.withLock { $0.isCurrent(generation) }
    }

    private func drain() {
        while true {
            let next = state.withLock { $0.pop() }
            if next.0 {
                session.reset()
                AutocorrectTextAccess.enqueue { self.target = nil }
            }
            guard let entry = next.1 else { return }
            autoreleasepool {
                if entry.event.kind == .text && session.isStartingWord {
                    AutocorrectTextAccess.enqueue {
                        self.target = Self.captureTarget()
                    }
                }
                if let candidate = session.consume(entry.event), isCurrent(entry.generation) {
                    let correction = correction(for: candidate)
                    AutocorrectTextAccess.enqueue {
                        guard self.isCurrent(entry.generation) else {
                            AutocorrectStatus.shared.report("Skipped: newer AMT input arrived."); return
                        }
                        guard let target = self.target else {
                            AutocorrectStatus.shared.report("Skipped: no eligible focused field (permission or secure input)."); return
                        }
                        guard let correction else {
                            AutocorrectStatus.shared.report("No spelling correction suggested."); return
                        }
                        self.apply(candidate, correction: correction, target: target, generation: entry.generation)
                    }
                }
                if entry.event.kind == .boundary || entry.event.kind == .navigation || entry.event.kind == .nonText {
                    AutocorrectTextAccess.enqueue { self.target = nil }
                }
            }
        }
    }

    @MainActor private func apply(_ candidate: AutocorrectSession.Candidate, correction: String, target: Target,
                       generation: UInt64, attempt: Int = 0) {
        guard isCurrent(generation) else {
            AutocorrectStatus.shared.report("Skipped: newer AMT input arrived."); return
        }
        guard Self.matches(target) else {
            AutocorrectStatus.shared.report("Skipped: focused app or field changed."); return
        }
        let plan = AutocorrectKeyboardReplacement(word: candidate.word, boundary: candidate.boundary,
                                                  correction: correction)
        let result = target.element.map {
            VerifiedAutocorrectReplacement.replace(candidate, with: correction, in: $0,
                validateOnly: plan != nil, isCurrent: { self.isCurrent(generation) })
        } ?? .unavailable("AX focused field unavailable.")
        switch result {
        case .verified, .unavailable:
            guard let plan else {
                AutocorrectStatus.shared.report("Skipped: keyboard fallback cannot erase Return or Tab."); return
            }
            let method: String
            if case let .unavailable(reason) = result { method = "Keyboard fallback · " + reason }
            else { method = "Keyboard · AX verified" }
            Self.log.debug("Scheduling keyboard replacement")
            AutocorrectStatus.shared.report("Sending replacement via \(method).")
            DispatchService.shared.performAutocorrectReplacement(plan, pid: target.pid,
                isCurrent: { [weak self] in self?.isCurrent(generation) == true },
                completion: { outcome in
                    AutocorrectTextAccess.enqueue {
                        switch outcome {
                        case .posted:
                            AutocorrectStatus.shared.sent(word: candidate.word, correction: correction, method: method)
                        case let .skipped(reason): AutocorrectStatus.shared.report("Skipped: " + reason)
                        case let .failed(reason): AutocorrectStatus.shared.reportIssue(reason)
                        }
                    }
                })
        case .applied:
            AutocorrectStatus.shared.sent(word: candidate.word, correction: correction, method: "Accessibility")
        case let .rejected(reason):
            Self.log.debug("Correction validation failed")
            AutocorrectStatus.shared.reportIssue("Skipped: " + reason)
        case .notReady:
            // AX may lag event delivery; a persistent mismatch must never authorize
            // backspacing. Report it rather than silently dropping the candidate.
            if attempt < 3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(15)) { [weak self] in
                    self?.apply(candidate, correction: correction, target: target, generation: generation, attempt: attempt + 1)
                }
            } else {
                AutocorrectStatus.shared.reportIssue("Skipped: AX text does not match “\(candidate.word)” plus its delimiter at the caret.")
            }
        }
    }

    private func correction(for candidate: AutocorrectSession.Candidate) -> String? {
        if checker == nil { checker = NSSpellChecker.shared; documentTag = NSSpellChecker.uniqueSpellDocumentTag() }
        guard let checker, let tag = documentTag else { return nil }
        let language = checker.language(forWordRange: candidate.range, in: candidate.context, orthography: nil) ?? "en_US"
        if let replacement = checker.correction(forWordRange: candidate.range, in: candidate.context,
            language: language, inSpellDocumentWithTag: tag), replacement != candidate.word,
            KeySemanticMapper.canTypeASCII(replacement), !replacement.isEmpty { return replacement }
        // Retain nearest-key ambiguity hints from the original implementation.
        guard candidate.alternatives.contains(where: { $0 != 0 }) else { return nil }
        return checker.guesses(forWordRange: candidate.range, in: candidate.context, language: language,
            inSpellDocumentWithTag: tag)?.first { candidate.acceptsAlternative($0) && KeySemanticMapper.canTypeASCII($0) }
    }
}

/// Never delete text speculatively: require the original field, an empty selection,
/// an exact complete word+delimiter immediately before the caret, and current output.
@MainActor enum VerifiedAutocorrectReplacement {
    enum Result { case verified, applied, notReady, unavailable(String), rejected(String) }
    static func focusedElement() -> AXUIElement? {
        guard !IsSecureEventInputEnabled(), AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        _ = AXUIElementSetMessagingTimeout(system, 0.05)
        guard let value = attribute(system, kAXFocusedUIElementAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        _ = AXUIElementSetMessagingTimeout(element, 0.05)
        return element
    }

    static func isSecure(_ element: AXUIElement?) -> Bool {
        guard let element else { return false }
        return attribute(element, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole
    }

    /// Pure range validation used by the AX adapter and offline tests.
    nonisolated static func replacementRange(prefix: String, caret: Int, word: String, boundary: UInt8) -> CFRange? {
        let suffix = word + String(UnicodeScalar(boundary))
        let value = prefix as NSString
        guard caret == value.length, value.hasSuffix(suffix) else { return nil }
        let start = caret - (suffix as NSString).length
        if start > 0 {
            // A truncated buffer must never correct just the tail of a larger word.
            let previous = value.character(at: start - 1)
            guard let scalar = UnicodeScalar(previous),
                  !CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_'" )).contains(scalar) else { return nil }
        }
        return CFRange(location: start, length: (word as NSString).length)
    }

    static func replace(_ candidate: AutocorrectSession.Candidate, with replacement: String,
                        in element: AXUIElement, validateOnly: Bool = false, isCurrent: () -> Bool) -> Result {
        guard isCurrent(), !isSecure(element), let focused = focusedElement(), CFEqual(focused, element) else { return .rejected("Focus changed, secure input, or newer AMT input.") }
        guard let caret = selectedRange(element) else { return .unavailable("AX caret unavailable.") }
        guard caret.length == 0, caret.location >= 0 else { return .rejected("Text is selected or the caret is invalid.") }
        // Query only the nearby prefix, rather than copying a whole document.
        let length = min(caret.location, 128)
        var preceding = CFRange(location: caret.location - length, length: length)
        guard let parameter = AXValueCreate(.cfRange, &preceding) else { return .rejected("AX range could not be created.") }
        var result: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(element,
            kAXStringForRangeParameterizedAttribute as CFString, parameter, &result)
        let prefix: String
        if status == .success, let text = result as? String { prefix = text }
        else if let text = attribute(element, kAXValueAttribute) as? String,
                (text as NSString).length >= caret.location {
            prefix = (text as NSString).substring(with: NSRange(location: preceding.location, length: length))
        } else { return .unavailable("AX text unavailable.") }
        guard var range = replacementRange(prefix: prefix, caret: length, word: candidate.word, boundary: candidate.boundary) else { return .notReady }
        guard isCurrent(), let currentCaret = selectedRange(element),
              currentCaret.location == caret.location, currentCaret.length == 0,
              let currentFocus = focusedElement(), CFEqual(currentFocus, element) else { return .rejected("Caret, focus or AMT input changed during validation.") }
        // Ordinary corrections use keystrokes after validation, without changing
        // AX selection/value. This lets editors receive their normal input events.
        if validateOnly { return .verified }
        // Retain verified AX editing for Return/Tab boundaries, which cannot be
        // safely deleted and replayed in unsupported fields.
        // Discover unsupported setters before touching the selection. Any failure
        // after a selection attempt stays rejected, never a keyboard fallback.
        var writableRange = DarwinBoolean(false), writableText = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &writableRange) == .success,
              AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &writableText) == .success,
              writableRange.boolValue, writableText.boolValue else { return .unavailable("AX text setters unavailable.") }
        range.location += preceding.location
        guard setRange(range, element: element) else { return .rejected("AX could not select the word; no keyboard fallback attempted.") }
        // A selection failure or output race must not trigger backspace/retype.
        guard isCurrent(), let selected = selectedRange(element),
              selected.location == range.location, selected.length == range.length,
              attribute(element, kAXSelectedTextAttribute) as? String == candidate.word,
              let editFocus = focusedElement(), CFEqual(editFocus, element), isCurrent() else {
            _ = setRange(caret, element: element); return .rejected("AX selection validation failed; no keyboard fallback attempted.")
        }
        let changed = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, replacement as CFString) == .success
        let finalCaret = changed ? CFRange(location: caret.location + replacement.utf16.count - candidate.word.utf16.count, length: 0) : caret
        _ = setRange(finalCaret, element: element)
        guard changed else { return .rejected("AX text replacement failed; no keyboard fallback attempted.") }
        guard let final = selectedRange(element), final.location == finalCaret.location, final.length == 0,
              let text = attribute(element, kAXValueAttribute) as? String,
              (text as NSString).length >= final.location,
              replacementRange(prefix: (text as NSString).substring(to: final.location), caret: final.location,
                               word: replacement, boundary: candidate.boundary) != nil else {
            return .rejected("AX reported success but the replacement could not be verified.")
        }
        return .applied
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    private static func selectedRange(_ element: AXUIElement) -> CFRange? {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let ax = value as! AXValue
        guard AXValueGetType(ax) == .cfRange else { return nil }
        var range = CFRange()
        return AXValueGetValue(ax, .cfRange, &range) ? range : nil
    }
    private static func setRange(_ range: CFRange, element: AXUIElement) -> Bool {
        var range = range
        guard let value = AXValueCreate(.cfRange, &range) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }
}

/// The fallback only rewrites a bounded ASCII word plus a non-submitting delimiter.
/// Return/Tab may already have submitted a form or moved focus, so never erase them.
struct AutocorrectKeyboardReplacement: Equatable, Sendable {
    let deleteCount: Int
    let text: String

    init?(word: String, boundary: UInt8, correction: String) {
        guard (2...64).contains(word.utf8.count), word.utf8.allSatisfy({ $0 < 128 }),
              (32...126).contains(boundary), !correction.isEmpty,
              correction.utf16.count <= 128, KeySemanticMapper.canTypeASCII(correction),
              !correction.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        deleteCount = word.utf8.count + 1
        text = correction + String(UnicodeScalar(boundary))
    }

    /// Construct every balanced edge before any deletion can occur. No OS output.
    func events() -> [CGEvent]? {
        var events: [CGEvent] = []
        for _ in 0..<deleteCount {
            guard let pair = KeyboardStrokeOutput.events(code: CGKeyCode(kVK_Delete), flags: [], restoringFlags: []) else { return nil }
            events.append(contentsOf: [pair.down, pair.up])
        }
        guard let strokes = KeySemanticMapper.keyStrokes(for: text) else { return nil }
        for stroke in strokes {
            guard let pair = KeyboardStrokeOutput.events(code: stroke.code, flags: stroke.flags,
                                                         restoringFlags: []) else { return nil }
            events.append(contentsOf: [pair.down, pair.up])
        }
        return events
    }
}

/// An indivisible batch on DispatchService's queue. A stale candidate posts nothing;
/// once begun, finish every balanced edge even if later AMT input is queued.
enum AutocorrectKeyboardOutput {
    enum Outcome: Equatable, Sendable { case posted, skipped(String), failed(String) }
    static let strokeInterval: TimeInterval = 0.002

    static func send(_ events: [CGEvent], isCurrent: () -> Bool, begin: () -> Void,
                     post: (CGEvent) -> Void, pause: (TimeInterval) -> Void) -> Outcome {
        guard isCurrent() else { return .skipped("Newer AMT input arrived.") }
        begin()
        for index in stride(from: 0, to: events.count, by: 2) {
            post(events[index]); post(events[index + 1])
            if index + 2 < events.count { pause(strokeInterval) }
        }
        return .posted
    }
}
