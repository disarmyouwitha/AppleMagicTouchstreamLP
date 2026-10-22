import CoreGraphics
import OpenMultitouchSupport
import XCTest
@testable import GlassToKeyRuntime

final class TwoFingerTapTests: XCTestCase {
    private func touch(_ id: Int32, _ x: Float = 0.3) -> OMSRawTouch {
        OMSRawTouch(id:id,posX:x,posY:0.5,total:1,pressure:100,majorAxis:5,minorAxis:3,
            angle:0,density:1,state:.touching)
    }
    private var pair: [OMSRawTouch] { [touch(1),touch(2,0.6)] }
    private var empty: [OMSRawTouch] { [] }
    func testTwoFingerTapClicksOnlyOnceOnAllUpWithEitherFingerLiftingFirst() {
        for survivor: Int32 in [1,2] {
            var tap = TwoFingerTapRecognizer()
            XCTAssertFalse(tap.process(device:1,time:1,contacts:[touch(1)]))
            XCTAssertFalse(tap.process(device:1,time:1.03,contacts:pair))
            let remaining = survivor == 1 ? touch(1) : touch(2,0.6)
            XCTAssertFalse(tap.process(device:1,time:1.08,contacts:[remaining]))
            XCTAssertTrue(tap.process(device:1,time:1.1,contacts:empty))
            XCTAssertFalse(tap.process(device:1,time:1.11,contacts:empty))
        }
    }
    func testSingleFingerHoldLatePairExtraFingerAndMovementDoNotClick() {
        for kind in 0..<5 {
            var tap = TwoFingerTapRecognizer()
            _ = tap.process(device:1,time:1,contacts:kind == 0 || kind == 2 ? [touch(1)] : pair)
            switch kind {
            case 0: break
            case 1:
                _ = tap.process(device:1,time:1.1,contacts:pair)
                _ = tap.process(device:1,time:1.2,contacts:pair)
                _ = tap.process(device:1,time:1.3,contacts:pair)
                _ = tap.process(device:1,time:1.4,contacts:pair)
                _ = tap.process(device:1,time:1.5,contacts:pair)
                _ = tap.process(device:1,time:1.6,contacts:pair)
            case 2: _ = tap.process(device:1,time:1.1,contacts:pair)
            case 3: _ = tap.process(device:1,time:1.03,contacts:pair+[touch(3,0.8)])
            default:
                // Opposing motion has no centroid travel, but is not a tap.
                _ = tap.process(device:1,time:1.03,contacts:[touch(1,0.28),touch(2,0.62)])
            }
            XCTAssertFalse(tap.process(device:1,time:kind == 1 ? 1.61 : 1.12,contacts:empty),"kind=\(kind)")
        }
    }
    func testHalfSecondTapWindowIncludingReleaseBoundary() {
        for (release,accepted) in [(1.49,true),(1.5,true),(1.501,false)] {
            var tap = TwoFingerTapRecognizer()
            _ = tap.process(device:1,time:1,contacts:pair)
            for frame in [1.1,1.2,1.3,1.4] {
                XCTAssertFalse(tap.process(device:1,time:frame,contacts:pair))
            }
            XCTAssertEqual(tap.process(device:1,time:release,contacts:empty),accepted)
        }
    }

    func testLongStaggeredReleaseRejoinAndIdentityReplacementRejectTap() {
        for kind in 0..<3 {
            var tap = TwoFingerTapRecognizer()
            _ = tap.process(device:1,time:1,contacts:pair)
            _ = tap.process(device:1,time:1.04,contacts:[touch(1)])
            if kind == 1 { _ = tap.process(device:1,time:1.06,contacts:pair) }
            if kind == 2 { _ = tap.process(device:1,time:1.06,contacts:[touch(9)]) }
            XCTAssertFalse(tap.process(device:1,time:kind == 0 ? 1.14 : 1.08,contacts:empty))
        }
    }
    func testMovementRecognitionCancelsTapAndCannotClickWhenMousingEnds() {
        var tap = TwoFingerTapRecognizer()
        var router = TrackpadGestureRouter()
        for (time,contacts) in [(1.0,pair),(1.02,[touch(1,0.303),touch(2,0.603)]),(1.06,empty)] {
            let motion = router.process(device:1,time:time,contacts:contacts,mouse:true,scroll:true)
            XCTAssertFalse(tap.process(device:1,time:time,contacts:contacts,gestureActive:motion != nil))
        }
    }
    func testSmallLandingDriftStaysTapButClearMovementClaimsMouse() {
        for (offset,expectedClick) in [(Float(0.0015),true),(Float(0.003),false)] {
            var tap = TwoFingerTapRecognizer()
            var router = TrackpadGestureRouter()
            for (time,contacts) in [(1.0,pair),(1.04,[touch(1,0.3+offset),touch(2,0.6+offset)])] {
                let motion = router.process(device:1,time:time,contacts:contacts,mouse:true,scroll:true)
                XCTAssertFalse(tap.process(device:1,time:time,contacts:contacts,gestureActive:motion != nil))
            }
            let motion = router.process(device:1,time:1.08,contacts:empty,mouse:true,scroll:true)
            XCTAssertEqual(tap.process(device:1,time:1.08,contacts:empty,gestureActive:motion != nil),expectedClick)
        }
    }

