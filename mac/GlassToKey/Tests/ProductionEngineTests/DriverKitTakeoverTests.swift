import Carbon
import CoreGraphics
import Foundation
import OpenMultitouchSupport
import XCTest
@testable import GlassToKeyRuntime

final class DriverKitTakeoverTests: XCTestCase {
    @MainActor
    func testCurrentCoordinatorAndReceiverAreAcceptedWithSameProtocolVersion() {
        XCTAssertTrue(DriverKitTakeover.acceptsStream(["StreamBuild": NSNumber(value: 22), "StreamCoordinator": 1]))
        XCTAssertTrue(DriverKitTakeover.acceptsStream(["StreamBuild": NSNumber(value: 22), "StreamSerial": "any-pad"]))
        XCTAssertFalse(DriverKitTakeover.acceptsStream(["StreamBuild": NSNumber(value: 20), "StreamCoordinator": 1]))
        XCTAssertFalse(DriverKitTakeover.acceptsStream(["StreamCoordinator": 1]))
    }
    @MainActor
    func testVisualizationSelectionAllowsZeroOneOrTwoConnectedPads() {
        let usb = (serial: "J84HMA00H0B0000501", transport: "USB", id: UInt64(1))
        let bt = (serial: "D0:C0:50:D4:75:6C", transport: "Bluetooth", id: UInt64(2))
        XCTAssertNil(DriverKitTakeover.selectionError(selected: [usb], connectedSerials: [usb.serial]))
        XCTAssertNil(DriverKitTakeover.selectionError(selected: [bt], connectedSerials: [bt.serial]))
        XCTAssertNil(DriverKitTakeover.selectionError(selected: [usb, bt], connectedSerials: [usb.serial, bt.serial]))
        XCTAssertNil(DriverKitTakeover.selectionError(selected: [usb], connectedSerials: [usb.serial, bt.serial]))
        XCTAssertNil(DriverKitTakeover.selectionError(selected: [("another-AMT", "Bluetooth", 3)], connectedSerials: []))
        XCTAssertNil(DriverKitTakeover.selectionError(selected: [], connectedSerials: [usb.serial, bt.serial]))
        XCTAssertNil(DriverKitTakeover.selectionError(selected: [], connectedSerials: []))
        XCTAssertNotNil(DriverKitTakeover.selectionError(selected: [usb, usb], connectedSerials: [usb.serial]))
    }

    func testDriverFramesRenderWithoutRunningNativeListener() async throws {
        let engine = RuntimeCore()
        await engine.updateActiveDevices(leftIndex: 0, rightIndex: 1, leftDeviceID: "41", rightDeviceID: "42")
        let input = InputRuntimeService()
        XCTAssertFalse(input.isRunning)
        let render = RuntimeRenderSnapshotService()
        render.setRecordingEnabled(true)
        let lifecycle = RuntimeLifecycleCoordinatorService(inputRuntimeService: input,
            renderSnapshotService: render, runtimeEngine: engine,
            runtimeCommandService: RuntimeCommandService(runtimeEngine: engine))
        let contact = try XCTUnwrap(MagicTrackpadPacket.decode(packet(usb: true))?.contacts.first)
        await lifecycle.ingestDriverContacts(device: 41, index: 0, timestamp: 1, touches: [contact])
        await lifecycle.ingestDriverContacts(device: 42, index: 1, timestamp: 2, touches: [contact])
        XCTAssertEqual(render.snapshot().left.count, 1)
        XCTAssertEqual(render.snapshot().right.count, 1)
        await lifecycle.ingestDriverContacts(device: 41, index: 0, timestamp: 3, touches: [])
        XCTAssertTrue(render.snapshot().left.isEmpty)
        XCTAssertEqual(render.snapshot().right.count, 1, "Clearing one source cannot stop the other pad")
    }

