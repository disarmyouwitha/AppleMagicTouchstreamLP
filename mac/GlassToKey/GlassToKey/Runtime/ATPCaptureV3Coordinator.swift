import Dispatch
import Foundation
import OpenMultitouchSupport
import os

enum ATPCaptureV3Codec {
    struct CaptureSample: Sendable {
        let frame: RuntimeRawFrame
        let arrivalTicks: Int64
    }

    struct ReplaySample: Sendable {
        let frame: RuntimeRawFrame
        let replayTimeSeconds: Double
    }

    struct ReplayData: Sendable {
        let samples: [ReplaySample]
        let durationSeconds: Double
    }

    static let fileMagic = "ATPCAP01"
    static let schema = "g2k-replay-v1"
    static let version2: Int32 = 2
    static let currentVersion: Int32 = 3
    static let headerSize = 20
    static let recordHeaderSize = 34
    static let defaultTickFrequency: Int64 = 1_000_000_000
    private static let framePayloadMagic: UInt32 = 0x33564652 // "RFV3" little-endian
    private static let metaRecordDeviceIndex: Int32 = -1
    private static let frameHeaderBytes = 32
    private static let frameContactBytes = 40
    private static let v2PtpReportID: UInt8 = 0x05
    private static let v2PtpExpectedSize = 50
    private static let v2MaxEmbeddedScanOffset = 96
    private static let v2MaxContacts = 5
    private static let v2MaxReasonableX = 20_000
    private static let v2MaxReasonableY = 15_000
    private static let v2OfficialMaxRawX = 14_720
    private static let v2OfficialMaxRawY = 10_240
    private static let v2TargetMaxX = 7_612
    private static let v2TargetMaxY = 5_065
    private static let v2UsagePageDigitizer: UInt16 = 0x0D
    private static let v2UsageTouchpad: UInt16 = 0x05
    private static let v2UsagePageUnknown: UInt16 = 0x00
    private static let v2UsageUnknown: UInt16 = 0x00
    private static let v2DecoderProfileLegacy: UInt8 = 1
    private static let v2DecoderProfileOfficial: UInt8 = 2
    private static let sideHintLeft: UInt8 = 1
    private static let sideHintRight: UInt8 = 2

    static func write(
        frames: [RuntimeRawFrame],
        to url: URL,
        tickFrequency: Int64 = defaultTickFrequency,
        platform: String = "macOS",
        source: String = "GlassToKeyMenuCapture"
    ) throws {
        let baseTimestamp = frames.first?.timestamp ?? 0
        let samples = frames.map { frame in
            let ticks = Int64(((frame.timestamp - baseTimestamp) * Double(tickFrequency)).rounded())
            return CaptureSample(frame: frame, arrivalTicks: max(0, ticks))
        }
        try write(
            samples: samples,
            to: url,
            tickFrequency: tickFrequency,
            platform: platform,
            source: source
        )
    }

