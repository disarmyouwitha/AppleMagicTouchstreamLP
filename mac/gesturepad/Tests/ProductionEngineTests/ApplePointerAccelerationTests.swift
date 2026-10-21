import CoreGraphics
import Foundation
import OpenMultitouchSupport
import ReplayFixtureKit
import XCTest
@testable import GesturePadRuntime

final class ApplePointerAccelerationTests: XCTestCase {
    private func installedExample() throws -> ApplePointerAccelerationProfile {
        try ApplePointerAccelerationProfile(resolution:400,fixedMultiplier:48545/65536,
            acceleration:3,curves:[ApplePointerCurve(index:3,linear:1,parabolic:123208/65536,
                cubic:23593/65536,tangentLinear:7,tangentRoot:12)])
    }
    private func touch(_ id: Int32, _ x: Float, _ y: Float = 0.5) -> OMSRawTouch {
        OMSRawTouch(id:id,posX:x,posY:y,total:1,pressure:100,majorAxis:5,minorAxis:3,
            angle:0,density:1,state:.touching)
    }

    func testAnalyticPolynomialLineAndRootVectors() throws {
        let profile = try ApplePointerAccelerationProfile(resolution:67,acceleration:0,
            curves:[ApplePointerCurve(index:0,linear:1,parabolic:0.5,tangentLinear:2,tangentRoot:4)])
        for (x,y) in [(1.0,1.25),(2,3),(3,5),(4,7),(5,sqrt(77))] {
            XCTAssertEqual(profile.acceleratedVelocity(x),y*96/67,accuracy:1e-10)
        }
    }
    func testSwiftMatchesPythonModelVectors() throws {
        struct Vector: Decodable { let t,dx,dy,expectedX,expectedY: Double }
        struct DataSet: Decodable { let vectors: [Vector] }
        let url = try XCTUnwrap(Bundle.module.url(forResource:"ApplePointerAccelerationVectors",withExtension:"json",subdirectory:"Fixtures"))
        let values = try JSONDecoder().decode(DataSet.self,from:Data(contentsOf:url))
        var model = ApplePointerAccelerator(profile:try installedExample())
        for v in values.vectors {
            let delta = try XCTUnwrap(model.delta(time:v.t,counts:CGPoint(x:v.dx,y:v.dy)))
            XCTAssertEqual(delta.x,v.expectedX,accuracy:1e-9)
            XCTAssertEqual(delta.y,v.expectedY,accuracy:1e-9)
        }
    }
    func testTimingNormalizationAndNonunitFixedMultiplier() throws {
        func profile(_ fixed: Double) throws -> ApplePointerAccelerationProfile {
            try ApplePointerAccelerationProfile(resolution:67,reportRate:100,fixedMultiplier:fixed,
                acceleration:0,curves:[ApplePointerCurve(index:0,linear:1,parabolic:0.5)])
        }
        for multiplier in [1.0,0.75] {
            var a = ApplePointerAccelerator(profile:try profile(multiplier))
            var b = a
            _ = a.delta(time:1,counts:CGPoint(x:2,y:0)); _ = b.delta(time:1,counts:CGPoint(x:2,y:0))
            let fast = try XCTUnwrap(a.delta(time:1.01,counts:CGPoint(x:2,y:0)))
            let slow = try XCTUnwrap(b.delta(time:1.02,counts:CGPoint(x:2,y:0)))
            if multiplier == 1 { XCTAssertGreaterThan(fast.x,slow.x) }
            else { XCTAssertEqual(fast,slow) }
        }
    }
    func testInterpolationInvalidSettingsAndDisabledAcceleration() throws {
        let curves = [ApplePointerCurve(index:0,linear:1),ApplePointerCurve(index:2,linear:3)]
        XCTAssertEqual(try ApplePointerCurve.interpolate(curves,at:1).linear,2)
        XCTAssertEqual(try ApplePointerCurve.interpolate(curves,at:4).linear,3)
        XCTAssertThrowsError(try ApplePointerAccelerationProfile(resolution:0,acceleration:0,curves:curves))
        XCTAssertThrowsError(try ApplePointerCurve.interpolate(Array(curves.reversed()),at:1))
        var model = ApplePointerAccelerator(profile:try ApplePointerAccelerationProfile(resolution:400,acceleration:-1,curves:curves))
        XCTAssertEqual(model.delta(time:1,counts:CGPoint(x:3,y:-4)),CGPoint(x:3,y:-4))
        XCTAssertNil(model.delta(time:1,counts:.zero))
    }
    func testModeAndSensitivityChangesReanchorAndFixedIsUnchanged() throws {
        var engine = TwoFingerPointerMotionEngine()
        let pair = [touch(1,0.2),touch(2,0.4)], moved = [touch(1,0.21),touch(2,0.41)]
        XCTAssertNil(engine.process(device:1,time:1,contacts:pair))
        XCTAssertEqual(try XCTUnwrap(engine.process(device:1,time:1.01,contacts:moved)).x,9.6,accuracy:0.001)
        engine.configure(response:.apple,sensitivity:1,profiles:[1:try installedExample()])
        XCTAssertNil(engine.process(device:1,time:1.02,contacts:pair))
        XCTAssertNotNil(engine.process(device:1,time:1.03,contacts:moved))
        engine.configure(response:.apple,sensitivity:0.75,profiles:[1:try installedExample()])
        XCTAssertNil(engine.process(device:1,time:1.04,contacts:pair))
        // No silent constant fallback for another device without a curve.
        _ = engine.process(device:2,time:1.05,contacts:pair)
        XCTAssertNil(engine.process(device:2,time:1.06,contacts:moved))
    }
    func testInstalledProfileReadOnlyWhenExplicitlyRequested() throws {
        guard let raw = ProcessInfo.processInfo.environment["POINTER_PROFILE_REGISTRY_ID"],let id = UInt64(raw) else {
            throw XCTSkip("Optional read-only registry smoke check; not part of ordinary offline tests.")
        }
        let profile = try InstalledPointerCurveReader.read(registryEntryID:id)
        XCTAssertGreaterThan(profile.resolution,0)
        XCTAssertTrue(profile.acceleration.isFinite)
    }
    func testUserTwoFingerCaptureThroughBothPureMotionModes() throws {
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = root.appendingPathComponent("RewriteValidation/captures/left_normal_right_takeover.atpcap")
        guard FileManager.default.fileExists(atPath:file.path) else { throw XCTSkip("Local user capture not bundled into tests.") }
        let capture = try ReplayFixtureParser.load(from:file)
        let profile = try installedExample()
        var metrics: [String:Any] = [:]
        for mode in TwoFingerPointerResponse.allCases {
            var engine = TwoFingerPointerMotionEngine()
            let ids = Set(capture.frames.map(\.deviceNumericID))
            engine.configure(response:mode,sensitivity:1,profiles:Dictionary(uniqueKeysWithValues:ids.map { ($0,profile) }))
            var outputs = 0, peak = 0.0, distance = 0.0
            for frame in capture.frames {
                let contacts = frame.contacts.map { c in
                    OMSRawTouch(id:Int32(c.id),posX:Float(c.x),posY:Float(c.y),total:Float(c.total),
                        pressure:Float(c.pressure),majorAxis:Float(c.majorAxis),minorAxis:Float(c.minorAxis),
                        angle:Float(c.angle),density:Float(c.density),state:OMSState(rawValue:c.state) ?? .notTouching)
                }
                if let delta = engine.process(device:frame.deviceNumericID,time:frame.timestampSec,contacts:contacts) {
                    XCTAssertTrue(delta.x.isFinite && delta.y.isFinite)
                    XCTAssertLessThan(abs(delta.x),150); XCTAssertLessThan(abs(delta.y),150)
                    outputs += 1; let length = hypot(delta.x,delta.y); peak = max(peak,length); distance += length
                }
            }
            XCTAssertGreaterThan(outputs,100)
            metrics[mode.rawValue] = ["output_frames":outputs,"peak_vector_points":peak,"path_length_points":distance]
        }
        if let path = ProcessInfo.processInfo.environment["POINTER_REPLAY_REPORT"] {
            try JSONSerialization.data(withJSONObject:metrics,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:path))
        }
    }
}
