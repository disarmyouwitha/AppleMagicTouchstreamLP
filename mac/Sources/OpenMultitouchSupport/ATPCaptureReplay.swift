import Foundation
import OpenMultitouchSupportXCF

public enum ATPCaptureSideHint: UInt8, Sendable {
    case unknown = 0
    case left = 1
    case right = 2
}

public enum ATPCaptureDecoderProfile: UInt8, Sendable {
    case legacy = 1
    case official = 2
}

public struct ATPCaptureReplayFrame: Sendable {
    public let offsetSeconds: TimeInterval
    public let deviceIndex: Int
    public let deviceHash: UInt32
    public let sideHint: ATPCaptureSideHint
    public let touches: [OMSRawTouch]
}

public struct ATPCaptureReplayStats: Sendable, Equatable {
    public let recordsRead: Int
    public let framesParsed: Int
    public let droppedInvalidSize: Int
    public let droppedNonMultitouch: Int
    public let droppedParseError: Int
}

public struct ATPCaptureReplayData: Sendable {
    public let sourcePath: String
    public let frames: [ATPCaptureReplayFrame]
    public let stats: ATPCaptureReplayStats
    public let fingerprint: UInt64
}

public enum ATPCaptureReplayLoader {
    public static func load(_ capturePath: String) throws -> ATPCaptureReplayData {
        let fullPath = URL(fileURLWithPath: capturePath).standardizedFileURL.path
        let bytes = Array(try Data(contentsOf: URL(fileURLWithPath: fullPath), options: .mappedIfSafe))
        var cursor = ByteCursor(bytes: bytes)
        let header = try parseHeader(cursor: &cursor)

        var recordsRead = 0
        var framesParsed = 0
        var droppedInvalidSize = 0
        var droppedNonMultitouch = 0
        let droppedParseError = 0
        var frames: [ATPCaptureReplayFrame] = []
        frames.reserveCapacity(4096)
        var sideMapper = ReplaySideMapper()
        var firstArrivalTicks: Int64?
        var previousTouchesBySide = ReplaySidePair<[UInt32: ActiveTouchState]>(left: [:], right: [:])
        var fingerprint: UInt64 = 14695981039346656037

        while cursor.remaining > 0 {
            let record = try parseRecord(cursor: &cursor)
            recordsRead += 1
            if record.payload.isEmpty {
                droppedInvalidSize += 1
                continue
            }

            guard let decoded = decodeFrame(
                payload: record.payload,
                deviceInfo: RawInputDeviceInfo(
                    vendorId: record.vendorId,
                    productId: record.productId,
                    usagePage: record.usagePage,
                    usage: record.usage
                ),
                preferredProfile: record.decoderProfile
            ) else {
                droppedNonMultitouch += 1
                continue
            }

            framesParsed += 1
            if firstArrivalTicks == nil {
                firstArrivalTicks = record.arrivalQpcTicks
            }
            let baseTicks = firstArrivalTicks ?? record.arrivalQpcTicks
            let relativeTicks = max(Int64(0), record.arrivalQpcTicks - baseTicks)
            let offsetSeconds = Double(relativeTicks) / Double(max(Int64(1), header.qpcFrequency))

            let side = sideMapper.resolve(
                deviceIndex: Int(record.deviceIndex),
                deviceHash: record.deviceHash,
                sideHint: record.sideHint
            )
            let syntheticDeviceIndex = side == .left ? 0 : 1
            let currentTouches = decodeActiveTouches(from: decoded.frame)
            let previousTouches = previousTouchesBySide[side]
            let touches = synthesizeTouches(
                current: currentTouches,
                previous: previousTouches
            )
            previousTouchesBySide[side] = currentTouches

            frames.append(
                ATPCaptureReplayFrame(
                    offsetSeconds: offsetSeconds,
                    deviceIndex: syntheticDeviceIndex,
                    deviceHash: record.deviceHash,
                    sideHint: record.sideHint,
                    touches: touches
                )
            )

            fingerprint = mix(fingerprint, UInt64(record.deviceHash))
            fingerprint = mix(fingerprint, UInt64(UInt32(bitPattern: record.deviceIndex)))
            fingerprint = mix(fingerprint, UInt64(decoded.frame.reportId))
            fingerprint = mix(fingerprint, UInt64(decoded.frame.scanTime))
            fingerprint = mix(fingerprint, UInt64(decoded.frame.contactCount))
            fingerprint = mix(fingerprint, UInt64(decoded.frame.isButtonClicked))
            let count = min(decoded.frame.contacts.count, Int(decoded.frame.contactCount))
            for index in 0..<count {
                let contact = decoded.frame.contacts[index]
                fingerprint = mix(fingerprint, UInt64(contact.flags))
                fingerprint = mix(fingerprint, UInt64(contact.id))
                fingerprint = mix(fingerprint, UInt64(contact.x))
                fingerprint = mix(fingerprint, UInt64(contact.y))
            }
        }

        let stats = ATPCaptureReplayStats(
            recordsRead: recordsRead,
            framesParsed: framesParsed,
            droppedInvalidSize: droppedInvalidSize,
            droppedNonMultitouch: droppedNonMultitouch,
            droppedParseError: droppedParseError
        )
        return ATPCaptureReplayData(
            sourcePath: fullPath,
            frames: frames,
            stats: stats,
            fingerprint: fingerprint
        )
    }
}

