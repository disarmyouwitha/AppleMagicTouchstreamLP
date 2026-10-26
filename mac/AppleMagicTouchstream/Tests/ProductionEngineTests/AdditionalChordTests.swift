import AppKit
import SwiftUI
import OpenMultitouchSupport
import XCTest
@testable import GlassToKeyRuntime

final class AdditionalChordTests:XCTestCase {
    private func touch(_ id:Int32,_ x:Float,_ y:Float,_ finger:Int32 = 0) -> OMSRawTouch {
        .init(id:id,posX:x,posY:y,total:1,pressure:40,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching,
            telemetry:.init(fingerID:finger,handID:1,velocityX:0,velocityY:0,absoluteX:0,absoluteY:0,
                absoluteVelocityX:0,absoluteVelocityY:0,sourceFrame:1,sourceTimestamp:1))
    }
    private var corners:[OMSRawTouch] { [touch(1,0.1,0.1),touch(2,0.1,0.9),touch(3,0.9,0.1),touch(4,0.9,0.9)] }
    private var four:[OMSRawTouch] { (0..<4).map { touch(Int32($0+1),0.2+Float($0)*0.15,0.5,Int32($0+2)) } }
    private var thumb:[OMSRawTouch] { [touch(1,0.15,0.2,1),touch(2,0.55,0.6,3),touch(3,0.65,0.6,4)] }
    private var ordinary:[OMSRawTouch] { [touch(1,0.3,0.5,2),touch(2,0.4,0.5,3),touch(3,0.5,0.5,4)] }
    private func cornerSettings(tap:GestureAction = .secondaryClick,hold:GestureAction = .openConfig) -> TwoHandGestureSettings {
        var value = TwoHandGestureSettings()
        value.setAction(tap,for:.init(chord:.fourCorners,phase:.tap))
        value.setAction(hold,for:.init(chord:.fourCorners,phase:.hold))
        return value
    }
    func testDefaultsOldProfilesAndIndependentPerHandBindingsRoundTrip() throws {
        var settings = HandGestureSettings()
        XCTAssertEqual(settings.left.bindings.action(for:.fourFingerTap),.disabled)
        XCTAssertEqual(settings.left.bindings.action(for:.fourCornersTap),.disabled)
        XCTAssertEqual(settings.left.holdAction(count:6),.disabled)
        XCTAssertEqual(settings.left.holdAction(count:7),.openConfig)
        settings.setHoldAction(.missionControl,count:3,in:.left)
        settings.setHoldAction(.secondaryClick,count:6,in:.left)
        settings.setHoldAction(.showDesktop,count:7,in:.left)
        settings.setAction(.primaryClick,for:.fourFingerTap,in:.both)
        settings.setAction(.openConfig,for:.fourCornersTap,in:.left)
        XCTAssertEqual(settings.right.holdAction(count:3),.disabled)
        XCTAssertEqual(settings.right.holdAction(count:6),.disabled)
        XCTAssertEqual(settings.right.holdAction(count:7),.openConfig)
        XCTAssertEqual(settings.twoHand.action(.init(chord:.fourCorners,phase:.hold)),.openConfig)
        var profile = AppKeymapProfile.defaultProfile(); profile.handGestureSettings = settings
        XCTAssertEqual(try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile()).handGestureSettings,settings)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(settings)) as? [String:Any])
        for side in ["left","right"] {
            var hand = try XCTUnwrap(object[side] as? [String:Any])
            var bindings = try XCTUnwrap(hand["bindings"] as? [String:Any])
            bindings.removeValue(forKey:"fourFingerTap"); bindings.removeValue(forKey:"fourCornersTap"); hand["bindings"] = bindings
            var holds = hand["holdActions"] as? [String:Any] ?? [:]; holds.removeValue(forKey:"6"); holds.removeValue(forKey:"7"); hand["holdActions"] = holds
            object[side] = hand
        }
        let old = try JSONDecoder().decode(HandGestureSettings.self,from:JSONSerialization.data(withJSONObject:object))
        XCTAssertEqual(old.left.holdAction(count:3),.missionControl)
        XCTAssertEqual(old.left.holdAction(count:6),.disabled)
        XCTAssertEqual(old.left.holdAction(count:7),.openConfig)
        XCTAssertEqual(old.left.bindings.action(for:.fourFingerTap),.disabled)
    }
    func testFiveFingerTapUsesSharedSkewCancellationAndAllUpRules() {
        let five = [touch(1,0.1,0.3,1),touch(2,0.3,0.5,2),touch(3,0.4,0.6,3),touch(4,0.5,0.5,4),touch(5,0.6,0.4,5)]
        var tap = TwoFingerTapRecognizer(requiredCount:5)
        XCTAssertFalse(tap.process(device:1,time:1,contacts:Array(five.prefix(3))))
        XCTAssertFalse(tap.process(device:1,time:1.04,contacts:five))
        XCTAssertFalse(tap.process(device:1,time:1.10,contacts:Array(five.prefix(2))))
        XCTAssertTrue(tap.process(device:1,time:1.14,contacts:[OMSRawTouch]()))
        XCTAssertFalse(tap.process(device:1,time:1.15,contacts:[OMSRawTouch]()))
        for failure in 0...3 {
            var tap = TwoFingerTapRecognizer(requiredCount:5)
            _ = tap.process(device:1,time:2,contacts:five)
            switch failure {
            case 0:_ = tap.process(device:1,time:2.1,contacts:five,gestureActive:true)
            case 1:_ = tap.process(device:1,time:2.1,contacts:five+[touch(6,0.8,0.5)])
            case 2:_ = tap.process(device:1,time:2.1,contacts:[touch(1,0.2,0.3,1)]+Array(five.dropFirst()))
            default:tap.cancel(device:1)
            }
            XCTAssertFalse(tap.process(device:1,time:2.15,contacts:[OMSRawTouch]()))
            XCTAssertFalse(tap.process(device:1,time:3,contacts:five))
            XCTAssertTrue(tap.process(device:1,time:3.1,contacts:[OMSRawTouch]()))
        }
    }
    func testFiveFingerAssignmentsDefaultOffAndRoundTripWithoutChangingExistingInputs() throws {
        var settings = HandGestureSettings()
        XCTAssertEqual(settings.left.bindings.action(for:.fiveFingerTap),.disabled)
        XCTAssertEqual(settings.left.bindings.action(for:.fiveFingerMove),.disabled)
        XCTAssertEqual(GestureTrigger.fiveFingerTap.allowedActions,GestureTrigger.fiveFingerForce.allowedActions)
        XCTAssertEqual(GesturePane.fiveFingers.title,"Tap and Move")
        XCTAssertEqual(GesturePane.fiveFingers.triggers,[.fiveFingerTap,.fiveFingerForce,.fiveFingerMove])
        settings.setAction(.missionControl,for:.fiveFingerTap,in:.left)
        settings.setAction(.pointer,for:.fiveFingerMove,in:.left)
        settings.setHoldAction(.showDesktop,count:5,in:.left)
        settings.editMovement(.fiveFingerMove,mode:.directional,direction:.right,action:.panRight,in:.left)
        settings.setDirectionalRepeatInterval(80,direction:.up,for:.fiveFingerMove,in:.left)
        var profile = AppKeymapProfile.defaultProfile(); profile.handGestureSettings = settings
        XCTAssertEqual(try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile()).handGestureSettings,settings)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(settings)) as? [String:Any])
        for side in ["left","right"] {
            var hand = try XCTUnwrap(object[side] as? [String:Any])
            var bindings = try XCTUnwrap(hand["bindings"] as? [String:Any])
            bindings.removeValue(forKey:"fiveFingerTap"); bindings.removeValue(forKey:"fiveFingerMove")
            hand["bindings"] = bindings; object[side] = hand
        }
        let legacy = try JSONDecoder().decode(HandGestureSettings.self,from:JSONSerialization.data(withJSONObject:object))
        XCTAssertEqual(legacy.left.bindings.action(for:.fiveFingerTap),.disabled)
        XCTAssertEqual(legacy.left.bindings.action(for:.fiveFingerMove),.disabled)
        XCTAssertEqual(legacy.left.holdAction(count:5),.showDesktop)
        XCTAssertEqual(legacy.left.bindings.action(for:.twoFingerMove),.pointer)
        XCTAssertEqual(legacy.left.bindings.action(for:.fourFingerMove),.scroll)
        XCTAssertEqual(legacy.right.bindings.action(for:.fiveFingerTap),.disabled)
    }
    func testThumbHoldAndOrdinaryHoldCannotFallBackToEachOther() {
        XCTAssertTrue(ThumbTwoChord.matches(thumb)); XCTAssertFalse(ThumbTwoChord.matches(ordinary))
        for isThumb in [false,true] {
            for enabledThumb in [false,true] {
                var hold = GestureHoldRecognizer(), output = [Int]()
                let actions:[Int:GestureAction] = enabledThumb ? [3:.primaryClick,6:.secondaryClick] : [3:.primaryClick]
                for i in 0...6 {
                    if let key = hold.observe(device:1,time:1+Double(i)*0.1,now:1+Double(i)*0.1,
                        contacts:isThumb ? thumb : ordinary,motionClaimed:false,actions:actions) { output.append(key) }
                }
                XCTAssertEqual(output,isThumb ? enabledThumb ? [6] : [] : [3])
            }
        }
    }
    func testThumbHoldKeepsItsPositiveMatchThroughFingertipRelabeling() {
        var hold = GestureHoldRecognizer(), output = [Int]()
        for i in 0...6 {
            let contacts = i < 2 ? thumb : [touch(1,0.15,0.2,0),touch(2,0.55,0.6,4),touch(3,0.65,0.6,5)]
            if let key = hold.observe(device:1,time:1+Double(i)*0.1,now:1+Double(i)*0.1,contacts:contacts,
                motionClaimed:false,actions:[3:.primaryClick,6:.secondaryClick]) { output.append(key) }
        }
        XCTAssertEqual(output,[6])
        _ = hold.observe(device:1,time:1.7,now:1.7,contacts:[OMSRawTouch](),motionClaimed:false,actions:[:])
        XCTAssertFalse(hold.claimed(device:1))
    }
    func testFourFingerTapSupportsSkewAndNeverFiresAfterHoldMovementOrExtraContacts() {
        var tap = TwoFingerTapRecognizer(requiredCount:4)
        XCTAssertFalse(tap.process(device:1,time:1,contacts:four))
        XCTAssertFalse(tap.process(device:1,time:1.1,contacts:Array(four.prefix(2))))
        XCTAssertTrue(tap.process(device:1,time:1.14,contacts:[OMSRawTouch]()))
        for failure in 0...3 {
            var tap = TwoFingerTapRecognizer(requiredCount:4)
            _ = tap.process(device:1,time:1,contacts:four)
            switch failure {
            case 0:_ = tap.process(device:1,time:1.1,contacts:four,gestureActive:true)
            case 1:_ = tap.process(device:1,time:1.1,contacts:four+[touch(5,0.8,0.5)])
            case 2:_ = tap.process(device:1,time:1.1,contacts:[touch(1,0.3,0.5)]+Array(four.dropFirst()))
            default:
                for i in 1...6 { _ = tap.process(device:1,time:1+Double(i)*0.1,contacts:four) }
            }
            XCTAssertFalse(tap.process(device:1,time:failure == 3 ? 1.65 : 1.15,contacts:[OMSRawTouch]()))
        }
        var reservation = GestureKeyboardArbitration()
        XCTAssertTrue(reservation.process(device:1,activeCount:4,enabled:{$0 == .fourFingerTap}))
        XCTAssertTrue(reservation.process(device:1,activeCount:0,enabled:{$0 == .fourFingerTap}))
    }
    func testCornerGeometryRequiresAllFourDistinctOuterCorners() {
        XCTAssertTrue(SinglePadCornersEngine.matches(corners))
        XCTAssertFalse(SinglePadCornersEngine.matches(four))
        XCTAssertFalse(SinglePadCornersEngine.matches(Array(corners.prefix(3))))
        XCTAssertFalse(SinglePadCornersEngine.matches(corners+[touch(5,0.5,0.5)]))
        XCTAssertFalse(SinglePadCornersEngine.matches([corners[0],corners[0],corners[2],corners[3]]))
        XCTAssertFalse(SinglePadCornersEngine.matches([touch(1,.nan,0.1)]+Array(corners.dropFirst())))
    }
    func testExpandedCornerTargetsShareBoundariesWithBothPadRecognition() {
        for inset:Float in [0.20,0.23,0.25,0.251,0.5] {
            let contacts = [touch(1,inset,inset),touch(2,inset,1-inset),
                            touch(3,1-inset,inset),touch(4,1-inset,1-inset)]
            let accepted = inset <= 0.25
            XCTAssertEqual(SinglePadCornersEngine.matches(contacts),accepted)
            let settings = TwoHandGestureSettings()
            var both = TwoHandGestureEngine()
            _ = both.process(leftHand:true,now:1,contacts:Array(contacts.prefix(2)),settings:settings)
            let decision = both.process(leftHand:false,now:1.01,contacts:Array(contacts.suffix(2)),settings:settings)
            XCTAssertEqual(decision.began,accepted)
            if accepted {
                var single = SinglePadCornersEngine()
                XCTAssertTrue(single.process(now:1.01,contacts:contacts,settings:settings).began)
                var singleOutput:[TwoHandTrigger] = [], bothOutput:[TwoHandTrigger] = []
                for i in 1...6 {
                    let now = 1.01+Double(i)*0.1
                    if let t = single.process(now:now,contacts:contacts,settings:settings).trigger { singleOutput.append(t) }
                    if let t = both.process(leftHand:true,now:now,contacts:Array(contacts.prefix(2)),settings:settings).trigger { bothOutput.append(t) }
                    if let t = both.process(leftHand:false,now:now+0.001,contacts:Array(contacts.suffix(2)),settings:settings).trigger { bothOutput.append(t) }
                }
                XCTAssertEqual(singleOutput,[.init(chord:.fourCorners,phase:.hold)])
                XCTAssertEqual(bothOutput,singleOutput)
                _ = single.process(now:1.7,contacts:[OMSRawTouch](),settings:settings)
                _ = both.process(leftHand:true,now:1.7,contacts:[OMSRawTouch](),settings:settings)
                _ = both.process(leftHand:false,now:1.71,contacts:[OMSRawTouch](),settings:settings)
                XCTAssertFalse(single.ownsCycle); XCTAssertFalse(both.ownsCycle)
            }
        }
        XCTAssertNil(CornerGestureGeometry.corner(x:Double.nan,y:0))
        XCTAssertNil(CornerGestureGeometry.corner(x:-0.01,y:0))
        XCTAssertNil(CornerGestureGeometry.corner(x:0.9,y:1.01))
        XCTAssertNil(CornerGestureGeometry.corner(x:0.5,y:0.1))
        XCTAssertNil(CornerGestureGeometry.corner(x:0.1,y:0.5))
    }
    func testCornerHoldFiresOnceWhileDownAndConsumesTap() {
        var engine = SinglePadCornersEngine(), fired = [TwoHandPhase]()
        let settings = cornerSettings()
        for i in 0...12 {
            let decision = engine.process(now:1+Double(i)*0.1,contacts:corners,settings:settings)
            XCTAssertTrue(decision.reserved)
            if let trigger = decision.trigger { fired.append(trigger.phase) }
        }
        XCTAssertEqual(fired,[.hold])
        let up = engine.process(now:2.25,contacts:[OMSRawTouch](),settings:settings)
        XCTAssertTrue(up.reserved); XCTAssertNil(up.trigger); XCTAssertFalse(engine.ownsCycle)
        XCTAssertTrue(engine.process(now:3,contacts:corners,settings:settings).began)
        XCTAssertNil(engine.process(now:3.15,contacts:[OMSRawTouch](),settings:settings).trigger)
    }
    func testCornerPartialLiftCannotTapOrHoldOnDeadlineLift() {
        let settings = cornerSettings()
        var engine = SinglePadCornersEngine()
        _ = engine.process(now:1,contacts:corners,settings:settings)
        _ = engine.process(now:1.1,contacts:Array(corners.prefix(2)),settings:settings)
        XCTAssertNil(engine.process(now:1.15,contacts:[OMSRawTouch](),settings:settings).trigger)
        _ = engine.process(now:2,contacts:corners,settings:settings)
        for i in 1...9 { _ = engine.process(now:2+Double(i)*0.1,contacts:corners,settings:settings) }
        XCTAssertNil(engine.process(now:3,contacts:Array(corners.prefix(3)),settings:settings).trigger)
        XCTAssertNil(engine.advance(now:3.01,settings:settings))
    }
    func testCornerInvalidExtraReplacedMovedOrStaleInputStaysReservedUntilAllUp() {
        let settings = cornerSettings()
        for failure in 0...4 {
            var engine = SinglePadCornersEngine()
            _ = engine.process(now:1,contacts:corners,settings:settings)
            switch failure {
            case 0:_ = engine.process(now:1.1,contacts:corners+[touch(5,0.5,0.5)],settings:settings)
            case 1:_ = engine.process(now:1.1,contacts:[touch(9,0.1,0.1)]+Array(corners.dropFirst()),settings:settings)
            case 2:_ = engine.process(now:1.1,contacts:[touch(1,0.15,0.1)]+Array(corners.dropFirst()),settings:settings)
            case 3:_ = engine.advance(now:1.3,settings:settings)
            default:
                _ = engine.process(now:1.1,contacts:Array(corners.prefix(3)),settings:settings)
                _ = engine.process(now:1.15,contacts:corners,settings:settings)
            }
            for i in 4...14 {
                let result = engine.process(now:1+Double(i)*0.1,contacts:corners,settings:settings)
                XCTAssertTrue(result.reserved); XCTAssertNil(result.trigger)
            }
            XCTAssertTrue(engine.process(now:2.45,contacts:[OMSRawTouch](),settings:settings).reserved)
            XCTAssertFalse(engine.ownsCycle)
        }
    }
    func testIndependentCornerPadsAndDisabledConfiguration() {
        var left = SinglePadCornersEngine(), right = SinglePadCornersEngine()
        let settings = cornerSettings()
        _ = left.process(now:1,contacts:corners,settings:settings)
        XCTAssertFalse(right.ownsCycle)
        XCTAssertFalse(right.process(now:1,contacts:corners,settings:cornerSettings(tap:.disabled,hold:.disabled)).reserved)
        _ = right.process(now:1,contacts:corners,settings:settings)
        left.reset(); XCTAssertFalse(left.ownsCycle); XCTAssertTrue(right.ownsCycle)
    }
}

