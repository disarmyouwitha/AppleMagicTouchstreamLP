import CoreGraphics
import Foundation
import OpenMultitouchSupport
import XCTest
@testable import GlassToKeyRuntime

final class IndependentHandGestureTests:XCTestCase {
    private func contacts(_ count:Int,dx:Float = 0) -> [OMSRawTouch] {
        (0..<count).map { OMSRawTouch(id:Int32($0+1),posX:0.25+Float($0)*0.1+dx,posY:0.5,total:1,
            pressure:40,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching) }
    }
    func testOtherHandPointerMovesHeldDragWithoutOwningOrReleasingButton() throws {
        for (right,left) in [(UInt64(1),UInt64(2)),(2,1)] {
            var router = TrackpadGestureRouter(), drag = PrimaryDragOutput()
            let enabled:(GestureTrigger)->Bool = { $0 == .twoFingerMove || $0 == .threeFingerMove }
            _ = router.recognize(device:right,time:1,contacts:contacts(3),enabled:enabled)
            XCTAssertEqual(router.recognize(device:right,time:1.01,contacts:contacts(3,dx:0.01),enabled:enabled).gesture,.threeFingerMove)
            let down = try XCTUnwrap(drag.begin(device:right,location:.init(x:100,y:100),flags:[]))
            XCTAssertEqual(down.type,.leftMouseDown)
            _ = router.recognize(device:left,time:1.02,contacts:contacts(2),enabled:enabled)
            let mouse = router.recognize(device:left,time:1.03,contacts:contacts(2,dx:0.01),enabled:enabled)
            XCTAssertEqual(mouse.gesture,.twoFingerMove)
            let event = try XCTUnwrap(drag.movePointer(location:.init(x:120,y:110),delta:.init(x:20,y:10),flags:[]))
            XCTAssertEqual(event.type,.leftMouseDragged)
            XCTAssertEqual(drag.owners,[right])
            XCTAssertNil(drag.end(device:left)) // Other-hand all-up cannot lift the drag.
            XCTAssertEqual(drag.owner,right)
            let move = try XCTUnwrap(drag.move(device:right,location:.init(x:125,y:110),delta:.init(x:5,y:0),flags:[]))
            XCTAssertEqual(move.type,.leftMouseDragged)
            let up = try XCTUnwrap(drag.end(device:right))
            XCTAssertEqual(up.type,.leftMouseUp); XCTAssertEqual(up.location,move.location)
            XCTAssertNil(drag.end())
            XCTAssertNil(drag.movePointer(location:.zero,delta:.zero,flags:[]))
        }
    }
    func testTwoDragOwnersShareOneButtonAndReleaseOnlyAfterLastOwner() throws {
        for first in [UInt64(1),UInt64(2)] {
            var drag = PrimaryDragOutput()
            XCTAssertNotNil(drag.begin(device:1,location:.zero,flags:[]))
            XCTAssertTrue(drag.join(device:2))
            XCTAssertTrue(drag.join(device:2)) // Idempotent, no extra release obligation.
            XCTAssertEqual(drag.owners,[1,2])
            XCTAssertTrue(drag.hasOtherOwner(than:1)); XCTAssertTrue(drag.hasOtherOwner(than:2))
            XCTAssertNotNil(drag.move(device:2,location:.init(x:5,y:6),delta:.init(x:5,y:6),flags:[]))
            XCTAssertNil(drag.end(device:first))
            let other:UInt64 = first == 1 ? 2 : 1
            XCTAssertEqual(drag.owners,[other])
            XCTAssertFalse(drag.hasOtherOwner(than:other)); XCTAssertTrue(drag.hasOtherOwner(than:first))
            XCTAssertNotNil(drag.move(device:other,location:.init(x:9,y:6),delta:.init(x:4,y:0),flags:[]))
            XCTAssertEqual(try XCTUnwrap(drag.end(device:other)).type,.leftMouseUp)
            XCTAssertNil(drag.owner); XCTAssertTrue(drag.owners.isEmpty)
        }
    }
    func testGlobalReleaseEndsBothDragsAndClearsTheirOwnership() throws {
        var drag = PrimaryDragOutput()
        XCTAssertFalse(drag.join(device:1))
        XCTAssertNotNil(drag.begin(device:1,location:.zero,flags:[]))
        XCTAssertTrue(drag.join(device:2))
        XCTAssertEqual(try XCTUnwrap(drag.end()).type,.leftMouseUp)
        XCTAssertNil(drag.end(device:1)); XCTAssertNil(drag.end(device:2))
        XCTAssertTrue(drag.owners.isEmpty)
        XCTAssertNotNil(drag.begin(device:2,location:.zero,flags:[]))
        XCTAssertEqual(drag.owners,[2]); XCTAssertNotNil(drag.end())
    }
    func testScrollAndDirectionalRecognitionRemainIndependentFromOtherPadsDrag() throws {
        var router = TrackpadGestureRouter(), drag = PrimaryDragOutput(), stepper = GestureDirectionalStepper()
        let enabled:(GestureTrigger)->Bool = { $0 == .threeFingerMove || $0 == .fourFingerMove }
        _ = router.recognize(device:1,time:1,contacts:contacts(3),enabled:enabled)
        _ = router.recognize(device:1,time:1.01,contacts:contacts(3,dx:0.01),enabled:enabled)
        XCTAssertNotNil(drag.begin(device:1,location:.zero,flags:[]))
        _ = router.recognize(device:2,time:1.02,contacts:contacts(4),enabled:enabled)
        XCTAssertEqual(router.recognize(device:2,time:1.03,contacts:contacts(4,dx:0.01),enabled:enabled).gesture,.fourFingerMove)
        router.reset(device:2)
        XCTAssertEqual(drag.owner,1)
        let config = GestureDirectionalAssignments(mode:.directional,actions:["right":.volumeUpSmall])
        let update = GestureSessionUpdate(gesture:GestureTrigger.threeFingerMove,phase:.began,millimetres:CGPoint(x:1,y:0),cancellation:nil)
        XCTAssertEqual(stepper.process(device:2,time:1.04,update:update,assignments:config),.right)
        XCTAssertEqual(drag.owner,1); XCTAssertNotNil(drag.end())
    }
    func testCapturedLateHandCanJoinDragWithoutBeingConsumedByBoth() throws {
        struct Fixture:Decodable {
            struct Sample:Decodable { let frame:RuntimeRawFrame; let arrivalTicks:UInt64 }
            let frames:[Sample]
        }
        let url = try XCTUnwrap(Bundle.module.url(forResource:"both-late-join",withExtension:"json",subdirectory:"Fixtures"))
        let frames = try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:url)).frames
        var settings = TwoHandGestureSettings()
        settings.setAction(.missionControl,for:.init(chord:.threeFingers,phase:.tap))
        settings.setAction(.showDesktop,for:.init(chord:.threeFingers,phase:.hold))
        var coordinated = TwoHandGestureEngine(), router = TrackpadGestureRouter(), drag = PrimaryDragOutput()
        var reservations = 0, downs = 0, ups = 0, joins = 0, dragged = Set<UInt64>(), activated = Set<UInt64>()
        for record in frames {
            let frame = record.frame, device = frame.deviceNumericID
            let decision = coordinated.process(leftHand:frame.deviceIndex == 0,now:Double(record.arrivalTicks)/1e9,
                contacts:frame.rawTouches,settings:settings)
            if decision.reserved {
                reservations += 1
                if decision.began { router.reset(); _ = drag.end() }
                continue
            }
            let update = router.recognize(device:device,time:frame.timestamp,contacts:frame.rawTouches) {
                $0 == .twoFingerMove || $0 == .threeFingerMove
            }
            if update.phase == .began && update.gesture == .threeFingerMove {
                activated.insert(device)
                if drag.owner != nil {
                    XCTAssertTrue(drag.join(device:device)); joins += 1
                } else {
                    XCTAssertNotNil(drag.begin(device:device,location:.zero,flags:[])); downs += 1
                }
            }
            if update.phase == .ended || update.phase == .cancelled {
                if drag.end(device:device) != nil { ups += 1 }
            } else if let delta = update.millimetres, delta != .zero, drag.owner != nil,
                      update.gesture == .threeFingerMove || update.gesture == .twoFingerMove {
                let previous = drag.location ?? .zero
                let location = CGPoint(x:previous.x+delta.x,y:previous.y+delta.y)
                let event = try XCTUnwrap(drag.movePointer(location:location,delta:delta,flags:[]))
                XCTAssertEqual(event.type,.leftMouseDragged); dragged.insert(device)
            }
        }
        XCTAssertEqual(reservations,0)
        XCTAssertEqual(activated.count,2)
        XCTAssertEqual(dragged.count,2)
        XCTAssertGreaterThan(joins,0)
        XCTAssertEqual(downs,1); XCTAssertEqual(ups,1)
        XCTAssertTrue(drag.owners.isEmpty)
    }

    func testSecondaryClickSharesPrivateDragSourceAndPreservesBothOwners() throws {
        var drag = PrimaryDragOutput(), clicks = PrimaryTapClickOutput()
        let down = try XCTUnwrap(drag.begin(device:1,location:.init(x:100,y:100),flags:[]))
        XCTAssertTrue(drag.join(device:2))
        let sourceID = down.getIntegerValueField(.eventSourceStateID)
        let right = try XCTUnwrap(GestureTapActionOutput.events(action:.secondaryClick,location:.init(x:110,y:110),
            time:1,doubleClickInterval:0.5,clicks:&clicks,mouseEventSource:drag.eventSource))
        XCTAssertEqual(right.map(\.type),[.rightMouseDown,.rightMouseUp])
        for event in right {
            XCTAssertEqual(event.getIntegerValueField(.eventSourceStateID),sourceID)
            XCTAssertFalse(DragButtonInterference.interrupts(type:event.type,tag:event.getIntegerValueField(.eventSourceUserData)))
        }
        XCTAssertEqual(drag.owners,[1,2])
        XCTAssertNil(drag.end(device:1))
        XCTAssertNotNil(drag.movePointer(location:.init(x:120,y:120),delta:.init(x:10,y:10),flags:[]))
        let up = try XCTUnwrap(drag.end(device:2))
        XCTAssertEqual(up.type,.leftMouseUp)
        XCTAssertEqual(up.getIntegerValueField(.eventSourceStateID),sourceID)
        XCTAssertNil(drag.eventSource)
        XCTAssertNotNil(drag.begin(device:1,location:.zero,flags:[]))
        XCTAssertNotNil(drag.end())
    }

    func testCapturedDragAndThumbTapKeepPrivateSourceAndLaterPointerRecognition() throws {
        struct Fixture:Decodable {
            struct Sample:Decodable { let frame:RuntimeRawFrame; let arrivalTicks:UInt64 }
            let frames:[Sample]
        }
        let url = try XCTUnwrap(Bundle.module.url(forResource:"drag-secondary-recovery",withExtension:"json",subdirectory:"Fixtures"))
        let frames = try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:url)).frames
        var router = TrackpadGestureRouter(), taps = ThreeFingerTapRecognizer(), drag = PrimaryDragOutput(), clicks = PrimaryTapClickOutput()
        var both = TwoHandGestureEngine(), bothSettings = TwoHandGestureSettings()
        bothSettings.setAction(.missionControl,for:.init(chord:.threeFingers,phase:.tap))
        var reservations = 0, downs = 0, ups = 0, secondaryDuringDrag = 0, pointerAfterClick = Set<UInt64>()
        for record in frames {
            let frame = record.frame, device = frame.deviceNumericID
            let coordinated = both.process(leftHand:frame.deviceIndex == 0,now:Double(record.arrivalTicks)/1e9,
                contacts:frame.rawTouches,settings:bothSettings)
            if coordinated.reserved { reservations += 1; continue }
            let update = router.recognize(device:device,time:frame.timestamp,contacts:frame.rawTouches) {
                $0 == .twoFingerMove || $0 == .threeFingerMove
            }
            if update.phase == .began && update.gesture == .threeFingerMove {
                if drag.owner == nil {
                    XCTAssertNotNil(drag.begin(device:device,location:.zero,flags:[])); downs += 1
                } else { XCTAssertTrue(drag.join(device:device)) }
            }
            if update.phase == .ended || update.phase == .cancelled {
                if drag.end(device:device) != nil { ups += 1 }
            }
            if taps.recognize(device:device,time:frame.timestamp,contacts:frame.rawTouches,
                gestureActive:update.gesture != nil && update.millimetres != nil,ordinaryEnabled:false,thumbEnabled:true) == .thumbTwoTap {
                let owners = drag.owners
                let events = try XCTUnwrap(GestureTapActionOutput.events(action:.secondaryClick,location:drag.location ?? .zero,
                    time:frame.timestamp,doubleClickInterval:0.5,clicks:&clicks,mouseEventSource:drag.eventSource))
                XCTAssertEqual(events.map(\.type),[.rightMouseDown,.rightMouseUp])
                XCTAssertEqual(drag.owners,owners)
                if !owners.isEmpty { secondaryDuringDrag += 1 }
                for event in events {
                    let source = event.getIntegerValueField(.eventSourceStateID)
                    XCTAssertNotEqual(source,Int64(CGEventSourceStateID.combinedSessionState.rawValue))
                    if let dragSource = drag.eventSource { XCTAssertEqual(source,Int64(dragSource.sourceStateID.rawValue)) }
                    XCTAssertFalse(DragButtonInterference.interrupts(type:event.type,tag:event.getIntegerValueField(.eventSourceUserData)))
                }
            }
            if secondaryDuringDrag > 0, update.gesture == .twoFingerMove,
               let delta = update.millimetres, delta != .zero {
                pointerAfterClick.insert(device)
                if drag.owner != nil {
                    XCTAssertNotNil(drag.movePointer(location:.zero,delta:delta,flags:[]))
                }
            }
        }
        XCTAssertEqual(reservations,0)
        XCTAssertEqual(secondaryDuringDrag,1)
        XCTAssertEqual(pointerAfterClick.count,2)
        XCTAssertEqual(downs,1); XCTAssertEqual(ups,1)
        XCTAssertTrue(drag.owners.isEmpty)
    }

    @MainActor func testIntervalDraftCanBeEmptyAndOnlyClampsWhenCommitted() {
        XCTAssertNil(GestureRepeatIntervalField.committedValue(""))
        XCTAssertNil(GestureRepeatIntervalField.committedValue(" "))
        XCTAssertNil(GestureRepeatIntervalField.committedValue("oops"))
        XCTAssertNil(GestureRepeatIntervalField.committedValue("nan"))
        XCTAssertEqual(GestureRepeatIntervalField.committedValue("8"),20)
        XCTAssertEqual(GestureRepeatIntervalField.committedValue("80"),80)
        XCTAssertEqual(GestureRepeatIntervalField.committedValue("0"),20)
        XCTAssertEqual(GestureRepeatIntervalField.committedValue("6000"),5000)
        XCTAssertEqual(GestureRepeatIntervalField.committedValue(" 240 "),240)
    }
    @MainActor func testMirrorRepeatIntervalCommitUnifiesMixedValuesAndEnablement() throws {
        for interval in ["20","80"] {
            var settings = HandGestureSettings()
            settings.setDirectionalRepeatInterval(80,direction:.up,for:.threeFingerMove,in:.left)
            settings.setDirectionalRepeatInterval(240,direction:.up,for:.threeFingerMove,in:.right)
            XCTAssertNil(settings.directionalConfiguredRepeatInterval(.up,for:.threeFingerMove,in:.both))
            let committed = try XCTUnwrap(GestureRepeatIntervalField.committedValue(interval))
            settings.setDirectionalRepeatInterval(committed,direction:.up,for:.threeFingerMove,in:.both)
            XCTAssertEqual(settings.directionalConfiguredRepeatInterval(.up,for:.threeFingerMove,in:.left),committed)
            XCTAssertEqual(settings.directionalConfiguredRepeatInterval(.up,for:.threeFingerMove,in:.right),committed)
            settings.setDirectionalRepeat(false,direction:.up,for:.threeFingerMove,in:.left)
            XCTAssertNil(settings.directionalRepeats(.up,for:.threeFingerMove,in:.both))
            // Explicit Return must reach this setter even if the numeric value
            // itself is unchanged; both pads then have the same enabled repeat.
            settings.setDirectionalRepeatInterval(committed,direction:.up,for:.threeFingerMove,in:.both)
            XCTAssertEqual(settings.directionalRepeats(.up,for:.threeFingerMove,in:.both),true)
        }
    }
}
