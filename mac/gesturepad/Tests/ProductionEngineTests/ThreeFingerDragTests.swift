import CoreGraphics
import OpenMultitouchSupport
import XCTest
@testable import GesturePadRuntime

final class ThreeFingerDragTests: XCTestCase {
    private func touches(_ count: Int = 3, dx: Float = 0, triangular: Bool = false, thumb: Bool = false) -> [OMSRawTouch] {
        (0..<count).map { index in
            let telemetry: OMSTouchTelemetry? = thumb ? OMSTouchTelemetry(
                fingerID:index == 0 ? 1 : Int32(index+2),handID:1,velocityX:0,velocityY:0,
                absoluteX:0,absoluteY:0,absoluteVelocityX:0,absoluteVelocityY:0,sourceFrame:1,sourceTimestamp:1) : nil
            return OMSRawTouch(id:Int32(index+1),posX:0.3+Float(index)*0.11+dx,
                posY:triangular && index == 1 ? 0.8 : 0.5,total:1,pressure:100,
                majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching,telemetry:telemetry)
        }
    }
    func testCloseAlignedChordRejectsThumbTriangleAndSpread() {
        XCTAssertTrue(ThreeFingerDragChord.accepts(touches()))
        XCTAssertFalse(ThreeFingerDragChord.accepts(touches(thumb:true)))
        XCTAssertFalse(ThreeFingerDragChord.accepts(touches(triangular:true)))
        XCTAssertFalse(ThreeFingerDragChord.accepts(touches(2)))
        let spread = touches().enumerated().map { index,t in
            OMSRawTouch(id:t.id,posX:Float(index)*0.4,posY:t.posY,total:1,pressure:100,
                majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
        }
        XCTAssertFalse(ThreeFingerDragChord.accepts(spread))
        // Geometry does not assume the user's hand is perfectly horizontal.
        let rotated = touches().map { t in
            OMSRawTouch(id:t.id,posX:0.5,posY:0.2+(t.posX-0.3)*160/114.9,total:1,
                pressure:100,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
        }
        XCTAssertTrue(ThreeFingerDragChord.accepts(rotated))
    }
    func testDragClaimsMovementAndLatchesAcrossCountsThenEnds() {
        var router = TrackpadGestureRouter()
        XCTAssertNil(router.process(device:1,time:1,contacts:touches(),mouse:true,scroll:true,drag:true))
        let begin = router.update(device:1,time:1.02,contacts:touches(dx:0.003),mouse:true,scroll:true,drag:true)
        XCTAssertEqual(begin.gesture,.drag); XCTAssertEqual(begin.phase,.began)
        for (time,count) in [(1.04,1),(1.06,4),(1.08,2)] {
            let step = router.update(device:1,time:time,contacts:touches(count,dx:Float(time-1)*0.1),mouse:true,scroll:true,drag:true)
            XCTAssertEqual(step.gesture,.drag); XCTAssertEqual(step.phase,.changed)
        }
        let end = router.update(device:1,time:1.1,contacts:touches(0),mouse:true,scroll:true,drag:true)
        XCTAssertEqual(end.gesture,.drag); XCTAssertEqual(end.phase,.ended)
    }
    func testRejectedChordsNeverDragAndExistingMouseNeverSwitches() {
        for (triangle,thumb) in [(true,false),(false,true)] {
            var router = TrackpadGestureRouter()
            for (time,dx) in [(1.0,Float(0)),(1.02,Float(0.004))] {
                XCTAssertNil(router.process(device:1,time:time,contacts:touches(dx:dx,triangular:triangle,thumb:thumb),mouse:true,scroll:true,drag:true))
            }
        }
        var router = TrackpadGestureRouter()
        _ = router.process(device:1,time:1,contacts:touches(2),mouse:true,scroll:true,drag:true)
        XCTAssertEqual(router.process(device:1,time:1.02,contacts:touches(2,dx:0.004),mouse:true,scroll:true,drag:true)?.gesture,.mouse)
        XCTAssertEqual(router.process(device:1,time:1.04,contacts:touches(dx:0.005),mouse:true,scroll:true,drag:true)?.gesture,.mouse)
    }
    func testStationaryTapDoubleClicksButDragNeverClicksOnLift() {
        for moving in [false,true] {
            var router = TrackpadGestureRouter(), taps = TwoFingerTapRecognizer(requiredCount:3)
            var clicks = 0
            for (time,contacts) in [(1.0,touches()),(1.04,touches(dx:moving ? 0.003 : 0)),(1.08,touches(0))] {
                let motion = router.process(device:1,time:time,contacts:contacts,mouse:true,scroll:true,drag:true)
                if taps.process(device:1,time:time,contacts:contacts,gestureActive:motion != nil) { clicks += 1 }
            }
            XCTAssertEqual(clicks,moving ? 0 : 1)
        }
    }
    func testDiscontinuityAndDisablingReportCancellation() {
        for disabled in [false,true] {
            var router = TrackpadGestureRouter()
            _ = router.update(device:1,time:1,contacts:touches(),mouse:true,scroll:true,drag:true)
            _ = router.update(device:1,time:1.02,contacts:touches(dx:0.004),mouse:true,scroll:true,drag:true)
            let cancelled = router.update(device:1,time:disabled ? 1.04 : 1.3,contacts:touches(dx:0.005),mouse:true,scroll:true,drag:!disabled)
            XCTAssertEqual(cancelled.phase,.cancelled); XCTAssertEqual(cancelled.gesture,.drag)
        }
    }
    func testOutputHasOneOwnerBalancedEdgesLatestLocationAndIdempotentCleanup() throws {
        var drag = PrimaryDragOutput()
        let down = try XCTUnwrap(drag.begin(device:1,location:CGPoint(x:10,y:20),flags:.maskShift))
        XCTAssertEqual(down.type,.leftMouseDown)
        XCTAssertNil(drag.begin(device:2,location:.zero,flags:[]))
        XCTAssertNil(drag.end(device:2)); XCTAssertEqual(drag.owner,1)
        let move = try XCTUnwrap(drag.move(device:1,location:CGPoint(x:30,y:40),delta:CGPoint(x:20,y:20),flags:.maskCommand))
        XCTAssertEqual(move.type,.leftMouseDragged)
        XCTAssertEqual(move.getDoubleValueField(.mouseEventDeltaX),20)
        XCTAssertNil(drag.move(device:1,location:CGPoint(x:Double.nan,y:0),delta:.zero,flags:[]))
        XCTAssertEqual(drag.owner,1) // failed allocation/input still leaves reserved cleanup available
        let up = try XCTUnwrap(drag.end())
        XCTAssertEqual(up.type,.leftMouseUp); XCTAssertEqual(up.location,move.location)
        XCTAssertEqual(up.flags,.maskCommand)
        for event in [down,move,up] {
            XCTAssertEqual(event.getIntegerValueField(.mouseEventClickState),1)
            XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData),SelectedTrackpadEventPolicy.interpreterTag)
        }
        XCTAssertEqual(up.getDoubleValueField(.mouseEventPressure),0)
        XCTAssertNil(drag.owner); XCTAssertNil(drag.end()); XCTAssertNil(drag.move(device:1,location:.zero,delta:.zero,flags:[]))
        XCTAssertNil(drag.begin(device:1,location:CGPoint(x:Double.nan,y:0),flags:[]))
        XCTAssertNotNil(drag.begin(device:2,location:.zero,flags:[]))
        XCTAssertEqual(drag.end(device:2,location:CGPoint(x:9,y:8))?.location,CGPoint(x:9,y:8))
    }
}
