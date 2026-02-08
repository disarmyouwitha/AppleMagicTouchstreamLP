import AppKit
import AVFoundation
import Carbon
import Foundation
import os
@preconcurrency import Speech

final class VoiceDictationManager: NSObject, @unchecked Sendable, SFSpeechRecognizerDelegate {
    private final class BoolBox: @unchecked Sendable {
        var value = false
    }

    static let shared = VoiceDictationManager()

    private let queue = DispatchQueue(
        label: "com.kyome.GlassToKey.VoiceDictation",
        qos: .userInitiated
    )
    private let textReplacer = AccessibilityTextReplacer()
    private let logger = Logger(
        subsystem: "com.kyome.GlassToKey",
        category: "VoiceDictation"
    )

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    private var chunkRestartWorkItem: DispatchWorkItem?
    private var isChunkRestartInFlight = false
    private var sessionID: UInt64 = 0
    private var chunkIDCounter: UInt64 = 0
    private var committedTranscript = ""
    private var latestTranscript = ""
    private var isSessionActive = false
    private var statusHandler: (@Sendable (String?) -> Void)?

    func setStatusHandler(_ handler: (@Sendable (String?) -> Void)?) {
        queue.async { [weak self] in
            self?.statusHandler = handler
        }
    }

    func beginSession() {
        queue.async { [weak self] in
            self?.beginSessionLocked()
        }
    }

    func endSession() {
        queue.async { [weak self] in
            self?.endSessionLocked(commitTranscript: true)
        }
    }

    private func beginSessionLocked() {
        guard !isSessionActive else { return }
        chunkRestartWorkItem?.cancel()
        chunkRestartWorkItem = nil
        sessionID &+= 1
        chunkIDCounter = 0
        isChunkRestartInFlight = false
        emitStatus("voice: requesting permission")
        guard ensureAuthorization() else { return }
        guard configureRecognitionLocked() else {
            teardownRecognitionLocked()
            return
        }
        isSessionActive = true
        emitStatus("voice: listening s#\(sessionID)")
    }

