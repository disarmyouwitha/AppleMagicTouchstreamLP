import AppKit
import SwiftUI
import OpenMultitouchSupport
import XCTest
@testable import GlassToKeyRuntime

final class ThumbDiagonalTests: XCTestCase {
    private func touch(_ id:Int32,x:Double,y:Double,finger:Int32,hand:Int32 = 1) -> OMSRawTouch {
        OMSRawTouch(id:id,posX:Float(x/160),posY:Float(1-y/114.9),total:1,pressure:40,
            majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching,
            telemetry:.init(fingerID:finger,handID:hand,velocityX:0,velocityY:0,absoluteX:0,absoluteY:0,
                absoluteVelocityX:0,absoluteVelocityY:0,sourceFrame:1,sourceTimestamp:1))
    }
    private func chord(_ delta:CGPoint = .zero,thumb:Bool = true,mirrored:Bool = false) -> [OMSRawTouch] {
        [(Int32(1),30.0,85.0,Int32(thumb ? 1 : 2)),(2,90,35,3),(3,110,35,4)].map { id,x,y,finger in
            touch(id,x:(mirrored ? 160-x : x)+delta.x,y:y+delta.y,finger:finger)
        }
    }
    private func config() -> GestureDirectionalAssignments {
        GestureDirectionalAssignments(mode:.directional,actions:["upLeft":.volumeUpSmall,"upRight":.volumeDownSmall,
            "downLeft":.brightnessDownSmall,"downRight":.brightnessUpSmall])
    }
    private let enabled:(GestureTrigger)->Bool = {
        $0 == .thumbTwoMove || $0 == .threeFingerMove || $0 == .threeFingerPinch || $0 == .threeFingerSpread
            || $0 == .threeFingerRotateLeft || $0 == .threeFingerRotateRight
    }

    func testEveryDiagonalAcquiresOnEitherHandAndCardinalsDoNot() throws {
        for mirrored in [false,true] {
            for direction in GestureMovementDirection.diagonals {
                var router = TrackpadGestureRouter(), stepper = GestureDirectionalStepper()
                XCTAssertNil(router.recognize(device:1,time:1,contacts:chord(mirrored:mirrored),enabled:enabled).gesture)
                let unit = direction.unitVector
                let delta = CGPoint(x:unit.x*0.9,y:unit.y*0.9)
                let update = router.recognize(device:1,time:1.01,contacts:chord(delta,mirrored:mirrored),enabled:enabled)
                XCTAssertEqual(update.gesture,.thumbTwoMove)
                XCTAssertEqual(update.phase,.began)
                XCTAssertEqual(stepper.process(device:1,time:1.01,update:update,assignments:config()),direction)
            }
        }
        for direction in GestureMovementDirection.cardinals {
            var router = TrackpadGestureRouter()
            _ = router.recognize(device:1,time:1,contacts:chord(),enabled:enabled)
            let unit = direction.unitVector
            let update = router.recognize(device:1,time:1.01,contacts:chord(.init(x:unit.x*3,y:unit.y*3)),enabled:enabled)
            XCTAssertNil(update.gesture)
        }
    }

    func testRequiresPositiveThumbSpreadGeometryAndCoherentTravel() {
        for mode in 0..<4 {
            var router = TrackpadGestureRouter()
            let initial = chord(thumb:mode != 0)
            _ = router.recognize(device:1,time:1,contacts:initial,enabled:{$0 == .thumbTwoMove})
            var moved = chord(.init(x:2,y:-2),thumb:mode != 0)
            if mode == 1 { moved[1] = initial[1]; moved[2] = initial[2] } // thumb wiggle
            if mode == 2 { moved[0] = touch(1,x:85,y:35,finger:1) } // close row, no spread thumb
            if mode == 3 { moved[1] = touch(2,x:92,y:33,finger:3,hand:2) } // mixed hands
            XCTAssertNil(router.recognize(device:1,time:1.01,contacts:moved,enabled:{$0 == .thumbTwoMove}).gesture)
        }
        var router = TrackpadGestureRouter()
        _ = router.recognize(device:1,time:1,contacts:chord(),enabled:enabled)
        XCTAssertNil(router.recognize(device:1,time:1.01,contacts:chord(.init(x:0.2,y:-0.2)),enabled:enabled).gesture)
    }

