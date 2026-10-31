import Carbon
import CoreGraphics
import Foundation
import OpenMultitouchSupport
import XCTest
@testable import GlassToKeyRuntime

@MainActor
final class ProductionEngineTests: XCTestCase {
    private func session(labels: [String] = ["F", "Shift", "G"], keyboardOnly: Bool = true, gestures: Bool = false, allowHold: Bool = false) -> ProductionReplaySession {
        let session = ProductionReplaySession(startTime: 1)
        let engine = session.engine
        let size = CGSize(width: 160, height: 115)
        let rects = labels.indices.map { index in
            CGRect(x: 10 + index * 45, y: 40, width: 35, height: 30)
        }
        let layout = ContentViewModel.Layout(keyRects: [rects], trackpadSize: size, allowHoldBindings: allowHold)
        engine.updateLayouts(leftLayout: layout, rightLayout: layout,
                             leftLabels: [labels], rightLabels: [labels],
                             trackpadSize: size, trackpadWidthMm: 160)
        engine.updateActiveDevices(leftIndex: 0, rightIndex: 1, leftDeviceID: "42", rightDeviceID: "43")
        engine.updateGestureRecognitionEnabled(gestures)
        engine.updateKeyboardModeEnabled(keyboardOnly)
        engine.updateForceClickMin(0)
        engine.updateForceClickCap(1000)
        engine.updateHapticStrength(0)
        engine.updateSnapRadiusPercent(0)
        engine.setListening(true)
        engine.setCaptureFrameDiagnosticsEnabled(true)
        return session
    }

    private func contact(_ id: Int32 = 1, key: Int = 0, state: OMSState = .touching,
                         x: Float? = nil) -> OMSRawTouch {
        OMSRawTouch(id: id, posX: x ?? Float(27.5 + Double(key) * 45) / 160,
                    posY: 1 - 55.0 / 115.0, total: 1, pressure: 100,
                    majorAxis: 5, minorAxis: 3, angle: 0, density: 1, state: state)
    }

    @discardableResult
    private func frame(_ session: ProductionReplaySession, _ time: Double, _ contacts: [OMSRawTouch],
                       side: Int = 0, reserved: Bool = false) -> RuntimeFrameDiagnostic? {
        session.ingest(RuntimeRawFrame(sequence: UInt64((time * 1000).rounded()), timestamp: time,
                                       deviceNumericID: side == 0 ? 42 : 43, deviceIndex: side,
                                       contacts: [], rawTouches: contacts), suppressKeyboard:reserved)
    }

    private func keys(_ session: ProductionReplaySession) -> [String] {
        session.output.events.compactMap { event in
            switch event.kind {
            case let .keyStroke(code, flags, _): return "tap:\(code):\(flags.rawValue)"
            case let .key(code, flags, down, _): return "\(down ? "down" : "up"):\(code):\(flags.rawValue)"
            default: return nil
            }
        }
    }

    func testKeyboardFeedbackWaitsForAcceptanceAndGestureReservationNeverHighlights() {
        let typing = session()
        frame(typing,1,[contact()])
        frame(typing,1.02,[])
        XCTAssertFalse(typing.output.acceptedBindings.isEmpty)
        let gesture = session()
        frame(gesture,1,[contact()],reserved:true)
        frame(gesture,1.02,[contact(x:0.8)],reserved:true)
        frame(gesture,1.04,[],reserved:true)
        XCTAssertTrue(gesture.output.acceptedBindings.isEmpty)
        XCTAssertTrue(keys(gesture).isEmpty)
    }

    func testContactPathsAreBoundedExpireAndRestartAfterLift() {
        func touch(_ x: Float, timestamp: Double = 1) -> OMSTouchData {
            OMSTouchData(deviceID: "42", deviceIndex: 0, id: 1,
                         position: OMSPosition(x: x, y: 0.5), total: 1, pressure: 100,
                         axis: OMSAxis(major: 5, minor: 3), angle: 0, density: 1,
                         state: .touching, timestamp: timestamp)
        }
        var paths = ContactPathHistory()
        for i in 0..<200 { paths.update([touch(Float(i) / 200)], now: 1 + Double(i) / 1000) }
        XCTAssertEqual(paths.trails.values.first?.points.count, 96)
        paths.update([], now: 1.3)
        paths.update([touch(0.2)], now: 1.4)
        XCTAssertEqual(paths.trails.values.first?.points.count, 1)
        paths.update([touch(0.3, timestamp: 0.5)], now: 1.5)
        XCTAssertEqual(paths.trails.values.first?.points.count, 1)
        paths.prune(now: 3)
        XCTAssertTrue(paths.trails.isEmpty)
    }

    func testMomentaryLayerReleasesOnMissingContactAfterOtherPadNumberTap() throws {
        for layerSide in [0,1] {
            for explicitRelease in [false,true] {
                let run = session(labels:["MO(1)","F"])
                let numberSide: TrackpadSide = layerSide == 0 ? .right : .left
                let number = GridKeyPosition(side:numberSide,row:0,column:1).storageKey
                run.engine.updateKeyMappings([1:[number:KeyMapping(primary:try XCTUnwrap(KeyActionCatalog.action(for:"1")),hold:nil)]])
                XCTAssertEqual(frame(run,1,[contact(state:.making)],side:layerSide)?.activeLayer,1)
                XCTAssertEqual(frame(run,1.02,[contact(key:1,state:.making)],side:1-layerSide)?.activeLayer,1)
                XCTAssertEqual(frame(run,1.04,[contact(key:1,state:.breaking)],side:1-layerSide)?.activeLayer,1)
                // Empty frames from the other pad cannot release the held layer.
                XCTAssertEqual(frame(run,1.06,[],side:1-layerSide)?.activeLayer,1)
                XCTAssertEqual(keys(run),["tap:\(kVK_ANSI_1):0"])
                let release = explicitRelease ? [contact(state:.breaking)] : []
                XCTAssertEqual(frame(run,1.08,release,side:layerSide)?.activeLayer,0)
                XCTAssertEqual(frame(run,1.10,[],side:layerSide)?.activeLayer,0)
                frame(run,1.12,[contact(2,key:1,state:.making)],side:1-layerSide)
                frame(run,1.14,[contact(2,key:1,state:.breaking)],side:1-layerSide)
                XCTAssertEqual(keys(run),["tap:\(kVK_ANSI_1):0","tap:\(kVK_ANSI_F):0"])
            }
        }
    }

    func testDisconnectCancelsOnlyLostPadsLayerWithoutFiringItsPendingTap() {
        let run = session(labels:["MO(1)","F"])
        XCTAssertEqual(frame(run,1,[contact(state:.making)],side:0)?.activeLayer,1)
        run.engine.updateActiveDevices(leftIndex:nil,rightIndex:1,leftDeviceID:nil,rightDeviceID:"43")
        XCTAssertEqual(frame(run,1.02,[],side:1)?.activeLayer,0)
        XCTAssertTrue(keys(run).isEmpty)
        run.engine.updateActiveDevices(leftIndex:0,rightIndex:1,leftDeviceID:"44",rightDeviceID:"43")
        XCTAssertEqual(frame(run,1.04,[contact(state:.making)],side:0)?.activeLayer,1)
        XCTAssertEqual(frame(run,1.06,[],side:0)?.activeLayer,0)
    }

    func testOtherPadDisconnectPreservesHeldLayerAndPendingTyping() throws {
        let run = session(labels:["MO(1)","F"])
        let key = GridKeyPosition(side:.left,row:0,column:1).storageKey
        run.engine.updateKeyMappings([1:[key:KeyMapping(primary:try XCTUnwrap(KeyActionCatalog.action(for:"F")),hold:nil)]])
        XCTAssertEqual(frame(run,1,[contact(state:.making)],side:0)?.activeLayer,1)
        frame(run,1.01,[contact(),contact(2,key:1,state:.making)],side:0)
        run.engine.updateActiveDevices(leftIndex:0,rightIndex:nil,leftDeviceID:"42",rightDeviceID:nil)
        XCTAssertEqual(frame(run,1.02,[contact(),contact(2,key:1,state:.touching)],side:0)?.activeLayer,1)
        frame(run,1.04,[contact(),contact(2,key:1,state:.breaking)],side:0)
        XCTAssertEqual(keys(run),["tap:\(kVK_ANSI_F):0"])
        XCTAssertEqual(frame(run,1.06,[],side:0)?.activeLayer,0)
    }

