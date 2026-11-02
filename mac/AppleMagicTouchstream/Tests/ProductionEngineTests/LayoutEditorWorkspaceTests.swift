import AppKit
import SwiftUI
import XCTest
@testable import GlassToKeyRuntime

@MainActor
final class LayoutEditorWorkspaceTests: XCTestCase {
    func testInitialWindowFitsLaptopVisibleFramesIncludingTitlebarAndMargins() {
        let style:NSWindow.StyleMask = [.titled,.closable,.miniaturizable,.resizable]
        let titlebar = NSWindow.frameRect(forContentRect:CGRect(x:0,y:0,width:100,height:100),styleMask:style).height-100
        for visible in [CGRect(x:0,y:25,width:1280,height:725),CGRect(x:0,y:25,width:1440,height:825),CGRect(x:0,y:25,width:1280,height:675)] {
            let size = ConfigWindowSizing.initialContentSize(visibleFrame:visible,titlebarHeight:titlebar)
            let frame = NSWindow.frameRect(forContentRect:CGRect(origin:.zero,size:size),styleMask:style)
            XCTAssertLessThanOrEqual(frame.width+32,visible.width)
            XCTAssertLessThanOrEqual(frame.height+32,visible.height)
            XCTAssertGreaterThanOrEqual(size.width,ConfigWindowSizing.minimum.width)
            XCTAssertGreaterThanOrEqual(size.height,ConfigWindowSizing.minimum.height)
        }
        XCTAssertEqual(ConfigWindowSizing.initialContentSize(visibleFrame:CGRect(x:0,y:0,width:2000,height:1200),titlebarHeight:titlebar),ConfigWindowSizing.preferred)
    }
    private func editableFields(_ view: NSView) -> [NSTextField] {
        let fields = (view as? NSTextField).map { [$0] } ?? []
        return fields.filter(\.isEditable)+view.subviews.flatMap { editableFields($0) }
    }
    private func document() -> LayoutDocument {
        let size = CGSize(width:800,height:574.5)
        let left = StenoLayoutDefinition.layout(preset:.steno,side:.left,size:size)
        let right = StenoLayoutDefinition.layout(preset:.steno,side:.right,size:size)
        var doc = LayoutDocument.seed(left:left,right:right,leftLabels:TrackpadLayoutPreset.steno.leftLabels,rightLabels:TrackpadLayoutPreset.steno.rightLabels)
        doc.inferMirrorPairs()
        return doc
    }
    private func defaultProfile() throws -> AppKeymapProfile {
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf:root.appendingPathComponent("AppleMagicTouchstream/AppleMagicTouchstream/DEFAULT_KEYMAP.json"))
        return try XCTUnwrap(PortableKeymapInterop.decodeBundledDefaultProfile(from:data))
    }
    func testEditorLegendsUseIndependentActiveHandMappingsAndDuplicateSource() throws {
        var doc = document()
        let left = try XCTUnwrap(doc.keys.first {!$0.right})
        let right = try XCTUnwrap(doc.keys.first {$0.right})
        let a = try XCTUnwrap(KeyActionCatalog.action(for:"A")), b = try XCTUnwrap(KeyActionCatalog.action(for:"B"))
        let mappings = [GridKeyPosition(side:.left,row:left.row,column:left.column).storageKey:KeyMapping(primary:a,hold:nil),
                        GridKeyPosition(side:.right,row:right.row,column:right.column).storageKey:KeyMapping(primary:b,hold:nil)]
        let before = doc
        let legends = doc.editorLegends(mappings:mappings)
        XCTAssertEqual(legends[left.id],a.displayText); XCTAssertEqual(legends[right.id],b.displayText)
        XCTAssertEqual(doc,before,"Display labels must not overwrite fallback actions or geometry")
        let copied = try XCTUnwrap(doc.duplicate([left.id]).first)
        XCTAssertEqual(doc.editorLegends(mappings:mappings)[copied],a.displayText)
    }
    func testResetGridTemplatesUseBundledColumnDimensionsAndRowSpacing() throws {
        let profile = try defaultProfile(), size = CGSize(width:432,height:310.23)
        for preset in [TrackpadLayoutPreset.sixByThree,.sixByFour] {
            let doc = ContentView.editorTemplate(preset:preset,size:size,profile:profile)
            if let authored = profile.layoutDocuments?[preset.rawValue] {
                XCTAssertTrue(authored.isValid)
                XCTAssertEqual(doc,authored,"An authored template takes priority over legacy column settings")
                continue
            }
            XCTAssertEqual(doc.keys.count,preset.rows*preset.columns*2)
            let mappings = profile.keyMappingsByLayout?[preset.rawValue]?[KeyLayerConfig.baseLayer] ?? [:]
            for key in doc.keys {
                let address = GridKeyPosition(side:key.right ? .right:.left,row:key.row,column:key.column).storageKey
                if let mapping = mappings[address] { XCTAssertEqual(key.label,mapping.primary.label) }
            }
            let columns = try XCTUnwrap(profile.columnSettingsByLayout[preset.rawValue])
            let spacing = try XCTUnwrap(profile.keySpacingPercentByLayout?[preset.rawValue])
            for side in [false,true] {
                let expected = ContentView.makeKeyLayout(size:size,keyWidth:ContentView.baseKeyWidthMM,keyHeight:ContentView.baseKeyHeightMM,
                    columns:preset.columns,rows:preset.rows,trackpadWidth:ContentView.trackpadWidthMM,trackpadHeight:ContentView.trackpadHeightMM,
                    columnAnchorsMM:preset.columnAnchors,columnSettings:columns,keySpacingPercent:spacing,
                    keyGeometryOverrides:profile.keyGeometryByLayout?[preset.rawValue] ?? [:],mirrored:!side)
                for key in doc.keys where key.right == side {
                    XCTAssertEqual(key.rect,expected.normalizedKeyRects[key.row][key.column],"\(preset) \(side) \(key.row):\(key.column)")
                }
            }
        }
    }
    func testResetSpecialTemplatesRetainBundledGeometryAndStenoOverlap() throws {
        let profile = try defaultProfile(), size = CGSize(width:432,height:310.23)
        for preset in [TrackpadLayoutPreset.touchstream,.steno,.stenoVoyager,.stenoSingle] {
            let doc = ContentView.editorTemplate(preset:preset,size:size,profile:profile)
            XCTAssertTrue(doc.isValid)
            if preset == .stenoSingle { XCTAssertFalse(doc.keys.contains {!$0.right}) }
            if preset == .steno || preset == .stenoSingle { XCTAssertTrue(doc.keys.contains {$0.edges.contains {$0 > 0}}) }
            for side in [false,true] {
                let expected = preset == .touchstream
                    ? ContentView.makeTouchStreamKeyLayout(size:size,side:side ? .right:.left,keyGeometryOverrides:profile.keyGeometryByLayout?[preset.rawValue] ?? [:])
                    : StenoLayoutDefinition.layout(preset:preset,side:side ? .right:.left,size:size,
                        columns:profile.columnSettingsByLayout[preset.rawValue] ?? [],spacing:profile.keySpacingPercentByLayout?[preset.rawValue] ?? 10,
                        overrides:profile.keyGeometryByLayout?[preset.rawValue] ?? [:])
                for key in doc.keys where key.right == side { XCTAssertEqual(key.rect,expected.normalizedKeyRects[key.row][key.column]) }
            }
        }
    }
    func testInlineWorkspaceRendersIndividualSelectionOnEitherPadWithoutApplying() throws {
        let doc = document()
        for side in [false,true] {
            let key = try XCTUnwrap(doc.keys.first {$0.right == side})
            let host = NSHostingView(rootView:LayoutEditor(document:doc,template:doc,
                onApply:{_ in XCTFail("Selection must stay staged")},onCancel:{},menuWidth:.constant(381),initialSelection:[key.id])
                .background(Color.white).environment(\.colorScheme,.light))
            host.frame = CGRect(x:0,y:0,width:1384,height:520)
            let window = NSWindow(contentRect:host.frame,styleMask:[.borderless],backing:.buffered,defer:false)
            window.contentView = host
            host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            RunLoop.current.run(until:Date().addingTimeInterval(0.05))
            XCTAssertFalse(window.isVisible)
            XCTAssertGreaterThanOrEqual(editableFields(host).count,5)
            window.contentView = nil
        }
    }
    func testTemporarySelectionSizingRendersWithCompactTools() throws {
        let doc = document()
        let group = try XCTUnwrap(doc.groups.first { g in doc.keys.filter {$0.group == g.id && !$0.right}.count > 1 })
        let ids = Set(doc.keys.filter {$0.group == group.id && !$0.right}.map(\.id))
        for menu in [220.0,450.0] {
            let host = NSHostingView(rootView:LayoutEditor(document:doc,template:doc,
                onApply:{_ in XCTFail("Preview must stay staged")},onCancel:{},menuWidth:.constant(menu),initialSelection:ids)
                .background(Color.white).environment(\.colorScheme,.light))
            host.frame = CGRect(x:0,y:0,width:1440,height:800)
            let window = NSWindow(contentRect:host.frame,styleMask:[.borderless],backing:.buffered,defer:false)
            window.contentView = host
            host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            RunLoop.current.run(until:Date().addingTimeInterval(0.05))
            XCTAssertGreaterThanOrEqual(editableFields(host).count,2)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds))
            host.cacheDisplay(in:host.bounds,to:bitmap)
            if let directory = ProcessInfo.processInfo.environment["AMT_LAYOUT_PREVIEW_DIR"] {
                let path = URL(fileURLWithPath:directory,isDirectory:true)
                try FileManager.default.createDirectory(at:path,withIntermediateDirectories:true)
                try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:path.appendingPathComponent("selection-sizing-\(Int(menu)).png"))
            }
            window.contentView = nil
        }
    }
    func testInlineWorkspaceFitsNarrowAndWideCanvasWithoutNativeInput() throws {
        let doc = document()
        for (name,size,menu) in [("narrow",CGSize(width:1140,height:460),300.0),("wide",CGSize(width:1600,height:720),381.0)] {
            let host = NSHostingView(rootView:LayoutEditor(document:doc,template:doc,
                onApply:{_ in XCTFail("Rendering must not apply geometry")},
                onCancel:{XCTFail("Rendering must not cancel")},menuWidth:.constant(menu))
                .background(Color.white).environment(\.colorScheme,.light))
            host.frame = CGRect(origin:.zero,size:size)
            let window = NSWindow(contentRect:host.frame,styleMask:[.borderless],backing:.buffered,defer:false)
            window.contentView = host
            host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            RunLoop.current.run(until:Date().addingTimeInterval(0.05))
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds))
            host.cacheDisplay(in:host.bounds,to:bitmap)
            XCTAssertGreaterThan(bitmap.pixelsHigh,0)
            XCTAssertGreaterThanOrEqual(bitmap.pixelsWide,Int(size.width))
            if let directory = ProcessInfo.processInfo.environment["AMT_LAYOUT_PREVIEW_DIR"] {
                let path = URL(fileURLWithPath:directory,isDirectory:true)
                try FileManager.default.createDirectory(at:path,withIntermediateDirectories:true)
                try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:path.appendingPathComponent("layout-\(name).png"))
            }
            window.contentView = nil
        }
    }
}
