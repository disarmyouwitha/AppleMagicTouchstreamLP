import Foundation

public struct ReplayFixtureMeta: Sendable {
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

public struct ReplayContactRecord: Sendable {
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

public struct ReplayFrameRecord: Sendable {
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

public struct ReplayFixture: Sendable {
    public let meta: ReplayFixtureMeta
    public let frames: [ReplayFrameRecord]

    public init(meta: ReplayFixtureMeta, frames: [ReplayFrameRecord]) {
        self.meta = meta
        self.frames = frames
    }
}

public enum ReplayFixtureError: Error, Equatable, CustomStringConvertible {
    case emptyFixture
    case invalidJSON(line: Int)
    case missingField(line: Int, field: String)
    case invalidFieldType(line: Int, field: String)
    case invalidSchema(line: Int, value: String)
    case invalidRecordType(line: Int, value: String)
    case invalidSequence(expected: Int, actual: Int)
    case invalidTouchCount(line: Int, expected: Int, actual: Int)
    case invalidState(line: Int, state: String)
    case metaFrameCountMismatch(expected: Int, actual: Int)

    public var description: String {
        switch self {
        case .emptyFixture:
            return "fixture is empty"
        case let .invalidJSON(line):
            return "invalid JSON at line \(line)"
        case let .missingField(line, field):
            return "missing field '\(field)' at line \(line)"
        case let .invalidFieldType(line, field):
            return "invalid type for field '\(field)' at line \(line)"
        case let .invalidSchema(line, value):
            return "unsupported schema '\(value)' at line \(line)"
        case let .invalidRecordType(line, value):
            return "unexpected record type '\(value)' at line \(line)"
        case let .invalidSequence(expected, actual):
            return "invalid sequence: expected \(expected), got \(actual)"
        case let .invalidTouchCount(line, expected, actual):
            return "touchCount mismatch at line \(line): expected \(expected), got \(actual)"
        case let .invalidState(line, state):
            return "invalid canonical state '\(state)' at line \(line)"
        case let .metaFrameCountMismatch(expected, actual):
            return "meta framesCaptured mismatch: expected \(expected), got \(actual)"
        }
    }
}

public enum ReplayFixtureParser {
    public static let schema = "g2k-replay-v1"

    public static let canonicalStates: Set<String> = [
        "notTouching",
        "starting",
        "hovering",
        "making",
        "touching",
        "breaking",
        "lingering",
        "leaving"
    ]

    public static func load(from url: URL) throws -> ReplayFixture {
        let payload = try String(contentsOf: url, encoding: .utf8)
        return try parse(jsonl: payload)
    }

    public static func parse(jsonl: String) throws -> ReplayFixture {
        let lines = jsonl.split(whereSeparator: \.isNewline)
        guard !lines.isEmpty else {
            throw ReplayFixtureError.emptyFixture
        }

        let firstObject = try parseJSONObject(line: String(lines[0]), lineNumber: 1)
        let meta = try parseMetaRecord(from: firstObject, line: 1)

        var frames: [ReplayFrameRecord] = []
        var expectedSeq = 1
        for (offset, lineSlice) in lines.dropFirst().enumerated() {
            let lineNumber = offset + 2
            let object = try parseJSONObject(line: String(lineSlice), lineNumber: lineNumber)
            let frame = try parseFrameRecord(from: object, line: lineNumber)
            if frame.seq != expectedSeq {
                throw ReplayFixtureError.invalidSequence(expected: expectedSeq, actual: frame.seq)
            }
            frames.append(frame)
            expectedSeq += 1
        }

        if meta.framesCaptured != frames.count {
            throw ReplayFixtureError.metaFrameCountMismatch(expected: meta.framesCaptured, actual: frames.count)
        }

        return ReplayFixture(meta: meta, frames: frames)
    }

    private static func parseMetaRecord(from object: [String: Any], line: Int) throws -> ReplayFixtureMeta {
        let recordType = try requiredString("type", in: object, line: line)
        guard recordType == "meta" else {
            throw ReplayFixtureError.invalidRecordType(line: line, value: recordType)
        }
        let schemaValue = try requiredString("schema", in: object, line: line)
        guard schemaValue == schema else {
            throw ReplayFixtureError.invalidSchema(line: line, value: schemaValue)
        }

        return ReplayFixtureMeta(
            schema: schemaValue,
            capturedAt: try requiredString("capturedAt", in: object, line: line),
            platform: try requiredString("platform", in: object, line: line),
            source: try requiredString("source", in: object, line: line),
            framesCaptured: try requiredInt("framesCaptured", in: object, line: line)
        )
    }