    func testHeldLayerOwnsSamePadArrowChordUntilAllUp() throws {
        for side in [0,1] {
            let run = session(labels:["MO(1)","F"])
            let key = GridKeyPosition(side:side == 0 ? .left : .right,row:0,column:1).storageKey
            run.engine.updateKeyMappings([1:[key:KeyMapping(primary:try XCTUnwrap(KeyActionCatalog.action(for:"Left")),hold:nil)]])
            XCTAssertEqual(frame(run,1,[contact(state:.making)],side:side)?.activeLayer,1)
            XCTAssertTrue(run.engine.keyboardChordOwnsCycle(deviceIndex:side))
            XCTAssertFalse(run.engine.keyboardChordOwnsCycle(deviceIndex:1-side))
            // Model a multi-finger reservation request: an established layer
            // hold must take keyboard priority instead of being cancelled.
            XCTAssertEqual(frame(run,1.02,[contact(),contact(2,key:1,state:.making)],side:side,reserved:true)?.activeLayer,1)
            XCTAssertEqual(frame(run,1.04,[contact(),contact(2,key:1,state:.breaking)],side:side,reserved:true)?.activeLayer,1)
            XCTAssertEqual(keys(run),["tap:\(kVK_LeftArrow):0"])
            // The opposite pad's gesture remains eligible and cannot clear this hold.
            frame(run,1.05,[contact(3),contact(4,key:1)],side:1-side,reserved:true)
            XCTAssertEqual(frame(run,1.06,[contact()],side:side,reserved:true)?.activeLayer,1)
            XCTAssertEqual(frame(run,1.08,[],side:side,reserved:true)?.activeLayer,0)
            XCTAssertFalse(run.engine.keyboardChordOwnsCycle(deviceIndex:side))
            XCTAssertEqual(keys(run),["tap:\(kVK_LeftArrow):0"])
            // Normal gesture reservation resumes for the next cycle.
            let next = frame(run,1.10,[contact(5),contact(6,key:1)],side:side,reserved:true)
            XCTAssertTrue(next?.touches.contains(where:{$0.reason == "gestureReserved"}) ?? false)
        }
    }
    func testStartingLayerContactKeepsKeyboardPriorityThroughSamePadTaps() throws {
        for side in [0, 1] {
            let run = session(labels: ["MO(1)", "F"])
            let key = GridKeyPosition(side: side == 0 ? .left : .right, row: 0, column: 1).storageKey
            run.engine.updateKeyMappings([1: [key: KeyMapping(
                primary: try XCTUnwrap(KeyActionCatalog.action(for: "Left")), hold: nil)]])
            // The failing capture starts MO with .starting, then .making.
            // Earlier successful cycles begin directly with .making.
            XCTAssertEqual(frame(run, 1, [contact(state: .starting)], side: side)?.activeLayer, 1)
            XCTAssertTrue(run.engine.keyboardChordOwnsCycle(deviceIndex: side))
            frame(run, 1.01, [contact(state: .making)], side: side)
            XCTAssertTrue(run.engine.keyboardChordOwnsCycle(deviceIndex: side))
            for time in [1.1, 1.3] {
                XCTAssertEqual(frame(run, time, [contact(), contact(2, key: 1, state: .making)],
                                     side: side, reserved: true)?.activeLayer, 1)
                XCTAssertEqual(frame(run, time + 0.04, [contact(), contact(2, key: 1, state: .breaking)],
                                     side: side, reserved: true)?.activeLayer, 1)
            }
            XCTAssertEqual(keys(run), Array(repeating: "tap:\(kVK_LeftArrow):0", count: 2))
            XCTAssertEqual(frame(run, 1.5, [], side: side, reserved: true)?.activeLayer, 0)
            XCTAssertFalse(run.engine.keyboardChordOwnsCycle(deviceIndex: side))
        }
    }

    func testLayerKeyboardOwnershipEndsOnResetAndSurvivesLayerFingerLiftingFirst() {
        let run = session(labels:["MO(1)","F"])
        frame(run,1,[contact(state:.making)])
        frame(run,1.02,[contact(),contact(2,key:1,state:.making)],reserved:true)
        frame(run,1.04,[contact(state:.breaking),contact(2,key:1)],reserved:true)
        XCTAssertTrue(run.engine.keyboardChordOwnsCycle(deviceIndex:0))
        frame(run,1.06,[],reserved:true)
        XCTAssertFalse(run.engine.keyboardChordOwnsCycle(deviceIndex:0))
        frame(run,1.08,[contact(3,state:.making)])
        XCTAssertTrue(run.engine.keyboardChordOwnsCycle(deviceIndex:0))
        run.engine.resetState()
        XCTAssertFalse(run.engine.keyboardChordOwnsCycle(deviceIndex:0))
    }

    func testTapSelectsFExactlyOnceAndDoesNotTriggerSwipe() async {
        let run = session()
        frame(run, 1.00, [contact(state: .making)])
        frame(run, 1.04, [contact()])
        frame(run, 1.08, [contact(state: .breaking)])
        frame(run, 1.10, [])
        run.finish(at: 2)
        XCTAssertEqual(keys(run), ["tap:\(kVK_ANSI_F):0"])
        XCTAssertEqual(run.output.events.count, 1)
    }

    func testEstablishedModifiersProtectRepeatedSamePadTaps() throws {
        let bindings: [(String, CGEventFlags)] = [
            ("Shift", .maskShift), ("Ctrl", .maskControl), ("Option", .maskAlternate),
            ("AltGr", .maskAlternate), ("Cmd", .maskCommand),
            ("Hyper", [.maskShift, .maskControl, .maskAlternate, .maskCommand]),
            ("Shift+AltGr", [.maskShift, .maskAlternate])
        ]
        for side in [0, 1] {
            for (label, flags) in bindings {
                let run = session(labels: [label, "F"])
                frame(run, 1, [contact(state: .starting)], side: side)
                XCTAssertTrue(run.engine.keyboardChordOwnsCycle(deviceIndex: side), label)
                XCTAssertFalse(run.engine.keyboardChordOwnsCycle(deviceIndex: 1 - side), label)
                frame(run, 1.01, [contact(state: .making)], side: side)
                for (id, time) in [(Int32(2), 1.1), (Int32(3), 1.3), (Int32(4), 1.5)] {
                    frame(run, time, [contact(), contact(id, key: 1, state: .making)], side: side, reserved: true)
                    frame(run, time + 0.04, [contact(), contact(id, key: 1, state: .breaking)], side: side, reserved: true)
                }
                let strokes = run.output.events.compactMap { event -> CGEventFlags? in
                    if case let .keyStroke(code, flags, _) = event.kind {
                        XCTAssertEqual(code, CGKeyCode(kVK_ANSI_F), label)
                        return flags
                    }
                    return nil
                }
                XCTAssertEqual(strokes.count, 3, label)
                XCTAssertTrue(strokes.allSatisfy { $0.contains(flags) }, label)
                XCTAssertFalse(run.output.events.contains {
                    if case let .key(_, _, down, _) = $0.kind { return !down }; return false
                }, label)
                // Opposite-pad gestures remain reserved while this modifier holds.
                let other = frame(run, 1.6, [contact(5), contact(6, key: 1)], side: 1 - side, reserved: true)
                XCTAssertTrue(other?.touches.contains { $0.reason == "gestureReserved" } ?? false, label)
                frame(run, 1.7, [], side: side, reserved: true)
                XCTAssertFalse(run.engine.keyboardChordOwnsCycle(deviceIndex: side), label)
                let edges = run.output.events.compactMap { event -> Bool? in
                    if case let .key(_, _, down, _) = event.kind { return down }; return nil
                }
                XCTAssertEqual(edges.filter { $0 }.count, edges.filter { !$0 }.count, label)
                let next = frame(run, 1.8, [contact(7), contact(8, key: 1)], side: side, reserved: true)
                XCTAssertTrue(next?.touches.contains { $0.reason == "gestureReserved" } ?? false, label)
            }
        }
    }

    func testHoldAssignedModifierProtectsChordAndResetClearsOwnership() throws {
        for side in [0, 1] {
            let run = session(labels: ["F", "G"], allowHold: true)
            let position = GridKeyPosition(side: side == 0 ? .left : .right, row: 0, column: 0).storageKey
            run.engine.updateKeyMappings([0: [position: KeyMapping(
                primary: try XCTUnwrap(KeyActionCatalog.action(for: "F")),
                hold: try XCTUnwrap(KeyActionCatalog.action(for: "Shift")))]])
            run.engine.updateHoldThreshold(0.2)
            frame(run, 1, [contact(state: .making)], side: side)
            XCTAssertFalse(run.engine.keyboardChordOwnsCycle(deviceIndex: side))
            frame(run, 1.3, [contact()], side: side)
            XCTAssertTrue(run.engine.keyboardChordOwnsCycle(deviceIndex: side))
            frame(run, 1.4, [contact(), contact(2, key: 1, state: .making)], side: side, reserved: true)
            frame(run, 1.44, [contact(), contact(2, key: 1, state: .breaking)], side: side, reserved: true)
            XCTAssertEqual(keys(run), ["down:\(kVK_Shift):0", "tap:\(kVK_ANSI_G):\(CGEventFlags.maskShift.rawValue)"])
            run.engine.resetState()
            XCTAssertFalse(run.engine.keyboardChordOwnsCycle(deviceIndex: side))
            XCTAssertEqual(keys(run).last, "up:\(kVK_Shift):0")
        }
    }

