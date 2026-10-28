import Foundation

public struct ReplayFixtureMeta: Sendable, Equatable {
    public let schema: String
    public let capturedAt: String
    public let platform: String
    public let source: String
    public let framesCaptured: Int

    public init(schema: String, capturedAt: String, platform: String, source: String, framesCaptured: Int) {
        self.schema = schema
        self.capturedAt = capturedAt
        self.platform = platform
        self.source = source
        self.framesCaptured = framesCaptured
    }
}

public struct ReplayContactRecord: Sendable, Equatable {
    public let id: Int
    public let x: Double
    public let y: Double
    public let total: Double
    public let pressure: Double
    public let majorAxis: Double
    public let minorAxis: Double
    public let angle: Double
    public let density: Double
    public let state: String

    public init(
        id: Int,
        x: Double,
        y: Double,
        total: Double,
        pressure: Double,
        majorAxis: Double,
        minorAxis: Double,
        angle: Double,
        density: Double,
        state: String
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.total = total
        self.pressure = pressure
        self.majorAxis = majorAxis
        self.minorAxis = minorAxis
        self.angle = angle
        self.density = density
        self.state = state
    }
}

public struct ReplayFrameRecord: Sendable, Equatable {
    public let seq: Int
    public let timestampSec: Double
    public let deviceID: String
    public let deviceNumericID: UInt64
    public let deviceIndex: Int
    public let contacts: [ReplayContactRecord]

    public init(
        seq: Int,
        timestampSec: Double,
        deviceID: String,
        deviceNumericID: UInt64,
        deviceIndex: Int,
        contacts: [ReplayContactRecord]
    ) {
        self.seq = seq
        self.timestampSec = timestampSec
        self.deviceID = deviceID
        self.deviceNumericID = deviceNumericID
        self.deviceIndex = deviceIndex
        self.contacts = contacts
    }
}

public struct ReplayFixture: Sendable, Equatable {
    public let meta: ReplayFixtureMeta
    public let frames: [ReplayFrameRecord]

    public init(meta: ReplayFixtureMeta, frames: [ReplayFrameRecord]) {
        self.meta = meta
        self.frames = frames
    }
}

public enum ReplayFixtureError: Error, Equatable, CustomStringConvertible {
    case invalidSchema(line: Int, value: String)
    case invalidSequence(expected: Int, actual: Int)
    case metaFrameCountMismatch(expected: Int, actual: Int)
    case invalidATPCapture(reason: String)
    case unsupportedATPCaptureVersion(actual: Int32)
    case invalidStateEncoding(state: String)

    public var description: String {
        switch self {
        case let .invalidSchema(line, value):
            return "unsupported schema '\(value)' at line \(line)"
        case let .invalidSequence(expected, actual):
            return "invalid sequence: expected \(expected), got \(actual)"
        case let .metaFrameCountMismatch(expected, actual):
            return "meta framesCaptured mismatch: expected \(expected), got \(actual)"
        case let .invalidATPCapture(reason):
            return "invalid atpcap: \(reason)"
        case let .unsupportedATPCaptureVersion(actual):
            return "unsupported atpcap version \(actual)"
        case let .invalidStateEncoding(state):
            return "cannot encode non-canonical state '\(state)'"
        }
    }
}

public enum ReplayFixtureParser {
    public static let schema = "g2k-replay-v1"

    public static let canonicalStateOrder: [String] = [
        "notTouching",
        "starting",
        "hovering",
        "making",
        "touching",
        "breaking",
        "lingering",
        "leaving"
    ]
    public static let canonicalStates: Set<String> = Set(canonicalStateOrder)
    private static let canonicalStateCodeByName: [String: UInt8] = {
        var map: [String: UInt8] = [:]
        map.reserveCapacity(canonicalStateOrder.count)
        for (index, label) in canonicalStateOrder.enumerated() {
            map[label] = UInt8(index)
        }
        return map
    }()

    public static func load(from url: URL) throws -> ReplayFixture {
        let payload = try Data(contentsOf: url)
        guard ATPCaptureCodec.isATPCapture(payload) else {
            throw ReplayFixtureError.invalidATPCapture(reason: "capture magic mismatch (expected ATPCAP01)")
        }
        return try ATPCaptureCodec.parse(data: payload)
    }

    public static func canonicalState(rawValue: UInt) -> String {
        guard rawValue < canonicalStateOrder.count else {
            return "notTouching"
        }
        return canonicalStateOrder[Int(rawValue)]
    }

