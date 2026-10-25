import CoreGraphics
import Foundation
import OpenMultitouchSupport
import XCTest
@testable import GlassToKeyRuntime

final class DirectionalMovementTests: XCTestCase {
    private func config(repeat enabled:Bool? = nil) -> GestureDirectionalAssignments {
        var value = GestureDirectionalAssignments(mode:.directional,actions:[
            "up":.volumeUpSmall,"down":.volumeDownSmall,"left":.brightnessDownSmall,"right":.brightnessUpSmall])
        if let enabled { value.repeatOverrides = Dictionary(uniqueKeysWithValues:GestureMovementDirection.allCases.map { ($0.rawValue,enabled) }) }
        return value
    }
    private func update(_ delta:CGPoint?,_ phase:GestureSessionPhase = .changed,
                        gesture:GestureTrigger = .threeFingerMove) -> GestureSessionUpdate<GestureTrigger> {
        GestureSessionUpdate(gesture:gesture,phase:phase,millimetres:delta,cancellation:nil)
    }
    func testAllDirectionsRequireTravelAndRejectDiagonalAmbiguity() {
        for (delta,direction) in [(CGPoint(x:0,y:-0.4),GestureMovementDirection.up),(.init(x:0,y:0.4),.down),(.init(x:-0.4,y:0),.left),(.init(x:0.4,y:0),.right)] {
            var stepper = GestureDirectionalStepper()
            XCTAssertNil(stepper.process(device:1,time:1,update:update(delta,.began),assignments:config()))
            XCTAssertEqual(stepper.process(device:1,time:1.01,update:update(delta),assignments:config()),direction)
        }
        var stepper = GestureDirectionalStepper()
        XCTAssertNil(stepper.process(device:1,time:1,update:update(.init(x:2,y:2),.began),assignments:config()))
        XCTAssertNil(stepper.process(device:1,time:1.01,update:update(.zero),assignments:config()))
        XCTAssertEqual(stepper.process(device:1,time:1.02,update:update(.init(x:2,y:0)),assignments:config()),.right)
    }
    func testHeldRepeatUsesTimeWhileStationaryAndNeverCatchesUp() {
        var stepper = GestureDirectionalStepper(), repeater = GestureDirectionalRepeater()
        XCTAssertEqual(stepper.process(device:1,time:1000,update:update(.init(x:0,y:-0.8),.began),assignments:config()),.up)
        // Native timestamps and host timer timestamps intentionally have different epochs.
        repeater.refresh(device:1,direction:stepper.direction(device:1),intervalMS:100,now:1)
        XCTAssertNil(repeater.tick(device:1,now:1.09))
        XCTAssertNil(stepper.process(device:1,time:1000.05,update:update(.zero),assignments:config()))
        repeater.refresh(device:1,direction:stepper.direction(device:1),intervalMS:100,now:1.05)
        XCTAssertEqual(repeater.tick(device:1,now:1.101),.up)
        XCTAssertNil(repeater.tick(device:1,now:1.102))
        repeater.refresh(device:1,direction:.up,intervalMS:100,now:1.19)
        XCTAssertEqual(repeater.tick(device:1,now:1.30),.up)
        XCTAssertNil(repeater.tick(device:1,now:1.301)) // No overdue burst.
        XCTAssertNil(repeater.tick(device:1,now:1.5)) // Lost input cancels repeat.
        XCTAssertNil(repeater.tick(device:1,now:1.6))
    }
    func testTimedRepeatTurnsReleaseAndIndependentDevices() {
        var repeater = GestureDirectionalRepeater()
        repeater.refresh(device:1,direction:.up,intervalMS:100,now:1)
        repeater.refresh(device:2,direction:.left,intervalMS:150,now:1)
        repeater.refresh(device:1,direction:.down,intervalMS:50,now:1.08)
        XCTAssertNil(repeater.tick(device:1,now:1.11))
        XCTAssertEqual(repeater.tick(device:1,now:1.14),.down)
        XCTAssertEqual(repeater.tick(device:2,now:1.16),.left)
        repeater.refresh(device:1,direction:nil,intervalMS:50,now:1.15)
        XCTAssertNil(repeater.tick(device:1,now:1.2))
        repeater.refresh(device:2,direction:.left,intervalMS:0,now:1.17)
        XCTAssertNil(repeater.tick(device:2,now:1.32))
        repeater.refresh(device:1,direction:.right,intervalMS:100,now:2)
        repeater.reset(device:1)
        XCTAssertNil(repeater.tick(device:1,now:2.1))
        repeater.refresh(device:1,direction:.right,intervalMS:100,now:3)
        repeater.reset()
        XCTAssertNil(repeater.tick(device:1,now:3.1))
    }
    func testLongIntervalKeepsItsDeadlineAcrossStationaryFrames() {
        var repeater = GestureDirectionalRepeater()
        repeater.refresh(device:1,direction:.right,intervalMS:5000,now:1)
        for i in 1...49 {
            let now = 1+Double(i)*0.1
            repeater.refresh(device:1,direction:.right,intervalMS:5000,now:now)
            XCTAssertNil(repeater.tick(device:1,now:now))
        }
        repeater.refresh(device:1,direction:.right,intervalMS:5000,now:6)
        XCTAssertEqual(repeater.tick(device:1,now:6.001),.right)
        repeater.refresh(device:1,direction:.right,intervalMS:Double.nan,now:6.01)
        XCTAssertNil(repeater.tick(device:1,now:6.1))
    }
    func testIntervalBoundsMigrationAndMirrorPersistence() throws {
        XCTAssertEqual(config().repeatIntervalMS(.up),80)
        XCTAssertEqual(config(repeat:false).repeatIntervalMS(.up),0)
        XCTAssertEqual(config(repeat:true).repeatIntervalMS(.up),80)
        for (input,expected) in [(Double.nan,0.0),(.infinity,0),(-1,0),(0,0),(1,20),(250.4,250),(9000,5000)] {
            XCTAssertEqual(GestureDirectionalAssignments.boundedIntervalMS(input),expected)
        }
        var settings = HandGestureSettings()
        settings.setDirectionalRepeatInterval(250,direction:.up,for:.threeFingerMove,in:.both)
        XCTAssertEqual(settings.directionalRepeatInterval(.up,for:.threeFingerMove,in:.both),250)
        settings.setDirectionalRepeatInterval(0,direction:.up,for:.threeFingerMove,in:.left)
        XCTAssertNil(settings.directionalRepeatInterval(.up,for:.threeFingerMove,in:.both))
        var profile = AppKeymapProfile.defaultProfile(); profile.handGestureSettings = settings
        XCTAssertEqual(try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile()).handGestureSettings,settings)
        let legacy = try JSONDecoder().decode(GestureDirectionalAssignments.self,from:Data(#"{"mode":"directional","actions":{},"repeatOverrides":{"up":true,"down":false}}"#.utf8))
        XCTAssertEqual(legacy.repeatIntervalMS(.up),80)
        XCTAssertEqual(legacy.repeatIntervalMS(.down),0)
    }
    func testLoopTogglePreservesIntervalAndUsesTwentyWhenUnset() throws {
        var settings = HandGestureSettings()
        let trigger = GestureTrigger.threeFingerMove
        settings.editMovement(trigger,mode:.directional,direction:.up,action:.missionControl,in:.both)
        XCTAssertEqual(settings.directionalRepeats(.up,for:trigger,in:.both),false)
        settings.setDirectionalRepeat(true,direction:.up,for:trigger,in:.both)
        XCTAssertEqual(settings.directionalRepeatInterval(.up,for:trigger,in:.both),20)
        settings.setDirectionalRepeatInterval(240,direction:.up,for:trigger,in:.both)
        settings.setDirectionalRepeat(false,direction:.up,for:trigger,in:.left)
        XCTAssertEqual(settings.directionalRepeatInterval(.up,for:trigger,in:.left),0)
        XCTAssertEqual(settings.directionalConfiguredRepeatInterval(.up,for:trigger,in:.left),240)
        XCTAssertNil(settings.directionalRepeats(.up,for:trigger,in:.both))
        let decoded = try JSONDecoder().decode(HandGestureSettings.self,from:JSONEncoder().encode(settings))
        XCTAssertEqual(decoded,settings)
        settings.setDirectionalRepeat(true,direction:.up,for:trigger,in:.left)
        XCTAssertEqual(settings.directionalRepeatInterval(.up,for:trigger,in:.both),240)
        settings.editMovement(trigger,mode:.directional,direction:.down,action:.volumeDownSmall,in:.both)
        settings.setDirectionalRepeat(false,direction:.down,for:trigger,in:.both)
        settings.setDirectionalRepeat(true,direction:.down,for:trigger,in:.both)
        XCTAssertEqual(settings.directionalRepeatInterval(.down,for:trigger,in:.both),80)
        settings.setDirectionalRepeatInterval(0,direction:.right,for:trigger,in:.both)
        settings.setDirectionalRepeat(true,direction:.right,for:trigger,in:.both)
        XCTAssertEqual(settings.directionalRepeatInterval(.right,for:trigger,in:.both),20)
        var profile = AppKeymapProfile.defaultProfile(); profile.handGestureSettings = decoded
        XCTAssertEqual(try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile()).handGestureSettings,decoded)
    }
    func testRepeatOffAndDeliberateReversalOrTurn() {
        var stepper = GestureDirectionalStepper()
        let assignments = config(repeat:false)
        XCTAssertEqual(stepper.process(device:1,time:1,update:update(.init(x:0,y:-2),.began),assignments:assignments),.up)
        XCTAssertNil(stepper.process(device:1,time:1.10,update:update(.init(x:0,y:-10)),assignments:assignments))
        XCTAssertNil(stepper.process(device:1,time:1.11,update:update(.init(x:0,y:0.3)),assignments:assignments))
        XCTAssertNil(stepper.process(device:1,time:1.12,update:update(.init(x:0,y:-0.2)),assignments:assignments))
        XCTAssertEqual(stepper.process(device:1,time:1.20,update:update(.init(x:0,y:1.6)),assignments:assignments),.down)
        XCTAssertNil(stepper.process(device:1,time:1.21,update:update(.init(x:0,y:5)),assignments:assignments))
        XCTAssertEqual(stepper.process(device:1,time:1.30,update:update(.init(x:1.6,y:0)),assignments:assignments),.right)
    }
    func testResetReleaseDiscontinuityAndOtherGestureCannotRetainProgress() {
        var stepper = GestureDirectionalStepper()
        let assignments = config()
        XCTAssertEqual(stepper.process(device:1,time:1,update:update(.init(x:2,y:0),.began),assignments:assignments),.right)
        XCTAssertNil(stepper.process(device:1,time:1.30,update:update(.init(x:4,y:0)),assignments:assignments))
        XCTAssertNil(stepper.process(device:1,time:1.31,update:update(.init(x:4,y:0)),assignments:assignments))
        XCTAssertEqual(stepper.process(device:1,time:2,update:update(.init(x:2,y:0),.began),assignments:assignments),.right)
        XCTAssertNil(stepper.process(device:1,time:2.01,update:update(nil,.ended),assignments:assignments))
        XCTAssertNil(stepper.process(device:1,time:2.02,update:update(.init(x:4,y:0)),assignments:assignments))
        XCTAssertNil(stepper.process(device:1,time:3,update:update(.init(x:4,y:0),.began,gesture:.oneFingerForce),assignments:assignments))
        XCTAssertNil(stepper.process(device:1,time:4,update:update(.init(x:Double.nan,y:0),.began),assignments:assignments))
        _ = stepper.process(device:1,time:5,update:update(.init(x:2,y:0),.began),assignments:assignments)
        stepper.reset(device:1)
        XCTAssertNil(stepper.process(device:1,time:5.01,update:update(.init(x:4,y:0)),assignments:assignments))
        XCTAssertNil(stepper.process(device:1,time:6,update:update(.init(x:4,y:0),.began),assignments:.init()))
    }
    func testIndependentDevicesAndPerDirectionRepeatDefaultsPersist() throws {
        var stepper = GestureDirectionalStepper()
        XCTAssertEqual(stepper.process(device:1,time:1,update:update(.init(x:2,y:0),.began),assignments:config()),.right)
        XCTAssertEqual(stepper.process(device:2,time:1,update:update(.init(x:0,y:-2),.began),assignments:config()),.up)
        stepper.reset(device:1)
        XCTAssertNil(stepper.process(device:2,time:1.1,update:update(.init(x:0,y:-3.1)),assignments:config()))
        var settings = HandGestureSettings()
        settings.editMovement(.threeFingerMove,mode:.directional,direction:.up,action:.volumeUpSmall,in:.both)
        XCTAssertEqual(settings.directionalRepeats(.up,for:.threeFingerMove,in:.both),true)
        XCTAssertEqual(settings.directionalRepeats(.left,for:.threeFingerMove,in:.both),false)
        settings.setDirectionalRepeat(false,direction:.up,for:.threeFingerMove,in:.left)
        XCTAssertNil(settings.directionalRepeats(.up,for:.threeFingerMove,in:.both))
        settings.editMovement(.threeFingerMove,mode:.directional,direction:.up,action:.brightnessUpSmall,in:.left)
        XCTAssertEqual(settings.directionalRepeats(.up,for:.threeFingerMove,in:.left),false)
        settings.editMovement(.threeFingerMove,mode:.directional,direction:.right,action:.missionControl,in:.both)
        XCTAssertEqual(settings.directionalRepeats(.right,for:.threeFingerMove,in:.both),false)
        settings.setDirectionalRepeat(true,direction:.right,for:.threeFingerMove,in:.both)
        var profile = AppKeymapProfile.defaultProfile(); profile.handGestureSettings = settings
        XCTAssertEqual(try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile()).handGestureSettings,settings)
        let original = HandGestureSettings()
        XCTAssertEqual(settings.routed(to:.init(left:1,right:2))[1]?.bindings.twoFingerMove,original.left.bindings.twoFingerMove)
    }
    func testAllFingerCountDirectionalConfigurationsAreIndependent() {
        var settings = PerHandGestureSettings()
        settings.editMovement(.twoFingerMove,mode:.directional,direction:.up,action:.volumeUpSmall)
        settings.editMovement(.threeFingerMove,mode:.directional,direction:.up,action:.brightnessUpSmall)
        settings.editMovement(.fourFingerMove,mode:.directional,direction:.up,action:.missionControl)
        XCTAssertEqual(Set(settings.liveDirectionalBindings.keys),[.twoFingerMove,.threeFingerMove,.fourFingerMove])
        XCTAssertEqual(settings.liveDirectionalBindings[.twoFingerMove]?.action(.up),.volumeUpSmall)
        XCTAssertEqual(settings.liveDirectionalBindings[.threeFingerMove]?.action(.up),.brightnessUpSmall)
        XCTAssertEqual(settings.liveDirectionalBindings[.fourFingerMove]?.action(.up),.missionControl)
        settings.editMovement(.twoFingerMove,mode:.continuous)
        XCTAssertNil(settings.liveDirectionalBindings[.twoFingerMove])
        XCTAssertEqual(settings.outputSettings.bindings.twoFingerMove,.pointer)
    }
    func testTwoFingerDirectionalsUseSharedOwnershipAndAllUpLatch() {
        var router = TrackpadGestureRouter(), stepper = GestureDirectionalStepper()
        let assignments = config()
        let enabled:(GestureTrigger)->Bool = { $0 == .twoFingerMove }
        _ = router.recognize(device:1,time:1,contacts:touches(2),enabled:enabled)
        let began = router.recognize(device:1,time:1.01,contacts:touches(2,dy:0.01),enabled:enabled)
        XCTAssertEqual(began.gesture,.twoFingerMove)
        XCTAssertEqual(stepper.process(device:1,time:1.01,update:began,assignments:assignments),.up)
        XCTAssertEqual(stepper.trigger(device:1),.twoFingerMove)
        let changed = router.recognize(device:1,time:1.02,contacts:touches(1,dy:0.012),enabled:enabled)
        XCTAssertEqual(changed.gesture,.twoFingerMove)
        XCTAssertNil(stepper.process(device:1,time:1.02,update:changed,assignments:assignments))
        let ended = router.recognize(device:1,time:1.03,contacts:touches(0),enabled:enabled)
        XCTAssertNil(stepper.process(device:1,time:1.03,update:ended,assignments:assignments))
        XCTAssertNil(stepper.trigger(device:1))
    }
    func testEveryFingerCountUsesTheSameDirectionTurnAndRepeatPolicy() {
        for trigger in GestureDirectionalAssignments.liveTriggers {
            var stepper = GestureDirectionalStepper(), repeater = GestureDirectionalRepeater()
            let config = config()
            XCTAssertEqual(stepper.process(device:1,time:1,update:update(.init(x:0,y:-1),.began,gesture:trigger),assignments:config),.up)
            repeater.refresh(device:1,direction:.up,intervalMS:80,now:10)
            XCTAssertEqual(repeater.tick(device:1,now:10.081),.up)
            XCTAssertEqual(stepper.process(device:1,time:1.1,update:update(.init(x:1,y:0),gesture:trigger),assignments:config),.right)
            XCTAssertEqual(stepper.trigger(device:1),trigger)
            XCTAssertNil(stepper.process(device:1,time:1.11,update:update(nil,.ended,gesture:trigger),assignments:config))
            repeater.reset(device:1)
            XCTAssertNil(repeater.tick(device:1,now:10.2))
        }
    }
    func testFourFingerDirectionsLatchWithoutContinuousScrollAndRestoreScrollOnSwitch() throws {
        var settings = HandGestureSettings()
        settings.editMovement(.fourFingerMove,mode:.directional,direction:.up,action:.volumeUpSmall,in:.left)
        settings.setDirectionalRepeatInterval(80,direction:.up,for:.fourFingerMove,in:.left)
        let routed = settings.routed(to:.init(left:1,right:2))
        let left = try XCTUnwrap(routed[1])
        XCTAssertEqual(left.bindings.fourFingerMove,.disabled)
        XCTAssertEqual(routed[2]?.bindings.fourFingerMove,.scroll)
        let assignments = try XCTUnwrap(left.liveDirectionalBindings[.fourFingerMove])
        var router = TrackpadGestureRouter(), stepper = GestureDirectionalStepper(), repeatEngine = GestureDirectionalRepeater()
        let enabled:(GestureTrigger)->Bool = { left.liveDirectionalBindings[$0] != nil }
        _ = router.recognize(device:1,time:1,contacts:touches(4),enabled:enabled)
        let began = router.recognize(device:1,time:1.01,contacts:touches(4,dy:0.01),enabled:enabled)
        XCTAssertEqual(began.gesture,.fourFingerMove)
        XCTAssertEqual(stepper.process(device:1,time:1.01,update:began,assignments:assignments),.up)
        repeatEngine.refresh(device:1,direction:.up,intervalMS:assignments.repeatIntervalMS(.up),now:20)
        XCTAssertEqual(repeatEngine.tick(device:1,now:20.081),.up)
        for (time,count,dy) in [(1.02,2,Float(0.012)),(1.03,1,Float(0.014))] {
            let changed = router.recognize(device:1,time:time,contacts:touches(count,dy:dy),enabled:enabled)
            XCTAssertEqual(changed.gesture,.fourFingerMove)
            XCTAssertNil(stepper.process(device:1,time:time,update:changed,assignments:assignments))
            XCTAssertEqual(stepper.trigger(device:1),.fourFingerMove)
        }
        let ended = router.recognize(device:1,time:1.04,contacts:touches(0),enabled:enabled)
        XCTAssertNil(stepper.process(device:1,time:1.04,update:ended,assignments:assignments))
        repeatEngine.reset(device:1)
        XCTAssertNil(repeatEngine.tick(device:1,now:20.2))
        settings.editMovement(.fourFingerMove,mode:.continuous,in:.left)
        XCTAssertEqual(settings.routed(to:.init(left:1,right:2))[1]?.bindings.fourFingerMove,.scroll)
        XCTAssertNil(settings.left.liveDirectionalBindings[.fourFingerMove])
        XCTAssertEqual(settings.left.movement(.fourFingerMove).action(.up),.volumeUpSmall)
        var profile = AppKeymapProfile.defaultProfile(); profile.handGestureSettings = settings
        XCTAssertEqual(try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile()).handGestureSettings,settings)
    }
    private func touches(_ count:Int,dy:Float = 0) -> [OMSRawTouch] {
        (0..<count).map { i in OMSRawTouch(id:Int32(i+1),posX:0.3+Float(i)*0.11,posY:0.5+dy,
            total:1,pressure:40,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching) }
    }
    func testSharedRouterLatchSurvivesAddedLiftedFingersAndEndsNormally() {
        var router = TrackpadGestureRouter(), stepper = GestureDirectionalStepper()
        let assignments = config()
        let enabled: (GestureTrigger)->Bool = { $0 == .threeFingerMove || $0 == .twoFingerMove }
        _ = router.recognize(device:1,time:1,contacts:touches(3),enabled:enabled)
        let began = router.recognize(device:1,time:1.01,contacts:touches(3,dy:0.02),enabled:enabled)
        XCTAssertEqual(began.gesture,.threeFingerMove)
        XCTAssertEqual(stepper.process(device:1,time:1.01,update:began,assignments:assignments),.up)
        for (time,count,dy) in [(1.02,4,Float(0.025)),(1.03,1,Float(0.03))] {
            let changed = router.recognize(device:1,time:time,contacts:touches(count,dy:dy),enabled:enabled)
            XCTAssertEqual(changed.gesture,.threeFingerMove)
            XCTAssertNil(stepper.process(device:1,time:time,update:changed,assignments:assignments))
        }
        let repeated = router.recognize(device:1,time:1.11,contacts:touches(1,dy:0.08),enabled:enabled)
        XCTAssertNil(stepper.process(device:1,time:1.11,update:repeated,assignments:assignments))
        XCTAssertEqual(stepper.direction(device:1),.up)
        let ended = router.recognize(device:1,time:1.12,contacts:touches(0),enabled:enabled)
        XCTAssertEqual(ended.phase,.ended)
        XCTAssertNil(stepper.process(device:1,time:1.12,update:ended,assignments:assignments))
        _ = router.recognize(device:2,time:2,contacts:touches(2),enabled:enabled)
        XCTAssertEqual(router.recognize(device:2,time:2.01,contacts:touches(2,dy:0.02),enabled:enabled).gesture,.twoFingerMove)
    }
}
