import AppKit
import CoreGraphics
import Foundation
import OpenMultitouchSupport
import XCTest
@testable import GlassToKeyRuntime

final class GestureActionBindingTests: XCTestCase {
    func testSmartZoomCatalogAndSettingsRoundTrip() throws {
        XCTAssertEqual(GestureAction(rawValue:"smartZoom"),.smartZoom)
        XCTAssertEqual(GestureAction.smartZoom.title,"Smart Zoom")
        XCTAssertTrue(GestureAction.smartZoom.isDiscreteOutput)
        XCTAssertFalse(GestureAction.smartZoom.isAppleShortcut)
        for trigger in [GestureTrigger.twoFingerTap,.threeFingerTap,.thumbTwoTap,
                        .fourFingerTap,.fiveFingerTap,.oneFingerForce,.twoFingerPinch,.fiveFingerRotateLeft] {
            var settings = HandGestureSettings()
            XCTAssertTrue(settings.setAction(.smartZoom,for:trigger,in:.left))
            let restored = try JSONDecoder().decode(HandGestureSettings.self,from:JSONEncoder().encode(settings))
            XCTAssertEqual(restored.action(trigger,in:.left),.smartZoom)
            XCTAssertNotEqual(restored.action(trigger,in:.right),.smartZoom)
        }
        var profile = AppKeymapProfile.defaultProfile()
        var settings = HandGestureSettings()
        settings.setAction(.smartZoom,for:.twoFingerTap,in:.left)
        profile.handGestureSettings = settings
        let imported = try PortableKeymapInterop.importProfile(
            from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile())
        XCTAssertEqual(imported.handGestureSettings?.action(.twoFingerTap,in:.left),.smartZoom)
        XCTAssertTrue(PerHandGestureSettings.holdActions(for:3).contains(.smartZoom))
        XCTAssertTrue(GestureDirectionalAssignments.allowedActions.contains(.smartZoom))
        XCTAssertTrue(TwoHandGestureSettings.allowedActions.contains(.smartZoom))
        XCTAssertFalse(GestureTrigger.twoFingerMove.allowedActions.contains(.smartZoom))
    }
    func testSmartZoomBuildsNativeEventWithoutButtonOrKeyboardEdges() throws {
        var clicks = PrimaryTapClickOutput()
        _ = clicks.events(location:CGPoint(x:100,y:200),time:1,doubleClickInterval:0.5)
        let events = try XCTUnwrap(GestureTapActionOutput.events(action:.smartZoom,
            location:CGPoint(x:100,y:200),time:1.1,doubleClickInterval:0.5,flags:.maskShift,clicks:&clicks))
        XCTAssertEqual(events.count,1)
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(try XCTUnwrap(NSEvent(cgEvent:event)).type,.smartMagnify)
        XCTAssertEqual(event.location,CGPoint(x:100,y:200))
        XCTAssertEqual(event.flags,.maskShift)
        XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData),SelectedTrackpadEventPolicy.interpreterTag)
        XCTAssertEqual(event.getIntegerValueField(MagnifyGestureOutput.phase),0)
        XCTAssertEqual(try XCTUnwrap(clicks.events(location:CGPoint(x:100,y:200),time:1.2,
            doubleClickInterval:0.5)).down.getIntegerValueField(.mouseEventClickState),1)
        XCTAssertNil(SmartZoomGestureOutput.event(location:CGPoint(x:Double.nan,y:0)))
        XCTAssertNil(SmartZoomGestureOutput.event(location:CGPoint(x:0,y:Double.infinity)))
    }
    func testLookUpAndSpacesUseConfiguredShortcutsAndHonorDisabledBindings() throws {
        for (action,id,code,flags) in [(GestureAction.lookUp,"70",CGKeyCode(2),CGEventFlags([.maskControl,.maskCommand])),
                                       (.previousSpace,"79",123,.maskControl),(.nextSpace,"81",124,.maskControl)] {
            for preferences:[String:Any] in [[:],[id:["enabled":true]]] {
                let plan = try XCTUnwrap(AppleShortcutPlan.resolve(action,preferences:preferences))
                XCTAssertEqual(plan.keyCode,code)
                XCTAssertEqual(plan.flags,flags)
                let events = try XCTUnwrap(plan.events())
                let keys = events.filter { $0.type != .flagsChanged }
                XCTAssertEqual(keys.map(\.type),[.keyDown,.keyUp])
                XCTAssertEqual(keys.map { $0.getIntegerValueField(.keyboardEventKeycode) },[Int64(code),Int64(code)])
                let expectedFlags = code == 2 ? flags : flags.union([.maskSecondaryFn,.maskNumericPad])
                XCTAssertTrue(keys.allSatisfy { $0.flags == expectedFlags })
                XCTAssertEqual(events.first?.type,.flagsChanged)
                XCTAssertEqual(events.last?.flags,[])
                XCTAssertTrue(events.allSatisfy { $0.getIntegerValueField(.eventSourceUserData) == SelectedTrackpadEventPolicy.interpreterTag })
                for phase in [GestureSessionPhase.pending,.changed,.ended,.cancelled] { XCTAssertNil(plan.events(phase:phase)) }
            }
            let custom:[String:Any] = [id:["enabled":true,"value":["type":"standard","parameters":[65535,20,CGEventFlags.maskAlternate.rawValue]]]]
            let configured = try XCTUnwrap(AppleShortcutPlan.resolve(action,preferences:custom))
            XCTAssertEqual(configured.keyCode,20)
            XCTAssertEqual(configured.flags,.maskAlternate)
            for invalid:[String:Any] in [[id:["enabled":false]],[id:["enabled":false,"value":custom[id]!]],
                                        [id:["enabled":true,"value":["type":"standard","parameters":[0,999,0]]]],
                                        [id:"invalid"],[id:["value":[:]]]] {
                XCTAssertNil(AppleShortcutPlan.resolve(action,preferences:invalid))
            }
            var profile = AppKeymapProfile.defaultProfile(), settings = HandGestureSettings()
            XCTAssertTrue(settings.setAction(action,for:.threeFingerTap,in:.left))
            profile.handGestureSettings = settings
            let imported = try PortableKeymapInterop.importProfile(
                from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile())
            XCTAssertEqual(imported.handGestureSettings?.action(.threeFingerTap,in:.left),action)
            XCTAssertEqual(imported.handGestureSettings?.action(.threeFingerTap,in:.right),.primaryDoubleClick)
        }
    }
    func testSpaceShortcutBorrowsAndRestoresOnlyItsOwnModifiers() throws {
        let plan = try XCTUnwrap(AppleShortcutPlan.resolve(.nextSpace,preferences:[:]))
        let events = try XCTUnwrap(plan.events(restoringFlags:.maskShift))
        XCTAssertEqual(events.map(\.type),[.flagsChanged,.keyDown,.keyUp,.flagsChanged])
        XCTAssertEqual(events.map { $0.getIntegerValueField(.keyboardEventKeycode) },[59,124,124,59])
        XCTAssertEqual(events.map(\.flags),[[.maskShift,.maskControl],[.maskShift,.maskControl,.maskSecondaryFn,.maskNumericPad],
                                           [.maskShift,.maskControl,.maskSecondaryFn,.maskNumericPad],.maskShift])
        let held = try XCTUnwrap(plan.events(restoringFlags:[.maskControl,.maskShift]))
        XCTAssertEqual(held.map(\.type),[.keyDown,.keyUp])
        XCTAssertTrue(held.allSatisfy { $0.flags == [.maskControl,.maskShift,.maskSecondaryFn,.maskNumericPad] })
        var clicks = PrimaryTapClickOutput()
        let dispatched = try XCTUnwrap(GestureTapActionOutput.events(action:.nextSpace,
            location:.zero,time:1,doubleClickInterval:0.5,flags:.maskControl,clicks:&clicks,shortcut:plan))
        XCTAssertEqual(dispatched.map(\.type),[.keyDown,.keyUp])
        let lookup = try XCTUnwrap(AppleShortcutPlan.resolve(.lookUp,preferences:[:])?.events())
        XCTAssertEqual(lookup.map { $0.getIntegerValueField(.keyboardEventKeycode) },[59,55,2,2,55,59])
        XCTAssertEqual(lookup.last?.flags,[])
    }
    func testNativeArrowClassificationDoesNotPressGlobeOrLeakToCustomLetterBinding() throws {
        let native = try XCTUnwrap(SystemShortcutOutput.events(code:123,
            flags:[.maskControl,.maskSecondaryFn],restoringFlags:[]))
        XCTAssertEqual(native.map { $0.getIntegerValueField(.keyboardEventKeycode) },[59,123,123,59])
        XCTAssertEqual(native.map(\.type),[.flagsChanged,.keyDown,.keyUp,.flagsChanged])
        let arrow = try XCTUnwrap(NSEvent(cgEvent:native[1]))
        XCTAssertTrue(arrow.modifierFlags.contains([.control,.function,.numericPad]))
        XCTAssertEqual(native.first?.flags,.maskControl)
        XCTAssertEqual(native.last?.flags,[])
        let letter = try XCTUnwrap(SystemShortcutOutput.events(code:20,flags:.maskAlternate,restoringFlags:[]))
        XCTAssertEqual(letter[1].flags,.maskAlternate)
        XCTAssertFalse(letter[1].flags.contains(.maskSecondaryFn))
        XCTAssertFalse(letter[1].flags.contains(.maskNumericPad))
    }
    func testNativePageNavigationDirectionAndPortableAssignments() throws {
        for action in [GestureAction.pageBack,.pageForward] {
            var clicks = PrimaryTapClickOutput()
            let events = try XCTUnwrap(GestureTapActionOutput.events(action:action,location:CGPoint(x:20,y:30),
                time:1,doubleClickInterval:0.5,flags:.maskShift,clicks:&clicks))
            XCTAssertEqual(events.count,1)
            let event = try XCTUnwrap(events.first)
            let native = try XCTUnwrap(NSEvent(cgEvent:event))
            XCTAssertEqual(native.type,.swipe)
            XCTAssertEqual(native.deltaX,action == .pageBack ? 1 : -1)
            XCTAssertEqual(native.deltaY,0)
            XCTAssertEqual(event.location,CGPoint(x:20,y:30))
            XCTAssertEqual(event.flags,.maskShift)
            XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData),SelectedTrackpadEventPolicy.interpreterTag)
            XCTAssertTrue(action.isDiscreteOutput)
            XCTAssertTrue(GestureTrigger.twoFingerTap.allowedActions.contains(action))
            XCTAssertTrue(GestureDirectionalAssignments.allowedActions.contains(action))
        }
        XCTAssertNil(PageNavigationOutput.event(forward:true,location:CGPoint(x:Double.nan,y:0)))
        var settings = HandGestureSettings(), profile = AppKeymapProfile.defaultProfile()
        settings.setAction(.pageBack,for:.twoFingerTap,in:.left)
        settings.setAction(.pageForward,for:.twoFingerTap,in:.right)
        settings.setAction(.rotate,for:.threeFingerRotateLeft,in:.left)
        profile.handGestureSettings = settings
        let restored = try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile())
        XCTAssertEqual(restored.handGestureSettings,settings)
        XCTAssertFalse(GestureTrigger.twoFingerTap.allowedActions.contains(.rotate))
        XCTAssertFalse(GestureDirectionalAssignments.allowedActions.contains(.rotate))
        XCTAssertTrue(GestureTrigger.liveRotationTriggers.allSatisfy { $0.allowedActions.contains(.rotate) })
    }
    func testNativeRotationPhasesDirectionAnchorAndCancellation() throws {
        var output = RotateGestureOutput()
        XCTAssertNil(output.update(radians:0.1,began:false,location:.zero))
        let start = try XCTUnwrap(output.update(radians:Double.pi/6,began:true,location:CGPoint(x:20,y:30),flags:.maskShift))
        let native = try XCTUnwrap(NSEvent(cgEvent:start))
        XCTAssertEqual(native.type,.rotate)
        XCTAssertEqual(native.rotation,-30,accuracy:0.001)
        XCTAssertEqual(native.phase,.began)
        let reverse = try XCTUnwrap(output.update(radians:-Double.pi/12,began:false,location:.zero,flags:.maskCommand))
        XCTAssertEqual(try XCTUnwrap(NSEvent(cgEvent:reverse)).rotation,15,accuracy:0.001)
        XCTAssertEqual(try XCTUnwrap(NSEvent(cgEvent:reverse)).phase,.changed)
        XCTAssertEqual(reverse.location,start.location); XCTAssertEqual(reverse.flags,.maskShift)
        XCTAssertEqual(reverse.getIntegerValueField(.eventSourceUserData),SelectedTrackpadEventPolicy.interpreterTag)
        let end = try XCTUnwrap(output.finish(cancelled:false))
        XCTAssertEqual(try XCTUnwrap(NSEvent(cgEvent:end)).phase,.ended)
        XCTAssertFalse(output.active); XCTAssertNil(output.finish(cancelled:true))
        _ = output.update(radians:0,began:true,location:.zero)
        XCTAssertEqual(try XCTUnwrap(NSEvent(cgEvent:try XCTUnwrap(output.finish(cancelled:true)))).phase,.cancelled)
        XCTAssertNil(output.update(radians:Double.nan,began:true,location:.zero))
        XCTAssertFalse(output.active)
        XCTAssertNil(RotateGestureOutput.event(degrees:181,phase:2,location:.zero))
    }
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
        let name = "AppleMagicTouchstream.ActionTests.\(UUID().uuidString)"
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


