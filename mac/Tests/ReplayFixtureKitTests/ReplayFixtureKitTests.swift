import Foundation
import XCTest
@testable import ReplayFixtureKit

final class ReplayFixtureKitTests: XCTestCase {
    func testBaselineFixtureParsesAndCanonicalStatesAreValid() throws {
        let fixture = try ReplayFixtureParser.load(from: fixtureURL())

        XCTAssertEqual(fixture.meta.schema, ReplayFixtureParser.schema)
        XCTAssertEqual(fixture.meta.framesCaptured, 52)
        XCTAssertEqual(fixture.frames.count, 52)

        for frame in fixture.frames {
            for contact in frame.contacts {
                XCTAssertTrue(ReplayFixtureParser.canonicalStates.contains(contact.state))
            }
        }
    }

    func testInvalidStateFailsATPCaptureEncoding() throws {
        let fixture = ReplayFixture(
            meta: ReplayFixtureMeta(
                schema: ReplayFixtureParser.schema,
                capturedAt: "2026-02-21T00:00:00Z",
                platform: "macOS",
                source: "unit",
                framesCaptured: 1
            ),
            frames: [
                ReplayFrameRecord(
                    seq: 1,
                    timestampSec: 1.0,
                    deviceID: "123",
                    deviceNumericID: 123,
                    deviceIndex: 0,
                    contacts: [
                        ReplayContactRecord(
                            id: 1,
                            x: 0.1,
                            y: 0.2,
                            total: 0.3,
                            pressure: 0.4,
                            majorAxis: 1.0,
                            minorAxis: 1.0,
                            angle: 0.0,
                            density: 0.5,
                            state: "invalidState"
                        )
                    ]
                )
            ]
        )

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("replay-fixture-kit-tests-invalid-\(UUID().uuidString)", isDirectory: true)
        let atpcapURL = tempDir.appendingPathComponent("invalid.atpcap", isDirectory: false)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        XCTAssertThrowsError(try ReplayFixtureCodec.write(fixture, to: atpcapURL)) { error in
            XCTAssertEqual(error as? ReplayFixtureError, .invalidStateEncoding(state: "invalidState"))
        }
    }