    func testModifierLiftReleasesFlagsButKeepsChordOwnedUntilAllUp() {
        let run = session(labels: ["Shift", "F"])
        frame(run, 1, [contact(state: .making)])
        frame(run, 1.1, [contact(), contact(2, key: 1, state: .making)], reserved: true)
        frame(run, 1.2, [contact(state: .breaking), contact(2, key: 1)], reserved: true)
        XCTAssertEqual(keys(run).last, "up:\(kVK_Shift):0")
        XCTAssertTrue(run.engine.keyboardChordOwnsCycle(deviceIndex: 0))
        frame(run, 1.3, [], reserved: true)
        XCTAssertFalse(run.engine.keyboardChordOwnsCycle(deviceIndex: 0))
    }

    func testShiftIsHeldForFAndReleased() async {
        let run = session()
        frame(run, 1.00, [contact(2, key: 1, state: .making)])
        frame(run, 1.04, [contact(2, key: 1)])
        frame(run, 1.06, [contact(2, key: 1), contact(1, state: .making)])
        frame(run, 1.10, [contact(2, key: 1), contact()])
        frame(run, 1.14, [contact(2, key: 1), contact(state: .breaking)])
        frame(run, 1.16, [contact(2, key: 1)])
        frame(run, 1.18, [contact(2, key: 1, state: .breaking)])
        frame(run, 1.20, [])
        run.finish(at: 2)
        XCTAssertEqual(keys(run), ["down:\(kVK_Shift):0", "tap:\(kVK_ANSI_F):\(CGEventFlags.maskShift.rawValue)", "up:\(kVK_Shift):0"])
    }

    func testResetReleasesModifierWithoutAReleaseFrame() async {
        let run = session()
        frame(run, 1.00, [contact(key: 1, state: .making)])
        frame(run, 1.04, [contact(key: 1)])
        run.engine.resetState()
        XCTAssertEqual(keys(run), ["down:\(kVK_Shift):0", "up:\(kVK_Shift):0"])
        run.scheduler.advance(to: 3)
        XCTAssertEqual(keys(run).count, 2)
    }

    func testReleaseOutsideAllKeysHasNoTarget() async {
        let run = session()
        frame(run, 1.00, [contact(state: .making)])
        frame(run, 1.04, [contact()])
        frame(run, 1.08, [contact(x: 0.95)])
        frame(run, 1.12, [contact(state: .breaking, x: 0.95)])
        frame(run, 1.14, [])
        run.finish(at: 2)
        XCTAssertTrue(keys(run).isEmpty)
    }

    func testHoldRepeatFiresOnVirtualTimeAndStopsOnRelease() async {
        let run = session(labels: ["Left"])
        run.engine.updateHoldRepeatEnabled(true)
        frame(run, 1.00, [contact(state: .making)])
        frame(run, 1.04, [contact()])
        frame(run, 1.30, [contact()])
        let initialCount = keys(run).count
        XCTAssertGreaterThan(initialCount, 0)
        run.scheduler.advance(to: 2)
        XCTAssertGreaterThan(keys(run).count, initialCount)
        frame(run, 2.01, [contact(state: .breaking)])
        frame(run, 2.02, [])
        let stoppedCount = keys(run).count
        run.scheduler.advance(to: 4)
        XCTAssertEqual(keys(run).count, stoppedCount)
        run.finish(at: 4)
    }

    func testOverlappingTouchesOnBothPadsProduceBothKeys() async {
        let run = session()
        frame(run, 1.00, [contact(state: .making)])
        frame(run, 1.01, [contact(1, key: 2, state: .making)], side: 1)
        frame(run, 1.04, [contact()])
        frame(run, 1.05, [contact(1, key: 2)], side: 1)
        frame(run, 1.08, [contact(state: .breaking)])
        frame(run, 1.09, [contact(1, key: 2, state: .breaking)], side: 1)
        frame(run, 1.10, [])
        frame(run, 1.11, [], side: 1)
        run.finish(at: 2)
        XCTAssertEqual(keys(run), ["tap:\(kVK_ANSI_F):0", "tap:\(kVK_ANSI_G):0"])
    }

    func testClassifierReturnsIdleAfterAllContactsLift() async {
        let run = session(keyboardOnly: false)
        frame(run, 1.00, [contact(state: .making)])
        frame(run, 1.04, [contact()])
        frame(run, 1.08, [contact(state: .breaking)])
        frame(run, 1.10, [])
        let before = keys(run)
        XCTAssertEqual(run.output.intents.left, .idle)
        run.scheduler.advance(to: 2)
        XCTAssertEqual(keys(run), before)
        XCTAssertEqual(run.output.intents.left, .idle)
    }

    func testTwoFingerMotionSuppressesTyping() async {
        let run = session(keyboardOnly: false)
        frame(run, 1.00, [contact(1, state: .making), contact(2, key: 2, state: .making)],reserved:true)
        frame(run, 1.04, [contact(1), contact(2, key: 2)])
        frame(run, 1.08, [contact(1, x: 0.28), contact(2, key: 2, x: 0.84)])
        frame(run, 1.12, [contact(1, state: .breaking, x: 0.28),
                          contact(2, key: 2, state: .breaking, x: 0.84)])
        frame(run, 1.14, [])
        run.finish(at: 2)
        XCTAssertTrue(keys(run).isEmpty, "A multi-finger movement must not leak F/G taps: \(keys(run))")
    }

    func testSimultaneousRepeatsHaveStableOutputOrder() async {
        func replay() -> [String] {
            let run = session(labels: ["Left", "Right"])
            run.engine.updateHoldRepeatEnabled(true)
            frame(run, 1.00, [contact(1, state: .making), contact(2, key: 1, state: .making)])
            frame(run, 1.04, [contact(1), contact(2, key: 1)])
            frame(run, 1.30, [contact(1), contact(2, key: 1)])
            run.scheduler.advance(to: 2)
            frame(run, 2.01, [])
            run.finish(at: 3)
            return keys(run)
        }
        let expected = replay()
        XCTAssertGreaterThan(expected.count, 4)
        for _ in 0..<10 { XCTAssertEqual(replay(), expected) }
    }