extension GestureActionBindingTests {
    func testRotationSlotsRoundTripIndependentlyAndTranslateWithoutTurning() throws {
        var settings = HandGestureSettings()
        for count in 2...5 {
            let left = try XCTUnwrap(GestureTrigger.rotation(count:count,right:false))
            let right = try XCTUnwrap(GestureTrigger.rotation(count:count,right:true))
            XCTAssertEqual(left.rotationCount,count); XCTAssertEqual(right.rotationCount,count)
            XCTAssertFalse(left.isPinch); XCTAssertFalse(right.isPinch)
            XCTAssertEqual(settings.action(left,in:.both),.disabled)
            XCTAssertEqual(settings.action(right,in:.both),.disabled)
            XCTAssertTrue(settings.setAction(.missionControl,for:left,in:.left))
            XCTAssertTrue(settings.setAction(.volumeUpSmall,for:right,in:.both))
            XCTAssertEqual(settings.action(left,in:.right),.disabled)
            XCTAssertEqual(settings.action(right,in:.both),.volumeUpSmall)
            var reservation = GestureKeyboardArbitration()
            XCTAssertEqual(reservation.process(device:1,activeCount:count) { GestureTrigger.liveRotationTriggers.contains($0) },count == 3 || count == 5)
            var router = TrackpadGestureRouter()
            _ = router.recognize(device:1,time:1,contacts:contacts(Array(1...Int32(count))),enabled:{$0.isRotation})
            XCTAssertNil(router.recognize(device:1,time:1.01,contacts:contacts(Array(1...Int32(count)),dx:0.02),enabled:{$0.isRotation}).gesture)
        }
        var profile = AppKeymapProfile.defaultProfile(); profile.handGestureSettings = settings
        let imported = try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile())
        XCTAssertEqual(imported.handGestureSettings,settings)
        let old = try JSONDecoder().decode(HandGestureSettings.self,from:JSONEncoder().encode(HandGestureSettings()))
        XCTAssertTrue(GestureTrigger.rotationTriggers.allSatisfy { old.left.bindings.action(for:$0) == .disabled })
    }
}
