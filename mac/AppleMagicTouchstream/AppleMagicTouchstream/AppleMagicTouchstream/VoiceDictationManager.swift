import AppKit
import AVFoundation
import Carbon
import Combine
import ApplicationServices
import os
@preconcurrency import Speech

/// Serialize publication with lifecycle cancellation. Already-scheduled toggles
/// cannot start a microphone after takeover/processing has been released.
enum VoiceDictationOutput {
    private static let generation = OSAllocatedUnfairLock(initialState: UInt64(0))
    static func toggle() {
        generation.withLock { token in
            let token = token
            DispatchQueue.main.async {
                guard generation.withLock({ $0 == token }) else { return }
                VoiceDictationManager.shared.toggle()
            }
        }
    }
    static func cancel() {
        generation.withLock { token in
            token &+= 1
            DispatchQueue.main.async { VoiceDictationManager.shared.cancel() }
        }
    }
}

/// Token-gated lifetime, independent of microphones/permissions for offline tests.
struct VoiceDictationSession {
    enum Phase { case idle, authorizing, listening, finishing }
    private(set) var phase = Phase.idle
    private(set) var generation: UInt64 = 0
    private(set) var chunk: UInt64 = 0
    private var committed: [String] = []
    private var latest = ""
    var active: Bool { phase != .idle }
    mutating func begin() -> UInt64 {
        cancel(); phase = .authorizing; return generation
    }
    mutating func authorized(_ token: UInt64) -> Bool {
        guard token == generation, phase == .authorizing else { return false }
        phase = .listening; return true
    }
    mutating func nextChunk() -> UInt64 {
        chunk &+= 1; latest = ""; return chunk
    }
    mutating func receive(_ text: String, token: UInt64, chunk: UInt64) -> Bool {
        guard token == generation, chunk == self.chunk,
              phase == .listening || phase == .finishing else { return false }
        latest = text.trimmingCharacters(in: .whitespacesAndNewlines); return true
    }
    mutating func commitChunk() {
        if !latest.isEmpty { committed.append(latest) }; latest = ""
    }
    mutating func finish() -> UInt64? {
        guard phase == .listening else { return nil }
        phase = .finishing; return generation
    }
    mutating func complete(_ token: UInt64) -> String? {
        guard token == generation, phase == .finishing else { return nil }
        commitChunk(); let text = committed.joined(separator: " "); cancel(); return text
    }
    mutating func cancel() {
        generation &+= 1; phase = .idle; chunk = 0; committed.removeAll(); latest = ""
    }
}

/// Dictation posts Unicode keystrokes, so an AX text implementation is optional.
/// Preserve exact field/window identity when exposed; otherwise retain the app.
struct VoiceDestinationPolicy {
    static func permits(originalPID:pid_t,currentPID:pid_t,secure:Bool,
                        fieldMatches:Bool?,windowMatches:Bool?) -> Bool {
        originalPID > 0 && originalPID == currentPID && !secure
            && fieldMatches != false && windowMatches != false
    }
}

@MainActor struct FocusedTextDestination {
    let pid:pid_t
    let field:AXUIElement?
    let window:AXUIElement?

    static func capture(rejectSecureInput:Bool = true) -> Self? {
        guard (!rejectSecureInput || !IsSecureEventInputEnabled()), AXIsProcessTrusted(),
              let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier, pid > 0 else { return nil }
        let app = AXUIElementCreateApplication(pid)
        // Voice is an explicit, infrequent action on the main actor, independent
        // of the input queue and autocorrect's shorter per-keystroke timeout.
        _ = AXUIElementSetMessagingTimeout(app,0.2)
        func element(_ name:String) -> AXUIElement? {
            var value:CFTypeRef?
            guard AXUIElementCopyAttributeValue(app,name as CFString,&value) == .success,
                  let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            let element = value as! AXUIElement
            _ = AXUIElementSetMessagingTimeout(element,0.2)
            return element
        }
        let field = element(kAXFocusedUIElementAttribute)
        if let field {
            var subrole:CFTypeRef?
            _ = AXUIElementCopyAttributeValue(field,kAXSubroleAttribute as CFString,&subrole)
            guard !rejectSecureInput || subrole as? String != kAXSecureTextFieldSubrole else { return nil }
        }
        return Self(pid:pid,field:field,window:element(kAXFocusedWindowAttribute))
    }

    func matches(_ current:Self,rejectSecureInput:Bool = true) -> Bool {
        VoiceDestinationPolicy.permits(originalPID:pid,currentPID:current.pid,secure:rejectSecureInput && IsSecureEventInputEnabled(),
            fieldMatches:field.map { original in current.field.map { CFEqual(original,$0) } ?? false },
            windowMatches:window.map { original in current.window.map { CFEqual(original,$0) } ?? false })
    }
}

