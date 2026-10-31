import AppKit
import OpenMultitouchSupport
import QuartzCore
import XCTest
@testable import GlassToKeyRuntime

@MainActor final class KeyHighlightTests:XCTestCase {
    private let rect = NormalizedRect(x:0.1,y:0.1,width:0.2,height:0.2,rotationDegrees:30)
    func testAcceptedChordKeysFadeIndependentlyAndRetriggerOnlyTheirOwnKey() throws {
        var history = KeyHitHighlightHistory()
        history.record(key:.grid(0,0),rect:rect,time:1)
        history.record(key:.grid(0,1),rect:rect,time:1)
        XCTAssertEqual(history.entries.count,2)
        XCTAssertEqual(history.entries[.grid(0,0)]?.rect,rect)
        XCTAssertEqual(try XCTUnwrap(history.entries[.grid(0,0)]).opacity(at:1.6),0.5,accuracy:0.001)
        history.record(key:.grid(0,0),rect:rect,time:1.6)
        XCTAssertEqual(history.entries[.grid(0,0)]?.opacity(at:1.6),1)
        XCTAssertEqual(try XCTUnwrap(history.entries[.grid(0,1)]).opacity(at:1.6),0.5,accuracy:0.001)
        history.prune(now:2.21); XCTAssertEqual(history.entries.count,1)
        history.prune(now:2.81); XCTAssertTrue(history.entries.isEmpty)
    }
    func testRawGestureTouchesNeverLightKeysAndOnlyAcceptedFeedbackDoes() {
        let view = TrackpadSurfaceView(frame:.init(x:0,y:0,width:320,height:115))
        let touch = OMSTouchData(deviceID:"42",deviceIndex:0,id:1,position:.init(x:0.2,y:0.8),total:1,pressure:50,axis:.init(major:5,minor:3),angle:0,density:1,state:.touching,timestamp:1)
        view.updateTouches(left:[touch],right:[])
        XCTAssertEqual(view.keyHighlightCount,0)
        var snapshot = TrackpadSurfaceSnapshot.empty
        snapshot.acceptedKeyHits = [.init(rect:.zero,label:"F",side:.left,timestamp:CACurrentMediaTime(),id:1,normalizedRect:rect,position:.init(side:.left,row:0,column:0),customButtonID:nil)]
        view.snapshot = snapshot
        XCTAssertEqual(view.keyHighlightCount,1)
        view.snapshot = snapshot // Publishing the same event must not restart its fade.
        XCTAssertEqual(view.keyHighlightCount,1)
    }
    func testGestureFeedbackPersistsBrieflyAfterReleaseAndExpires() {
        let value = GestureRecognitionFeedback(kind:.gesture(.threeFingerMove),time:1)
        XCTAssertTrue(value.visible(at:2.9)); XCTAssertFalse(value.visible(at:3))
        XCTAssertFalse(value.visible(at:0.9))
        XCTAssertEqual(GestureRecognitionFeedback.Kind.stenoDrag.title,"1F drag/select")
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
            snapshot.acceptedKeyHits = snapshot.leftLayout.normalizedKeyRects[1].prefix(3).enumerated().map { index,rect in
                .init(rect:.zero,label:"key",side:.left,timestamp:CACurrentMediaTime(),id:UInt64(index+1),normalizedRect:rect,position:.init(side:.left,row:1,column:index),customButtonID:nil)
            }
            view.snapshot = snapshot
            view.updateTouches(left:left,right:[])
            let image = NSImage(size:view.bounds.size); image.lockFocusFlipped(true)
            NSColor.windowBackgroundColor.setFill(); view.bounds.fill(); view.draw(view.bounds); image.unlockFocus()
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data:try XCTUnwrap(image.tiffRepresentation)))
            try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:folder+"/"+preset.displayName+"-hits.png"))
        }
    }
}