private struct CaptureHeader {
    let version: Int32
    let qpcFrequency: Int64
}

private struct CaptureRecord {
    let arrivalQpcTicks: Int64
    let deviceIndex: Int32
    let deviceHash: UInt32
    let vendorId: UInt32
    let productId: UInt32
    let usagePage: UInt16
    let usage: UInt16
    let sideHint: ATPCaptureSideHint
    let decoderProfile: ATPCaptureDecoderProfile
    let payload: [UInt8]
}

private enum CaptureError: Error {
    case invalidHeader
    case unsupportedVersion(Int32)
    case truncatedRecordHeader(offset: Int)
    case truncatedRecordPayload(offset: Int, length: Int)
    case invalidPayloadLength(Int)
}

private struct ByteCursor {
    let bytes: [UInt8]
    var offset: Int = 0

    var remaining: Int {
        bytes.count - offset
    }

    mutating func readUInt8() throws -> UInt8 {
        guard remaining >= 1 else {
            throw CaptureError.invalidHeader
        }
        let value = bytes[offset]
        offset += 1
        return value
    }

    mutating func readUInt16LE() throws -> UInt16 {
        guard remaining >= 2 else {
            throw CaptureError.invalidHeader
        }
        let b0 = UInt16(bytes[offset])
        let b1 = UInt16(bytes[offset + 1]) << 8
        offset += 2
        return b0 | b1
    }

    mutating func readUInt32LE() throws -> UInt32 {
        guard remaining >= 4 else {
            throw CaptureError.invalidHeader
        }
        let b0 = UInt32(bytes[offset])
        let b1 = UInt32(bytes[offset + 1]) << 8
        let b2 = UInt32(bytes[offset + 2]) << 16
        let b3 = UInt32(bytes[offset + 3]) << 24
        offset += 4
        return b0 | b1 | b2 | b3
    }

    mutating func readInt32LE() throws -> Int32 {
        Int32(bitPattern: try readUInt32LE())
    }

    mutating func readUInt64LE() throws -> UInt64 {
        guard remaining >= 8 else {
            throw CaptureError.invalidHeader
        }
        let b0 = UInt64(bytes[offset])
        let b1 = UInt64(bytes[offset + 1]) << 8
        let b2 = UInt64(bytes[offset + 2]) << 16
        let b3 = UInt64(bytes[offset + 3]) << 24
        let b4 = UInt64(bytes[offset + 4]) << 32
        let b5 = UInt64(bytes[offset + 5]) << 40
        let b6 = UInt64(bytes[offset + 6]) << 48
        let b7 = UInt64(bytes[offset + 7]) << 56
        offset += 8
        return b0 | b1 | b2 | b3 | b4 | b5 | b6 | b7
    }

    mutating func readInt64LE() throws -> Int64 {
        Int64(bitPattern: try readUInt64LE())
    }

