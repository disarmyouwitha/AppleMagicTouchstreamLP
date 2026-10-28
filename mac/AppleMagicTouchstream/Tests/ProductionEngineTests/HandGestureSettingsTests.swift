import CoreGraphics
import XCTest
@testable import GlassToKeyRuntime

final class HandGestureSettingsTests: XCTestCase {
    func testDefaultsAreMirroredAndSeedCopiesExistingConfiguration() {
        var defaults = HandGestureSettings()
        XCTAssertEqual(defaults.left,defaults.right)
        for feature in GestureFeature.allCases where feature != .fourCornersTap && feature != .thumbTwoMove { XCTAssertEqual(defaults.enabled(feature,in:.both),feature.defaultAction != .disabled) }
        XCTAssertEqual(defaults.left.pointerSensitivity,1); XCTAssertEqual(defaults.right.scrollSensitivity,1)
        var seed = PerHandGestureSettings()
        seed[.mouse] = false; seed[GestureSensitivity.pointer] = 0.75
        defaults = HandGestureSettings(mirrored:seed)
        XCTAssertEqual(defaults.left,seed); XCTAssertEqual(defaults.right,seed)
        defaults.set(.tap,enabled:false,in:.left)
        XCTAssertFalse(defaults.left.tap); XCTAssertTrue(defaults.right.tap)
        XCTAssertTrue(seed.tap) // value copies, no shared mutable hand configuration
    }
    func testEveryFeatureCanDivergeAndBothExplicitlyAppliesWithoutTouchingOtherFeatures() {
        for feature in GestureFeature.allCases where feature != .fourCornersTap && feature != .thumbTwoMove {
            var settings = HandGestureSettings()
            for trigger in GestureTrigger.allCases { settings.set(trigger,enabled:true,in:.both) }
            settings.set(feature,enabled:false,in:.left)
            XCTAssertEqual(settings.enabled(feature,in:.left),false)
            XCTAssertEqual(settings.enabled(feature,in:.right),true)
            XCTAssertNil(settings.enabled(feature,in:.both))
            for other in GestureFeature.allCases where other != feature && other != .fourCornersTap && other != .thumbTwoMove { XCTAssertEqual(settings.enabled(other,in:.both),true) }
            settings.set(feature,enabled:false,in:.both)
            XCTAssertEqual(settings.enabled(feature,in:.both),false)
            settings.set(feature,enabled:true,in:.right)
            XCTAssertFalse(settings.left[feature]); XCTAssertTrue(settings.right[feature])
            settings.set(feature,enabled:true,in:.both)
            XCTAssertEqual(settings.enabled(feature,in:.both),true)
        }
    }
    func testSensitivityIsIndependentMixedAndClamped() {
        var settings = HandGestureSettings()
        settings.set(.pointer,value:0.5,in:.left); settings.set(.pointer,value:1.5,in:.right)
        settings.set(.scroll,value:0.75,in:.left); settings.set(.scroll,value:1.25,in:.right)
        XCTAssertNil(settings.sensitivity(.pointer,in:.both)); XCTAssertNil(settings.sensitivity(.scroll,in:.both))
        XCTAssertEqual(settings.sensitivity(.pointer,in:.left),0.5)
        XCTAssertEqual(settings.sensitivity(.scroll,in:.right),1.25)
        settings.set(.pointer,value:3,in:.both)
        XCTAssertEqual(settings.sensitivity(.pointer,in:.both),2)
        XCTAssertEqual(settings.left.scrollSensitivity,0.75); XCTAssertEqual(settings.right.scrollSensitivity,1.25)
        settings.set(.scroll,value:0,in:.right); XCTAssertEqual(settings.right.scrollSensitivity,0.25)
        settings.set(.pointer,value:.nan,in:.left); XCTAssertEqual(settings.left.pointerSensitivity,1)
        settings.set(.scroll,value:.infinity,in:.both); XCTAssertEqual(settings.sensitivity(.scroll,in:.both),1)
    }
    func testRoutingUsesExplicitSlotsIncludingNoneAndSwaps() {
        var settings = HandGestureSettings()
        settings.set(.mouse,enabled:false,in:.left); settings.set(.rightClick,enabled:false,in:.right)
        settings.set(.pointer,value:0.5,in:.left); settings.set(.pointer,value:1.5,in:.right)
        let pads = GestureSelectedPads(left:11,right:22)
        XCTAssertEqual(settings.outputDevices(.mouse,pads:pads,eligible:[11,22]),[22])
        XCTAssertEqual(settings.outputDevices(.rightClick,pads:pads,eligible:[11,22]),[11])
        XCTAssertEqual(settings.routed(to:pads)[22]?.pointerSensitivity,1.5)
        let onlyRight = GestureSelectedPads(left:nil,right:22)
        XCTAssertEqual(settings.outputDevices(.mouse,pads:onlyRight,eligible:[22]),[22])
        XCTAssertEqual(settings.routed(to:onlyRight)[22],settings.right)
        let swapped = GestureSelectedPads(left:22,right:11)
        XCTAssertEqual(settings.outputDevices(.mouse,pads:swapped,eligible:[11,22]),[11])
        XCTAssertEqual(settings.routed(to:swapped)[22],settings.left)
        XCTAssertTrue(settings.routed(to:GestureSelectedPads()).isEmpty)
    }
    func testEligibilityCannotLeakToUnselectedOrUnownedDevices() {
        let settings = HandGestureSettings(), pads = GestureSelectedPads(left:11,right:22)
        for feature in GestureFeature.allCases where feature != .fourCornersTap && feature != .thumbTwoMove {
            XCTAssertEqual(settings.outputDevices(feature,pads:pads,eligible:[22,33]),feature.defaultAction != .disabled ? [22] : [])
            XCTAssertTrue(settings.outputDevices(feature,pads:pads,eligible:[]).isEmpty)
            XCTAssertTrue(settings.outputDevices(feature,pads:pads,eligible:[33]).isEmpty)
        }
    }
    func testDuplicatePhysicalPadMergesEnabledFeaturesButUsesLeftSensitivityOnce() {
        var settings = HandGestureSettings()
        settings.set(.mouse,enabled:false,in:.left); settings.set(.rightClick,enabled:false,in:.right)
        settings.set(.pointer,value:0.5,in:.left); settings.set(.pointer,value:1.5,in:.right)
        let pads = GestureSelectedPads(left:11,right:11), routed = settings.routed(to:pads)
        XCTAssertEqual(routed.count,1)
        XCTAssertEqual(routed[11]?.mouse,true); XCTAssertEqual(routed[11]?.rightClick,true)
        XCTAssertEqual(routed[11]?.pointerSensitivity,0.5)
        XCTAssertEqual(settings.outputDevices(.mouse,pads:pads,eligible:[11]),[11])
    }
    func testPerDevicePointerGainsMatchIndependentAppleModels() throws {
        let profile = try ApplePointerAccelerationProfile(resolution:400,fixedMultiplier:48545/65536,
            acceleration:3,curves:[ApplePointerCurve(index:3,linear:1,parabolic:123208/65536,
                cubic:23593/65536,tangentLinear:7,tangentRoot:12)])
        var combined = TwoFingerPointerMotionEngine(), left = TwoFingerPointerMotionEngine(), right = TwoFingerPointerMotionEngine()
        combined.configure(response:.apple,sensitivity:1,profiles:[11:profile,22:profile],sensitivities:[11:0.75,22:1.25])
        left.configure(response:.apple,sensitivity:0.75,profiles:[11:profile])
        right.configure(response:.apple,sensitivity:1.25,profiles:[22:profile])
        for frame in 0..<30 {
            let time = 1+Double(frame)*0.01, mm = CGPoint(x:0.1+Double(frame)*0.005,y:0.05)
            XCTAssertEqual(combined.processMotion(device:11,time:time,millimetres:mm),left.processMotion(device:11,time:time,millimetres:mm))
            XCTAssertEqual(combined.processMotion(device:22,time:time,millimetres:mm),right.processMotion(device:22,time:time,millimetres:mm))
        }
        XCTAssertNil(combined.processMotion(device:33,time:1,millimetres:CGPoint(x:1,y:0)))
    }
}

