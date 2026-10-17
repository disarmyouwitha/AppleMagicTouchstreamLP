import Carbon
import CoreGraphics
import Foundation
import OpenMultitouchSupport
import XCTest
@testable import GesturePadRuntime

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

    private func noGestures() -> GestureActionSet {
        GestureActionSet(
            twoFingerTap: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            threeFingerTap: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            twoFingerHold: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            threeFingerHold: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            fourFingerHold: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            outerCornersHold: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            innerCornersHold: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            leftEdgeUp: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            leftEdgeDown: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            rightEdgeUp: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            rightEdgeDown: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            topEdgeLeft: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            topEdgeRight: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            bottomEdgeLeft: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            bottomEdgeRight: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            threeFingerSwipeLeft: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            threeFingerSwipeRight: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            threeFingerSwipeUp: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            threeFingerSwipeDown: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            fourFingerSwipeLeft: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            fourFingerSwipeRight: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            fourFingerSwipeUp: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            fourFingerSwipeDown: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            fiveFingerSwipeLeft: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            fiveFingerSwipeRight: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            fiveFingerSwipeUp: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            fiveFingerSwipeDown: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            topLeftCornerSwipe: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            topRightCornerSwipe: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            bottomLeftCornerSwipe: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            bottomRightCornerSwipe: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            topLeftTriangle: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            topRightTriangle: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            bottomLeftTriangle: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            bottomRightTriangle: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            upperLeftCornerClick: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            upperRightCornerClick: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            lowerLeftCornerClick: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            lowerRightCornerClick: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            threeFingerClick: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            fourFingerClick: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            topLeftForceClick: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            topRightForceClick: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            bottomLeftForceClick: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            bottomRightForceClick: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none)
        )
    }
    func testKeyboardLandingNeverDispatchesEvenWithLegacyKeyboardMode() async {
        let run = session()
        run.engine.updateGestureActions(noGestures())
        frame(run, 1.00, [contact(state: .making)])
        frame(run, 1.04, [contact()])
        frame(run, 1.08, [contact(state: .breaking)])
        frame(run, 1.10, [])
        run.finish(at: 2)
        XCTAssertTrue(run.output.events.isEmpty)
    }

    func testLegacyThreeFingerSwipeDoesNotDispatch() async {
        let run = session()
        var actions = noGestures()
        actions.threeFingerSwipeRight = KeyActionCatalog.action(for: "F")!
        run.engine.updateGestureActions(actions)
        frame(run, 1.00, [contact(1, x: 0.4), contact(2, x: 0.5), contact(3, x: 0.6)])
        frame(run, 1.06, [contact(1, x: 0.5), contact(2, x: 0.6), contact(3, x: 0.7)])
        frame(run, 1.12, [])
        XCTAssertTrue(run.output.events.isEmpty)
    }

    func testLegacyTwoFingerTapDoesNotDispatch() async {
        let run = session()
        var actions = noGestures()
        actions.twoFingerTap = KeyAction(label: "Left Click", keyCode: 0, flags: 0, kind: .leftClick)
        run.engine.updateGestureActions(actions)
        frame(run, 1.00, [contact(1, x: 0.4), contact(2, x: 0.6)])
        frame(run, 1.04, [contact(1, x: 0.4), contact(2, x: 0.6)])
        frame(run, 1.08, [])
        XCTAssertTrue(keys(run).isEmpty)
        XCTAssertTrue(run.output.events.isEmpty)
    }
}