    mutating func readBytes(_ count: Int) throws -> [UInt8] {
        guard count >= 0, remaining >= count else {
            throw CaptureError.invalidHeader
        }
        let value = Array(bytes[offset..<(offset + count)])
        offset += count
        return value
    }
}

private func parseHeader(cursor: inout ByteCursor) throws -> CaptureHeader {
    let magic = try cursor.readBytes(8)
    if String(bytes: magic, encoding: .ascii) != "ATPCAP01" {
        throw CaptureError.invalidHeader
    }
    let version = try cursor.readInt32LE()
    if version != 2 {
        throw CaptureError.unsupportedVersion(version)
    }
    let qpcFrequency = try cursor.readInt64LE()
    return CaptureHeader(version: version, qpcFrequency: qpcFrequency)
}

private func parseRecord(cursor: inout ByteCursor) throws -> CaptureRecord {
    let headerOffset = cursor.offset
    guard cursor.remaining >= 34 else {
        throw CaptureError.truncatedRecordHeader(offset: headerOffset)
    }
    let payloadLength = Int(try cursor.readInt32LE())
    if payloadLength < 0 || payloadLength > 64 * 1024 {
        throw CaptureError.invalidPayloadLength(payloadLength)
    }

    let arrivalQpcTicks = try cursor.readInt64LE()
    let deviceIndex = try cursor.readInt32LE()
    let deviceHash = try cursor.readUInt32LE()
    let vendorId = try cursor.readUInt32LE()
    let productId = try cursor.readUInt32LE()
    let usagePage = try cursor.readUInt16LE()
    let usage = try cursor.readUInt16LE()
    let sideHintRaw = try cursor.readUInt8()
    let profileRaw = try cursor.readUInt8()

    guard cursor.remaining >= payloadLength else {
        throw CaptureError.truncatedRecordPayload(offset: cursor.offset, length: payloadLength)
    }
    let payload = try cursor.readBytes(payloadLength)
    let sideHint = ATPCaptureSideHint(rawValue: sideHintRaw) ?? .unknown
    let profile = ATPCaptureDecoderProfile(rawValue: profileRaw) ?? .official

    return CaptureRecord(
        arrivalQpcTicks: arrivalQpcTicks,
        deviceIndex: deviceIndex,
        deviceHash: deviceHash,
        vendorId: vendorId,
        productId: productId,
        usagePage: usagePage,
        usage: usage,
        sideHint: sideHint,
        decoderProfile: profile,
        payload: payload
    )
}

private struct RawInputDeviceInfo {
    let vendorId: UInt32
    let productId: UInt32
    let usagePage: UInt16
    let usage: UInt16
}

private struct PtpContact {
    let flags: UInt8
    let contactId: UInt32
    let x: UInt16
    let y: UInt16

    var tipSwitch: Bool {
        (flags & 0x02) != 0
    }
}

private struct PtpReport {
    static let maxContacts = 5
    static let expectedSize = 50

    let reportId: UInt8
    let contacts: [PtpContact]
    let scanTime: UInt16
    let contactCount: UInt8
    let isButtonClicked: UInt8

    static func tryParse(_ payload: [UInt8], offset: Int) -> PtpReport? {
        guard offset >= 0, payload.count - offset >= expectedSize else {
            return nil
        }
        let reportId = payload[offset]
        var contacts: [PtpContact] = []
        contacts.reserveCapacity(maxContacts)
        var cursor = offset + 1
        for _ in 0..<maxContacts {
            let flags = payload[cursor]
            cursor += 1
            let contactId = readUInt32LE(payload, cursor)
            cursor += 4
            let x = readUInt16LE(payload, cursor)
            cursor += 2
            let y = readUInt16LE(payload, cursor)
            cursor += 2
            contacts.append(PtpContact(flags: flags, contactId: contactId, x: x, y: y))
        }
        let scanTime = readUInt16LE(payload, cursor)
        cursor += 2
        let contactCount = payload[cursor]
        cursor += 1
        let isButtonClicked = payload[cursor]
        return PtpReport(
            reportId: reportId,
            contacts: contacts,
            scanTime: scanTime,
            contactCount: contactCount,
            isButtonClicked: isButtonClicked
        )
    }