    func testSharedOwnerLatchesAcrossCountAndLabelChangesAndEndsOnce() {
        var router = TrackpadGestureRouter()
        _ = router.recognize(device:1,time:1,contacts:chord(),enabled:enabled)
        let translated = chord(.init(x:1,y:-1))
        XCTAssertEqual(router.recognize(device:1,time:1.01,contacts:translated,enabled:enabled).gesture,.thumbTwoMove)
        var extra = translated; extra.append(touch(4,x:120,y:45,finger:5))
        XCTAssertEqual(router.recognize(device:1,time:1.02,contacts:extra,enabled:enabled).gesture,.thumbTwoMove)
        let one = [touch(2,x:93,y:32,finger:0)]
        XCTAssertEqual(router.recognize(device:1,time:1.03,contacts:one,enabled:enabled).gesture,.thumbTwoMove)
        let ended = router.recognize(device:1,time:1.04,contacts:[OMSRawTouch](),enabled:enabled)
        XCTAssertEqual(ended.gesture,.thumbTwoMove); XCTAssertEqual(ended.phase,.ended)
        XCTAssertNil(router.recognize(device:1,time:1.05,contacts:[OMSRawTouch](),enabled:enabled).gesture)
    }

    func testSharedRepeatsTurnsStaleInputDisableAndIndependentPads() {
        var stepper = GestureDirectionalStepper(), repeaters = GestureDirectionalRepeater()
        func update(_ delta:CGPoint,_ phase:GestureSessionPhase = .changed) -> GestureSessionUpdate<GestureTrigger> {
            .init(gesture:.thumbTwoMove,phase:phase,millimetres:delta,cancellation:nil)
        }
        XCTAssertEqual(stepper.process(device:1,time:1,update:update(.init(x:-1,y:-1),.began),assignments:config()),.upLeft)
        XCTAssertEqual(stepper.process(device:2,time:1,update:update(.init(x:1,y:1),.began),assignments:config()),.downRight)
        repeaters.refresh(device:1,direction:.upLeft,intervalMS:80,now:10)
        XCTAssertEqual(repeaters.tick(device:1,now:10.081),.upLeft)
        XCTAssertNil(stepper.process(device:1,time:1.05,update:update(.zero),assignments:config()))
        XCTAssertEqual(stepper.direction(device:1),.upLeft)
        XCTAssertEqual(stepper.process(device:1,time:1.1,update:update(.init(x:1,y:-1)),assignments:config()),.upRight)
        XCTAssertEqual(stepper.direction(device:2),.downRight)
        XCTAssertNil(stepper.process(device:1,time:2,update:update(.init(x:1,y:1)),assignments:config()))
        XCTAssertNil(stepper.direction(device:1))
        XCTAssertNil(repeaters.tick(device:1,now:10.5))
        var router = TrackpadGestureRouter()
        _ = router.recognize(device:1,time:1,contacts:chord(),enabled:enabled)
        _ = router.recognize(device:1,time:1.01,contacts:chord(.init(x:1,y:-1)),enabled:enabled)
        XCTAssertEqual(router.recognize(device:1,time:1.02,contacts:chord(.init(x:1,y:-1)),enabled:{_ in false}).phase,.cancelled)
    }

    func testDisabledDiagonalsDoNotClaimMovementAndTapStillCompletes() {
        var router = TrackpadGestureRouter()
        _ = router.recognize(device:1,time:1,contacts:chord(),enabled:{_ in false})
        XCTAssertNil(router.recognize(device:1,time:1.01,contacts:chord(.init(x:2,y:-2)),enabled:{_ in false}).gesture)
        var tap = ThreeFingerTapRecognizer()
        XCTAssertNil(tap.recognize(device:1,time:1,contacts:chord(),ordinaryEnabled:true,thumbEnabled:true))
        XCTAssertNil(tap.recognize(device:1,time:1.04,contacts:chord(),ordinaryEnabled:true,thumbEnabled:true))
        XCTAssertEqual(tap.recognize(device:1,time:1.06,contacts:[OMSRawTouch](),ordinaryEnabled:true,thumbEnabled:true),.thumbTwoTap)
    }

    func testPinchSpreadAndRotationWinTheirOwnShapeEvidence() {
        for clockwise in [false,true] {
            var router = TrackpadGestureRouter()
            _ = router.recognize(device:1,time:1,contacts:chord(),enabled:enabled)
            let angle = clockwise ? 0.1 : -0.1
            var rotated = chord()
            for (index,x) in [(1,90.0),(2,110.0)] {
                let dx = x-30, dy = 35.0-85
                rotated[index] = touch(Int32(index+1),x:30+dx*cos(angle)-dy*sin(angle),
                    y:85+dx*sin(angle)+dy*cos(angle),finger:index == 1 ? 3 : 4)
            }
            XCTAssertEqual(router.recognize(device:1,time:1.01,contacts:rotated,enabled:enabled).gesture,
                clockwise ? .threeFingerRotateRight : .threeFingerRotateLeft)
        }
        for spreading in [false,true] {
            var router = TrackpadGestureRouter()
            _ = router.recognize(device:1,time:1,contacts:chord(),enabled:enabled)
            let scale = spreading ? 1.06 : 0.94
            var scaled = chord()
            for (index,x) in [(1,90.0),(2,110.0)] {
                scaled[index] = touch(Int32(index+1),x:30+(x-30)*scale,y:85+(35-85)*scale,finger:index == 1 ? 3 : 4)
            }
            XCTAssertEqual(router.recognize(device:1,time:1.01,contacts:scaled,enabled:enabled).gesture,
                spreading ? .threeFingerSpread : .threeFingerPinch)
        }
    }

