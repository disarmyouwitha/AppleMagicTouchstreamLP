import CoreGraphics
import OpenMultitouchSupport
import XCTest
@testable import GlassToKeyRuntime

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

    func testHoverAndOneFingerCannotStartThePointer() {
        var tracker = TwoFingerPointerTracker()
        XCTAssertNil(tracker.process(device: 42, time: 1, contacts: [touch(1,0.2)]))
        XCTAssertNil(tracker.process(device: 42, time: 1.01,
            contacts: [touch(1,0.3),touch(2,0.5,state:.starting)]))
        XCTAssertNil(tracker.process(device: 42, time: 1.02, contacts: [touch(1,0.3),touch(2,0.5)]))
        XCTAssertNotNil(tracker.process(device: 42, time: 1.03, contacts: [touch(1,0.31),touch(2,0.51)]))
    }

    func testTwoFingerLatchContinuesWithEitherSurvivorUntilAllLift() throws {
        for survivor: Int32 in [1, 2] {
            var tracker = TwoFingerPointerTracker()
            _ = tracker.process(device: 42, time: 1, contacts: [touch(1,0.2),touch(2,0.7)])
            // Stationary survivor: no centroid jump when the distant finger lifts.
            let survivorX: Float = survivor == 1 ? 0.2 : 0.7
            XCTAssertEqual(tracker.process(device: 42, time: 1.01, contacts: [touch(survivor,survivorX)])?.x,0)
            let moved = try XCTUnwrap(tracker.process(device: 42, time: 1.02, contacts: [touch(survivor,survivorX+0.01)]))
            XCTAssertEqual(moved.x,9.6,accuracy:0.001)
            // Rejoining the chord cannot introduce the new contact's position.
            let rejoined = survivor == 1
                ? [touch(1,survivorX+0.01),touch(2,0.7)]
                : [touch(1,0.3),touch(2,survivorX+0.01)]
            XCTAssertEqual(tracker.process(device: 42, time: 1.03, contacts: rejoined)?.x,0)
            XCTAssertNotNil(tracker.process(device: 42, time: 1.04, contacts: [touch(1,0.31),touch(2,0.71)]))
            XCTAssertNil(tracker.process(device: 42, time: 1.05, contacts: [OMSRawTouch]()))
            XCTAssertNil(tracker.process(device: 42, time: 1.06, contacts: [touch(1,0.4)]))
            XCTAssertNil(tracker.process(device: 42, time: 1.07, contacts: [touch(1,0.41)]))
        }
    }

    func testLatchCannotCrossPadsStaleFramesResetOrContactReplacement() {
        var tracker = TwoFingerPointerTracker()
        let pair = [touch(1,0.2),touch(2,0.4)]
        _ = tracker.process(device: 42, time: 1, contacts: pair)
        XCTAssertNil(tracker.process(device: 99, time: 1.01, contacts: [touch(1,0.2)]))
        XCTAssertNil(tracker.process(device: 99, time: 1.02, contacts: [touch(1,0.3)]))
        XCTAssertNil(tracker.process(device: 42, time: 1.01, contacts: [touch(9,0.3)]))
        XCTAssertNil(tracker.process(device: 42, time: 1.02, contacts: [touch(9,0.4)]))
        _ = tracker.process(device: 42, time: 2, contacts: pair)
        XCTAssertNil(tracker.process(device: 42, time: 3, contacts: [touch(1,0.2)]))
        XCTAssertNil(tracker.process(device: 42, time: 3.01, contacts: [touch(1,0.3)]))
        _ = tracker.process(device: 42, time: 4, contacts: pair)
        tracker.reset(device:42)
        XCTAssertNil(tracker.process(device: 42, time: 4.01, contacts: [touch(1,0.2)]))
        XCTAssertNil(tracker.process(device: 42, time: 4.02, contacts: [touch(1,0.3)]))
    }

    func testExtraContactsDoNotActivateButDoNotCancelExistingLatch() {
        var tracker = TwoFingerPointerTracker()
        let pair = [touch(1,0.2),touch(2,0.4)]
        _ = tracker.process(device: 42, time: 1, contacts: pair+[touch(3,0.6)])
        _ = tracker.process(device: 42, time: 1.01, contacts: [touch(1,0.2)])
        XCTAssertNil(tracker.process(device: 42, time: 1.02, contacts: [touch(1,0.3)]))
        _ = tracker.process(device: 42, time: 1.03, contacts: pair)
        _ = tracker.process(device: 42, time: 1.04, contacts: pair+[touch(3,0.6)])
        XCTAssertEqual(tracker.process(device: 42, time: 1.05, contacts: [touch(1,0.2)])?.x,0)
        XCTAssertNotNil(tracker.process(device: 42, time: 1.06, contacts: [touch(1,0.21)]))
    }

    func testSymmetricPinchHasNoCentroidTranslationAndDoesNotEmitZoom() {
        var tracker = TwoFingerPointerTracker()
        _ = tracker.process(device: 42, time: 1, contacts: [touch(1,0.25),touch(2,0.75)])
        let delta = tracker.process(device: 42, time: 1.01, contacts: [touch(1,0.125),touch(2,0.875)])
        XCTAssertEqual(delta?.x, 0)
        XCTAssertEqual(delta?.y, 0)
    }

    func testLatchMovesThroughTwoThreeFourOneContactsWithoutMembershipJumps() throws {
        var tracker = TwoFingerPointerTracker()
        var time = 1.0
        let pair = [touch(1,0.2),touch(2,0.4)]
        _ = tracker.process(device: 42, time: time, contacts: pair)
        let frames = [
            [touch(1,0.21),touch(2,0.41),touch(3,0.9)],
            [touch(3,0.91),touch(2,0.42),touch(4,0.05),touch(1,0.22)],
            [touch(4,0.06),touch(2,0.43),touch(1,0.23),touch(3,0.92)],
            [touch(1,0.24),touch(4,0.07)],
            [touch(4,0.08)],
        ]
        for contacts in frames {
            time += 0.01
            let delta = try XCTUnwrap(tracker.process(device: 42, time: time, contacts: contacts))
            XCTAssertEqual(delta.x,9.6,accuracy:0.001)
            XCTAssertEqual(delta.y,0,accuracy:0.001)
        }
        _ = tracker.process(device: 42, time: time+0.01, contacts: [OMSRawTouch]())
        XCTAssertNil(tracker.process(device: 42, time: time+0.02, contacts: [touch(4,0.1)]))
    }

    func testThreeOrFourContactsCannotStartWithoutTwoFingerActivation() {
        for count in [3,4] {
            var tracker = TwoFingerPointerTracker()
            let chord = (1...count).map { touch(Int32($0),Float($0)*0.1) }
            XCTAssertNil(tracker.process(device: 42, time: 1, contacts: chord))
            XCTAssertNil(tracker.process(device: 42, time: 1.01, contacts: chord))
        }
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