    var clampedContactCount: Int {
        min(Int(contactCount), Self.maxContacts)
    }
}

private struct DecodedContact {
    let id: UInt32
    let x: UInt16
    let y: UInt16
    let flags: UInt8
    let pressure: UInt8
    let phase: UInt8
}

private struct DecodedFrame {
    let reportId: UInt8
    let scanTime: UInt16
    let contactCount: UInt8
    let isButtonClicked: UInt8
    var contacts: [DecodedContact]
}

private struct TrackpadDecodeResult {
    let frame: DecodedFrame
}

private let reportIdMultitouch: UInt8 = 0x05
private let usagePageDigitizer: UInt16 = 0x0D
private let usageTouchpad: UInt16 = 0x05
private let officialMaxRawX = 14720
private let officialMaxRawY = 10240
private let replayMaxX: UInt16 = 7612
private let replayMaxY: UInt16 = 5065
private let maxEmbeddedScanOffset = 96
private let maxReasonableX = 20000
private let maxReasonableY = 15000

private func decodeFrame(
    payload: [UInt8],
    deviceInfo: RawInputDeviceInfo,
    preferredProfile: ATPCaptureDecoderProfile
) -> TrackpadDecodeResult? {
    if payload.isEmpty {
        return nil
    }
    if preferredProfile == .legacy {
        return tryDecodePtp(
            payload: payload,
            deviceInfo: deviceInfo,
            profile: .legacy,
            strictLegacyValidation: false
        )
    }

    if let official = tryDecodePtp(
        payload: payload,
        deviceInfo: deviceInfo,
        profile: .official,
        strictLegacyValidation: true
    ) {
        return official
    }
    if let legacy = tryDecodePtp(
        payload: payload,
        deviceInfo: deviceInfo,
        profile: .legacy,
        strictLegacyValidation: false
    ) {
        return legacy
    }
    return tryDecodeAppleNineByte(payload: payload, deviceInfo: deviceInfo)
}

private func tryDecodePtp(
    payload: [UInt8],
    deviceInfo: RawInputDeviceInfo,
    profile: ATPCaptureDecoderProfile,
    strictLegacyValidation: Bool
) -> TrackpadDecodeResult? {
    guard payload.count >= PtpReport.expectedSize else {
        return nil
    }
    if payload[0] == reportIdMultitouch,
       let decoded = tryParsePtpAtOffset(
        payload: payload,
        offset: 0,
        deviceInfo: deviceInfo,
        profile: profile,
        strictLegacyValidation: strictLegacyValidation
       ) {
        return decoded
    }

    let maxOffset = min(payload.count - PtpReport.expectedSize, maxEmbeddedScanOffset)
    if maxOffset < 1 {
        return nil
    }
    for offset in 1...maxOffset where payload[offset] == reportIdMultitouch {
        if let decoded = tryParsePtpAtOffset(
            payload: payload,
            offset: offset,
            deviceInfo: deviceInfo,
            profile: profile,
            strictLegacyValidation: strictLegacyValidation
        ) {
            return decoded
        }
    }
    return nil
}

private func tryParsePtpAtOffset(
    payload: [UInt8],
    offset: Int,
    deviceInfo: RawInputDeviceInfo,
    profile: ATPCaptureDecoderProfile,
    strictLegacyValidation: Bool
) -> TrackpadDecodeResult? {
    guard offset >= 0,
          offset <= payload.count - PtpReport.expectedSize,
          payload[offset] == reportIdMultitouch,
          let report = PtpReport.tryParse(payload, offset: offset) else {
        return nil
    }
    if profile == .official {
        guard looksReasonableOfficial(report) else { return nil }
    } else {
        guard looksReasonableLegacy(report, strictValidation: strictLegacyValidation) else { return nil }
    }

    var frame = DecodedFrame(
        reportId: report.reportId,
        scanTime: report.scanTime,
        contactCount: report.contactCount,
        isButtonClicked: report.isButtonClicked,
        contacts: report.contacts.map {
            DecodedContact(
                id: $0.contactId,
                x: $0.x,
                y: $0.y,
                flags: $0.flags,
                pressure: 0,
                phase: 0
            )
        }
    )
    if profile == .official {
        normalizeOfficialTouchFields(frame: &frame, payload: payload, deviceInfo: deviceInfo, offset: offset)
    } else {
        normalizeLikelyPackedContactIds(frame: &frame)
    }
    return TrackpadDecodeResult(frame: frame)
}

