import Foundation
import XCTest
import ReplayFixtureKit
@testable import RewriteProbeKit

final class RewriteProbeTests: XCTestCase {
    func contact(_ id: Int, _ x: Double = 0.5, _ state: String = "touching", finger: Int32? = nil, y: Double = 0.5) -> ReplayContactRecord {
        ReplayContactRecord(id: id, x: x, y: y, total: 1, pressure: 0.25,
            majorAxis: 1, minorAxis: 1, angle: 0, density: 1, state: state,
            telemetry: finger.map { ReplayTouchTelemetry(fingerID: $0, handID: 0, velocityX: 0,
                velocityY: 0, absoluteX: 0, absoluteY: 0, absoluteVelocityX: 0,
                absoluteVelocityY: 0, sourceFrame: 0, sourceTimestamp: 0) })
    }
    func frame(_ seq: Int, _ time: Double, _ contacts: [ReplayContactRecord], device: Int = 0) -> ReplayFrameRecord {
        ReplayFrameRecord(seq: seq, timestampSec: time, deviceID: "42", deviceNumericID: 42,
                          deviceIndex: device, contacts: contacts)
    }
    func analyze(_ frames: [ReplayFrameRecord], width: Double? = 100, height: Double? = 50) throws -> ProbeObservation {
        try RewriteProbeAnalyzer.analyze(frames, deviceIndex: 0, widthMM: width, heightMM: height, gapLimitMS: 100)
    }
    func trial(_ checks: String) throws -> ProbeTrial {
        try JSONDecoder().decode(ProbeTrial.self, from: Data("""
        {"id":"test","capture":"test.atpcap","intent":"independent test intent","deviceIndex":0,"checks":\(checks)}
        """.utf8))
    }
    func testAnatomicalRelabelKeepsLifetimeAndIDReuseCreatesGeneration() throws {
        let o = try analyze([frame(1,0,[]),frame(2,0.01,[contact(7,finger: 2)]),
            frame(3,0.02,[contact(7,0.51,finger: 3)]),frame(4,0.03,[contact(7,0.51,"breaking")]),
            frame(5,0.04,[contact(7)]),frame(6,0.05,[])])
        XCTAssertEqual(o.lifetimes.count,2); XCTAssertEqual(o.lifetimes.map(\.generation),[1,2])
        XCTAssertEqual(o.lifetimes[0].identityChanges,1)
        XCTAssertEqual(o.lifetimes[0].maxDisplacementMM!,1,accuracy: 1e-8)
        XCTAssertFalse(o.lifetimes[0].uncertain); XCTAssertTrue(o.lifetimes[1].uncertain)
        XCTAssertEqual(o.identityRevisions.count,1)
        XCTAssertEqual(o.identityRevisions[0].from,2)
        XCTAssertEqual(o.identityRevisions[0].to,3)
        XCTAssertEqual(o.identityRevisions[0].generation,1)
    }
    func testLandingCanReviseExistingLabelWithoutRestartingTouch() throws {
        let o = try analyze([frame(1,0,[]),frame(2,0.01,[contact(1,finger:4)]),
            frame(3,0.02,[contact(1,finger:2),contact(9,finger:4)]),frame(4,0.03,[])])
        XCTAssertEqual(o.lifetimes.count,2)
        XCTAssertEqual(o.lifetimes[0].samples,2)
        let event = try XCTUnwrap(o.identityRevisions.first)
        XCTAssertEqual(event.rawID,1); XCTAssertEqual(event.previousActiveCount,1)
        XCTAssertEqual(event.currentActiveCount,2)
        XCTAssertEqual(event.context.map(\.rawID),[1,9])
        XCTAssertEqual(event.context.map(\.rawFingerID),[2,4])
        let reversed = try analyze([frame(1,0,[]),frame(2,0.01,[contact(1,finger:4)]),
            frame(3,0.02,[contact(9,finger:4),contact(1,finger:2)]),frame(4,0.03,[])])
        XCTAssertEqual(reversed.identityRevisions[0].currentActiveCount,2)
        XCTAssertEqual(reversed.identityRevisions[0].context.map(\.rawID),[1,9])
    }
    func testPartialLiftAndStaggeredLandingRemainOneNonemptyEpisode() throws {
        let o = try analyze([frame(1,0,[]),frame(2,0.01,[contact(1)]),
            frame(3,0.04,[contact(1),contact(2)]),frame(4,0.06,[contact(1),contact(2,0.5,"breaking")]),
            frame(5,0.08,[])])
        XCTAssertEqual(o.peakContacts,2); XCTAssertEqual(o.partialLiftFrames,1)
        XCTAssertEqual(o.largestLandingSpreadMS,30,accuracy: 1e-8)
    }
    func testSeparateTapsDoNotAcquireFakeLandingSpread() throws {
        let o = try analyze([frame(1,0,[]),frame(2,0.01,[contact(1)]),frame(3,0.03,[]),
            frame(4,0.05,[contact(2)]),frame(5,0.06,[])])
        XCTAssertEqual(o.largestLandingSpreadMS,0)
    }
    func testGapAndCaptureBoundariesCannotProveStableContact() throws {
        let o = try analyze([frame(1,0,[contact(1)]),frame(2,0.2,[contact(1)])])
        XCTAssertEqual(o.gaps,1); XCTAssertEqual(o.lifetimes.count,2)
        XCTAssertTrue(o.lifetimes.allSatisfy(\.uncertain))
        let t = try trial(#"[{"metric":"minimumLifetimes","value":1}]"#)
        XCTAssertEqual(RewriteProbeAnalyzer.evaluate(t,observation:o)[0].status,"inconclusive")
    }
    func testMissingDimensionsAndTelemetryAreNotPassingZeros() throws {
        let o = try analyze([frame(1,0,[]),frame(2,0.01,[contact(1)]),frame(3,0.02,[])],width:nil,height:nil)
        let t = try trial(#"[{"metric":"maximumDisplacementMM","value":3},{"metric":"maximumIdentityChanges","value":0}]"#)
        XCTAssertEqual(RewriteProbeAnalyzer.evaluate(t,observation:o).map(\.status),["inconclusive","inconclusive"])
    }
    func testOtherDeviceCannotSatisfySelectedTrial() throws {
        let o = try analyze([frame(1,0,[contact(1)],device:1)])
        let t = try trial(#"[{"metric":"maximumPeakContacts","value":1}]"#)
        XCTAssertEqual(RewriteProbeAnalyzer.evaluate(t,observation:o)[0].status,"inconclusive")
    }
    func testDisplacementUsesBothPhysicalAxesAndBoundaryIsInclusive() throws {
        let o = try analyze([frame(1,0,[]),frame(2,0.01,[contact(1,0)]),
            frame(3,0.02,[contact(1,0.03)]),frame(4,0.03,[])])
        let t = try trial(#"[{"metric":"maximumDisplacementMM","value":3},{"metric":"minimumDisplacementMM","value":3.1}]"#)
        XCTAssertEqual(RewriteProbeAnalyzer.evaluate(t,observation:o).map(\.status),["pass","fail"])
    }
    func testCorruptSamplesAndRegressingTimeAreInconclusive() throws {
        let o = try analyze([frame(1,0,[]),frame(2,0.02,[contact(1),contact(1)]),
            frame(3,0.01,[contact(2,.nan)])])
        XCTAssertEqual(o.duplicateIDs,1); XCTAssertEqual(o.invalidSamples,1)
        XCTAssertEqual(o.timestampRegressions,1)
    }
    func testDiagonalDisplacementUsesUnequalPhysicalDimensions() throws {
        let o = try analyze([frame(1,0,[]),frame(2,0.01,[contact(1,0,y:0)]),
            frame(3,0.02,[contact(1,0.03,y:0.04)]),frame(4,0.03,[])])
        XCTAssertEqual(o.lifetimes[0].maxDisplacementMM!,sqrt(13),accuracy:1e-8)
    }
    func testIdleGapDoesNotInventLostActiveContact() throws {
        let o = try analyze([frame(1,0,[]),frame(2,2,[]),frame(3,2.01,[contact(1)]),frame(4,2.02,[])])
        XCTAssertEqual(o.gaps,0)
        let t = try trial(#"[{"metric":"minimumLifetimes","value":1}]"#)
        XCTAssertEqual(RewriteProbeAnalyzer.evaluate(t,observation:o)[0].status,"pass")
    }
    func testPlanRejectsUnknownMetricAndPartialDimensions() throws {
        XCTAssertThrowsError(try trial(#"[{"metric":"misspelledTest","value":0}]"#))
        let plan = try JSONDecoder().decode(ProbePlan.self,from:Data(#"{"schema":"g2k-rewrite-probe-v1","gapLimitMS":100,"widthMM":100,"trials":[{"id":"a","capture":"a.atpcap","intent":"tap","deviceIndex":0,"checks":[{"metric":"minimumLifetimes","value":1}]}]}"#.utf8))
        XCTAssertThrowsError(try plan.validate())
    }
    func testSavedCaptureRoundTripReplaysSameObservations() throws {
        let frames = [frame(1,0,[]),frame(2,0.01,[contact(1,finger:0)]),frame(3,0.02,[])]
        let fixture = ReplayFixture(meta: ReplayFixtureMeta(schema: ReplayFixtureParser.schema,
            capturedAt:"2026-10-17T00:00:00Z",platform:"macOS",source:"synthetic-unit-test",framesCaptured:frames.count),frames:frames)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("probe-\(UUID().uuidString).atpcap")
        defer { try? FileManager.default.removeItem(at:url) }
        try ReplayFixtureCodec.write(fixture,to:url)
        let loaded = try ReplayFixtureParser.load(from:url)
        let a = try analyze(frames), b = try analyze(loaded.frames)
        XCTAssertEqual(a.lifetimes.count,b.lifetimes.count)
        XCTAssertEqual(b.lifetimes[0].rawFingerIDs,[0]) // Raw zero is valid telemetry.
        XCTAssertEqual(b.lifetimes[0].durationMS,a.lifetimes[0].durationMS,accuracy:1e-8)
    }
}
