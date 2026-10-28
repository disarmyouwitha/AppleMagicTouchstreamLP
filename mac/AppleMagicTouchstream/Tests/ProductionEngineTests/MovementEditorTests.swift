import Foundation
import XCTest
@testable import GlassToKeyRuntime

final class MovementEditorTests: XCTestCase {
    func testDirectionalModePreservesContinuousAndDirectionalAssignments() {
        var settings = HandGestureSettings()
        settings.editMovement(.twoFingerMove,mode:.directional,direction:.up,action:.volumeUpSmall,in:.left)
        XCTAssertEqual(settings.action(.twoFingerMove,in:.left),.pointer)
        XCTAssertEqual(settings.directionalAction(.up,for:.twoFingerMove,in:.left),.volumeUpSmall)
        XCTAssertEqual(settings.routed(to:.init(left:11,right:22))[11]?.bindings.action(for:.twoFingerMove),.disabled)
        XCTAssertEqual(settings.routed(to:.init(left:11,right:22))[22]?.bindings.action(for:.twoFingerMove),.pointer)
        XCTAssertEqual(settings.routed(to:.init(left:11,right:22))[11]?.bindings.action(for:.threeFingerMove),.primaryDrag)
        settings.editMovement(.twoFingerMove,mode:.continuous,in:.left)
        XCTAssertEqual(settings.routed(to:.init(left:11,right:22))[11]?.bindings.action(for:.twoFingerMove),.pointer)
        XCTAssertEqual(settings.directionalAction(.up,for:.twoFingerMove,in:.left),.volumeUpSmall)
    }

    func testMirrorEditingAndMixedValues() {
        var settings = HandGestureSettings()
        settings.editMovement(.threeFingerMove,mode:.directional,direction:.left,action:.brightnessDownSmall,in:.right)
        XCTAssertNil(settings.movementMode(.threeFingerMove,in:.both))
        XCTAssertNil(settings.directionalAction(.left,for:.threeFingerMove,in:.both))
        settings.editMovement(.threeFingerMove,mode:.directional,direction:.left,action:.brightnessUpSmall,in:.both)
        XCTAssertEqual(settings.movementMode(.threeFingerMove,in:.both),.directional)
        XCTAssertEqual(settings.directionalAction(.left,for:.threeFingerMove,in:.both),.brightnessUpSmall)
    }

    func testEditorSettingsRoundTripAndOldProfilesDefaultToContinuous() throws {
        var settings = HandGestureSettings()
        settings.editMovement(.fourFingerMove,mode:.directional,direction:.down,action:.volumeDownSmall,in:.both)
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(HandGestureSettings.self,from:data),settings)
        var profile = AppKeymapProfile.defaultProfile()
        profile.handGestureSettings = settings
        let exported = try PortableKeymapInterop.exportBundle(from:profile)
        XCTAssertEqual(try PortableKeymapInterop.importProfile(from:exported,currentProfile:.defaultProfile()).handGestureSettings,settings)
        let suite = "MovementEditorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        settings.save(to:defaults)
        XCTAssertEqual(HandGestureSettings.load(from:defaults),settings)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        for side in ["left","right"] {
            var hand = try XCTUnwrap(old[side] as? [String:Any])
            hand.removeValue(forKey:"directionalMovement")
            old[side] = hand
        }
        let decoded = try JSONDecoder().decode(HandGestureSettings.self,from:JSONSerialization.data(withJSONObject:old))
        XCTAssertEqual(decoded.movementMode(.fourFingerMove,in:.both),.continuous)
        XCTAssertEqual(decoded.routed(to:.init(left:11,right:22))[11]?.bindings.action(for:.fourFingerMove),.scroll)
    }

    func testDirectionalMenuAllowsVolumeBrightnessButRejectsContinuousOutputs() {
        for action in GestureAction.smallStepActions { XCTAssertTrue(GestureDirectionalAssignments.allowedActions.contains(action)) }
        var settings = HandGestureSettings()
        settings.editMovement(.twoFingerMove,mode:.directional,direction:.up,action:.pointer,in:.both)
        XCTAssertEqual(settings.movementMode(.twoFingerMove,in:.both),.continuous)
        XCTAssertEqual(settings.directionalAction(.up,for:.twoFingerMove,in:.both),.disabled)
    }
}