    private func ensureAuthorization() -> Bool {
        final class SpeechStatusBox: @unchecked Sendable {
            var value: SFSpeechRecognizerAuthorizationStatus = .notDetermined
        }

        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            break
        case .notDetermined:
            let semaphore = DispatchSemaphore(value: 0)
            let statusBox = SpeechStatusBox()
            SFSpeechRecognizer.requestAuthorization { status in
                statusBox.value = status
                semaphore.signal()
            }
            semaphore.wait()
            guard statusBox.value == .authorized else {
                emitStatus("voice: speech permission denied")
                return false
            }
        case .denied, .restricted:
            emitStatus("voice: speech permission denied")
            return false
        @unknown default:
            emitStatus("voice: speech permission denied")
            return false
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            let semaphore = DispatchSemaphore(value: 0)
            let grantedBox = BoolBox()
            DispatchQueue.main.async {
                AVCaptureDevice.requestAccess(for: .audio) { allowed in
                    grantedBox.value = allowed
                    semaphore.signal()
                }
            }
            semaphore.wait()
            if !grantedBox.value {
                emitStatus("voice: microphone permission denied")
            }
            return grantedBox.value
        case .denied, .restricted:
            emitStatus("voice: microphone permission denied")
            return false
        @unknown default:
            emitStatus("voice: microphone permission denied")
            return false
        }
    }

    private func configureRecognitionLocked() -> Bool {
        teardownRecognitionLocked()
        committedTranscript = ""
        latestTranscript = ""
        recognizer = makeAvailableRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            emitStatus("voice: recognizer unavailable on start")
            return false
        }
        recognizer.delegate = self

        let engine = AVAudioEngine()
        _ = engine.inputNode
        engine.prepare()

        do {
            try engine.start()
        } catch {
            emitStatus("voice: audio start failed (\(describeError(error)))")
            return false
        }

        audioEngine = engine
        guard startRecognitionChunkLocked(recognizer: recognizer) else {
            teardownRecognitionLocked()
            return false
        }
        return true
    }

    private func endSessionLocked(commitTranscript: Bool) {
        guard isSessionActive || recognitionTask != nil || recognitionRequest != nil else { return }
        let transcript = mergedTranscript()
        logger.info("voice: ending session s#\(self.sessionID, privacy: .public) commit=\(commitTranscript, privacy: .public) chars=\(transcript.count, privacy: .public)")
        teardownRecognitionLocked()

        guard commitTranscript else { return }
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            emitStatus("voice: no speech detected")
            return
        }
        if textReplacer.insertTextAtCaret(text) {
            emitStatus("voice: inserted")
            return
        }
        if pasteTextFallback(text) {
            emitStatus("voice: pasted fallback")
            return
        }
        if typeWithMappedKeyStrokesFallback(text) {
            emitStatus("voice: typed mapped fallback")
            return
        }
        if typeWithUnicodeEventsFallback(text) {
            emitStatus("voice: typed unicode fallback")
            return
        }
        emitStatus("voice: insert failed")
    }

    private func teardownRecognitionLocked() {
        chunkRestartWorkItem?.cancel()
        chunkRestartWorkItem = nil
        isChunkRestartInFlight = false
        isSessionActive = false
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        recognizer = nil
    }

    private func startRecognitionChunkLocked(recognizer: SFSpeechRecognizer) -> Bool {
        guard audioEngine.isRunning else {
            emitStatus("voice: audio stopped")
            return false
        }
        chunkIDCounter &+= 1
        let chunkID = chunkIDCounter
        isChunkRestartInFlight = false
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if #available(macOS 13.0, *) {
            request.requiresOnDeviceRecognition = false
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            self?.queue.async { [weak self] in
                guard let self else { return }
                if let transcript, !transcript.isEmpty {
                    self.latestTranscript = transcript
                }
                guard self.isSessionActive else { return }
                if isFinal || error != nil {
                    if let error {
                        self.emitStatus("voice: chunk c#\(chunkID) error (\(self.describeError(error)))")
                    } else {
                        self.emitStatus("voice: chunk c#\(chunkID) final (len=\(transcript?.count ?? 0)); restarting")
                    }
                    self.commitLatestChunkLocked()
                    self.restartRecognitionChunkLocked(reason: "result-final-or-error")
                }
            }
        }
        logger.info("voice: started chunk s#\(self.sessionID, privacy: .public) c#\(chunkID, privacy: .public)")
        return true
    }

    private func restartRecognitionChunkLocked(reason: String) {
        guard !isChunkRestartInFlight else {
            logger.debug("voice: restart already in flight; reason=\(reason, privacy: .public)")
            return
        }
        isChunkRestartInFlight = true
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        logger.info("voice: schedule chunk restart s#\(self.sessionID, privacy: .public) reason=\(reason, privacy: .public)")
        scheduleChunkRestartLocked(after: 0.05, attempt: 1, reason: reason)
    }

    private func scheduleChunkRestartLocked(after delay: TimeInterval, attempt: Int, reason: String) {
        chunkRestartWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isSessionActive else { return }
            let recognizer = self.recognizer ?? self.makeAvailableRecognizer()
            guard let recognizer else {
                self.emitStatus("voice: restart wait (no recognizer) a#\(attempt)")
                self.scheduleChunkRestartLocked(after: 0.25, attempt: attempt + 1, reason: reason)
                return
            }
            self.recognizer = recognizer
            recognizer.delegate = self
            guard recognizer.isAvailable else {
                self.emitStatus("voice: restart wait (recognizer unavailable) a#\(attempt)")
                self.scheduleChunkRestartLocked(after: 0.25, attempt: attempt + 1, reason: reason)
                return
            }
            if !self.startRecognitionChunkLocked(recognizer: recognizer) {
                self.emitStatus("voice: restart failed a#\(attempt); retrying")
                self.scheduleChunkRestartLocked(after: 0.25, attempt: attempt + 1, reason: reason)
            }
        }
        chunkRestartWorkItem = workItem
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func commitLatestChunkLocked() {
        let chunk = latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chunk.isEmpty else { return }
        if committedTranscript.isEmpty {
            committedTranscript = chunk
        } else {
            committedTranscript += " " + chunk
        }
        latestTranscript = ""
    }

    private func mergedTranscript() -> String {
        let latest = latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if committedTranscript.isEmpty {
            return latest
        }
        if latest.isEmpty {
            return committedTranscript
        }
        return committedTranscript + " " + latest
    }

    private func makeAvailableRecognizer() -> SFSpeechRecognizer? {
        let preferredLocales = [
            Locale.current,
            Locale(identifier: "en_US")
        ]
        for locale in preferredLocales {
            if let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable {
                recognizer.delegate = self
                return recognizer
            }
        }
        if let recognizer = SFSpeechRecognizer(), recognizer.isAvailable {
            recognizer.delegate = self
            return recognizer
        }
        emitStatus("voice: recognizer unavailable")
        return nil
    }

    func speechRecognizer(
        _ speechRecognizer: SFSpeechRecognizer,
        availabilityDidChange available: Bool
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            self.logger.info("voice: recognizer availability changed available=\(available, privacy: .public)")
            guard self.isSessionActive, !available else { return }
            self.emitStatus("voice: recognizer became unavailable; retrying")
            self.restartRecognitionChunkLocked(reason: "recognizer-unavailable")
        }
    }

    private func describeError(_ error: Error) -> String {
        let nsError = error as NSError
        var parts: [String] = [
            "domain=\(nsError.domain)",
            "code=\(nsError.code)"
        ]
        if !nsError.localizedDescription.isEmpty {
            parts.append("desc=\(nsError.localizedDescription)")
        }
        if let reason = nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String,
           !reason.isEmpty {
            parts.append("reason=\(reason)")
        }
        return parts.joined(separator: ", ")
    }

    private func typeWithUnicodeEventsFallback(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        KeyEventDispatcher.shared.postText(text)
        return true
    }

    private func typeWithMappedKeyStrokesFallback(_ text: String) -> Bool {
        let normalized = normalizeForMappedKeyTyping(text)
        guard !normalized.isEmpty,
              let strokes = KeySemanticMapper.keyStrokes(for: normalized) else {
            return false
        }
        for stroke in strokes {
            KeyEventDispatcher.shared.postKeyStroke(code: stroke.code, flags: stroke.flags)
        }
        return true
    }

    private func pasteTextFallback(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = BoolBox()

        DispatchQueue.main.async {
            let pasteboard = NSPasteboard.general
            let previous = pasteboard.string(forType: .string)

            pasteboard.clearContents()
            guard pasteboard.setString(text, forType: .string) else {
                resultBox.value = false
                semaphore.signal()
                return
            }

            KeyEventDispatcher.shared.postKeyStroke(
                code: CGKeyCode(kVK_ANSI_V),
                flags: .maskCommand
            )

            if let previous {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    pasteboard.clearContents()
                    _ = pasteboard.setString(previous, forType: .string)
                }
            }

            resultBox.value = true
            semaphore.signal()
        }

        semaphore.wait()
        return resultBox.value
    }

    private func normalizeForMappedKeyTyping(_ text: String) -> String {
        var normalized = text
        normalized = normalized.replacingOccurrences(of: "\u{2018}", with: "'")
        normalized = normalized.replacingOccurrences(of: "\u{2019}", with: "'")
        normalized = normalized.replacingOccurrences(of: "\u{201C}", with: "\"")
        normalized = normalized.replacingOccurrences(of: "\u{201D}", with: "\"")
        normalized = normalized.replacingOccurrences(of: "\u{2013}", with: "-")
        normalized = normalized.replacingOccurrences(of: "\u{2014}", with: "-")
        normalized = normalized.replacingOccurrences(of: "\u{2026}", with: "...")
        normalized = normalized.folding(
            options: [.diacriticInsensitive, .widthInsensitive],
            locale: .current
        )

        var output = ""
        output.reserveCapacity(normalized.count)
        for character in normalized {
            if character == "\n" || character == "\t" {
                output.append(character)
                continue
            }
            guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else {
                continue
            }
            if scalar.value < 128 {
                output.append(character)
                continue
            }
        }
        return output
    }

    private func emitStatus(_ message: String?) {
        if let message {
            logger.log("\(message, privacy: .public)")
        }
        statusHandler?(message)
    }
}
