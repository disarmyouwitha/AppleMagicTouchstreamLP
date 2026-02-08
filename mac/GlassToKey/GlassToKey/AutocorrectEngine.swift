import AppKit
import Carbon
import Dispatch
import Foundation
import Darwin

// Autocorrect enable flow:
// 1) Toggle "Autocorrect" in the app.
// 2) Type a misspelled word followed by space/punctuation/return.
// 3) The engine replaces the last word using AX when available, or backspace-retype as fallback.
//    AX may be unsupported in secure fields or some apps, which triggers the fallback path.
final class AutocorrectEngine: @unchecked Sendable {
    static let shared = AutocorrectEngine()

    private static let capacity = 2048
    private static let mask = capacity - 1
    private static let historyCapacity = 3
    private static let maxContextLeft = 1024
    private static let maxContextRight = 256

    nonisolated(unsafe) private static var enabledFlag: Int32 = 0
    nonisolated(unsafe) private static var suppressionCount: Int64 = 0
    nonisolated(unsafe) private static var minWordLengthFlag: Int32 = 2

    private let queue: DispatchQueue
    private let wakeSource: DispatchSourceUserDataAdd
    private let spellChecker: NSSpellChecker
    private let spellDocumentTag: Int
    private let textReplacer = AccessibilityTextReplacer()

    nonisolated(unsafe) private var writeIndex: Int64 = 0
    private var readIndex: Int64 = 0
    private let storage: UnsafeMutableBufferPointer<KeySemanticEvent>

    private var wordBuffer: [UInt8] = []
    private var autocorrectBuffer: [UInt8] = []
    private var ambiguityBuffer: [UInt8] = []
    private var leftContext = ByteRing(capacity: AutocorrectEngine.maxContextLeft)
    private var rightContext = ByteRing(capacity: AutocorrectEngine.maxContextRight)
    private var historyBuffers: [[UInt8]] = []
    private var historyHead = 0
    private var historyCount = 0
    private let maxWordLength = 64

    private init() {
        precondition(Self.capacity > 0 && (Self.capacity & Self.mask) == 0)
        let pointer = UnsafeMutablePointer<KeySemanticEvent>.allocate(capacity: Self.capacity)
        pointer.initialize(repeating: KeySemanticEvent.empty, count: Self.capacity)
        storage = UnsafeMutableBufferPointer(start: pointer, count: Self.capacity)

        spellChecker = NSSpellChecker.shared
        spellDocumentTag = NSSpellChecker.uniqueSpellDocumentTag()

        queue = DispatchQueue(label: "com.kyome.GlassToKey.Autocorrect", qos: .utility)
        wakeSource = DispatchSource.makeUserDataAddSource(queue: queue)
        wakeSource.setEventHandler { [weak self] in
            self?.drain()
        }
        wakeSource.resume()

        wordBuffer.reserveCapacity(maxWordLength)
        autocorrectBuffer.reserveCapacity(maxWordLength)
        ambiguityBuffer.reserveCapacity(maxWordLength)
        historyBuffers = Array(repeating: [], count: Self.historyCapacity)
        for index in 0..<historyBuffers.count {
            historyBuffers[index].reserveCapacity(maxWordLength)
        }
    }

    func setEnabled(_ enabled: Bool) {
        let value: Int32 = enabled ? 1 : 0
        var current = OSAtomicAdd32Barrier(0, &Self.enabledFlag)
        while !OSAtomicCompareAndSwap32Barrier(current, value, &Self.enabledFlag) {
            current = OSAtomicAdd32Barrier(0, &Self.enabledFlag)
        }
        if !enabled {
            queue.async { [weak self] in
                self?.wordBuffer.removeAll(keepingCapacity: true)
                self?.autocorrectBuffer.removeAll(keepingCapacity: true)
                self?.ambiguityBuffer.removeAll(keepingCapacity: true)
                self?.leftContext.removeAll()
                self?.rightContext.removeAll()
                self?.resetHistory()
            }
        }
    }

    func setMinimumWordLength(_ length: Int) {
        let clamped = max(2, min(length, maxWordLength))
        let value = Int32(clamped)
        var current = OSAtomicAdd32Barrier(0, &Self.minWordLengthFlag)
        while !OSAtomicCompareAndSwap32Barrier(current, value, &Self.minWordLengthFlag) {
            current = OSAtomicAdd32Barrier(0, &Self.minWordLengthFlag)
        }
    }

