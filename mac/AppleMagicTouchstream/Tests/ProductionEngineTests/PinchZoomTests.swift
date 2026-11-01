import AppKit
import XCTest
import OpenMultitouchSupport
@testable import GlassToKeyRuntime

@MainActor
final class PinchZoomTests: XCTestCase {
    private func touches(_ distance:Double = 30, center:Double = 80, secondID:Int32 = 2) -> [OMSRawTouch] {
        [(Int32(1),center-distance/2),(secondID,center+distance/2)].map { id,x in
            OMSRawTouch(id:id,posX:Float(x/160),posY:0.5,total:1,pressure:40,
                majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching,
                telemetry:OMSTouchTelemetry(fingerID:id == 1 ? 1 : 2,handID:1,velocityX:0,velocityY:0,
                    absoluteX:0,absoluteY:0,absoluteVelocityX:0,absoluteVelocityY:0,sourceFrame:1,sourceTimestamp:1))
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
    private func chord(_ count:Int, spread:Double = 0, translation:Double = 0, rotation:Double = 0, thumb:Int32? = 1) -> [OMSRawTouch] {
        (0..<count).map { i in
            let x = i == 0 ? 50.0 : 90 + spread
            let y = i == 0 ? 60.0 : 35 + Double(i)*10
            let dx=x-70, dy=y-60
            let px=70+dx*cos(rotation)-dy*sin(rotation)+translation
            let py=60+dx*sin(rotation)+dy*cos(rotation)
            return OMSRawTouch(id:Int32(i+1),posX:Float(px/160),posY:Float(py/114.9),total:1,pressure:40,
                majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching,
                telemetry:thumb.map { finger in OMSTouchTelemetry(fingerID:i == 0 ? finger : Int32(i+1),handID:1,
                    velocityX:0,velocityY:0,absoluteX:0,absoluteY:0,absoluteVelocityX:0,absoluteVelocityY:0,
                    sourceFrame:1,sourceTimestamp:1) })
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

    func testBothDirectionsRequireRecognizedThumbOnlyAtActivation() throws {
        for count in 2...5 {
            let inward = try XCTUnwrap(GestureTrigger.pinch(count:count))
            let outward = try XCTUnwrap(GestureTrigger.spread(count:count))
            for label:Int32? in [nil,0,2,3,4,5] {
                var blocked = TrackpadGestureRouter()
                _ = blocked.recognize(device:1,time:1,contacts:chord(count,thumb:label),enabled:{$0 == inward})
                XCTAssertNil(blocked.recognize(device:1,time:1.01,contacts:chord(count,spread:-2,thumb:label),enabled:{$0 == inward}).gesture)
                var spread = TrackpadGestureRouter()
                _ = spread.recognize(device:1,time:1,contacts:chord(count,thumb:label),enabled:{$0 == outward})
                XCTAssertNil(spread.recognize(device:1,time:1.01,contacts:chord(count,spread:2,thumb:label),enabled:{$0 == outward}).gesture)
            }
            var latched = TrackpadGestureRouter()
            _ = latched.recognize(device:1,time:1,contacts:chord(count),enabled:{$0 == inward})
            XCTAssertEqual(latched.recognize(device:1,time:1.01,contacts:chord(count,spread:-2),enabled:{$0 == inward}).gesture,inward)
            // Classification can fluctuate after activation without breaking the latch.
            let unknown = latched.recognize(device:1,time:1.02,contacts:chord(count,spread:-3,thumb:nil),enabled:{$0 == inward})
            XCTAssertEqual(unknown.gesture,inward); XCTAssertEqual(unknown.phase,.changed)
            let lifted = latched.recognize(device:1,time:1.03,contacts:Array(chord(count,spread:-4,thumb:nil).dropFirst()),enabled:{$0 == inward})
            XCTAssertEqual(lifted.gesture,inward); XCTAssertEqual(lifted.phase,.changed)
            XCTAssertEqual(latched.recognize(device:1,time:1.04,contacts:[],enabled:{$0 == inward}).phase,.ended)
        }
        // Non-thumb opening first must not latch Spread and then bypass Pinch's thumb rule.
        var reversal = TrackpadGestureRouter()
        _ = reversal.recognize(device:1,time:1,contacts:chord(2,thumb:4),enabled:{$0.isPinch})
        XCTAssertNil(reversal.recognize(device:1,time:1.01,contacts:chord(2,spread:2,thumb:4),enabled:{$0.isPinch}).gesture)
        XCTAssertNil(reversal.recognize(device:1,time:1.02,contacts:chord(2,spread:-2,thumb:4),enabled:{$0.isPinch}).gesture)
        // An ineligible pinch must not postpone ordinary pointer movement.
        var pointer = TrackpadGestureRouter()
        _ = pointer.recognize(device:1,time:1,contacts:chord(2,thumb:nil),enabled:{$0 == .twoFingerMove || $0 == .twoFingerPinch})
        XCTAssertEqual(pointer.recognize(device:1,time:1.01,contacts:chord(2,spread:-2,thumb:nil),enabled:{$0 == .twoFingerMove || $0 == .twoFingerPinch}).gesture,.twoFingerMove)
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
            if action == .missionControl || action == .appExpose {
                XCTAssertEqual(plan.dockMessage,action == .missionControl ? "com.apple.expose.awake" : "com.apple.expose.front.awake")
                XCTAssertNil(plan.events()) // Native actions must never emit Control-arrow keys.
                continue
            }
            let events = try XCTUnwrap(plan.events())
            let keys = events.filter { $0.type != .flagsChanged }
            XCTAssertEqual(keys.count,2)
            XCTAssertEqual(keys[0].type,.keyDown); XCTAssertEqual(keys[1].type,.keyUp)
            for event in keys {
                XCTAssertEqual(event.getIntegerValueField(.keyboardEventKeycode),Int64(plan.keyCode))
                let keyFlags:CGEventFlags = plan.explicitModifiers && (123...126).contains(plan.keyCode) ? [.maskSecondaryFn,.maskNumericPad] : []
                XCTAssertEqual(event.flags,plan.flags.union(keyFlags))
                XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData),SelectedTrackpadEventPolicy.interpreterTag)
            }
            for phase in [GestureSessionPhase.pending,.changed,.ended,.cancelled] {
                XCTAssertNil(plan.events(phase:phase))
            }
            var clicks = PrimaryTapClickOutput()
            XCTAssertEqual(GestureTapActionOutput.events(action:action,location:.zero,time:1,doubleClickInterval:0.5,clicks:&clicks,shortcut:plan)?.count,events.count)
            XCTAssertNil(GestureTapActionOutput.events(action:action,location:.zero,time:1,doubleClickInterval:0.5,clicks:&clicks))
        }
    }
    func testAppleShortcutPreferencesOverrideAndDockActionsIgnoreDisabledBindings() throws {
        let flags: CGEventFlags = [.maskCommand,.maskAlternate]
        let modifiers = flags.rawValue
        let custom:[String:Any] = ["163":["enabled":true,"value":["type":"standard","parameters":[65535,20,modifiers]]]]
        let plan = try XCTUnwrap(AppleShortcutPlan.resolve(.notificationCenter,preferences:custom))
        XCTAssertEqual(plan.keyCode,20); XCTAssertEqual(plan.flags.rawValue,modifiers)
        for action in [GestureAction.missionControl,.appExpose] {
            let id = try XCTUnwrap(AppleShortcutPlan.symbolicID(action))
            let native = try XCTUnwrap(AppleShortcutPlan.resolve(action,preferences:[id:["enabled":false]]))
            XCTAssertNotNil(native.dockMessage)
            XCTAssertNil(native.events())
            XCTAssertFalse(native.postDock(phase:.changed)) // Never invokes a native action in tests.
            XCTAssertFalse(native.postDock(phase:.ended))
        }
        XCTAssertNil(AppleShortcutPlan.resolve(.notificationCenter,preferences:["163":["enabled":true,"value":["type":"standard","parameters":[65535,65535,0]]]]))
        XCTAssertNil(AppleShortcutPlan.resolve(.notificationCenter,preferences:["163":["enabled":true,"value":["type":"standard","parameters":[65535,12,-1]]]]))
        XCTAssertNil(AppleShortcutPlan.resolve(.primaryClick,preferences:[:]))
        XCTAssertEqual(AppleShortcutPlan.resolve(.notificationCenter,preferences:[:])?.flags,.maskSecondaryFn)
    }
}


extension PinchZoomTests {
    func testSmallStepMediaActionsEncodeBalancedFineAdjustmentAndRoundTrip() throws {
        for (action,code) in zip(GestureAction.smallStepActions,[0,1,2,3]) {
            let plan = try XCTUnwrap(AppleShortcutPlan.resolve(action,preferences:[:]))
            XCTAssertEqual(plan.eventTap,.cgSessionEventTap)
            let events = try XCTUnwrap(plan.events())
            XCTAssertEqual(events.count,2)
            for (event,state) in zip(events,[0xA,0xB]) {
                let native = try XCTUnwrap(NSEvent(cgEvent:event))
                XCTAssertEqual(native.type,.systemDefined)
                XCTAssertEqual(native.subtype.rawValue,8)
                XCTAssertEqual(native.data1,(code << 16) | (state << 8))
                XCTAssertEqual(native.data2,-1)
                XCTAssertTrue(native.modifierFlags.contains([.option,.shift]))
                XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData),SelectedTrackpadEventPolicy.interpreterTag)
            }
            for phase in [GestureSessionPhase.pending,.changed,.ended,.cancelled] {
                XCTAssertNil(plan.events(phase:phase))
            }
            for trigger in GestureTrigger.allCases where trigger != .fourCornersTap && (!trigger.isContinuous || trigger.isPinch) {
                var settings = HandGestureSettings()
                XCTAssertTrue(trigger.allowedActions.contains(action))
                XCTAssertTrue(settings.setAction(action,for:trigger,in:.both))
                var profile = AppKeymapProfile.defaultProfile(); profile.handGestureSettings = settings
                let imported = try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile())
                XCTAssertEqual(imported.handGestureSettings,settings)
            }
            var clicks = PrimaryTapClickOutput()
            XCTAssertEqual(GestureTapActionOutput.events(action:action,location:.zero,time:1,
                doubleClickInterval:0.5,clicks:&clicks,shortcut:plan)?.count,2)
            XCTAssertFalse(GestureTrigger.twoFingerMove.allowedActions.contains(action))
        }
    }
}

