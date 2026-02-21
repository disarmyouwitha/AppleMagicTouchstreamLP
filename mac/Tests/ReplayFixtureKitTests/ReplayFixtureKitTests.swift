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

    func testInvalidStateFailsValidation() throws {
        let invalid = """
        {"type":"meta","schema":"g2k-replay-v1","capturedAt":"2026-02-21T00:00:00Z","platform":"macOS","source":"unit","framesCaptured":1}
        {"type":"frame","schema":"g2k-replay-v1","seq":1,"timestampSec":1.0,"deviceID":"123","deviceNumericID":123,"deviceIndex":0,"touchCount":1,"contacts":[{"id":1,"x":0.1,"y":0.2,"total":0.3,"pressure":0.4,"majorAxis":1.0,"minorAxis":1.0,"angle":0.0,"density":0.5,"state":"invalidState"}]}
        """

        XCTAssertThrowsError(try ReplayFixtureParser.parse(jsonl: invalid)) { error in
            XCTAssertEqual(error as? ReplayFixtureError, .invalidState(line: 2, state: "invalidState"))
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

    private func fixtureURL() -> URL {
        URL(fileURLWithPath: "ReplayFixtures/macos_first_capture_2026-02-20.jsonl", relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL
    }

    private func engineTranscriptURL() -> URL {
        URL(fileURLWithPath: "ReplayFixtures/macos_first_capture_2026-02-20.engine.transcript.jsonl", relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL
    }
}