@MainActor
final class SearchableGestureActionTests:XCTestCase {
    func testSearchFiltersSupportedActionsAndMixedChoicesDoNotMutateSettings() {
        for actions in [GestureDirectionalAssignments.allowedActions,GestureTrigger.fourFingerTap.allowedActions,TwoHandGestureSettings.allowedActions,PerHandGestureSettings.holdActions(for:6)] {
            let groups = GestureActionChooser.groups(actions)
            let shortcutChoices = GestureActionChooser.shortcutActions(actions,savedLabels:[])
            XCTAssertEqual(Set(groups.flatMap(\.actions) + shortcutChoices).intersection(Set(actions)),Set(actions.filter { $0 != .voice }))
            XCTAssertFalse(groups.flatMap(\.actions).contains(.voice))
            XCTAssertFalse(shortcutChoices.contains(.voice))
            let results = SearchableActionGroup.filtered(groups,query:"  PaN  ",label:{$0.title}).flatMap(\.actions)
            XCTAssertTrue(results.allSatisfy { $0.title.localizedCaseInsensitiveContains("pan") })
            XCTAssertTrue(SearchableActionGroup.filtered(groups,query:"not-a-real-action",label:{$0.title}).isEmpty)
            XCTAssertEqual(SearchableActionGroup.filtered(groups,query:"  ",label:{$0.title}).flatMap(\.actions),groups.flatMap(\.actions))
        }
        XCTAssertEqual(GesturePane.thumbTwo.holdKey,6)
        XCTAssertEqual(GesturePane.threeFingers.holdKey,3)
        XCTAssertEqual(GesturePane.fourCorners.holdKey,7)
        XCTAssertEqual(GesturePane.fourFingers.title,"Tap and Move")
        XCTAssertTrue(GesturePane.fourFingers.triggers.contains(.fourFingerTap))
    }
}