extension PinchZoomTests {
    private func rotatingChord(count:Int,angle:Double,thumb:Bool = true,scale:Double = 1) -> [OMSRawTouch] {
        (0..<count).map { i in
            let x = i == 0 ? 0.0 : 45+Double(i-1)*7
            let y = i == 0 ? 0.0 : -45.0
            let px = 40+scale*(x*cos(angle)-y*sin(angle))
            let py = 80+scale*(x*sin(angle)+y*cos(angle))
            return OMSRawTouch(id:Int32(i+1),posX:Float(px/160),posY:Float(1-py/114.9),total:1,pressure:40,
                majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching,
                telemetry:.init(fingerID:i == 0 ? thumb ? 1 : 2 : Int32(i+1),handID:1,velocityX:0,velocityY:0,
                    absoluteX:0,absoluteY:0,absoluteVelocityX:0,absoluteVelocityY:0,sourceFrame:1,sourceTimestamp:1))
        }
    }
    func testRotationUsesSharedLatchAndFiresOnceForEitherDirectionAndCount() {
        for count in 2...5 { for sign in [-1.0,1.0] {
            var router = TrackpadGestureRouter()
            let expected = GestureTrigger.rotation(count:count,right:sign > 0)!
            _ = router.recognize(device:1,time:1,contacts:rotatingChord(count:count,angle:0),enabled:{$0.isRotation})
            let start = router.recognize(device:1,time:1.01,contacts:rotatingChord(count:count,angle:sign*0.10),enabled:{$0.isRotation})
            XCTAssertEqual(start.gesture,expected); XCTAssertEqual(start.phase,.began)
            XCTAssertEqual(start.rotationDelta ?? 0,sign*0.10,accuracy:0.00001)
            let reversed = router.recognize(device:1,time:1.02,contacts:rotatingChord(count:count,angle:-sign*0.12),enabled:{$0.isRotation})
            XCTAssertEqual(reversed.gesture,expected); XCTAssertEqual(reversed.phase,.changed)
            XCTAssertEqual(reversed.rotationDelta ?? 0,-sign*0.22,accuracy:0.00001)
            let still = router.recognize(device:1,time:1.025,contacts:rotatingChord(count:count,angle:-sign*0.12),enabled:{$0.isRotation})
            XCTAssertEqual(still.rotationDelta ?? 1,0,accuracy:0.00001)
            let lifted = router.recognize(device:1,time:1.03,contacts:Array(rotatingChord(count:count,angle:0).prefix(1)),enabled:{$0.isRotation})
            XCTAssertEqual(lifted.gesture,expected); XCTAssertEqual(lifted.phase,.changed)
            XCTAssertEqual(router.recognize(device:1,time:1.04,contacts:[OMSRawTouch](),enabled:{$0.isRotation}).phase,.ended)
        }}
    }
    func testThumbRotationDoesNotBlockCoherentTranslationOrWaitForeverForLanding() {
        for count in [2,4,5] {
            var router = TrackpadGestureRouter()
            _ = router.recognize(device:1,time:1,contacts:chord(count),enabled:{_ in true})
            let moved = router.recognize(device:1,time:1.01,contacts:chord(count,translation:1),enabled:{_ in true})
            let expected:GestureTrigger = count == 2 ? .twoFingerMove : count == 4 ? .fourFingerMove : .fiveFingerMove
            XCTAssertEqual(moved.gesture,expected)
        }
        var router = TrackpadGestureRouter()
        func landing(_ dx:Double) -> [OMSRawTouch] {
            let source = chord(5)[0]
            let thumb = OMSRawTouch(id:source.id,posX:source.posX,posY:source.posY,total:source.total,
                pressure:source.pressure,majorAxis:source.majorAxis,minorAxis:source.minorAxis,angle:source.angle,
                density:source.density,state:.hovering,telemetry:source.telemetry)
            return Array(chord(5,translation:dx).dropFirst()) + [thumb]
        }
        _ = router.recognize(device:2,time:1,contacts:landing(0),enabled:{_ in true})
        for offset in [0.01,0.06,0.11] {
            XCTAssertNil(router.recognize(device:2,time:1+offset,contacts:landing(offset*20),enabled:{_ in true}).gesture)
        }
        XCTAssertEqual(router.recognize(device:2,time:1.16,contacts:landing(3.2),enabled:{_ in true}).gesture,.fourFingerMove)
    }
    func testPureScaleAndMissingThumbCannotClaimRotation() {
        for count in 2...5 { for missingThumb in [false,true] {
            var router = TrackpadGestureRouter()
            _ = router.recognize(device:1,time:1,contacts:rotatingChord(count:count,angle:0,thumb:!missingThumb),enabled:{$0.isRotation})
            XCTAssertNil(router.recognize(device:1,time:1.01,contacts:rotatingChord(count:count,angle:missingThumb ? 0.2 : 0,thumb:!missingThumb,scale:missingThumb ? 1 : 1.15),enabled:{$0.isRotation}).gesture)
        }}
    }
    func testUserRotationCaptureActivatesLeftRotationWithCompetingShapeActions() throws {
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("AppleMagicTouchstream/AppleMagicTouchstream/rotate_no_work.atpcap")
        guard FileManager.default.fileExists(atPath:url.path) else { throw XCTSkip("Local rotation capture not bundled") }
        let records = try ATPCaptureV3Codec.readCaptureData(from:url).frameRecords
        var router = TrackpadGestureRouter(), activations:[GestureTrigger] = []
        for record in records {
            let frame = record.frame
            let update = router.recognize(device:frame.deviceNumericID,time:frame.timestamp,contacts:frame.rawTouches) {
                $0.isPinch || GestureTrigger.liveRotationTriggers.contains($0) || $0 == .threeFingerMove
            }
            if update.phase == .began, let gesture = update.gesture { activations.append(gesture) }
        }
        XCTAssertEqual(activations,Array(repeating:.threeFingerRotateLeft,count:8))
    }
}