    private var fixturesDirectory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("ReplayFixtures")
    }

    func testOldNonMonotonicCaptureIsRejectedByProductionReplay() async {
        let fixture = fixturesDirectory.appendingPathComponent("macos_first_capture_2026-02-20.atpcap")
        XCTAssertThrowsError(try ProductionReplayHarness.run(captureURL: fixture))
    }

    func testReplayTranscriptMatchesProductionBaselineAndIsDeterministic() async throws {
        let fixture = fixturesDirectory.appendingPathComponent("production_typing.atpcap")
        let expectedURL = fixturesDirectory.appendingPathComponent("production_typing.engine.transcript.jsonl")
        if ProcessInfo.processInfo.environment["UPDATE_PRODUCTION_REPLAY_FIXTURES"] == "1" {
            try writeRegressionFixture(to: fixture)
            try ProductionReplayHarness.run(captureURL: fixture).transcript
                .write(to: expectedURL, atomically: true, encoding: .utf8)
        }
        let first = try ProductionReplayHarness.run(captureURL: fixture)
        let second = try ProductionReplayHarness.run(captureURL: fixture)
        XCTAssertEqual(first.transcript, second.transcript)
        XCTAssertEqual(first.frameCount, 18)
        XCTAssertEqual(first.transcript, try String(contentsOf: expectedURL, encoding: .utf8))
        XCTAssertTrue(first.transcript.contains("TouchProcessorEngine"))
        XCTAssertTrue(first.transcript.contains("\"configuration\":\"capture\""))
        let lines = try first.transcript.split(separator: "\n").map {
            try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
        }
        let events = lines.flatMap { $0["events"] as? [[String: Any]] ?? [] }
        let kinds = try events.map {
            try JSONDecoder().decode(RuntimeDispatchEventKind.self,
                                     from: JSONSerialization.data(withJSONObject: $0["kind"]!))
        }
        let strokes: [(CGKeyCode, CGEventFlags)] = kinds.compactMap {
            if case let .keyStroke(code, flags, _) = $0 { return (code, flags) }
            return nil
        }
        XCTAssertEqual(strokes.map(\.0), [CGKeyCode(kVK_ANSI_F), CGKeyCode(kVK_ANSI_F)])
        XCTAssertEqual(strokes.map { $0.1.rawValue }, [0, CGEventFlags.maskShift.rawValue])
        let arrowEvents = kinds.filter {
            if case let .key(code, _, _, _) = $0 { return code == CGKeyCode(kVK_LeftArrow) }
            return false
        }
        XCTAssertGreaterThan(arrowEvents.count, 2, "Virtual deadlines must produce repeats between frames")
    }

    private func writeRegressionFixture(to url: URL) throws {
        let buttons: [CustomButton] = [
            ("F", kVK_ANSI_F, 0.05), ("Shift", kVK_Shift, 0.30), ("Left", kVK_LeftArrow, 0.55)
        ].enumerated().map { offset, item in
            CustomButton(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(offset + 1)")!,
                         side: .left,
                         rect: NormalizedRect(x: item.2, y: 0.35, width: 0.15, height: 0.30),
                         action: KeyAction(label: item.0, keyCode: UInt16(item.1), flags: 0, kind: .key),
                         hold: nil)
        }
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppKeymapProfile.defaultProfile())) as! [String: Any]
        json["layoutPreset"] = "Blank"
        json["leftDeviceID"] = "42"
        json["rightDeviceID"] = "43"
        json["keyboardModeEnabled"] = true
        json["holdRepeatEnabled"] = true
        json["hapticStrength"] = 0
        json["forceClickMin"] = 0
        json["forceClickCap"] = 1000
        json["customButtonsByLayout"] = ["Blank": ["0": try JSONSerialization.jsonObject(with: JSONEncoder().encode(buttons))]]
        let profile = try JSONDecoder().decode(AppKeymapProfile.self, from: JSONSerialization.data(withJSONObject: json))
        func touch(_ id: Int32, _ x: Float, _ state: OMSState = .touching) -> OMSRawTouch {
            OMSRawTouch(id: id, posX: x, posY: 0.5, total: 1, pressure: 100,
                        majorAxis: 5, minorAxis: 3, angle: 0, density: 1, state: state)
        }
        let frames: [(Double, [OMSRawTouch])] = [
            (1.00, [touch(1, 0.125, .making)]), (1.04, [touch(1, 0.125)]),
            (1.08, [touch(1, 0.125, .breaking)]), (1.10, []),
            (1.30, [touch(2, 0.375, .making)]), (1.34, [touch(2, 0.375)]),
            (1.36, [touch(2, 0.375), touch(1, 0.125, .making)]),
            (1.40, [touch(2, 0.375), touch(1, 0.125)]),
            (1.44, [touch(2, 0.375), touch(1, 0.125, .breaking)]),
            (1.46, [touch(2, 0.375)]), (1.48, [touch(2, 0.375, .breaking)]), (1.50, []),
            (2.00, [touch(3, 0.625, .making)]), (2.04, [touch(3, 0.625)]),
            (2.30, [touch(3, 0.625)]), (3.00, [touch(3, 0.625)]),
            (3.01, [touch(3, 0.625, .breaking)]), (3.02, [])
        ]
        let records = frames.enumerated().map { index, input in
            let ticks = Int64(((input.0 - 1) * 1_000_000_000).rounded())
            let contacts = input.1.map { raw in
                RuntimeRawContact(id: raw.id, posX: raw.posX, posY: raw.posY,
                                  pressure: raw.pressure, majorAxis: raw.majorAxis, minorAxis: raw.minorAxis,
                                  angle: raw.angle, density: raw.density, state: raw.state)
            }
            return ProcessedFrameRecord(
                frame: RuntimeRawFrame(sequence: UInt64(index + 1), timestamp: input.0,
                                       deviceNumericID: 42, deviceIndex: 0,
                                       contacts: contacts, rawTouches: input.1),
                arrivalTicks: ticks, ingress: nil, diagnostic: nil, dispatchEvents: []
            )
        }
        try ATPCaptureV3Codec.write(captureData: ATPCaptureV3Codec.CaptureData(
            configuration: profile, frameRecords: records, detachedDispatchEvents: []), to: url,
            source: "SyntheticProductionRecognitionRegression")
    }
    private func noGestures() -> GestureActionSet {
        GestureActionSet(
            twoFingerTap: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            threeFingerTap: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            twoFingerHold: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            threeFingerHold: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            fourFingerHold: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            outerCornersHold: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            innerCornersHold: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            leftEdgeUp: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            leftEdgeDown: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            rightEdgeUp: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            rightEdgeDown: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            topEdgeLeft: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            topEdgeRight: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            bottomEdgeLeft: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            bottomEdgeRight: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            threeFingerSwipeLeft: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            threeFingerSwipeRight: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            threeFingerSwipeUp: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            threeFingerSwipeDown: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            fourFingerSwipeLeft: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            fourFingerSwipeRight: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            fourFingerSwipeUp: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            fourFingerSwipeDown: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            fiveFingerSwipeLeft: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            fiveFingerSwipeRight: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            fiveFingerSwipeUp: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            fiveFingerSwipeDown: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            topLeftCornerSwipe: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            topRightCornerSwipe: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            bottomLeftCornerSwipe: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            bottomRightCornerSwipe: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            topLeftTriangle: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            topRightTriangle: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            bottomLeftTriangle: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            bottomRightTriangle: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            upperLeftCornerClick: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            upperRightCornerClick: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            lowerLeftCornerClick: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            lowerRightCornerClick: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            threeFingerClick: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            fourFingerClick: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            topLeftForceClick: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            topRightForceClick: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            bottomLeftForceClick: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none),
            bottomRightForceClick: KeyAction(label: "None", keyCode: 0, flags: 0, kind: .none)
        )
    }
    func testSingleFingerMovementKeepsTypingAndNextTapTypes() async {
        let run = session(keyboardOnly: false)
        frame(run, 1.00, [contact(state: .making)])
        frame(run, 1.02, [contact(x: 0.25)])
        XCTAssertEqual(run.output.intents.left, .typing)
        frame(run, 1.04, [contact()])
        frame(run, 1.06, [contact(state: .breaking)])
        frame(run, 1.08, [])
        XCTAssertEqual(keys(run), ["tap:\(kVK_ANSI_F):0"])
        frame(run, 1.10, [contact(state: .making)])
        frame(run, 1.12, [contact(state: .breaking)])
        XCTAssertEqual(keys(run), ["tap:\(kVK_ANSI_F):0", "tap:\(kVK_ANSI_F):0"])
    }

    func testMovementReportedOnlyOnReleaseStillTypes() async {
        let run = session()
        frame(run, 1.00, [contact(state: .making)])
        frame(run, 1.04, [contact(state: .breaking, x: 0.25)])
        XCTAssertEqual(keys(run), ["tap:\(kVK_ANSI_F):0"])
    }

    func testEmptyFrameReleasesHeldModifier() async {
        let run = session()
        frame(run, 1.00, [contact(key: 1, state: .making)])
        frame(run, 1.04, [])
        XCTAssertEqual(keys(run), ["down:\(kVK_Shift):0", "up:\(kVK_Shift):0"])
    }

    func testHapticFeedbackUsesConfiguredStrengthAndDevice() async {
        let run = session()
        run.engine.updateHapticStrength(0.4)
        frame(run, 1.00, [contact(state: .making)])
        frame(run, 1.08, [contact(state: .breaking)])
        let haptics = run.output.events.compactMap { event -> Double? in
            guard case let .haptic(strength, deviceID) = event.kind else { return nil }
            XCTAssertEqual(deviceID, "42")
            return strength
        }
        XCTAssertEqual(haptics, [0.4])
        XCTAssertEqual(keys(run), ["tap:\(kVK_ANSI_F):0"])
    }


    func testHapticThrottleIsIndependentPerTrackpad() async {
        let run = session()
        run.engine.updateHapticStrength(0.6)
        func tap(_ time: Double, side: Int = 0) {
            frame(run, time, [contact(state: .making)], side: side)
            frame(run, time + 0.004, [contact(state: .breaking)], side: side)
        }
        tap(1)
        tap(1.006) // Same pad inside 20 ms: coalesced.
        tap(1.012, side: 1) // Other pad still gets feedback.
        tap(1.032)
        let devices = run.output.events.compactMap { event -> String? in
            guard case let .haptic(strength, deviceID) = event.kind else { return nil }
            XCTAssertEqual(strength, 0.6)
            return deviceID
        }
        XCTAssertEqual(devices, ["42", "43", "42"])
        XCTAssertEqual(keys(run).count, 4)
    }

    func testHapticStrengthClampsAndZeroDisablesFeedback() async {
        let run = session()
        run.engine.updateHapticStrength(99)
        frame(run, 1, [contact(state: .making)])
        frame(run, 1.08, [contact(state: .breaking)])
        run.engine.updateHapticStrength(0)
        frame(run, 2, [contact(state: .making)])
        frame(run, 2.08, [contact(state: .breaking)])
        run.engine.updateHapticStrength(.nan)
        frame(run, 3, [contact(state: .making)])
        frame(run, 3.08, [contact(state: .breaking)])
        let strengths = run.output.events.compactMap { event -> Double? in
            if case let .haptic(strength, _) = event.kind { return strength }
            return nil
        }
        XCTAssertEqual(strengths, [2])
        XCTAssertEqual(keys(run).count, 3)
    }

    func testTypingHapticFineLevelsReachOutputWithoutChangingWaveform() async throws {
        let run = session()
        for (index,level) in [0.15,0.73,1.37,2.0].enumerated() {
            run.engine.updateHapticStrength(level)
            let time = 1 + Double(index)
            frame(run,time,[contact(state:.making)])
            frame(run,time+0.08,[contact(state:.breaking)])
        }
        let levels = run.output.events.compactMap { event -> Double? in
            if case let .haptic(strength,deviceID) = event.kind {
                XCTAssertEqual(deviceID,"42")
                return strength
            }
            return nil
        }
        XCTAssertEqual(levels,[0.15,0.73,1.37,2.0])
        for level in levels {
            let parameters = try XCTUnwrap(TypingHapticFeedback.parameters(for:level))
            XCTAssertEqual(parameters.waveform,6)
            XCTAssertEqual(parameters.level,Float(level),accuracy:0.00001)
        }
        for level in [0.0,-1.0,Double.nan,Double.infinity] {
            XCTAssertNil(TypingHapticFeedback.parameters(for:level))
        }
        XCTAssertEqual(TypingHapticFeedback.parameters(for:99)?.level,2)
        XCTAssertEqual(ForceClickHapticSettings.fixed.waveform,6)
        XCTAssertEqual(ForceClickHapticSettings.fixed.level,0.25)
    }

    func testReplayProfileHapticPercentIsNormalized() async throws {
        let run = session()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(AppKeymapProfile.defaultProfile())) as? [String: Any])
        json["hapticStrength"] = 40
        json["leftDeviceID"] = "42"
        json["rightDeviceID"] = "43"
        let profile = try JSONDecoder().decode(AppKeymapProfile.self, from: JSONSerialization.data(withJSONObject: json))
        run.configure(profile: profile, leftIndex: 0, rightIndex: 1)
        let size = CGSize(width: 160, height: 115)
        let layout = ContentViewModel.Layout(keyRects: [[CGRect(x: 10, y: 40, width: 35, height: 30)]], trackpadSize: size)
        run.engine.updateKeyMappings([:])
        run.engine.updateCustomButtons([])
        run.engine.updateLayouts(leftLayout: layout, rightLayout: layout,
            leftLabels: [["F"]], rightLabels: [["F"]], trackpadSize: size, trackpadWidthMm: 160)
        frame(run, 1, [contact(state: .making)])
        frame(run, 1.08, [contact(state: .breaking)])
        let strengths = run.output.events.compactMap { event -> Double? in
            if case let .haptic(strength, _) = event.kind { return strength }
            return nil
        }
        XCTAssertEqual(strengths, [0.4])
    }

    func testLegacyGestureToggleCannotRestoreGTKSwipeRecognition() async {
        let run = session(keyboardOnly: false)
        var actions = noGestures()
        actions.threeFingerSwipeRight = KeyActionCatalog.action(for: "G")!
        run.engine.updateGestureActions(actions)
        func swipe(_ start: Double) {
            frame(run, start, [contact(1, x: 0.10), contact(2, x: 0.15), contact(3, x: 0.20)])
            frame(run, start + 0.06, [contact(1, x: 0.20), contact(2, x: 0.25), contact(3, x: 0.30)])
            frame(run, start + 0.12, [])
        }
        swipe(1)
        let ordinaryTyping = keys(run)
        XCTAssertFalse(ordinaryTyping.contains("tap:\(kVK_ANSI_G):0"))
        run.engine.updateGestureRecognitionEnabled(true)
        swipe(2)
        XCTAssertEqual(keys(run),ordinaryTyping + ordinaryTyping)
        run.engine.updateGestureRecognitionEnabled(false)
        swipe(3)
        XCTAssertEqual(keys(run),ordinaryTyping + ordinaryTyping + ordinaryTyping)
    }

    func testLegacyGestureToggleCannotRestoreGTKTapClick() async {
        let run = session(keyboardOnly: false)
        var actions = noGestures()
        actions.twoFingerTap = KeyAction(label: "Left Click", keyCode: 0, flags: 0, kind: .leftClick)
        run.engine.updateGestureActions(actions)
        frame(run, 1, [contact(1, x: 0.12), contact(2, x: 0.20)])
        frame(run, 1.08, [])
        XCTAssertFalse(run.output.events.contains { if case .leftClick = $0.kind { true } else { false } })
        run.engine.updateGestureRecognitionEnabled(true)
        frame(run, 2, [contact(1, x: 0.12), contact(2, x: 0.20)])
        frame(run, 2.08, [])
        XCTAssertFalse(run.output.events.contains { if case .leftClick = $0.kind { true } else { false } })
    }

    func testUnassignedHoldNeverFallsBackToLegacyCatalog() async {
        // F historically acquired Shift+0 despite the inspector showing None.
        // Exercise absent mappings, explicit None, and clearing a prior hold.
        for mode in 0..<3 {
            let run = session(allowHold: true)
            let key = GridKeyPosition(side: .left, row: 0, column: 0).storageKey
            let primary = KeyActionCatalog.action(for: "F")!
            if mode == 2 {
                run.engine.updateKeyMappings([0: [key: KeyMapping(primary: primary,
                    hold: KeyActionCatalog.holdAction(for: "F")!)]])
            }
            if mode > 0 {
                run.engine.updateKeyMappings([0: [key: KeyMapping(primary: primary, hold: nil)]])
            }
            run.engine.updateHoldThreshold(0.2)
            frame(run, 1, [contact(state: .making)])
            frame(run, 1.04, [contact()])
            frame(run, 1.3, [contact()])
            frame(run, 1.32, [contact(state: .breaking)])
            run.finish(at: 2)
            XCTAssertEqual(keys(run), ["tap:\(kVK_ANSI_F):0"], "mapping mode \(mode)")
        }
    }

    func testOriginalHoldShortcutSurvivesClassifierReplacement() async {
        let run = session(allowHold: true)
        let key = GridKeyPosition(side: .left, row: 0, column: 0).storageKey
        let copy = KeyAction(label: "Copy", keyCode: UInt16(kVK_ANSI_C), flags: CGEventFlags.maskCommand.rawValue)
        run.engine.updateKeyMappings([0: [key: KeyMapping(primary: KeyActionCatalog.action(for: "F")!, hold: copy)]])
        run.engine.updateHoldThreshold(0.2)
        frame(run, 1, [contact(state: .making)])
        frame(run, 1.04, [contact()])
        frame(run, 1.3, [contact()])
        frame(run, 1.32, [contact(state: .breaking)])
        run.finish(at: 2)
        XCTAssertEqual(keys(run), ["tap:\(kVK_ANSI_C):\(CGEventFlags.maskCommand.rawValue)"])
    }

    func testLegacyMovementSettingsCannotBlockTyping() async {
        let run = session(keyboardOnly: false)
        run.engine.updateDragCancelDistance(0)
        run.engine.updateIntentMoveThreshold(0)
        run.engine.updateIntentVelocityThreshold(0)
        run.engine.updateTapClickCadence(1)
        frame(run, 1, [contact(state: .making)])
        frame(run, 1.04, [contact(x: 0.25)])
        frame(run, 1.08, [contact(state: .breaking, x: 0.25)])
        XCTAssertEqual(keys(run), ["tap:\(kVK_ANSI_F):0"])
    }

    func testGlobalForceBoundsCannotBlockTypingAndPerKeyForceHoldStillWorks() async {
        for pressure: Float in [0,10,255,500] {
            let run = session()
            run.engine.updateForceClickMin(200)
            run.engine.updateForceClickCap(201)
            func sample(_ state: OMSState) -> OMSRawTouch {
                OMSRawTouch(id:1,posX:27.5/160,posY:1-55.0/115,total:1,pressure:pressure,
                    majorAxis:5,minorAxis:3,angle:0,density:1,state:state)
            }
            frame(run,1,[sample(.making)]); frame(run,1.08,[sample(.breaking)])
            XCTAssertEqual(keys(run),["tap:\(kVK_ANSI_F):0"],"pressure \(pressure)")
        }
        let run = session(allowHold:true)
        run.engine.updateForceClickMin(250); run.engine.updateForceClickCap(251)
        let key = GridKeyPosition(side:.left,row:0,column:0).storageKey
        run.engine.updateKeyMappings([0:[key:KeyMapping(primary:KeyActionCatalog.action(for:"F")!,
            hold:KeyAction(label:"Copy",keyCode:UInt16(kVK_ANSI_C),flags:CGEventFlags.maskCommand.rawValue),holdForceThreshold:130)]])
        run.engine.updateHoldThreshold(0.05)
        frame(run,1,[contact(state:.making)])
        frame(run,1.1,[contact()]) // 100 stays below per-key threshold even after time expires.
        XCTAssertTrue(keys(run).isEmpty)
        let press = OMSRawTouch(id:1,posX:0.25,posY:1-55.0/115,total:1,pressure:140,
            majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
        frame(run,1.12,[press]); frame(run,1.14,[])
        XCTAssertEqual(keys(run),["tap:\(kVK_ANSI_C):\(CGEventFlags.maskCommand.rawValue)"])
    }

    func testLandingOutsideKeyThenMovingOntoKeyDoesNotLatchMouse() async {
        let run = session(keyboardOnly:false)
        frame(run,1,[contact(state:.making,x:0.95)])
        frame(run,1.04,[contact()])
        frame(run,1.08,[contact(state:.breaking)])
        XCTAssertEqual(keys(run),["tap:\(kVK_ANSI_F):0"])
    }

    func testGestureToggleRoundTripsAndOldProfilesDefaultOff() throws {
        var profile = AppKeymapProfile.defaultProfile()
        XCTAssertFalse(profile.gestureRecognitionEnabled ?? false)
        profile.gestureRecognitionEnabled = true
        let encoded = try JSONEncoder().encode(profile)
        XCTAssertEqual(try JSONDecoder().decode(AppKeymapProfile.self, from: encoded).gestureRecognitionEnabled, true)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "gestureRecognitionEnabled")
        let decoded = try JSONDecoder().decode(AppKeymapProfile.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertFalse(decoded.gestureRecognitionEnabled ?? false)
    }

    func testImportedGTKActionKindsCannotDispatchThroughKeysOrCustomButtons() async throws {
        let removed: [KeyActionKind] = [.typingToggle,
            .gestureTwoFingerTap, .gestureThreeFingerTap, .gestureFourFingerHold,
            .gestureInnerCornersHold, .gestureFiveFingerSwipeLeft, .gestureFiveFingerSwipeRight,
            .volumeUpSmall, .volumeDownSmall, .brightnessUp, .brightnessDown,
            .brightnessUpSmall, .brightnessDownSmall]
        for kind in removed {
            let action = try JSONDecoder().decode(KeyAction.self, from: JSONEncoder().encode(
                KeyAction(label: "Legacy unsupported action", keyCode: 0, flags: 0, kind: kind)))
            let run = session(allowHold: true)
            let key = GridKeyPosition(side: .left, row: 0, column: 0).storageKey
            run.engine.updateKeyMappings([0: [key: KeyMapping(primary: action, hold: action)]])
            run.engine.updateCustomButtons([CustomButton(id: UUID(), side: .left,
                rect: NormalizedRect(x: 0.65, y: 0.7, width: 0.3, height: 0.2), action: action, hold: action)])
            frame(run, 1, [contact(state: .making)])
            frame(run, 1.5, [contact()])
            frame(run, 1.6, [])
            func customTouch(_ state:OMSState) -> OMSRawTouch {
                OMSRawTouch(id:1,posX:0.8,posY:0.2,total:1,pressure:100,majorAxis:5,minorAxis:3,angle:0,density:1,state:state)
            }
            frame(run, 2, [customTouch(.making)])
            frame(run, 2.5, [customTouch(.touching)])
            frame(run, 2.6, [])
            run.finish(at: 3)
            XCTAssertTrue(run.output.events.isEmpty, "Unsupported imported kind \(kind) produced output: \(run.output.events)")
        }
    }

    func testActionCatalogOffersOnlySupportedBootstrapActions() {
        let allowed: Set<KeyActionKind> = [.key, .leftClick, .doubleClick, .rightClick,
            .middleClick, .volumeUp, .volumeDown, .voice, .layerMomentary, .layerToggle, .none, .steno]
        for group in KeyActionCatalog.primaryActionGroups {
            for action in group.actions { XCTAssertTrue(allowed.contains(action.kind), action.label) }
        }
        XCTAssertNil(KeyActionCatalog.action(for: "TT"))
        XCTAssertEqual(KeyActionCatalog.action(for: "VOICE")?.kind, .voice)
        let app = AppLaunchActionHelper.createActionLabel(fileName: "/Applications/Calculator.app")!
        XCTAssertEqual(KeyActionCatalog.action(for: app)?.kind, .appLaunch)
    }

}