extension SearchableGestureActionTests {
    func testSearchableGestureAndKeymapSheetsRenderWithoutChangingAssignments() throws {
        func render<V:View>(_ view:V,name:String) throws {
            let host = NSHostingView(rootView:view.frame(width:540,height:560).background(Color(nsColor:.windowBackgroundColor)))
            host.frame = NSRect(x:0,y:0,width:540,height:560)
            let window = NSWindow(contentRect:host.frame,styleMask:[.borderless],backing:.buffered,defer:false)
            window.contentView = host; host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds))
            host.cacheDisplay(in:host.bounds,to:bitmap)
            if let directory = ProcessInfo.processInfo.environment["AMT_WORKSPACE_PREVIEW_DIR"] {
                let root = URL(fileURLWithPath:directory,isDirectory:true)
                try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
                try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:root.appendingPathComponent(name+".png"))
            }
            window.contentView = nil
        }
        try render(SearchableActionSheet(title:"Gesture Action",groups:GestureActionChooser.groups(GestureDirectionalAssignments.allowedActions),
            selected:GestureAction.panRight,label:{$0.title},choose:{_ in XCTFail("Render must not choose actions")}),name:"searchable-gesture-actions")
        let groups = KeyActionCatalog.primaryActionGroups.map { SearchableActionGroup(title:$0.title,actions:$0.actions) }
        try render(SearchableActionSheet(title:"Primary Action",groups:groups,selected:groups.first?.actions.first,
            label:{$0.pickerText},searchLabel:{$0.label+" "+$0.pickerText},choose:{_ in XCTFail("Render must not choose keymap actions")}),name:"searchable-keymap-actions")
    }
}

