import Carbon
import XCTest
@testable import GlassToKeyRuntime

@MainActor final class ShortcutMenuTests: XCTestCase {
    func testEmptyLibraryHasScreenshotVoiceEmojiButNoInjectedModifiers() {
        let actions = KeyActionCatalog.shortcutMenuActions(savedLabels: [])
        XCTAssertEqual(actions.map(\.pickerText), ["Screenshot", "Voice", "Emoji"])
        let gestures = GestureActionChooser.shortcutActions(GestureTrigger.twoFingerTap.allowedActions, savedLabels: [])
        XCTAssertEqual(gestures.map(\.title), ["Screenshot", "Voice", "Emoji"])
        for modifier in ["Shift", "Ctrl", "Option", "Cmd", "Hyper"] {
            let saved = GestureActionChooser.shortcutActions(GestureTrigger.twoFingerTap.allowedActions, savedLabels: [modifier])
            XCTAssertEqual(saved.filter { $0.shortcutAssignment?.label == modifier }.count, 1)
            XCTAssertEqual(KeyActionCatalog.shortcutMenuActions(savedLabels: [modifier]).filter { $0.label == modifier }.count, 1)
        }
    }

    func testBuiltinsShareShortcutsSectionWithoutDuplicatingSavedEntries() throws {
        let saved = ["Shift+Cmd+4", "VOICE", "Emoji", "Cmd+S"]
        let actions = KeyActionCatalog.shortcutMenuActions(savedLabels: saved)
        XCTAssertEqual(actions.filter { $0.kind == .voice }.count, 1)
        XCTAssertEqual(actions.filter { $0.label == "Emoji" }.count, 1)
        XCTAssertEqual(actions.filter { $0.pickerText == "Screenshot" }.count, 1)
        XCTAssertTrue(actions.contains { $0.label == "Cmd+S" })
        XCTAssertEqual(actions.first { $0.label == "Emoji" }?.keyCode, UInt16(kVK_Function))
        XCTAssertFalse(KeyActionCatalog.primaryActionGroups.flatMap(\.actions).contains { $0.kind == .voice })

        let gestures = GestureActionChooser.shortcutActions(GestureTrigger.twoFingerTap.allowedActions, savedLabels: saved)
        XCTAssertEqual(gestures.filter { $0 == .voice }.count, 1)
        XCTAssertEqual(gestures.filter { $0.shortcutAssignment?.label == "Emoji" }.count, 1)
        XCTAssertTrue(gestures.contains { $0.shortcutAssignment?.action?.pickerText == "Screenshot" })
        XCTAssertFalse(GestureActionChooser.groups(GestureAction.allCases).flatMap(\.actions).contains(.voice))
        // Moving the menu entry does not make continuous movement invoke Voice.
        let movement = GestureActionChooser.shortcutActions(GestureTrigger.twoFingerMove.allowedActions, savedLabels: saved)
        XCTAssertFalse(movement.contains(.voice))
        XCTAssertTrue(movement.contains { $0.shortcutAssignment?.label == "Emoji" })

        var profile = AppKeymapProfile.defaultProfile()
        var settings = HandGestureSettings()
        settings.setAction(.shortcut(.init(label: "Emoji")), for: .twoFingerTap, in: .left)
        settings.setAction(.voice, for: .threeFingerTap, in: .right)
        profile.handGestureSettings = settings
        let restored = try PortableKeymapInterop.importProfile(from: PortableKeymapInterop.exportBundle(from: profile), currentProfile: .defaultProfile())
        XCTAssertEqual(restored.handGestureSettings, settings)
        // Built-in presentation never rewrites or seeds the user's saved list.
        XCTAssertEqual(ShortcutActionLibraryStorage.normalized(["Cmd+S"]), ["Cmd+S"])
    }
}
