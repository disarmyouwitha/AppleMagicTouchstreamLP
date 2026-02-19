import Darwin
import Foundation
@preconcurrency import OpenMultitouchSupportXCF

public enum ATPCaptureWriterError: Error {
    case openFailed(path: String, code: Int32)
    case writeFailed(code: Int32)
    case invalidPayloadLength(Int)
}

extension ATPCaptureWriterError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .openFailed(path, code):
            return "Failed to open capture '\(path)': \(Self.message(for: code))"
        case let .writeFailed(code):
            return "Failed to write capture: \(Self.message(for: code))"
        case let .invalidPayloadLength(length):
            return "Invalid capture payload length: \(length)"
        }
    }

    private static func message(for code: Int32) -> String {
        guard let ptr = strerror(code) else {
            return "errno \(code)"
        }
        return String(cString: ptr)
    }
}

public final class ATPCaptureWriter {
    private static let headerSize = 20
    private static let recordHeaderSize = 34
    private static let version: Int32 = 2
    private static let maxPayloadLength = 64 * 1024
    private static let magic: [UInt8] = Array("ATPCAP01".utf8)
    private static let legacyReportId: UInt8 = 0x05
    private static let legacyMaxContacts = 5
    private static let legacyPayloadSize = 50
    private static let replayMaxX: UInt16 = 7612
    private static let replayMaxY: UInt16 = 5065

    private var fileDescriptor: Int32
    private var scanTime: UInt16 = 0
    private var closed = false

    public let outputPath: String
    public let qpcFrequency: Int64

    public init(path: String, qpcFrequency: Int64 = 1_000_000_000) throws {
        let fullPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let directory = URL(fileURLWithPath: fullPath).deletingLastPathComponent().path
        if !directory.isEmpty {
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true
            )
        }

        let flags = O_WRONLY | O_CREAT | O_TRUNC
        let mode: mode_t = S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH
        let fd = fullPath.withCString { pointer in
            Darwin.open(pointer, flags, mode)
        }
        guard fd >= 0 else {
            throw ATPCaptureWriterError.openFailed(path: fullPath, code: errno)
        }

