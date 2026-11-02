import XCTest
@testable import GlassToKeyRuntime

final class TouchStreamTemplateTests:XCTestCase {
    private var root:URL { URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    func testTouchStreamTemplateImportsEveryAssignmentWithoutSilentNormalization() throws {
        let data = try Data(contentsOf:root.appendingPathComponent("AppleMagicTouchstream/AppleMagicTouchstream/TOUCHSTERAM_KEYMAP.json"))
        let profile = try PortableKeymapInterop.importProfile(from:data,currentProfile:.defaultProfile())
        let settings = try XCTUnwrap(profile.handGestureSettings)
        XCTAssertEqual(profile.layoutPreset,TrackpadLayoutPreset.touchstream.rawValue)
        XCTAssertEqual(settings.right.bindings.action(for:.twoFingerMove),.pointer)
        XCTAssertEqual(settings.right.bindings.action(for:.threeFingerMove),.primaryDrag)
        XCTAssertEqual(settings.right.bindings.action(for:.fourFingerMove),.scroll)
        XCTAssertEqual(settings.right.bindings.action(for:.thumbTwoTap),.secondaryClick)
        XCTAssertEqual(settings.left.movement(.twoFingerMove).action(.left).shortcutAssignment?.label,"Left")
        XCTAssertEqual(settings.left.movement(.threeFingerMove).action(.right).shortcutAssignment?.label,"Shift+Right")
        XCTAssertEqual(settings.right.bindings.action(for:.fourFingerPinch).shortcutAssignment?.label,"Cmd+S")
        for hand in [settings.left,settings.right] {
            for trigger in GestureTrigger.allCases { XCTAssertEqual(hand.bindings[trigger],hand.bindings.action(for:trigger),trigger.rawValue) }
            for (_,config) in hand.directionalMovement ?? [:] {
                for (_,action) in config.actions { XCTAssertTrue(GestureDirectionalAssignments.allowedActions.acceptsGestureAction(action)) }
            }
            for (key,action) in hand.holdActions ?? [:] {
                XCTAssertEqual(action,hand.holdAction(count:Int(key)!))
            }
            XCTAssertEqual(hand.holdThreshold(count:7),1)
        }
        XCTAssertEqual(settings.left.holdAction(count:4).shortcutAssignment?.label,"Shift")
        XCTAssertTrue(settings.left.holdAction(count:4).isHeldShortcut)
        XCTAssertEqual(settings.twoHand.action(.init(chord:.fourCorners,phase:.hold)),.openConfig)
        XCTAssertEqual(settings.twoHand.action(.init(chord:.threeFingers,phase:.tap)).shortcutAssignment?.label,"Enter")
        let roundTrip = try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:profile),currentProfile:.defaultProfile())
        XCTAssertEqual(roundTrip.handGestureSettings,settings)
        XCTAssertEqual(roundTrip.keyMappingsByLayout,profile.keyMappingsByLayout)
    }
    func testTemplateLeavesLocalSettingsAndOtherAuthoredGeometryAlone() throws {
        var current = AppKeymapProfile.defaultProfile()
        var gestures = HandGestureSettings()
        gestures.stenoConnectionMode = .serial; gestures.stenoHapticOnTouch = true; gestures.stenoForceThreshold = 147
        current.handGestureSettings = gestures
        let data = try Data(contentsOf:root.appendingPathComponent("AppleMagicTouchstream/AppleMagicTouchstream/TOUCHSTERAM_KEYMAP.json"))
        let result = try PortableKeymapInterop.importProfile(from:data,currentProfile:current)
        XCTAssertEqual(result.handGestureSettings?.stenoConnectionMode,.serial)
        XCTAssertEqual(result.handGestureSettings?.stenoHapticOnTouch,true)
        XCTAssertEqual(result.handGestureSettings?.stenoForceThreshold,147)
        let factoryData = try Data(contentsOf:root.appendingPathComponent("AppleMagicTouchstream/AppleMagicTouchstream/DEFAULT_KEYMAP.json"))
        let factory = try XCTUnwrap(PortableKeymapInterop.decodeBundledDefaultProfile(from:factoryData))
        XCTAssertEqual(result.columnSettingsByLayout["6x3"],factory.columnSettingsByLayout["6x3"])
        XCTAssertEqual(result.columnSettingsByLayout["STENO Voyager"],factory.columnSettingsByLayout["STENO Voyager"])
        let templates:Set<String> = ["6x3","STENO Voyager"]
        XCTAssertEqual(result.columnSettingsByLayout.filter { !templates.contains($0.key) },current.columnSettingsByLayout.filter { !templates.contains($0.key) })
        for template in templates { XCTAssertEqual(result.layoutDocuments?[template],factory.layoutDocuments?[template]) }
        XCTAssertEqual(result.leftDeviceID,current.leftDeviceID)
        XCTAssertEqual(result.runAtStartupEnabled,current.runAtStartupEnabled)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        XCTAssertEqual(Set(try XCTUnwrap(json["Settings"] as? [String:Any]).keys),["ActiveLayer","LayoutPresetName","ColumnSettingsByLayout","KeyPaddingPercentByLayout"])
    }
}