extension ProductionEngineTests {
    private var hyperFlags: CGEventFlags { [.maskCommand,.maskControl,.maskAlternate,.maskShift] }

    func testHyperAndModifierOnlyShortcutCatalogAndKeymapRoundTrip() throws {
        let hyper = try XCTUnwrap(KeyActionCatalog.action(for:"Hyper"))
        XCTAssertEqual(hyper.keyCode,UInt16(kVK_Command))
        XCTAssertTrue(CGEventFlags(rawValue:hyper.flags).contains(hyperFlags))
        XCTAssertTrue(KeyActionCatalog.holdPresets.contains(hyper))
        XCTAssertEqual(hyper.pickerText,"Hyper")
        XCTAssertEqual(hyper.displayText,"Hyper")
        let builderHyper = try XCTUnwrap(KeyActionCatalog.shortcutAction(modifiers:[.control:.generic,.shift:.generic,.option:.generic,.command:.generic],keyLabel:""))
        XCTAssertEqual(builderHyper.pickerText,"Hyper")
        XCTAssertEqual(builderHyper.displayText,"Hyper")
        for label in ["Shift","Ctrl","Option","AltGr","Cmd"] {
            XCTAssertFalse(KeyActionCatalog.shortcutKeyLabels.contains(label))
        }
        let built = try XCTUnwrap(KeyActionCatalog.shortcutAction(modifiers:[.shift:.generic,.control:.generic,.option:.generic],keyLabel:""))
        XCTAssertEqual(KeyActionCatalog.action(for:built.label),built)
        XCTAssertEqual(KeyActionCatalog.shortcutSpec(for:hyper)?.keyLabel,"")
        XCTAssertEqual(KeyActionCatalog.shortcutSpec(for:hyper)?.modifiers.count,4)
        let position = GridKeyPosition(side:.left,row:0,column:0).storageKey
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(AppKeymapProfile.defaultProfile())) as? [String:Any])
        object["keyMappingsByLayout"] = try JSONSerialization.jsonObject(with:JSONEncoder().encode(["TouchStream":[0:[position:KeyMapping(primary:hyper,hold:hyper)]]]))
        let profile = try JSONDecoder().decode(AppKeymapProfile.self,from:JSONSerialization.data(withJSONObject:object))
        let imported = try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile())
        XCTAssertEqual(imported.keyMappingsByLayout?["TouchStream"]?[0]?[position]?.primary,hyper)
        XCTAssertEqual(imported.keyMappingsByLayout?["TouchStream"]?[0]?[position]?.hold,hyper)
    }

    func testHyperPrimaryHoldsFourModifiersUntilAllUpAndNeverTypesCommand() {
        let run = session(labels:["Hyper","F"])
        frame(run,1,[contact(state:.making)])
        frame(run,1.04,[contact()])
        frame(run,1.06,[contact(),contact(2,key:1,state:.making)])
        frame(run,1.10,[contact(),contact(2,key:1)])
        frame(run,1.14,[contact(),contact(2,key:1,state:.breaking)])
        frame(run,1.16,[contact()])
        frame(run,1.2,[]) // A missing terminal record must still release Hyper.
        run.finish(at:2)
        let codes = [kVK_Shift,kVK_Control,kVK_Option,kVK_Command].map(UInt16.init)
        var downs:[UInt16] = [], ups:[UInt16] = [], strokes:[UInt16] = []
        for event in run.output.events {
            switch event.kind {
            case let .key(code,_,down,_): if down { downs.append(code) } else { ups.append(code) }
            case let .keyStroke(code,flags,_):
                strokes.append(code)
                XCTAssertTrue(flags.contains(hyperFlags))
            default: break
            }
        }
        XCTAssertEqual(downs,codes); XCTAssertEqual(ups,codes)
        XCTAssertEqual(strokes,[UInt16(kVK_ANSI_F)])
    }

    func testHyperSharesShiftOwnershipAcrossBothReleaseOrders() {
        for hyperFirst in [true,false] {
            let run = session(labels:["Hyper","Shift","F"])
            frame(run,1,[contact(state:.making)])
            frame(run,1.04,[contact()])
            frame(run,1.06,[contact(),contact(2,key:1,state:.making)])
            frame(run,1.10,[contact(),contact(2,key:1)])
            let survivor = hyperFirst ? contact(2,key:1) : contact()
            let departing = hyperFirst ? contact(state:.breaking) : contact(2,key:1,state:.breaking)
            frame(run,1.14,[survivor,departing])
            let shiftUps = run.output.events.filter {
                if case let .key(code,_,down,_) = $0.kind { return code == UInt16(kVK_Shift) && !down }
                return false
            }
            XCTAssertTrue(shiftUps.isEmpty)
            frame(run,1.18,[survivor,contact(3,key:2,state:.making)])
            frame(run,1.22,[survivor,contact(3,key:2)])
            frame(run,1.24,[survivor,contact(3,key:2,state:.breaking)])
            frame(run,1.28,[])
            run.finish(at:2)
            XCTAssertEqual(run.output.events.filter {
                if case let .key(code,_,down,_) = $0.kind { return code == UInt16(kVK_Shift) && !down }
                return false
            }.count,1)
            let stroke = run.output.events.first { if case .keyStroke = $0.kind { return true }; return false }
            if case let .keyStroke(_,flags,_) = stroke?.kind {
                XCTAssertTrue(flags.contains(hyperFirst ? .maskShift : hyperFlags))
                if hyperFirst { XCTAssertFalse(flags.contains(.maskCommand)) }
            } else { XCTFail("Expected the surviving modifier to apply to F") }
        }
    }

    func testHyperHoldAndResetReleaseEveryModifierWithoutPrimaryTap() {
        for reset in [false,true] {
            let run = session(labels:["F"],allowHold:true)
            let position = GridKeyPosition(side:.left,row:0,column:0).storageKey
            run.engine.updateKeyMappings([0:[position:KeyMapping(primary:KeyActionCatalog.action(for:"F")!,hold:KeyActionCatalog.action(for:"Hyper")!)]])
            run.engine.updateHoldThreshold(0.2)
            frame(run,1,[contact(state:.making)])
            frame(run,1.04,[contact()])
            frame(run,1.3,[contact()])
            if reset { run.engine.resetState() }
            else { frame(run,1.34,[contact(state:.breaking)]); frame(run,1.36,[]) }
            run.finish(at:2)
            XCTAssertEqual(run.output.events.filter { if case .keyStroke = $0.kind { return true }; return false }.count,0)
            for code in [kVK_Shift,kVK_Control,kVK_Option,kVK_Command] {
                XCTAssertEqual(run.output.events.filter {
                    if case let .key(actual,_,down,_) = $0.kind { return actual == UInt16(code) && down }; return false
                }.count,1)
                XCTAssertEqual(run.output.events.filter {
                    if case let .key(actual,_,down,_) = $0.kind { return actual == UInt16(code) && !down }; return false
                }.count,1)
            }
        }
    }
}