    func testTerminalDriverFrameClearsRenderButRetainsRawTelemetryInCapture() async throws {
        let engine = RuntimeCore()
        await engine.updateActiveDevices(leftIndex: 0, rightIndex: nil, leftDeviceID: "41", rightDeviceID: nil)
        let render = RuntimeRenderSnapshotService()
        render.setRecordingEnabled(true)
        let lifecycle = RuntimeLifecycleCoordinatorService(inputRuntimeService: InputRuntimeService(),
            renderSnapshotService: render, runtimeEngine: engine,
            runtimeCommandService: RuntimeCommandService(runtimeEngine: engine))
        engine.startCapture(configuration: nil, startUptimeNanoseconds: 0)
        let active = try XCTUnwrap(MagicTrackpadPacket.decode(packet(usb: true))?.contacts.first)
        let lifted = try XCTUnwrap(MagicTrackpadPacket.decode(packet(usb: true, down: false))?.contacts.first)
        await lifecycle.ingestDriverContacts(device: 41, index: 0, timestamp: 1, touches: [active])
        XCTAssertEqual(render.snapshot().left.count, 1)
        await lifecycle.ingestDriverContacts(device: 41, index: 0, timestamp: 2, touches: [lifted])
        XCTAssertTrue(render.snapshot().left.isEmpty)
        let capture = await engine.stopCapture()
        let records = try XCTUnwrap(capture).frameRecords
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.last?.frame.rawTouches.first?.state, .notTouching)
        XCTAssertEqual(records.last?.frame.rawTouches.first?.telemetry?.driverKit?.contactBytes.count, 9)
    }

    @MainActor
    func testDriverInputUsesKeyboardEngineAndSuspendingReleasesHeldModifier() async throws {
        let scheduler = ReplayTouchEngineScheduler(startTime: 1)
        let output = ProductionReplaySession.Output()
        let dispatcher = DispatchService(recordingWith: scheduler) { output.events.append($0) }
        let engine = RuntimeCore(dispatchService: dispatcher)
        let size = CGSize(width: 160, height: 115)
        let layout = ContentViewModel.Layout(keyRects: [[CGRect(origin: .zero, size: size)]],
            trackpadSize: size, allowHoldBindings: false)
        await engine.updateLayouts(leftLayout: layout, rightLayout: layout,
            leftLabels: [["Shift"]], rightLabels: [["Shift"]], trackpadSize: size, trackpadWidthMm: 160)
        await engine.updateActiveDevices(leftIndex: 0, rightIndex: nil, leftDeviceID: "41", rightDeviceID: nil)
        await engine.updateKeyboardModeEnabled(true)
        await engine.updateForceClickMin(0)
        await engine.updateForceClickCap(1000)
        await engine.updateHapticStrength(0)
        await engine.setListening(true)
        let input = InputRuntimeService()
        XCTAssertFalse(input.isRunning)
        let lifecycle = RuntimeLifecycleCoordinatorService(inputRuntimeService: input,
            renderSnapshotService: RuntimeRenderSnapshotService(), runtimeEngine: engine,
            runtimeCommandService: RuntimeCommandService(runtimeEngine: engine))
        var making = packet(usb: true)
        making[15] = 3 << 5
        let landing = try XCTUnwrap(MagicTrackpadPacket.decode(making))
        let touching = try XCTUnwrap(MagicTrackpadPacket.decode(packet(usb: true)))
        await lifecycle.ingestDriverContacts(device: 41, index: 0, timestamp: 1, touches: landing.contacts)
        await lifecycle.ingestDriverContacts(device: 41, index: 0, timestamp: 1.04, touches: touching.contacts)
        func modifierEvents() -> [Bool] {
            output.events.compactMap {
                if case let .key(code, _, down, _) = $0.kind, code == kVK_Shift { return down }
                return nil
            }
        }
        XCTAssertEqual(modifierEvents(), [true])
        await lifecycle.suspendDriverOutput()
        XCTAssertEqual(modifierEvents(), [true, false])
        await lifecycle.ingestDriverContacts(device: 41, index: 0, timestamp: 1.1, touches: touching.contacts)
        XCTAssertEqual(modifierEvents(), [true, false], "Suspended restart/release input must not re-arm held modifiers")
    }

    @MainActor
    func testDriverInventorySurvivesMissingNativeServicesWithOriginalRouting() {
        let manager = OMSManager.shared
        defer { manager.setDriverInventory([]) }
        DriverKitTakeover.installInventory([DriverSessionDevice(serial: "arbitrary-pad", transport: "USB",
            id: UInt64.max - 1, index: 7, registryID: 999, name: "Magic Trackpad")])
        XCTAssertTrue(manager.availableDevices.contains { $0.serialNumber == "arbitrary-pad" })
        XCTAssertEqual(manager.deviceIndex(for: UInt64.max - 1), 7)
    }

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
            XCTAssertEqual(c.posX, Float(5356) / 15225, accuracy: 0.00001)
            XCTAssertEqual(c.posY, Float(1174) / 10130, accuracy: 0.00001)
            XCTAssertEqual(c.pressure, 84)
            XCTAssertEqual(c.total, Float(CompactV7Scalars.total(33)) / 256)
            XCTAssertEqual(c.majorAxis, Float(CompactV7Scalars.major(21)) / 100, accuracy: 0.00001)
            XCTAssertEqual(c.minorAxis, Float(CompactV7Scalars.minor(11)) / 100, accuracy: 0.00001)
            XCTAssertEqual(c.state, .touching)
            XCTAssertEqual(c.telemetry?.fingerID, 0, "Finger type comes from dedicated bits, never tracking ID7")
            XCTAssertEqual(c.telemetry?.driverKit?.contactBytes.count, 9)
            XCTAssertEqual(c.angle, .pi / 2, accuracy: 0.00001)
        }
    }
    func testCapturedBluetoothSample() throws {
        let b: [UInt8] = [0x31,0x9c,0x22,0x81,0x05,0x82,0xf4,0x23,0x32,0x55,0x0e,0x0a,0x6b]
        let decoded = try XCTUnwrap(MagicTrackpadPacket.decode(Data(b)))
        XCTAssertEqual(decoded.contacts.count, 1)
        XCTAssertEqual(decoded.contacts[0].id, 11)
        XCTAssertEqual(decoded.contacts[0].pressure, 20)
        XCTAssertEqual(decoded.contacts[0].state, .starting)
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
        XCTAssertEqual(c.posX, Float(15224) / 15225, accuracy: 0.00001)
        XCTAssertEqual(c.posY, 1, accuracy: 0.00001)
        XCTAssertEqual(c.id, 15)
    }
    func testDedicatedFingerBitsAndAllEightStatesArePreserved() throws {
        let states: [OMSState] = [.notTouching,.starting,.hovering,.making,.touching,.breaking,.lingering,.leaving]
        for (index, state) in states.enumerated() {
            var data = packet(usb: true, id: 15)
            data[15] = UInt8((index << 5) | (2 << 2))
            let c = try XCTUnwrap(MagicTrackpadPacket.decode(data)?.contacts.first)
            XCTAssertEqual(c.id, 15); XCTAssertEqual(c.telemetry?.fingerID, 2)
            XCTAssertEqual(c.state, state)
        }
    }
    func testDerivedVelocityIsPerDeviceAndResetsAfterLiftAndGap() throws {
        func contacts(_ x: Int, down: Bool = true) throws -> [OMSRawTouch] {
            var data = packet(usb: false, x: x, down: down)
            let ticks = UInt32(1000 + x / 10)
            data[1] = UInt8((ticks & 31) << 3); data[2] = UInt8((ticks >> 5) & 255); data[3] = UInt8(ticks >> 13)
            return try XCTUnwrap(MagicTrackpadPacket.decode(data)).contacts
        }
        var estimator = DriverContactEstimator()
        let first = estimator.process(device: 1, time: 1, sequence: 1, contacts: try contacts(0))
        XCTAssertEqual(first[0].telemetry?.driverKit?.velocityAvailable, false)
        let second = estimator.process(device: 1, time: 1.01, sequence: 2, contacts: try contacts(100))
        XCTAssertEqual(second[0].telemetry?.driverKit?.velocityAvailable, true)
        XCTAssertEqual(try XCTUnwrap(second[0].telemetry?.velocityX), Float(1599 * 2) / 160 * 1000 / 15225, accuracy: 0.0001)
        XCTAssertEqual(second[0].telemetry?.sourceFrame, 2)
        XCTAssertEqual(estimator.process(device: 2, time: 1.02, sequence: 3, contacts: try contacts(200))[0].telemetry?.driverKit?.velocityAvailable, false)
        _ = estimator.process(device: 1, time: 1.02, sequence: 3, contacts: try contacts(200, down: false))
        XCTAssertEqual(estimator.process(device: 1, time: 1.03, sequence: 4, contacts: try contacts(300))[0].telemetry?.driverKit?.velocityAvailable, false)
        estimator.reset()
        XCTAssertEqual(estimator.process(device: 1, time: 2, sequence: 5, contacts: try contacts(400))[0].telemetry?.driverKit?.velocityAvailable, false)
    }
    func testTelemetryRoundTripRetainsRawBytesAndDecodesLegacyAbsence() throws {
        let telemetry = try XCTUnwrap(MagicTrackpadPacket.decode(packet(usb: true))?.contacts.first?.telemetry)
        let data = try JSONEncoder().encode(telemetry)
        XCTAssertEqual(try JSONDecoder().decode(OMSTouchTelemetry.self, from: data), telemetry)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "driverKit")
        let decoded = try JSONDecoder().decode(OMSTouchTelemetry.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded.driverKit)
        XCTAssertEqual(decoded.fingerID, telemetry.fingerID)
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
