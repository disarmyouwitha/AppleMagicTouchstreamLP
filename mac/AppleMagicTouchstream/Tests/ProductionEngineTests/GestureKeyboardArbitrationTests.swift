import Carbon
import CoreGraphics
import OpenMultitouchSupport
import XCTest
@testable import GlassToKeyRuntime

@MainActor
final class GestureKeyboardArbitrationTests: XCTestCase {
    private func session() -> ProductionReplaySession {
        let run = ProductionReplaySession(startTime: 1)
        let size = CGSize(width: 160, height: 115)
        let layout = ContentViewModel.Layout(keyRects: [[CGRect(x: 10, y: 40, width: 35, height: 30),
            CGRect(x: 55, y: 40, width: 35, height: 30)]], trackpadSize: size, allowHoldBindings: true)
        run.engine.updateLayouts(leftLayout: layout, rightLayout: layout, leftLabels: [["F", "Shift"]],
            rightLabels: [["F", "Shift"]], trackpadSize: size, trackpadWidthMm: 160)
        run.engine.updateActiveDevices(leftIndex: 0, rightIndex: 1, leftDeviceID: "42", rightDeviceID: "43")
        run.engine.updateKeyboardModeEnabled(true)
        run.engine.updateForceClickMin(0)
        run.engine.updateForceClickCap(1000)
        run.engine.updateHapticStrength(0)
        run.engine.updateSnapRadiusPercent(0)
        run.engine.setListening(true)
        run.engine.setCaptureFrameDiagnosticsEnabled(true)
        return run
    }
    private func touch(_ id: Int32 = 1, shift: Bool = false, state: OMSState = .touching) -> OMSRawTouch {
        OMSRawTouch(id: id, posX: shift ? 72.5 / 160 : 27.5 / 160, posY: 1 - 55 / 115,
            total: 1, pressure: 100, majorAxis: 5, minorAxis: 3, angle: 0, density: 1, state: state)
    }
    @discardableResult
    private func frame(_ run: ProductionReplaySession, _ time: Double, _ touches: [OMSRawTouch],
        side: Int = 0, reserved: Bool = false) -> RuntimeFrameDiagnostic? {
        let diagnostic = run.ingest(RuntimeRawFrame(sequence: UInt64(time * 1000), timestamp: time,
            deviceNumericID: side == 0 ? 42 : 43, deviceIndex: side, contacts: [], rawTouches: touches),
            suppressKeyboard: reserved)
        return diagnostic
    }
    private func keyCodes(_ run: ProductionReplaySession) -> [CGKeyCode] {
        run.output.events.compactMap {
            if case let .keyStroke(code, _, _) = $0.kind { return code }
            return nil
        }
    }
    func testPerPadKeyboardOverrideClearsOnlyItsGestureReservation() {
        var gate = GestureKeyboardArbitration()
        XCTAssertTrue(gate.process(device:42,activeCount:2) {_ in true})
        XCTAssertTrue(gate.process(device:43,activeCount:2) {_ in true})
        gate.reset(device:42)
        XCTAssertFalse(gate.process(device:42,activeCount:1) {_ in false})
        XCTAssertTrue(gate.process(device:43,activeCount:1) {_ in false})
    }