    func recordDispatchedKey(
        code: CGKeyCode,
        flags: CGEventFlags,
        keyDown: Bool,
        altAscii: UInt8 = 0
    ) {
        guard keyDown else { return }
        guard isEnabled else { return }
        guard !isSuppressed else { return }
        guard let event = KeySemanticMapper.semanticEvent(
            code: code,
            flags: flags,
            timestampNs: DispatchTime.now().uptimeNanoseconds,
            altAscii: altAscii
        ) else {
            return
        }
        enqueue(event)
    }

    private var isEnabled: Bool {
        OSAtomicAdd32Barrier(0, &Self.enabledFlag) != 0
    }

    private var isSuppressed: Bool {
        OSAtomicAdd64Barrier(0, &Self.suppressionCount) > 0
    }

    private var minWordLength: Int {
        Int(OSAtomicAdd32Barrier(0, &Self.minWordLengthFlag))
    }

    private func enqueue(_ event: KeySemanticEvent) {
        let index = OSAtomicIncrement64Barrier(&writeIndex) - 1
        let slot = Int(index) & Self.mask
        storage[slot] = event
        wakeSource.add(data: 1)
    }

    private func drain() {
        let end = OSAtomicAdd64Barrier(0, &writeIndex)
        guard end > readIndex else { return }
        if !isEnabled {
            readIndex = end
            wordBuffer.removeAll(keepingCapacity: true)
            autocorrectBuffer.removeAll(keepingCapacity: true)
            ambiguityBuffer.removeAll(keepingCapacity: true)
            leftContext.removeAll()
            rightContext.removeAll()
            resetHistory()
            return
        }
        let pending = end - readIndex
        if pending > Int64(Self.capacity) {
            readIndex = end - Int64(Self.capacity)
        }
        while readIndex < end {
            let event = storage[Int(readIndex) & Self.mask]
            readIndex += 1
            process(event)
        }
    }

    private func process(_ event: KeySemanticEvent) {
        switch event.kind {
        case .text:
            guard wordBuffer.count < maxWordLength else { return }
            wordBuffer.append(event.ascii)
            if autocorrectBuffer.count < maxWordLength {
                autocorrectBuffer.append(event.ascii)
            }
            if ambiguityBuffer.count < maxWordLength {
                ambiguityBuffer.append(event.altAscii)
            }
            leftContext.append(event.ascii)
        case .backspace:
            _ = leftContext.popLast()
            if !wordBuffer.isEmpty {
                wordBuffer.removeLast()
                if !autocorrectBuffer.isEmpty {
                    autocorrectBuffer.removeLast()
                }
                if !ambiguityBuffer.isEmpty {
                    ambiguityBuffer.removeLast()
                }
            } else {
                _ = resurrectPreviousWord()
                autocorrectBuffer.removeAll(keepingCapacity: true)
                ambiguityBuffer.removeAll(keepingCapacity: true)
            }
        case .boundary:
            if !wordBuffer.isEmpty {
                if autocorrectBuffer.count == wordBuffer.count,
                   let correctedBytes = attemptCorrection(
                    bytes: autocorrectBuffer,
                    ambiguity: ambiguityBuffer,
                    boundaryEvent: event
                   ) {
                    pushHistory(bytes: correctedBytes)
                } else {
                    pushHistoryFromCurrent()
                }
            }
            appendBoundaryByte(for: event)
            wordBuffer.removeAll(keepingCapacity: true)
            autocorrectBuffer.removeAll(keepingCapacity: true)
            ambiguityBuffer.removeAll(keepingCapacity: true)
        case .navigation:
            handleNavigation(event)
            wordBuffer.removeAll(keepingCapacity: true)
            autocorrectBuffer.removeAll(keepingCapacity: true)
            ambiguityBuffer.removeAll(keepingCapacity: true)
            resetHistory()
        case .nonText:
            wordBuffer.removeAll(keepingCapacity: true)
            autocorrectBuffer.removeAll(keepingCapacity: true)
            ambiguityBuffer.removeAll(keepingCapacity: true)
            resetHistory()
            leftContext.removeAll()
            rightContext.removeAll()
        }
    }

