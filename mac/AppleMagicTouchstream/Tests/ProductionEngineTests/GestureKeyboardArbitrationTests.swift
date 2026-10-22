import Carbon
import CoreGraphics
import OpenMultitouchSupport
import XCTest
@testable import GlassToKeyRuntime

@MainActor
final class GestureKeyboardArbitrationTests: XCTestCase {
    private func session() -> ProductionReplaySession {
        let run = ProductionReplaySession(startTime: 1)
        let size = CGSize(width: 160, height: 115)
        let layout = ContentViewModel.Layout(keyRects: [[CGRect(x: 10, y: 40, width: 35, height: 30),
            CGRect(x: 55, y: 40, width: 35, height: 30)]], trackpadSize: size, allowHoldBindings: true)
        run.engine.updateLayouts(leftLayout: layout, rightLayout: layout, leftLabels: [["F", "Shift"]],
            rightLabels: [["F", "Shift"]], trackpadSize: size, trackpadWidthMm: 160)
        run.engine.updateActiveDevices(leftIndex: 0, rightIndex: 1, leftDeviceID: "42", rightDeviceID: "43")
        run.engine.updateKeyboardModeEnabled(true)
        run.engine.updateForceClickMin(0)
        run.engine.updateForceClickCap(1000)
        run.engine.updateHapticStrength(0)
        run.engine.updateSnapRadiusPercent(0)
        run.engine.setListening(true)
        run.engine.setCaptureFrameDiagnosticsEnabled(true)
        return run
    }
    private func touch(_ id: Int32 = 1, shift: Bool = false, state: OMSState = .touching) -> OMSRawTouch {
        OMSRawTouch(id: id, posX: shift ? 72.5 / 160 : 27.5 / 160, posY: 1 - 55 / 115,
            total: 1, pressure: 100, majorAxis: 5, minorAxis: 3, angle: 0, density: 1, state: state)
    }
    @discardableResult
    private func frame(_ run: ProductionReplaySession, _ time: Double, _ touches: [OMSRawTouch],
        side: Int = 0, reserved: Bool = false) -> RuntimeFrameDiagnostic? {
        let diagnostic = run.ingest(RuntimeRawFrame(sequence: UInt64(time * 1000), timestamp: time,
            deviceNumericID: side == 0 ? 42 : 43, deviceIndex: side, contacts: [], rawTouches: touches),
            suppressKeyboard: reserved)
        return diagnostic
    }
    private func keyCodes(_ run: ProductionReplaySession) -> [CGKeyCode] {
        run.output.events.compactMap {
            if case let .keyStroke(code, _, _) = $0.kind { return code }
            return nil
        }
    }
    func testReservationIncludesLiftFrameAndCannotCrossDevices() {
        var gate = GestureKeyboardArbitration()
        XCTAssertFalse(gate.process(device: 42, activeCount: 1) { _ in true })
        XCTAssertTrue(gate.process(device: 42, activeCount: 2) { $0 == .twoFingerTap })
        for count in [1, 3, 4, 5] {
            XCTAssertTrue(gate.process(device: 42, activeCount: count) { _ in false })
        }
        XCTAssertFalse(gate.process(device: 43, activeCount: 1) { _ in true })
        XCTAssertTrue(gate.process(device: 42, activeCount: 0) { _ in false })
        XCTAssertFalse(gate.process(device: 42, activeCount: 1) { _ in true })
        XCTAssertFalse(gate.process(device: 42, activeCount: 2) { _ in false })
    }
    func testEachConfiguredInputReservesItsChordRegardlessOfChosenAction() {
        for trigger in GestureTrigger.allCases {
            let count = trigger == .fourFingerMove ? 4 : (trigger == .twoFingerMove || trigger == .twoFingerTap ? 2 : 3)
            var gate = GestureKeyboardArbitration()
            XCTAssertTrue(gate.process(device: 42, activeCount: count) { $0 == trigger })
        }
    }
    func testReservedPairCannotTypeOrHoldAndSurvivingFingerStaysSuppressed() {
        let run = session()
        frame(run, 1, [touch(state: .making)])
        let diagnostic = frame(run, 1.03, [touch(), touch(2, shift: true)], reserved: true)
        XCTAssertTrue(diagnostic?.touches.contains { $0.reason == "gestureReserved" } ?? false)
        frame(run, 1.06, [touch()]) // caller no longer requests; engine still latches.
        frame(run, 1.4, [touch()])
        frame(run, 1.45, [touch(state: .breaking)])
        frame(run, 1.46, [])
        run.finish(at: 2)
        XCTAssertTrue(run.output.events.isEmpty)
    }
    func testClaimBalancesAlreadyHeldModifierBeforeSuppressingRemainingCycle() {
        let run = session()
        frame(run, 1, [touch(1, shift: true, state: .making)])
        frame(run, 1.03, [touch(1, shift: true), touch(2)], reserved: true)
        frame(run, 1.06, [touch(1, shift: true, state: .breaking), touch(2, state: .breaking)])
        frame(run, 1.07, [])
        run.finish(at: 2)
        let edges = run.output.events.compactMap { event -> Bool? in
            if case let .key(code, _, down, _) = event.kind, code == kVK_Shift { return down }
            return nil
        }
        XCTAssertEqual(edges, [true, false])
        XCTAssertTrue(keyCodes(run).isEmpty)
    }
    func testOtherHandKeepsTypingAndOneFingerWorksAfterReservedCycle() {
        let run = session()
        frame(run, 1, [touch(state: .making)], side: 1)
        frame(run, 1.01, [touch(), touch(2, shift: true)], reserved: true)
        frame(run, 1.03, [touch()], side: 1)
        frame(run, 1.04, [touch(state: .breaking)], side: 1)
        frame(run, 1.05, [], side: 1)
        frame(run, 1.06, [])
        frame(run, 1.1, [touch(state: .making)])
        frame(run, 1.15, [touch(state: .breaking)])
        frame(run, 1.16, [])
        run.finish(at: 2)
        XCTAssertEqual(keyCodes(run), [CGKeyCode(kVK_ANSI_F), CGKeyCode(kVK_ANSI_F)])
    }
}
