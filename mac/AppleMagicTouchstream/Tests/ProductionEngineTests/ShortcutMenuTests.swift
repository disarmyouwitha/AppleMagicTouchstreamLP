import Carbon
import XCTest
@testable import GlassToKeyRuntime

@MainActor final class ShortcutMenuTests: XCTestCase {
    func testMenusIncludeVoiceAndDictationWithoutInjectedModifiers() {
        let actions = KeyActionCatalog.shortcutMenuActions(savedLabels: [])
        XCTAssertEqual(actions.map(\.pickerText), ["Screenshot", "Dictation", "Voice", "Emoji"])
        let gestures = GestureActionChooser.shortcutActions(GestureTrigger.twoFingerTap.allowedActions, savedLabels: [])
        XCTAssertEqual(gestures.map(\.title), ["Screenshot", "Dictation", "Voice", "Emoji"])
        for modifier in ["Shift", "Ctrl", "Option", "Cmd", "Hyper"] {
            let saved = GestureActionChooser.shortcutActions(GestureTrigger.twoFingerTap.allowedActions, savedLabels: [modifier])
            XCTAssertEqual(saved.filter { $0.shortcutAssignment?.label == modifier }.count, 1)
            XCTAssertEqual(KeyActionCatalog.shortcutMenuActions(savedLabels: [modifier]).filter { $0.label == modifier }.count, 1)
        }
    }

    func testDictationIsANamedBalancedKeyboardShortcutAndRoundTrips() throws {
        let action = try XCTUnwrap(KeyActionCatalog.action(for:"Dictation"))
        XCTAssertEqual(action.kind,.key)
        XCTAssertEqual(action.pickerText,"Dictation")
        XCTAssertEqual(action.keyCode,UInt16(kVK_ANSI_D))
        XCTAssertEqual(action.flags,CGEventFlags.maskSecondaryFn.rawValue)
        XCTAssertEqual(KeyActionCatalog.shortcutMenuActions(savedLabels:[action.storageLabel,"DICTATION"]).filter { $0.pickerText == "Dictation" }.count,1)
        let edges = try XCTUnwrap(KeyboardStrokeOutput.events(code:action.keyCode,flags:CGEventFlags(rawValue:action.flags),restoringFlags:[]))
        XCTAssertEqual(edges.down.flags,.maskSecondaryFn)
        XCTAssertEqual(edges.up.flags,[])
        // Old named entries keep their literal command; the user reassigns them.
        let old = NamedShortcutStorage.label(name:"Dictation",command:"Option+Cmd+D")
        XCTAssertEqual(KeyActionCatalog.action(for:old)?.flags,CGEventFlags([.maskAlternate,.maskCommand]).rawValue)
        XCTAssertEqual(GestureShortcutAssignment(label:old).action?.flags,CGEventFlags([.maskAlternate,.maskCommand]).rawValue)
        var profile = AppKeymapProfile.defaultProfile()
        var settings = HandGestureSettings()
        settings.setAction(.shortcut(.init(label:action.storageLabel)),for:.thumbTwoTap,in:.left)
        profile.handGestureSettings = settings
        let restored = try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile())
        XCTAssertEqual(restored.handGestureSettings,settings)
        let saved = try XCTUnwrap(ShortcutActionLibraryStorage.encode([action.storageLabel]))
        XCTAssertEqual(ShortcutActionLibraryStorage.decode(from:saved),[action.storageLabel])
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