    private func attemptCorrection(
        bytes: [UInt8],
        ambiguity: [UInt8],
        boundaryEvent: KeySemanticEvent
    ) -> [UInt8]? {
        guard shouldConsiderWord(bytes) else { return nil }
        let hasAmbiguity = hasAmbiguity(ambiguity)
        if bytes.count == 2, minWordLength <= 2, !hasAmbiguity {
            return nil
        }
        guard let word = String(bytes: bytes, encoding: .ascii) else { return nil }
        let fallbackRange = NSRange(location: 0, length: word.utf16.count)
        let (contextString, wordRange) =
            contextStringForCorrection(currentWordBytes: bytes) ?? (word, fallbackRange)
        let language = spellChecker.language(
            forWordRange: wordRange,
            in: contextString,
            orthography: nil
        ) ?? "en_US"
        if let correction = spellChecker.correction(
            forWordRange: wordRange,
            in: contextString,
            language: language,
            inSpellDocumentWithTag: spellDocumentTag
        ) {
            guard correction != word else { return nil }
            guard KeySemanticMapper.canTypeASCII(correction) else { return nil }

            let correctionBytes = [UInt8](correction.utf8)
            let boundaryLength = boundaryEvent.boundaryLength
            if textReplacer.replaceLastWord(
                wordLength: bytes.count,
                boundaryLength: boundaryLength,
                replacement: correction
            ) {
                return correctionBytes
            }

            fallbackBackspaceRetype(
                originalWordLength: bytes.count,
                boundaryEvent: boundaryEvent,
                replacement: correction
            )
            return correctionBytes
        }

        if let ambiguousCorrection = attemptAmbiguousCorrection(
            bytes: bytes,
            ambiguity: ambiguity,
            hasAmbiguity: hasAmbiguity,
            contextString: contextString,
            wordRange: wordRange,
            language: language
        ) {
            let correction = ambiguousCorrection
            guard let correctionString = String(bytes: correction, encoding: .ascii) else {
                return nil
            }
            let boundaryLength = boundaryEvent.boundaryLength
            if textReplacer.replaceLastWord(
                wordLength: bytes.count,
                boundaryLength: boundaryLength,
                replacement: correctionString
            ) {
                return correction
            }

            fallbackBackspaceRetype(
                originalWordLength: bytes.count,
                boundaryEvent: boundaryEvent,
                replacement: correctionString
            )
            return correction
        }

        return nil
    }

    private func attemptAmbiguousCorrection(
        bytes: [UInt8],
        ambiguity: [UInt8],
        hasAmbiguity: Bool,
        contextString: String,
        wordRange: NSRange,
        language: String
    ) -> [UInt8]? {
        guard bytes.count == ambiguity.count else { return nil }
        guard hasAmbiguity else { return nil }
        guard let guesses = spellChecker.guesses(
            forWordRange: wordRange,
            in: contextString,
            language: language,
            inSpellDocumentWithTag: spellDocumentTag
        ) else {
            return nil
        }
        for guess in guesses {
            guard KeySemanticMapper.canTypeASCII(guess) else { continue }
            let guessBytes = [UInt8](guess.utf8)
            guard guessBytes.count == bytes.count else { continue }
            var matches = true
            for index in 0..<bytes.count {
                let alt = ambiguity[index]
                let original = bytes[index]
                let candidate = guessBytes[index]
                if alt == 0 {
                    if candidate != original {
                        matches = false
                        break
                    }
                } else if candidate != original && candidate != alt {
                    matches = false
                    break
                }
            }
            if matches && guessBytes != bytes {
                return guessBytes
            }
        }
        return nil
    }

    private func appendBoundaryByte(for boundaryEvent: KeySemanticEvent) {
        let ascii = boundaryEvent.ascii
        if ascii != 0 {
            leftContext.append(ascii)
            return
        }
        leftContext.append(UInt8(ascii: " "))
    }

    private func contextStringForCorrection(currentWordBytes: [UInt8]) -> (String, NSRange)? {
        let wordLength = currentWordBytes.count
        guard wordLength > 0 else { return nil }
        var contextBytes: [UInt8] = []
        contextBytes.reserveCapacity(leftContext.count + rightContext.count)
        leftContext.appendInOrder(to: &contextBytes)
        guard contextBytes.count >= wordLength else { return nil }
        let wordStart = contextBytes.count - wordLength
        rightContext.appendInReverseOrder(to: &contextBytes)
        guard let context = String(bytes: contextBytes, encoding: .ascii) else { return nil }
        let wordRange = NSRange(location: wordStart, length: wordLength)
        return (context, wordRange)
    }

    private func handleNavigation(_ event: KeySemanticEvent) {
        switch event.code {
        case CGKeyCode(kVK_LeftArrow):
            if let byte = leftContext.popLast() {
                rightContext.append(byte)
            }
        case CGKeyCode(kVK_RightArrow):
            if let byte = rightContext.popLast() {
                leftContext.append(byte)
            }
        default:
            break
        }
    }