private func looksReasonableLegacy(_ report: PtpReport, strictValidation: Bool) -> Bool {
    if report.contactCount > UInt8(PtpReport.maxContacts) {
        return false
    }
    let count = report.clampedContactCount
    if !strictValidation {
        for index in 0..<count {
            let contact = report.contacts[index]
            if contact.x > maxReasonableX || contact.y > maxReasonableY {
                return false
            }
        }
        return true
    }

    var tipContacts = 0
    for index in 0..<PtpReport.maxContacts {
        let contact = report.contacts[index]
        if !contact.tipSwitch {
            continue
        }
        tipContacts += 1
        if contact.x > maxReasonableX || contact.y > maxReasonableY {
            return false
        }
    }
    if report.contactCount == 0 {
        return tipContacts == 0
    }
    return tipContacts > 0 && tipContacts <= report.clampedContactCount
}

private func looksReasonableOfficial(_ report: PtpReport) -> Bool {
    if report.contactCount > UInt8(PtpReport.maxContacts) {
        return false
    }
    let count = report.clampedContactCount
    if count == 0 {
        return true
    }
    for index in 0..<count {
        let contact = report.contacts[index]
        if contact.x != 0 || contact.y != 0 || contact.flags != 0 || contact.contactId != 0 {
            return true
        }
    }
    return false
}

private func tryDecodeAppleNineByte(
    payload: [UInt8],
    deviceInfo: RawInputDeviceInfo
) -> TrackpadDecodeResult? {
    guard isTargetVidPid(deviceInfo.vendorId, deviceInfo.productId),
          UInt16(deviceInfo.productId) == 0x0324,
          payload.count >= 64 else {
        return nil
    }

    let baseOffsets = [9, 1]
    var bestContacts: [DecodedContact] = []
    var bestCount = 0
    for baseOffset in baseOffsets {
        if payload.count < baseOffset + 9 {
            continue
        }
        let slotCount = min(5, (payload.count - baseOffset) / 9)
        if slotCount <= 0 {
            continue
        }
        let contacts = decodeAppleNineByteSlots(payload: payload, baseOffset: baseOffset, slotCount: slotCount)
        if contacts.count > bestCount {
            bestContacts = contacts
            bestCount = contacts.count
        }
    }
    guard bestCount > 0 else {
        return nil
    }

    let frame = DecodedFrame(
        reportId: payload[0],
        scanTime: 0,
        contactCount: UInt8(bestCount),
        isButtonClicked: 0,
        contacts: bestContacts
    )
    return TrackpadDecodeResult(frame: frame)
}

private func decodeAppleNineByteSlots(
    payload: [UInt8],
    baseOffset: Int,
    slotCount: Int
) -> [DecodedContact] {
    var usedIds = Array(repeating: false, count: 16)
    var contacts: [DecodedContact] = []
    contacts.reserveCapacity(5)
    for slot in 0..<slotCount {
        let index = baseOffset + slot * 9
        let x = decodeAppleCoordinate(payload[index], payload[index + 1], payload[index + 2])
        let y = decodeAppleCoordinate(payload[index + 3], payload[index + 4], payload[index + 5])
        if x < 0 || y < 0 || x > maxReasonableX || y > maxReasonableY {
            continue
        }
        let id = Int(payload[index + 7] & 0x0F)
        if usedIds[id] {
            continue
        }
        usedIds[id] = true
        contacts.append(
            DecodedContact(
                id: UInt32(id),
                x: UInt16(x),
                y: UInt16(y),
                flags: 0x03,
                pressure: 0,
                phase: 0
            )
        )
        if contacts.count >= 5 {
            break
        }
    }
    return contacts
}

