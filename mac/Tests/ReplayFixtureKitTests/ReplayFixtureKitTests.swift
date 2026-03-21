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

    private func fixtureURL() -> URL {
        URL(fileURLWithPath: "ReplayFixtures/macos_first_capture_2026-02-20.atpcap", relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL
    }

    private func engineTranscriptURL() -> URL {
        URL(fileURLWithPath: "ReplayFixtures/macos_first_capture_2026-02-20.engine.transcript.jsonl", relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL
    }
}