    func testStaleInvalidDuplicateAndUnorderedFramesCannotClick() {
        for kind in 0..<4 {
            var tap = TwoFingerTapRecognizer()
            _ = tap.process(device:1,time:1,contacts:pair)
            switch kind {
            case 0: _ = tap.process(device:1,time:1.2,contacts:pair)
            case 1: _ = tap.process(device:1,time:1.02,contacts:[touch(1,.nan),touch(2)])
            case 2: _ = tap.process(device:1,time:1.02,contacts:[touch(1),touch(1)])
            default: _ = tap.process(device:1,time:1,contacts:pair)
            }
            XCTAssertFalse(tap.process(device:1,time:1.22,contacts:empty))
        }
    }
    func testCancellationBlocksUntilAllUpButIdleWatchdogDoesNotEatNextTap() {
        var tap = TwoFingerTapRecognizer()
        tap.invalidate(device:1) // no pending tap; inactive status watchdog
        _ = tap.process(device:1,time:1,contacts:pair)
        XCTAssertTrue(tap.process(device:1,time:1.06,contacts:empty))
        _ = tap.process(device:1,time:2,contacts:pair)
        tap.reset() // feature/selection/lifecycle cancellation
        _ = tap.process(device:1,time:2.03,contacts:pair)
        XCTAssertFalse(tap.process(device:1,time:2.06,contacts:empty))
        tap.cancel(device:1) // physical button or touch braking momentum
        _ = tap.process(device:1,time:3,contacts:pair)
        XCTAssertFalse(tap.process(device:1,time:3.06,contacts:empty))
        _ = tap.process(device:1,time:4,contacts:pair)
        XCTAssertTrue(tap.process(device:1,time:4.06,contacts:empty))
    }
    func testPadsAreIndependentAndShortBounceDoesNotClick() {
        var tap = TwoFingerTapRecognizer()
        _ = tap.process(device:1,time:1,contacts:pair)
        _ = tap.process(device:2,time:1.01,contacts:[touch(1)])
        XCTAssertFalse(tap.process(device:2,time:1.06,contacts:empty))
        XCTAssertTrue(tap.process(device:1,time:1.07,contacts:empty))
        _ = tap.process(device:1,time:2,contacts:pair)
        XCTAssertFalse(tap.process(device:1,time:2.005,contacts:empty))
    }
    func testClickEdgesLocationFlagsTagAndDoubleClickCountWithoutPosting() throws {
        var output = PrimaryTapClickOutput()
        let point = CGPoint(x:120,y:230)
        let first = try XCTUnwrap(output.events(location:point,time:1,doubleClickInterval:0.5,flags:.maskShift))
        XCTAssertEqual(first.down.type,.leftMouseDown); XCTAssertEqual(first.up.type,.leftMouseUp)
        XCTAssertEqual(first.down.location,point); XCTAssertEqual(first.up.location,point)
        XCTAssertEqual(first.down.flags,.maskShift); XCTAssertEqual(first.up.flags,.maskShift)
        XCTAssertEqual(first.down.getIntegerValueField(.mouseEventButtonNumber),0)
        XCTAssertEqual(first.up.getIntegerValueField(.mouseEventButtonNumber),0)
        XCTAssertEqual(first.down.getIntegerValueField(.eventSourceUserData),SelectedTrackpadEventPolicy.interpreterTag)
        XCTAssertEqual(first.up.getDoubleValueField(.mouseEventPressure),0)
        XCTAssertEqual(first.down.getIntegerValueField(.mouseEventClickState),1)
        let second = try XCTUnwrap(output.events(location:point,time:1.2,doubleClickInterval:0.5,flags:.maskShift))
        XCTAssertEqual(second.down.getIntegerValueField(.mouseEventClickState),2)
        XCTAssertEqual(second.up.getIntegerValueField(.mouseEventClickState),2)
        XCTAssertEqual(output.events(location:point,time:1.3,doubleClickInterval:0.5)?.down.getIntegerValueField(.mouseEventClickState),1)
        XCTAssertEqual(output.events(location:CGPoint(x:200,y:300),time:1.4,doubleClickInterval:0.5)?.down.getIntegerValueField(.mouseEventClickState),1)
        output.reset()
        XCTAssertEqual(output.events(location:point,time:1.5,doubleClickInterval:0.5)?.down.getIntegerValueField(.mouseEventClickState),1)
    }
}
