import Foundation

public enum ReplayFixtureCodec {
    public static func write(_ fixture: ReplayFixture, to url: URL) throws {
        let ext = url.pathExtension.lowercased()
        if ext == "jsonl" {
            try writeJSONL(fixture, to: url)
        } else {
            try ATPCaptureCodec.write(fixture: fixture, to: url)
        }
    }

    public static func writeJSONL(_ fixture: ReplayFixture, to url: URL) throws {
        var lines: [String] = []
        lines.reserveCapacity(fixture.frames.count + 1)

        let meta = JSONLMetaLine(
            type: "meta",
            schema: fixture.meta.schema,
            capturedAt: fixture.meta.capturedAt,
            platform: fixture.meta.platform,
            source: fixture.meta.source,
            framesCaptured: fixture.frames.count
        )
        lines.append(try encodeJSONLine(meta))

        for frame in fixture.frames {
            let contacts = frame.contacts.map { contact in
                JSONLContactLine(
                    id: contact.id,
                    x: contact.x,
                    y: contact.y,
                    total: contact.total,
                    pressure: contact.pressure,
                    majorAxis: contact.majorAxis,
                    minorAxis: contact.minorAxis,
                    angle: contact.angle,
                    density: contact.density,
                    state: contact.state
                )
            }
            let frameLine = JSONLFrameLine(
                type: "frame",
                schema: fixture.meta.schema,
                seq: frame.seq,
                timestampSec: frame.timestampSec,
                deviceID: frame.deviceID,
                deviceNumericID: String(frame.deviceNumericID),
                deviceIndex: frame.deviceIndex,
                touchCount: contacts.count,
                contacts: contacts
            )
            lines.append(try encodeJSONLine(frameLine))
        }

        let payload = lines.joined(separator: "\n") + "\n"
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try payload.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func encodeJSONLine<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        if #available(macOS 10.13, *) {
            encoder.outputFormatting = [.sortedKeys]
        }
        let data = try encoder.encode(value)
        guard let line = String(data: data, encoding: .utf8) else {
            throw ReplayFixtureError.invalidJSON(line: 1)
        }
        return line
    }

    private struct JSONLMetaLine: Encodable {
        let type: String
        let schema: String
        let capturedAt: String
        let platform: String
        let source: String
        let framesCaptured: Int
    }

    private struct JSONLFrameLine: Encodable {
        let type: String
        let schema: String
        let seq: Int
        let timestampSec: Double
        let deviceID: String
        let deviceNumericID: String
        let deviceIndex: Int
        let touchCount: Int
        let contacts: [JSONLContactLine]
    }

    private struct JSONLContactLine: Encodable {
        let id: Int
        let x: Double
        let y: Double
        let total: Double
        let pressure: Double
        let majorAxis: Double
        let minorAxis: Double
        let angle: Double
        let density: Double
        let state: String
    }
}

public enum ATPCaptureCodec {
    public static let fileMagic = "ATPCAP01"
    public static let currentVersion: Int32 = 3
    public static let headerSize = 20
    public static let recordHeaderSize = 34
    public static let defaultTickFrequency: Int64 = 1_000_000_000
    private static let framePayloadMagic: UInt32 = 0x33564652 // "RFV3" little-endian
    private static let metaRecordDeviceIndex: Int32 = -1
    private static let frameHeaderBytes = 32
    private static let frameContactBytes = 40

    public static func isATPCapture(_ data: Data) -> Bool {
        guard data.count >= 8 else {
            return false
        }
        guard let magic = String(data: data.prefix(8), encoding: .ascii) else {
            return false
        }
        return magic == fileMagic
    }

    public static func write(
        fixture: ReplayFixture,
        to url: URL,
        tickFrequency: Int64 = defaultTickFrequency
    ) throws {
        guard tickFrequency > 0 else {
            throw ReplayFixtureError.invalidATPCapture(reason: "tick frequency must be > 0")
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: url)
        defer {
            try? handle.close()
        }
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: fileHeader(tickFrequency: tickFrequency))

        let normalizedMeta = ReplayFixtureMeta(
            schema: fixture.meta.schema,
            capturedAt: fixture.meta.capturedAt,
            platform: fixture.meta.platform,
            source: fixture.meta.source,
            framesCaptured: fixture.frames.count
        )
        let metaPayload = try encodeMetaPayload(normalizedMeta)
        try handle.write(contentsOf: recordHeader(
            payloadLength: metaPayload.count,
            arrivalTicks: 0,
            deviceIndex: metaRecordDeviceIndex,
            deviceHash: 0,
            vendorID: 0,
            productID: 0,
            usagePage: 0,
            usage: 0,
            sideHint: 0,
            decoderProfile: 0
        ))
        try handle.write(contentsOf: metaPayload)

