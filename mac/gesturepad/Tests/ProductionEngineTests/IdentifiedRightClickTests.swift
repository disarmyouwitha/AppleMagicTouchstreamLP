import CoreGraphics
import OpenMultitouchSupport
import XCTest
@testable import GesturePadRuntime

final class IdentifiedRightClickTests: XCTestCase {
    private func touches(_ fingers: [Int32], hand: Int32 = 1, dx: Float = 0) -> [OMSRawTouch] {
        fingers.enumerated().map { index,finger in
            OMSRawTouch(id:Int32(100+index*7),posX:((finger == 1 || (finger == 0 && index == 0)) ? 0.15 : 0.5+Float(index)*0.04)+dx,posY:((finger == 1 || (finger == 0 && index == 0)) ? 0.25 : 0.6),
                total:1,pressure:100,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching,
                telemetry:OMSTouchTelemetry(fingerID:finger,handID:hand,velocityX:0,velocityY:0,
                    absoluteX:0,absoluteY:0,absoluteVelocityX:0,absoluteVelocityY:0,sourceFrame:1,sourceTimestamp:1))
        }
    }
    private func tap(_ contacts: [OMSRawTouch], doubleClick: Bool = true, rightClick: Bool = true) -> ThreeFingerTapRecognizer.Action? {
        var recognizer = ThreeFingerTapRecognizer()
        XCTAssertNil(recognizer.process(device:1,time:1,contacts:contacts,doubleClick:doubleClick,rightClick:rightClick))
        XCTAssertNil(recognizer.process(device:1,time:1.04,contacts:contacts,doubleClick:doubleClick,rightClick:rightClick))
        return recognizer.process(device:1,time:1.08,contacts:[OMSRawTouch](),doubleClick:doubleClick,rightClick:rightClick)
    }
    func testExactAnatomicalChordOnEitherHandHasPriorityAndTrackingIDsAreNotFingerLabels() {
        for hand: Int32 in [1,2] {
            XCTAssertEqual(tap(touches([1,3,4],hand:hand)),.rightClick)
            XCTAssertEqual(tap(touches([4,1,3],hand:hand)),.rightClick)
        }
        XCTAssertEqual(tap(touches([2,3,4])),.doubleClick)
        XCTAssertEqual(tap(touches([0,0,0])),.doubleClick) // existing generic triple-tap compatibility
    }
    func testCompactThumbChordDoesNotClick() {
        let compact = touches([1,3,4]).enumerated().map { i,t in
            OMSRawTouch(id:t.id,posX:0.4+Float(i)*0.04,posY:0.5,total:t.total,pressure:t.pressure,majorAxis:t.majorAxis,minorAxis:t.minorAxis,angle:t.angle,density:t.density,state:t.state,telemetry:t.telemetry)
        }
        XCTAssertNil(tap(compact))
    }
    func testSpreadPairFallbackAndRelabeling() {
        for fingers: [Int32] in [[1,2,3],[1,3,4],[1,4,5],[1,3,5]] {
            XCTAssertEqual(tap(touches(fingers)),.rightClick)
        }
        var r = ThreeFingerTapRecognizer()
        _ = r.process(device:1,time:1,contacts:touches([1,3,4]),doubleClick:true,rightClick:true)
        _ = r.process(device:1,time:1.04,contacts:touches([1,4,5]),doubleClick:true,rightClick:true)
        XCTAssertEqual(r.process(device:1,time:1.08,contacts:[OMSRawTouch](),doubleClick:true,rightClick:true),.rightClick)
    }
    func testStaggeredLandingAndLiftNeverAlsoProducePrimaryClickOrDrag() {
        var recognizer = ThreeFingerTapRecognizer(), single = TwoFingerTapRecognizer(), router = TrackpadGestureRouter()
        let chord = touches([1,3,4])
        let frames: [(Double,[OMSRawTouch])] = [(1,Array(chord.prefix(1))),
            (1.02,Array(chord.prefix(2))),(1.04,Array(chord.reversed())),
            (1.08,Array(chord.suffix(2))),(1.1,Array(chord.suffix(1))),(1.12,[]),(1.13,[])]
        for (time,contacts) in frames {
            let motion = router.process(device:1,time:time,contacts:contacts,mouse:true,scroll:true,drag:true)
            XCTAssertNil(motion)
            XCTAssertFalse(single.process(device:1,time:time,contacts:contacts))
            XCTAssertEqual(recognizer.process(device:1,time:time,contacts:contacts,
                gestureActive:motion != nil,doubleClick:true,rightClick:true),time == 1.12 ? .rightClick : nil)
        }
    }
    func testWrongUnknownDuplicatedFingerLabelsAndMixedHandsCannotRightClick() {
        for fingers: [Int32] in [[0,3,4],[1,0,4],[1,3],[1,3,4,5]] {
            XCTAssertNil(tap(touches(fingers),doubleClick:false))
            if fingers.contains(1) { XCTAssertNil(tap(touches(fingers))) }
        }
        let a = touches([1,3,4],hand:1), b = touches([1,3,4],hand:2)
        XCTAssertNil(tap([a[0],b[1],a[2]]))
    }
    func testIndependentControlsReserveThumbChordEvenWhenRightClickDisabled() {
        XCTAssertNil(tap(touches([1,3,4]),rightClick:false))
        XCTAssertEqual(tap(touches([1,3,4]),doubleClick:false),.rightClick)
        XCTAssertNil(tap(touches([2,3,4]),doubleClick:false))
        XCTAssertNil(tap(touches([1,3,4]),doubleClick:false,rightClick:false))
    }
    func testIdentityMaySettleBeforeLiftButContradictoryKnownLabelsReject() {
        for conflicting in [false,true] {
            var recognizer = ThreeFingerTapRecognizer()
            _ = recognizer.process(device:1,time:1,contacts:touches([0,0,0]),doubleClick:true,rightClick:true)
            _ = recognizer.process(device:1,time:1.03,contacts:touches([1,3,4]),doubleClick:true,rightClick:true)
            _ = recognizer.process(device:1,time:1.06,contacts:touches(conflicting ? [2,3,4] : [0,0,0]),doubleClick:true,rightClick:true)
            XCTAssertEqual(recognizer.process(device:1,time:1.1,contacts:[OMSRawTouch](),doubleClick:true,rightClick:true),conflicting ? nil : .rightClick)
        }
    }
    func testHoldsMotionStaleFramesAndLifecycleCancellationDoNotRightClick() {
        for rejection in 0..<5 {
            var recognizer = ThreeFingerTapRecognizer()
            let chord = touches([1,3,4])
            _ = recognizer.process(device:1,time:1,contacts:chord,doubleClick:true,rightClick:true)
            switch rejection {
            case 0:
                for time in [1.1,1.2,1.3,1.4,1.5] {
                    _ = recognizer.process(device:1,time:time,contacts:chord,doubleClick:true,rightClick:true)
                }
            case 1: _ = recognizer.process(device:1,time:1.04,contacts:touches([1,3,4],dx:0.02),doubleClick:true,rightClick:true)
            case 2: _ = recognizer.process(device:1,time:1.3,contacts:chord,doubleClick:true,rightClick:true)
            case 3: recognizer.reset()
            default: recognizer.cancel(device:1)
            }
            XCTAssertNil(recognizer.process(device:1,time:rejection == 0 ? 1.51 : (rejection == 2 ? 1.35 : 1.08),
                contacts:[OMSRawTouch](),doubleClick:true,rightClick:true))
            _ = recognizer.process(device:1,time:2,contacts:chord,doubleClick:true,rightClick:true)
            XCTAssertEqual(recognizer.process(device:1,time:2.06,contacts:[OMSRawTouch](),doubleClick:true,rightClick:true),.rightClick)
        }
    }
    func testPerPadIsolationAndContinuousGestureCancellation() {
        var recognizer = ThreeFingerTapRecognizer()
        _ = recognizer.process(device:1,time:1,contacts:touches([1,3,4]),doubleClick:true,rightClick:true)
        _ = recognizer.process(device:2,time:1,contacts:touches([2,3,4]),doubleClick:true,rightClick:true)
        _ = recognizer.process(device:1,time:1.03,contacts:touches([1,3,4]),gestureActive:true,doubleClick:true,rightClick:true)
        XCTAssertNil(recognizer.process(device:1,time:1.08,contacts:[OMSRawTouch](),doubleClick:true,rightClick:true))
        XCTAssertEqual(recognizer.process(device:2,time:1.08,contacts:[OMSRawTouch](),doubleClick:true,rightClick:true),.doubleClick)
    }
    func testSecondaryOutputBuildsBothRightEdgesWithModifiersAndTagWithoutPosting() throws {
        let point = CGPoint(x:123,y:456)
        let output = try XCTUnwrap(SecondaryTapClickOutput.events(location:point,flags:.maskShift))
        XCTAssertEqual(output.down.type,.rightMouseDown); XCTAssertEqual(output.up.type,.rightMouseUp)
        for event in [output.down,output.up] {
            XCTAssertEqual(event.location,point); XCTAssertEqual(event.flags,.maskShift)
            XCTAssertEqual(event.getIntegerValueField(.mouseEventButtonNumber),1)
            XCTAssertEqual(event.getIntegerValueField(.mouseEventClickState),1)
            XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData),SelectedTrackpadEventPolicy.interpreterTag)
        }
        XCTAssertEqual(output.down.getDoubleValueField(.mouseEventPressure),1)
        XCTAssertEqual(output.up.getDoubleValueField(.mouseEventPressure),0)
        XCTAssertNil(SecondaryTapClickOutput.events(location:CGPoint(x:Double.nan,y:0)))
    }
    func testRightClickUsesAcceptedHalfSecondWindow() {
        for (end,accepted) in [(1.5,true),(1.501,false)] {
            var recognizer = ThreeFingerTapRecognizer()
            for time in [1.0,1.1,1.2,1.3,1.4] {
                _ = recognizer.process(device:1,time:time,contacts:touches([1,3,4]),doubleClick:true,rightClick:true)
            }
            XCTAssertEqual(recognizer.process(device:1,time:end,contacts:[OMSRawTouch](),doubleClick:true,rightClick:true),accepted ? .rightClick : nil)
        }
    }

}