extension HandGestureSettingsTests {
    func testOldSettingsMigrateWithoutLosingActionsOrGainsAndForceEditsRoundTrip() throws {
        var old = HandGestureSettings()
        old.setAction(.secondaryClick,for:.twoFingerTap,in:.left)
        old.set(.pointer,value:0.7,in:.right)
        let data = try JSONEncoder().encode(old)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        for hand in ["left","right"] {
            var side = try XCTUnwrap(json[hand] as? [String:Any])
            side.removeValue(forKey:"forceHaptic")
            var bindings = try XCTUnwrap(side["bindings"] as? [String:Any])
            bindings.removeValue(forKey:"forceActions"); side["bindings"] = bindings; json[hand] = side
        }
        var migrated = try JSONDecoder().decode(HandGestureSettings.self,from:JSONSerialization.data(withJSONObject:json))
        XCTAssertEqual(migrated,old)
        XCTAssertEqual(migrated.action(.oneFingerForce,in:.both),.primaryClick)
        for trigger in GestureTrigger.forceTriggers.dropFirst() { XCTAssertEqual(migrated.action(trigger,in:.both),.disabled) }
        migrated.setAction(.primaryDoubleClick,for:.fiveFingerForce,in:.right)
        migrated.left.forceHaptic = ForceClickHapticSettings(waveform:1,level:0.1)
        migrated.right.forceHaptic = ForceClickHapticSettings(waveform:4,level:0)
        let roundtrip = try JSONDecoder().decode(HandGestureSettings.self,from:JSONEncoder().encode(migrated))
        XCTAssertEqual(roundtrip,migrated)
        XCTAssertEqual(roundtrip.action(.fiveFingerForce,in:.left),.disabled)
        XCTAssertEqual(roundtrip.action(.twoFingerTap,in:.left),.secondaryClick)
        XCTAssertEqual(roundtrip.right.pointerSensitivity,0.7)
        XCTAssertEqual(ForceClickHapticSettings(waveform:999,level:.infinity).normalized,ForceClickHapticSettings(waveform:6,level:0.25))
        XCTAssertEqual(ForceClickHapticSettings(waveform:-1,level:100).normalized,ForceClickHapticSettings(waveform:1,level:2))
    }
}