extension ProductionEngineTests {
    func testCustomModifierOnlyShortcutHoldsAndReleasesWithoutRepeating() {
        for label in ["Ctrl+Shift+Option+Cmd","Shift+AltGr"] {
            let run = session(labels:[label])
            run.engine.updateHoldRepeatEnabled(true)
            frame(run,1,[contact(state:.making)])
            frame(run,1.04,[contact()])
            frame(run,1.5,[contact()])
            run.scheduler.advance(to:2)
            run.engine.resetState()
            let expected = label == "Shift+AltGr" ? [kVK_Shift,kVK_RightOption] : [kVK_Shift,kVK_Control,kVK_Option,kVK_Command]
            let actual = run.output.events.compactMap { event -> UInt16? in
                if case let .key(code,_,down,_) = event.kind, down { return code }; return nil
            }
            XCTAssertEqual(actual,expected.map(UInt16.init))
            XCTAssertEqual(run.output.events.count,expected.count * 2)
        }
    }
}


extension ProductionEngineTests {
    func testModifierOnlyBuilderAllCombinationsPersistenceAndLegacyLabels() throws {
        XCTAssertEqual(KeyActionCatalog.action(for:"AltGr")?.label,"AltGr")
        XCTAssertEqual(KeyActionCatalog.action(for:"Shift")?.flags,0)
        XCTAssertNil(KeyActionCatalog.shortcutAction(modifiers:[:],keyLabel:""))
        XCTAssertEqual(KeyActionCatalog.shortcutAction(modifiers:[:],keyLabel:"A"),KeyActionCatalog.action(for:"A"))
        let all = ShortcutModifier.ordered
        for mask in 1..<16 {
            let modifiers = Dictionary(uniqueKeysWithValues:all.enumerated().compactMap { index,modifier in
                mask & (1 << index) != 0 ? (modifier,ShortcutModifierVariant.generic) : nil
            })
            let action = try XCTUnwrap(KeyActionCatalog.shortcutAction(modifiers:modifiers,keyLabel:""))
            let spec = try XCTUnwrap(KeyActionCatalog.shortcutSpec(for:action))
            XCTAssertEqual(spec.modifiers,modifiers)
            XCTAssertEqual(spec.keyLabel,"")
            XCTAssertFalse(action.label.hasSuffix("+"))
            let position = GridKeyPosition(side:.left,row:0,column:0).storageKey
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(AppKeymapProfile.defaultProfile())) as? [String:Any])
            object["keyMappingsByLayout"] = try JSONSerialization.jsonObject(with:JSONEncoder().encode(["TouchStream":[0:[position:KeyMapping(primary:action,hold:action)]]]))
            let profile = try JSONDecoder().decode(AppKeymapProfile.self,from:JSONSerialization.data(withJSONObject:object))
            let imported = try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile())
            XCTAssertEqual(imported.keyMappingsByLayout?["TouchStream"]?[0]?[position]?.primary,action)
            XCTAssertEqual(imported.keyMappingsByLayout?["TouchStream"]?[0]?[position]?.hold,action)
        }
        for variant in ShortcutModifierVariant.allCases {
            for modifier in all {
                let action = try XCTUnwrap(KeyActionCatalog.shortcutAction(modifiers:[modifier:variant],keyLabel:""))
                XCTAssertEqual(KeyActionCatalog.action(for:action.label),action)
                XCTAssertEqual(KeyActionCatalog.shortcutSpec(for:action)?.modifiers,[modifier:variant])
            }
        }
        let legacy = try XCTUnwrap(KeyActionCatalog.action(for:"Cmd+Shift"))
        XCTAssertEqual(KeyActionCatalog.shortcutSpec(for:legacy)?.keyLabel,"")
        XCTAssertEqual(KeyActionCatalog.shortcutSpec(for:legacy)?.modifiers,[.command:.generic,.shift:.generic])
        let normal = try XCTUnwrap(KeyActionCatalog.shortcutAction(modifiers:[.command:.generic,.shift:.generic],keyLabel:"S"))
        XCTAssertEqual(normal.keyCode,UInt16(kVK_ANSI_S))
        XCTAssertEqual(KeyActionCatalog.shortcutSpec(for:normal)?.keyLabel,"S")
    }
}


