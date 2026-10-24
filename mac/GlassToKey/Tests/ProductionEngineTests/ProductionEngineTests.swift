import Carbon
import CoreGraphics
import Foundation
import OpenMultitouchSupport
import XCTest
@testable import GlassToKeyRuntime

@MainActor
final class ProductionEngineTests: XCTestCase {
    private func session(labels: [String] = ["F", "Shift", "G"], keyboardOnly: Bool = true, allowHold: Bool = false) -> ProductionReplaySession {
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
                       side: Int = 0) -> RuntimeFrameDiagnostic? {
        session.ingest(RuntimeRawFrame(sequence: UInt64((time * 1000).rounded()), timestamp: time,
                                       deviceNumericID: side == 0 ? 42 : 43, deviceIndex: side,
                                       contacts: [], rawTouches: contacts))
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

    func testDragCancelsTap() async {
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

    func testScheduledTypingGraceExpiresWithoutMoreInputFrames() async {
        let run = session(keyboardOnly: false)
        frame(run, 1.00, [contact(state: .making)])
        frame(run, 1.04, [contact()])
        frame(run, 1.08, [contact(state: .breaking)])
        frame(run, 1.10, [])
        let before = keys(run)
        XCTAssertEqual(run.output.intents.left, .typing)
        run.scheduler.advance(to: 2)
        XCTAssertEqual(keys(run), before)
        XCTAssertEqual(run.output.intents.left, .idle)
    }

    func testTwoFingerMotionSuppressesTyping() async {
        let run = session(keyboardOnly: false)
        frame(run, 1.00, [contact(1, state: .making), contact(2, key: 2, state: .making)])
        frame(run, 1.04, [contact(1), contact(2, key: 2)])
        frame(run, 1.08, [contact(1, x: 0.28), contact(2, key: 2, x: 0.84)])
        frame(run, 1.12, [contact(1, state: .breaking, x: 0.28),
                          contact(2, key: 2, state: .breaking, x: 0.84)])
        frame(run, 1.14, [])
        run.finish(at: 2)
        XCTAssertTrue(keys(run).isEmpty, "A multi-finger movement must not leak F/G taps")
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
