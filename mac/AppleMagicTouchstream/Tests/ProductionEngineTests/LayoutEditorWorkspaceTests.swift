import AppKit
import SwiftUI
import XCTest
@testable import GlassToKeyRuntime

@MainActor
final class LayoutEditorWorkspaceTests: XCTestCase {
    private func popups(_ view: NSView) -> [NSPopUpButton] {
        (view as? NSPopUpButton).map { [$0] } ?? view.subviews.flatMap { popups($0) }
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
    func testInlineWorkspaceSelectsKeysFromBothPadsWithoutApplying() throws {
        let doc = document()
        var applied = false, canceled = false
        let host = NSHostingView(rootView:LayoutEditor(document:doc,template:doc,
            onApply:{_ in applied = true},onCancel:{canceled = true},menuWidth:.constant(381))
            .background(Color.white).environment(\.colorScheme,.light))
        host.frame = CGRect(x:0,y:0,width:1384,height:520)
        let window = NSWindow(contentRect:host.frame,styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        RunLoop.current.run(until:Date().addingTimeInterval(0.05))
        XCTAssertFalse(window.isVisible)
        let popup = try XCTUnwrap(popups(host).first { $0.itemTitles.contains(where:{$0.hasPrefix("L ·")}) })
        for side in ["L ·","R ·"] {
            let item = try XCTUnwrap(popup.itemArray.first {$0.title.hasPrefix(side)})
            XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action),to:item.target,from:item))
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until:Date().addingTimeInterval(0.05))
            XCTAssertGreaterThanOrEqual(editableFields(host).count,5)
            XCTAssertFalse(applied,"Selection must never publish geometry")
            XCTAssertFalse(canceled)
        }
        if let directory = ProcessInfo.processInfo.environment["AMT_LAYOUT_PREVIEW_DIR"] {
            let url = URL(fileURLWithPath:directory,isDirectory:true)
            try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds))
            host.cacheDisplay(in:host.bounds,to:bitmap)
            try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:url.appendingPathComponent("layout-selected.png"))
        }
    }
    func testSelectionSizingAndSavedGroupRenderWithCompactTools() throws {
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