    func testReservationIncludesLiftFrameAndCannotCrossDevices() {
        var gate = GestureKeyboardArbitration()
        XCTAssertFalse(gate.process(device: 42, activeCount: 1) { _ in true })
        XCTAssertTrue(gate.process(device: 42, activeCount: 2) { $0 == .twoFingerTap })
        for count in [1, 3, 4, 5] {
            XCTAssertTrue(gate.process(device: 42, activeCount: count) { _ in false })
        }
        XCTAssertFalse(gate.process(device: 43, activeCount: 1) { _ in true })
        XCTAssertTrue(gate.process(device: 42, activeCount: 0) { _ in false })
        XCTAssertFalse(gate.process(device: 42, activeCount: 1) { _ in true })
        XCTAssertFalse(gate.process(device: 42, activeCount: 2) { _ in false })
    }
    func testEachConfiguredInputReservesItsChordRegardlessOfChosenAction() {
        for trigger in GestureTrigger.allCases where trigger != .fourCornersTap && (!trigger.isRotation || GestureTrigger.liveRotationTriggers.contains(trigger)) {
            // Corner reservation is geometry-aware and runs before this count gate.
            let count = trigger.forceCount ?? trigger.pinchCount ?? trigger.rotationCount ?? ((trigger == .fiveFingerMove || trigger == .fiveFingerTap) ? 5 : (trigger == .fourFingerMove || trigger == .fourFingerTap) ? 4 : (trigger == .twoFingerMove || trigger == .twoFingerTap || trigger == .twoFingerPinch ? 2 : 3))
            var gate = GestureKeyboardArbitration()
            XCTAssertTrue(gate.process(device: 42, activeCount: count, forceClick:trigger.forceCount != nil) { $0 == trigger })
        }
    }
    func testReservedPairCannotTypeOrHoldAndSurvivingFingerStaysSuppressed() {
        let run = session()
        frame(run, 1, [touch(state: .making)])
        let diagnostic = frame(run, 1.03, [touch(), touch(2, shift: true)], reserved: true)
        XCTAssertTrue(diagnostic?.touches.contains { $0.reason == "gestureReserved" } ?? false)
        frame(run, 1.06, [touch()]) // caller no longer requests; engine still latches.
        frame(run, 1.4, [touch()])
        frame(run, 1.45, [touch(state: .breaking)])
        frame(run, 1.46, [])
        run.finish(at: 2)
        XCTAssertTrue(run.output.events.isEmpty)
    }
    func testEstablishedModifierKeepsKeyboardPriorityAndBalancesRelease() {
        let run = session()
        frame(run, 1, [touch(1, shift: true, state: .making)])
        frame(run, 1.03, [touch(1, shift: true), touch(2)], reserved: true)
        frame(run, 1.06, [touch(1, shift: true), touch(2, state: .breaking)], reserved: true)
        frame(run, 1.07, [touch(1, shift: true, state: .breaking)], reserved: true)
        frame(run, 1.08, [])
        run.finish(at: 2)
        let edges = run.output.events.compactMap { event -> Bool? in
            if case let .key(code, _, down, _) = event.kind, code == kVK_Shift { return down }
            return nil
        }
        XCTAssertEqual(edges, [true, false])
        XCTAssertEqual(keyCodes(run), [CGKeyCode(kVK_ANSI_F)])
    }
    func testOtherHandKeepsTypingAndOneFingerWorksAfterReservedCycle() {
        let run = session()
        frame(run, 1, [touch(state: .making)], side: 1)
        frame(run, 1.01, [touch(), touch(2, shift: true)], reserved: true)
        frame(run, 1.03, [touch()], side: 1)
        frame(run, 1.04, [touch(state: .breaking)], side: 1)
        frame(run, 1.05, [], side: 1)
        frame(run, 1.06, [])
        frame(run, 1.1, [touch(state: .making)])
        frame(run, 1.15, [touch(state: .breaking)])
        frame(run, 1.16, [])
        run.finish(at: 2)
        XCTAssertEqual(keyCodes(run), [CGKeyCode(kVK_ANSI_F), CGKeyCode(kVK_ANSI_F)])
    }
}

