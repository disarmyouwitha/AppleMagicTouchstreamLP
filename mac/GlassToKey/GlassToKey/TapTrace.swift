//
//  TapTrace.swift
//  GlassToKey
//
//  Debug-only tap lifecycle tracing for low-overhead capture.
//  Usage: run the app, reproduce the issue, click "Dump Tap Trace", then open the JSONL file
//  in ~/Library/Logs/GlassToKey/.
//

import Carbon
import Dispatch
import Foundation
import Darwin

#if DEBUG

struct TapTraceEntry: Sendable {
    var timestampNs: UInt64
    var frame: UInt64
    var touchKey: UInt64
    var type: UInt8
    var keyRow: Int16
    var keyCol: Int16
    var keyCode: Int16
    var char: UInt32
    var auxChar: UInt32
    var aux0: Float
    var aux1: Float
    var aux2: Float
    var aux3: Float
    var reason: UInt8

    init(
        timestampNs: UInt64 = 0,
        frame: UInt64 = 0,
        touchKey: UInt64 = 0,
        type: UInt8 = 0,
        keyRow: Int16 = -1,
        keyCol: Int16 = -1,
        keyCode: Int16 = -1,
        char: UInt32 = 0,
        auxChar: UInt32 = 0,
        aux0: Float = 0,
        aux1: Float = 0,
        aux2: Float = 0,
        aux3: Float = 0,
        reason: UInt8 = 0
    ) {
        self.timestampNs = timestampNs
        self.frame = frame
        self.touchKey = touchKey
        self.type = type
        self.keyRow = keyRow
        self.keyCol = keyCol
        self.keyCode = keyCode
        self.char = char
        self.auxChar = auxChar
        self.aux0 = aux0
        self.aux1 = aux1
        self.aux2 = aux2
        self.aux3 = aux3
        self.reason = reason
    }
}

enum TapTraceEventType: UInt8 {
    case created = 1
    case updated = 2
    case dispatched = 3
    case disqualified = 4
    case finalized = 5
    case expired = 6
    case snapAmbiguity = 7

    var label: String {
        switch self {
        case .created: return "created"
        case .updated: return "updated"
        case .dispatched: return "dispatched"
        case .disqualified: return "disqualified"
        case .finalized: return "finalized"
        case .expired: return "expired"
        case .snapAmbiguity: return "snap_ambiguity"
        }
    }
}

enum TapTraceReasonCode: UInt8 {
    case none = 0
    case timeout = 1
    case collision = 2
    case cancelled = 3
    case disqualifiedMove = 4
    case typingDisabled = 5
    case intentMouse = 6
    case dragCancelled = 7
    case pendingDragCancelled = 8
    case leftContinuousRect = 9
    case forceCapExceeded = 10
    case offKeyNoSnap = 11
    case snapAccepted = 12
    case momentaryLayerCancelled = 13
    case snapAmbiguity = 14

    var label: String {
        switch self {
        case .none: return "none"
        case .timeout: return "timeout"
        case .collision: return "collision"
        case .cancelled: return "cancelled"
        case .disqualifiedMove: return "disqualified_move"
        case .typingDisabled: return "typing_disabled"
        case .intentMouse: return "intent_mouse"
        case .dragCancelled: return "drag_cancelled"
        case .pendingDragCancelled: return "pending_drag_cancelled"
        case .leftContinuousRect: return "left_continuous_rect"
        case .forceCapExceeded: return "force_cap_exceeded"
        case .offKeyNoSnap: return "off_key_no_snap"
        case .snapAccepted: return "snap_accepted"
        case .momentaryLayerCancelled: return "momentary_layer_cancelled"
        case .snapAmbiguity: return "snap_ambiguity"
        }
    }
}

enum TapTrace {
    nonisolated(unsafe) static var isEnabled = true
    static let capacity = 8192
    private static let mask = capacity - 1
    nonisolated(unsafe) private static var writeIndex: Int64 = 0
    nonisolated(unsafe) private static let storage: UnsafeMutableBufferPointer<TapTraceEntry> = {
        precondition(capacity > 0 && (capacity & mask) == 0)
        let pointer = UnsafeMutablePointer<TapTraceEntry>.allocate(capacity: capacity)
        pointer.initialize(repeating: TapTraceEntry(), count: capacity)
        return UnsafeMutableBufferPointer(start: pointer, count: capacity)
    }()

