import Foundation
import OpenMultitouchSupport
import XCTest
@testable import GesturePadRuntime

final class DriverKitTakeoverTests: XCTestCase {
    private func packet(usb: Bool, x: Int = 0, y: Int = 0, id: UInt8 = 7, down: Bool = true) -> Data {
        var b = [UInt8](repeating: 0, count: usb ? 21 : 13)
        b[0] = usb ? 2 : 0x31
        let i = usb ? 12 : 4
        let ux = x & 0x1fff, uy = y & 0x1fff
        b[i] = UInt8(ux & 255)
        b[i+1] = UInt8((ux >> 8) | ((uy & 7) << 5))
        b[i+2] = UInt8((uy >> 3) & 255)
        b[i+3] = UInt8((uy >> 11) | (down ? 0x80 : 0))
        b[i+4] = 21; b[i+5] = 11; b[i+6] = 33; b[i+7] = 42; b[i+8] = 0x80 | id
        return Data(b)
    }
    func testTransportHeadersDecodeSameSignedContact() throws {
        for usb in [false, true] {
            let decoded = try XCTUnwrap(MagicTrackpadPacket.decode(packet(usb: usb, x: -1000, y: -2000)))
            let c = try XCTUnwrap(decoded.contacts.first)
            XCTAssertEqual(c.id, 7)
            XCTAssertEqual(c.posX, Float(2678) / 7612, accuracy: 0.00001)
            XCTAssertEqual(c.posY, Float(587) / 5065, accuracy: 0.00001)
            XCTAssertEqual(c.pressure, 42)
            XCTAssertEqual(c.total, 33)
            XCTAssertEqual(c.majorAxis, 21)
            XCTAssertEqual(c.minorAxis, 11)
            XCTAssertEqual(c.state, .touching)
            XCTAssertNil(c.telemetry, "Tracking IDs must not become anatomical finger labels")
        }
    }
    func testCapturedBluetoothSample() throws {
        let b: [UInt8] = [0x31,0x9c,0x22,0x81,0x05,0x82,0xf4,0x23,0x32,0x55,0x0e,0x0a,0x6b]
        let decoded = try XCTUnwrap(MagicTrackpadPacket.decode(Data(b)))
        XCTAssertEqual(decoded.contacts.count, 1)
        XCTAssertEqual(decoded.contacts[0].id, 11)
        XCTAssertEqual(decoded.contacts[0].pressure, 10)
        XCTAssertEqual(decoded.contacts[0].state, .leaving)
    }
    func testLiftAndEmptyFramesDoNotGenerateMovement() throws {
        let lifted = try XCTUnwrap(MagicTrackpadPacket.decode(packet(usb: false, down: false)))
        XCTAssertEqual(lifted.contacts[0].state, .leaving)
        var tracker = TwoFingerPointerTracker()
        XCTAssertNil(tracker.process(device: 1, time: 1, contacts: lifted.contacts))
        XCTAssertEqual(MagicTrackpadPacket.decode(Data([0x31,0,0,0]))?.contacts.count, 0)
    }
    func testRejectsTruncationUnknownReportsAndExcessContacts() {
        XCTAssertNil(MagicTrackpadPacket.decode(Data([2,0,0,0,0,0,0,0])))
        XCTAssertNil(MagicTrackpadPacket.decode(Data([0x31,0,0,0,0])))
        XCTAssertNil(MagicTrackpadPacket.decode(Data([0x44,0,0,0])))
        var oversized = Data(repeating: 0, count: 4 + 16 * 9); oversized[0] = 0x31
        XCTAssertNil(MagicTrackpadPacket.decode(oversized))
    }
    func testPositiveCoordinateAndTrackingIDLimits() throws {
        let c = try XCTUnwrap(MagicTrackpadPacket.decode(packet(usb: true, x: 3934, y: 2478, id: 15))?.contacts.first)
        XCTAssertEqual(c.posX, 1, accuracy: 0.00001)
        XCTAssertEqual(c.posY, 1, accuracy: 0.00001)
        XCTAssertEqual(c.id, 15)
    }
    func testDecodedTwoFingerMotionUsesSensorDirectionAndResetsOnLift() throws {
        func frame(_ x: Int, _ y: Int) throws -> [OMSRawTouch] {
            var bytes = packet(usb: false, x: x, y: y, id: 1)
            bytes.append(packet(usb: false, x: x + 500, y: y, id: 2).dropFirst(4))
            return try XCTUnwrap(MagicTrackpadPacket.decode(bytes)).contacts
        }
        var tracker = TwoFingerPointerTracker()
        XCTAssertNil(tracker.process(device: 1, time: 1, contacts: try frame(0, 0)))
        let move = try XCTUnwrap(tracker.process(device: 1, time: 1.01, contacts: try frame(40, 50)))
        XCTAssertGreaterThan(move.x, 0)
        XCTAssertLessThan(move.y, 0, "Upward sensor movement must move the screen cursor upward")
        XCTAssertNil(tracker.process(device: 1, time: 1.02, contacts: [OMSRawTouch]()))
        XCTAssertNil(tracker.process(device: 1, time: 1.03, contacts: try frame(800, 800)))
    }
    private func record(_ sequence: UInt64) -> DriverStreamRecord {
        DriverStreamRecord(sequence: sequence, timestamp: Double(sequence) / 100, payload: packet(usb: false))
    }
    func testCursorDeduplicatesAndResetsAcrossDriverSessions() {
        var cursor = DriverStreamCursor()
        XCTAssertEqual(cursor.take(session: 10, records: [record(1),record(2)]).records.count, 2)
        XCTAssertTrue(cursor.take(session: 10, records: [record(1),record(2)]).records.isEmpty)
        XCTAssertFalse(cursor.take(session: 10, records: [record(2),record(3)]).discontinuity)
        let gap = cursor.take(session: 10, records: [record(5)])
        XCTAssertTrue(gap.discontinuity)
        XCTAssertEqual(gap.records.map(\.sequence), [5])
        XCTAssertEqual(cursor.take(session: 11, records: [record(1)]).records.map(\.sequence), [1])
    }
    func testWireLayoutAndInvalidLengthAreChecked() throws {
        var batch = Data(repeating: 0, count: 176 * 64)
        let payload = packet(usb: false)
        func put(_ offset: Int, _ count: Int, _ value: UInt64) {
            for i in 0..<count { batch[offset+i] = UInt8(truncatingIfNeeded: value >> (8*i)) }
        }
        put(0,8,7); put(8,8,1_000_000_000); put(16,4,UInt64(payload.count)); put(20,4,0x31)
        batch.replaceSubrange(24..<(24+payload.count), with: payload)
        let records = try XCTUnwrap(DriverStreamRecord.decodeBatch(batch))
        XCTAssertEqual(records.count, 1); XCTAssertEqual(records[0].sequence, 7)
        XCTAssertEqual(records[0].timestamp, 1); XCTAssertEqual(records[0].payload, payload)
        put(16,4,149); XCTAssertNil(DriverStreamRecord.decodeBatch(batch))
        XCTAssertNil(DriverStreamRecord.decodeBatch(Data()))
    }
}
