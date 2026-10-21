import CoreGraphics
import OpenMultitouchSupport
import XCTest
@testable import GesturePadRuntime

final class NativeTwoFingerMouseTests: XCTestCase {
    private func touch(_ id: Int32, _ x: Float, _ y: Float = 0.5, state: OMSState = .touching) -> OMSRawTouch {
        OMSRawTouch(id: id, posX: x, posY: y, total: 1, pressure: 100,
            majorAxis: 2, minorAxis: 1, angle: 0, density: 1, state: state)
    }

    func testOutputRequiresOptInTakeoverOwnershipAndPermission() {
        func eligible(_ enabled: Bool = true, _ armed: Bool = true, _ takeover: Bool = true,
                      _ trusted: Bool = true, owned: Set<UInt64> = [1]) -> Set<UInt64> {
            NativeTwoFingerMouseGate.outputDevices(enabled: enabled, armed: armed,
                takeoverEnabled: takeover, trusted: trusted, selected: [1], owned: owned)
        }
        XCTAssertEqual(eligible(), [1])
        XCTAssertTrue(eligible(false).isEmpty)
        XCTAssertTrue(eligible(true, false).isEmpty) // release/failed-transition pause
        XCTAssertTrue(eligible(true, true, false).isEmpty)
        XCTAssertTrue(eligible(true, true, true, false).isEmpty)
        XCTAssertTrue(eligible(owned: []).isEmpty)
    }

    func testOldPadAndFailedCleanupExtraOwnedPadAreNotOutputSources() {
        let allowed = NativeTwoFingerMouseGate.outputDevices(enabled: true, armed: true,
            takeoverEnabled: true, trusted: true, selected: [42,88], owned: [42,43,88,99])
        XCTAssertEqual(allowed, [42,88])
    }

    func testHoverAndOneFingerNeverMoveThePointer() {
        var tracker = TwoFingerPointerTracker()
        XCTAssertNil(tracker.process(device: 42, time: 1, contacts: [touch(1,0.2)]))
        XCTAssertNil(tracker.process(device: 42, time: 1.01,
            contacts: [touch(1,0.3),touch(2,0.5,state:.starting)]))
        XCTAssertNil(tracker.process(device: 42, time: 1.02, contacts: [touch(1,0.3),touch(2,0.5)]))
        XCTAssertNotNil(tracker.process(device: 42, time: 1.03, contacts: [touch(1,0.31),touch(2,0.51)]))
    }

    func testSymmetricPinchHasNoCentroidTranslationAndDoesNotEmitZoom() {
        var tracker = TwoFingerPointerTracker()
        _ = tracker.process(device: 42, time: 1, contacts: [touch(1,0.25),touch(2,0.75)])
        let delta = tracker.process(device: 42, time: 1.01, contacts: [touch(1,0.125),touch(2,0.875)])
        XCTAssertEqual(delta?.x, 0)
        XCTAssertEqual(delta?.y, 0)
    }

    func testThreeOrFourFingersResetRatherThanMovingPointer() {
        var tracker = TwoFingerPointerTracker()
        let pair = [touch(1,0.2),touch(2,0.4)]
        _ = tracker.process(device: 42, time: 1, contacts: pair)
        XCTAssertNil(tracker.process(device: 42, time: 1.01, contacts: pair+[touch(3,0.6)]))
        XCTAssertNil(tracker.process(device: 42, time: 1.02, contacts: pair))
        XCTAssertNil(tracker.process(device: 42, time: 1.03, contacts: pair+[touch(3,0.6),touch(4,0.8)]))
        XCTAssertNil(tracker.process(device: 42, time: 1.04, contacts: pair))
    }

    func testReleaseSelectionChangeAndLargeJumpsDoNotCarryMovement() {
        var tracker = TwoFingerPointerTracker()
        let pair = [touch(1,0.2),touch(2,0.4)]
        _ = tracker.process(device: 42, time: 1, contacts: pair)
        tracker.reset()
        XCTAssertNil(tracker.process(device: 42, time: 1.01, contacts: pair))
        XCTAssertNil(tracker.process(device: 88, time: 1.02, contacts: pair))
        XCTAssertNil(tracker.process(device: 88, time: 1.03, contacts: [touch(1,0.8),touch(2,1)]))
        // Rejected jump still establishes the next baseline rather than accumulating it.
        let next = tracker.process(device: 88, time: 1.04, contacts: [touch(1,0.801),touch(2,0.999)])
        XCTAssertEqual(next?.x ?? 999, 0, accuracy:0.001)
    }
}