    @inline(__always)
    static func record(
        _ type: TapTraceEventType,
        frame: UInt64,
        touchKey: UInt64,
        keyRow: Int16 = -1,
        keyCol: Int16 = -1,
        keyCode: Int16 = -1,
        char: UInt32 = 0,
        auxChar: UInt32 = 0,
        aux0: Float = 0,
        aux1: Float = 0,
        aux2: Float = 0,
        aux3: Float = 0,
        reason: TapTraceReasonCode = .none
    ) {
        if !isEnabled { return }
        let index = OSAtomicIncrement64Barrier(&writeIndex) - 1
        let slot = Int(index) & mask
        storage[slot] = TapTraceEntry(
            timestampNs: DispatchTime.now().uptimeNanoseconds,
            frame: frame,
            touchKey: touchKey,
            type: type.rawValue,
            keyRow: keyRow,
            keyCol: keyCol,
            keyCode: keyCode,
            char: char,
            auxChar: auxChar,
            aux0: aux0,
            aux1: aux1,
            aux2: aux2,
            aux3: aux3,
            reason: reason.rawValue
        )
    }

    static func snapshot(max: Int) -> [TapTraceEntry] {
        let end = OSAtomicAdd64Barrier(0, &writeIndex)
        let available = min(Int64(capacity), end)
        let count = min(max, Int(available))
        guard count > 0 else { return [] }
        let start = Int(end) - count
        var results: [TapTraceEntry] = []
        results.reserveCapacity(count)
        for offset in 0..<count {
            let slot = (start + offset) & mask
            results.append(storage[slot])
        }
        return results
    }