/// Restores GlassToKey's Voice action: trigger once to listen, again to insert.
/// No microphone, permission request or recognizer is created until user action.
@MainActor final class VoiceDictationManager: ObservableObject {
    static let shared = VoiceDictationManager()
    @Published private(set) var status = "Voice: ready"
    @Published private(set) var isActive = false
    private var session = VoiceDictationSession()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var engine: AVAudioEngine?
    private var tapInstalled = false
    private var destination: FocusedTextDestination?
    private var restartAttempts = 0

    func toggle() {
        switch session.phase {
        case .authorizing: cancel()
        case .listening: finish()
        case .finishing: break
        case .idle:
            let token = session.begin()
            isActive = true; status = "Voice: requesting permission"
            Task { await authorizeAndBegin(token) }
        }
    }

    func cancel() {
        session.cancel(); teardown(); destination = nil
        isActive = false; status = "Voice: ready"
    }

    private func authorizeAndBegin(_ token: UInt64) async {
        let speech: SFSpeechRecognizerAuthorizationStatus
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            speech = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { @Sendable status in continuation.resume(returning: status) }
            }
        } else { speech = SFSpeechRecognizer.authorizationStatus() }
        guard token == session.generation, session.phase == .authorizing else { return }
        guard speech == .authorized else { fail("Voice: enable Speech Recognition in Privacy & Security"); return }
        let microphone: Bool
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            microphone = await AVCaptureDevice.requestAccess(for: .audio)
        } else { microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
        guard token == session.generation, session.phase == .authorizing else { return }
        guard microphone else { fail("Voice: enable Microphone in Privacy & Security"); return }
        guard let focused = FocusedTextDestination.capture() else {
            fail("Voice: focus a non-secure destination app first"); return
        }
        destination = focused
        recognizer = [Locale.current, Locale(identifier: "en_US")].compactMap { SFSpeechRecognizer(locale: $0) }.first { $0.isAvailable }
        guard let recognizer else { fail("Voice: speech recognition is unavailable"); return }
        guard session.authorized(token) else { return }
        restartAttempts = 0
        do {
            let engine = AVAudioEngine()
            self.engine = engine
            let format = engine.inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { fail("Voice: microphone has no audio input"); return }
            startChunk(recognizer, token: token)
            engine.prepare(); try engine.start()
            status = "Voice: listening — trigger Voice again to insert"
        } catch { fail("Voice: microphone could not start") }
    }

    private func startChunk(_ recognizer: SFSpeechRecognizer, token: UInt64) {
        guard let engine, session.phase == .listening, token == session.generation else { return }
        let chunk = session.nextChunk()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true; request.taskHint = .dictation
        // Preserve compatibility with the old Voice action. Apple's service may
        // process audio remotely when on-device recognition isn't available.
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        let format = engine.inputNode.outputFormat(forBus: 0)
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable [weak request] buffer, _ in
            request?.append(buffer)
        }
        tapInstalled = true
        task = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor [weak self] in
                guard let self, token == self.session.generation, chunk == self.session.chunk else { return }
                if let text { _ = self.session.receive(text, token: token, chunk: chunk) }
                if self.session.phase == .finishing {
                    if final || failed { self.complete(token) }
                } else if self.session.phase == .listening && (final || failed) {
                    self.session.commitChunk()
                    self.task?.cancel(); self.task = nil; self.request?.endAudio(); self.request = nil
                    // Reject callbacks from the cancelled chunk immediately.
                    _ = self.session.nextChunk()
                    self.restartAttempts = failed ? self.restartAttempts + 1 : 0
                    guard self.restartAttempts <= 3 else { self.fail("Voice: speech recognition stopped; try again"); return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
                        guard let self, self.session.generation == token, self.session.phase == .listening else { return }
                        guard let recognizer = self.recognizer, recognizer.isAvailable else {
                            self.fail("Voice: speech recognition became unavailable"); return
                        }
                        self.startChunk(recognizer, token: token)
                    }
                }
            }
        }
    }

    private func finish() {
        guard let token = session.finish() else { return }
        status = "Voice: finishing"
        stopAudio(); request?.endAudio(); task?.finish()
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(600)) { [weak self] in self?.complete(token) }
    }

    private func complete(_ token: UInt64) {
        guard let text = session.complete(token) else { return }
        teardown(); isActive = false
        defer { destination = nil }
        guard !text.isEmpty else { status = "Voice: no speech detected"; return }
        guard let destination, let focused = FocusedTextDestination.capture(), destination.matches(focused) else {
            status = "Voice: focus changed; transcript discarded"; return
        }
        AutocorrectEngine.shared.invalidate()
        KeyEventDispatcher.shared.postText(text)
        status = "Voice: inserted"
    }

    private func stopAudio() {
        engine?.stop()
        if tapInstalled { engine?.inputNode.removeTap(onBus: 0); tapInstalled = false }
    }
    private func teardown() {
        stopAudio(); request?.endAudio(); task?.cancel()
        task = nil; request = nil; recognizer = nil; engine = nil
    }
    private func fail(_ message: String) {
        cancel(); status = message
    }
}
