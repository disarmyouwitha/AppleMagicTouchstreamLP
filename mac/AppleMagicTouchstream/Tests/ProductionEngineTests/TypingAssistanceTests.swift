import Carbon
import CoreGraphics
import OpenMultitouchSupport
import XCTest
@testable import GlassToKeyRuntime

final class AutocorrectSessionTests: XCTestCase {
    private func event(_ code: Int, flags: CGEventFlags = [], alternative: UInt8 = 0) -> KeySemanticEvent {
        KeySemanticMapper.semanticEvent(code: CGKeyCode(code), flags: flags, timestampNs: 1, altAscii: alternative) ?? .empty
    }
    private func type(_ text: String, into session: inout AutocorrectSession) -> AutocorrectSession.Candidate? {
        var result: AutocorrectSession.Candidate?
        for stroke in KeySemanticMapper.keyStrokes(for: text)! {
            result = session.consume(event(Int(stroke.code), flags: stroke.flags)) ?? result
        }
        return result
    }

    func testWordBoundaryContextAndBackspace() throws {
        var session = AutocorrectSession()
        XCTAssertEqual(type("the ", into: &session)?.word, "the")
        _ = type("tehx", into: &session)
        XCTAssertNil(session.consume(event(kVK_Delete)))
        let candidate = try XCTUnwrap(session.consume(event(kVK_Space)))
        XCTAssertEqual(candidate.word, "teh")
        XCTAssertEqual(candidate.context, "the teh")
        XCTAssertEqual(candidate.range, NSRange(location: 4, length: 3))
        XCTAssertEqual(candidate.boundary, 32)
        XCTAssertTrue(session.isStartingWord)
    }

    func testCommandsNavigationAndResetCannotCorrectEarlierText() {
        for cancellation in [event(kVK_ANSI_S, flags: .maskCommand), event(kVK_LeftArrow),
                             event(kVK_Return, flags: .maskControl), KeySemanticEvent.empty] {
            var session = AutocorrectSession()
            _ = type("teh", into: &session)
            XCTAssertNil(session.consume(cancellation))
            XCTAssertNil(session.consume(event(kVK_Space)))
        }
        var session = AutocorrectSession()
        _ = type("teh", into: &session); session.reset()
        XCTAssertNil(session.consume(event(kVK_Space)))
    }

    func testShortWordsCapsAndIdentifiersStayUnchanged() {
        for word in ["te", "TEH", "test1", "test_word", String(repeating: "x", count: 65)] {
            var session = AutocorrectSession()
            XCTAssertNil(type(word + " ", into: &session), word)
            XCTAssertEqual(type("teh ", into: &session)?.word, "teh")
        }
    }

    func testSnapAlternativesOnlyAllowObservedKeyAmbiguity() throws {
        var session = AutocorrectSession()
        _ = session.consume(event(kVK_ANSI_T))
        _ = session.consume(event(kVK_ANSI_E, alternative: 104)) // e or h
        _ = session.consume(event(kVK_ANSI_H, alternative: 101)) // h or e
        let candidate = try XCTUnwrap(session.consume(event(kVK_Space)))
        XCTAssertTrue(candidate.acceptsAlternative("the"))
        XCTAssertFalse(candidate.acceptsAlternative("tie"))
        XCTAssertFalse(candidate.acceptsAlternative("they"))
        XCTAssertFalse(candidate.acceptsAlternative("teh"))
        var short = AutocorrectSession()
        _ = short.consume(event(kVK_ANSI_T))
        _ = short.consume(event(kVK_ANSI_E, alternative: 111))
        XCTAssertNotNil(short.consume(event(kVK_Space)))
    }

    func testBackspacingAcrossBoundaryDoesNotCorrectWordSuffix() {
        var session = AutocorrectSession()
        _ = type("other ", into: &session)
        _ = session.consume(event(kVK_Delete))
        XCTAssertNil(type("teh ", into: &session))
        XCTAssertEqual(type("teh ", into: &session)?.word, "teh")
    }

    func testReplacementRequiresExactCompleteWordAndDelimiterAtCaret() {
        func range(_ prefix: String, caret: Int? = nil, boundary: UInt8 = 32) -> CFRange? {
            VerifiedAutocorrectReplacement.replacementRange(prefix: prefix, caret: caret ?? prefix.utf16.count,
                word: "teh", boundary: boundary)
        }
        XCTAssertEqual(range("hello teh ")?.location, 6)
        XCTAssertEqual(range("teh ")?.length, 3)
        XCTAssertEqual(range("🙂 teh ")?.location, 3) // AX uses UTF-16 offsets.
        XCTAssertNotNil(range("teh,", boundary: 44))
        XCTAssertNil(range("teh"))
        XCTAssertNil(range("the "))
        XCTAssertNil(range("otherteh "))
        XCTAssertNil(range("other_teh "))
        XCTAssertNil(range("teh next"))
        XCTAssertNil(range("teh ", caret: 3))
    }

