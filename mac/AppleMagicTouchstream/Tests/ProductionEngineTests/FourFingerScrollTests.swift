import AppKit
import CoreGraphics
import ReplayFixtureKit
import Foundation
import OpenMultitouchSupport
import XCTest
@testable import GlassToKeyRuntime

final class FourFingerScrollTests: XCTestCase {
    private func touches(_ count: Int, _ offset: Float = 0) -> [OMSRawTouch] {
        (0..<count).map { i in
            OMSRawTouch(id:Int32(i+1),posX:Float(i)*0.1+offset,posY:0.5,total:1,
                pressure:100,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
        }
    }
    func testInitialMovingChordChoosesScrollAndLatchesThroughCountChanges() {
        var router = TrackpadGestureRouter()
        _ = router.process(device:1,time:1,contacts:touches(2),mouse:true,scroll:true)
        // Four fingers finish arriving before deliberate motion; two must not steal it.
        XCTAssertNil(router.process(device:1,time:1.01,contacts:touches(4),mouse:true,scroll:true))
        XCTAssertEqual(router.process(device:1,time:1.02,contacts:touches(4,0.003),mouse:true,scroll:true)?.gesture,.scroll)
        XCTAssertEqual(router.process(device:1,time:1.03,contacts:touches(1,0.004),mouse:true,scroll:true)?.gesture,.scroll)
        XCTAssertEqual(router.process(device:1,time:1.04,contacts:touches(3,0.005),mouse:true,scroll:true)?.gesture,.scroll)
        XCTAssertNil(router.process(device:1,time:1.05,contacts:touches(0),mouse:true,scroll:true))
        XCTAssertNil(router.process(device:1,time:1.06,contacts:touches(1),mouse:true,scroll:true))
        XCTAssertNil(router.process(device:1,time:1.07,contacts:touches(1,0.01),mouse:true,scroll:true))
    }
    func testMouseLatchSurvivesFourFingersAndPadsDoNotShareModes() {
        var router = TrackpadGestureRouter()
        _ = router.process(device:1,time:1,contacts:touches(2),mouse:true,scroll:true)
        XCTAssertEqual(router.process(device:1,time:1.01,contacts:touches(2,0.003),mouse:true,scroll:true)?.gesture,.mouse)
        XCTAssertEqual(router.process(device:1,time:1.02,contacts:touches(4,0.004),mouse:true,scroll:true)?.gesture,.mouse)
        _ = router.process(device:2,time:1.02,contacts:touches(4),mouse:true,scroll:true)
        XCTAssertEqual(router.process(device:2,time:1.03,contacts:touches(4,0.003),mouse:true,scroll:true)?.gesture,.scroll)
        router.reset(device:1)
        XCTAssertNil(router.process(device:1,time:1.04,contacts:touches(1,0.01),mouse:true,scroll:true))
    }
    func testDisabledModesStaleFramesAndJitterCannotClaimGesture() {
        var router = TrackpadGestureRouter()
        _ = router.process(device:1,time:1,contacts:touches(4),mouse:true,scroll:false)
        XCTAssertNil(router.process(device:1,time:1.01,contacts:touches(4,0.01),mouse:true,scroll:false))
        router.reset()
        _ = router.process(device:1,time:2,contacts:touches(4),mouse:true,scroll:true)
        XCTAssertNil(router.process(device:1,time:2.01,contacts:touches(4,0.0001),mouse:true,scroll:true))
        _ = router.process(device:1,time:2.02,contacts:touches(4,0.003),mouse:true,scroll:true)
        XCTAssertNil(router.process(device:1,time:3,contacts:touches(1,0.1),mouse:true,scroll:true))
        XCTAssertNil(router.process(device:1,time:3.01,contacts:touches(1,0.2),mouse:true,scroll:true))
    }
    func testScrollHistoryMatchesIndependentPythonVectors() throws {
        struct Fixture: Decodable {
            struct Vector: Decodable { let t,counts,expected: Double }
            let curves: [[String:Double]]
            let vectors: [Vector]
        }
        let url = try XCTUnwrap(Bundle.module.url(forResource:"AppleScrollAccelerationVectors",withExtension:"json",subdirectory:"Fixtures"))
        let fixture = try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:url))
        let curves = fixture.curves.map { c in
            ApplePointerCurve(index:c["index"]!,linear:c["HIDAccelGainLinear"] ?? 0,
                parabolic:c["HIDAccelGainParabolic"] ?? 0,cubic:c["HIDAccelGainCubic"] ?? 0,
                quartic:c["HIDAccelGainQuartic"] ?? 0,tangentLinear:c["HIDAccelTangentSpeedLinear"] ?? 0,
                tangentRoot:c["HIDAccelTangentSpeedParabolicRoot"] ?? 0)
        }
        let profile = try ApplePointerAccelerationProfile(resolution:400,acceleration:0.5,curves:curves)
        var axis = AppleScrollAxis(profile:profile)
        for vector in fixture.vectors {
            XCTAssertEqual(try XCTUnwrap(axis.points(time:vector.t,counts:vector.counts)),vector.expected,accuracy:1e-9)
        }
    }
    func testFineScrollDirectionAndIndependentAxes() throws {
        let p = try ApplePointerAccelerationProfile(resolution:400,acceleration:0,
            curves:[ApplePointerCurve(index:0,linear:1,parabolic:1)])
        var natural = FourFingerScrollEngine(profile:AppleScrollProfile(horizontal:p,vertical:p,natural:true))
        var traditional = FourFingerScrollEngine(profile:AppleScrollProfile(horizontal:p,vertical:p,natural:false))
        let a = try XCTUnwrap(natural.process(time:1,millimetres:CGPoint(x:0.001,y:-0.001),sensitivity:1))
        let b = try XCTUnwrap(traditional.process(time:1,millimetres:CGPoint(x:0.001,y:-0.001),sensitivity:1))
        XCTAssertGreaterThan(a.x,0); XCTAssertLessThan(a.y,0)
        XCTAssertLessThan(abs(a.x),1); XCTAssertGreaterThan(abs(a.x),0)
        XCTAssertEqual(a.x,-b.x,accuracy:1e-12); XCTAssertEqual(a.y,-b.y,accuracy:1e-12)
    }
    func testPreciseEventFractionsRemainderAndPhasesWithoutPosting() throws {
        var output = PreciseScrollOutput()
        var totalPoints: Int64 = 0
        var cocoaPoints = 0.0
        for index in 0..<8 {
            let event = try XCTUnwrap(output.event(points:CGPoint(x:0,y:0.25)))
            XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),0.025,accuracy:1.0/65536)
            XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventIsContinuous),1)
            XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventScrollPhase),index == 0 ? 1 : 2)
            XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventMomentumPhase),0)
            let cocoa = try XCTUnwrap(NSEvent(cgEvent:event))
            XCTAssertTrue(cocoa.hasPreciseScrollingDeltas)
            cocoaPoints += Double(cocoa.scrollingDeltaY)
            totalPoints += event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        }
        XCTAssertEqual(totalPoints,2)
        XCTAssertEqual(cocoaPoints,2)
        XCTAssertEqual(output.finish(cancelled:false)?.getIntegerValueField(.scrollWheelEventScrollPhase),4)
        XCTAssertNil(output.finish(cancelled:false))
        _ = output.event(points:CGPoint(x:0,y:-0.25))
        XCTAssertEqual(output.finish(cancelled:true)?.getIntegerValueField(.scrollWheelEventScrollPhase),8)
    }
    func testExistingTwoFingerCaptureKeepsMouseRouting() throws {
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = root.appendingPathComponent("RewriteValidation/captures/left_normal_right_takeover.atpcap")
        guard FileManager.default.fileExists(atPath:file.path) else { throw XCTSkip("Local user capture not bundled.") }
        let fixture = try ReplayFixtureParser.load(from:file)
        var router = TrackpadGestureRouter()
        var mouseFrames = 0
        for frame in fixture.frames {
            let contacts = frame.contacts.map { c in
                OMSRawTouch(id:Int32(c.id),posX:Float(c.x),posY:Float(c.y),total:Float(c.total),
                    pressure:Float(c.pressure),majorAxis:Float(c.majorAxis),minorAxis:Float(c.minorAxis),
                    angle:Float(c.angle),density:Float(c.density),state:OMSState(rawValue:c.state) ?? .notTouching)
            }
            if let output = router.process(device:frame.deviceNumericID,time:frame.timestampSec,
                contacts:contacts,mouse:true,scroll:true) {
                XCTAssertEqual(output.gesture,.mouse)
                mouseFrames += 1
            }
        }
        XCTAssertGreaterThan(mouseFrames,100)
    }

    func testInstalledScrollProfileReadOnlyWhenExplicitlyRequested() throws {
        guard let raw = ProcessInfo.processInfo.environment["SCROLL_PROFILE_REGISTRY_ID"],let id = UInt64(raw) else {
            throw XCTSkip("Optional read-only profile check, no hardware activation.")
        }
        let profile = try InstalledScrollCurveReader.read(registryEntryID:id)
        XCTAssertGreaterThan(profile.vertical.resolution,0)
        XCTAssertGreaterThan(profile.vertical.algorithmRate,0)
    }
}