extension PinchZoomTests {
    func testRightRotationCaptureCompetesWithScale() throws {
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("AppleMagicTouchstream/AppleMagicTouchstream/rotate_right.atpcap")
        guard FileManager.default.fileExists(atPath:url.path) else { throw XCTSkip("Local right rotation capture not bundled") }
        let records = try ATPCaptureV3Codec.readCaptureData(from:url).frameRecords
        var router = TrackpadGestureRouter(), cycle=0, outputs:[String] = [], wasDown=false
        for record in records {
            let frame=record.frame, down=frame.rawTouches.contains {$0.state == .making || $0.state == .touching}
            let update = router.recognize(device:frame.deviceNumericID,time:frame.timestamp,contacts:frame.rawTouches) {
                $0.isPinch || GestureTrigger.liveRotationTriggers.contains($0) || $0 == .threeFingerMove
            }
            if update.phase == .began, let gesture=update.gesture { outputs.append("\(cycle):\(gesture.rawValue)") }
            if wasDown && !down { cycle += 1 }; wasDown=down
        }
        XCTAssertEqual(outputs,["0:threeFingerRotateLeft","1:threeFingerRotateLeft"] + (2...9).map { "\($0):threeFingerRotateRight" })
    }
}


extension PinchZoomTests {
    func testRotationPreservesGeometryWhileThumbClassificationSettles() {
        var router = TrackpadGestureRouter()
        _ = router.recognize(device:1,time:1,contacts:rotatingChord(count:3,angle:0,thumb:false),enabled:{$0.isRotation})
        XCTAssertNil(router.recognize(device:1,time:1.01,contacts:rotatingChord(count:3,angle:0.1,thumb:false),enabled:{$0.isRotation}).gesture)
        let recognized = router.recognize(device:1,time:1.02,contacts:rotatingChord(count:3,angle:0.12),enabled:{$0.isRotation})
        XCTAssertEqual(recognized.gesture,.threeFingerRotateRight)
        XCTAssertEqual(recognized.phase,.began)
    }
}

