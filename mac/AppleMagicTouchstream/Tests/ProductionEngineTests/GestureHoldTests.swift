import Foundation
import OpenMultitouchSupport
import XCTest
@testable import GlassToKeyRuntime

final class GestureHoldTests:XCTestCase {
    private let actions:[Int:GestureAction] = [1:.primaryClick,2:.secondaryClick,3:.missionControl,4:.volumeUpSmall,5:.showDesktop]
    private func touches(_ count:Int,dx:Float = 0,idOffset:Int32 = 0) -> [OMSRawTouch] {
        (0..<count).map { i in OMSRawTouch(id:Int32(i+1)+idOffset,posX:0.2+Float(i)*0.1+dx,posY:0.5,
            total:1,pressure:40,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching) }
    }
    private func ready(_ count:Int) -> PerHandGestureSettings {
        var value = PerHandGestureSettings()
        if let move = PerHandGestureSettings.moveTrigger(count:count) {
            value.editMovement(move,mode:.directional,direction:.up,action:.volumeUpSmall)
        }
        if let pinch = GestureTrigger.pinch(count:count), let spread = GestureTrigger.spread(count:count) {
            value.bindings[pinch] = .disabled; value.bindings[spread] = .disabled
        }
        return value
    }
    func testAvailabilityRequiresNoContinuousMovePinchOrSpreadAndPreservesSavedHold() {
        for count in 1...5 {
            var value = ready(count)
            value.setHoldAction(.missionControl,count:count)
            XCTAssertTrue(value.holdAvailable(count:count))
            XCTAssertEqual(value.liveHoldActions[count],.missionControl)
            if let move = PerHandGestureSettings.moveTrigger(count:count) {
                value.editMovement(move,mode:.continuous)
                XCTAssertFalse(value.holdAvailable(count:count))
                XCTAssertNil(value.liveHoldActions[count])
                value.bindings[move] = .disabled
                XCTAssertTrue(value.holdAvailable(count:count))
            }
            if let pinch = GestureTrigger.pinch(count:count), let spread = GestureTrigger.spread(count:count) {
                for trigger in [pinch,spread] {
                    value.bindings[trigger] = .missionControl
                    XCTAssertFalse(value.holdAvailable(count:count))
                    XCTAssertNil(value.liveHoldActions[count])
                    value.bindings[trigger] = .disabled
                    XCTAssertTrue(value.holdAvailable(count:count))
                }
            }
            XCTAssertEqual(value.holdAction(count:count),.missionControl)
        }
    }
    func testDefaultsOldProfilesMirrorEditAndPortableRoundTrip() throws {
        let original = HandGestureSettings()
        XCTAssertTrue(original.left.liveHoldActions.isEmpty)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(original)) as? [String:Any])
        for hand in ["left","right"] {
            var settings = try XCTUnwrap(object[hand] as? [String:Any]); settings.removeValue(forKey:"holdActions"); object[hand] = settings
        }
        XCTAssertEqual(try JSONDecoder().decode(HandGestureSettings.self,from:JSONSerialization.data(withJSONObject:object)),original)
        var settings = HandGestureSettings(mirrored:ready(3))
        settings.setHoldAction(.missionControl,count:3,in:.left)
        XCTAssertNil(settings.holdAction(count:3,in:.both))
        settings.setHoldAction(.secondaryClick,count:3,in:.both)
        XCTAssertEqual(settings.holdAction(count:3,in:.both),.secondaryClick)
        settings.right.bindings[.threeFingerPinch] = .zoom
        XCTAssertFalse(settings.holdAvailable(count:3,in:.both))
        settings.setHoldAction(.showDesktop,count:3,in:.both) // no half-applied mirror edit
        XCTAssertEqual(settings.left.holdAction(count:3),.secondaryClick)
        var profile = AppKeymapProfile.defaultProfile(); profile.handGestureSettings = settings
        XCTAssertEqual(try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile()).handGestureSettings,settings)
    }
    func testAllCountsFireOnceAndLatchAcrossMembershipChangesUntilAllUp() {
        for count in 1...5 {
            var engine = GestureHoldRecognizer()
            for i in 0...5 {
                let time = 1+Double(i)*0.1
                let result = engine.observe(device:1,time:time,now:time,contacts:touches(count),motionClaimed:false,actions:actions)
                XCTAssertEqual(result,i == 5 ? count : nil)
            }
            XCTAssertTrue(engine.claimed(device:1))
            XCTAssertNil(engine.observe(device:1,time:1.6,now:1.6,contacts:touches(1,idOffset:20),motionClaimed:true,actions:actions))
            XCTAssertTrue(engine.claimed(device:1))
            XCTAssertNil(engine.advance(device:1,now:1.65,actions:actions))
            XCTAssertNil(engine.observe(device:1,time:1.7,now:1.7,contacts:[OMSRawTouch](),motionClaimed:false,actions:actions))
            XCTAssertFalse(engine.claimed(device:1))
        }
    }
    func testTimerUsesHostClockAndFreshFramesNotNativeClockEpoch() {
        var engine = GestureHoldRecognizer()
        for i in 0...4 {
            XCTAssertNil(engine.observe(device:1,time:100+Double(i)*0.1,now:1+Double(i)*0.1,contacts:touches(3),motionClaimed:false,actions:actions))
        }
        XCTAssertNil(engine.advance(device:1,now:1.49,actions:actions))
        XCTAssertEqual(engine.advance(device:1,now:1.501,actions:actions),3)
        XCTAssertNil(engine.advance(device:1,now:1.51,actions:actions))
    }
    func testMotionWinsBeforeHoldAndHoldWinsBeforeLaterMotion() {
        var engine = GestureHoldRecognizer(), router = TrackpadGestureRouter()
        for i in 0...7 {
            let time = 1+Double(i)*0.1
            let contacts = touches(3,dx:i == 0 ? 0 : 0.01)
            let update = router.recognize(device:1,time:time,contacts:contacts,enabled:{$0 == .threeFingerMove})
            XCTAssertNil(engine.observe(device:1,time:time,now:time,contacts:contacts,motionClaimed:update.gesture != nil,actions:actions))
        }
        XCTAssertFalse(engine.claimed(device:1))
        XCTAssertNil(engine.advance(device:1,now:1.71,actions:actions))
        // A fully stationary cycle can fire; caller keeps its ownership until all-up.
        _ = engine.observe(device:1,time:2,now:2,contacts:[OMSRawTouch](),motionClaimed:false,actions:actions)
        for i in 0...5 {
            _ = engine.observe(device:1,time:3+Double(i)*0.1,now:3+Double(i)*0.1,contacts:touches(3),motionClaimed:false,actions:actions)
        }
        XCTAssertTrue(engine.claimed(device:1))
        _ = engine.observe(device:1,time:3.6,now:3.6,contacts:touches(3,dx:0.1),motionClaimed:true,actions:actions)
        XCTAssertTrue(engine.claimed(device:1))
    }
    func testStaleInvalidReplacementAndCancellationCannotRearmBeforeAllUp() {
        for failure in 0...5 {
            var engine = GestureHoldRecognizer()
            _ = engine.observe(device:1,time:1,now:1,contacts:touches(3),motionClaimed:false,actions:actions)
            if failure == 0 { XCTAssertNil(engine.advance(device:1,now:1.3,actions:actions)) }
            if failure == 1 { engine.cancel(device:1) }
            if failure == 2 { _ = engine.observe(device:1,time:1.01,now:1.01,contacts:touches(3,idOffset:20),motionClaimed:false,actions:actions) }
            if failure == 3 { _ = engine.observe(device:1,time:1.01,now:1.01,contacts:touches(2),motionClaimed:false,actions:actions) }
            if failure == 4 { _ = engine.observe(device:1,time:1,now:1.01,contacts:touches(3),motionClaimed:false,actions:actions) }
            if failure == 5 { _ = engine.observe(device:1,time:1.01,now:1.01,contacts:touches(3,dx:Float.nan),motionClaimed:false,actions:actions) }
            for i in 1...10 {
                XCTAssertNil(engine.observe(device:1,time:1.3+Double(i)*0.1,now:1.3+Double(i)*0.1,contacts:touches(3),motionClaimed:false,actions:actions))
            }
            XCTAssertFalse(engine.claimed(device:1))
        }
    }
    func testLandingSkewAndIndependentHands() {
        var engine = GestureHoldRecognizer()
        _ = engine.observe(device:1,time:1,now:1,contacts:touches(1),motionClaimed:false,actions:actions)
        _ = engine.observe(device:1,time:1.04,now:1.04,contacts:touches(3),motionClaimed:false,actions:actions)
        _ = engine.observe(device:2,time:1.04,now:1.04,contacts:touches(4),motionClaimed:false,actions:actions)
        for i in 1...4 {
            let time = 1.04+Double(i)*0.1
            _ = engine.observe(device:1,time:time,now:time,contacts:touches(3),motionClaimed:false,actions:actions)
            _ = engine.observe(device:2,time:time,now:time,contacts:touches(4),motionClaimed:false,actions:actions)
        }
        engine.cancel(device:1)
        XCTAssertNil(engine.advance(device:1,now:1.55,actions:actions))
        XCTAssertEqual(engine.advance(device:2,now:1.55,actions:actions),4)
        engine.reset()
        XCTAssertFalse(engine.claimed(device:2))
    }
    func testHoldReservesKeyboardEvenWithoutTapMovementOrOutputPermission() {
        var arbitration = GestureKeyboardArbitration()
        for count in 1...5 {
            XCTAssertTrue(arbitration.process(device:UInt64(count),activeCount:count,holdCandidate:true,enabled:{_ in false}))
            XCTAssertTrue(arbitration.process(device:UInt64(count),activeCount:1,enabled:{_ in false}))
            XCTAssertTrue(arbitration.process(device:UInt64(count),activeCount:0,enabled:{_ in false}))
            XCTAssertFalse(arbitration.process(device:UInt64(count),activeCount:1,enabled:{_ in false}))
        }
    }
}