extension GestureKeyboardArbitrationTests {
    private func rolloverSession() -> ProductionReplaySession {
        let run = session(), size = CGSize(width:160,height:115)
        let rects = [CGPoint(x:98.66,y:39.05),CGPoint(x:80.71,y:36.44),CGPoint(x:57.13,y:44.16)]
            .map { CGRect(x:$0.x-7,y:$0.y-7,width:14,height:14) }
        let layout = ContentViewModel.Layout(keyRects:[rects],trackpadSize:size,allowHoldBindings:false)
        run.engine.updateLayouts(leftLayout:layout,rightLayout:layout,leftLabels:[["L","K","J"]],rightLabels:[["L","K","J"]],trackpadSize:size,trackpadWidthMm:160)
        return run
    }
    private struct RolloverFixture:Decodable { let frames:[RuntimeRawFrame] }
    private func rolloverFrames() throws -> [RuntimeRawFrame] {
        let url = try XCTUnwrap(Bundle.module.url(forResource:"typing-rollover-LKJ",withExtension:"json",subdirectory:"Fixtures"))
        return try JSONDecoder().decode(RolloverFixture.self,from:Data(contentsOf:url)).frames
    }
    // Offline wiring uses the same real recognizers, buffer, decision predicate and
    // keyboard entry point as live ingress; no native event posting or registry access.
    private func exercise(_ frames:[RuntimeRawFrame],run:ProductionReplaySession) -> [(GestureSessionPhase,CGPoint?)] {
        let buffer = PendingKeyboardProposalBuffer()
        var gate = GestureKeyboardArbitration(), router = TrackpadGestureRouter(), tap = TwoFingerTapRecognizer()
        var claimed = false, updates:[(GestureSessionPhase,CGPoint?)] = []
        for f in frames {
            let count = f.rawTouches.filter { $0.state == .making || $0.state == .touching }.count
            let candidate = gate.process(device:42,activeCount:count) { $0 == .twoFingerMove || $0 == .twoFingerTap }
            if buffer.mode == .typing {
                _ = run.engine.processRuntimeRawFrame(f)
            } else {
                let update = router.recognize(device:42,time:f.timestamp,contacts:f.rawTouches,enabled:{$0 == .twoFingerMove})
                updates.append((update.phase,update.millimetres))
                let tapped = tap.process(device:42,time:f.timestamp,contacts:f.rawTouches,gestureActive:update.gesture != nil)
                claimed = claimed || tapped || update.phase == .began || update.phase == .changed
                if candidate || buffer.mode != .idle {
                    if buffer.mode == .idle { buffer.mode = .pending }
                    if claimed || buffer.mode == .gesture {
                        buffer.clear(); buffer.mode = .gesture
                        _ = run.engine.processRuntimeRawFrame(f,suppressKeyboard:true)
                    } else {
                        XCTAssertTrue(buffer.append(sequence:f.sequence,index:f.deviceIndex,time:f.timestamp,touches:f.rawTouches,flags:run.engine.keyboardModifierFlagsSnapshot))
                        if PendingKeyboardProposalBuffer.resolvesToTyping(activeCount:count,tapPending:tap.canStillComplete(device:42)) {
                            buffer.drain { h,t in
                                _ = run.engine.processKeyboardFrame(sequence:h.sequence,deviceIndex:h.index,timestamp:h.time,touches:t,modifierFlags:h.flags)
                            }
                            buffer.mode = .typing
                        }
                    }
                } else { _ = run.engine.processRuntimeRawFrame(f) }
            }
            if count == 0 { buffer.reset(); claimed = false }
        }
        return updates
    }
    func testCapturedRolloverCommitsLThenKThenJInsteadOfDiscardingTheCycle() throws {
        let frames = try rolloverFrames(), direct = rolloverSession(), recovered = rolloverSession(), old = rolloverSession()
        var oldGate = GestureKeyboardArbitration()
        for f in frames {
            _ = direct.engine.processRuntimeRawFrame(f)
            let count = f.rawTouches.filter { $0.state == .making || $0.state == .touching }.count
            let reserved = oldGate.process(device:42,activeCount:count) { $0 == .twoFingerTap || $0 == .twoFingerMove }
            _ = old.engine.processRuntimeRawFrame(f,suppressKeyboard:reserved)
        }
        _ = exercise(frames,run:recovered)
        XCTAssertEqual(keyCodes(direct),[CGKeyCode(kVK_ANSI_L),CGKeyCode(kVK_ANSI_K),CGKeyCode(kVK_ANSI_J)])
        XCTAssertEqual(keyCodes(recovered),keyCodes(direct))
        XCTAssertTrue(keyCodes(old).isEmpty)
    }
    func testTwoFingerMovementRetainsExactActivationAndDeltasAcrossCountChangesWithoutTyping() {
        let run = rolloverSession()
        func contacts(_ count:Int,_ x:Float) -> [OMSRawTouch] {
            (0..<count).map { i in OMSRawTouch(id:Int32(i+1),posX:x+Float(i)*0.15,posY:0.6,total:1,pressure:40,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching) }
        }
        let samples:[(Int,Float)] = [(2,0.3),(2,0.301),(2,0.304),(1,0.305),(3,0.306),(4,0.307),(2,0.308),(0,0)]
        let frames = samples.enumerated().map { i,s in RuntimeRawFrame(sequence:UInt64(i),timestamp:1+Double(i)*0.011,deviceNumericID:42,deviceIndex:0,contacts:[],rawTouches:contacts(s.0,s.1)) }
        var baseline = TrackpadGestureRouter()
        let expected = frames.map { baseline.recognize(device:42,time:$0.timestamp,contacts:$0.rawTouches,enabled:{$0 == .twoFingerMove}) }
        let actual = exercise(frames,run:run)
        XCTAssertEqual(actual.count,expected.count)
        for (a,b) in zip(actual,expected) { XCTAssertEqual(a.0,b.phase); XCTAssertEqual(a.1,b.millimetres) }
        XCTAssertEqual(actual.firstIndex(where:{$0.0 == .began}),2)
        // Golden trace from the accepted stable-pair/latch behavior before this fix.
        XCTAssertEqual(actual.map(\.0),[.pending,.pending,.began,.changed,.changed,.changed,.changed,.ended])
        XCTAssertEqual(actual[2].1?.x ?? 0,0.64,accuracy:0.0001)
        for index in 3...6 { XCTAssertEqual(actual[index].1?.x ?? 0,0.16,accuracy:0.0001) }
        XCTAssertTrue(keyCodes(run).isEmpty)
    }
    func testValidTwoFingerTapOverKeysDoesNotAlsoTypeAndSingleTapsStayDirect() throws {
        let frames = try rolloverFrames(), run = rolloverSession()
        let pair = [frames[0].rawTouches[0],frames[4].rawTouches.first(where:{$0.id == 2})!]
        let chord = (0...6).map { i in RuntimeRawFrame(sequence:UInt64(i),timestamp:1+Double(i)*0.011,deviceNumericID:42,deviceIndex:0,contacts:[],rawTouches:i == 6 ? [] : pair) }
        _ = exercise(chord,run:run)
        XCTAssertTrue(keyCodes(run).isEmpty)
        let direct = rolloverSession()
        let taps = [frames[0],RuntimeRawFrame(sequence:99,timestamp:1.04,deviceNumericID:42,deviceIndex:0,contacts:[],rawTouches:[])]
        _ = exercise(taps,run:direct)
        XCTAssertEqual(keyCodes(direct),[CGKeyCode(kVK_ANSI_L)])
    }
    func testProposalStorageCopiesContactsAndCancelsOverflowInvalidInputAndReset() throws {
        let bank = PendingKeyboardProposalBuffer()
        var contacts = [touch()]
        XCTAssertTrue(bank.append(sequence:1,index:0,time:1,touches:contacts))
        contacts[0] = touch(9)
        bank.drain { _,retained in XCTAssertEqual(retained.first?.id,1) }
        for i in 0..<PendingKeyboardProposalBuffer.capacity {
            XCTAssertTrue(bank.append(sequence:UInt64(i),index:0,time:1+Double(i)*0.01,touches:contacts))
        }
        XCTAssertFalse(bank.append(sequence:9999,index:0,time:12,touches:contacts))
        XCTAssertEqual(bank.mode,.gesture)
        bank.drain { _,_ in XCTFail("Cancelled proposals must not be emitted") }
        bank.reset(); XCTAssertEqual(bank.mode,.idle)
        XCTAssertFalse(bank.append(sequence:1,index:0,time:.nan,touches:contacts))
        bank.reset()
        XCTAssertFalse(bank.append(sequence:1,index:0,time:1,touches:[touch(),touch()]))
        bank.reset(); XCTAssertTrue(bank.append(sequence:2,index:0,time:2,touches:contacts))
    }
    func testRetiredTypingGraceImportsWithoutReturningInExports() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(AppKeymapProfile.defaultProfile())) as? [String:Any])
        object["typingGraceMs"] = 600
        let profile = try JSONDecoder().decode(AppKeymapProfile.self,from:JSONSerialization.data(withJSONObject:object))
        let exported = try PortableKeymapInterop.exportBundle(from:profile)
        let text = String(decoding:exported,as:UTF8.self)
        XCTAssertFalse(text.contains("TypingGraceMs")); XCTAssertFalse(text.contains("typingGraceMs"))
        var legacyBundle = try XCTUnwrap(JSONSerialization.jsonObject(with:exported) as? [String:Any])
        var settings = legacyBundle["Settings"] as? [String:Any] ?? [:]
        settings["TypingGraceMs"] = 600; legacyBundle["Settings"] = settings
        let imported = try PortableKeymapInterop.importProfile(from:JSONSerialization.data(withJSONObject:legacyBundle),currentProfile:.defaultProfile())
        let reexported = String(decoding:try PortableKeymapInterop.exportBundle(from:imported),as:UTF8.self)
        XCTAssertFalse(reexported.contains("TypingGraceMs"))
    }
}