extension HandGestureSettingsTests {
    func testGestureActionsAndGainsExportWithKeymapAndOldFilesPreserveCurrentGestures() throws {
        var profile = AppKeymapProfile.defaultProfile(), gestures = HandGestureSettings()
        for trigger in GestureTrigger.allCases {
            gestures.setAction(trigger.isContinuous ? .scroll : .secondaryClick,for:trigger,in:.left)
            gestures.setAction(.disabled,for:trigger,in:.right)
        }
        gestures.set(.pointer,value:0.65,in:.left); gestures.set(.scroll,value:1.75,in:.right)
        profile.handGestureSettings = gestures
        let exported = try PortableKeymapInterop.exportBundle(from:profile)
        let restored = try PortableKeymapInterop.importProfile(from:exported,currentProfile:.defaultProfile())
        XCTAssertEqual(restored.handGestureSettings,gestures)
        let direct = try JSONDecoder().decode(AppKeymapProfile.self,from:JSONEncoder().encode(profile))
        XCTAssertEqual(direct.handGestureSettings,gestures)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with:exported) as? [String:Any])
        var hosts = try XCTUnwrap(legacy["HostExtensions"] as? [String:Any])
        var mac = try XCTUnwrap(hosts["mac"] as? [String:Any])
        XCTAssertNotNil(mac.removeValue(forKey:"GestureBindings"))
        hosts["mac"] = mac; legacy["HostExtensions"] = hosts
        let old = try JSONSerialization.data(withJSONObject:legacy)
        XCTAssertEqual(try PortableKeymapInterop.importProfile(from:old,currentProfile:profile).handGestureSettings,gestures)
        XCTAssertNil(try PortableKeymapInterop.importProfile(from:old,currentProfile:.defaultProfile()).handGestureSettings)
        let bare = try XCTUnwrap(legacy["KeymapJson"] as? String).data(using:.utf8)!
        XCTAssertEqual(try PortableKeymapInterop.importProfile(from:bare,currentProfile:profile).handGestureSettings,gestures)
    }
}

