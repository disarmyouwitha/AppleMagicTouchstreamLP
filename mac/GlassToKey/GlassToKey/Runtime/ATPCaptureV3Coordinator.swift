import Dispatch
import Foundation
import OpenMultitouchSupport
import os

enum ATPCaptureV3Codec {
    struct DispatchSample: Sendable {
        let event: RuntimeDispatchEvent
        let arrivalTicks: Int64
    }

    struct CaptureData: Sendable {
        let configuration: AppKeymapProfile?
        let frameRecords: [ProcessedFrameRecord]
        let detachedDispatchEvents: [DispatchSample]

        var frameCount: Int {
            frameRecords.count
        }
    }

    struct ReplayData: Sendable {
        let configuration: AppKeymapProfile?
        let records: [ProcessedFrameRecord]
        let frameTimesSeconds: [Double]
        let durationSeconds: Double
    }

    static let fileMagic = "ATPCAP01"
    static let schema = "g2k-replay-v1"
    static let currentVersion: Int32 = 5
    static let headerSize = 20
    static let recordHeaderSize = 34
    static let defaultTickFrequency: Int64 = 1_000_000_000
    private static let metaRecordDeviceIndex: Int32 = -1
    private static let configRecordDeviceIndex: Int32 = -2
    private static let dispatchRecordDeviceIndex: Int32 = -4
    private static let processedFrameRecordDeviceIndex: Int32 = -5

    static func write(
        frames: [RuntimeRawFrame],
        to url: URL,
        tickFrequency: Int64 = defaultTickFrequency,
        platform: String = "macOS",
        source: String = "GlassToKeyMenuCapture"
    ) throws {
        let baseTimestamp = frames.first?.timestamp ?? 0
        let frameRecords = frames.map { frame in
            let ticks = Int64(((frame.timestamp - baseTimestamp) * Double(tickFrequency)).rounded())
            return ProcessedFrameRecord(
                frame: frame,
                arrivalTicks: max(0, ticks),
                ingress: nil,
                diagnostic: nil,
                dispatchEvents: [],
                renderUpdate: nil
            )
        }
        try write(
            captureData: CaptureData(
                configuration: nil,
                frameRecords: frameRecords,
                detachedDispatchEvents: []
            ),
            to: url,
            tickFrequency: tickFrequency,
            platform: platform,
            source: source
        )
    }

