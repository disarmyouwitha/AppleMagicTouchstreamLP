import CoreGraphics
import Foundation
import XCTest
@testable import GlassToKeyRuntime

@MainActor final class StenoSixByThreeDefaultsTests:XCTestCase {
    func testAllMainKeysMatchBundledSixByThreeOnBothHandsAndLegacySeed() throws {
        let profile = try XCTUnwrap(StenoSixByThreeDefaults.profile)
        let size = CGSize(width:432,height:310.23)
        let columns = try XCTUnwrap(profile.columnSettingsByLayout[TrackpadLayoutPreset.sixByThree.rawValue])
        let spacing = try XCTUnwrap(profile.keySpacingPercentByLayout?[TrackpadLayoutPreset.sixByThree.rawValue])
        for side in [TrackpadSide.left,.right] {
            let expected = ContentView.makeKeyLayout(size:size,keyWidth:ContentView.baseKeyWidthMM,keyHeight:ContentView.baseKeyHeightMM,
                columns:6,rows:3,trackpadWidth:ContentView.trackpadWidthMM,trackpadHeight:ContentView.trackpadHeightMM,
                columnAnchorsMM:TrackpadLayoutPreset.sixByThree.columnAnchors,columnSettings:columns,keySpacingPercent:spacing,mirrored:side == .left)
            for legacy in [false,true] {
                let layout = legacy
                    ? StenoLayoutDefinition.layout(preset:.stenoVoyager,side:side,size:size,columns:ColumnLayoutDefaults.defaultSettings(columns:6),spacing:0.5)
                    : StenoLayoutDefinition.layout(preset:.stenoVoyager,side:side,size:size)
                XCTAssertEqual(Array(layout.normalizedKeyRects.prefix(3)),expected.normalizedKeyRects)
                XCTAssertEqual(layout.normalizedKeyRects[3].count,2)
                XCTAssertTrue(layout.isSteno)
            }
            let reset = ContentView.editorTemplate(preset:.stenoVoyager,size:size,profile:profile)
            if let authored = profile.layoutDocuments?[TrackpadLayoutPreset.stenoVoyager.rawValue] {
                XCTAssertTrue(authored.isValid)
                XCTAssertEqual(reset,authored,"Authored STENO geometry overrides its legacy seed on reset")
            } else {
                for key in reset.keys where key.right == (side == .right) && key.row < 3 {
                    XCTAssertEqual(key.rect,expected.normalizedKeyRects[key.row][key.column])
                }
            }
        }
    }
    func testExplicitColumnTuningAndOtherStenoVariantsStayIndependent() {
        let neutral = ColumnLayoutDefaults.defaultSettings(columns:6)
        var changed = neutral; changed[0].offsetXPercent = 3
        let result = StenoSixByThreeDefaults.resolve(columns:changed,spacing:18)
        XCTAssertEqual(result.0,changed); XCTAssertEqual(result.1,18)
        for preset in [TrackpadLayoutPreset.steno,.stenoSingle] {
            let base = StenoLayoutDefinition.layout(preset:preset,side:.right,size:.init(width:432,height:310))
            let custom = StenoLayoutDefinition.layout(preset:preset,side:.right,size:.init(width:432,height:310),columns:changed,spacing:18)
            XCTAssertEqual(base.normalizedKeyRects,custom.normalizedKeyRects)
        }
    }
    func testRetiredTemplatesAreAbsentFromPickersAndBundledKeymaps() throws {
        for name in ["5x3","5x4"] {
            XCTAssertNil(TrackpadLayoutPreset.resolveByName(name))
            XCTAssertFalse(TrackpadLayoutPreset.allCases.contains { $0.rawValue == name })
            XCTAssertFalse(TrackpadLayoutPreset.selectableCases.contains { $0.rawValue == name })
        }
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func check(_ object:Any) {
            if let map = object as? [String:Any] {
                XCTAssertNil(map["5x3"]); XCTAssertNil(map["5x4"])
                for value in map.values { check(value) }
                if let embedded = map["KeymapJson"] as? String, let data = embedded.data(using:.utf8), let value = try? JSONSerialization.jsonObject(with:data) { check(value) }
            } else if let list = object as? [Any] { for value in list { check(value) } }
        }
        // MY_KEYMAP is user-authored and may retain old preference entries;
        // factory templates must not reintroduce retired layouts.
        for name in ["DEFAULT_KEYMAP.json","TOUCHSTERAM_KEYMAP.json"] {
            check(try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("AppleMagicTouchstream/AppleMagicTouchstream/"+name))))
        }
    }
}