    private static func parseFrameRecord(from object: [String: Any], line: Int) throws -> ReplayFrameRecord {
        let recordType = try requiredString("type", in: object, line: line)
        guard recordType == "frame" else {
            throw ReplayFixtureError.invalidRecordType(line: line, value: recordType)
        }
        let schemaValue = try requiredString("schema", in: object, line: line)
        guard schemaValue == schema else {
            throw ReplayFixtureError.invalidSchema(line: line, value: schemaValue)
        }

        let contactObjects = try requiredArrayOfDictionaries("contacts", in: object, line: line)
        let contacts = try contactObjects.map { contactObject in
            let state = try requiredString("state", in: contactObject, line: line)
            guard canonicalStates.contains(state) else {
                throw ReplayFixtureError.invalidState(line: line, state: state)
            }
            return ReplayContactRecord(
                id: try requiredInt("id", in: contactObject, line: line),
                x: try requiredDouble("x", in: contactObject, line: line),
                y: try requiredDouble("y", in: contactObject, line: line),
                total: try requiredDouble("total", in: contactObject, line: line),
                pressure: try requiredDouble("pressure", in: contactObject, line: line),
                majorAxis: try requiredDouble("majorAxis", in: contactObject, line: line),
                minorAxis: try requiredDouble("minorAxis", in: contactObject, line: line),
                angle: try requiredDouble("angle", in: contactObject, line: line),
                density: try requiredDouble("density", in: contactObject, line: line),
                state: state
            )
        }

        let touchCount = try requiredInt("touchCount", in: object, line: line)
        if touchCount != contacts.count {
            throw ReplayFixtureError.invalidTouchCount(line: line, expected: contacts.count, actual: touchCount)
        }

        return ReplayFrameRecord(
            seq: try requiredInt("seq", in: object, line: line),
            timestampSec: try requiredDouble("timestampSec", in: object, line: line),
            deviceID: try requiredString("deviceID", in: object, line: line),
            deviceNumericID: UInt64(try requiredInt64("deviceNumericID", in: object, line: line)),
            deviceIndex: try requiredInt("deviceIndex", in: object, line: line),
            contacts: contacts
        )
    }

    private static func parseJSONObject(line: String, lineNumber: Int) throws -> [String: Any] {
        guard let data = line.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReplayFixtureError.invalidJSON(line: lineNumber)
        }
        return object
    }

    private static func requiredString(_ field: String, in object: [String: Any], line: Int) throws -> String {
        guard let value = object[field] else {
            throw ReplayFixtureError.missingField(line: line, field: field)
        }
        guard let value = value as? String else {
            throw ReplayFixtureError.invalidFieldType(line: line, field: field)
        }
        return value
    }

    private static func requiredInt(_ field: String, in object: [String: Any], line: Int) throws -> Int {
        guard let value = object[field] else {
            throw ReplayFixtureError.missingField(line: line, field: field)
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        throw ReplayFixtureError.invalidFieldType(line: line, field: field)
    }

    private static func requiredInt64(_ field: String, in object: [String: Any], line: Int) throws -> Int64 {
        guard let value = object[field] else {
            throw ReplayFixtureError.missingField(line: line, field: field)
        }
        if let number = value as? NSNumber {
            return number.int64Value
        }
        throw ReplayFixtureError.invalidFieldType(line: line, field: field)
    }

    private static func requiredDouble(_ field: String, in object: [String: Any], line: Int) throws -> Double {
        guard let value = object[field] else {
            throw ReplayFixtureError.missingField(line: line, field: field)
        }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        throw ReplayFixtureError.invalidFieldType(line: line, field: field)
    }

    private static func requiredArrayOfDictionaries(_ field: String, in object: [String: Any], line: Int) throws -> [[String: Any]] {
        guard let value = object[field] else {
            throw ReplayFixtureError.missingField(line: line, field: field)
        }
        guard let value = value as? [[String: Any]] else {
            throw ReplayFixtureError.invalidFieldType(line: line, field: field)
        }
        return value
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

public actor EngineActorStub: EngineActorBoundary {
    private var latestRender = RuntimeRenderSnapshot()
    private var latestStatus = RuntimeStatusSnapshot()

    public init() {}

    public func ingest(_ frame: RuntimeRawFrame) async {
        latestRender.revision &+= 1
        if frame.deviceIndex == 0 {
            latestStatus.contactCountBySide.left = frame.contacts.count
        } else {
            latestStatus.contactCountBySide.right = frame.contacts.count
        }
        latestStatus.diagnostics.captureFrames &+= 1
    }

    public func renderSnapshot() async -> RuntimeRenderSnapshot {
        latestRender
    }

    public func statusSnapshot() async -> RuntimeStatusSnapshot {
        latestStatus
    }
}

public struct ReplayTranscriptRecord: Sendable, Equatable {
    public let seq: UInt64
    public let deviceIndex: Int
    public let contactCount: Int
    public let renderRevision: UInt64
    public let leftContacts: Int
    public let rightContacts: Int
    public let captureFrames: UInt64

    public init(
        seq: UInt64,
        deviceIndex: Int,
        contactCount: Int,
        renderRevision: UInt64,
        leftContacts: Int,
        rightContacts: Int,
        captureFrames: UInt64
    ) {
        self.seq = seq
        self.deviceIndex = deviceIndex
        self.contactCount = contactCount
        self.renderRevision = renderRevision
        self.leftContacts = leftContacts
        self.rightContacts = rightContacts
        self.captureFrames = captureFrames
    }
}

public enum ReplayHarnessRunner {
    public static func run(
        fixture: ReplayFixture,
        engine: any EngineActorBoundary = EngineActorStub()
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
        let meta: [String: Any] = [
            "type": "transcriptMeta",
            "schema": ReplayFixtureParser.schema,
            "source": fixture.meta.source,
            "platform": fixture.meta.platform,
            "capturedAt": fixture.meta.capturedAt,
            "frames": transcript.count
        ]

        var lines: [String] = []
        if let metaLine = jsonLine(meta) {
            lines.append(metaLine)
        }

        for record in transcript {
            let payload: [String: Any] = [
                "type": "transcriptFrame",
                "schema": ReplayFixtureParser.schema,
                "seq": Int(record.seq),
                "deviceIndex": record.deviceIndex,
                "contactCount": record.contactCount,
                "renderRevision": Int(record.renderRevision),
                "leftContacts": record.leftContacts,
                "rightContacts": record.rightContacts,
                "captureFrames": Int(record.captureFrames)
            ]
            if let line = jsonLine(payload) {
                lines.append(line)
            }
        }

        return lines
    }

    private static func jsonLine(_ object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: []),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }
}
