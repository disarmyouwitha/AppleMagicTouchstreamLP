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
        XCTAssertEqual(config().repeatIntervalMS(.up),100)
        XCTAssertEqual(config(repeat:false).repeatIntervalMS(.up),0)
        XCTAssertEqual(config(repeat:true).repeatIntervalMS(.up),100)
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
        XCTAssertEqual(legacy.repeatIntervalMS(.up),100)
        XCTAssertEqual(legacy.repeatIntervalMS(.down),0)
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
        XCTAssertNil(stepper.process(device:1,time:3,update:update(.init(x:4,y:0),.began,gesture:.twoFingerMove),assignments:assignments))
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