    public static func canonicalState(code: UInt8) -> String? {
        guard Int(code) < canonicalStateOrder.count else {
            return nil
        }
        return canonicalStateOrder[Int(code)]
    }

    public static func canonicalStateCode(state: String) -> UInt8? {
        canonicalStateCodeByName[state]
    }
}

public struct SidePair<Value: Sendable>: Sendable {
    public var left: Value
    public var right: Value

    public init(left: Value, right: Value) {
        self.left = left
        self.right = right
    }
}

public enum RuntimeIntentMode: String, Sendable {
    case idle
    case keyCandidate
    case typing
    case mouse
    case gesture
}

public struct RuntimeRawContact: Sendable {
    public var id: Int32
    public var posX: Float
    public var posY: Float
    public var pressure: Float
    public var majorAxis: Float
    public var minorAxis: Float
    public var angle: Float
    public var density: Float
    public var state: String

    public init(
        id: Int32,
        posX: Float,
        posY: Float,
        pressure: Float,
        majorAxis: Float,
        minorAxis: Float,
        angle: Float,
        density: Float,
        state: String
    ) {
        self.id = id
        self.posX = posX
        self.posY = posY
        self.pressure = pressure
        self.majorAxis = majorAxis
        self.minorAxis = minorAxis
        self.angle = angle
        self.density = density
        self.state = state
    }
}

public struct RuntimeRawFrame: Sendable {
    public var sequence: UInt64
    public var timestamp: TimeInterval
    public var deviceNumericID: UInt64
    public var deviceIndex: Int
    public var contacts: [RuntimeRawContact]

    public init(
        sequence: UInt64,
        timestamp: TimeInterval,
        deviceNumericID: UInt64,
        deviceIndex: Int,
        contacts: [RuntimeRawContact]
    ) {
        self.sequence = sequence
        self.timestamp = timestamp
        self.deviceNumericID = deviceNumericID
        self.deviceIndex = deviceIndex
        self.contacts = contacts
    }
}

public struct RuntimeDiagnosticsCounters: Sendable {
    public var captureFrames: UInt64 = 0

    public init() {}
}

public struct RuntimeRenderSnapshot: Sendable {
    public var revision: UInt64 = 0
    public var leftContactCount: Int = 0
    public var rightContactCount: Int = 0
    public var leftIntent: RuntimeIntentMode = .idle
    public var rightIntent: RuntimeIntentMode = .idle

    public init() {}
}

public struct RuntimeStatusSnapshot: Sendable {
    public var intentBySide: SidePair<RuntimeIntentMode> = SidePair(left: .idle, right: .idle)
    public var contactCountBySide: SidePair<Int> = SidePair(left: 0, right: 0)
    public var diagnostics: RuntimeDiagnosticsCounters = RuntimeDiagnosticsCounters()

    public init() {}
}

public protocol EngineActorBoundary: Sendable {
    func ingest(_ frame: RuntimeRawFrame) async
    func renderSnapshot() async -> RuntimeRenderSnapshot
    func statusSnapshot() async -> RuntimeStatusSnapshot
}

public actor EngineActor: EngineActorBoundary {
    private var latestRender = RuntimeRenderSnapshot()
    private var latestStatus = RuntimeStatusSnapshot()

    public init() {}

    public func ingest(_ frame: RuntimeRawFrame) async {
        let contactCount = frame.contacts.count
        if frame.deviceIndex == 0 {
            latestStatus.contactCountBySide.left = contactCount
            latestStatus.intentBySide.left = Self.intent(for: contactCount)
        } else {
            latestStatus.contactCountBySide.right = contactCount
            latestStatus.intentBySide.right = Self.intent(for: contactCount)
        }
        latestStatus.diagnostics.captureFrames &+= 1

        latestRender.revision &+= 1
        latestRender.leftContactCount = latestStatus.contactCountBySide.left
        latestRender.rightContactCount = latestStatus.contactCountBySide.right
        latestRender.leftIntent = latestStatus.intentBySide.left
        latestRender.rightIntent = latestStatus.intentBySide.right
    }

    public func renderSnapshot() async -> RuntimeRenderSnapshot {
        latestRender
    }

    public func statusSnapshot() async -> RuntimeStatusSnapshot {
        latestStatus
    }

    private static func intent(for contactCount: Int) -> RuntimeIntentMode {
        switch contactCount {
        case ...0:
            return .idle
        case 1:
            return .keyCandidate
        default:
            return .typing
        }
    }
}

