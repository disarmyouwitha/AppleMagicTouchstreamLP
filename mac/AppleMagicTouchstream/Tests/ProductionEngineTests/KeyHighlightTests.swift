import AppKit
import OpenMultitouchSupport
import XCTest
@testable import GlassToKeyRuntime

final class KeyHighlightTests:XCTestCase {
    private let size = CGSize(width:160,height:115)
    private let rects:[[NormalizedRect]] = [[.init(x:0.1,y:0.1,width:0.2,height:0.2),.init(x:0.4,y:0.1,width:0.2,height:0.2)]]
    private func touch(_ x:Float = 0.2,_ y:Float = 0.8,id:Int32 = 1,time:Double = 1,state:OMSState = .touching) -> OMSTouchData {
        .init(deviceID:"42",deviceIndex:4,id:id,position:.init(x:x,y:y),total:1,pressure:50,axis:.init(major:5,minor:3),angle:0,density:1,state:state,timestamp:time)
    }
    private func update(_ history:inout KeyHitHighlightHistory,_ touches:[OMSTouchData],now:Double,steno:Bool = false) {
        history.update(touches,rects:rects,buttons:[],isSteno:steno,size:size,now:now)
    }
    func testEveryChordKeyStaysBrightWhileHeldThenFadesAndExpires() throws {
        var history = KeyHitHighlightHistory()
        update(&history,[touch(),touch(0.5,id:2)],now:1)
        XCTAssertEqual(history.entries.count,2)
        update(&history,[touch(time:1.2),touch(0.5,id:2,time:1.2)],now:1.2)
        XCTAssertTrue(history.entries.values.allSatisfy { $0.opacity(at:1.2) == 1 })
        update(&history,[],now:1.3)
        for entry in history.entries.values {
            XCTAssertEqual(entry.opacity(at:1.3),1)
            XCTAssertEqual(entry.opacity(at:1.9),0.5,accuracy:0.001)
            XCTAssertEqual(entry.opacity(at:2.5),0,accuracy:0.001)
        }
        history.prune(now:2.51); XCTAssertTrue(history.entries.isEmpty)
    }
    func testNewHitRebrightensOnlyThatKeyAndRewindClearsOldKeys() throws {
        var history = KeyHitHighlightHistory()
        update(&history,[touch(),touch(0.5,id:2)],now:1)
        update(&history,[],now:1.1)
        update(&history,[touch(time:1.5)],now:1.5)
        XCTAssertEqual(history.entries[.grid(0,0)]?.opacity(at:1.5),1)
        XCTAssertLessThan(try XCTUnwrap(history.entries[.grid(0,1)]?.opacity(at:1.5)),1)
        update(&history,[touch(time:0.5)],now:1.6)
        XCTAssertEqual(history.entries.count,1)
        XCTAssertNil(history.entries[.grid(0,1)])
    }
    func testStenoSeamHighlightsBothKeysAndOrdinaryLayoutsKeepDirectHitGeometry() {
        let rows:[[NormalizedRect]] = [[.init(x:0.1,y:0.1,width:0.2,height:0.2)], [.init(x:0.1,y:0.31,width:0.2,height:0.2)]]
        let seam = touch(0.2,0.695)
        var steno = KeyHitHighlightHistory(), normal = KeyHitHighlightHistory()
        steno.update([seam],rects:rows,buttons:[],isSteno:true,size:size,now:1)
        normal.update([seam],rects:rows,buttons:[],isSteno:false,size:size,now:1)
        XCTAssertEqual(steno.entries.count,2); XCTAssertEqual(normal.entries.count,0)
    }
    func testRotatedGeometryMissesInvalidPositionsAndMissingFramesCannotStick() {
        var history = KeyHitHighlightHistory()
        let rotated:[[NormalizedRect]] = [[.init(x:0.1,y:0.1,width:0.2,height:0.2,rotationDegrees:30)]]
        history.update([touch()],rects:rotated,buttons:[],isSteno:false,size:size,now:1)
        XCTAssertEqual(history.entries.count,1)
        history.prune(now:1.5)
        XCTAssertTrue(history.entries.values.allSatisfy { !$0.active && $0.opacity(at:1.5) < 1 })
        history.prune(now:2.5); XCTAssertTrue(history.entries.isEmpty)
        update(&history,[touch(.nan),touch(2)],now:3)
        XCTAssertTrue(history.entries.isEmpty)
    }
}

@MainActor final class KeyHighlightPreviewTests:XCTestCase {
    func testStenoAndOrdinaryLayoutsRenderContactHighlights() throws {
        guard let folder = ProcessInfo.processInfo.environment["KEY_HIGHLIGHT_PREVIEW_DIR"] else { return }
        let size = CGSize(width:432,height:310)
        for preset in [TrackpadLayoutPreset.steno,.touchstream] {
            var snapshot = TrackpadSurfaceSnapshot.empty
            snapshot.trackpadSize = size; snapshot.spacing = 16; snapshot.showDetailed = true
            snapshot.leftLayout = preset.isSteno ? StenoLayoutDefinition.layout(preset:preset,side:.left,size:size):ContentView.makeTouchStreamKeyLayout(size:size,side:.left)
            snapshot.rightLayout = preset.isSteno ? StenoLayoutDefinition.layout(preset:preset,side:.right,size:size):ContentView.makeTouchStreamKeyLayout(size:size,side:.right)
            snapshot.leftLabels = preset.leftLabels.map { $0.map { .init(primary:KeyActionCatalog.action(for:$0)?.displayText ?? $0) } }
            snapshot.rightLabels = preset.rightLabels.map { $0.map { .init(primary:KeyActionCatalog.action(for:$0)?.displayText ?? $0) } }
            let view = TrackpadSurfaceView(frame:.init(x:0,y:0,width:880,height:310)); view.snapshot = snapshot
            let left = snapshot.leftLayout.normalizedKeyRects[1].prefix(3).enumerated().map { index,rect in
                OMSTouchData(deviceID:"42",deviceIndex:4,id:Int32(index+1),position:.init(x:Float(rect.centerX),y:Float(1-rect.centerY)),total:1,pressure:50,axis:.init(major:5,minor:3),angle:0,density:1,state:.touching,timestamp:1)
            }
            view.updateTouches(left:left,right:[])
            let image = NSImage(size:view.bounds.size); image.lockFocusFlipped(true)
            NSColor.windowBackgroundColor.setFill(); view.bounds.fill(); view.draw(view.bounds); image.unlockFocus()
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data:try XCTUnwrap(image.tiffRepresentation)))
            try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:folder+"/"+preset.displayName+"-hits.png"))
        }
    }
}
