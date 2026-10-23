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
            XCTAssertEqual(began.gesture,.twoFingerPinch); XCTAssertEqual(began.phase,.began)
            XCTAssertEqual(try XCTUnwrap(began.magnification),1/30.0,accuracy:0.00001)
            let close = router.recognize(device:1,time:1.02,contacts:touches(30,center:center+1),enabled:{_ in true})
            XCTAssertEqual(close.gesture,.twoFingerPinch)
            XCTAssertLessThan(try XCTUnwrap(close.magnification),0)
            let end = router.recognize(device:1,time:1.03,contacts:[OMSRawTouch](),enabled:{_ in true})
            XCTAssertEqual(end.phase,.ended)
        }
        var router = TrackpadGestureRouter()
        _ = router.recognize(device:1,time:1,contacts:touches(),enabled:{_ in true})
        let move = router.recognize(device:1,time:1.01,contacts:touches(center:80.4),enabled:{_ in true})
        XCTAssertEqual(move.gesture,.twoFingerMove); XCTAssertEqual(move.phase,.began)
        let laterSpread = router.recognize(device:1,time:1.02,contacts:touches(34,center:81),enabled:{_ in true})
        XCTAssertEqual(laterSpread.gesture,.twoFingerMove); XCTAssertNil(laterSpread.magnification)
    }
    func testPinchOnlyReservationJitterIdentityChangesAndCountsAreSafe() {
        var gate = GestureKeyboardArbitration(), router = TrackpadGestureRouter()
        XCTAssertTrue(gate.process(device:1,activeCount:2) {$0 == .twoFingerPinch})
        XCTAssertTrue(gate.process(device:1,activeCount:1) {_ in false})
        XCTAssertTrue(gate.process(device:1,activeCount:0) {_ in false})
        _ = router.recognize(device:1,time:1,contacts:touches(),enabled:{_ in true})
        XCTAssertNil(router.recognize(device:1,time:1.01,contacts:touches(30.2),enabled:{_ in true}).gesture)
        XCTAssertEqual(router.recognize(device:1,time:1.02,contacts:touches(31),enabled:{_ in true}).gesture,.twoFingerPinch)
        let lift = router.recognize(device:1,time:1.03,contacts:Array(touches().prefix(1)),enabled:{_ in true})
        XCTAssertEqual(lift.gesture,.twoFingerPinch); XCTAssertNotNil(lift.magnification)
        let replacement = router.recognize(device:1,time:1.04,contacts:touches(40,secondID:99),enabled:{_ in true})
        XCTAssertEqual(replacement.gesture,.twoFingerPinch); XCTAssertEqual(replacement.magnification,0)
        XCTAssertEqual(router.recognize(device:1,time:1.5,contacts:touches(41,secondID:99),enabled:{_ in true}).phase,.cancelled)
        var tracker = PinchDistanceTracker()
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
        XCTAssertEqual(recognize(1.01,touches(31)).gesture,.twoFingerPinch)
        let extra = OMSRawTouch(id:3,posX:0.9,posY:0.8,total:1,pressure:40,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
        let four = OMSRawTouch(id:4,posX:0.2,posY:0.8,total:1,pressure:40,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
        let added = recognize(1.02,touches(32)+[extra,four])
        XCTAssertEqual(added.gesture,.twoFingerPinch)
        XCTAssertEqual(try XCTUnwrap(added.magnification),32/31.0-1,accuracy:0.00001)
        let survivor = recognize(1.03,Array(touches(34).prefix(1)))
        XCTAssertEqual(survivor.gesture,.twoFingerPinch)
        XCTAssertGreaterThan(try XCTUnwrap(survivor.magnification),0)
        XCTAssertGreaterThan(try XCTUnwrap(recognize(1.04,Array(touches(36).prefix(1))).magnification),0)
        let returned = recognize(1.05,touches(36))
        XCTAssertEqual(returned.gesture,.twoFingerPinch); XCTAssertEqual(returned.magnification,0)
        XCTAssertGreaterThan(try XCTUnwrap(recognize(1.06,touches(37)).magnification),0)
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
        settings.setAction(.disabled,for:.twoFingerPinch,in:.right)
        settings.set(.zoom,value:0.7,in:.left); settings.set(.zoom,value:1.4,in:.right)
        XCTAssertNil(settings.sensitivity(.zoom,in:.both))
        profile.handGestureSettings = settings
        let loaded = try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile())
        XCTAssertEqual(loaded.handGestureSettings,settings)
        let data = try JSONEncoder().encode(settings)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        for hand in ["left","right"] {
            var side = try XCTUnwrap(old[hand] as? [String:Any]); side.removeValue(forKey:"zoomSensitivity")
            var bindings = try XCTUnwrap(side["bindings"] as? [String:Any]); bindings.removeValue(forKey:"twoFingerPinch")
            side["bindings"] = bindings; old[hand] = side
        }
        let migrated = try JSONDecoder().decode(HandGestureSettings.self,from:JSONSerialization.data(withJSONObject:old))
        XCTAssertEqual(migrated.action(.twoFingerPinch,in:.both),.zoom)
        XCTAssertEqual(migrated.sensitivity(.zoom,in:.both),1)
    }
}