extension PinchZoomTests {
    func testOpposedThumbAndFingertipsCannotAcquireMovementBeforePinch() throws {
        for count in 3...5 {
            var router = TrackpadGestureRouter()
            _ = router.recognize(device:1,time:1,contacts:chord(count),enabled:{_ in true})
            let early = router.recognize(device:1,time:1.01,contacts:chord(count,spread:-0.5,translation:0.1),enabled:{_ in true})
            XCTAssertNil(early.gesture,"Early contraction must not latch majority motion for \(count) contacts")
            let pinch = router.recognize(device:1,time:1.02,contacts:chord(count,spread:-2,translation:0.3),enabled:{_ in true})
            XCTAssertEqual(pinch.gesture,GestureTrigger.pinch(count:count))
        }
    }
    func testThumbJoiningDoesNotCountPriorFingertipTravelAsFiveFingerMovement() {
        var router = TrackpadGestureRouter()
        _ = router.recognize(device:1,time:1,contacts:Array(chord(5).dropFirst()),enabled:{_ in true})
        let join = router.recognize(device:1,time:1.01,contacts:chord(5,spread:-2,translation:0.5),enabled:{_ in true})
        XCTAssertNil(join.gesture)
        let pinch = router.recognize(device:1,time:1.02,contacts:chord(5,spread:-3.5,translation:1),enabled:{_ in true})
        XCTAssertEqual(pinch.gesture,.fiveFingerPinch)
    }
    func testThumbBearingRigidTranslationStillActivatesMovementAndKeepsFirstOwner() {
        for count in 4...5 {
            var router = TrackpadGestureRouter()
            _ = router.recognize(device:1,time:1,contacts:chord(count),enabled:{_ in true})
            let move = router.recognize(device:1,time:1.01,contacts:chord(count,translation:0.5),enabled:{_ in true})
            let expected:GestureTrigger = count == 4 ? .fourFingerMove:.fiveFingerMove
            XCTAssertEqual(move.gesture,expected)
            XCTAssertEqual(router.recognize(device:1,time:1.02,contacts:chord(count,spread:-4,translation:1),enabled:{_ in true}).gesture,expected)
        }
        var router = TrackpadGestureRouter()
        _ = router.recognize(device:1,time:1,contacts:Array(chord(4).dropFirst()),enabled:{_ in true})
        XCTAssertEqual(router.recognize(device:1,time:1.01,contacts:Array(chord(4,translation:0.5).dropFirst()),enabled:{_ in true}).gesture,.threeFingerMove)
        XCTAssertEqual(router.recognize(device:1,time:1.02,contacts:chord(4,spread:-4,translation:1),enabled:{_ in true}).gesture,.threeFingerMove)
    }
    func testRecordedStaggeredPinchesBeatCompetingMovement() throws {
        struct Trace:Decodable { let frames:[RuntimeRawFrame] }
        let url = try XCTUnwrap(Bundle.module.url(forResource:"bad-pinch",withExtension:"json",subdirectory:"Fixtures"))
        let frames = try JSONDecoder().decode(Trace.self,from:Data(contentsOf:url)).frames
        var router = TrackpadGestureRouter(), cycle=0, wasDown=false
        var results:[String] = []
        for frame in frames {
            let down = frame.rawTouches.contains { $0.state == .making || $0.state == .touching }
            let result = router.recognize(device:frame.deviceNumericID,time:frame.timestamp,contacts:frame.rawTouches) {
                $0.isPinch || $0 == .twoFingerMove || $0 == .threeFingerMove || $0 == .fourFingerMove || $0 == .fiveFingerMove
            }
            if result.phase == .began, let gesture = result.gesture { results.append("\(cycle):\(gesture.rawValue)") }
            if wasDown && !down { cycle += 1 }; wasDown=down
        }
        XCTAssertEqual(results,["0:fiveFingerPinch","1:fiveFingerPinch","2:fourFingerPinch",
            "3:fourFingerPinch","4:fiveFingerPinch","5:fourFingerPinch","6:threeFingerPinch",
            "7:threeFingerPinch","8:threeFingerPinch","9:threeFingerPinch","10:threeFingerPinch",
            "11:fourFingerPinch","12:fiveFingerPinch","13:twoFingerMove","15:twoFingerMove"])
    }
}