        self.outputPath = fullPath
        self.qpcFrequency = max(Int64(1), qpcFrequency)
        fileDescriptor = fd
        do {
            try writeHeader()
        } catch {
            close()
            throw error
        }
    }

    deinit {
        close()
    }

    public func close() {
        guard !closed else { return }
        closed = true
        if fileDescriptor >= 0 {
            Darwin.close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    public func writeSyntheticLegacyFrame(
        _ frame: OMSRawTouchFrame,
        arrivalQpcTicks: Int64,
        sideHint: ATPCaptureSideHint = .unknown
    ) throws {
        let payload = Self.makeLegacyPayload(from: frame.touches, scanTime: scanTime)
        scanTime &+= 1
        try writeRecord(
            payload: payload,
            arrivalQpcTicks: arrivalQpcTicks,
            deviceIndex: Int32(clamping: frame.deviceIndex),
            deviceHash: frame.deviceHash,
            vendorId: frame.vendorId,
            productId: frame.productId,
            usagePage: frame.usagePage,
            usage: frame.usage,
            sideHint: sideHint,
            decoderProfile: .legacy
        )
    }

    public func writeRecord(
        payload: [UInt8],
        arrivalQpcTicks: Int64,
        deviceIndex: Int32,
        deviceHash: UInt32,
        vendorId: UInt32,
        productId: UInt32,
        usagePage: UInt16,
        usage: UInt16,
        sideHint: ATPCaptureSideHint = .unknown,
        decoderProfile: ATPCaptureDecoderProfile = .official
    ) throws {
        guard payload.count <= Self.maxPayloadLength else {
            throw ATPCaptureWriterError.invalidPayloadLength(payload.count)
        }
        guard !closed else {
            throw ATPCaptureWriterError.writeFailed(code: EBADF)
        }

        var header = [UInt8](repeating: 0, count: Self.recordHeaderSize)
        writeInt32LE(&header, offset: 0, Int32(payload.count))
        writeInt64LE(&header, offset: 4, arrivalQpcTicks)
        writeInt32LE(&header, offset: 12, deviceIndex)
        writeUInt32LE(&header, offset: 16, deviceHash)
        writeUInt32LE(&header, offset: 20, vendorId)
        writeUInt32LE(&header, offset: 24, productId)
        writeUInt16LE(&header, offset: 28, usagePage)
        writeUInt16LE(&header, offset: 30, usage)
        header[32] = sideHint.rawValue
        header[33] = decoderProfile == .legacy ? ATPCaptureDecoderProfile.legacy.rawValue : ATPCaptureDecoderProfile.official.rawValue

        try writeAll(header)
        if !payload.isEmpty {
            try writeAll(payload)
        }
    }

    private func writeHeader() throws {
        var header = [UInt8](repeating: 0, count: Self.headerSize)
        for index in 0..<Self.magic.count {
            header[index] = Self.magic[index]
        }
        writeInt32LE(&header, offset: 8, Self.version)
        writeInt64LE(&header, offset: 12, qpcFrequency)
        try writeAll(header)
    }

    private func writeAll(_ bytes: [UInt8]) throws {
        try bytes.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var written = 0
            let total = rawBuffer.count
            while written < total {
                let result = Darwin.write(fileDescriptor, base.advanced(by: written), total - written)
                if result > 0 {
                    written += result
                    continue
                }
                if result == 0 {
                    throw ATPCaptureWriterError.writeFailed(code: EIO)
                }
                if errno == EINTR {
                    continue
                }
                throw ATPCaptureWriterError.writeFailed(code: errno)
            }
        }
    }

    private static func makeLegacyPayload(from touches: [OMSRawTouch], scanTime: UInt16) -> [UInt8] {
        var payload = [UInt8](repeating: 0, count: legacyPayloadSize)
        payload[0] = legacyReportId

        var contacts = touches.filter { isTipActiveState($0.state) }
        contacts.sort { $0.id < $1.id }
        if contacts.count > legacyMaxContacts {
            contacts.removeLast(contacts.count - legacyMaxContacts)
        }

        let count = contacts.count
        for index in 0..<count {
            let contact = contacts[index]
            let base = 1 + (index * 9)
            payload[base] = 0x03
            writeUInt32LE(&payload, offset: base + 1, UInt32(bitPattern: contact.id))
            writeUInt16LE(&payload, offset: base + 5, scaleCoordinate(contact.posX, maxRaw: replayMaxX))
            writeUInt16LE(&payload, offset: base + 7, scaleCoordinate(contact.posY, maxRaw: replayMaxY))
        }

        writeUInt16LE(&payload, offset: 46, scanTime)
        payload[48] = UInt8(count)
        payload[49] = 0
        return payload
    }

    private static func isTipActiveState(_ state: OpenMTState) -> Bool {
        switch state {
        case .starting, .making, .touching, .breaking, .lingering:
            return true
        case .notTouching, .hovering, .leaving:
            return false
        @unknown default:
            return false
        }
    }

    private static func scaleCoordinate(_ position: Float, maxRaw: UInt16) -> UInt16 {
        let clamped = min(max(Double(position), 0), 1)
        let scaled = (clamped * Double(maxRaw)).rounded()
        return UInt16(min(max(scaled, 0), Double(maxRaw)))
    }
}

private func writeUInt16LE(_ buffer: inout [UInt8], offset: Int, _ value: UInt16) {
    buffer[offset] = UInt8(truncatingIfNeeded: value)
    buffer[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
}

private func writeUInt32LE(_ buffer: inout [UInt8], offset: Int, _ value: UInt32) {
    buffer[offset] = UInt8(truncatingIfNeeded: value)
    buffer[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
    buffer[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
    buffer[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
}

private func writeInt32LE(_ buffer: inout [UInt8], offset: Int, _ value: Int32) {
    writeUInt32LE(&buffer, offset: offset, UInt32(bitPattern: value))
}

private func writeInt64LE(_ buffer: inout [UInt8], offset: Int, _ value: Int64) {
    let bits = UInt64(bitPattern: value)
    buffer[offset] = UInt8(truncatingIfNeeded: bits)
    buffer[offset + 1] = UInt8(truncatingIfNeeded: bits >> 8)
    buffer[offset + 2] = UInt8(truncatingIfNeeded: bits >> 16)
    buffer[offset + 3] = UInt8(truncatingIfNeeded: bits >> 24)
    buffer[offset + 4] = UInt8(truncatingIfNeeded: bits >> 32)
    buffer[offset + 5] = UInt8(truncatingIfNeeded: bits >> 40)
    buffer[offset + 6] = UInt8(truncatingIfNeeded: bits >> 48)
    buffer[offset + 7] = UInt8(truncatingIfNeeded: bits >> 56)
}