extension AdditionalChordTests {
    func testFourFingerTapOffersForceClickSystemActionsAndPreservesOneShotRecognition() throws {
        XCTAssertEqual(GestureTrigger.fourFingerTap.allowedActions,GestureTrigger.fourFingerForce.allowedActions)
        var settings = HandGestureSettings()
        for action in GestureAction.appleShortcuts {
            XCTAssertTrue(settings.setAction(action,for:.fourFingerTap,in:.both))
            XCTAssertEqual(settings.action(.fourFingerTap,in:.both),action)
            let plan = try XCTUnwrap(AppleShortcutPlan.resolve(action,preferences:[:]))
            if action == .missionControl || action == .appExpose {
                XCTAssertNotNil(plan.dockMessage)
                XCTAssertNil(plan.events()) // shared live dispatcher uses the Dock path
            } else {
                let events = try XCTUnwrap(plan.events())
                XCTAssertEqual(events.count,2)
                XCTAssertEqual(events.first?.type,.keyDown)
                XCTAssertEqual(events.last?.type,.keyUp)
            }
            var profile = AppKeymapProfile.defaultProfile(); profile.handGestureSettings = settings
            XCTAssertEqual(try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile()).handGestureSettings,settings)
        }
        var tap = TwoFingerTapRecognizer(requiredCount:4)
        XCTAssertFalse(tap.process(device:1,time:1,contacts:four))
        XCTAssertFalse(tap.process(device:1,time:1.1,contacts:four))
        XCTAssertTrue(tap.process(device:1,time:1.15,contacts:[OMSRawTouch]()))
        XCTAssertFalse(tap.process(device:1,time:1.16,contacts:[OMSRawTouch]()))
    }
}