    static func write(
        captureData: CaptureData,
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

        let metaPayload = try encodeJSON(
            MetaPayload(
                type: "meta",
                schema: schema,
                capturedAt: iso8601Timestamp(Date()),
                platform: platform,
                source: source,
                framesCaptured: captureData.frameCount
            )
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

        if let configuration = captureData.configuration {
            let payload = try encodeJSON(
                ConfigurationPayload(
                    type: "config",
                    profile: configuration
                )
            )
            try handle.write(contentsOf: recordHeader(
                payloadLength: payload.count,
                arrivalTicks: 0,
                deviceIndex: configRecordDeviceIndex,
                deviceHash: 0,
                vendorID: 0,
                productID: 0,
                usagePage: 0,
                usage: 0,
                sideHint: 0,
                decoderProfile: 0
            ))
            try handle.write(contentsOf: payload)
        }

        for frameRecord in captureData.frameRecords {
            let payload = try encodeJSON(
                ProcessedFrameRecordPayload(
                    type: "processedFrameRecord",
                    record: frameRecord
                )
            )
            try handle.write(contentsOf: recordHeader(
                payloadLength: payload.count,
                arrivalTicks: max(0, frameRecord.arrivalTicks),
                deviceIndex: processedFrameRecordDeviceIndex,
                deviceHash: UInt32(truncatingIfNeeded: frameRecord.frame.deviceNumericID),
                vendorID: 0,
                productID: 0,
                usagePage: 0,
                usage: 0,
                sideHint: sideHintForDeviceIndex(frameRecord.frame.deviceIndex),
                decoderProfile: 0
            ))
            try handle.write(contentsOf: payload)
        }

        for dispatchEvent in captureData.detachedDispatchEvents.sorted(by: { lhs, rhs in
            if lhs.arrivalTicks == rhs.arrivalTicks {
                return (lhs.event.sourceSequence ?? 0) < (rhs.event.sourceSequence ?? 0)
            }
            return lhs.arrivalTicks < rhs.arrivalTicks
        }) {
            let payload = try encodeJSON(
                DetachedDispatchPayload(
                    type: "detachedDispatch",
                    dispatch: ProcessedDispatchEvent(
                        event: dispatchEvent.event,
                        arrivalTicks: dispatchEvent.arrivalTicks
                    )
                )
            )
            try handle.write(contentsOf: recordHeader(
                payloadLength: payload.count,
                arrivalTicks: max(0, dispatchEvent.arrivalTicks),
                deviceIndex: dispatchRecordDeviceIndex,
                deviceHash: 0,
                vendorID: 0,
                productID: 0,
                usagePage: 0,
                usage: 0,
                sideHint: 0,
                decoderProfile: 0
            ))
            try handle.write(contentsOf: payload)
        }
    }

    static func readCaptureData(from url: URL) throws -> CaptureData {
        try parseCaptureData(data: Data(contentsOf: url))
    }

    static func parseCaptureData(data: Data) throws -> CaptureData {
        let container = try readContainer(data: data)
        return try parseCaptureData(container: container).captureData
    }

    static func readReplayData(from url: URL) throws -> ReplayData {
        try parseReplayData(data: Data(contentsOf: url))
    }

    static func parseReplayData(data: Data) throws -> ReplayData {
        let container = try readContainer(data: data)
        let parsed = try parseCaptureData(container: container)
        let captureData = parsed.captureData
        let replayTimes = try replayTimelineSeconds(
            rawArrivalTicks: captureData.frameRecords.map(\.arrivalTicks),
            tickFrequency: parsed.tickFrequency
        )

        var records = captureData.frameRecords
        for index in records.indices {
            var record = records[index]
            let replayTime = replayTimes[index]
            record.frame.timestamp = replayTime
            if var diagnostic = record.diagnostic {
                diagnostic.timestamp = replayTime
                record.diagnostic = diagnostic
            }
            records[index] = record
        }
        return ReplayData(
            configuration: captureData.configuration,
            records: records,
            frameTimesSeconds: replayTimes,
            durationSeconds: replayTimes.last ?? 0
        )
    }

    static func readFrames(from url: URL) throws -> [RuntimeRawFrame] {
        try readReplayData(from: url).records.map(\.frame)
    }

    static func parseFrames(data: Data) throws -> [RuntimeRawFrame] {
        try parseReplayData(data: data).records.map(\.frame)
    }

    private static func parseCaptureData(
        container: ATPCaptureContainer
    ) throws -> (captureData: CaptureData, tickFrequency: Int64) {
        guard container.header.version == currentVersion else {
            throw RuntimeCaptureReplayError.unsupportedATPCaptureVersion(
                actual: container.header.version
            )
        }

        var configuration: AppKeymapProfile?
        var frameRecords: [ProcessedFrameRecord] = []
        frameRecords.reserveCapacity(1024)
        var detachedDispatchEvents: [DispatchSample] = []

        var expectedSequence: UInt64?
        for record in container.records {
            switch record.deviceIndex {
            case metaRecordDeviceIndex:
                _ = try decodeMetaPayload(record.payload)
            case configRecordDeviceIndex:
                configuration = try decodeJSON(
                    ConfigurationPayload.self,
                    from: record.payload,
                    context: "config"
                ).profile
            case processedFrameRecordDeviceIndex:
                var frameRecord = try decodeJSON(
                    ProcessedFrameRecordPayload.self,
                    from: record.payload,
                    context: "processed frame record"
                ).record
                frameRecord.arrivalTicks = max(0, record.arrivalTicks)
                let requiredSequence = expectedSequence ?? frameRecord.sequence
                guard frameRecord.sequence == requiredSequence else {
                    throw RuntimeCaptureReplayError.invalidATPCapture(
                        reason: "invalid sequence: expected \(requiredSequence), got \(frameRecord.sequence)"
                    )
                }
                frameRecords.append(frameRecord)
                expectedSequence = frameRecord.sequence &+ 1
            case dispatchRecordDeviceIndex:
                let detached = try decodeJSON(
                    DetachedDispatchPayload.self,
                    from: record.payload,
                    context: "detached dispatch"
                ).dispatch
                detachedDispatchEvents.append(
                    DispatchSample(
                        event: detached.event,
                        arrivalTicks: max(0, record.arrivalTicks)
                    )
                )
            default:
                throw RuntimeCaptureReplayError.invalidATPCapture(
                    reason: "unexpected record type \(record.deviceIndex)"
                )
            }
        }

        return (
            captureData: CaptureData(
                configuration: configuration,
                frameRecords: frameRecords,
                detachedDispatchEvents: detachedDispatchEvents
            ),
            tickFrequency: container.header.tickFrequency
        )
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
            records.append(
                ATPCaptureRecord(
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
                )
            )
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

    private static func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        if #available(macOS 10.13, *) {
            encoder.outputFormatting = [.sortedKeys]
        }
        return try encoder.encode(value)
    }