extension ProductionEngineTests {
    func testRunAtStartupPreferenceRoundTripsWithoutRegisteringLoginItems() throws {
        XCTAssertFalse(GlassToKeySettings.runAtStartupEnabled)
        for enabled in [true,false] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(AppKeymapProfile.defaultProfile())) as? [String:Any])
            object["runAtStartupEnabled"] = enabled
            let profile = try JSONDecoder().decode(AppKeymapProfile.self,from:JSONSerialization.data(withJSONObject:object))
            let imported = try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile())
            XCTAssertEqual(imported.runAtStartupEnabled,enabled)
        }
    }
}


extension ProductionEngineTests {
    func testAppTargetsRoundTripInMappingsAndShortcutLibrary() throws {
        for target in ["/Applications/Calculator.app", "/tmp/A folder/notes.txt", "https://example.com/path?q=a%20b"] {
            let action = try XCTUnwrap(KeyActionCatalog.appLaunchAction(fileName:target,arguments:"--example \"two words\""))
            XCTAssertEqual(KeyActionCatalog.action(for:action.label),action)
            let mapping = KeyMapping(primary:action,hold:action)
            let decoded = try JSONDecoder().decode(KeyMapping.self,from:JSONEncoder().encode(mapping))
            XCTAssertEqual(decoded.primary,action)
            XCTAssertEqual(decoded.hold,action)
            let encoded = try XCTUnwrap(ShortcutActionLibraryStorage.encode([action.label]))
            XCTAssertEqual(ShortcutActionLibraryStorage.decode(from:encoded),[action.label])
            XCTAssertEqual(KeyActionCatalog.appLaunchSpec(for:action)?.fileName,target)
            let position = GridKeyPosition(side:.left,row:0,column:0).storageKey
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(AppKeymapProfile.defaultProfile())) as? [String:Any])
            object["keyMappingsByLayout"] = try JSONSerialization.jsonObject(with:JSONEncoder().encode(["TouchStream":[0:[position:mapping]]]))
            object["shortcutActions"] = [action.label]
            let profile = try JSONDecoder().decode(AppKeymapProfile.self,from:JSONSerialization.data(withJSONObject:object))
            let imported = try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile())
            XCTAssertEqual(imported.keyMappingsByLayout?["TouchStream"]?[0]?[position]?.primary,action)
            XCTAssertEqual(imported.keyMappingsByLayout?["TouchStream"]?[0]?[position]?.hold,action)
            XCTAssertEqual(imported.shortcutActions,[action.label])
        }
        XCTAssertNil(KeyActionCatalog.appLaunchAction(fileName:"  "))
    }

    func testAppTargetDispatchesOnceFromPrimaryHoldAndCustomButtonWithoutOpening() throws {
        let action = try XCTUnwrap(KeyActionCatalog.appLaunchAction(fileName:"/Applications/Calculator.app"))
        for source in ["primary", "hold", "custom"] {
            let run = session(allowHold:true)
            let key = GridKeyPosition(side:.left,row:0,column:0).storageKey
            if source == "custom" {
                run.engine.updateCustomButtons([CustomButton(id:UUID(),side:.left,
                    rect:NormalizedRect(x:0.65,y:0.7,width:0.3,height:0.2),action:action,hold:nil)])
            } else {
                run.engine.updateKeyMappings([0:[key:KeyMapping(
                    primary:source == "hold" ? KeyActionCatalog.noneAction : action,
                    hold:source == "hold" ? action : nil)]])
            }
            func touch(_ state:OMSState) -> OMSRawTouch {
                if source != "custom" { return contact(state:state) }
                return OMSRawTouch(id:1,posX:0.8,posY:0.2,total:1,pressure:100,
                    majorAxis:5,minorAxis:3,angle:0,density:1,state:state)
            }
            frame(run,1,[touch(.making)])
            frame(run,1.6,[touch(.touching)])
            frame(run,1.7,[touch(.breaking)])
            frame(run,1.8,[])
            run.finish(at:2)
            let launches = run.output.events.filter {
                if case .appLaunch(action.label) = $0.kind { return true }
                return false
            }
            XCTAssertEqual(launches.count,1,"App target did not fire once from \(source): \(run.output.events)")
            XCTAssertTrue(keys(run).isEmpty)
        }
    }
}


