import Foundation
import Carbon
import CoreGraphics
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
    func testHoldAvailabilityIncludesContinuousMovementAndPreservesSavedHold() {
        for count in 2...5 {
            var value = ready(count)
            value.setHoldAction(.missionControl,count:count)
            XCTAssertTrue(value.holdAvailable(count:count))
            XCTAssertEqual(value.liveHoldActions[count],.missionControl)
            if let move = PerHandGestureSettings.moveTrigger(count:count) {
                value.editMovement(move,mode:.continuous)
                XCTAssertTrue(value.holdAvailable(count:count))
                XCTAssertEqual(value.liveHoldActions[count],.missionControl)
                value.bindings[move] = .disabled
                XCTAssertTrue(value.holdAvailable(count:count))
            }
            if let pinch = GestureTrigger.pinch(count:count), let spread = GestureTrigger.spread(count:count) {
                for trigger in [pinch,spread] {
                    value.bindings[trigger] = .missionControl
                    XCTAssertTrue(value.holdAvailable(count:count))
                    XCTAssertEqual(value.liveHoldActions[count],.missionControl)
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
        settings.right.editMovement(.threeFingerMove,mode:.continuous)
        XCTAssertTrue(settings.holdAvailable(count:3,in:.both))
        settings.setHoldAction(.showDesktop,count:3,in:.both)
        XCTAssertEqual(settings.left.holdAction(count:3),.showDesktop)
        XCTAssertEqual(settings.right.holdAction(count:3),.showDesktop)
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
    func testThumbPinchAndSpreadCanWinBeforeHoldDeadline() {
        for distance in [29.0,31.0] {
            var router = TrackpadGestureRouter(), hold = GestureHoldRecognizer()
            for i in 0...8 {
                let width = i == 0 ? 30 : distance
                let contacts = [(Int32(1),80-width/2),(Int32(2),80+width/2)].map { id,x in
                    OMSRawTouch(id:id,posX:Float(x/160),posY:0.5,total:1,pressure:40,
                        majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching,
                        telemetry:OMSTouchTelemetry(fingerID:id == 1 ? 1 : 2,handID:1,velocityX:0,velocityY:0,
                            absoluteX:0,absoluteY:0,absoluteVelocityX:0,absoluteVelocityY:0,sourceFrame:1,sourceTimestamp:1))
                }
                let time = 1+Double(i)*0.1
                let update = router.recognize(device:1,time:time,contacts:contacts,enabled:{$0.isPinch})
                if i == 1 { XCTAssertEqual(update.gesture,distance < 30 ? .twoFingerPinch : .twoFingerSpread) }
                XCTAssertNil(hold.observe(device:1,time:time,now:time,contacts:contacts,
                    motionClaimed:update.gesture != nil,actions:actions))
            }
            XCTAssertFalse(hold.claimed(device:1))
        }
    }
    func testSettlingToleranceStillRejectsDeliberateMotion() {
        for dx:Float in [0.01,0.02] {
            var hold = GestureHoldRecognizer()
            var result:Int?
            for i in 0...5 {
                result = hold.observe(device:1,time:1+Double(i)*0.1,now:1+Double(i)*0.1,
                    contacts:touches(4,dx:i == 0 ? 0 : dx),motionClaimed:false,actions:actions)
            }
            XCTAssertEqual(result,dx == 0.01 ? 4 : nil) // 1.6 mm settling vs. 3.2 mm motion
        }
    }
    func testDirectionalCandidateDoesNotCancelHoldBeforeARealDirection() {
        let pending = GestureSessionUpdate(gesture:GestureTrigger.fourFingerMove,phase:.began,millimetres:.init(x:0.21,y:0),cancellation:nil)
        XCTAssertFalse(GestureHoldRecognizer.motionClaimsHold(pending,directional:true,direction:nil))
        XCTAssertTrue(GestureHoldRecognizer.motionClaimsHold(pending,directional:true,direction:.right))
        XCTAssertTrue(GestureHoldRecognizer.motionClaimsHold(pending,directional:false,direction:nil))
        var directions = GestureDirectionalAssignments(mode:.directional)
        XCTAssertFalse(directions.hasAssignments)
        directions.actions["up"] = .volumeUpSmall
        XCTAssertTrue(directions.hasAssignments)
    }
    func testCapturedFourFingerHoldsSurviveLandingSettlingAndEmptyDirections() throws {
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let capture = root.appendingPathComponent("AppleMagicTouchstream/AppleMagicTouchstream/LHS_4FHold_bad.atpcap")
        guard FileManager.default.fileExists(atPath:capture.path) else { throw XCTSkip("Optional local four-finger Hold capture is unavailable") }
        let records = try ATPCaptureV3Codec.readCaptureData(from:capture).frameRecords
        var config = PerHandGestureSettings()
        config.bindings[.threeFingerPinch] = .disabled; config.bindings[.threeFingerSpread] = .disabled
        config.bindings[.fourFingerPinch] = .disabled; config.bindings[.fourFingerSpread] = .disabled
        config.bindings[.oneFingerForce] = .disabled; config.bindings[.twoFingerForce] = .missionControl
        config.editMovement(.fourFingerMove,mode:.directional)
        config.editMovement(.threeFingerMove,mode:.directional,direction:.up,action:.volumeUpSmall)
        config.setHoldAction(.appExpose,count:4)
        var hold = GestureHoldRecognizer(), router = TrackpadGestureRouter(), stepper = GestureDirectionalStepper()
        var force = ForceClickRecognizer(), fired = [Int](), deadlines = [Double]()
        let directional = config.liveDirectionalBindings, live = config.outputSettings.bindings
        var fullChordTime:Double?
        for record in records {
            let frame = record.frame, device = frame.deviceNumericID, time = frame.timestamp
            let now = Double(record.arrivalTicks)/1_000_000_000
            let contacts = frame.rawTouches
            let count = contacts.filter { $0.state == .making || $0.state == .touching }.count
            if count == 4 && fullChordTime == nil { fullChordTime = now }
            if count == 0 { fullChordTime = nil }
            if hold.claimed(device:device) {
                _ = hold.observe(device:device,time:time,now:now,contacts:contacts,motionClaimed:false,actions:[:])
                if count == 0 { _ = force.recognize(device:device,time:time,contacts:contacts,enabled:{_ in false}) }
                continue
            }
            _ = force.recognize(device:device,time:time,contacts:contacts,enabled:{ config.bindings.action(for:$0) != .disabled })
            if force.claimed(device:device) { hold.cancel(device:device); continue }
            let update = router.recognize(device:device,time:time,contacts:contacts,enabled:{ trigger in
                if let assignments = directional[trigger] { return assignments.hasAssignments }
                return trigger.isContinuous && live.action(for:trigger) != .disabled
            })
            let assignments = update.gesture.flatMap { directional[$0] }
            if let assignments { _ = stepper.process(device:device,time:time,update:update,assignments:assignments) }
            let motion = GestureHoldRecognizer.motionClaimsHold(update,directional:assignments != nil,direction:stepper.direction(device:device))
            if let count = hold.observe(device:device,time:time,now:now,contacts:contacts,motionClaimed:motion,actions:config.liveHoldActions) {
                fired.append(count); deadlines.append(now-(fullChordTime ?? now))
                router.reset(device:device); stepper.reset(device:device); force.cancel(device:device)
            }
        }
        XCTAssertEqual(fired,Array(repeating:4,count:9))
        for elapsed in deadlines { XCTAssertGreaterThanOrEqual(elapsed,0.5); XCTAssertLessThan(elapsed,0.55) }
    }
    func testContinuousMovementStillStartsImmediatelyAndStationaryHoldCanWinFirst() {
        for count in 2...4 {
            let trigger = PerHandGestureSettings.moveTrigger(count:count)!
            var settings = PerHandGestureSettings()
            settings.setHoldAction(.missionControl,count:count)
            XCTAssertEqual(settings.liveHoldActions[count],.missionControl)
            for moving in [false,true] {
                var router = TrackpadGestureRouter(), hold = GestureHoldRecognizer()
                var fired = [Int]()
                for i in 0...6 {
                    let time = 1+Double(i)*0.1
                    let contacts = touches(count,dx:moving && i > 0 ? 0.01 : 0)
                    if hold.claimed(device:1) { continue } // runtime gives Hold the remainder of this cycle
                    let update = router.recognize(device:1,time:time,contacts:contacts,enabled:{$0 == trigger})
                    if moving && i == 1 { XCTAssertEqual(update.gesture,trigger); XCTAssertEqual(update.phase,.began) }
                    if let result = hold.observe(device:1,time:time,now:time,contacts:contacts,
                        motionClaimed:GestureHoldRecognizer.motionClaimsHold(update,directional:false,direction:nil),actions:settings.liveHoldActions) {
                        fired.append(result)
                    }
                }
                XCTAssertEqual(fired,moving ? [] : [count])
            }
        }
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

extension GestureHoldTests {
    func testCustomShortcutsPreserveOldActionEncodingAndPortableAssignments() throws {
        for action in GestureAction.allCases {
            XCTAssertEqual(try JSONDecoder().decode(String.self,from:JSONEncoder().encode(action)),action.rawValue)
            XCTAssertEqual(try JSONDecoder().decode(GestureAction.self,from:JSONEncoder().encode(action)),action)
        }
        var settings = HandGestureSettings()
        let stroke = GestureAction.shortcut(.init(label:"Cmd+S"))
        let held = GestureAction.shortcut(.init(label:"Shift",holdUntilRelease:true))
        for trigger in GestureTrigger.allCases where trigger != .fourCornersTap {
            XCTAssertTrue(settings.setAction(stroke,for:trigger,in:.both),trigger.rawValue)
            XCTAssertEqual(settings.action(trigger,in:.both),stroke)
            XCTAssertFalse(settings.setAction(held,for:trigger,in:.left),trigger.rawValue)
        }
        settings.editMovement(.twoFingerMove,mode:.directional,direction:.up,action:stroke,in:.right)
        XCTAssertEqual(settings.directionalAction(.up,for:.twoFingerMove,in:.right),stroke)
        for count in 2...7 { settings.setHoldAction(held,count:count,in:.both); XCTAssertEqual(settings.holdAction(count:count,in:.both),held) }
        var coordinated = settings.twoHand
        coordinated.setAction(held,for:.init(chord:.threeFingers,phase:.hold))
        settings.coordinated = coordinated
        XCTAssertEqual(settings.twoHand.action(.init(chord:.threeFingers,phase:.hold)),held)
        coordinated.setAction(held,for:.init(chord:.threeFingers,phase:.tap))
        settings.coordinated = coordinated
        XCTAssertEqual(settings.twoHand.action(.init(chord:.threeFingers,phase:.tap)),.disabled)
        var profile = AppKeymapProfile.defaultProfile(); profile.handGestureSettings = settings
        let decoded = try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile())
        XCTAssertEqual(decoded.handGestureSettings,settings)
        XCTAssertNil(GestureAction(rawValue:"shortcut:{\"label\":\"UNSUPPORTED\",\"holdUntilRelease\":false}"))
        let app = try XCTUnwrap(KeyActionCatalog.appLaunchAction(fileName:"/Applications/Calculator.app"))
        XCTAssertNil(GestureAction(rawValue:GestureAction.shortcut(.init(label:app.label,holdUntilRelease:true)).rawValue))
    }

    func testHeldShortcutOwnersShareKeysAcrossPadsAndKeyboardReleaseOrders() throws {
        let shift = try XCTUnwrap(KeyActionCatalog.action(for:"Shift"))
        for keyboardFirst in [true,false] {
            for firstReleased in [0,1,2] {
                var keys = GestureShortcutKeyOwnership()
                var downs = 0, ups = 0
                if keyboardFirst { downs += keys.keyboardEdge(code:shift.keyCode,flags:.maskShift,down:true) == nil ? 0 : 1 }
                downs += keys.begin(.pad(1),action:shift).filter(\.down).count
                downs += keys.begin(.pad(2),action:shift).filter(\.down).count
                if !keyboardFirst { _ = keys.keyboardEdge(code:shift.keyCode,flags:.maskShift,down:true) }
                let order = [firstReleased] + [0,1,2].filter { $0 != firstReleased }
                for (index,owner) in order.enumerated() {
                    let edges = owner == 0 ? keys.keyboardEdge(code:shift.keyCode,flags:[],down:false).map { [$0] } ?? []
                        : keys.end(.pad(UInt64(owner)))
                    ups += edges.filter { !$0.down }.count
                    if index < 2 { XCTAssertTrue(edges.isEmpty) }
                }
                XCTAssertEqual(downs,1); XCTAssertEqual(ups,1); XCTAssertTrue(keys.flags.isEmpty)
            }
        }
    }

    func testHeldShortcutKeepsOtherPadFlagsAndBalancedChordEdges() throws {
        let hyper = try XCTUnwrap(KeyActionCatalog.action(for:"Hyper"))
        let shift = try XCTUnwrap(KeyActionCatalog.action(for:"Shift"))
        var keys = GestureShortcutKeyOwnership()
        XCTAssertEqual(keys.begin(.pad(1),action:hyper).count,4)
        XCTAssertTrue(keys.begin(.pad(2),action:shift).isEmpty)
        let key = try XCTUnwrap(keys.keyboardEdge(code:0,flags:[],down:true))
        XCTAssertTrue(key.flags.contains([.maskShift,.maskControl,.maskAlternate,.maskCommand]))
        let released = keys.end(.pad(1))
        XCTAssertEqual(released.count,3)
        XCTAssertTrue(released.allSatisfy { $0.flags.contains(.maskShift) && !$0.down })
        XCTAssertEqual(keys.end(.pad(2)).count,1)
        XCTAssertTrue(keys.end(.pad(2)).isEmpty)
        let cmdS = try XCTUnwrap(KeyActionCatalog.action(for:"Cmd+S"))
        let down = keys.begin(.coordinated,action:cmdS)
        XCTAssertEqual(down.count,2)
        XCTAssertEqual(keys.end(.coordinated).map(\.code),down.map(\.code).reversed())
        for (label,code) in [("Left Shift",kVK_Shift),("Right Shift",kVK_RightShift),("AltGr",kVK_RightOption),("Right Cmd",kVK_RightCommand)] {
            let action = try XCTUnwrap(KeyActionCatalog.action(for:label))
            XCTAssertEqual(GestureShortcutKeyOwnership.keys(for:action),[CGKeyCode(code)],label)
        }
    }
}


extension GestureHoldTests {
    func testShortcutDispatchRecordsBalancedKeysAndAppTargetsWithoutLiveInput() throws {
        let output = ProductionReplaySession.Output()
        let service = DispatchService(recordingWith:ReplayTouchEngineScheduler(startTime:1)) { output.events.append($0) }
        let held = GestureShortcutAssignment(label:"Shift",holdUntilRelease:true)
        service.postGestureShortcut(held,owner:.pad(1))
        service.postGestureShortcut(held,owner:.pad(2))
        service.postKeyStroke(code:0,flags:[])
        service.releaseGestureShortcut(.pad(1))
        XCTAssertEqual(output.events.count,2)
        service.postKeyStroke(code:0,flags:[])
        service.releaseGestureShortcut(.pad(2))
        XCTAssertEqual(output.events.count,4)
        for index in [1,2] {
            guard case let .keyStroke(_,flags,_) = output.events[index].kind else { return XCTFail("Expected recorded key stroke") }
            XCTAssertTrue(flags.contains(.maskShift))
        }
        guard case let .key(_,flags,down,_) = output.events.last?.kind else { return XCTFail("Expected key release") }
        XCTAssertFalse(down); XCTAssertTrue(flags.isEmpty)
        let app = try XCTUnwrap(KeyActionCatalog.appLaunchAction(fileName:"/Applications/Calculator.app"))
        service.postGestureShortcut(.init(label:app.label),owner:.pad(1))
        guard case .appLaunch(app.label) = output.events.last?.kind else { return XCTFail("Expected recording-only app launch") }
    }
}


extension GestureHoldTests {
    func testHeldShortcutInputAcceptsLatchChangesButRejectsBrokenDelivery() {
        XCTAssertTrue(HeldGestureShortcutInput.continues(time:1.1,previous:1,contacts:touches(1,idOffset:20)))
        XCTAssertTrue(HeldGestureShortcutInput.continues(time:1.1,previous:1,contacts:[OMSRawTouch]()))
        XCTAssertFalse(HeldGestureShortcutInput.continues(time:1,previous:1,contacts:touches(2)))
        XCTAssertFalse(HeldGestureShortcutInput.continues(time:1.3,previous:1,contacts:touches(2)))
        XCTAssertFalse(HeldGestureShortcutInput.continues(time:.nan,previous:1,contacts:touches(2)))
        XCTAssertFalse(HeldGestureShortcutInput.continues(time:1.1,previous:1,contacts:touches(1)+touches(1)))
        XCTAssertFalse(HeldGestureShortcutInput.continues(time:1.1,previous:1,contacts:touches(2,dx:.nan)))
    }
}


extension GestureHoldTests {
    func testPerGestureHoldThresholdsDriveFramesAndTimerWithIndependentPads() {
        for count in 2...5 {
            for useTimer in [false,true] {
                var engine = GestureHoldRecognizer()
                let thresholds = [count:0.8]
                for i in 0...7 {
                    let time = Double(i)*0.1
                    XCTAssertNil(engine.observe(device:1,time:time,now:time,contacts:touches(count),motionClaimed:false,actions:actions,thresholds:thresholds))
                    let other = engine.observe(device:2,time:time,now:time,contacts:touches(count),motionClaimed:false,actions:actions)
                    XCTAssertEqual(other,i == 5 ? count : nil)
                }
                if useTimer {
                    XCTAssertNil(engine.advance(device:1,now:0.79,actions:actions,thresholds:thresholds))
                    XCTAssertEqual(engine.advance(device:1,now:0.801,actions:actions,thresholds:thresholds),count)
                } else {
                    XCTAssertEqual(engine.observe(device:1,time:0.801,now:0.801,contacts:touches(count),motionClaimed:false,actions:actions,thresholds:thresholds),count)
                }
                XCTAssertNil(engine.advance(device:1,now:0.81,actions:actions,thresholds:thresholds))
                XCTAssertTrue(engine.claimed(device:1))
            }
        }
    }
    func testHoldThresholdDefaultsMirrorValidationAndPortableRoundTrip() throws {
        var settings = HandGestureSettings()
        for key in 2...7 { XCTAssertEqual(settings.left.holdThreshold(count:key),0.5) }
        for chord in TwoHandChord.allCases { XCTAssertEqual(settings.twoHand.holdThreshold(for:chord),0.5) }
        settings.setHoldThreshold(0.25,count:2,in:.left)
        XCTAssertNil(settings.holdThreshold(count:2,in:.both))
        XCTAssertEqual(settings.right.holdThreshold(count:2),0.5)
        for key in 2...7 { settings.setHoldThreshold(Double(key)/4,count:key,in:.both) }
        var both = settings.twoHand
        for (i,chord) in TwoHandChord.allCases.enumerated() { both.setHoldThreshold(Double(i+1)/4,for:chord) }
        settings.coordinated = both
        XCTAssertEqual(settings.left.singlePadCorners.holdThreshold(for:.fourCorners),1.75)
        var profile = AppKeymapProfile.defaultProfile(); profile.handGestureSettings = settings
        let imported = try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile())
        XCTAssertEqual(imported.handGestureSettings,settings)
        XCTAssertEqual(GestureHoldTiming.validated(.nan),0.5)
        XCTAssertEqual(GestureHoldTiming.validated(.infinity),0.5)
        XCTAssertEqual(GestureHoldTiming.validated(-1),0.1)
        XCTAssertEqual(GestureHoldTiming.validated(10),5)
        XCTAssertEqual(GestureHoldTiming.validated(0.754),0.75)
        XCTAssertNil(GestureHoldThresholdField.committedValue(""))
        XCTAssertNil(GestureHoldThresholdField.committedValue("NaN"))
        XCTAssertEqual(GestureHoldThresholdField.committedValue("750"),0.75)
        XCTAssertEqual(GestureHoldThresholdField.committedValue("500"),0.5)
        XCTAssertEqual(GestureHoldThresholdField.committedValue("0"),0.1)
        XCTAssertEqual(GestureHoldThresholdField.committedValue("9999"),5)
        XCTAssertEqual(GestureHoldTiming.milliseconds(0.5),500)
        XCTAssertEqual(GestureHoldTiming.milliseconds(0.75),750)
        XCTAssertEqual(GestureHoldTiming.milliseconds(1.25),1250)
    }
}
