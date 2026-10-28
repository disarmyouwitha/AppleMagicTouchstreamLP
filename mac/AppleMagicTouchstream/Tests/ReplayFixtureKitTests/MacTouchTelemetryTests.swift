import Foundation
import XCTest
import OpenMultitouchSupportXCF
@testable import OpenMultitouchSupport
@testable import ReplayFixtureKit

final class MacTouchTelemetryTests: XCTestCase {
    func testHardwareContactCopiesIdentityAndBothVectorsWithoutInferringNames() throws {
        var hardware = MTTouch()
        hardware.identifier = 37
        hardware.state = 4
        hardware.fingerId = 0 // Preserve zero; do not turn it into missing data.
        hardware.handId = -1
        hardware.frame = 1234
        hardware.timestamp = 98.125
        hardware.normalizedPosition.position.x = 0.25
        hardware.normalizedPosition.position.y = 0.75
        hardware.normalizedPosition.velocity.x = -0.5
        hardware.normalizedPosition.velocity.y = 0.125
        hardware.absolutePosition.position.x = 45.5
        hardware.absolutePosition.position.y = 66.25
        hardware.absolutePosition.velocity.x = -12
        hardware.absolutePosition.velocity.y = 3
        let contact = OMSRawTouch(hardwareTouch: hardware)
        let raw = try XCTUnwrap(contact.telemetry)
        XCTAssertEqual(contact.id, 37)
        XCTAssertEqual(contact.state, .touching)
        XCTAssertEqual(contact.posX, 0.25)
        XCTAssertEqual(contact.posY, 0.75)
        XCTAssertEqual(raw.fingerID, 0)
        XCTAssertEqual(raw.handID, -1)
        XCTAssertEqual(raw.velocityX, -0.5)
        XCTAssertEqual(raw.velocityY, 0.125)
        XCTAssertEqual(raw.absoluteX, 45.5)
        XCTAssertEqual(raw.absoluteY, 66.25)
        XCTAssertEqual(raw.absoluteVelocityX, -12)
        XCTAssertEqual(raw.absoluteVelocityY, 3)
        XCTAssertEqual(raw.sourceFrame, 1234)
        XCTAssertEqual(raw.sourceTimestamp, 98.125)

        let decoded = try JSONDecoder().decode(OMSRawTouch.self, from: JSONEncoder().encode(contact))
        XCTAssertEqual(decoded.telemetry, raw)
    }

    func testOldContactsDecodeAsUnavailableRatherThanZeroIdentity() throws {
        let data = Data(#"{"id":1,"posX":0.1,"posY":0.2,"total":3,"pressure":4,"majorAxis":5,"minorAxis":6,"angle":0,"density":7,"state":"touching"}"#.utf8)
        let contact = try JSONDecoder().decode(OMSRawTouch.self, from: data)
        XCTAssertNil(contact.telemetry)
    }

    func testCaptureRoundTripRetainsTelemetryAndOldContactsRemainAbsent() throws {
        let metadata = ReplayTouchTelemetry(
            fingerID: 0, handID: -1, velocityX: -0.25, velocityY: 0.5,
            absoluteX: 123.5, absoluteY: 87.25, absoluteVelocityX: -4,
            absoluteVelocityY: 2, sourceFrame: 9876, sourceTimestamp: 98.125
        )
        let contacts = [metadata, nil].enumerated().map { index, raw in
            ReplayContactRecord(
                id: index + 1, x: 0.25, y: 0.75, total: 3, pressure: 4,
                majorAxis: 5, minorAxis: 6, angle: 0.125, density: 7,
                state: "touching", telemetry: raw
            )
        }
        let fixture = ReplayFixture(
            meta: ReplayFixtureMeta(schema: ReplayFixtureParser.schema,
                                    capturedAt: "2026-10-15T00:00:00Z", platform: "macOS",
                                    source: "telemetry-test", framesCaptured: 1),
            frames: [ReplayFrameRecord(seq: 1, timestampSec: 0, deviceID: "42",
                                       deviceNumericID: 42, deviceIndex: 0, contacts: contacts)]
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("telemetry-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.atpcap")
        try ReplayFixtureCodec.write(fixture, to: url)
        let loaded = try ReplayFixtureParser.load(from: url)
        XCTAssertEqual(loaded.frames[0].contacts[0].telemetry, metadata)
        XCTAssertNil(loaded.frames[0].contacts[1].telemetry)

        // The package decoder and the app use the same optional wire object.
        let container = try ATPCaptureCodec.loadContainer(from: url)
        let record = try XCTUnwrap(container.records.first { $0.deviceIndex == -5 })
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: record.payload) as? [String: Any])
        let body = try XCTUnwrap(json["record"] as? [String: Any])
        let frame = try XCTUnwrap(body["frame"] as? [String: Any])
        let rawTouches = try XCTUnwrap(frame["rawTouches"] as? [[String: Any]])
        let rawContact = try JSONDecoder().decode(OMSRawTouch.self, from: JSONSerialization.data(withJSONObject: rawTouches[0]))
        XCTAssertEqual(rawContact.telemetry?.fingerID, 0)
        XCTAssertEqual(rawContact.telemetry?.handID, -1)
        XCTAssertEqual(rawContact.telemetry?.absoluteX, 123.5)
        XCTAssertEqual(rawContact.telemetry?.absoluteVelocityY, 2)
        XCTAssertEqual(rawContact.telemetry?.sourceFrame, 9876)
    }
}