    private static func decodeJSON<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        context: String
    ) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw RuntimeCaptureReplayError.invalidATPCapture(
                reason: "\(context) payload decode failed: \(error.localizedDescription)"
            )
        }
    }

    private static func decodeMetaPayload(_ data: Data) throws -> MetaPayload {
        let payload = try decodeJSON(MetaPayload.self, from: data, context: "meta")
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

    private struct MetaPayload: Codable {
        let type: String
        let schema: String
        let capturedAt: String
        let platform: String
        let source: String
        let framesCaptured: Int
    }

    private struct ConfigurationPayload: Codable {
        let type: String
        let profile: AppKeymapProfile
    }

    private struct ProcessedFrameRecordPayload: Codable {
        let type: String
        let record: ProcessedFrameRecord
    }

    private struct DetachedDispatchPayload: Codable {
        let type: String
        let dispatch: ProcessedDispatchEvent
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
    private struct CaptureSession {
        let outputURL: URL
        let startedRuntimeForCapture: Bool
    }

    private struct ReplaySession {
        let sourceName: String
        let records: [ProcessedFrameRecord]
        let frameTimesSeconds: [Double]
        let durationSeconds: Double
        let wasRuntimeRunningBeforeSession: Bool
        let activeDeviceRoutingBeforeSession: RuntimeActiveDeviceRouting
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
    private let runtimeEngine: RuntimeCoreBoundary
    private let renderSnapshotService: RuntimeRenderSnapshotService
    private let stateLock = OSAllocatedUnfairLock<State>(uncheckedState: State())

    init(
        inputRuntimeService: InputRuntimeService,
        runtimeLifecycleCoordinator: RuntimeLifecycleCoordinatorService,
        runtimeEngine: RuntimeCoreBoundary,
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

    func startCapture(to outputURL: URL, configuration: AppKeymapProfile? = nil) throws {
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

        let captureStartUptime = DispatchTime.now().uptimeNanoseconds
        runtimeEngine.startCapture(
            configuration: configuration,
            startUptimeNanoseconds: captureStartUptime
        )

        stateLock.withLockUnchecked { state in
            state.captureSession = CaptureSession(
                outputURL: outputURL,
                startedRuntimeForCapture: startedRuntimeForCapture
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

        guard let captureData = await runtimeEngine.stopCapture() else {
            throw RuntimeCaptureReplayError.captureNotRunning
        }

        if session.startedRuntimeForCapture {
            _ = runtimeLifecycleCoordinator.stop(stopVoiceDictation: false)
        }

        try ATPCaptureV3Codec.write(captureData: captureData, to: session.outputURL)
        return captureData.frameCount
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
        let records = replayData.records
        let frameTimes = replayData.frameTimesSeconds
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
        let activeDeviceRoutingBeforeSession = await runtimeEngine.activeDeviceRouting()
        let replayRouting = Self.makeReplayDeviceRouting(
            configuration: replayData.configuration,
            records: records,
            fallback: activeDeviceRoutingBeforeSession
        )
        await runtimeEngine.updateActiveDevices(
            leftIndex: replayRouting.leftIndex,
            rightIndex: replayRouting.rightIndex,
            leftDeviceID: replayRouting.leftDeviceID,
            rightDeviceID: replayRouting.rightDeviceID
        )
        await runtimeEngine.setListening(true)
        await runtimeEngine.reset(stopVoiceDictation: false)

        var currentIndex = -1
        var currentTime = 0.0
        if !records.isEmpty {
            await ingestFrame(records[0])
            currentIndex = 0
            currentTime = frameTimes[0]
        }

        let session = ReplaySession(
            sourceName: sourceName,
            records: records,
            frameTimesSeconds: frameTimes,
            durationSeconds: durationSeconds,
            wasRuntimeRunningBeforeSession: wasRunning,
            activeDeviceRoutingBeforeSession: activeDeviceRoutingBeforeSession,
            currentFrameIndex: currentIndex,
            currentTimeSeconds: currentTime
        )
        stateLock.withLockUnchecked { state in
            state.replaySession = session
            state.replayPlaybackInProgress = false
        }

        return RuntimeReplaySessionInfo(
            sourceName: sourceName,
            frameCount: records.count,
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
                frameCount: session.records.count,
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

        guard !session.records.isEmpty else {
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
                await ingestFrame(session.records[index])
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

        let records = session.records
        let frameTimes = session.frameTimesSeconds
        guard !records.isEmpty else {
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
            await ingestFrame(records[0])
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

        while currentIndex + 1 < records.count {
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

            await ingestFrame(records[nextIndex])
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
        await runtimeEngine.updateActiveDevices(
            leftIndex: session.activeDeviceRoutingBeforeSession.leftIndex,
            rightIndex: session.activeDeviceRoutingBeforeSession.rightIndex,
            leftDeviceID: session.activeDeviceRoutingBeforeSession.leftDeviceID,
            rightDeviceID: session.activeDeviceRoutingBeforeSession.rightDeviceID
        )
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

    private func ingestFrame(_ record: ProcessedFrameRecord) async {
        _ = await renderSnapshotService.ingest(
            record.frame,
            runtimeEngine: runtimeEngine,
            ingress: record.ingress
        )
    }

    private static func makeReplayDeviceRouting(
        configuration: AppKeymapProfile?,
        records: [ProcessedFrameRecord],
        fallback: RuntimeActiveDeviceRouting
    ) -> RuntimeActiveDeviceRouting {
        guard let configuration else { return fallback }

        let leftDeviceID = configuration.leftDeviceID.isEmpty
            ? fallback.leftDeviceID
            : configuration.leftDeviceID
        let rightDeviceID = configuration.rightDeviceID.isEmpty
            ? fallback.rightDeviceID
            : configuration.rightDeviceID

        var leftIndex: Int?
        var rightIndex: Int?
        for record in records {
            let frame = record.frame
            let deviceID = String(frame.deviceNumericID)
            if leftIndex == nil, deviceID == configuration.leftDeviceID {
                leftIndex = frame.deviceIndex
            }
            if rightIndex == nil, deviceID == configuration.rightDeviceID {
                rightIndex = frame.deviceIndex
            }
            if leftIndex != nil, rightIndex != nil {
                break
            }
        }

        if leftIndex == nil {
            leftIndex = fallback.leftIndex
        }
        if rightIndex == nil {
            rightIndex = fallback.rightIndex
        }

        if leftIndex == nil || rightIndex == nil {
            let distinctIndices = Array(Set(records.map { $0.frame.deviceIndex })).sorted()
            if leftIndex == nil, distinctIndices.count == 1 {
                leftIndex = distinctIndices[0]
            }
            if rightIndex == nil, distinctIndices.count == 2 {
                rightIndex = distinctIndices.first(where: { $0 != leftIndex })
            }
        }

        return RuntimeActiveDeviceRouting(
            leftIndex: leftIndex,
            rightIndex: rightIndex,
            leftDeviceID: leftDeviceID,
            rightDeviceID: rightDeviceID
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