        let baseTimestamp = fixture.frames.first?.timestampSec ?? 0
        var expectedSeq = 1
        for frame in fixture.frames {
            guard frame.seq == expectedSeq else {
                throw ReplayFixtureError.invalidSequence(expected: expectedSeq, actual: frame.seq)
            }
            guard let deviceIndex = Int32(exactly: frame.deviceIndex) else {
                throw ReplayFixtureError.invalidATPCapture(reason: "deviceIndex \(frame.deviceIndex) out of Int32 range")
            }

            let payload = try encodeFramePayload(frame)
            let arrivalTicks = max(
                Int64(0),
                Int64(((frame.timestampSec - baseTimestamp) * Double(tickFrequency)).rounded())
            )
            let sideHint: UInt8 = sideHintForDeviceIndex(frame.deviceIndex)

            try handle.write(contentsOf: recordHeader(
                payloadLength: payload.count,
                arrivalTicks: arrivalTicks,
                deviceIndex: deviceIndex,
                deviceHash: UInt32(truncatingIfNeeded: frame.deviceNumericID),
                vendorID: 0,
                productID: 0,
                usagePage: 0,
                usage: 0,
                sideHint: sideHint,
                decoderProfile: 0
            ))
            try handle.write(contentsOf: payload)
            expectedSeq += 1
        }
    }

    public static func parse(data: Data) throws -> ReplayFixture {
        guard isATPCapture(data) else {
            throw ReplayFixtureError.invalidATPCapture(reason: "missing ATPCAP01 header")
        }
        guard data.count >= headerSize else {
            throw ReplayFixtureError.invalidATPCapture(reason: "header truncated")
        }

        let version = readInt32LE(from: data, at: 8)
        guard version == currentVersion else {
            throw ReplayFixtureError.unsupportedATPCaptureVersion(actual: version)
        }

        _ = readInt64LE(from: data, at: 12)

        var offset = headerSize
        var meta: ReplayFixtureMeta?
        var frames: [ReplayFrameRecord] = []
        frames.reserveCapacity(1024)
        var expectedSeq = 1

        while offset < data.count {
            guard offset + recordHeaderSize <= data.count else {
                throw ReplayFixtureError.invalidATPCapture(reason: "record header truncated at byte \(offset)")
            }

            let payloadLength = readInt32LE(from: data, at: offset)
            if payloadLength < 0 {
                throw ReplayFixtureError.invalidATPCapture(reason: "negative payload length at byte \(offset)")
            }
            let payloadLengthInt = Int(payloadLength)
            let arrivalTicks = readInt64LE(from: data, at: offset + 4)
            let deviceIndex = readInt32LE(from: data, at: offset + 12)
            offset += recordHeaderSize

            guard offset + payloadLengthInt <= data.count else {
                throw ReplayFixtureError.invalidATPCapture(reason: "payload truncated at byte \(offset)")
            }

            let payload = data.subdata(in: offset..<(offset + payloadLengthInt))
            offset += payloadLengthInt
            _ = arrivalTicks

            if deviceIndex == metaRecordDeviceIndex {
                meta = try decodeMetaPayload(payload)
                continue
            }

            let frame = try decodeFramePayload(payload, headerDeviceIndex: Int(deviceIndex))
            if frame.seq != expectedSeq {
                throw ReplayFixtureError.invalidSequence(expected: expectedSeq, actual: frame.seq)
            }
            frames.append(frame)
            expectedSeq += 1
        }

        let resolvedMeta = meta ?? ReplayFixtureMeta(
            schema: ReplayFixtureParser.schema,
            capturedAt: iso8601Timestamp(Date()),
            platform: "unknown",
            source: "ATPCaptureCodec",
            framesCaptured: frames.count
        )
        if resolvedMeta.framesCaptured != frames.count {
            throw ReplayFixtureError.metaFrameCountMismatch(expected: resolvedMeta.framesCaptured, actual: frames.count)
        }
        return ReplayFixture(meta: resolvedMeta, frames: frames)
    }

    private static func fileHeader(tickFrequency: Int64) -> Data {
        var data = Data()
        data.reserveCapacity(headerSize)
        data.append(fileMagic.data(using: .ascii)!)
        appendInt32LE(currentVersion, to: &data)
        appendInt64LE(tickFrequency, to: &data)
        return data
    }

    private static func recordHeader(
        payloadLength: Int,
        arrivalTicks: Int64,
        deviceIndex: Int32,
        deviceHash: UInt32,
        vendorID: UInt32,
        productID: UInt32,
        usagePage: UInt16,
        usage: UInt16,
        sideHint: UInt8,
        decoderProfile: UInt8
    ) -> Data {
        var data = Data()
        data.reserveCapacity(recordHeaderSize)
        appendInt32LE(Int32(payloadLength), to: &data)
        appendInt64LE(arrivalTicks, to: &data)
        appendInt32LE(deviceIndex, to: &data)
        appendUInt32LE(deviceHash, to: &data)
        appendUInt32LE(vendorID, to: &data)
        appendUInt32LE(productID, to: &data)
        appendUInt16LE(usagePage, to: &data)
        appendUInt16LE(usage, to: &data)
        data.append(sideHint)
        data.append(decoderProfile)
        return data
    }

    private static func encodeMetaPayload(_ meta: ReplayFixtureMeta) throws -> Data {
        let payload = MetaPayload(
            type: "meta",
            schema: meta.schema,
            capturedAt: meta.capturedAt,
            platform: meta.platform,
            source: meta.source,
            framesCaptured: meta.framesCaptured
        )
        let encoder = JSONEncoder()
        if #available(macOS 10.13, *) {
            encoder.outputFormatting = [.sortedKeys]
        }
        return try encoder.encode(payload)
    }

    private static func decodeMetaPayload(_ data: Data) throws -> ReplayFixtureMeta {
        let decoder = JSONDecoder()
        let payload: MetaPayload
        do {
            payload = try decoder.decode(MetaPayload.self, from: data)
        } catch {
            throw ReplayFixtureError.invalidATPCapture(reason: "meta payload decode failed: \(error.localizedDescription)")
        }
        guard payload.type == "meta" else {
            throw ReplayFixtureError.invalidATPCapture(reason: "meta payload type must be 'meta'")
        }
        guard payload.schema == ReplayFixtureParser.schema else {
            throw ReplayFixtureError.invalidSchema(line: 1, value: payload.schema)
        }
        return ReplayFixtureMeta(
            schema: payload.schema,
            capturedAt: payload.capturedAt,
            platform: payload.platform,
            source: payload.source,
            framesCaptured: payload.framesCaptured
        )
    }

    private static func encodeFramePayload(_ frame: ReplayFrameRecord) throws -> Data {
        guard let seq = UInt64(exactly: frame.seq) else {
            throw ReplayFixtureError.invalidATPCapture(reason: "sequence \(frame.seq) out of UInt64 range")
        }
        guard let contactCount = UInt16(exactly: frame.contacts.count) else {
            throw ReplayFixtureError.invalidATPCapture(reason: "contact count \(frame.contacts.count) exceeds UInt16")
        }

        var payload = Data()
        payload.reserveCapacity(frameHeaderBytes + frame.contacts.count * frameContactBytes)
        appendUInt32LE(framePayloadMagic, to: &payload)
        appendUInt64LE(seq, to: &payload)
        appendDoubleLE(frame.timestampSec, to: &payload)
        appendUInt64LE(frame.deviceNumericID, to: &payload)
        appendUInt16LE(contactCount, to: &payload)
        appendUInt16LE(0, to: &payload)

        for contact in frame.contacts {
            guard let id = Int32(exactly: contact.id) else {
                throw ReplayFixtureError.invalidATPCapture(reason: "contact id \(contact.id) out of Int32 range")
            }
            guard let state = ReplayFixtureParser.canonicalStateCode(state: contact.state) else {
                throw ReplayFixtureError.invalidStateEncoding(state: contact.state)
            }

            appendInt32LE(id, to: &payload)
            appendFloatLE(Float(contact.x), to: &payload)
            appendFloatLE(Float(contact.y), to: &payload)
            appendFloatLE(Float(contact.total), to: &payload)
            appendFloatLE(Float(contact.pressure), to: &payload)
            appendFloatLE(Float(contact.majorAxis), to: &payload)
            appendFloatLE(Float(contact.minorAxis), to: &payload)
            appendFloatLE(Float(contact.angle), to: &payload)
            appendFloatLE(Float(contact.density), to: &payload)
            payload.append(state)
            payload.append(0)
            payload.append(0)
            payload.append(0)
        }

        return payload
    }

    private static func decodeFramePayload(
        _ payload: Data,
        headerDeviceIndex: Int
    ) throws -> ReplayFrameRecord {
        guard payload.count >= frameHeaderBytes else {
            throw ReplayFixtureError.invalidATPCapture(reason: "frame payload too small (\(payload.count) bytes)")
        }

        let magic = readUInt32LE(from: payload, at: 0)
        guard magic == framePayloadMagic else {
            throw ReplayFixtureError.invalidATPCapture(reason: "frame payload magic mismatch")
        }

        let sequence = readUInt64LE(from: payload, at: 4)
        guard let sequenceInt = Int(exactly: sequence) else {
            throw ReplayFixtureError.invalidATPCapture(reason: "sequence \(sequence) exceeds Int range")
        }
        let timestampSec = readDoubleLE(from: payload, at: 12)
        let deviceNumericID = readUInt64LE(from: payload, at: 20)
        let contactCount = Int(readUInt16LE(from: payload, at: 28))
        let expectedLength = frameHeaderBytes + contactCount * frameContactBytes
        guard payload.count == expectedLength else {
            throw ReplayFixtureError.invalidATPCapture(
                reason: "frame payload length mismatch expected \(expectedLength), got \(payload.count)"
            )
        }

        var contacts: [ReplayContactRecord] = []
        contacts.reserveCapacity(contactCount)

        var offset = frameHeaderBytes
        for _ in 0..<contactCount {
            let id = Int(readInt32LE(from: payload, at: offset))
            let x = Double(readFloatLE(from: payload, at: offset + 4))
            let y = Double(readFloatLE(from: payload, at: offset + 8))
            let total = Double(readFloatLE(from: payload, at: offset + 12))
            let pressure = Double(readFloatLE(from: payload, at: offset + 16))
            let majorAxis = Double(readFloatLE(from: payload, at: offset + 20))
            let minorAxis = Double(readFloatLE(from: payload, at: offset + 24))
            let angle = Double(readFloatLE(from: payload, at: offset + 28))
            let density = Double(readFloatLE(from: payload, at: offset + 32))
            let stateCode = payload[offset + 36]
            guard let state = ReplayFixtureParser.canonicalState(code: stateCode) else {
                throw ReplayFixtureError.invalidATPCapture(reason: "invalid canonical state code \(stateCode)")
            }
            contacts.append(
                ReplayContactRecord(
                    id: id,
                    x: x,
                    y: y,
                    total: total,
                    pressure: pressure,
                    majorAxis: majorAxis,
                    minorAxis: minorAxis,
                    angle: angle,
                    density: density,
                    state: state
                )
            )
            offset += frameContactBytes
        }

        return ReplayFrameRecord(
            seq: sequenceInt,
            timestampSec: timestampSec,
            deviceID: String(deviceNumericID),
            deviceNumericID: deviceNumericID,
            deviceIndex: headerDeviceIndex,
            contacts: contacts
        )
    }

    private static func sideHintForDeviceIndex(_ deviceIndex: Int) -> UInt8 {
        switch deviceIndex {
        case 0:
            return 1
        case 1:
            return 2
        default:
            return 0
        }
    }

    private static func iso8601Timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func readInt32LE(from data: Data, at offset: Int) -> Int32 {
        Int32(bitPattern: readUInt32LE(from: data, at: offset))
    }

    private static func readUInt32LE(from data: Data, at offset: Int) -> UInt32 {
        data.withUnsafeBytes { rawBuffer in
            let value = rawBuffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            return UInt32(littleEndian: value)
        }
    }

    private static func readInt64LE(from data: Data, at offset: Int) -> Int64 {
        Int64(bitPattern: readUInt64LE(from: data, at: offset))
    }

    private static func readUInt64LE(from data: Data, at offset: Int) -> UInt64 {
        data.withUnsafeBytes { rawBuffer in
            let value = rawBuffer.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
            return UInt64(littleEndian: value)
        }
    }

    private static func readUInt16LE(from data: Data, at offset: Int) -> UInt16 {
        data.withUnsafeBytes { rawBuffer in
            let value = rawBuffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
            return UInt16(littleEndian: value)
        }
    }

    private static func readDoubleLE(from data: Data, at offset: Int) -> Double {
        let bits = readUInt64LE(from: data, at: offset)
        return Double(bitPattern: bits)
    }

    private static func readFloatLE(from data: Data, at offset: Int) -> Float {
        let bits = readUInt32LE(from: data, at: offset)
        return Float(bitPattern: bits)
    }

    private static func appendInt32LE(_ value: Int32, to data: inout Data) {
        appendUInt32LE(UInt32(bitPattern: value), to: &data)
    }

    private static func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { bytes in
            data.append(contentsOf: bytes)
        }
    }

    private static func appendInt64LE(_ value: Int64, to data: inout Data) {
        appendUInt64LE(UInt64(bitPattern: value), to: &data)
    }

    private static func appendUInt64LE(_ value: UInt64, to data: inout Data) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { bytes in
            data.append(contentsOf: bytes)
        }
    }

    private static func appendUInt16LE(_ value: UInt16, to data: inout Data) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { bytes in
            data.append(contentsOf: bytes)
        }
    }

    private static func appendDoubleLE(_ value: Double, to data: inout Data) {
        appendUInt64LE(value.bitPattern, to: &data)
    }

    private static func appendFloatLE(_ value: Float, to data: inout Data) {
        appendUInt32LE(value.bitPattern, to: &data)
    }

    private struct MetaPayload: Codable {
        let type: String
        let schema: String
        let capturedAt: String
        let platform: String
        let source: String
        let framesCaptured: Int
    }
}
