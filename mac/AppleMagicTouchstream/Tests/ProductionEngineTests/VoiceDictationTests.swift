import AppKit
import Carbon
import OpenMultitouchSupport
import XCTest
@testable import GlassToKeyRuntime

final class VoiceDictationSessionTests: XCTestCase {
    func testToggleSessionCollectsChunksAndCommitsExactlyOnce() {
        var state = VoiceDictationSession()
        let token = state.begin()
        XCTAssertTrue(state.authorized(token))
        let first = state.nextChunk()
        XCTAssertTrue(state.receive("hello", token: token, chunk: first))
        XCTAssertTrue(state.receive("hello world", token: token, chunk: first))
        state.commitChunk()
        let second = state.nextChunk()
        XCTAssertFalse(state.receive("old callback", token: token, chunk: first))
        XCTAssertTrue(state.receive("second phrase", token: token, chunk: second))
        XCTAssertEqual(state.finish(), token)
        XCTAssertTrue(state.receive("second phrase finished", token: token, chunk: second))
        XCTAssertEqual(state.complete(token), "hello world second phrase finished")
        XCTAssertNil(state.complete(token))
        XCTAssertFalse(state.active)
    }

    func testCancellationRejectsPendingPermissionResultsTranscriptsAndFinalCommit() {
        var state = VoiceDictationSession()
        let first = state.begin()
        state.cancel()
        XCTAssertFalse(state.authorized(first))
        let token = state.begin()
        XCTAssertTrue(state.authorized(token))
        let chunk = state.nextChunk()
        _ = state.receive("do not insert", token: token, chunk: chunk)
        _ = state.finish()
        state.cancel()
        XCTAssertNil(state.complete(token))
        XCTAssertFalse(state.receive("late", token: token, chunk: chunk))
        let next = state.begin()
        XCTAssertNotEqual(next, token)
        XCTAssertFalse(state.authorized(token))
        XCTAssertTrue(state.authorized(next))
        _ = state.finish()
        XCTAssertEqual(state.complete(next), "")
    }

    @MainActor func testVoiceCatalogAndGestureAssignmentsRoundTrip() throws {
        for label in ["Voice", "VOICE"] { XCTAssertEqual(KeyActionCatalog.action(for: label)?.kind, .voice) }
        XCTAssertTrue(KeyActionCatalog.primaryActionGroups.flatMap(\.actions).contains { $0.kind == .voice })
        XCTAssertTrue(GestureActionChooser.groups([.voice]).flatMap(\.actions).contains(.voice))
        var settings = HandGestureSettings()
        settings.setAction(.voice, for: .twoFingerTap, in: .left)
        settings.setAction(.voice, for: .oneFingerForce, in: .right)
        settings.setHoldAction(.voice, count: 4, in: .left)
        var both = settings.twoHand
        both.setAction(.voice, for: .init(chord: .fourCorners, phase: .hold))
        settings.coordinated = both
        var profile = AppKeymapProfile.defaultProfile()
        profile.handGestureSettings = settings
        let restored = try PortableKeymapInterop.importProfile(from: PortableKeymapInterop.exportBundle(from: profile), currentProfile: .defaultProfile())
        XCTAssertEqual(restored.handGestureSettings, settings)
        XCTAssertTrue(GestureTrigger.twoFingerTap.accepts(.voice))
        XCTAssertTrue(GestureTrigger.oneFingerForce.accepts(.voice))
        XCTAssertTrue(GestureAction.voice.isDiscreteOutput)
        XCTAssertFalse(GestureAction.voice.isAppleShortcut)
    }
}

@MainActor final class AutocorrectEditorThreadTests: XCTestCase {
    func testWorkerTextAccessEntersAppKitEditorOnMainThread() async {
        // Reproduce the failing operation without posting input or opening a
        // window. The crash reports ended in NSTextView selection from worker AX.
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        editor.string = "teh "
        await Task.detached {
            await withCheckedContinuation { continuation in
                AutocorrectTextAccess.enqueue {
                    XCTAssertTrue(Thread.isMainThread)
                    editor.setSelectedRange(NSRange(location: 0, length: 3))
                    editor.insertText("the", replacementRange: editor.selectedRange())
                    editor.setSelectedRange(NSRange(location: 4, length: 0))
                    continuation.resume()
                }
            }
        }.value
        XCTAssertEqual(editor.string, "the ")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 4, length: 0))
    }
}

@MainActor final class VoiceKeyboardTests: XCTestCase {
    func testKeyPrimaryAndHoldDispatchVoiceWithoutStartingRecognition() throws {
        for held in [false, true] {
            let run = ProductionReplaySession(startTime: 1)
            let size = CGSize(width: 160, height: 115)
            let layout = ContentViewModel.Layout(keyRects: [[CGRect(x: 40, y: 40, width: 20, height: 20)]],
                trackpadSize: size, allowHoldBindings: true)
            run.engine.updateLayouts(leftLayout: layout, rightLayout: layout, leftLabels: [[held ? "F" : "Voice"]], rightLabels: [["F"]],
                trackpadSize: size, trackpadWidthMm: 160)
            run.engine.updateActiveDevices(leftIndex: 0, rightIndex: 1, leftDeviceID: "42", rightDeviceID: "43")
            if held {
                let key = GridKeyPosition(side: .left, row: 0, column: 0).storageKey
                run.engine.updateKeyMappings([0: [key: KeyMapping(primary: try XCTUnwrap(KeyActionCatalog.action(for: "F")),
                    hold: try XCTUnwrap(KeyActionCatalog.action(for: "Voice")))]])
            }
            run.engine.updateKeyboardModeEnabled(true)
            run.engine.updateHoldThreshold(0.2)
            run.engine.updateHapticStrength(0)
            run.engine.updateSnapRadiusPercent(0)
            run.engine.setListening(true)
            for (time, state) in [(1.0, OMSState.making), (held ? 1.25 : 1.02, .touching), (held ? 1.3 : 1.04, .breaking)] {
                let touch = OMSRawTouch(id: 1, posX: 50.0 / 160, posY: 1 - 50.0 / 115, total: 1, pressure: 100,
                    majorAxis: 5, minorAxis: 3, angle: 0, density: 1, state: state)
                run.ingest(RuntimeRawFrame(sequence: UInt64(time * 1000), timestamp: time,
                    deviceNumericID: 42, deviceIndex: 0, contacts: [], rawTouches: [touch]))
            }
            run.finish(at: 2)
            let toggles = run.output.events.filter { if case .systemKey("voiceToggle") = $0.kind { return true }; return false }
            XCTAssertEqual(toggles.count, 1, "held=\(held)")
            XCTAssertFalse(run.output.events.contains { if case .keyStroke = $0.kind { return true }; return false })
            let encoded = try JSONEncoder().encode(try XCTUnwrap(toggles.first))
            let decoded = try JSONDecoder().decode(RuntimeDispatchEvent.self, from: encoded)
            if case .systemKey("voiceToggle") = decoded.kind {} else { XCTFail("Voice capture did not round-trip") }
        }
    }
}