extension ProductionEngineTests {
    func testNamedShortcutsPreserveCommandIdentityAndLegacyLabels() throws {
        for label in ["Cmd+S","Hyper","Shift","Right Option+Left"] {
            let original = try XCTUnwrap(KeyActionCatalog.action(for:label))
            var named = original; named.customName = "My \"shortcut\" + ❤️"
            XCTAssertEqual(named.label,original.label)
            XCTAssertEqual(named.keyCode,original.keyCode)
            XCTAssertEqual(named.flags,original.flags)
            XCTAssertEqual(named.displayText,named.customName)
            XCTAssertEqual(named.pickerText,named.customName)
            XCTAssertEqual(named.holdLabelText,named.customName)
            XCTAssertEqual(named.commandText,original.pickerText)
            XCTAssertEqual(KeyActionCatalog.shortcutSpec(for:named),KeyActionCatalog.shortcutSpec(for:original))
            XCTAssertEqual(GestureShortcutKeyOwnership.keys(for:named),GestureShortcutKeyOwnership.keys(for:original))
            XCTAssertEqual(KeyActionCatalog.action(for:named.storageLabel),named)
            XCTAssertEqual(try JSONDecoder().decode(KeyAction.self,from:JSONEncoder().encode(named)),named)
            XCTAssertEqual(KeyActionCatalog.action(for:original.storageLabel),original)
            let encoded = try XCTUnwrap(ShortcutActionLibraryStorage.encode([original.storageLabel,named.storageLabel,named.storageLabel]))
            XCTAssertEqual(ShortcutActionLibraryStorage.decode(from:encoded),[original.storageLabel,named.storageLabel])
            named.customName = " \n "
            XCTAssertEqual(named.storageLabel,original.label)
            XCTAssertEqual(named.displayText,original.displayText)
        }
        XCTAssertNil(KeyActionCatalog.action(for:"NAMED_SHORTCUT:not json"))
        XCTAssertNil(KeyActionCatalog.action(for:NamedShortcutStorage.label(name:"Bad",command:"not a command")))
        XCTAssertNil(KeyActionCatalog.action(for:NamedShortcutStorage.label(name:"Nested",command:NamedShortcutStorage.label(name:"Inner",command:"Cmd+S"))))
    }
    func testNamedShortcutsRoundTripAcrossKeyboardGesturesAndLibrary() throws {
        for base in [try XCTUnwrap(KeyActionCatalog.action(for:"Cmd+S")),
                     try XCTUnwrap(KeyActionCatalog.appLaunchAction(fileName:"/Applications/Calculator.app",arguments:"--example"))] {
            var action = base; action.customName = "My custom name"
            let position = GridKeyPosition(side:.left,row:0,column:0).storageKey
            let mapping = KeyMapping(primary:action,hold:action)
            let button = CustomButton(id:UUID(),side:.right,rect:NormalizedRect(x:0.1,y:0.1,width:0.2,height:0.2),action:action,hold:action)
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(AppKeymapProfile.defaultProfile())) as? [String:Any])
            object["keyMappingsByLayout"] = try JSONSerialization.jsonObject(with:JSONEncoder().encode(["TouchStream":[0:[position:mapping]]]))
            object["customButtonsByLayout"] = try JSONSerialization.jsonObject(with:JSONEncoder().encode(["TouchStream":[0:[button]]]))
            object["shortcutActions"] = [action.storageLabel]
            var profile = try JSONDecoder().decode(AppKeymapProfile.self,from:JSONSerialization.data(withJSONObject:object))
            var gestures = HandGestureSettings()
            let assigned = GestureAction.shortcut(.init(label:action.storageLabel))
            XCTAssertTrue(gestures.setAction(assigned,for:.twoFingerTap,in:.left))
            if action.kind == .key {
                gestures.setHoldAction(.shortcut(.init(label:action.storageLabel,holdUntilRelease:true)),count:4,in:.right)
            }
            profile.handGestureSettings = gestures
            let imported = try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile())
            XCTAssertEqual(imported.keyMappingsByLayout?["TouchStream"]?[0]?[position],mapping)
            XCTAssertEqual(imported.customButtonsByLayout["TouchStream"]?[0]?.first,button)
            XCTAssertEqual(imported.handGestureSettings,gestures)
            XCTAssertEqual(imported.shortcutActions,[action.storageLabel])
            XCTAssertEqual(imported.handGestureSettings?.action(.twoFingerTap,in:.left)?.title,"My custom name")
            var renamed = action; renamed.customName = "Renamed"
            let edited = ShortcutActionLibraryStorage.replacing(action.storageLabel,with:renamed,in:imported.shortcutActions)
            XCTAssertEqual(edited,[renamed.storageLabel])
            XCTAssertEqual(assigned.title,"My custom name") // assignments remain snapshots
        }
    }
    func testNamedKeyboardShortcutDispatchMatchesUnnamedCommand() throws {
        for name in [nil,"Save document"] as [String?] {
            var action = try XCTUnwrap(KeyActionCatalog.action(for:"Cmd+S")); action.customName = name
            let run = session()
            let key = GridKeyPosition(side:.left,row:0,column:0).storageKey
            run.engine.updateKeyMappings([0:[key:KeyMapping(primary:action,hold:nil)]])
            frame(run,1,[contact(state:.making)])
            frame(run,1.04,[contact(state:.breaking)])
            frame(run,1.05,[])
            run.finish(at:1.2)
            XCTAssertTrue(run.output.events.contains { if case let .keyStroke(code,flags,_) = $0.kind { return code == action.keyCode && flags.rawValue == action.flags }; return false })
        }
    }
    func testShortcutLibraryEditsDeduplicateAndPreserveAssignedActionsThroughExport() throws {
        let original = try XCTUnwrap(KeyActionCatalog.action(for:"Cmd+S"))
        let replacement = try XCTUnwrap(KeyActionCatalog.action(for:"Cmd+O"))
        let saved = [original.label,"Hyper",replacement.label]
        XCTAssertEqual(ShortcutActionLibraryStorage.replacing(original.label,with:replacement,in:saved),[replacement.label,"Hyper"])
        let deleted = ShortcutActionLibraryStorage.removing(original.label,from:saved)
        XCTAssertEqual(deleted,["Hyper",replacement.label])
        XCTAssertEqual(ShortcutActionLibraryStorage.replacing(original.label,with:replacement,in:deleted),deleted)
        let position = GridKeyPosition(side:.left,row:0,column:0).storageKey
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(AppKeymapProfile.defaultProfile())) as? [String:Any])
        object["keyMappingsByLayout"] = try JSONSerialization.jsonObject(with:JSONEncoder().encode(["TouchStream":[0:[position:KeyMapping(primary:original,hold:original)]]]))
        object["shortcutActions"] = deleted
        var profile = try JSONDecoder().decode(AppKeymapProfile.self,from:JSONSerialization.data(withJSONObject:object))
        var gestures = HandGestureSettings()
        let assigned = GestureAction.shortcut(.init(label:original.label))
        XCTAssertTrue(gestures.setAction(assigned,for:.twoFingerTap,in:.left))
        profile.handGestureSettings = gestures
        let imported = try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile())
        XCTAssertEqual(imported.shortcutActions,deleted)
        XCTAssertEqual(imported.keyMappingsByLayout?["TouchStream"]?[0]?[position]?.primary,original)
        XCTAssertEqual(imported.keyMappingsByLayout?["TouchStream"]?[0]?[position]?.hold,original)
        XCTAssertEqual(imported.handGestureSettings?.action(.twoFingerTap,in:.left),assigned)
    }
}

extension ProductionEngineTests {
    func testSavedTextReferencesFireOnceFromPrimaryHoldAndCustomButtonInReplay() throws {
        let action = TextShortcutReference.action(id:UUID())
        for source in ["primary","hold","custom"] {
            let run = session(allowHold:true)
            let key = GridKeyPosition(side:.left,row:0,column:0).storageKey
            if source == "custom" {
                run.engine.updateCustomButtons([CustomButton(id:UUID(),side:.left,
                    rect:NormalizedRect(x:0.65,y:0.7,width:0.3,height:0.2),action:action,hold:nil)])
            } else {
                run.engine.updateKeyMappings([0:[key:KeyMapping(primary:source == "hold" ? KeyActionCatalog.noneAction:action,
                    hold:source == "hold" ? action:nil)]])
            }
            func touch(_ state:OMSState) -> OMSRawTouch {
                source == "custom" ? OMSRawTouch(id:1,posX:0.8,posY:0.2,total:1,pressure:100,
                    majorAxis:5,minorAxis:3,angle:0,density:1,state:state) : contact(state:state)
            }
            frame(run,1,[touch(.making)]); frame(run,1.6,[touch(.touching)])
            frame(run,1.7,[touch(.breaking)]); frame(run,1.8,[]); run.finish(at:2)
            let commands = run.output.events.filter { if case .systemKey(action.label) = $0.kind { return true }; return false }
            XCTAssertEqual(commands.count,1,"Expected a single opaque paste reference from \(source)")
            XCTAssertTrue(keys(run).isEmpty) // No fake key code 0 or native paste in replay.
        }
    }
}