    private func shouldConsiderWord(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= minWordLength else { return false }
        var hasLetter = false
        var allCaps = true
        for byte in bytes {
            if byte >= 65 && byte <= 90 {
                hasLetter = true
                continue
            }
            if byte >= 97 && byte <= 122 {
                hasLetter = true
                allCaps = false
                continue
            }
            if byte >= 48 && byte <= 57 { return false }
            if byte == UInt8(ascii: "_") { return false }
            if byte == UInt8(ascii: "/") { return false }
            if byte == UInt8(ascii: ".") { return false }
            allCaps = false
        }
        guard hasLetter else { return false }
        if allCaps { return false }
        return true
    }

    private func fallbackBackspaceRetype(
        originalWordLength: Int,
        boundaryEvent: KeySemanticEvent,
        replacement: String
    ) {
        guard let strokes = KeySemanticMapper.keyStrokes(for: replacement) else { return }
        let boundaryLength = boundaryEvent.boundaryLength
        let totalDeletes = originalWordLength + boundaryLength

        OSAtomicIncrement64Barrier(&Self.suppressionCount)
        defer { OSAtomicDecrement64Barrier(&Self.suppressionCount) }

        if totalDeletes > 0 {
            for _ in 0..<totalDeletes {
                KeyEventDispatcher.shared.postKeyStroke(code: CGKeyCode(kVK_Delete), flags: [])
            }
        }
        for stroke in strokes {
            KeyEventDispatcher.shared.postKeyStroke(code: stroke.code, flags: stroke.flags)
        }
        if boundaryLength > 0 {
            KeyEventDispatcher.shared.postKeyStroke(code: boundaryEvent.code, flags: boundaryEvent.flags)
        }
    }

    @inline(__always)
    private func resetHistory() {
        historyHead = 0
        historyCount = 0
    }

    @inline(__always)
    private func pushHistoryFromCurrent() {
        guard !wordBuffer.isEmpty else { return }
        let slot = historyHead
        if !historyBuffers.isEmpty {
            swap(&wordBuffer, &historyBuffers[slot])
        }
        historyHead = (historyHead + 1) % Self.historyCapacity
        if historyCount < Self.historyCapacity {
            historyCount += 1
        }
    }

    @inline(__always)
    private func pushHistory(bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        let slot = historyHead
        historyBuffers[slot].removeAll(keepingCapacity: true)
        historyBuffers[slot].append(contentsOf: bytes)
        historyHead = (historyHead + 1) % Self.historyCapacity
        if historyCount < Self.historyCapacity {
            historyCount += 1
        }
    }

    @inline(__always)
    private func resurrectPreviousWord() -> Bool {
        guard historyCount > 0 else { return false }
        let lastIndex = (historyHead - 1 + Self.historyCapacity) % Self.historyCapacity
        if !historyBuffers.isEmpty {
            swap(&wordBuffer, &historyBuffers[lastIndex])
        }
        historyHead = lastIndex
        historyCount -= 1
        return true
    }

    private func hasAmbiguity(_ ambiguity: [UInt8]) -> Bool {
        for alt in ambiguity where alt != 0 {
            return true
        }
        return false
    }

    private struct ByteRing {
        private var buffer: [UInt8]
        private var head = 0
        private(set) var count = 0

        init(capacity: Int) {
            buffer = [UInt8](repeating: 0, count: max(0, capacity))
        }

        mutating func removeAll() {
            head = 0
            count = 0
        }

        mutating func append(_ byte: UInt8) {
            guard !buffer.isEmpty else { return }
            if count < buffer.count {
                buffer[(head + count) % buffer.count] = byte
                count += 1
                return
            }
            buffer[head] = byte
            head = (head + 1) % buffer.count
        }

        mutating func popLast() -> UInt8? {
            guard count > 0 else { return nil }
            let index = (head + count - 1) % buffer.count
            let byte = buffer[index]
            count -= 1
            return byte
        }

        mutating func popFirst() -> UInt8? {
            guard count > 0 else { return nil }
            let byte = buffer[head]
            head = (head + 1) % buffer.count
            count -= 1
            return byte
        }

        func appendInOrder(to array: inout [UInt8]) {
            guard count > 0 else { return }
            for index in 0..<count {
                array.append(buffer[(head + index) % buffer.count])
            }
        }

        func appendInReverseOrder(to array: inout [UInt8]) {
            guard count > 0 else { return }
            var index = count - 1
            while true {
                array.append(buffer[(head + index) % buffer.count])
                if index == 0 { break }
                index -= 1
            }
        }
    }
}