    static func write(
        samples: [CaptureSample],
        to url: URL,
        tickFrequency: Int64 = defaultTickFrequency,
        platform: String = "macOS",
        source: String = "GlassToKeyMenuCapture"
    ) throws {
        guard tickFrequency > 0 else {
            throw RuntimeCaptureReplayError.invalidATPCapture(reason: "tick frequency must be > 0")
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

        let metaPayload = try encodeMetaPayload(
            schema: schema,
            capturedAt: iso8601Timestamp(Date()),
            platform: platform,
            source: source,
            framesCaptured: samples.count
        )
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

        var sequence: UInt64 = 1
        for sample in samples {
            let frame = sample.frame
            guard let deviceIndex = Int32(exactly: frame.deviceIndex) else {
                throw RuntimeCaptureReplayError.invalidATPCapture(
                    reason: "deviceIndex \(frame.deviceIndex) out of Int32 range"
                )
            }
            let payload = try encodeFramePayload(sequence: sequence, frame: frame)
            let arrivalTicks = max(0, sample.arrivalTicks)

            try handle.write(contentsOf: recordHeader(
                payloadLength: payload.count,
                arrivalTicks: arrivalTicks,
                deviceIndex: deviceIndex,
                deviceHash: UInt32(truncatingIfNeeded: frame.deviceNumericID),
                vendorID: 0,
                productID: 0,
                usagePage: 0,
                usage: 0,
                sideHint: sideHintForDeviceIndex(frame.deviceIndex),
                decoderProfile: 0
            ))
            try handle.write(contentsOf: payload)
            sequence &+= 1
        }
    }

    static func readReplayData(from url: URL) throws -> ReplayData {
        let data = try Data(contentsOf: url)
        return try parseReplayData(data: data)
    }

    static func parseReplayData(data: Data) throws -> ReplayData {
        let container = try readContainer(data: data)
        let version = container.header.version
        guard version == currentVersion || version == version2 else {
            throw RuntimeCaptureReplayError.unsupportedATPCaptureVersion(
                actual: version
            )
        }
        let isV3Capture = version == currentVersion

        var expectedSequence: UInt64 = 1
        var frames: [RuntimeRawFrame] = []
        frames.reserveCapacity(1024)
        var rawArrivalTicks: [Int64] = []
        rawArrivalTicks.reserveCapacity(1024)

        for record in container.records {
            if isV3Capture {
                if record.deviceIndex == metaRecordDeviceIndex {
                    _ = try decodeMetaPayload(record.payload)
                    continue
                }

                let frame = try decodeFramePayload(
                    record.payload,
                    headerDeviceIndex: Int(record.deviceIndex)
                )
                guard frame.sequence == expectedSequence else {
                    throw RuntimeCaptureReplayError.invalidATPCapture(
                        reason: "invalid sequence: expected \(expectedSequence), got \(frame.sequence)"
                    )
                }
                frames.append(frame)
                rawArrivalTicks.append(record.arrivalTicks)
                expectedSequence &+= 1
                continue
            }

            guard let frame = decodeV2FramePayload(record: record, sequence: expectedSequence) else {
                continue
            }
            frames.append(frame)
            rawArrivalTicks.append(record.arrivalTicks)
            expectedSequence &+= 1
        }

        let replayTimes = try replayTimelineSeconds(
            rawArrivalTicks: rawArrivalTicks,
            tickFrequency: container.header.tickFrequency
        )
        var samples: [ReplaySample] = []
        samples.reserveCapacity(frames.count)
        for index in frames.indices {
            var frame = frames[index]
            let replayTime = replayTimes[index]
            frame.timestamp = replayTime
            samples.append(
                ReplaySample(
                    frame: frame,
                    replayTimeSeconds: replayTime
                )
            )
        }
        return ReplayData(
            samples: samples,
            durationSeconds: replayTimes.last ?? 0
        )
    }

    static func readFrames(from url: URL) throws -> [RuntimeRawFrame] {
        try readReplayData(from: url).samples.map(\.frame)
    }

    static func parseFrames(data: Data) throws -> [RuntimeRawFrame] {
        try parseReplayData(data: data).samples.map(\.frame)
    }

    private static func decodeV2FramePayload(
        record: ATPCaptureRecord,
        sequence: UInt64
    ) -> RuntimeRawFrame? {
        guard record.deviceIndex >= 0 else {
            return nil
        }
        let mappedDeviceIndex = mapV2DeviceIndex(
            headerDeviceIndex: Int(record.deviceIndex),
            sideHint: record.sideHint
        )
        guard let contacts = decodeV2Contacts(
            payload: record.payload,
            usagePage: record.usagePage,
            usage: record.usage,
            decoderProfile: record.decoderProfile
        ) else {
            return nil
        }
        return RuntimeRawFrame(
            sequence: sequence,
            timestamp: 0,
            deviceNumericID: UInt64(record.deviceHash),
            deviceIndex: mappedDeviceIndex,
            contacts: contacts,
            rawTouches: []
        )
    }

    private static func decodeV2Contacts(
        payload: Data,
        usagePage: UInt16,
        usage: UInt16,
        decoderProfile: UInt8
    ) -> [RuntimeRawContact]? {
        let preferredLegacy = decoderProfile == v2DecoderProfileLegacy
        if preferredLegacy {
            if let contacts = decodeV2PtpContacts(
                payload: payload,
                usagePage: usagePage,
                usage: usage,
                profile: .legacy
            ) {
                return contacts
            }
            return nil
        }

        if let contacts = decodeV2PtpContacts(
            payload: payload,
            usagePage: usagePage,
            usage: usage,
            profile: .official
        ) {
            return contacts
        }
        if let contacts = decodeV2PtpContacts(
            payload: payload,
            usagePage: usagePage,
            usage: usage,
            profile: .legacy
        ) {
            return contacts
        }
        return nil
    }

    private static func decodeV2PtpContacts(
        payload: Data,
        usagePage: UInt16,
        usage: UInt16,
        profile: V2DecoderProfile
    ) -> [RuntimeRawContact]? {
        guard payload.count >= v2PtpExpectedSize else {
            return nil
        }

        if payload[0] == v2PtpReportID,
           let contacts = tryParseV2PtpAtOffset(
               payload: payload,
               offset: 0,
               usagePage: usagePage,
               usage: usage,
               profile: profile
           ) {
            return contacts
        }

        let maxOffset = min(payload.count - v2PtpExpectedSize, v2MaxEmbeddedScanOffset)
        guard maxOffset >= 1 else {
            return nil
        }
        for offset in 1...maxOffset {
            guard payload[offset] == v2PtpReportID else {
                continue
            }
            if let contacts = tryParseV2PtpAtOffset(
                payload: payload,
                offset: offset,
                usagePage: usagePage,
                usage: usage,
                profile: profile
            ) {
                return contacts
            }
        }

        return nil
    }

    private static func tryParseV2PtpAtOffset(
        payload: Data,
        offset: Int,
        usagePage: UInt16,
        usage: UInt16,
        profile: V2DecoderProfile
    ) -> [RuntimeRawContact]? {
        guard offset >= 0, offset <= payload.count - v2PtpExpectedSize else {
            return nil
        }
        guard payload[offset] == v2PtpReportID else {
            return nil
        }

        var contacts: [V2Contact] = []
        contacts.reserveCapacity(v2MaxContacts)
        for index in 0..<v2MaxContacts {
            let slotOffset = offset + 1 + (index * 9)
            let flags = payload[slotOffset]
            let contactID = readUInt32LE(from: payload, at: slotOffset + 1)
            let x = readUInt16LE(from: payload, at: slotOffset + 5)
            let y = readUInt16LE(from: payload, at: slotOffset + 7)
            contacts.append(
                V2Contact(
                    id: contactID,
                    x: x,
                    y: y,
                    flags: flags,
                    pressure: 0,
                    phase: 0
                )
            )
        }

        let reportedContactCount = Int(payload[offset + 48])
        guard reportedContactCount <= v2MaxContacts else {
            return nil
        }
        let clampedContactCount = min(reportedContactCount, v2MaxContacts)

        switch profile {
        case .official:
            guard looksReasonableOfficial(
                contacts: contacts,
                clampedContactCount: clampedContactCount
            ) else {
                return nil
            }
            contacts = normalizeOfficialContacts(
                contacts: contacts,
                payload: payload,
                offset: offset,
                usagePage: usagePage,
                usage: usage,
                clampedContactCount: clampedContactCount
            )
        case .legacy:
            guard looksReasonableLegacy(
                contacts: contacts,
                clampedContactCount: clampedContactCount
            ) else {
                return nil
            }
            contacts = Array(contacts.prefix(clampedContactCount))
            normalizeLikelyPackedContactIDs(contacts: &contacts)
        }

        var runtimeContacts: [RuntimeRawContact] = []
        runtimeContacts.reserveCapacity(contacts.count)
        let shouldFlipY = shouldFlipYForV2(
            usagePage: usagePage,
            usage: usage,
            decoderProfile: decoderProfileCode(for: profile)
        )
        for contact in contacts where (contact.flags & 0x02) != 0 {
            let xNorm = clamp01(Float(contact.x) / Float(v2TargetMaxX))
            let yNormSource = clamp01(Float(contact.y) / Float(v2TargetMaxY))
            let yNormBottomOrigin = shouldFlipY
                ? (1.0 - yNormSource)
                : yNormSource
            runtimeContacts.append(
                RuntimeRawContact(
                    id: Int32(bitPattern: contact.id),
                    posX: xNorm,
                    posY: yNormBottomOrigin,
                    pressure: Float(contact.pressure) / 255.0,
                    majorAxis: 0,
                    minorAxis: 0,
                    angle: 0,
                    density: 0,
                    state: .touching
                )
            )
        }
        return runtimeContacts
    }

    private static func looksReasonableLegacy(
        contacts: [V2Contact],
        clampedContactCount: Int
    ) -> Bool {
        for index in 0..<clampedContactCount {
            let contact = contacts[index]
            if Int(contact.x) > v2MaxReasonableX || Int(contact.y) > v2MaxReasonableY {
                return false
            }
        }
        return true
    }

    private static func looksReasonableOfficial(
        contacts: [V2Contact],
        clampedContactCount: Int
    ) -> Bool {
        guard clampedContactCount > 0 else {
            return true
        }
        for index in 0..<clampedContactCount {
            let contact = contacts[index]
            if contact.x != 0 || contact.y != 0 || contact.flags != 0 || contact.id != 0 {
                return true
            }
        }
        return false
    }

    private static func normalizeOfficialContacts(
        contacts: [V2Contact],
        payload: Data,
        offset: Int,
        usagePage: UInt16,
        usage: UInt16,
        clampedContactCount: Int
    ) -> [V2Contact] {
        let isNativeTouchpadUsage = usagePage == v2UsagePageDigitizer && usage == v2UsageTouchpad
        var usedIDs = Array(repeating: false, count: 256)
        var normalized: [V2Contact] = []
        normalized.reserveCapacity(clampedContactCount)

        for index in 0..<clampedContactCount {
            let source = contacts[index]
            let normalizedFlags = (source.flags & 0xFC) | 0x03
            var x = source.x
            var y = source.y
            var pressure: UInt8 = 0
            var phase: UInt8 = 0
            let assignedID: UInt32

            if !isNativeTouchpadUsage {
                let slotOffset = offset + 1 + (index * 9)
                if slotOffset + 8 < payload.count {
                    assignedID = assignOfficialContactID(
                        candidateID: payload[slotOffset],
                        usedIDs: &usedIDs
                    )
                    let rawX = Int(readUInt16LE(from: payload, at: slotOffset + 2))
                    let rawY = Int(readUInt16LE(from: payload, at: slotOffset + 4))
                    x = scaleOfficialCoordinate(
                        value: rawX,
                        maxRaw: v2OfficialMaxRawX,
                        targetMax: v2TargetMaxX
                    )
                    y = scaleOfficialCoordinate(
                        value: rawY,
                        maxRaw: v2OfficialMaxRawY,
                        targetMax: v2TargetMaxY
                    )
                    pressure = payload[slotOffset + 6]
                    phase = payload[slotOffset + 7]
                } else {
                    assignedID = assignOfficialContactID(
                        candidateID: UInt8(truncatingIfNeeded: index),
                        usedIDs: &usedIDs
                    )
                }
            } else {
                assignedID = assignOfficialContactID(
                    candidateID: UInt8(truncatingIfNeeded: index),
                    usedIDs: &usedIDs
                )
            }

            normalized.append(
                V2Contact(
                    id: assignedID,
                    x: x,
                    y: y,
                    flags: normalizedFlags,
                    pressure: pressure,
                    phase: phase
                )
            )
        }

        return normalized
    }

    private static func assignOfficialContactID(
        candidateID: UInt8,
        usedIDs: inout [Bool]
    ) -> UInt32 {
        let candidateIndex = Int(candidateID)
        if !usedIDs[candidateIndex] {
            usedIDs[candidateIndex] = true
            return UInt32(candidateID)
        }

        for index in usedIDs.indices where !usedIDs[index] {
            usedIDs[index] = true
            return UInt32(index)
        }

        return UInt32(candidateID)
    }

    private static func scaleOfficialCoordinate(
        value: Int,
        maxRaw: Int,
        targetMax: Int
    ) -> UInt16 {
        let clamped = min(max(value, 0), maxRaw)
        let scaled = (clamped * targetMax + (maxRaw / 2)) / maxRaw
        return UInt16(clamping: scaled)
    }

    private static func normalizeLikelyPackedContactIDs(contacts: inout [V2Contact]) {
        guard !contacts.isEmpty else {
            return
        }
        var tipCount = 0
        var suspiciousIDCount = 0
        for contact in contacts where (contact.flags & 0x02) != 0 {
            tipCount += 1
            if (contact.id & 0xFF) == 0 && contact.id > 0x00FF_FFFF {
                suspiciousIDCount += 1
            }
        }
        guard tipCount > 0, suspiciousIDCount == tipCount else {
            return
        }

        for index in contacts.indices where (contacts[index].flags & 0x02) != 0 {
            contacts[index].id = UInt32(index)
        }
    }

    private static func mapV2DeviceIndex(
        headerDeviceIndex: Int,
        sideHint: UInt8
    ) -> Int {
        switch sideHint {
        case sideHintLeft:
            return 1
        case sideHintRight:
            return 0
        default:
            return headerDeviceIndex
        }
    }

    private static func shouldFlipYForV2(
        usagePage: UInt16,
        usage: UInt16,
        decoderProfile: UInt8
    ) -> Bool {
        _ = usagePage
        _ = usage
        _ = decoderProfile
        return true
    }

    private static func decoderProfileCode(for profile: V2DecoderProfile) -> UInt8 {
        switch profile {
        case .legacy:
            return v2DecoderProfileLegacy
        case .official:
            return v2DecoderProfileOfficial
        }
    }

    private static func clamp01(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }

    private static func replayTimelineSeconds(
        rawArrivalTicks: [Int64],
        tickFrequency: Int64
    ) throws -> [Double] {
        guard !rawArrivalTicks.isEmpty else {
            return []
        }

        let normalizedFrequency = max(1, tickFrequency)
        let firstTick = rawArrivalTicks[0]
        var normalizedTicks: [Int64] = []
        normalizedTicks.reserveCapacity(rawArrivalTicks.count)

        var previousTick: Int64 = 0
        for (index, rawTick) in rawArrivalTicks.enumerated() {
            let tick = rawTick - firstTick
            guard tick >= 0 else {
                throw RuntimeCaptureReplayError.invalidATPCapture(
                    reason: "arrivalTicks must be monotonic (record \(index))"
                )
            }

            if index > 0, tick < previousTick {
                throw RuntimeCaptureReplayError.invalidATPCapture(
                    reason: "arrivalTicks must be monotonic (record \(index))"
                )
            }

            normalizedTicks.append(tick)
            previousTick = tick
        }

        let frequencyAsDouble = Double(normalizedFrequency)
        return normalizedTicks.map { Double($0) / frequencyAsDouble }
    }

    private static func readContainer(data: Data) throws -> ATPCaptureContainer {
        guard isATPCapture(data) else {
            throw RuntimeCaptureReplayError.invalidATPCapture(reason: "missing ATPCAP01 header")
        }
        guard data.count >= headerSize else {
            throw RuntimeCaptureReplayError.invalidATPCapture(reason: "header truncated")
        }

        let header = ATPCaptureHeader(
            version: readInt32LE(from: data, at: 8),
            tickFrequency: readInt64LE(from: data, at: 12)
        )

        var offset = headerSize
        var records: [ATPCaptureRecord] = []
        records.reserveCapacity(1024)

        while offset < data.count {
            guard offset + recordHeaderSize <= data.count else {
                throw RuntimeCaptureReplayError.invalidATPCapture(
                    reason: "record header truncated at byte \(offset)"
                )
            }

            let payloadLength = readInt32LE(from: data, at: offset)
            guard payloadLength >= 0 else {
                throw RuntimeCaptureReplayError.invalidATPCapture(
                    reason: "negative payload length at byte \(offset)"
                )
            }

            let payloadLengthInt = Int(payloadLength)
            let arrivalTicks = readInt64LE(from: data, at: offset + 4)
            let deviceIndex = readInt32LE(from: data, at: offset + 12)
            let deviceHash = readUInt32LE(from: data, at: offset + 16)
            let vendorID = readUInt32LE(from: data, at: offset + 20)
            let productID = readUInt32LE(from: data, at: offset + 24)
            let usagePage = readUInt16LE(from: data, at: offset + 28)
            let usage = readUInt16LE(from: data, at: offset + 30)
            let sideHint = data[offset + 32]
            let decoderProfile = data[offset + 33]
            offset += recordHeaderSize

            guard offset + payloadLengthInt <= data.count else {
                throw RuntimeCaptureReplayError.invalidATPCapture(
                    reason: "payload truncated at byte \(offset)"
                )
            }

            let payload = data.subdata(in: offset..<(offset + payloadLengthInt))
            offset += payloadLengthInt
            records.append(ATPCaptureRecord(
                payloadLength: payloadLengthInt,
                arrivalTicks: arrivalTicks,
                deviceIndex: deviceIndex,
                deviceHash: deviceHash,
                vendorID: vendorID,
                productID: productID,
                usagePage: usagePage,
                usage: usage,
                sideHint: sideHint,
                decoderProfile: decoderProfile,
                payload: payload
            ))
        }

        return ATPCaptureContainer(header: header, records: records)
    }

    private static func isATPCapture(_ data: Data) -> Bool {
        guard data.count >= 8 else {
            return false
        }
        guard let magic = String(data: data.prefix(8), encoding: .ascii) else {
            return false
        }
        return magic == fileMagic
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

    private static func encodeMetaPayload(
        schema: String,
        capturedAt: String,
        platform: String,
        source: String,
        framesCaptured: Int
    ) throws -> Data {
        let payload = MetaPayload(
            type: "meta",
            schema: schema,
            capturedAt: capturedAt,
            platform: platform,
            source: source,
            framesCaptured: framesCaptured
        )
        let encoder = JSONEncoder()
        if #available(macOS 10.13, *) {
            encoder.outputFormatting = [.sortedKeys]
        }
        return try encoder.encode(payload)
    }

    private static func decodeMetaPayload(_ data: Data) throws -> MetaPayload {
        let decoder = JSONDecoder()
        let payload: MetaPayload
        do {
            payload = try decoder.decode(MetaPayload.self, from: data)
        } catch {
            throw RuntimeCaptureReplayError.invalidATPCapture(
                reason: "meta payload decode failed: \(error.localizedDescription)"
            )
        }

        guard payload.type == "meta" else {
            throw RuntimeCaptureReplayError.invalidATPCapture(reason: "meta payload type must be 'meta'")
        }
        guard payload.schema == schema else {
            throw RuntimeCaptureReplayError.invalidATPCapture(
                reason: "unsupported schema '\(payload.schema)'"
            )
        }
        return payload
    }

    private static func encodeFramePayload(
        sequence: UInt64,
        frame: RuntimeRawFrame
    ) throws -> Data {
        guard frame.contacts.count <= Int(UInt16.max) else {
            throw RuntimeCaptureReplayError.invalidATPCapture(
                reason: "contact count \(frame.contacts.count) exceeds UInt16"
            )
        }

        var payload = Data()
        payload.reserveCapacity(frameHeaderBytes + frame.contacts.count * frameContactBytes)

        appendUInt32LE(framePayloadMagic, to: &payload)
        appendUInt64LE(sequence, to: &payload)
        appendDoubleLE(frame.timestamp, to: &payload)
        appendUInt64LE(frame.deviceNumericID, to: &payload)
        appendUInt16LE(UInt16(frame.contacts.count), to: &payload)
        appendUInt16LE(0, to: &payload)

        var totalByTouchID: [Int32: Float] = [:]
        totalByTouchID.reserveCapacity(frame.rawTouches.count)
        for touch in frame.rawTouches {
            totalByTouchID[touch.id] = touch.total
        }

        for contact in frame.contacts {
            appendInt32LE(contact.id, to: &payload)
            appendFloatLE(contact.posX, to: &payload)
            appendFloatLE(contact.posY, to: &payload)
            appendFloatLE(totalByTouchID[contact.id] ?? 0, to: &payload)
            appendFloatLE(contact.pressure, to: &payload)
            appendFloatLE(contact.majorAxis, to: &payload)
            appendFloatLE(contact.minorAxis, to: &payload)
            appendFloatLE(contact.angle, to: &payload)
            appendFloatLE(contact.density, to: &payload)
            payload.append(try stateCode(for: contact.state))
            payload.append(0)
            payload.append(0)
            payload.append(0)
        }

        return payload
    }

    private static func decodeFramePayload(
        _ payload: Data,
        headerDeviceIndex: Int
    ) throws -> RuntimeRawFrame {
        guard payload.count >= frameHeaderBytes else {
            throw RuntimeCaptureReplayError.invalidATPCapture(
                reason: "frame payload too small (\(payload.count) bytes)"
            )
        }

        let magic = readUInt32LE(from: payload, at: 0)
        guard magic == framePayloadMagic else {
            throw RuntimeCaptureReplayError.invalidATPCapture(reason: "frame payload magic mismatch")
        }

        let sequence = readUInt64LE(from: payload, at: 4)
        let timestampSec = readDoubleLE(from: payload, at: 12)
        let deviceNumericID = readUInt64LE(from: payload, at: 20)
        let contactCount = Int(readUInt16LE(from: payload, at: 28))

        let expectedLength = frameHeaderBytes + contactCount * frameContactBytes
        guard payload.count == expectedLength else {
            throw RuntimeCaptureReplayError.invalidATPCapture(
                reason: "frame payload length mismatch expected \(expectedLength), got \(payload.count)"
            )
        }

        var contacts: [RuntimeRawContact] = []
        contacts.reserveCapacity(contactCount)

        var offset = frameHeaderBytes
        for _ in 0..<contactCount {
            let id = readInt32LE(from: payload, at: offset)
            let posX = readFloatLE(from: payload, at: offset + 4)
            let posY = readFloatLE(from: payload, at: offset + 8)
            let pressure = readFloatLE(from: payload, at: offset + 16)
            let majorAxis = readFloatLE(from: payload, at: offset + 20)
            let minorAxis = readFloatLE(from: payload, at: offset + 24)
            let angle = readFloatLE(from: payload, at: offset + 28)
            let density = readFloatLE(from: payload, at: offset + 32)
            let stateRaw = payload[offset + 36]
            let state = try omsState(code: stateRaw)

            contacts.append(RuntimeRawContact(
                id: id,
                posX: posX,
                posY: posY,
                pressure: pressure,
                majorAxis: majorAxis,
                minorAxis: minorAxis,
                angle: angle,
                density: density,
                state: state
            ))
            offset += frameContactBytes
        }

        return RuntimeRawFrame(
            sequence: sequence,
            timestamp: timestampSec,
            deviceNumericID: deviceNumericID,
            deviceIndex: headerDeviceIndex,
            contacts: contacts,
            rawTouches: []
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

    private static func stateCode(for state: OMSState) throws -> UInt8 {
        switch state {
        case .notTouching:
            return 0
        case .starting:
            return 1
        case .hovering:
            return 2
        case .making:
            return 3
        case .touching:
            return 4
        case .breaking:
            return 5
        case .lingering:
            return 6
        case .leaving:
            return 7
        }
    }

    private static func omsState(code: UInt8) throws -> OMSState {
        switch code {
        case 0:
            return .notTouching
        case 1:
            return .starting
        case 2:
            return .hovering
        case 3:
            return .making
        case 4:
            return .touching
        case 5:
            return .breaking
        case 6:
            return .lingering
        case 7:
            return .leaving
        default:
            throw RuntimeCaptureReplayError.invalidATPCapture(
                reason: "invalid canonical state code \(code)"
            )
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

    private struct ATPCaptureHeader: Sendable {
        let version: Int32
        let tickFrequency: Int64
    }

    private struct ATPCaptureRecord: Sendable {
        let payloadLength: Int
        let arrivalTicks: Int64
        let deviceIndex: Int32
        let deviceHash: UInt32
        let vendorID: UInt32
        let productID: UInt32
        let usagePage: UInt16
        let usage: UInt16
        let sideHint: UInt8
        let decoderProfile: UInt8
        let payload: Data
    }

    private struct ATPCaptureContainer: Sendable {
        let header: ATPCaptureHeader
        let records: [ATPCaptureRecord]
    }

    private enum V2DecoderProfile {
        case legacy
        case official
    }

    private struct V2Contact {
        var id: UInt32
        var x: UInt16
        var y: UInt16
        var flags: UInt8
        var pressure: UInt8
        var phase: UInt8
    }
}

enum RuntimeCaptureReplayError: LocalizedError {
    case captureAlreadyRunning
    case captureNotRunning
    case replaySessionAlreadyActive
    case replaySessionNotActive
    case replayPlaybackAlreadyActive
    case captureOrReplayConflict
    case unableToStartRuntimeForCapture
    case unableToRestartRuntimeAfterReplay
    case invalidATPCapture(reason: String)
    case unsupportedATPCaptureVersion(actual: Int32)

    var errorDescription: String? {
        switch self {
        case .captureAlreadyRunning:
            return "A capture session is already running."
        case .captureNotRunning:
            return "No capture session is currently running."
        case .replaySessionAlreadyActive:
            return "A replay session is already active."
        case .replaySessionNotActive:
            return "No replay session is active."
        case .replayPlaybackAlreadyActive:
            return "Replay playback is already running."
        case .captureOrReplayConflict:
            return "Capture and replay cannot run at the same time."
        case .unableToStartRuntimeForCapture:
            return "Unable to start runtime capture."
        case .unableToRestartRuntimeAfterReplay:
            return "Replay finished, but live runtime could not restart."
        case let .invalidATPCapture(reason):
            return "Invalid .atpcap: \(reason)"
        case let .unsupportedATPCaptureVersion(actual):
            return "Unsupported .atpcap version \(actual)."
        }
    }
}

struct RuntimeReplaySessionInfo: Sendable, Equatable {
    let sourceName: String
    let frameCount: Int
    let durationSeconds: Double
    let currentFrameIndex: Int
    let currentTimeSeconds: Double
    let isPlaying: Bool
}

struct RuntimeReplayPosition: Sendable, Equatable {
    let frameIndex: Int
    let timeSeconds: Double
}

final class RuntimeCaptureReplayCoordinator: @unchecked Sendable {
    private actor CaptureBuffer {
        private var samples: [ATPCaptureV3Codec.CaptureSample] = []

        func append(_ frame: RuntimeRawFrame, arrivalTicks: Int64) {
            samples.append(
                ATPCaptureV3Codec.CaptureSample(
                    frame: frame,
                    arrivalTicks: max(0, arrivalTicks)
                )
            )
        }

        func snapshot() -> [ATPCaptureV3Codec.CaptureSample] {
            samples
        }
    }

    private struct CaptureSession {
        let outputURL: URL
        let startedRuntimeForCapture: Bool
        let buffer: CaptureBuffer
        let task: Task<Void, Never>
    }

    private struct ReplaySession {
        let sourceName: String
        let frames: [RuntimeRawFrame]
        let frameTimesSeconds: [Double]
        let durationSeconds: Double
        let wasRuntimeRunningBeforeSession: Bool
        var currentFrameIndex: Int
        var currentTimeSeconds: Double
    }

    private struct State {
        var captureSession: CaptureSession?
        var captureInitializing = false
        var replaySession: ReplaySession?
        var replayPlaybackInProgress = false
    }

    private let inputRuntimeService: InputRuntimeService
    private let runtimeLifecycleCoordinator: RuntimeLifecycleCoordinatorService
    private let runtimeEngine: EngineActorBoundary
    private let renderSnapshotService: RuntimeRenderSnapshotService
    private let stateLock = OSAllocatedUnfairLock<State>(uncheckedState: State())

    init(
        inputRuntimeService: InputRuntimeService,
        runtimeLifecycleCoordinator: RuntimeLifecycleCoordinatorService,
        runtimeEngine: EngineActorBoundary,
        renderSnapshotService: RuntimeRenderSnapshotService
    ) {
        self.inputRuntimeService = inputRuntimeService
        self.runtimeLifecycleCoordinator = runtimeLifecycleCoordinator
        self.runtimeEngine = runtimeEngine
        self.renderSnapshotService = renderSnapshotService
    }

    var isCaptureActive: Bool {
        stateLock.withLockUnchecked { $0.captureSession != nil }
    }

    var isReplayActive: Bool {
        stateLock.withLockUnchecked { $0.replaySession != nil }
    }

    var isReplayPlaying: Bool {
        stateLock.withLockUnchecked(\.replayPlaybackInProgress)
    }

    func startCapture(to outputURL: URL) throws {
        var startedRuntimeForCapture = false

        let canStart = stateLock.withLockUnchecked { state -> Bool in
            guard state.captureSession == nil else {
                return false
            }
            guard !state.captureInitializing else {
                return false
            }
            guard state.replaySession == nil else {
                return false
            }
            state.captureInitializing = true
            return true
        }

        guard canStart else {
            if isReplayActive {
                throw RuntimeCaptureReplayError.captureOrReplayConflict
            }
            throw RuntimeCaptureReplayError.captureAlreadyRunning
        }

        if !inputRuntimeService.isRunning {
            startedRuntimeForCapture = runtimeLifecycleCoordinator.start()
            guard startedRuntimeForCapture else {
                stateLock.withLockUnchecked { $0.captureInitializing = false }
                throw RuntimeCaptureReplayError.unableToStartRuntimeForCapture
            }
        }

        let buffer = CaptureBuffer()
        let stream = inputRuntimeService.rawFrameStream
        let captureStartUptime = DispatchTime.now().uptimeNanoseconds
        let task = Task.detached(priority: .userInitiated) {
            for await rawFrame in stream {
                if Task.isCancelled {
                    return
                }
                let nowUptime = DispatchTime.now().uptimeNanoseconds
                let elapsed = nowUptime >= captureStartUptime ? nowUptime - captureStartUptime : 0
                await buffer.append(
                    rawFrame,
                    arrivalTicks: Int64(clamping: elapsed)
                )
            }
        }

        stateLock.withLockUnchecked { state in
            state.captureSession = CaptureSession(
                outputURL: outputURL,
                startedRuntimeForCapture: startedRuntimeForCapture,
                buffer: buffer,
                task: task
            )
            state.captureInitializing = false
        }
    }

    func stopCapture() async throws -> Int {
        let session = stateLock.withLockUnchecked { state -> CaptureSession? in
            let current = state.captureSession
            state.captureSession = nil
            return current
        }

        guard let session else {
            throw RuntimeCaptureReplayError.captureNotRunning
        }

        session.task.cancel()
        await Task.yield()

        if session.startedRuntimeForCapture {
            _ = runtimeLifecycleCoordinator.stop(stopVoiceDictation: false)
        }

        let samples = await session.buffer.snapshot()
        try ATPCaptureV3Codec.write(samples: samples, to: session.outputURL)
        return samples.count
    }

    func replayCapture(from inputURL: URL) async throws -> Int {
        let info = try await beginReplaySession(from: inputURL)
        _ = try await playReplay()
        try await endReplaySession()
        return info.frameCount
    }

    func beginReplaySession(from inputURL: URL) async throws -> RuntimeReplaySessionInfo {
        let sourceName = inputURL.lastPathComponent
        let replayData = try ATPCaptureV3Codec.readReplayData(from: inputURL)
        let frames = replayData.samples.map(\.frame)
        let frameTimes = replayData.samples.map(\.replayTimeSeconds)
        let wasRunning = inputRuntimeService.isRunning
        let durationSeconds = replayData.durationSeconds

        let canBegin = stateLock.withLockUnchecked { state -> Bool in
            guard state.captureSession == nil else { return false }
            guard !state.captureInitializing else { return false }
            guard state.replaySession == nil else { return false }
            return true
        }
        guard canBegin else {
            if isCaptureActive {
                throw RuntimeCaptureReplayError.captureOrReplayConflict
            }
            throw RuntimeCaptureReplayError.replaySessionAlreadyActive
        }

        _ = inputRuntimeService.stop()
        await runtimeEngine.setListening(true)
        await runtimeEngine.reset(stopVoiceDictation: false)

        var currentIndex = -1
        var currentTime = 0.0
        if !frames.isEmpty {
            await ingestFrame(frames[0])
            currentIndex = 0
            currentTime = frameTimes[0]
        }

        let session = ReplaySession(
            sourceName: sourceName,
            frames: frames,
            frameTimesSeconds: frameTimes,
            durationSeconds: durationSeconds,
            wasRuntimeRunningBeforeSession: wasRunning,
            currentFrameIndex: currentIndex,
            currentTimeSeconds: currentTime
        )
        stateLock.withLockUnchecked { state in
            state.replaySession = session
            state.replayPlaybackInProgress = false
        }

        return RuntimeReplaySessionInfo(
            sourceName: sourceName,
            frameCount: frames.count,
            durationSeconds: durationSeconds,
            currentFrameIndex: currentIndex,
            currentTimeSeconds: currentTime,
            isPlaying: false
        )
    }

    func replaySessionInfo() -> RuntimeReplaySessionInfo? {
        stateLock.withLockUnchecked { state in
            guard let session = state.replaySession else { return nil }
            return RuntimeReplaySessionInfo(
                sourceName: session.sourceName,
                frameCount: session.frames.count,
                durationSeconds: session.durationSeconds,
                currentFrameIndex: session.currentFrameIndex,
                currentTimeSeconds: session.currentTimeSeconds,
                isPlaying: state.replayPlaybackInProgress
            )
        }
    }

    @discardableResult
    func setReplayTimeSeconds(_ timeSeconds: Double) async throws -> RuntimeReplayPosition {
        let replaySession = stateLock.withLockUnchecked { state -> ReplaySession? in
            guard !state.replayPlaybackInProgress else { return nil }
            return state.replaySession
        }
        if isReplayPlaying {
            throw RuntimeCaptureReplayError.replayPlaybackAlreadyActive
        }
        guard let session = replaySession else {
            throw RuntimeCaptureReplayError.replaySessionNotActive
        }

        guard !session.frames.isEmpty else {
            stateLock.withLockUnchecked { state in
                state.replaySession?.currentFrameIndex = -1
                state.replaySession?.currentTimeSeconds = 0
            }
            await runtimeEngine.reset(stopVoiceDictation: false)
            return RuntimeReplayPosition(frameIndex: -1, timeSeconds: 0)
        }

        let clampedTime = min(max(timeSeconds, 0), session.durationSeconds)
        let targetIndex = frameIndex(
            forTime: clampedTime,
            frameTimes: session.frameTimesSeconds
        )

        await runtimeEngine.setListening(true)
        await runtimeEngine.reset(stopVoiceDictation: false)
        if targetIndex >= 0 {
            for index in 0...targetIndex {
                await ingestFrame(session.frames[index])
            }
        }

        stateLock.withLockUnchecked { state in
            state.replaySession?.currentFrameIndex = targetIndex
            state.replaySession?.currentTimeSeconds = clampedTime
        }
        return RuntimeReplayPosition(
            frameIndex: targetIndex,
            timeSeconds: clampedTime
        )
    }

    @discardableResult
    func playReplay(
        onProgress: (@Sendable (RuntimeReplayPosition) -> Void)? = nil
    ) async throws -> RuntimeReplayPosition {
        let session = stateLock.withLockUnchecked { state -> ReplaySession? in
            guard let session = state.replaySession else { return nil }
            guard !state.replayPlaybackInProgress else { return nil }
            state.replayPlaybackInProgress = true
            return session
        }
        if isReplayPlaying, session == nil {
            throw RuntimeCaptureReplayError.replayPlaybackAlreadyActive
        }
        guard let session else {
            throw RuntimeCaptureReplayError.replaySessionNotActive
        }
        defer {
            stateLock.withLockUnchecked { state in
                state.replayPlaybackInProgress = false
            }
        }

        let frames = session.frames
        let frameTimes = session.frameTimesSeconds
        guard !frames.isEmpty else {
            stateLock.withLockUnchecked { state in
                state.replaySession?.currentFrameIndex = -1
                state.replaySession?.currentTimeSeconds = 0
            }
            return RuntimeReplayPosition(frameIndex: -1, timeSeconds: 0)
        }

        var currentIndex = stateLock.withLockUnchecked {
            $0.replaySession?.currentFrameIndex ?? -1
        }
        var currentTime = stateLock.withLockUnchecked {
            $0.replaySession?.currentTimeSeconds ?? 0
        }

        if currentIndex < 0 {
            await runtimeEngine.reset(stopVoiceDictation: false)
            await ingestFrame(frames[0])
            currentIndex = 0
            currentTime = frameTimes[0]
            stateLock.withLockUnchecked { state in
                state.replaySession?.currentFrameIndex = 0
                state.replaySession?.currentTimeSeconds = currentTime
            }
            onProgress?(
                RuntimeReplayPosition(
                    frameIndex: 0,
                    timeSeconds: currentTime
                )
            )
        }

        while currentIndex + 1 < frames.count {
            try Task.checkCancellation()
            let nextIndex = currentIndex + 1
            let nextTime = frameTimes[nextIndex]
            if nextTime > currentTime {
                let waitStartUptime = DispatchTime.now().uptimeNanoseconds
                let waitStartTime = currentTime
                let sleepChunkNanoseconds: UInt64 = 16_000_000
                while currentTime < nextTime {
                    try Task.checkCancellation()
                    let nowUptime = DispatchTime.now().uptimeNanoseconds
                    let elapsedNanoseconds = nowUptime >= waitStartUptime ? nowUptime - waitStartUptime : 0
                    let elapsedSeconds = Double(elapsedNanoseconds) / 1_000_000_000
                    let advancedTime = min(nextTime, waitStartTime + elapsedSeconds)
                    if advancedTime > currentTime {
                        currentTime = advancedTime
                        stateLock.withLockUnchecked { state in
                            state.replaySession?.currentTimeSeconds = currentTime
                        }
                        onProgress?(
                            RuntimeReplayPosition(
                                frameIndex: currentIndex,
                                timeSeconds: currentTime
                            )
                        )
                    }
                    guard currentTime < nextTime else { break }

                    let remainingSeconds = nextTime - currentTime
                    let remainingNanosecondsDouble = remainingSeconds * 1_000_000_000
                    if remainingNanosecondsDouble < 1 {
                        continue
                    }
                    let remainingNanoseconds = UInt64(
                        min(remainingNanosecondsDouble.rounded(.up), Double(UInt64.max))
                    )
                    try await Task.sleep(
                        nanoseconds: min(sleepChunkNanoseconds, max(1, remainingNanoseconds))
                    )
                }
            }

            await ingestFrame(frames[nextIndex])
            currentIndex = nextIndex
            currentTime = nextTime
            stateLock.withLockUnchecked { state in
                state.replaySession?.currentFrameIndex = currentIndex
                state.replaySession?.currentTimeSeconds = currentTime
            }
            onProgress?(
                RuntimeReplayPosition(
                    frameIndex: currentIndex,
                    timeSeconds: currentTime
                )
            )
        }

        return RuntimeReplayPosition(
            frameIndex: currentIndex,
            timeSeconds: currentTime
        )
    }

    func endReplaySession() async throws {
        let session = stateLock.withLockUnchecked { state -> ReplaySession? in
            let current = state.replaySession
            state.replaySession = nil
            state.replayPlaybackInProgress = false
            return current
        }
        guard let session else { return }
        try await restoreRuntimeAfterReplay(
            wasRunning: session.wasRuntimeRunningBeforeSession
        )
    }

    private func frameIndex(
        forTime timeSeconds: Double,
        frameTimes: [Double]
    ) -> Int {
        guard !frameTimes.isEmpty else {
            return -1
        }

        if timeSeconds <= frameTimes[0] {
            return 0
        }
        let lastIndex = frameTimes.count - 1
        if timeSeconds >= frameTimes[lastIndex] {
            return lastIndex
        }

        var low = 0
        var high = lastIndex
        var result = 0
        while low <= high {
            let mid = (low + high) / 2
            if frameTimes[mid] <= timeSeconds {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    private func ingestFrame(_ frame: RuntimeRawFrame) async {
        _ = await renderSnapshotService.ingest(
            frame,
            runtimeEngine: runtimeEngine
        )
    }

    private func restoreRuntimeAfterReplay(wasRunning: Bool) async throws {
        if wasRunning {
            let restarted = inputRuntimeService.start()
            guard restarted else {
                throw RuntimeCaptureReplayError.unableToRestartRuntimeAfterReplay
            }
            await runtimeEngine.setListening(true)
        } else {
            await runtimeEngine.setListening(false)
            await runtimeEngine.reset(stopVoiceDictation: false)
        }
    }
}
