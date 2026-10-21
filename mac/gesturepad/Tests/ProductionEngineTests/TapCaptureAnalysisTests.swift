import Foundation
import OpenMultitouchSupport
import ReplayFixtureKit
import XCTest
@testable import GesturePadRuntime

final class TapCaptureAnalysisTests: XCTestCase {
    private func analyze(_ filename: String, reportVariable: String) throws -> [[String:Any]] {
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = root.appendingPathComponent("RewriteValidation/captures/\(filename)")
        guard FileManager.default.fileExists(atPath:file.path) else { throw XCTSkip("Local user capture not bundled.") }
        let fixture = try ReplayFixtureParser.load(from:file)
        var reports: [[String:Any]] = []
        for threshold in [0.2,0.35,0.5,0.75,1.0] {
            var router = TrackpadGestureRouter(mouseActivationMM:threshold)
            var tap = TwoFingerTapRecognizer(), isolatedTap = TwoFingerTapRecognizer()
            var cycles: [[String:Any]] = [], index = 0
            var start: Double?, clicks = 0, isolatedClicks = 0, hadMouse = false
            var mouseStart: Double?
            var firstPositions: [Int:CGPoint] = [:]
            var maxTravel = 0.0
            let base = fixture.frames.first?.timestampSec ?? 0
            for frame in fixture.frames {
                let contacts = frame.contacts.map { c in
                    OMSRawTouch(id:Int32(c.id),posX:Float(c.x),posY:Float(c.y),total:Float(c.total),
                        pressure:Float(c.pressure),majorAxis:Float(c.majorAxis),minorAxis:Float(c.minorAxis),
                        angle:Float(c.angle),density:Float(c.density),state:OMSState(rawValue:c.state) ?? .notTouching)
                }
                let active = frame.contacts.filter { $0.state == "making" || $0.state == "touching" }
                if !active.isEmpty && start == nil { start = frame.timestampSec; index += 1 }
                for c in active {
                    let first = firstPositions[c.id] ?? CGPoint(x:c.x,y:c.y)
                    firstPositions[c.id] = first
                    maxTravel = max(maxTravel,hypot((c.x-first.x)*160,(c.y-first.y)*114.9))
                }
                let output = router.process(device:frame.deviceNumericID,time:frame.timestampSec,
                    contacts:contacts,mouse:true,scroll:true)
                if output?.gesture == .mouse {
                    hadMouse = true
                    if mouseStart == nil { mouseStart = frame.timestampSec }
                }
                if tap.process(device:frame.deviceNumericID,time:frame.timestampSec,contacts:contacts,gestureActive:output != nil) { clicks += 1 }
                if isolatedTap.process(device:frame.deviceNumericID,time:frame.timestampSec,contacts:contacts) { isolatedClicks += 1 }
                if active.isEmpty, let began = start {
                    cycles.append(["cycle":index,"start_seconds":began-base,
                        "duration_ms":(frame.timestampSec-began)*1000,"clicks":clicks,
                        "tap_without_router":isolatedClicks,"mouse_claimed":hadMouse,
                        "mouse_onset_ms":mouseStart.map { ($0-began)*1000 } as Any? ?? NSNull(),
                        "max_individual_travel_mm":maxTravel])
                    start = nil; clicks = 0; isolatedClicks = 0; hadMouse = false; mouseStart = nil
                    firstPositions.removeAll(keepingCapacity:true); maxTravel = 0
                }
            }
            let clickCount = cycles.reduce(0) { $0 + ($1["clicks"] as! Int) }
            let movementCycles = cycles.filter { ($0["max_individual_travel_mm"] as! Double) > 8 }
            XCTAssertTrue(movementCycles.allSatisfy { ($0["clicks"] as! Int) == 0 })
            XCTAssertTrue(movementCycles.allSatisfy { ($0["mouse_claimed"] as! Bool) })
            reports.append(["mouse_threshold_mm":threshold,"click_count":clickCount,
                "movement_cycles":movementCycles.count,"cycles":cycles])
        }
        if let path = ProcessInfo.processInfo.environment[reportVariable] {
            try JSONSerialization.data(withJSONObject:reports,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:path))
        }
        return reports
    }
    func testMoveTapCaptureAcrossMouseInitiationThresholdsWithoutPosting() throws {
        let reports = try analyze("2finger_tap.atpcap",reportVariable:"TAP_CAPTURE_REPORT")
        XCTAssertEqual(reports[0]["click_count"] as? Int,19)
        XCTAssertEqual(reports[1]["click_count"] as? Int,25)
        XCTAssertEqual(reports[0]["movement_cycles"] as? Int,29)
        XCTAssertEqual(reports[1]["movement_cycles"] as? Int,29)
    }
    func testFollowupCaptureAcrossMouseInitiationThresholdsWithoutPosting() throws {
        let reports = try analyze("2finger_tap_test2.atpcap",reportVariable:"TAP_CAPTURE_REPORT2")
        XCTAssertEqual(reports[0]["click_count"] as? Int,17)
        XCTAssertEqual(reports[1]["click_count"] as? Int,22)
        let cycles = reports[1]["cycles"] as! [[String:Any]]
        XCTAssertEqual(cycles.count,45)
        // First stationary-tap block, then alternating move/tap, then no-click strokes.
        XCTAssertTrue(cycles.prefix(10).allSatisfy { ($0["clicks"] as! Int) == 1 })
        XCTAssertTrue(cycles.suffix(11).allSatisfy {
            ($0["clicks"] as! Int) == 0 && ($0["mouse_claimed"] as! Bool)
        })
        XCTAssertEqual(cycles.filter { $0["mouse_claimed"] as! Bool }.count,23)
        XCTAssertTrue(cycles.allSatisfy {
            ($0["clicks"] as! Int) == ($0["tap_without_router"] as! Int)
        })
    }
}