public struct ReplayTranscriptRecord: Sendable, Equatable {
    public let seq: UInt64
    public let deviceIndex: Int
    public let contactCount: Int
    public let renderRevision: UInt64
    public let leftIntent: String
    public let rightIntent: String
    public let leftContacts: Int
    public let rightContacts: Int
    public let captureFrames: UInt64

    public init(
        seq: UInt64,
        deviceIndex: Int,
        contactCount: Int,
        renderRevision: UInt64,
        leftIntent: String,
        rightIntent: String,
        leftContacts: Int,
        rightContacts: Int,
        captureFrames: UInt64
    ) {
        self.seq = seq
        self.deviceIndex = deviceIndex
        self.contactCount = contactCount
        self.renderRevision = renderRevision
        self.leftIntent = leftIntent
        self.rightIntent = rightIntent
        self.leftContacts = leftContacts
        self.rightContacts = rightContacts
        self.captureFrames = captureFrames
    }
}

public enum ReplayHarnessRunner {
    public static func run(
        fixture: ReplayFixture,
        engine: any EngineActorBoundary = EngineActor()
    ) async -> [ReplayTranscriptRecord] {
        var transcript: [ReplayTranscriptRecord] = []
        transcript.reserveCapacity(fixture.frames.count)

        for frame in fixture.frames {
            let runtimeFrame = RuntimeRawFrame(
                sequence: UInt64(frame.seq),
                timestamp: frame.timestampSec,
                deviceNumericID: frame.deviceNumericID,
                deviceIndex: frame.deviceIndex,
                contacts: frame.contacts.map { contact in
                    RuntimeRawContact(
                        id: Int32(contact.id),
                        posX: Float(contact.x),
                        posY: Float(contact.y),
                        pressure: Float(contact.pressure),
                        majorAxis: Float(contact.majorAxis),
                        minorAxis: Float(contact.minorAxis),
                        angle: Float(contact.angle),
                        density: Float(contact.density),
                        state: contact.state
                    )
                }
            )

            await engine.ingest(runtimeFrame)
            let render = await engine.renderSnapshot()
            let status = await engine.statusSnapshot()

            transcript.append(
                ReplayTranscriptRecord(
                    seq: runtimeFrame.sequence,
                    deviceIndex: runtimeFrame.deviceIndex,
                    contactCount: runtimeFrame.contacts.count,
                    renderRevision: render.revision,
                    leftIntent: render.leftIntent.rawValue,
                    rightIntent: render.rightIntent.rawValue,
                    leftContacts: status.contactCountBySide.left,
                    rightContacts: status.contactCountBySide.right,
                    captureFrames: status.diagnostics.captureFrames
                )
            )
        }

        return transcript
    }

    public static func transcriptJSONLines(
        fixture: ReplayFixture,
        transcript: [ReplayTranscriptRecord]
    ) -> [String] {
        let meta = TranscriptMetaLine(
            schema: ReplayFixtureParser.schema,
            source: fixture.meta.source,
            platform: fixture.meta.platform,
            capturedAt: fixture.meta.capturedAt,
            frames: transcript.count
        )
        var lines: [String] = []
        if let metaLine = jsonLine(meta) {
            lines.append(metaLine)
        }

        for record in transcript {
            let payload = TranscriptFrameLine(
                schema: ReplayFixtureParser.schema,
                seq: Int(record.seq),
                deviceIndex: record.deviceIndex,
                contactCount: record.contactCount,
                renderRevision: Int(record.renderRevision),
                leftIntent: record.leftIntent,
                rightIntent: record.rightIntent,
                leftContacts: record.leftContacts,
                rightContacts: record.rightContacts,
                captureFrames: Int(record.captureFrames)
            )
            if let line = jsonLine(payload) {
                lines.append(line)
            }
        }

        return lines
    }

    private struct TranscriptMetaLine: Encodable {
        let type = "transcriptMeta"
        let schema: String
        let source: String
        let platform: String
        let capturedAt: String
        let frames: Int
    }

    private struct TranscriptFrameLine: Encodable {
        let type = "transcriptFrame"
        let schema: String
        let seq: Int
        let deviceIndex: Int
        let contactCount: Int
        let renderRevision: Int
        let leftIntent: String
        let rightIntent: String
        let leftContacts: Int
        let rightContacts: Int
        let captureFrames: Int
    }

    private static func jsonLine<T: Encodable>(_ object: T) -> String? {
        let encoder = JSONEncoder()
        if #available(macOS 10.13, *) {
            encoder.outputFormatting = [.sortedKeys]
        }
        guard let data = try? encoder.encode(object),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }
}