private func decodeAppleCoordinate(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8) -> Int {
    let packed = (Int(b0) << 27) | (Int(b1) << 19) | (Int(b2) << 11)
    return packed >> 22
}

private func normalizeOfficialTouchFields(
    frame: inout DecodedFrame,
    payload: [UInt8],
    deviceInfo: RawInputDeviceInfo,
    offset: Int
) {
    let isNativeTouchpadUsage = deviceInfo.usagePage == usagePageDigitizer &&
        deviceInfo.usage == usageTouchpad
    let count = min(frame.contacts.count, Int(frame.contactCount))
    var usedAssignedIds = Array(repeating: false, count: 256)
    for index in 0..<count {
        var contact = frame.contacts[index]
        let normalizedFlags = (contact.flags & 0xFC) | 0x03
        var x = contact.x
        var y = contact.y
        var pressure = contact.pressure
        var phase = contact.phase
        let assignedId: UInt32

        if !isNativeTouchpadUsage {
            let slotOffset = offset + 1 + index * 9
            if slotOffset + 8 < payload.count {
                let candidateId = payload[slotOffset]
                assignedId = assignOfficialContactId(candidateId: candidateId, usedIds: &usedAssignedIds)
                let rawX = Int(readUInt16LE(payload, slotOffset + 2))
                let rawY = Int(readUInt16LE(payload, slotOffset + 4))
                x = scaleOfficialCoordinate(value: rawX, maxRaw: officialMaxRawX, targetMax: replayMaxX)
                y = scaleOfficialCoordinate(value: rawY, maxRaw: officialMaxRawY, targetMax: replayMaxY)
                pressure = payload[slotOffset + 6]
                phase = payload[slotOffset + 7]
            } else {
                assignedId = assignOfficialContactId(candidateId: UInt8(index), usedIds: &usedAssignedIds)
            }
        } else {
            assignedId = assignOfficialContactId(candidateId: UInt8(index), usedIds: &usedAssignedIds)
        }

        contact = DecodedContact(
            id: assignedId,
            x: x,
            y: y,
            flags: normalizedFlags,
            pressure: pressure,
            phase: phase
        )
        frame.contacts[index] = contact
    }
}

private func assignOfficialContactId(candidateId: UInt8, usedIds: inout [Bool]) -> UInt32 {
    let candidate = Int(candidateId)
    if !usedIds[candidate] {
        usedIds[candidate] = true
        return UInt32(candidateId)
    }
    for index in 0..<usedIds.count where !usedIds[index] {
        usedIds[index] = true
        return UInt32(index)
    }
    return UInt32(candidateId)
}

private func scaleOfficialCoordinate(value: Int, maxRaw: Int, targetMax: UInt16) -> UInt16 {
    let clamped = min(max(value, 0), maxRaw)
    let scaled = (clamped * Int(targetMax) + maxRaw / 2) / maxRaw
    return UInt16(min(max(scaled, 0), Int(targetMax)))
}

private func normalizeLikelyPackedContactIds(frame: inout DecodedFrame) {
    let count = min(frame.contacts.count, Int(frame.contactCount))
    if count == 0 {
        return
    }
    var tipCount = 0
    var suspiciousIdCount = 0
    for index in 0..<count {
        let contact = frame.contacts[index]
        if (contact.flags & 0x02) == 0 {
            continue
        }
        tipCount += 1
        if (contact.id & 0xFF) == 0 && contact.id > 0x00FF_FFFF {
            suspiciousIdCount += 1
        }
    }
    if tipCount == 0 || suspiciousIdCount != tipCount {
        return
    }
    for index in 0..<count {
        let contact = frame.contacts[index]
        if (contact.flags & 0x02) == 0 {
            continue
        }
        frame.contacts[index] = DecodedContact(
            id: UInt32(index),
            x: contact.x,
            y: contact.y,
            flags: contact.flags,
            pressure: contact.pressure,
            phase: contact.phase
        )
    }
}

