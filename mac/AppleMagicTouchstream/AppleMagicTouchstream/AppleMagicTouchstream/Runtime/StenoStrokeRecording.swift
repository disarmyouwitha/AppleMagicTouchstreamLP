import AppKit
import SwiftUI
import JavelinBridge
import os

/// Completed strokes are captured before translation. The UUID is stamped on
/// each queued command, so stopping/cancelling cannot leak delayed chords as text.
final class StenoStrokeRecorder:@unchecked Sendable {
    static let shared = StenoStrokeRecorder()
    enum Event:Sendable,Equatable { case stroke(UInt64), ended }
    private struct State {
        var id:UUID?
        var receive:(@Sendable (Event)->Void)?
        var contactsActive = false
        var ready = true
        var discardID:UUID?
    }
    private let state = OSAllocatedUnfairLock(initialState:State())
    var id:UUID? { state.withLock { $0.id } }
    var routingID:UUID? { state.withLock { value in
        if let id = value.id { return value.ready ? id:value.discardID }
        return value.discardID
    } }
    func observeContacts(active:Bool) {
        state.withLock { value in
            value.contactsActive = active
            if !active { value.ready = true; if value.id == nil { value.discardID = nil } }
        }
    }
    func begin(id:UUID,receive:@escaping @Sendable (Event)->Void) {
        let previous = state.withLock { value in
            let previous = value.receive
            value.id = id; value.receive = receive; value.ready = !value.contactsActive
            value.discardID = UUID()
            return previous
        }
        previous?(.ended)
    }
    @discardableResult func consume(_ mask:UInt64,id:UUID) -> Bool {
        guard mask != 0, mask & ~GeminiPRPacket.keyMask == 0 else { return false }
        let receive = state.withLock { $0.id == id ? $0.receive:nil }
        guard let receive else { return false }; receive(.stroke(mask)); return true
    }
    func cancel(id:UUID? = nil) {
        let callback = state.withLock { value -> (@Sendable (Event)->Void)? in
            guard id == nil || value.id == id else { return nil }
            let receive = value.receive; value.id = nil; value.receive = nil
            if !value.contactsActive { value.discardID = nil }
            return receive
        }
        callback?(.ended)
    }
    func reset() {
        let callback = state.withLock { value in let callback = value.receive; value = State(); return callback }
        callback?(.ended)
    }

}

struct StenoRecordedOutline:Equatable {
    private(set) var strokes:[String] = []
    var text:String { strokes.joined(separator:"/") }
    mutating func append(_ mask:UInt64) -> Bool {
        guard strokes.count < 31, let stroke = Self.format(mask) else { return false }
        strokes.append(stroke); return true
    }
    static func format(_ mask:UInt64) -> String? {
        guard mask != 0, mask & ~GeminiPRPacket.keyMask == 0 else { return nil }
        var output = [CChar](repeating:0,count:128)
        guard AMTJavelinFormatStroke(JavelinTranslator.stroke(mask),&output,output.count) != 0 else { return nil }
        return String(cString:output)
    }
}

@MainActor final class StenoOutlineRecordingModel:ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var outline:String?
    @Published private(set) var error:String?
    private var lease:UUID?
    private var captured = StenoRecordedOutline()
    private var timeout:Task<Void,Never>?
    func start() {
        stop()
        let id = UUID(); lease = id; captured = .init(); outline = nil; error = nil
        let armed = DispatchService.shared.beginStenoStrokeRecording(id:id) { [weak self] event in
            DispatchQueue.main.async { self?.receive(event,id:id) }
        }
        guard armed else { lease = nil; error = "Choose a STENO layout with a built-in connection to record strokes."; return }
        isRecording = true
        timeout = Task { [weak self] in
            try? await Task.sleep(for:.seconds(30))
            guard !Task.isCancelled else { return }; self?.stop()
        }
    }
    func stop() {
        timeout?.cancel(); timeout = nil
        let id = lease; lease = nil; isRecording = false
        if let id { StenoStrokeRecorder.shared.cancel(id:id) }
    }
    private func receive(_ event:StenoStrokeRecorder.Event,id:UUID) {
        guard lease == id else { return }
        switch event {
        case .ended: stop()
        case .stroke(let mask):
            guard captured.append(mask) else { return }
            outline = captured.text
            if captured.strokes.count == 31 { stop() }
        }
    }
}