    func testFallbackReplacesWholeWordAndPreservesDelimiter() throws {
        for boundary: UInt8 in [32, 44, 46] {
            let plan = try XCTUnwrap(AutocorrectFallbackPlan(word: "teh", boundary: boundary, correction: "the"))
            XCTAssertEqual(plan.deleteCount, 4)
            XCTAssertEqual(plan.text, "the" + String(UnicodeScalar(boundary)))
            let events = try XCTUnwrap(plan.events())
            XCTAssertEqual(events.count, 16)
            for index in stride(from: 0, to: events.count, by: 2) {
                XCTAssertEqual(events[index].type, .keyDown)
                XCTAssertEqual(events[index + 1].type, .keyUp)
                XCTAssertTrue(events[index].flags.isEmpty)
                XCTAssertTrue(events[index + 1].flags.isEmpty)
            }
            for event in events.prefix(8) {
                XCTAssertEqual(event.getIntegerValueField(.keyboardEventKeycode), Int64(kVK_Delete))
            }
            var text = ""
            for event in events.dropFirst(8) where event.type == .keyDown {
                var count = 0
                var units = [UniChar](repeating: 0, count: 16)
                event.keyboardGetUnicodeString(maxStringLength: units.count, actualStringLength: &count, unicodeString: &units)
                text += String(decoding: units.prefix(count), as: UTF16.self)
            }
            XCTAssertEqual(text, plan.text)
        }
    }

    func testFallbackNeverErasesSubmittingOrFocusChangingDelimiters() {
        for boundary: UInt8 in [9, 10, 13, 0, 127] {
            XCTAssertNil(AutocorrectFallbackPlan(word: "teh", boundary: boundary, correction: "the"))
        }
        for word in ["", "a", String(repeating: "x", count: 65), "café"] {
            XCTAssertNil(AutocorrectFallbackPlan(word: word, boundary: 32, correction: "the"))
        }
        for correction in ["", "hello\nworld", String(repeating: "x", count: 129)] {
            XCTAssertNil(AutocorrectFallbackPlan(word: "teh", boundary: 32, correction: correction))
        }
        XCTAssertNotNil(AutocorrectFallbackPlan(word: "cafe", boundary: 32, correction: "café"))
    }

    func testPendingCorrectionInvalidatesOnLaterKeysDisableResetAndOverflow() throws {
        var input = AutocorrectInputBuffer(capacity: 2)
        input.enqueue(event(kVK_ANSI_T))
        XCTAssertEqual(input.count, 0)
        input.setEnabled(true)
        input.enqueue(event(kVK_ANSI_T))
        let first = input.pop()
        XCTAssertTrue(first.reset)
        let generation = try XCTUnwrap(first.entry).generation
        XCTAssertTrue(input.isCurrent(generation))
        input.enqueue(event(kVK_Space))
        XCTAssertFalse(input.isCurrent(generation))
        let boundary = try XCTUnwrap(input.pop().entry).generation
        XCTAssertTrue(input.isCurrent(boundary))
        input.setEnabled(true) // Opening config must not clear an active word.
        XCTAssertTrue(input.isCurrent(boundary))
        input.clear()
        XCTAssertFalse(input.isCurrent(boundary))
        XCTAssertTrue(input.pop().reset)
        for _ in 0..<3 { input.enqueue(event(kVK_ANSI_E)) }
        XCTAssertEqual(input.count, 1)
        XCTAssertTrue(input.pop().reset)
        input.enqueue(event(kVK_Space))
        let pending = input.generation
        input.setEnabled(false)
        XCTAssertFalse(input.isCurrent(pending))
        XCTAssertNil(input.pop().entry)
    }
}

@MainActor
final class SnapRadiusTests: XCTestCase {
    private func session(radius: Double) -> ProductionReplaySession {
        let run = ProductionReplaySession(startTime: 1)
        let size = CGSize(width: 160, height: 115)
        let layout = ContentViewModel.Layout(keyRects: [[CGRect(x: 40, y: 40, width: 20, height: 20)]], trackpadSize: size)
        run.engine.updateLayouts(leftLayout: layout, rightLayout: layout, leftLabels: [["F"]], rightLabels: [["F"]],
            trackpadSize: size, trackpadWidthMm: 160)
        run.engine.updateActiveDevices(leftIndex: 0, rightIndex: 1, leftDeviceID: "42", rightDeviceID: "43")
        run.engine.updateKeyboardModeEnabled(true)
        run.engine.updateHapticStrength(0)
        run.engine.updateSnapRadiusPercent(radius)
        run.engine.setListening(true)
        return run
    }

