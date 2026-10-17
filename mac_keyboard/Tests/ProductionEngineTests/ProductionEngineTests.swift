import Carbon
import CoreGraphics
import Foundation
import OpenMultitouchSupport
import XCTest
@testable import GlassToKeyRuntime

@MainActor
final class ProductionEngineTests: XCTestCase {
    private func session(labels: [String] = ["F", "Shift", "G"], keyboardOnly: Bool = true) -> ProductionReplaySession {
        let session = ProductionReplaySession(startTime: 1)
        let engine = session.engine
        let size = CGSize(width: 160, height: 115)
        let rects = labels.indices.map { index in
            CGRect(x: 10 + index * 45, y: 40, width: 35, height: 30)
        }
        let layout = ContentViewModel.Layout(keyRects: [rects], trackpadSize: size, allowHoldBindings: false)
        engine.updateLayouts(leftLayout: layout, rightLayout: layout,
                             leftLabels: [labels], rightLabels: [labels],
                             trackpadSize: size, trackpadWidthMm: 160)
        engine.updateActiveDevices(leftIndex: 0, rightIndex: 1, leftDeviceID: "42", rightDeviceID: "43")
        engine.updateKeyboardModeEnabled(keyboardOnly)
        engine.updateForceClickMin(0)
        engine.updateForceClickCap(1000)
        engine.updateHapticStrength(0)
        engine.updateSnapRadiusPercent(0)
        engine.setListening(true)
        engine.setCaptureFrameDiagnosticsEnabled(true)
        return session
    }

    private func contact(_ id: Int32 = 1, key: Int = 0, state: OMSState = .touching,
                         x: Float? = nil) -> OMSRawTouch {
        OMSRawTouch(id: id, posX: x ?? Float(27.5 + Double(key) * 45) / 160,
                    posY: 1 - 55.0 / 115.0, total: 1, pressure: 100,
                    majorAxis: 5, minorAxis: 3, angle: 0, density: 1, state: state)
    }

    @discardableResult
    private func frame(_ session: ProductionReplaySession, _ time: Double, _ contacts: [OMSRawTouch],
                       side: Int = 0) -> RuntimeFrameDiagnostic? {
        session.ingest(RuntimeRawFrame(sequence: UInt64((time * 1000).rounded()), timestamp: time,
                                       deviceNumericID: side == 0 ? 42 : 43, deviceIndex: side,
                                       contacts: [], rawTouches: contacts))
    }

    private func keys(_ session: ProductionReplaySession) -> [String] {
        session.output.events.compactMap { event in
            switch event.kind {
            case let .keyStroke(code, flags, _): return "tap:\(code):\(flags.rawValue)"
            case let .key(code, flags, down, _): return "\(down ? "down" : "up"):\(code):\(flags.rawValue)"
            default: return nil
            }
        }
    }

    func testTapSelectsFExactlyOnceAndDoesNotTriggerSwipe() async {
        let run = session()
        frame(run, 1.00, [contact(state: .making)])
        frame(run, 1.04, [contact()])
        frame(run, 1.08, [contact(state: .breaking)])
        frame(run, 1.10, [])
        run.finish(at: 2)
        XCTAssertEqual(keys(run), ["tap:\(kVK_ANSI_F):0"])
        XCTAssertEqual(run.output.events.count, 1)
    }

    func testShiftIsHeldForFAndReleased() async {
        let run = session()
        frame(run, 1.00, [contact(2, key: 1, state: .making)])
        frame(run, 1.04, [contact(2, key: 1)])
        frame(run, 1.06, [contact(2, key: 1), contact(1, state: .making)])
        frame(run, 1.10, [contact(2, key: 1), contact()])
        frame(run, 1.14, [contact(2, key: 1), contact(state: .breaking)])
        frame(run, 1.16, [contact(2, key: 1)])
        frame(run, 1.18, [contact(2, key: 1, state: .breaking)])
        frame(run, 1.20, [])
        run.finish(at: 2)
        XCTAssertEqual(keys(run), ["down:\(kVK_Shift):0", "tap:\(kVK_ANSI_F):\(CGEventFlags.maskShift.rawValue)", "up:\(kVK_Shift):0"])
    }