private func isTargetVidPid(_ vid: UInt32, _ pid: UInt32) -> Bool {
    let vid16 = UInt16(vid)
    let pid16 = UInt16(pid)
    let vendorMatch = vid16 == 0x8910 || vid16 == 0x05AC || vid16 == 0x004C
    if !vendorMatch {
        return false
    }
    return pid16 == 0x0265 || pid16 == 0x0324
}

private func readUInt16LE(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
    UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
}

private func readUInt32LE(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
    UInt32(bytes[offset]) |
        (UInt32(bytes[offset + 1]) << 8) |
        (UInt32(bytes[offset + 2]) << 16) |
        (UInt32(bytes[offset + 3]) << 24)
}

private struct ActiveTouchState {
    let x: Float
    let y: Float
    let pressure: Float
}

private func decodeActiveTouches(from frame: DecodedFrame) -> [UInt32: ActiveTouchState] {
    let count = min(frame.contacts.count, Int(frame.contactCount))
    var touches: [UInt32: ActiveTouchState] = [:]
    touches.reserveCapacity(count)
    for index in 0..<count {
        let contact = frame.contacts[index]
        if (contact.flags & 0x02) == 0 {
            continue
        }
        let x = min(max(Float(contact.x) / Float(replayMaxX), 0), 1)
        let y = min(max(Float(contact.y) / Float(replayMaxY), 0), 1)
        let pressure = Float(contact.pressure)
        touches[contact.id] = ActiveTouchState(x: x, y: y, pressure: pressure)
    }
    return touches
}

private func synthesizeTouches(
    current: [UInt32: ActiveTouchState],
    previous: [UInt32: ActiveTouchState]
) -> [OMSRawTouch] {
    if current.isEmpty && previous.isEmpty {
        return []
    }

    let currentIDs = current.keys.sorted()
    let previousIDs = previous.keys.sorted()
    var touches: [OMSRawTouch] = []
    touches.reserveCapacity(currentIDs.count + previousIDs.count)

    for id in currentIDs {
        guard let touch = current[id] else { continue }
        let state: OpenMTState = previous[id] == nil ? .starting : .touching
        touches.append(
            OMSRawTouch(
                id: Int32(bitPattern: id),
                posX: touch.x,
                posY: touch.y,
                total: touch.pressure,
                pressure: touch.pressure,
                majorAxis: 0,
                minorAxis: 0,
                angle: 0,
                density: 0,
                state: state
            )
        )
    }

    for id in previousIDs where current[id] == nil {
        guard let touch = previous[id] else { continue }
        touches.append(
            OMSRawTouch(
                id: Int32(bitPattern: id),
                posX: touch.x,
                posY: touch.y,
                total: touch.pressure,
                pressure: touch.pressure,
                majorAxis: 0,
                minorAxis: 0,
                angle: 0,
                density: 0,
                state: .breaking
            )
        )
    }

    return touches
}

private struct ReplayDeviceTag: Hashable {
    let deviceIndex: Int
    let deviceHash: UInt32
}

private struct ReplaySideMapper {
    private var sides: [ReplayDeviceTag: TrackpadSide] = [:]
    private var next = 0

    mutating func resolve(
        deviceIndex: Int,
        deviceHash: UInt32,
        sideHint: ATPCaptureSideHint
    ) -> TrackpadSide {
        let key = ReplayDeviceTag(deviceIndex: deviceIndex, deviceHash: deviceHash)
        if sideHint == .left {
            sides[key] = .left
            return .left
        }
        if sideHint == .right {
            sides[key] = .right
            return .right
        }
        if let existing = sides[key] {
            return existing
        }
        let side: TrackpadSide = next == 0 ? .left : .right
        next = (next + 1) % 2
        sides[key] = side
        return side
    }
}

private enum TrackpadSide {
    case left
    case right
}

private struct ReplaySidePair<Value> {
    var left: Value
    var right: Value

    subscript(_ side: TrackpadSide) -> Value {
        get { side == .left ? left : right }
        set {
            if side == .left {
                left = newValue
            } else {
                right = newValue
            }
        }
    }
}

@inline(__always)
private func mix(_ hash: UInt64, _ value: UInt64) -> UInt64 {
    var result = hash ^ value
    result &*= 1099511628211
    return result
}