extension PinchZoomTests {
    func testRecordedRotationsAcrossCountsWithPinchAndMovementCompetition() throws {
        struct Trace:Decodable { let frames:[RuntimeRawFrame] }
        let url = try XCTUnwrap(Bundle.module.url(forResource:"rotation-counts",withExtension:"json",subdirectory:"Fixtures"))
        let frames = try JSONDecoder().decode(Trace.self,from:Data(contentsOf:url)).frames
        var router = TrackpadGestureRouter(), cycle=0, wasDown=false
        var results:[String] = []
        for frame in frames {
            let down = frame.rawTouches.contains { $0.state == .making || $0.state == .touching }
            let result = router.recognize(device:frame.deviceNumericID,time:frame.timestamp,contacts:frame.rawTouches) {
                $0.isPinch || GestureTrigger.liveRotationTriggers.contains($0) || [.twoFingerMove,.threeFingerMove,.fourFingerMove,.fiveFingerMove].contains($0)
            }
            if result.phase == .began, let gesture = result.gesture { results.append("\(cycle):\(gesture.rawValue)") }
            if wasDown && !down { cycle += 1 }; wasDown=down
        }
        let expected = [2,3,4,5].flatMap { count in
            (0..<4).map { i in "\((count-2)*4+i):\(GestureTrigger.rotation(count:count,right:i % 2 == 0)!.rawValue)" }
        }
        XCTAssertEqual(Array(results.prefix(16)),expected)
        XCTAssertTrue(results.dropFirst(16).allSatisfy { $0.hasSuffix(":twoFingerMove") })
    }
}