    func testTranscriptDeterminismForBaselineFixture() async throws {
        let fixture = try ReplayFixtureParser.load(from: fixtureURL())

        let first = await ReplayHarnessRunner.run(fixture: fixture)
        let second = await ReplayHarnessRunner.run(fixture: fixture)

        XCTAssertEqual(first.count, fixture.frames.count)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.last?.captureFrames, UInt64(fixture.frames.count))
    }

    func testOnlyEngineTranscriptBaselinesAreCommitted() throws {
        let fixturesDirectory = URL(
            fileURLWithPath: "ReplayFixtures",
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        ).standardizedFileURL
        let fileManager = FileManager.default
        let items = try fileManager.contentsOfDirectory(atPath: fixturesDirectory.path)

        let transcriptFiles = items.filter { $0.hasSuffix(".transcript.jsonl") }
        XCTAssertFalse(transcriptFiles.isEmpty, "Expected at least one committed transcript baseline.")

        let nonCanonical = transcriptFiles.filter { !$0.hasSuffix(".engine.transcript.jsonl") }
        XCTAssertTrue(
            nonCanonical.isEmpty,
            "Non-canonical transcript baseline names detected: \(nonCanonical.joined(separator: ", "))"
        )
    }

    func testTranscriptMatchesCommittedEngineBaseline() async throws {
        let fixture = try ReplayFixtureParser.load(from: fixtureURL())
        let transcript = await ReplayHarnessRunner.run(fixture: fixture)
        let lines = ReplayHarnessRunner.transcriptJSONLines(fixture: fixture, transcript: transcript)
        let payload = lines.joined(separator: "\n") + "\n"
        let expected = try String(contentsOf: engineTranscriptURL(), encoding: .utf8)
        XCTAssertEqual(payload, expected)
    }

    func testATPCaptureRoundTripFromBaselineFixture() throws {
        let baseline = try ReplayFixtureParser.load(from: fixtureURL())
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("replay-fixture-kit-tests-\(UUID().uuidString)", isDirectory: true)
        let atpcapURL = tempDir.appendingPathComponent("baseline.atpcap", isDirectory: false)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        try ReplayFixtureCodec.write(baseline, to: atpcapURL)
        let loaded = try ReplayFixtureParser.load(from: atpcapURL)

        XCTAssertEqual(loaded.meta.schema, baseline.meta.schema)
        XCTAssertEqual(loaded.meta.platform, baseline.meta.platform)
        XCTAssertEqual(loaded.meta.source, baseline.meta.source)
        XCTAssertEqual(loaded.frames.count, baseline.frames.count)

        for (lhs, rhs) in zip(loaded.frames, baseline.frames) {
            XCTAssertEqual(lhs.seq, rhs.seq)
            XCTAssertEqual(lhs.deviceIndex, rhs.deviceIndex)
            XCTAssertEqual(lhs.deviceNumericID, rhs.deviceNumericID)
            XCTAssertEqual(lhs.contacts.count, rhs.contacts.count)
            XCTAssertEqual(lhs.deviceID, String(lhs.deviceNumericID))
            for (leftContact, rightContact) in zip(lhs.contacts, rhs.contacts) {
                XCTAssertEqual(leftContact.id, rightContact.id)
                XCTAssertEqual(leftContact.state, rightContact.state)
                XCTAssertEqual(leftContact.x, rightContact.x, accuracy: 0.0001)
                XCTAssertEqual(leftContact.y, rightContact.y, accuracy: 0.0001)
                XCTAssertEqual(leftContact.total, rightContact.total, accuracy: 0.0001)
                XCTAssertEqual(leftContact.pressure, rightContact.pressure, accuracy: 0.0001)
                XCTAssertEqual(leftContact.majorAxis, rightContact.majorAxis, accuracy: 0.0001)
                XCTAssertEqual(leftContact.minorAxis, rightContact.minorAxis, accuracy: 0.0001)
                XCTAssertEqual(leftContact.angle, rightContact.angle, accuracy: 0.0001)
                XCTAssertEqual(leftContact.density, rightContact.density, accuracy: 0.0001)
            }
        }
    }

    func testProcessedFrameV5ATPCaptureParsesAndReplays() async throws {
        let data = try makeProcessedFrameV5CaptureData()
        let fixture = try ReplayFixtureParser.load(from: writeTempCapture(data, name: "processed-v5.atpcap"))

        XCTAssertEqual(fixture.meta.schema, ReplayFixtureParser.schema)
        XCTAssertEqual(fixture.meta.framesCaptured, 2)
        XCTAssertEqual(fixture.frames.count, 2)
        XCTAssertEqual(fixture.frames[0].seq, 2727)
        XCTAssertEqual(fixture.frames[0].timestampSec, 0, accuracy: 0.000001)
        XCTAssertEqual(fixture.frames[1].seq, 2728)
        XCTAssertEqual(fixture.frames[1].timestampSec, 0.5, accuracy: 0.000001)
        XCTAssertEqual(fixture.frames[0].contacts.first?.state, "touching")

        let transcript = await ReplayHarnessRunner.run(fixture: fixture)
        XCTAssertEqual(transcript.count, fixture.frames.count)
        XCTAssertEqual(transcript.last?.captureFrames, 2)
    }

    func testLegacyV3ATPCaptureCanBeTranscodedToCurrentVersion() throws {
        let legacyURL = try writeTempCapture(try makeLegacyV3CaptureData(), name: "legacy-v3.atpcap")
        let transcodedURL = legacyURL.deletingLastPathComponent().appendingPathComponent("legacy-v5.atpcap")

        try ReplayFixtureCodec.transcodeLegacyATPCapture(from: legacyURL, to: transcodedURL)

        let container = try ATPCaptureCodec.loadContainer(from: transcodedURL)
        XCTAssertEqual(container.header.version, ATPCaptureCodec.currentVersion)

        let fixture = try ReplayFixtureParser.load(from: transcodedURL)
        XCTAssertEqual(fixture.meta.framesCaptured, 2)
        XCTAssertEqual(fixture.frames.count, 2)
        XCTAssertEqual(fixture.frames[0].seq, 1)
        XCTAssertEqual(fixture.frames[0].timestampSec, 0, accuracy: 0.000001)
        XCTAssertEqual(fixture.frames[1].seq, 2)
        XCTAssertEqual(fixture.frames[1].timestampSec, 0.5, accuracy: 0.000001)
        XCTAssertEqual(fixture.frames[0].contacts.first?.state, "touching")
    }

    private func fixtureURL() -> URL {
        URL(fileURLWithPath: "ReplayFixtures/macos_first_capture_2026-02-20.atpcap", relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL
    }

    private func engineTranscriptURL() -> URL {
        URL(fileURLWithPath: "ReplayFixtures/macos_first_capture_2026-02-20.engine.transcript.jsonl", relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL
    }

    private func writeTempCapture(_ data: Data, name: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("replay-fixture-kit-tests-v5-\(UUID().uuidString)", isDirectory: true)
        let captureURL = tempDir.appendingPathComponent(name, isDirectory: false)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try data.write(to: captureURL, options: .atomic)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempDir)
        }
        return captureURL
    }

    private func makeProcessedFrameV5CaptureData() throws -> Data {
        struct MetaPayload: Encodable {
            let type = "meta"
            let schema = ReplayFixtureParser.schema
            let capturedAt = "2026-03-25T00:00:00.000Z"
            let platform = "macOS"
            let source = "unit"
            let framesCaptured = 2
        }

        struct Contact: Encodable {
            let id: Int32
            let posX: Float
            let posY: Float
            let total: Float
            let pressure: Float
            let majorAxis: Float
            let minorAxis: Float
            let angle: Float
            let density: Float
            let state: String
        }

        struct Frame: Encodable {
            let sequence: UInt64
            let timestamp: Double
            let deviceNumericID: UInt64
            let deviceIndex: Int
            let contacts: [Contact]
        }

        struct RecordPayload: Encodable {
            struct Record: Encodable {
                let frame: Frame
            }

            let type = "processedFrameRecord"
            let record: Record
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        var data = Data()
        data.append("ATPCAP01".data(using: .ascii)!)
        appendInt32LE(ATPCaptureCodec.processedFrameVersion, to: &data)
        appendInt64LE(ATPCaptureCodec.defaultTickFrequency, to: &data)

        let metaPayload = try encoder.encode(MetaPayload())
        appendRecord(
            payload: metaPayload,
            arrivalTicks: 0,
            deviceIndex: -1,
            to: &data
        )

        let firstFrame = RecordPayload(
            record: .init(
                frame: Frame(
                    sequence: 2727,
                    timestamp: 123.0,
                    deviceNumericID: 42,
                    deviceIndex: 0,
                    contacts: [
                        Contact(
                            id: 7,
                            posX: 0.25,
                            posY: 0.5,
                            total: 1,
                            pressure: 0.8,
                            majorAxis: 2,
                            minorAxis: 1,
                            angle: 0,
                            density: 0.4,
                            state: "touching"
                        )
                    ]
                )
            )
        )
        appendRecord(
            payload: try encoder.encode(firstFrame),
            arrivalTicks: 0,
            deviceIndex: -5,
            to: &data
        )

        let secondFrame = RecordPayload(
            record: .init(
                frame: Frame(
                    sequence: 2728,
                    timestamp: 999.0,
                    deviceNumericID: 99,
                    deviceIndex: 1,
                    contacts: []
                )
            )
        )
        appendRecord(
            payload: try encoder.encode(secondFrame),
            arrivalTicks: 500_000_000,
            deviceIndex: -5,
            to: &data
        )

        return data
    }

    private func makeLegacyV3CaptureData() throws -> Data {
        struct MetaPayload: Encodable {
            let type = "meta"
            let schema = ReplayFixtureParser.schema
            let capturedAt = "2026-03-26T00:00:00.000Z"
            let platform = "macOS"
            let source = "unit-legacy"
            let framesCaptured = 2
        }

        var data = Data()
        data.append("ATPCAP01".data(using: .ascii)!)
        appendInt32LE(3, to: &data)
        appendInt64LE(ATPCaptureCodec.defaultTickFrequency, to: &data)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let metaPayload = try encoder.encode(MetaPayload())
        appendRecord(
            payload: metaPayload,
            arrivalTicks: 0,
            deviceIndex: -1,
            to: &data
        )

        appendLegacyFrameRecord(
            seq: 1,
            timestampSec: 4.0,
            deviceNumericID: 42,
            deviceIndex: 0,
            contacts: [
                (
                    id: 7,
                    x: 0.25,
                    y: 0.5,
                    total: 1.0,
                    pressure: 0.8,
                    majorAxis: 2.0,
                    minorAxis: 1.0,
                    angle: 0.0,
                    density: 0.4,
                    state: 4
                )
            ],
            to: &data
        )
        appendLegacyFrameRecord(
            seq: 2,
            timestampSec: 4.5,
            deviceNumericID: 99,
            deviceIndex: 1,
            contacts: [],
            to: &data
        )

        return data
    }

    private func appendLegacyFrameRecord(
        seq: UInt64,
        timestampSec: Double,
        deviceNumericID: UInt64,
        deviceIndex: Int32,
        contacts: [(id: Int32, x: Float, y: Float, total: Float, pressure: Float, majorAxis: Float, minorAxis: Float, angle: Float, density: Float, state: UInt8)],
        to data: inout Data
    ) {
        var payload = Data()
        appendUInt32LE(0x33564652, to: &payload)
        appendUInt64LE(seq, to: &payload)
        appendDoubleLE(timestampSec, to: &payload)
        appendUInt64LE(deviceNumericID, to: &payload)
        appendUInt16LE(UInt16(contacts.count), to: &payload)
        appendUInt16LE(0, to: &payload)

        for contact in contacts {
            appendInt32LE(contact.id, to: &payload)
            appendFloatLE(contact.x, to: &payload)
            appendFloatLE(contact.y, to: &payload)
            appendFloatLE(contact.total, to: &payload)
            appendFloatLE(contact.pressure, to: &payload)
            appendFloatLE(contact.majorAxis, to: &payload)
            appendFloatLE(contact.minorAxis, to: &payload)
            appendFloatLE(contact.angle, to: &payload)
            appendFloatLE(contact.density, to: &payload)
            appendUInt8(contact.state, to: &payload)
            appendUInt8(0, to: &payload)
            appendUInt8(0, to: &payload)
            appendUInt8(0, to: &payload)
        }

        appendRecord(
            payload: payload,
            arrivalTicks: Int64((timestampSec - 4.0) * Double(ATPCaptureCodec.defaultTickFrequency)),
            deviceIndex: deviceIndex,
            to: &data
        )
    }

    private func appendRecord(
        payload: Data,
        arrivalTicks: Int64,
        deviceIndex: Int32,
        to data: inout Data
    ) {
        appendInt32LE(Int32(payload.count), to: &data)
        appendInt64LE(arrivalTicks, to: &data)
        appendInt32LE(deviceIndex, to: &data)
        appendUInt32LE(0, to: &data)
        appendUInt32LE(0, to: &data)
        appendUInt32LE(0, to: &data)
        appendUInt16LE(0, to: &data)
        appendUInt16LE(0, to: &data)
        data.append(0)
        data.append(0)
        data.append(payload)
    }

    private func appendInt32LE(_ value: Int32, to data: inout Data) {
        appendUInt32LE(UInt32(bitPattern: value), to: &data)
    }

    private func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }

    private func appendInt64LE(_ value: Int64, to data: inout Data) {
        appendUInt64LE(UInt64(bitPattern: value), to: &data)
    }

    private func appendUInt64LE(_ value: UInt64, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }

    private func appendUInt16LE(_ value: UInt16, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }

    private func appendDoubleLE(_ value: Double, to data: inout Data) {
        appendUInt64LE(value.bitPattern, to: &data)
    }

    private func appendFloatLE(_ value: Float, to data: inout Data) {
        appendUInt32LE(value.bitPattern, to: &data)
    }

    private func appendUInt8(_ value: UInt8, to data: inout Data) {
        data.append(value)
    }
}