    func testDiagonalScrollProjectionRetainsFineTravelAndRejectsReverse() {
        for direction in GestureMovementDirection.diagonals {
            let unit = direction.unitVector
            XCTAssertEqual(DirectionalScrollEngine.travel(.init(x:unit.x*0.01,y:unit.y*0.01),direction:direction),0.01,accuracy:0.0000001)
            XCTAssertEqual(DirectionalScrollEngine.travel(.init(x:-unit.x*0.01,y:-unit.y*0.01),direction:direction),0)
        }
    }

    func testSettingsAreIndependentOffByDefaultAndPortableIncludingRepeat() throws {
        var settings = HandGestureSettings()
        XCTAssertNil(settings.left.liveDirectionalBindings[.thumbTwoMove])
        XCTAssertFalse(settings.setAction(.pointer,for:.thumbTwoMove,in:.left))
        for direction in GestureMovementDirection.diagonals {
            settings.editMovement(.thumbTwoMove,mode:.directional,direction:direction,action:.volumeUpSmall,in:.left)
            settings.setDirectionalRepeatInterval(120,direction:direction,for:.thumbTwoMove,in:.left)
            XCTAssertEqual(settings.directionalAction(direction,for:.thumbTwoMove,in:.right),.disabled)
            XCTAssertEqual(settings.directionalRepeatInterval(direction,for:.thumbTwoMove,in:.left),120)
        }
        settings.editMovement(.thumbTwoMove,mode:.directional,direction:.up,action:.missionControl,in:.left)
        XCTAssertEqual(settings.directionalAction(.up,for:.thumbTwoMove,in:.left),.disabled)
        var profile = AppKeymapProfile.defaultProfile(); profile.handGestureSettings = settings
        let restored = try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile())
        XCTAssertEqual(restored.handGestureSettings,settings)
        settings.editMovement(.thumbTwoMove,mode:.directional,direction:.upLeft,action:.showDesktop,in:.both)
        XCTAssertEqual(settings.directionalAction(.upLeft,for:.thumbTwoMove,in:.both),.showDesktop)
        for direction in GestureMovementDirection.diagonals {
            XCTAssertEqual(try JSONDecoder().decode(GestureMovementDirection.self,from:JSONEncoder().encode(direction)),direction)
        }
    }
}

@MainActor final class ThumbDiagonalWorkspaceTests:XCTestCase {
    func testDiagonalWorkspaceAndAnimationRenderWithoutInput() throws {
        let settings = HandGestureSettings()
        XCTAssertEqual(GesturePane.thumbTwo.triggers,[.thumbTwoTap,.thumbTwoMove,.threeFingerRotateLeft,.threeFingerRotateRight])
        // One render exercises the shared layout; pure tests cover all four
        // directions. Explicit screenshot runs still export every direction.
        let directions: [GestureMovementDirection] = ProcessInfo.processInfo.environment["AMT_WORKSPACE_PREVIEW_DIR"] == nil
            ? [.upLeft] : GestureMovementDirection.diagonals
        for direction in directions {
            let view = GestureAssignmentWorkspace(settings:settings,initialPane:.thumbTwo,initialDirection:direction,
                status:{_,_ in "Offline"},apply:{_,_,_ in XCTFail("Must not assign during render")},
                setSensitivity:{_,_,_ in XCTFail("Must not edit sensitivity during render")}).frame(width:1320,height:900)
            let host = NSHostingView(rootView:view)
            host.frame = NSRect(x:0,y:0,width:1320,height:900)
            let window = NSWindow(contentRect:host.frame,styleMask:[.borderless],backing:.buffered,defer:false)
            window.contentView = host; host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds))
            host.cacheDisplay(in:host.bounds,to:bitmap)
            if let directory = ProcessInfo.processInfo.environment["AMT_WORKSPACE_PREVIEW_DIR"] {
                let url = URL(fileURLWithPath:directory,isDirectory:true)
                try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
                try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:url.appendingPathComponent("thumb-diagonal-\(direction.rawValue).png"))
            }
            window.contentView = nil
        }
    }
}