extension HandGestureSettingsTests {
    func testRetiredActionLabelsRoundTripWithGesturesWhileUnknownLabelsStillFail() throws {
        var profile = AppKeymapProfile.defaultProfile()
        var gestures = HandGestureSettings()
        gestures.setAction(.secondaryClick,for:.threeFingerForce,in:.right)
        profile.handGestureSettings = gestures
        let retired: [(String,KeyActionKind)] = [("BRIGHT_DOWN",.brightnessDown),("BRIGHT_UP",.brightnessUp),("Voice",.voice)]
        var mappings: [String:KeyMapping] = [:]
        for (column,item) in retired.enumerated() {
            let action = KeyAction(label:item.0,keyCode:0,flags:0,kind:item.1)
            mappings[GridKeyPosition(side:.left,row:0,column:column).storageKey] = KeyMapping(primary:action,hold:action)
            if item.1 == .voice { XCTAssertEqual(KeyActionCatalog.action(for:item.0)?.kind,.voice) }
            else { XCTAssertNil(KeyActionCatalog.action(for:item.0)) } // Other retired labels remain inert.
        }
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(profile)) as? [String:Any])
        object["keyMappingsByLayout"] = try JSONSerialization.jsonObject(with:JSONEncoder().encode(["TouchStream":[0:mappings]]))
        profile = try JSONDecoder().decode(AppKeymapProfile.self,from:JSONSerialization.data(withJSONObject:object))
        let data = try PortableKeymapInterop.exportBundle(from:profile)
        let restored = try PortableKeymapInterop.importProfile(from:data,currentProfile:.defaultProfile())
        XCTAssertEqual(restored.handGestureSettings,gestures)
        XCTAssertEqual(restored.keyMappingsByLayout?["TouchStream"]?[0],mappings)
        let second = try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:restored),currentProfile:.defaultProfile())
        XCTAssertEqual(second.keyMappingsByLayout?["TouchStream"]?[0],mappings)
        let bad = String(decoding:data,as:UTF8.self).replacingOccurrences(of:"BRIGHT_DOWN",with:"UNKNOWN_ACTION_TEST")
        XCTAssertThrowsError(try PortableKeymapInterop.importProfile(from:Data(bad.utf8),currentProfile:.defaultProfile()))
    }
    func testActualBundledDefaultKeymapCanBeReexportedAndImported() throws {
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf:root.appendingPathComponent("AppleMagicTouchstream/AppleMagicTouchstream/DEFAULT_KEYMAP.json"))
        let original = try PortableKeymapInterop.importProfile(from:data,currentProfile:.defaultProfile())
        let restored = try PortableKeymapInterop.importProfile(from:PortableKeymapInterop.exportBundle(from:original),currentProfile:.defaultProfile())
        XCTAssertEqual(restored.keyMappingsByLayout,original.keyMappingsByLayout)
        XCTAssertEqual(restored.handGestureSettings,original.handGestureSettings)
    }
}