extension GestureKeyboardArbitrationTests {
    func testRetainedTypingPreservesOtherPadShiftEvenIfItLiftsBeforeResolution() throws {
        let run = rolloverSession(), bank = PendingKeyboardProposalBuffer()
        let shiftPosition = GridKeyPosition(side:.right,row:0,column:0).storageKey
        run.engine.updateKeyMappings([0:[shiftPosition:KeyMapping(primary:try XCTUnwrap(KeyActionCatalog.action(for:"Shift")),hold:nil)]])
        let shift = OMSRawTouch(id:99,posX:98.66/160,posY:1-39.05/115,total:1,pressure:40,majorAxis:5,minorAxis:3,angle:0,density:1,state:.making)
        _ = run.engine.processRuntimeRawFrame(.init(sequence:1,timestamp:1,deviceNumericID:43,deviceIndex:1,contacts:[],rawTouches:[shift]))
        let flags = run.engine.keyboardModifierFlagsSnapshot
        XCTAssertNotEqual(flags & CGEventFlags.maskShift.rawValue,0)
        let frames = try rolloverFrames()
        XCTAssertTrue(bank.append(sequence:2,index:0,time:1.01,touches:frames[0].rawTouches,flags:flags))
        XCTAssertTrue(bank.append(sequence:3,index:0,time:1.05,touches:[OMSRawTouch](),flags:flags))
        _ = run.engine.processRuntimeRawFrame(.init(sequence:4,timestamp:1.06,deviceNumericID:43,deviceIndex:1,contacts:[],rawTouches:[]))
        XCTAssertEqual(run.engine.keyboardModifierFlagsSnapshot,0)
        bank.drain { h,t in _ = run.engine.processKeyboardFrame(sequence:h.sequence,deviceIndex:h.index,timestamp:h.time,touches:t,modifierFlags:h.flags) }
        let strokes = run.output.events.compactMap { event -> CGEventFlags? in
            if case let .keyStroke(_,flags,_) = event.kind { return flags }; return nil
        }
        XCTAssertEqual(strokes.count,1)
        XCTAssertTrue(strokes.first?.contains(.maskShift) == true)
        XCTAssertEqual(run.engine.keyboardModifierFlagsSnapshot,0)
    }
}

extension GestureKeyboardArbitrationTests {
    func testCommittedOrdinaryKeyHoldRetainsItsPadAgainstLaterGestureCandidates() throws {
        let run = session()
        let position = GridKeyPosition(side:.left,row:0,column:0).storageKey
        run.engine.updateKeyMappings([0:[position:KeyMapping(primary:try XCTUnwrap(KeyActionCatalog.action(for:"F")),hold:try XCTUnwrap(KeyActionCatalog.action(for:"G")))]])
        frame(run,1,[touch(state:.making)])
        frame(run,1.3,[touch()])
        XCTAssertEqual(keyCodes(run),[CGKeyCode(kVK_ANSI_G)])
        XCTAssertTrue(run.engine.keyboardChordOwnsCycle(deviceIndex:0))
        frame(run,1.31,[touch(),touch(2,shift:true)],reserved:true)
        frame(run,1.34,[],reserved:true)
        XCTAssertEqual(keyCodes(run),[CGKeyCode(kVK_ANSI_G)])
        XCTAssertFalse(run.engine.keyboardChordOwnsCycle(deviceIndex:0))
    }
}
