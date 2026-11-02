import CoreGraphics
import OpenMultitouchSupport
import XCTest
@testable import GlassToKeyRuntime

@MainActor final class LayoutContactPreviewTests:XCTestCase {
    private func session(steno:Bool = false) -> ProductionReplaySession {
        let run = ProductionReplaySession(startTime:1), size = CGSize(width:160,height:115)
        let layout = ContentViewModel.Layout(keyRects:[[CGRect(x:40,y:40,width:20,height:20)]],trackpadSize:size,isSteno:steno)
        run.engine.updateLayouts(leftLayout:layout,rightLayout:layout,leftLabels:[[steno ? StenoKey.a.label:"F"]],rightLabels:[[steno ? StenoKey.a.label:"F"]],trackpadSize:size,trackpadWidthMm:160)
        run.engine.updateActiveDevices(leftIndex:0,rightIndex:1,leftDeviceID:"42",rightDeviceID:"43")
        run.engine.updateKeyboardModeEnabled(true); run.engine.updateSnapRadiusPercent(0)
        run.engine.updateHapticStrength(1); run.engine.setListening(true)
        return run
    }
    private func frame(_ run:ProductionReplaySession,_ time:Double,down:Bool,side:Int = 0) {
        let touches:[OMSRawTouch] = down ? [.init(id:1,posX:Float(50)/160,posY:1-Float(50)/115,total:1,pressure:100,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)]:[]
        run.ingest(.init(sequence:UInt64(time*10000),timestamp:time,deviceNumericID:side == 0 ? 42:43,deviceIndex:side,contacts:[],rawTouches:touches))
    }
    func testPreviewSuppressesKeyboardStenoHapticsAndFreshInputResumes() {
        for steno in [false,true] {
            let run = session(steno:steno)
            run.engine.setKeymapEditingEnabled(true)
            run.output.events.removeAll()
            for side in 0...1 {
                frame(run,1+Double(side)*0.1,down:true,side:side)
                frame(run,1.05+Double(side)*0.1,down:false,side:side)
            }
            run.scheduler.advance(to:2)
            XCTAssertTrue(run.output.events.isEmpty,"Preview must never type or pulse")
            XCTAssertTrue(run.output.acceptedBindings.isEmpty)
            run.engine.setKeymapEditingEnabled(false)
            frame(run,2.1,down:true); frame(run,2.15,down:false)
            XCTAssertFalse(run.output.events.isEmpty,"Fresh input resumes after preview: steno=\(steno), events=\(run.output.events)")
        }
    }
    func testTurningPreviewOffWhileTouchHeldWaitsForAllUp() {
        for steno in [false,true] {
            let run = session(steno:steno)
            run.engine.setKeymapEditingEnabled(true)
            run.output.events.removeAll()
            frame(run,1,down:true)
            run.engine.setKeymapEditingEnabled(false)
            let afterCleanup = run.output.events.count
            frame(run,1.03,down:true); frame(run,1.06,down:false)
            XCTAssertEqual(run.output.events.count,afterCleanup,"Never turn preview contacts into typing")
            frame(run,1.2,down:true); frame(run,1.25,down:false)
            XCTAssertFalse(run.output.events.isEmpty)
        }
    }
    func testEnteringPreviewCancelsPendingTapRatherThanReplayingOnLift() {
        let run = session()
        frame(run,1,down:true)
        run.engine.setKeymapEditingEnabled(true)
        let afterCleanup = run.output.events.count
        frame(run,1.04,down:false)
        run.scheduler.advance(to:2)
        XCTAssertEqual(run.output.events.count,afterCleanup)
        run.engine.setKeymapEditingEnabled(false)
        frame(run,2.1,down:true); frame(run,2.15,down:false)
        XCTAssertGreaterThan(run.output.events.count,afterCleanup,"\(run.output.events)")
    }
}

final class LayoutContactPreviewGestureTests:XCTestCase {
    func testPreviewKeepsLowCountMouseActionsAndSuppressesAllHighCountFamilies() {
        var saved = PerHandGestureSettings()
        for trigger in GestureTrigger.allCases { saved.bindings[trigger] = .primaryClick }
        saved.bindings[.twoFingerMove] = .pointer
        saved.bindings[.threeFingerMove] = .primaryDrag
        for count in 2...7 { saved.setHoldAction(.primaryClick,count:count) }
        for trigger in GestureDirectionalAssignments.triggers {
            saved.editMovement(trigger,mode:.directional,direction:GestureDirectionalAssignments.directions(for:trigger).first,action:.primaryClick)
        }
        let original = saved, preview = saved.layoutContactPreview
        let high:[GestureTrigger] = [.fourFingerTap,.fiveFingerTap,.fourFingerMove,.fiveFingerMove,
            .fourFingerForce,.fiveFingerForce,.fourFingerPinch,.fiveFingerPinch,.fourFingerSpread,.fiveFingerSpread,
            .fourFingerRotateLeft,.fourFingerRotateRight,.fiveFingerRotateLeft,.fiveFingerRotateRight]
        for trigger in high {
            XCTAssertEqual(preview.bindings.action(for:trigger),.disabled,trigger.rawValue)
            XCTAssertNil(preview.liveDirectionalBindings[trigger])
        }
        for trigger in GestureTrigger.allCases where !high.contains(trigger) && trigger != .fourCornersTap {
            XCTAssertEqual(preview.bindings.action(for:trigger),original.bindings.action(for:trigger),trigger.rawValue)
        }
        for count in [4,5,7] { XCTAssertEqual(preview.holdAction(count:count),.disabled) }
        for count in [2,3,6] { XCTAssertEqual(preview.holdAction(count:count),original.holdAction(count:count)) }
        XCTAssertEqual(preview.liveDirectionalBindings[.twoFingerMove],original.liveDirectionalBindings[.twoFingerMove])
        XCTAssertEqual(preview.liveDirectionalBindings[.threeFingerMove],original.liveDirectionalBindings[.threeFingerMove])
        XCTAssertEqual(saved,original)
    }
    func testPreviewOnlyFiltersCoordinatedFourFingerChord() {
        var saved = TwoHandGestureSettings()
        for chord in TwoHandChord.allCases {
            for phase in chord.phases { saved.setAction(.primaryClick,for:.init(chord:chord,phase:phase)) }
        }
        let preview = saved.layoutContactPreview
        for chord in TwoHandChord.allCases {
            for phase in chord.phases {
                let trigger = TwoHandTrigger(chord:chord,phase:phase)
                XCTAssertEqual(preview.action(trigger),chord == .fourFingers ? .disabled:saved.action(trigger))
            }
        }
        XCTAssertTrue(saved.enabled(.fourFingers))
        XCTAssertFalse(preview.enabled(.fourFingers))
    }
}