    func testResetReleasesModifierWithoutAReleaseFrame() async {
        let run = session()
        frame(run, 1.00, [contact(key: 1, state: .making)])
        frame(run, 1.04, [contact(key: 1)])
        run.engine.resetState()
        XCTAssertEqual(keys(run), ["down:\(kVK_Shift):0", "up:\(kVK_Shift):0"])
        run.scheduler.advance(to: 3)
        XCTAssertEqual(keys(run).count, 2)
    }

    func testOverlappingTouchesOnBothPadsProduceBothKeys() async {
        let run = session()
        frame(run, 1.00, [contact(state: .making)])
        frame(run, 1.01, [contact(1, key: 2, state: .making)], side: 1)
        frame(run, 1.04, [contact()])
        frame(run, 1.05, [contact(1, key: 2)], side: 1)
        frame(run, 1.08, [contact(state: .breaking)])
        frame(run, 1.09, [contact(1, key: 2, state: .breaking)], side: 1)
        frame(run, 1.10, [])
        frame(run, 1.11, [], side: 1)
        run.finish(at: 2)
        XCTAssertEqual(keys(run), ["tap:\(kVK_ANSI_F):0", "tap:\(kVK_ANSI_G):0"])
    }

    func testTwoFingerMotionSuppressesTyping() async {
        let run = session(keyboardOnly: false)
        frame(run, 1.00, [contact(1, state: .making), contact(2, key: 2, state: .making)])
        frame(run, 1.04, [contact(1), contact(2, key: 2)])
        frame(run, 1.08, [contact(1, x: 0.28), contact(2, key: 2, x: 0.84)])
        frame(run, 1.12, [contact(1, state: .breaking, x: 0.28),
                          contact(2, key: 2, state: .breaking, x: 0.84)])
        frame(run, 1.14, [])
        run.finish(at: 2)
        XCTAssertTrue(keys(run).isEmpty, "A multi-finger movement must not leak F/G taps")
    }

    func testMouseMotionLatchesUntilAllUpAndNextTapTypes() async {
        let run = session(keyboardOnly: false)
        frame(run, 1.00, [contact(state: .making)])
        frame(run, 1.02, [contact(x: 0.25)])
        XCTAssertEqual(run.output.intents.left, .mouse)
        frame(run, 1.04, [contact()])
        frame(run, 1.06, [contact(state: .breaking)])
        frame(run, 1.08, [])
        XCTAssertTrue(keys(run).isEmpty)
        frame(run, 1.10, [contact(state: .making)])
        frame(run, 1.12, [contact(state: .breaking)])
        XCTAssertEqual(keys(run), ["tap:\(kVK_ANSI_F):0"])
    }

    func testLegacyTuningCannotRejectStationaryLongTap() async {
        let run = session()
        run.engine.updateHoldThreshold(0.001)
        run.engine.updateForceClickMin(255)
        run.engine.updateForceClickCap(0)
        run.engine.updateDragCancelDistance(0)
        run.engine.updateIntentMoveThreshold(0)
        run.engine.updateHoldRepeatEnabled(true)
        frame(run, 1.00, [contact(state: .making)])
        frame(run, 2.00, [contact()])
        frame(run, 2.10, [contact(state: .breaking)])
        XCTAssertEqual(keys(run), ["tap:\(kVK_ANSI_F):0"])
    }

    func testMovementReportedOnlyOnReleaseStillSelectsMouse() async {
        let run = session()
        frame(run, 1.00, [contact(state: .making)])
        frame(run, 1.04, [contact(state: .breaking, x: 0.25)])
        XCTAssertTrue(keys(run).isEmpty)
    }

    func testEmptyFrameReleasesHeldModifier() async {
        let run = session()
        frame(run, 1.00, [contact(key: 1, state: .making)])
        frame(run, 1.04, [])
        XCTAssertEqual(keys(run), ["down:\(kVK_Shift):0", "up:\(kVK_Shift):0"])
    }
}
