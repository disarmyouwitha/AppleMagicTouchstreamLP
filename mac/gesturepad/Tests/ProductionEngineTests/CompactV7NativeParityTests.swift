import Foundation
import OpenMultitouchSupport
import XCTest
@testable import GesturePadRuntime

final class CompactV7NativeParityTests: XCTestCase {
    struct Reference: Decodable {
        var frameworkUUID: String
        var scalars: [[Int]]
        var densitySamples: [[Int]]
        var fillSamples: [Fill]
        var velocitySamples: [Velocity]
    }
    struct Fill: Decodable {
        var raw: [UInt8]
        var state, finger, hand: Int
        var x, y, absoluteX, absoluteY, major, minor, total, pressure, angle, density: Float
    }
    struct Velocity: Decodable {
        var raw: [UInt8]
        var state: Int
        var vx, vy, avx, avy: Float
    }
    func reference() throws -> Reference {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "CompactV7NativeReference", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Reference.self, from: Data(contentsOf: url))
    }
    func packet(_ raw: [UInt8], ticks: UInt32 = 1000, usb: Bool = false) -> Data {
        var bytes = [UInt8](repeating: 0, count: usb ? 12 : 4)
        bytes[0] = usb ? 2 : 0x31
        let base = bytes.count - 4
        if usb { bytes[base] = 0x31 }
        bytes[base+1] = UInt8((ticks & 31) << 3)
        bytes[base+2] = UInt8((ticks >> 5) & 255)
        bytes[base+3] = UInt8((ticks >> 13) & 255)
        bytes.append(contentsOf: raw)
        return Data(bytes)
    }
    func testAll256ScalarByteValuesAgainstAppleUnpacker() throws {
        let r = try reference()
        XCTAssertEqual(r.frameworkUUID, "B172DB85-9E88-3A4E-AB6E-B458FD373A58")
        XCTAssertEqual(r.scalars.count, 256)
        for row in r.scalars {
            let byte = UInt8(row[0])
            XCTAssertEqual(CompactV7Scalars.major(byte), row[1], "major byte \(byte)")
            XCTAssertEqual(CompactV7Scalars.minor(byte), row[2], "minor byte \(byte)")
            XCTAssertEqual(CompactV7Scalars.total(byte), row[3], "total byte \(byte)")
            XCTAssertEqual(CompactV7Scalars.pressure(byte), row[4], "pressure byte \(byte)")
        }
    }
    func testDensityAgainst576NativeOracleCases() throws {
        let rows = try reference().densitySamples
        XCTAssertEqual(rows.count, 576)
        for row in rows {
            XCTAssertEqual(CompactV7Scalars.density(total: row[0], major: row[1], minor: row[2]), row[3])
        }
    }
    func testBothTransportAdaptersAgainst256NativeFilledContacts() throws {
        let rows = try reference().fillSamples
        XCTAssertEqual(rows.count, 256)
        for row in rows {
            for usb in [false, true] {
                let c = try XCTUnwrap(MagicTrackpadPacket.decode(packet(row.raw, usb: usb))?.contacts.first)
                let t = try XCTUnwrap(c.telemetry)
                XCTAssertEqual(t.fingerID, Int32(row.finger)); XCTAssertEqual(t.handID, Int32(row.hand))
                let states: [OMSState] = [.notTouching,.starting,.hovering,.making,.touching,.breaking,.lingering,.leaving]
                XCTAssertEqual(c.state, states[row.state])
                XCTAssertEqual(c.posX, row.x, accuracy: 0.000001)
                XCTAssertEqual(c.posY, row.y, accuracy: 0.000001)
                XCTAssertEqual(t.absoluteX, row.absoluteX, accuracy: 0.00001)
                XCTAssertEqual(t.absoluteY, row.absoluteY, accuracy: 0.00001)
                XCTAssertEqual(c.majorAxis, row.major, accuracy: 0.00001)
                XCTAssertEqual(c.minorAxis, row.minor, accuracy: 0.00001)
                XCTAssertEqual(c.total, row.total, accuracy: 0.000001)
                XCTAssertEqual(c.pressure, row.pressure)
                XCTAssertEqual(c.angle, row.angle, accuracy: 0.000001)
                XCTAssertEqual(c.density, row.density, accuracy: 0.000001)
                XCTAssertEqual(t.driverKit?.contactBytes, row.raw)
                XCTAssertEqual(t.driverKit?.reportBytes, Array(packet(row.raw, usb: usb)))
            }
        }
    }
    func testQuantizedVelocityAndStatesAgainstNativeTwoFrameOracle() throws {
        let rows = try reference().velocitySamples
        XCTAssertEqual(rows.count, 96)
        // Initial native position in oracle is (10,60), corresponding to raw (500,500).
        let initial: [UInt8] = [244,129,62,136,80,90,18,25,129]
        for row in rows {
            var estimator = DriverContactEstimator()
            let first = try XCTUnwrap(MagicTrackpadPacket.decode(packet(initial, ticks: 1000)))
            _ = estimator.process(device: 1, time: 50, sequence: 1, contacts: first.contacts)
            let second = try XCTUnwrap(MagicTrackpadPacket.decode(packet(row.raw, ticks: 1010)))
            let c = estimator.process(device: 1, time: 50.012, sequence: 2, contacts: second.contacts)[0]
            let t = try XCTUnwrap(c.telemetry)
            XCTAssertEqual(t.velocityX, row.vx, accuracy: 0.000001)
            XCTAssertEqual(t.velocityY, row.vy, accuracy: 0.000001)
            XCTAssertEqual(t.absoluteVelocityX, row.avx, accuracy: 0.000001)
            XCTAssertEqual(t.absoluteVelocityY, row.avy, accuracy: 0.000001)
            let states: [OMSState] = [.notTouching,.starting,.hovering,.making,.touching,.breaking,.lingering,.leaving]
            XCTAssertEqual(c.state, states[row.state])
            XCTAssertEqual(t.sourceTimestamp, 1.01)
        }
    }
    func testEmptyContactReportsStillAdvanceSensorClockEpoch() throws {
        var estimator = DriverContactEstimator()
        _ = estimator.process(device: 1, time: 1, sequence: 1, contacts: [], sensorTicks: 0x1ffffb)
        _ = estimator.process(device: 1, time: 1.01, sequence: 2, contacts: [], sensorTicks: 5)
        let raw: [UInt8] = [244,129,62,136,80,90,18,25,129]
        let frame = try XCTUnwrap(MagicTrackpadPacket.decode(packet(raw, ticks: 15)))
        let c = estimator.process(device: 1, time: 1.02, sequence: 3, contacts: frame.contacts)[0]
        XCTAssertEqual(c.telemetry?.sourceTimestamp ?? 0, Double(0x20000f) / 1000, accuracy: 0.000001)
        XCTAssertEqual(c.telemetry?.driverKit?.velocityAvailable, false)
    }
    func testSensorClockWrapIsPerPad() throws {
        let raw: [UInt8] = [244,129,62,136,80,90,18,25,129]
        var estimator = DriverContactEstimator()
        let first = try XCTUnwrap(MagicTrackpadPacket.decode(packet(raw, ticks: 0x1ffffb)))
        _ = estimator.process(device: 1, time: 5, sequence: 1, contacts: first.contacts)
        let second = try XCTUnwrap(MagicTrackpadPacket.decode(packet(raw, ticks: 5)))
        let touch = estimator.process(device: 1, time: 5.01, sequence: 2, contacts: second.contacts)[0]
        XCTAssertEqual(touch.telemetry?.sourceTimestamp ?? 0, Double(0x200005) / 1000, accuracy: 0.000001)
        XCTAssertEqual(touch.telemetry?.driverKit?.velocityAvailable, true)
        let other = estimator.process(device: 2, time: 5.01, sequence: 1, contacts: second.contacts)[0]
        XCTAssertEqual(other.telemetry?.sourceTimestamp, 0.005)
        XCTAssertEqual(other.telemetry?.driverKit?.velocityAvailable, false)
    }
}
