import Foundation
import OpenMultitouchSupport
import XCTest
@testable import GesturePadRuntime

@MainActor
final class SelectedDeviceSourceTests: XCTestCase {
    private func frame(_ id: UInt64, index: Int, contactID: Int32 = 1) -> RuntimeRawFrame {
        let touch = OMSRawTouch(id: contactID, posX: 0.5, posY: 0.5, total: 1,
            pressure: 100, majorAxis: 5, minorAxis: 3, angle: 0, density: 1, state: .touching)
        return RuntimeRawFrame(sequence: UInt64(contactID), timestamp: Double(contactID),
            deviceNumericID: id, deviceIndex: index, contacts: [], rawTouches: [touch])
    }

    func testEngineUsesPhysicalSourceWhenThirdPadReusesIndices() {
        let run = ProductionReplaySession()
        run.engine.setListening(true)
        run.engine.setCaptureFrameDiagnosticsEnabled(true)
        run.engine.updateActiveDevices(leftIndex: 0, rightIndex: 1, leftDeviceID: "42", rightDeviceID: "43")
        XCTAssertEqual(run.ingest(frame(43, index: 1))?.touches.first?.side, "right")
        // Right pad changes BT43 -> USB88. The old BT pad keeps sending frames.
        run.engine.updateActiveDevices(leftIndex: 0, rightIndex: 1, leftDeviceID: "42", rightDeviceID: "88")
        XCTAssertNil(run.ingest(frame(43, index: 1, contactID: 2)))
        XCTAssertNil(run.ingest(frame(43, index: 0, contactID: 3)))
        XCTAssertEqual(run.ingest(frame(88, index: 0, contactID: 4))?.touches.first?.side, "right")
        XCTAssertEqual(run.ingest(frame(42, index: 1, contactID: 5))?.touches.first?.side, "left")
        run.engine.updateActiveDevices(leftIndex: 0, rightIndex: nil, leftDeviceID: "42", rightDeviceID: nil)
        XCTAssertNil(run.ingest(frame(88, index: 0, contactID: 6)))
    }

    func testRenderClearsOldContactsAndIgnoresDeselectedPadDespiteIndexCollision() async {
        let core = RuntimeCore()
        await core.setListening(true)
        await core.updateActiveDevices(leftIndex: 0, rightIndex: 1, leftDeviceID: "42", rightDeviceID: "43")
        let old = await core.ingest(frame(43, index: 1), ingress: nil, captureRenderSnapshot: true)
        XCTAssertEqual(old.renderSnapshot?.rightTouches.map(\.id), [1])
        await core.updateActiveDevices(leftIndex: 0, rightIndex: 1, leftDeviceID: "42", rightDeviceID: "88")
        let ignored = await core.ingest(frame(43, index: 1, contactID: 2), ingress: nil, captureRenderSnapshot: true)
        XCTAssertTrue(ignored.renderSnapshot?.rightTouches.isEmpty == true)
        let usb = await core.ingest(frame(88, index: 0, contactID: 3), ingress: nil, captureRenderSnapshot: true)
        XCTAssertEqual(usb.renderSnapshot?.rightTouches.map(\.id), [3])
        XCTAssertTrue(usb.renderSnapshot?.leftTouches.isEmpty == true)
        let left = await core.ingest(frame(42, index: 1, contactID: 4), ingress: nil, captureRenderSnapshot: true)
        XCTAssertEqual(left.renderSnapshot?.leftTouches.map(\.id), [4])
        XCTAssertEqual(left.renderSnapshot?.rightTouches.map(\.id), [3])
    }

    func testLegacyCapturesWithoutNumericIDsStillUseRecordedIndices() {
        let source = RuntimeSelectedDeviceSource(id: "42", index: 0)
        XCTAssertTrue(source.matches(numericID: 0, index: 0))
        XCTAssertFalse(source.matches(numericID: 0, index: 1))
        XCTAssertFalse(source.matches(numericID: 99, index: 0))
        XCTAssertTrue(source.matches(numericID: 42, index: 1))
    }
}