extension AdditionalChordTests {
    func testRetiredOneFingerHoldAndCornerTapsAreInertEvenInImportedSettings() throws {
        var hand = PerHandGestureSettings()
        hand.holdActions = ["1":.missionControl]
        hand.bindings.fourCornersTap = .primaryClick
        XCTAssertFalse(hand.holdAvailable(count:1))
        XCTAssertEqual(hand.holdAction(count:1),.disabled)
        XCTAssertNil(hand.liveHoldActions[1])
        XCTAssertEqual(hand.bindings.action(for:.fourCornersTap),.disabled)
        hand.setHoldAction(.secondaryClick,count:1)
        XCTAssertEqual(hand.holdAction(count:1),.disabled)
        var both = TwoHandGestureSettings()
        both.assignments["fourCorners.tap"] = .primaryClick
        XCTAssertEqual(both.action(.init(chord:.fourCorners,phase:.tap)),.disabled)
        XCTAssertEqual(TwoHandChord.fourCorners.phases,[.hold])
        XCTAssertEqual(TwoHandChord.threeFingers.phases,[.tap,.hold])
        let decoded = try JSONDecoder().decode(PerHandGestureSettings.self,from:JSONEncoder().encode(hand))
        XCTAssertEqual(decoded.holdAction(count:1),.disabled)
        XCTAssertEqual(decoded.bindings.action(for:.fourCornersTap),.disabled)
        var engine = SinglePadCornersEngine()
        _ = engine.process(now:1,contacts:corners,settings:decoded.singlePadCorners)
        XCTAssertNil(engine.process(now:1.1,contacts:[OMSRawTouch](),settings:decoded.singlePadCorners).trigger)
        var paired = TwoHandGestureEngine()
        let left = Array(corners.prefix(2)), right = Array(corners.suffix(2))
        _ = paired.process(leftHand:true,now:1,contacts:left,settings:both)
        _ = paired.process(leftHand:false,now:1.01,contacts:right,settings:both)
        XCTAssertNil(paired.process(leftHand:true,now:1.1,contacts:[OMSRawTouch](),settings:both).trigger)
        XCTAssertNil(paired.process(leftHand:false,now:1.11,contacts:[OMSRawTouch](),settings:both).trigger)
    }
}


extension AdditionalChordTests {
    func testThumbAndSinglePadCornersUseTheirOwnHoldThreshold() {
        var hold = GestureHoldRecognizer()
        for i in 0...2 {
            let now = Double(i)*0.1
            XCTAssertNil(hold.observe(device:1,time:now,now:now,contacts:thumb,motionClaimed:false,actions:[6:.secondaryClick],thresholds:[3:1.5,6:0.25]))
        }
        XCTAssertEqual(hold.advance(device:1,now:0.251,actions:[6:.secondaryClick],thresholds:[3:1.5,6:0.25]),6)
        for duration in [0.5,1.25] {
            var engine = SinglePadCornersEngine(), settings = cornerSettings()
            settings.setHoldThreshold(duration,for:.fourCorners)
            for i in 0..<Int(duration*100) {
                XCTAssertNil(engine.process(now:Double(i)/100,contacts:corners,settings:settings).trigger)
            }
            XCTAssertEqual(engine.advance(now:duration+0.001,settings:settings),.init(chord:.fourCorners,phase:.hold))
            XCTAssertNil(engine.advance(now:duration+0.01,settings:settings))
        }
    }
}
