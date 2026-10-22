import CoreGraphics
import Foundation
import OpenMultitouchSupport
import XCTest
@testable import GesturePadRuntime

final class GestureActionBindingTests: XCTestCase {
    private func contacts(_ fingers: [Int32], dx: Float = 0) -> [OMSRawTouch] {
        fingers.enumerated().map { index,finger in
            OMSRawTouch(id:Int32(index+10),posX:Float(index)*0.11+0.3+dx,
                posY:finger == 1 ? 0.12 : 0.65,total:1,pressure:100,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching,
                telemetry:OMSTouchTelemetry(fingerID:finger,handID:1,velocityX:0,velocityY:0,absoluteX:0,absoluteY:0,
                    absoluteVelocityX:0,absoluteVelocityY:0,sourceFrame:1,sourceTimestamp:1))
        }
    }
    func testDefaultAssignmentsPreserveCurrentBehaviorAndMirroredHands() {
        let settings = HandGestureSettings()
        let expected: [GestureTrigger:GestureAction] = [.twoFingerMove:.pointer,.twoFingerTap:.primaryClick,
            .threeFingerMove:.primaryDrag,.threeFingerTap:.primaryDoubleClick,.fourFingerMove:.scroll,.thumbTwoTap:.secondaryClick]
        for (trigger,action) in expected { XCTAssertEqual(settings.action(trigger,in:.both),action) }
    }
    func testAssignmentsAreIndependentBothShowsMixedAndExplicitlyReplacesBoth() {
        var settings = HandGestureSettings()
        XCTAssertTrue(settings.setAction(.secondaryClick,for:.twoFingerTap,in:.left))
        XCTAssertEqual(settings.action(.twoFingerTap,in:.right),.primaryClick)
        XCTAssertNil(settings.action(.twoFingerTap,in:.both))
        XCTAssertTrue(settings.setAction(.primaryDoubleClick,for:.twoFingerTap,in:.both))
        XCTAssertEqual(settings.action(.twoFingerTap,in:.both),.primaryDoubleClick)
        XCTAssertEqual(settings.action(.threeFingerTap,in:.both),.primaryDoubleClick)
        XCTAssertTrue(settings.setAction(.disabled,for:.threeFingerMove,in:.right))
        XCTAssertEqual(settings.enabled(.threeFingerMove,in:.right),false)
    }
    func testUnsupportedActionFamiliesCannotBeStoredOrDispatched() {
        var settings = HandGestureSettings()
        XCTAssertFalse(settings.setAction(.primaryDrag,for:.twoFingerTap,in:.both))
        XCTAssertFalse(settings.setAction(.primaryClick,for:.fourFingerMove,in:.left))
        XCTAssertEqual(settings.action(.twoFingerTap,in:.both),.primaryClick)
        var malformed = GestureActionBindings()
        malformed[.twoFingerTap] = .scroll
        XCTAssertEqual(malformed.action(for:.twoFingerTap),.disabled)
        var clicks = PrimaryTapClickOutput()
        for action in [GestureAction.disabled,.pointer,.primaryDrag,.scroll] {
            XCTAssertNil(GestureTapActionOutput.events(action:action,location:.zero,time:1,doubleClickInterval:0.5,clicks:&clicks))
        }
    }
    func testContinuousRecognizerKeepsItsInputIdentityWhenAssignedDifferentActions() throws {
        for (trigger,fingers,action) in [(GestureTrigger.twoFingerMove,[Int32(2),3],GestureAction.scroll),
            (.threeFingerMove,[Int32(2),3,4],.pointer),(.fourFingerMove,[Int32(2),3,4,5],.primaryDrag)] {
            var settings = HandGestureSettings(), router = TrackpadGestureRouter()
            settings.setAction(action,for:trigger,in:.left)
            _ = router.recognize(device:11,time:1,contacts:contacts(fingers),enabled:{$0 == trigger})
            let begin = router.recognize(device:11,time:1.02,contacts:contacts(fingers,dx:0.003),enabled:{$0 == trigger})
            XCTAssertEqual(begin.phase,.began); XCTAssertEqual(begin.gesture,trigger)
            XCTAssertEqual(settings.routed(to:GestureSelectedPads(left:11,right:22))[11]?.bindings.action(for:try XCTUnwrap(begin.gesture)),action)
            let continued = router.recognize(device:11,time:1.04,contacts:contacts([fingers[0]],dx:0.004),enabled:{$0 == trigger})
            XCTAssertEqual(continued.gesture,trigger); XCTAssertEqual(continued.phase,.changed)
            XCTAssertEqual(router.recognize(device:11,time:1.06,contacts:[OMSRawTouch](),enabled:{$0 == trigger}).phase,.ended)
        }
    }
    func testTwoFingerTapCanDispatchDoubleClickInsteadOfItsFactorySingleClick() throws {
        var tap = TwoFingerTapRecognizer(), settings = HandGestureSettings(), clicks = PrimaryTapClickOutput()
        settings.setAction(.primaryDoubleClick,for:.twoFingerTap,in:.left)
        _ = tap.process(device:11,time:1,contacts:contacts([2,3]))
        XCTAssertTrue(tap.process(device:11,time:1.06,contacts:[OMSRawTouch]()))
        let events = try XCTUnwrap(GestureTapActionOutput.events(action:try XCTUnwrap(settings.action(.twoFingerTap,in:.left)),
            location:CGPoint(x:10,y:20),time:1.06,doubleClickInterval:0.5,clicks:&clicks))
        XCTAssertEqual(events.map(\.type),[.leftMouseDown,.leftMouseUp,.leftMouseDown,.leftMouseUp])
        XCTAssertEqual(events.map { $0.getIntegerValueField(.mouseEventClickState) },[1,1,2,2])
    }
    func testRecognizedThreeFingerAndThumbInputsDispatchReassignedClickActions() throws {
        for (fingers,trigger,action,types) in [([Int32(2),3,4],GestureTrigger.threeFingerTap,GestureAction.secondaryClick,[CGEventType.rightMouseDown,.rightMouseUp]),
            ([Int32(1),3,4],.thumbTwoTap,.primaryClick,[.leftMouseDown,.leftMouseUp])] {
            var recognizer = ThreeFingerTapRecognizer(), settings = HandGestureSettings(), clicks = PrimaryTapClickOutput()
            settings.setAction(action,for:trigger,in:.right)
            _ = recognizer.recognize(device:22,time:1,contacts:contacts(fingers),ordinaryEnabled:true,thumbEnabled:true)
            let recognized = try XCTUnwrap(recognizer.recognize(device:22,time:1.06,contacts:[OMSRawTouch](),ordinaryEnabled:true,thumbEnabled:true))
            XCTAssertEqual(recognized,trigger)
            let assigned = try XCTUnwrap(settings.routed(to:GestureSelectedPads(left:11,right:22))[22]?.bindings.action(for:recognized))
            let events = try XCTUnwrap(GestureTapActionOutput.events(action:assigned,location:CGPoint(x:100,y:200),time:1.06,
                doubleClickInterval:0.5,flags:.maskShift,clicks:&clicks))
            XCTAssertEqual(events.map(\.type),types)
            for event in events {
                XCTAssertEqual(event.flags,.maskShift)
                XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData),SelectedTrackpadEventPolicy.interpreterTag)
            }
        }
    }
    func testPersistenceKeepsPerHandActionsDisabledBindingsAndGains() throws {
        let name = "GesturePad.ActionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName:name))
        defer { defaults.removePersistentDomain(forName:name) }
        var original = HandGestureSettings()
        original.setAction(.scroll,for:.twoFingerMove,in:.left)
        original.setAction(.disabled,for:.fourFingerMove,in:.right)
        original.setAction(.primaryClick,for:.thumbTwoTap,in:.both)
        original.set(.pointer,value:0.75,in:.left); original.set(.scroll,value:1.25,in:.right)
        original.save(to:defaults)
        XCTAssertEqual(HandGestureSettings.load(from:defaults),original)
        defaults.set(Data("invalid".utf8),forKey:HandGestureSettings.defaultsKey)
        XCTAssertEqual(HandGestureSettings.load(from:defaults),HandGestureSettings())
    }
    func testDuplicateSelectionUsesActiveLeftActionThenRightFallbackWithoutDoubleDispatch() {
        var settings = HandGestureSettings()
        settings.setAction(.scroll,for:.twoFingerMove,in:.left)
        settings.setAction(.primaryDrag,for:.twoFingerMove,in:.right)
        let pads = GestureSelectedPads(left:11,right:11)
        XCTAssertEqual(settings.routed(to:pads).count,1)
        XCTAssertEqual(settings.routed(to:pads)[11]?.bindings.action(for:.twoFingerMove),.scroll)
        settings.setAction(.disabled,for:.twoFingerMove,in:.left)
        XCTAssertEqual(settings.routed(to:pads)[11]?.bindings.action(for:.twoFingerMove),.primaryDrag)
    }
}