    static func dumpJSONL(to url: URL, maxEntries: Int = capacity) throws {
        let entries = snapshot(max: maxEntries)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        for entry in entries {
            let typeLabel = TapTraceEventType(rawValue: entry.type)?.label ?? "unknown"
            let reasonLabel = TapTraceReasonCode(rawValue: entry.reason)?.label ?? "unknown"
            let keyCodeValue = entry.keyCode >= 0 ? String(entry.keyCode) : "null"
            let keyNameValue = TapTrace.keyName(for: entry.keyCode)
                .map { "\"\(TapTrace.escapeJSON($0))\"" } ?? "null"
            let keyCell: String
            if entry.keyRow >= 0 && entry.keyCol >= 0 {
                keyCell = "\"\(entry.keyRow),\(entry.keyCol)\""
            } else {
                keyCell = "null"
            }
            let charValue = entry.char > 0 ? String(entry.char) : "null"
            let charStr: String
            if entry.char > 0, let scalar = UnicodeScalar(entry.char) {
                charStr = "\"\(TapTrace.escapeJSON(String(scalar)))\""
            } else {
                charStr = "null"
            }
            let auxCharValue = entry.auxChar > 0 ? String(entry.auxChar) : "null"
            let auxCharStr: String
            if entry.auxChar > 0, let scalar = UnicodeScalar(entry.auxChar) {
                auxCharStr = "\"\(TapTrace.escapeJSON(String(scalar)))\""
            } else {
                auxCharStr = "null"
            }
            let aux0 = entry.aux0 != 0 ? String(format: "%.4f", entry.aux0) : "null"
            let aux1 = entry.aux1 != 0 ? String(format: "%.4f", entry.aux1) : "null"
            let aux2 = entry.aux2 != 0 ? String(format: "%.4f", entry.aux2) : "null"
            let aux3 = entry.aux3 != 0 ? String(format: "%.4f", entry.aux3) : "null"
            let line = "{\"ts_ns\":\(entry.timestampNs),\"frame\":\(entry.frame),\"touchKey\":\(entry.touchKey),\"type\":\"\(typeLabel)\",\"keyCell\":\(keyCell),\"keyCode\":\(keyCodeValue),\"keyName\":\(keyNameValue),\"char\":\(charValue),\"charStr\":\(charStr),\"auxChar\":\(auxCharValue),\"auxCharStr\":\(auxCharStr),\"aux0\":\(aux0),\"aux1\":\(aux1),\"aux2\":\(aux2),\"aux3\":\(aux3),\"reason\":\"\(reasonLabel)\"}\n"
            buffer.append(contentsOf: line.utf8)
            if entry.type == TapTraceEventType.finalized.rawValue {
                buffer.append(contentsOf: "-------\n".utf8)
            }
            if buffer.count >= 64 * 1024 {
                handle.write(buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty {
            handle.write(buffer)
        }
    }

    static func defaultDumpURL() -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let fileName = "tap_trace_\(timestamp).jsonl"
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/GlassToKey", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    private static func escapeJSON(_ value: String) -> String {
        var escaped = value
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        return escaped
    }

    private static func keyName(for keyCode: Int16) -> String? {
        guard keyCode >= 0 else { return nil }
        switch CGKeyCode(keyCode) {
        case CGKeyCode(kVK_ANSI_A): return "A"
        case CGKeyCode(kVK_ANSI_B): return "B"
        case CGKeyCode(kVK_ANSI_C): return "C"
        case CGKeyCode(kVK_ANSI_D): return "D"
        case CGKeyCode(kVK_ANSI_E): return "E"
        case CGKeyCode(kVK_ANSI_F): return "F"
        case CGKeyCode(kVK_ANSI_G): return "G"
        case CGKeyCode(kVK_ANSI_H): return "H"
        case CGKeyCode(kVK_ANSI_I): return "I"
        case CGKeyCode(kVK_ANSI_J): return "J"
        case CGKeyCode(kVK_ANSI_K): return "K"
        case CGKeyCode(kVK_ANSI_L): return "L"
        case CGKeyCode(kVK_ANSI_M): return "M"
        case CGKeyCode(kVK_ANSI_N): return "N"
        case CGKeyCode(kVK_ANSI_O): return "O"
        case CGKeyCode(kVK_ANSI_P): return "P"
        case CGKeyCode(kVK_ANSI_Q): return "Q"
        case CGKeyCode(kVK_ANSI_R): return "R"
        case CGKeyCode(kVK_ANSI_S): return "S"
        case CGKeyCode(kVK_ANSI_T): return "T"
        case CGKeyCode(kVK_ANSI_U): return "U"
        case CGKeyCode(kVK_ANSI_V): return "V"
        case CGKeyCode(kVK_ANSI_W): return "W"
        case CGKeyCode(kVK_ANSI_X): return "X"
        case CGKeyCode(kVK_ANSI_Y): return "Y"
        case CGKeyCode(kVK_ANSI_Z): return "Z"
        case CGKeyCode(kVK_ANSI_0): return "0"
        case CGKeyCode(kVK_ANSI_1): return "1"
        case CGKeyCode(kVK_ANSI_2): return "2"
        case CGKeyCode(kVK_ANSI_3): return "3"
        case CGKeyCode(kVK_ANSI_4): return "4"
        case CGKeyCode(kVK_ANSI_5): return "5"
        case CGKeyCode(kVK_ANSI_6): return "6"
        case CGKeyCode(kVK_ANSI_7): return "7"
        case CGKeyCode(kVK_ANSI_8): return "8"
        case CGKeyCode(kVK_ANSI_9): return "9"
        case CGKeyCode(kVK_Return): return "Return"
        case CGKeyCode(kVK_Tab): return "Tab"
        case CGKeyCode(kVK_Space): return "Space"
        case CGKeyCode(kVK_Delete): return "Delete"
        case CGKeyCode(kVK_Escape): return "Escape"
        case CGKeyCode(kVK_LeftArrow): return "LeftArrow"
        case CGKeyCode(kVK_RightArrow): return "RightArrow"
        case CGKeyCode(kVK_UpArrow): return "UpArrow"
        case CGKeyCode(kVK_DownArrow): return "DownArrow"
        case CGKeyCode(kVK_Shift): return "Shift"
        case CGKeyCode(kVK_RightShift): return "RightShift"
        case CGKeyCode(kVK_Control): return "Control"
        case CGKeyCode(kVK_RightControl): return "RightControl"
        case CGKeyCode(kVK_Option): return "Option"
        case CGKeyCode(kVK_RightOption): return "RightOption"
        case CGKeyCode(kVK_Command): return "Command"
        case CGKeyCode(kVK_RightCommand): return "RightCommand"
        default: return nil
        }
    }
}

#endif