    private func tap(_ run: ProductionReplaySession, x: Float, side: Int = 0, reserved: Bool = false,
                     duration: Double = 0.08, missingLift: Bool = false, start: Double = 1) {
        var samples: [(Double, OMSState)] = [(start, .making), (start + duration / 2, .touching)]
        if !missingLift { samples.append((start + duration, .breaking)); samples.append((start + duration + 0.01, .leaving)) }
        for (time, state) in samples {
            let touch = OMSRawTouch(id: 1, posX: x / 160, posY: 1 - 50.0 / 115.0, total: 1,
                pressure: 100, majorAxis: 5, minorAxis: 3, angle: 0, density: 1, state: state)
            run.ingest(RuntimeRawFrame(sequence: UInt64(time * 1000), timestamp: time,
                deviceNumericID: side == 0 ? 42 : 43, deviceIndex: side, contacts: [], rawTouches: [touch]), suppressKeyboard: reserved)
        }
        run.ingest(RuntimeRawFrame(sequence: UInt64((start + duration + 0.02) * 1000), timestamp: start + duration + 0.02, deviceNumericID: side == 0 ? 42 : 43,
            deviceIndex: side, contacts: [], rawTouches: []), suppressKeyboard: reserved)
    }

    private func typedKeys(_ run: ProductionReplaySession) -> [UInt16] {
        run.output.events.compactMap { if case let .keyStroke(code, _, _) = $0.kind { return code }; return nil }
    }

    func testNearMissSnapsOnlyWhenEnabledOnBothPadsWithoutDuplicating() {
        for side in [0, 1] {
            for radius in [0.0, 35, 100] {
                let run = session(radius: radius)
                tap(run, x: 65, side: side) // 5 mm outside key, 15 mm from center.
                XCTAssertEqual(typedKeys(run), radius == 100 ? [UInt16(kVK_ANSI_F)] : [], "side=\(side), radius=\(radius)")
                run.finish(at: 2)
                XCTAssertEqual(typedKeys(run), radius == 100 ? [UInt16(kVK_ANSI_F)] : [])
            }
        }
    }

    func testDirectHitAndOutOfRadiusStayUnchanged() {
        for radius in [0.0, 100] {
            let direct = session(radius: radius); tap(direct, x: 50)
            XCTAssertEqual(typedKeys(direct), [UInt16(kVK_ANSI_F)])
            let distant = session(radius: radius); tap(distant, x: 80)
            XCTAssertTrue(typedKeys(distant).isEmpty)
        }
    }

    func testGestureReservedNearMissNeverTypes() {
        let run = session(radius: 100); tap(run, x: 65, reserved: true)
        XCTAssertTrue(typedKeys(run).isEmpty)
    }

    func testNearMissUsesOriginalTapDurationAndHandlesMissingLift() {
        for missing in [false, true] {
            let short = session(radius: 100); tap(short, x: 65, missingLift: missing)
            XCTAssertEqual(typedKeys(short), [UInt16(kVK_ANSI_F)])
            let held = session(radius: 100); tap(held, x: 65, duration: 1, missingLift: missing)
            XCTAssertTrue(typedKeys(held).isEmpty)
        }
    }

    func testSnapSettingChangesRebuildCachedRadius() {
        let enabled = session(radius: 0)
        enabled.engine.updateSnapRadiusPercent(100)
        tap(enabled, x: 65)
        XCTAssertEqual(typedKeys(enabled), [UInt16(kVK_ANSI_F)])
        let disabled = session(radius: 100)
        disabled.engine.updateSnapRadiusPercent(0)
        tap(disabled, x: 65)
        XCTAssertTrue(typedKeys(disabled).isEmpty)
    }

    func testSnappedReleaseDoesNotBlockReusedContactIDOrDuplicateTerminalRecords() {
        for missing in [false, true] {
            let run = session(radius: 100)
            tap(run, x: 65, missingLift: missing)
            tap(run, x: 65, missingLift: missing, start: 1.2)
            tap(run, x: 50, start: 1.4)
            XCTAssertEqual(typedKeys(run), [UInt16(kVK_ANSI_F), UInt16(kVK_ANSI_F), UInt16(kVK_ANSI_F)])
        }
    }

    func testTypingAssistancePortableSettingsRoundTripWithLegacyFields() throws {
        for enabled in [false, true] {
            for radius in [0.0, 35, 100] {
                var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(AppKeymapProfile.defaultProfile())) as? [String: Any])
                json["autocorrectEnabled"] = enabled
                json["snapRadiusPercent"] = radius
                let profile = try JSONDecoder().decode(AppKeymapProfile.self, from: JSONSerialization.data(withJSONObject: json))
                let restored = try PortableKeymapInterop.importProfile(from: PortableKeymapInterop.exportBundle(from: profile), currentProfile: .defaultProfile())
                XCTAssertEqual(restored.autocorrectEnabled, enabled)
                XCTAssertEqual(restored.snapRadiusPercent, radius)
            }
        }
    }
}
