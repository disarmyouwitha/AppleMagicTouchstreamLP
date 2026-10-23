import AppKit
import XCTest
import OpenMultitouchSupport
@testable import GlassToKeyRuntime

@MainActor
final class PinchZoomTests: XCTestCase {
    private func touches(_ distance:Double = 30, center:Double = 80, secondID:Int32 = 2) -> [OMSRawTouch] {
        [(Int32(1),center-distance/2),(secondID,center+distance/2)].map { id,x in
            OMSRawTouch(id:id,posX:Float(x/160),posY:0.5,total:1,pressure:40,
                majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
        }
    }
    func testSymmetricAndAsymmetricPinchesWinWhileTranslationKeepsMouseResponse() throws {
        for center in [80.0,80.5] {
            var router = TrackpadGestureRouter()
            _ = router.recognize(device:1,time:1,contacts:touches(),enabled:{_ in true})
            let began = router.recognize(device:1,time:1.01,contacts:touches(31,center:center),enabled:{_ in true})
            XCTAssertEqual(began.gesture,.twoFingerSpread); XCTAssertEqual(began.phase,.began)
            XCTAssertEqual(try XCTUnwrap(began.scaleDelta),1/30.0,accuracy:0.00001)
            let close = router.recognize(device:1,time:1.02,contacts:touches(30,center:center+1),enabled:{_ in true})
            XCTAssertEqual(close.gesture,.twoFingerSpread)
            XCTAssertLessThan(try XCTUnwrap(close.scaleDelta),0)
            let end = router.recognize(device:1,time:1.03,contacts:[OMSRawTouch](),enabled:{_ in true})
            XCTAssertEqual(end.phase,.ended)
        }
        var router = TrackpadGestureRouter()
        _ = router.recognize(device:1,time:1,contacts:touches(),enabled:{_ in true})
        let move = router.recognize(device:1,time:1.01,contacts:touches(center:80.4),enabled:{_ in true})
        XCTAssertEqual(move.gesture,.twoFingerMove); XCTAssertEqual(move.phase,.began)
        let laterSpread = router.recognize(device:1,time:1.02,contacts:touches(34,center:81),enabled:{_ in true})
        XCTAssertEqual(laterSpread.gesture,.twoFingerMove); XCTAssertNil(laterSpread.scaleDelta)
    }
    func testPinchOnlyReservationJitterIdentityChangesAndCountsAreSafe() {
        var gate = GestureKeyboardArbitration(), router = TrackpadGestureRouter()
        XCTAssertTrue(gate.process(device:1,activeCount:2) {$0 == .twoFingerSpread})
        XCTAssertTrue(gate.process(device:1,activeCount:1) {_ in false})
        XCTAssertTrue(gate.process(device:1,activeCount:0) {_ in false})
        _ = router.recognize(device:1,time:1,contacts:touches(),enabled:{_ in true})
        XCTAssertNil(router.recognize(device:1,time:1.01,contacts:touches(30.2),enabled:{_ in true}).gesture)
        XCTAssertEqual(router.recognize(device:1,time:1.02,contacts:touches(31),enabled:{_ in true}).gesture,.twoFingerSpread)
        let lift = router.recognize(device:1,time:1.03,contacts:Array(touches().prefix(1)),enabled:{_ in true})
        XCTAssertEqual(lift.gesture,.twoFingerSpread); XCTAssertNotNil(lift.scaleDelta)
        let replacement = router.recognize(device:1,time:1.04,contacts:touches(40,secondID:99),enabled:{_ in true})
        XCTAssertEqual(replacement.gesture,.twoFingerSpread); XCTAssertEqual(replacement.scaleDelta,0)
        XCTAssertEqual(router.recognize(device:1,time:1.5,contacts:touches(41,secondID:99),enabled:{_ in true}).phase,.cancelled)
        var tracker = PinchSpreadTracker()
        XCTAssertNil(tracker.process(device:1,time:1,contacts:touches()))
        XCTAssertNil(tracker.process(device:2,time:1.01,contacts:touches(40)))
        XCTAssertNil(tracker.process(device:1,time:0.9,contacts:touches(31)))
        XCTAssertNil(tracker.process(device:1,time:1,contacts:touches(31,secondID:1)))
    }
    func testLatchedPinchContinuesWithOneAndExtraFingersWithoutMembershipJumps() throws {
        var router = TrackpadGestureRouter()
        func recognize(_ time:Double,_ contacts:[OMSRawTouch]) -> GestureSessionUpdate<GestureTrigger> {
            router.recognize(device:1,time:time,contacts:contacts,enabled:{_ in true})
        }
        _ = recognize(1,touches())
        XCTAssertEqual(recognize(1.01,touches(31)).gesture,.twoFingerSpread)
        let extra = OMSRawTouch(id:3,posX:0.9,posY:0.8,total:1,pressure:40,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
        let four = OMSRawTouch(id:4,posX:0.2,posY:0.8,total:1,pressure:40,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
        let added = recognize(1.02,touches(32)+[extra,four])
        XCTAssertEqual(added.gesture,.twoFingerSpread)
        XCTAssertEqual(try XCTUnwrap(added.scaleDelta),0,accuracy:0.00001)
        let survivor = recognize(1.03,Array(touches(34).prefix(1)))
        XCTAssertEqual(survivor.gesture,.twoFingerSpread)
        XCTAssertGreaterThan(try XCTUnwrap(survivor.scaleDelta),0)
        XCTAssertGreaterThan(try XCTUnwrap(recognize(1.04,Array(touches(36).prefix(1))).scaleDelta),0)
        let returned = recognize(1.05,touches(36))
        XCTAssertEqual(returned.gesture,.twoFingerSpread); XCTAssertEqual(returned.scaleDelta,0)
        XCTAssertGreaterThan(try XCTUnwrap(recognize(1.06,touches(37)).scaleDelta),0)
        XCTAssertEqual(recognize(1.07,[]).phase,.ended)
        _ = recognize(1.08,touches())
        XCTAssertEqual(recognize(1.09,touches(center:80.5)).gesture,.twoFingerMove)
    }

    func testDisabledPinchDoesNotStealMouseAndResetEndsOwner() {
        var router = TrackpadGestureRouter()
        _ = router.recognize(device:1,time:1,contacts:touches(),enabled:{$0 == .twoFingerMove})
        let result = router.recognize(device:1,time:1.01,contacts:touches(31,center:80.5),enabled:{$0 == .twoFingerMove})
        XCTAssertEqual(result.gesture,.twoFingerMove)
        router.reset(device:1)
        XCTAssertNil(router.recognize(device:1,time:1.02,contacts:touches(32),enabled:{_ in true}).gesture)
    }
    private func chord(_ count:Int, spread:Double = 0, translation:Double = 0, rotation:Double = 0) -> [OMSRawTouch] {
        (0..<count).map { i in
            let x = i == 0 ? 50.0 : 90 + spread
            let y = i == 0 ? 60.0 : 35 + Double(i)*10
            let dx=x-70, dy=y-60
            let px=70+dx*cos(rotation)-dy*sin(rotation)+translation
            let py=60+dx*sin(rotation)+dy*cos(rotation)
            return OMSRawTouch(id:Int32(i+1),posX:Float(px/160),posY:Float(py/114.9),total:1,pressure:40,
                majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
        }
    }
    func testEveryThumbPlusFingertipCountRecognizesSpreadAndPinchWithoutStealingTranslation() throws {
        for count in 2...5 {
            var router = TrackpadGestureRouter()
            let trigger = try XCTUnwrap(GestureTrigger.spread(count:count))
            _ = router.recognize(device:1,time:1,contacts:chord(count),enabled:{_ in true})
            let initial = router.recognize(device:1,time:1.01,contacts:chord(count,spread:0.8),enabled:{_ in true})
            XCTAssertTrue(initial.gesture == nil || initial.gesture == trigger)
            let spread = router.recognize(device:1,time:1.02,contacts:chord(count,spread:2),enabled:{_ in true})
            XCTAssertEqual(spread.gesture,trigger,"count \(count)")
            XCTAssertGreaterThan(try XCTUnwrap(spread.scaleDelta),0)
            let pinch = router.recognize(device:1,time:1.03,contacts:chord(count,spread:1),enabled:{_ in true})
            XCTAssertEqual(pinch.gesture,trigger)
            XCTAssertLessThan(try XCTUnwrap(pinch.scaleDelta),0)
            XCTAssertEqual(router.recognize(device:1,time:1.04,contacts:[],enabled:{_ in true}).phase,.ended)
            var tracker = PinchSpreadTracker()
            _ = tracker.process(device:1,time:1,contacts:chord(count))
            let rigid = try XCTUnwrap(tracker.process(device:1,time:1.01,contacts:chord(count,translation:1,rotation:0.05)))
            XCTAssertEqual(rigid.changeMM,0,accuracy:0.0001)
        }
    }
    func testAllContactsContributeAndCountChangesRebaseWithoutChangingOwner() throws {
        var router = TrackpadGestureRouter()
        _ = router.recognize(device:1,time:1,contacts:chord(5),enabled:{_ in true})
        let begin = router.recognize(device:1,time:1.01,contacts:chord(5,spread:2),enabled:{_ in true})
        XCTAssertEqual(begin.gesture,.fiveFingerSpread)
        var fifthOnly = chord(5,spread:2)
        fifthOnly[4] = chord(5,spread:4)[4]
        let fifth = router.recognize(device:1,time:1.02,contacts:fifthOnly,enabled:{_ in true})
        XCTAssertNotEqual(try XCTUnwrap(fifth.scaleDelta),0)
        for (index,count) in [4,3,2,1,3,5].enumerated() {
            let changed = router.recognize(device:1,time:1.03+Double(index)*0.01,contacts:Array(chord(5,spread:4).prefix(count)),enabled:{_ in true})
            XCTAssertEqual(changed.gesture,.fiveFingerSpread)
            if count >= 2 { XCTAssertEqual(changed.scaleDelta,0) }
        }
        XCTAssertEqual(router.recognize(device:1,time:1.1,contacts:[],enabled:{_ in true}).phase,.ended)
    }

    func testDirectionsChooseIndependentBindingsAndKeepOwnerOnReversal() throws {
        for count in 2...5 {
            let inward = try XCTUnwrap(GestureTrigger.pinch(count:count))
            let outward = try XCTUnwrap(GestureTrigger.spread(count:count))
            for (direction,amount) in [(inward,-2.0),(outward,2.0)] {
                var router = TrackpadGestureRouter()
                _ = router.recognize(device:1,time:1,contacts:chord(count),enabled:{_ in true})
                let begin = router.recognize(device:1,time:1.01,contacts:chord(count,spread:amount),enabled:{_ in true})
                XCTAssertEqual(begin.gesture,direction)
                let reverse = router.recognize(device:1,time:1.02,contacts:chord(count),enabled:{_ in true})
                XCTAssertEqual(reverse.gesture,direction)
                XCTAssertEqual(reverse.phase,.changed)
                XCTAssertTrue((try XCTUnwrap(reverse.scaleDelta)) * amount < 0)
                var disabled = TrackpadGestureRouter()
                _ = disabled.recognize(device:1,time:1,contacts:chord(count),enabled:{$0 == (direction == inward ? outward : inward)})
                XCTAssertNil(disabled.recognize(device:1,time:1.01,contacts:chord(count,spread:amount),enabled:{$0 == (direction == inward ? outward : inward)}).gesture)
            }
            var bindings = GestureActionBindings()
            bindings[inward] = .disabled
            XCTAssertEqual(bindings[outward],.zoom)
            bindings[outward] = .disabled
            bindings[inward] = .zoom
            XCTAssertEqual(bindings[outward],.disabled)
        }
        // Old combined settings migrate to the same action for both directions.
        var old = GestureActionBindings()
        old.twoFingerPinch = .disabled
        let migrated = try JSONDecoder().decode(GestureActionBindings.self,from:JSONEncoder().encode(old))
        XCTAssertEqual(migrated[.twoFingerPinch],.disabled)
        XCTAssertEqual(migrated[.twoFingerSpread],.disabled)
    }

    func testNativeMagnificationPhasesDeltaFlagsAnchorAndCleanupWithoutPosting() throws {
        var output = MagnifyGestureOutput()
        let anchor = CGPoint(x:120,y:240)
        let begin = try XCTUnwrap(output.update(delta:0.03,began:true,location:anchor,flags:.maskShift))
        let changed = try XCTUnwrap(output.update(delta:-0.02,began:false,location:CGPoint(x:900,y:800)))
        let end = try XCTUnwrap(output.finish(cancelled:false))
        for (event,phase,delta) in [(begin,NSEvent.Phase.began,0.03),(changed,.changed,-0.02),(end,.ended,0.0)] {
            let ns = try XCTUnwrap(NSEvent(cgEvent:event))
            XCTAssertEqual(ns.type,.magnify); XCTAssertEqual(ns.phase,phase)
            XCTAssertEqual(ns.magnification,delta,accuracy:0.000001)
            XCTAssertEqual(event.location,anchor); XCTAssertEqual(event.flags,.maskShift)
            XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData),SelectedTrackpadEventPolicy.interpreterTag)
        }
        XCTAssertNil(output.finish(cancelled:false))
        XCTAssertNil(output.update(delta:0.02,began:false,location:anchor))
        _ = output.update(delta:0,began:true,location:anchor)
        XCTAssertEqual(NSEvent(cgEvent:try XCTUnwrap(output.finish(cancelled:true)))?.phase,.cancelled)
        XCTAssertNil(MagnifyGestureOutput.event(delta:.nan,phase:2,location:anchor))
        XCTAssertNil(MagnifyGestureOutput.event(delta:1,phase:2,location:anchor))
    }
    func testPinchActionAndGainMigratePersistAndExportWithKeymap() throws {
        var profile = AppKeymapProfile.defaultProfile(), settings = HandGestureSettings()
        XCTAssertEqual(settings.action(.twoFingerPinch,in:.both),.zoom)
        for trigger in GestureTrigger.pinchTriggers {
            XCTAssertEqual(settings.action(trigger,in:.both),.zoom)
            settings.setAction(.disabled,for:trigger,in:.right)
        }
        settings.set(.zoom,value:0.7,in:.left); settings.set(.zoom,value:1.4,in:.right)
        XCTAssertNil(settings.sensitivity(.zoom,in:.both))
        profile.handGestureSettings = settings
        let loaded = try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile())
        XCTAssertEqual(loaded.handGestureSettings,settings)
        let data = try JSONEncoder().encode(settings)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        for hand in ["left","right"] {
            var side = try XCTUnwrap(old[hand] as? [String:Any]); side.removeValue(forKey:"zoomSensitivity")
            var bindings = try XCTUnwrap(side["bindings"] as? [String:Any]); bindings.removeValue(forKey:"twoFingerPinch"); bindings.removeValue(forKey:"pinchActions"); bindings.removeValue(forKey:"spreadActions")
            side["bindings"] = bindings; old[hand] = side
        }
        let migrated = try JSONDecoder().decode(HandGestureSettings.self,from:JSONSerialization.data(withJSONObject:old))
        XCTAssertEqual(migrated.action(.twoFingerPinch,in:.both),.zoom)
        XCTAssertEqual(migrated.sensitivity(.zoom,in:.both),1)
    }
}

extension PinchZoomTests {
    func testAppleShortcutMenusPersistenceAndBalancedOneShotEvents() throws {
        var settings = HandGestureSettings()
        for trigger in GestureTrigger.pinchTriggers + GestureTrigger.forceTriggers {
            for action in GestureAction.appleShortcuts {
                XCTAssertTrue(trigger.allowedActions.contains(action))
                XCTAssertTrue(settings.setAction(action,for:trigger,in:.both))
                XCTAssertEqual(settings.action(trigger,in:.both),action)
            }
        }
        XCTAssertFalse(GestureTrigger.twoFingerTap.allowedActions.contains(.missionControl))
        var profile = AppKeymapProfile.defaultProfile(); profile.handGestureSettings = settings
        let roundtrip = try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile())
        XCTAssertEqual(roundtrip.handGestureSettings,settings)
        for action in GestureAction.appleShortcuts {
            let plan = try XCTUnwrap(AppleShortcutPlan.resolve(action,preferences:[:]))
            let events = try XCTUnwrap(plan.events())
            XCTAssertEqual(events.count,2)
            XCTAssertEqual(events[0].type,.keyDown); XCTAssertEqual(events[1].type,.keyUp)
            for event in events {
                XCTAssertEqual(event.getIntegerValueField(.keyboardEventKeycode),Int64(plan.keyCode))
                XCTAssertEqual(event.flags,plan.flags)
                XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData),SelectedTrackpadEventPolicy.interpreterTag)
            }
            for phase in [GestureSessionPhase.pending,.changed,.ended,.cancelled] {
                XCTAssertNil(plan.events(phase:phase))
            }
            var clicks = PrimaryTapClickOutput()
            XCTAssertEqual(GestureTapActionOutput.events(action:action,location:.zero,time:1,doubleClickInterval:0.5,clicks:&clicks,shortcut:plan)?.count,2)
            XCTAssertNil(GestureTapActionOutput.events(action:action,location:.zero,time:1,doubleClickInterval:0.5,clicks:&clicks))
        }
    }
    func testAppleShortcutPreferencesOverrideAndRejectUnsafeOrDisabledBindings() throws {
        let flags: CGEventFlags = [.maskCommand,.maskAlternate]
        let modifiers = flags.rawValue
        let custom:[String:Any] = ["32":["enabled":true,"value":["type":"standard","parameters":[65535,20,modifiers]]]]
        let plan = try XCTUnwrap(AppleShortcutPlan.resolve(.missionControl,preferences:custom))
        XCTAssertEqual(plan.keyCode,20); XCTAssertEqual(plan.flags.rawValue,modifiers)
        XCTAssertNil(AppleShortcutPlan.resolve(.missionControl,preferences:["32":["enabled":false]]))
        XCTAssertNil(AppleShortcutPlan.resolve(.appExpose,preferences:["33":["enabled":true,"value":["type":"standard","parameters":[65535,65535,0]]]]))
        XCTAssertNil(AppleShortcutPlan.resolve(.appExpose,preferences:["33":["enabled":true,"value":["type":"standard","parameters":[65535,12,-1]]]]))
        XCTAssertNil(AppleShortcutPlan.resolve(.primaryClick,preferences:[:]))
        XCTAssertEqual(AppleShortcutPlan.resolve(.notificationCenter,preferences:[:])?.flags,.maskSecondaryFn)
    }
}
