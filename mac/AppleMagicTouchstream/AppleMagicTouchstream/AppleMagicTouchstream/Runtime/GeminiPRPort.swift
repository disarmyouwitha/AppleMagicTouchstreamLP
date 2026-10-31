import AppKit
import SwiftUI
import Darwin
import Foundation
import os

/// Native user-space serial endpoint. Initialization is inert; only live STENO
/// configuration opens a PTY. No HID device/helper, network listener or driver.
final class GeminiPRPort:@unchecked Sendable {
    static let shared = GeminiPRPort()
    struct Snapshot:Sendable {
        var path:String?
        var connected:Bool
        var sent:UInt64
        var dropped:UInt64
        var lastPacket:String?
        var error:String?
    }
    private struct State {
        var master:Int32 = -1
        var folder:String?
        var path:String?
        var sent:UInt64 = 0
        var dropped:UInt64 = 0
        var lastPacket:String?
        var error:String?
    }
    private let state = OSAllocatedUnfairLock(initialState:State())
    private static func hasReader(_ fd:Int32) -> Bool {
        guard fd >= 0 else { return false }
        var descriptor = pollfd(fd:fd,events:Int16(POLLOUT),revents:0)
        return poll(&descriptor,1,0) >= 0 && descriptor.revents & Int16(POLLHUP|POLLERR|POLLNVAL) == 0
    }
    var snapshot:Snapshot {
        state.withLock { value in .init(path:value.path,connected:Self.hasReader(value.master),sent:value.sent,
            dropped:value.dropped,lastPacket:value.lastPacket,error:value.error) }
    }
    func start() {
        state.withLock { value in
            guard value.master < 0 else { return }
            var master:Int32 = -1, slave:Int32 = -1
            guard openpty(&master,&slave,nil,nil,nil) == 0 else { value.error = "Could not open the GeminiPR port."; return }
            defer { if slave >= 0 { Darwin.close(slave) }; if master >= 0 { Darwin.close(master) } }
            var settings = termios()
            guard tcgetattr(slave,&settings) == 0 else { value.error = "Could not configure the GeminiPR port."; return }
            cfmakeraw(&settings)
            cfsetispeed(&settings,speed_t(B9600)); cfsetospeed(&settings,speed_t(B9600))
            guard tcsetattr(slave,TCSANOW,&settings) == 0,
                  fcntl(master,F_SETFL,O_NONBLOCK) == 0, fcntl(master,F_SETFD,FD_CLOEXEC) == 0,
                  let name = ttyname(slave) else { value.error = "Could not configure the GeminiPR port."; return }
            let device = String(cString:name)
            var template = Array((NSTemporaryDirectory()+"amt-geminipr-XXXXXX").utf8CString)
            let folder = template.withUnsafeMutableBufferPointer { buffer -> String? in
                guard let pointer = mkdtemp(buffer.baseAddress) else { return nil }
                return String(cString:pointer)
            }
            guard let folder else { value.error = "Could not create the GeminiPR port path."; return }
            let path = folder+"/GeminiPR"
            guard symlink(device,path) == 0 else {
                rmdir(folder); value.error = "Could not create the GeminiPR port path."; return
            }
            value.master = master; master = -1
            value.folder = folder; value.path = path; value.error = nil
        }
    }
    func stop() {
        state.withLock { Self.close(&$0); $0.error = nil }
    }
    func flush() {
        state.withLock { value in if value.master >= 0 { _ = tcflush(value.master,TCIOFLUSH) } }
    }
    @discardableResult func send(_ mask:UInt64) -> Bool {
        guard mask != 0, mask & ~GeminiPRPacket.keyMask == 0 else { return false }
        let bytes = GeminiPRPacket.bytes(for:mask)
        return state.withLock { value in
            guard Self.hasReader(value.master) else { value.dropped &+= 1; return false }
            let count = bytes.withUnsafeBytes { Darwin.write(value.master,$0.baseAddress,bytes.count) }
            if count == bytes.count {
                value.sent &+= 1; value.lastPacket = GeminiPRPacket.recordingLabel(for:mask); return true
            }
            value.dropped &+= 1
            // No reader/full buffer drops a whole stroke without buffering for a
            // later connection. A partial packet closes the stream, never splices
            // another stroke onto an incomplete packet.
            if count > 0 {
                Self.close(&value)
                value.error = "Serial output was interrupted. Switch out of STENO and back, then reconnect Plover."
            }
            return false
        }
    }
    private static func close(_ value:inout State) {
        if value.master >= 0 { Darwin.close(value.master); value.master = -1 }
        if let path = value.path { unlink(path) }
        if let folder = value.folder { rmdir(folder) }
        value.path = nil; value.folder = nil
    }
    deinit { stop() }
}

/// Visible only for a STENO preset. Snapshot polling does not open a port.
struct StenoConnectionPanel:View {
    @Binding var pointerMode:StenoPointerMode
    var body:some View {
        TimelineView(.periodic(from:.now,by:1)) { _ in
            let status = GeminiPRPort.shared.snapshot
            VStack(alignment:.leading,spacing:8) {
                HStack {
                    Text("Mouse")
                    Picker("Mouse",selection:$pointerMode) {
                        ForEach(StenoPointerMode.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(maxWidth:.infinity)
                }
                Text(pointerMode == .disabled ? "Mouse is off; all contacts form chords." : "Move 2 mm to claim the mouse. Two-pad chords keep steno priority. Lift all fingers before switching between mouse and steno.")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                if pointerMode == .oneFingerForce {
                    Text("Press firmly with one finger for a click. A force-click discards the pending stroke.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text("Gemini PR → Plover").font(.callout.weight(.semibold))
                Text(status.error ?? (status.path == nil ? "Preparing serial port…" : status.connected ? "Serial reader connected" : "Waiting for Plover"))
                    .font(.caption).foregroundStyle(status.error == nil ? Color.secondary:Color.red)
                if let path = status.path {
                    Text(path).font(.caption.monospaced()).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                    Button("Copy Port") {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(path,forType:.string)
                    }.buttonStyle(.bordered)
                }
                Text("Plover: Configure → Machine → Gemini PR. Paste the port path into Port; use 9600 baud, 8N1, no flow control. Enable Plover output.")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                Text("Chords send when both hands lift. Other gestures pause in STENO. Mouse requires Trackpad Takeover and Accessibility permission.")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                Text("Sent: \(status.sent) · Dropped without a reader: \(status.dropped)").font(.caption2).foregroundStyle(.secondary)
            }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
                .background(Color.primary.opacity(0.05),in:RoundedRectangle(cornerRadius:12))
        }
    }
}
