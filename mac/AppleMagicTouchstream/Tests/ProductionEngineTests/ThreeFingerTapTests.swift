import CoreGraphics
import OpenMultitouchSupport
import XCTest
@testable import GlassToKeyRuntime

final class ThreeFingerTapTests: XCTestCase {
    private func touches(_ ids: [Int32], offset: Float = 0) -> [OMSRawTouch] {
        ids.map { id in
            OMSRawTouch(id:id,posX:Float(id)*0.15+offset,posY:0.5,total:1,
                pressure:100,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
        }
    }
    func testStaggeredThreeFingerTapCompletesOnceAndNeverBecomesSingleClick() {
        var single = TwoFingerTapRecognizer(), double = TwoFingerTapRecognizer(requiredCount:3)
        let frames: [(Double,[Int32])] = [(1,[1]),(1.02,[2,1]),(1.04,[3,1,2]),
            (1.08,[2,3]),(1.1,[3]),(1.12,[]),(1.13,[])]
        for (time,ids) in frames {
            let contacts = touches(ids)
            XCTAssertFalse(single.process(device:1,time:time,contacts:contacts))
            XCTAssertEqual(double.process(device:1,time:time,contacts:contacts),time == 1.12)
        }
    }
    func testTwoFingerTapDoesNotDoubleClickAndFourthFingerRejectsBoth() {
        for count in [2,4] {
            var double = TwoFingerTapRecognizer(requiredCount:3)
            let ids = (1...count).map(Int32.init)
            _ = double.process(device:1,time:1,contacts:touches(ids))
            _ = double.process(device:1,time:1.04,contacts:touches(ids))
            XCTAssertFalse(double.process(device:1,time:1.08,contacts:touches([])))
        }
    }
    func testLateThirdRejoinReplacementMovementAndOwnershipReject() {
        for kind in 0..<5 {
            var tap = TwoFingerTapRecognizer(requiredCount:3)
            let chord = touches([1,2,3])
            _ = tap.process(device:1,time:1,contacts:kind == 0 ? touches([1,2]) : chord)
            switch kind {
            case 0: _ = tap.process(device:1,time:1.1,contacts:chord)
            case 1:
                _ = tap.process(device:1,time:1.04,contacts:touches([1,2]))
                _ = tap.process(device:1,time:1.06,contacts:chord)
            case 2: _ = tap.process(device:1,time:1.04,contacts:touches([1,2,9]))
            case 3: _ = tap.process(device:1,time:1.04,contacts:touches([1,2,3],offset:0.01))
            default: _ = tap.process(device:1,time:1.04,contacts:chord,gestureActive:true)
            }
            XCTAssertFalse(tap.process(device:1,time:1.12,contacts:touches([])))
        }
    }
    func testHalfSecondBoundaryAndIndependentPadsAndCancellation() {
        for (end,accepted) in [(1.5,true),(1.501,false)] {
            var tap = TwoFingerTapRecognizer(requiredCount:3)
            for time in [1.0,1.1,1.2,1.3,1.4] {
                _ = tap.process(device:1,time:time,contacts:touches([1,2,3]))
            }
            XCTAssertFalse(tap.process(device:2,time:1.45,contacts:touches([])))
            XCTAssertEqual(tap.process(device:1,time:end,contacts:touches([])),accepted)
        }
        var tap = TwoFingerTapRecognizer(requiredCount:3)
        _ = tap.process(device:1,time:1,contacts:touches([1,2,3]))
        tap.reset()
        XCTAssertFalse(tap.process(device:1,time:1.06,contacts:touches([])))
        _ = tap.process(device:1,time:2,contacts:touches([1,2,3]))
        XCTAssertTrue(tap.process(device:1,time:2.06,contacts:touches([])))
    }
    func testMouseOrScrollLatchDoesNotBecomeDoubleClickWhenCountChanges() {
        for initial in [[Int32(1),2],[Int32(1),2,3,4]] {
            var router = TrackpadGestureRouter()
            var tap = TwoFingerTapRecognizer(requiredCount:3)
            let frames: [(Double,[OMSRawTouch])] = [(1,touches(initial)),
                (1.04,touches(initial,offset:0.003)),(1.08,touches([1,2,3],offset:0.004)),(1.12,touches([]))]
            for (time,contacts) in frames {
                let motion = router.process(device:1,time:time,contacts:contacts,mouse:true,scroll:true)
                XCTAssertFalse(tap.process(device:1,time:time,contacts:contacts,gestureActive:motion != nil))
            }
        }
    }
    func testDedicatedDoubleClickBuildsFourBalancedEdgesAndCountsWithoutPosting() throws {
        let point = CGPoint(x:120,y:240)
        let output = try XCTUnwrap(PrimaryTapClickOutput.doubleClickEvents(location:point,flags:.maskCommand))
        let edges = [output.first.down,output.first.up,output.second.down,output.second.up]
        for (index,event) in edges.enumerated() {
            XCTAssertEqual(event.type,index%2 == 0 ? .leftMouseDown : .leftMouseUp)
            XCTAssertEqual(event.location,point)
            XCTAssertEqual(event.flags,.maskCommand)
            XCTAssertEqual(event.getIntegerValueField(.mouseEventClickState),index < 2 ? 1 : 2)
            XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData),SelectedTrackpadEventPolicy.interpreterTag)
        }
        let repeated = try XCTUnwrap(PrimaryTapClickOutput.doubleClickEvents(location:point))
        XCTAssertEqual(repeated.first.down.getIntegerValueField(.mouseEventClickState),1)
        XCTAssertEqual(repeated.second.up.getIntegerValueField(.mouseEventClickState),2)
        XCTAssertNil(PrimaryTapClickOutput.doubleClickEvents(location:CGPoint(x:Double.nan,y:0)))
    }
}
