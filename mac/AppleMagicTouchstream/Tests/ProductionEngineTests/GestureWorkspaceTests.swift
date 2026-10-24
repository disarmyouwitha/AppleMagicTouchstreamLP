import AppKit
import SwiftUI
import XCTest
@testable import GlassToKeyRuntime

@MainActor
final class GestureWorkspaceTests: XCTestCase {
    func testCatalogExposesEveryExistingInputExactlyOnce() {
        let triggers = GesturePane.allCases.flatMap(\.triggers)
        XCTAssertEqual(Set(triggers),Set(GestureTrigger.allCases))
        XCTAssertEqual(triggers.count,Set(triggers).count)
        for pane in GesturePane.allCases {
            XCTAssertFalse(pane.triggers.isEmpty)
            for trigger in pane.triggers { XCTAssertTrue(pane.includes(trigger)) }
            if pane.isPinchSection {
                XCTAssertEqual(pane.triggers.count,2)
                XCTAssertTrue(pane.triggers.allSatisfy(\.isPinch))
                XCTAssertTrue(pane.contactLabel.contains("thumb required"))
            }
        }
    }

    func testBehaviorDescriptionsFollowExistingActionsWithoutAddingRecognizers() {
        XCTAssertEqual(GestureTrigger.twoFingerMove.behavior(for:.pointer),"Follow motion")
        XCTAssertEqual(GestureTrigger.twoFingerPinch.behavior(for:.missionControl),"Once on activation")
        XCTAssertEqual(GestureTrigger.twoFingerTap.behavior(for:.volumeDownSmall),"One step per recognition")
        XCTAssertEqual(GestureTrigger.oneFingerForce.behavior(for:.disabled),"No output")
        XCTAssertEqual(GestureTrigger.twoFingerTap.assignmentTitle,"Tap")
        XCTAssertEqual(GestureTrigger.twoFingerSpread.assignmentTitle,"Spread")
    }

    func testWorkspaceRendersExistingGestureFamiliesWithoutInputClients() throws {
        let suite = "GestureWorkspacePreview.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        for narrow in [false,true] {
            defaults.set(narrow ? WorkspaceColumnSizing.minimumMenu : WorkspaceColumnSizing.defaultGestureColumnWidth,forKey:WorkspaceColumnSizing.gestureNavigationWidthKey)
            defaults.set(narrow ? WorkspaceColumnSizing.minimumInspector : WorkspaceColumnSizing.defaultGestureColumnWidth,forKey:WorkspaceColumnSizing.gestureInspectorWidthKey)
            for pane in [GesturePane.twoFingers,.threeFingers,.threeFingerPinch,.thumbTwo,.oneFinger] {
                let view = GestureAssignmentWorkspace(settings:HandGestureSettings(),initialPane:pane,
                    status:{_,_ in "Waiting for Trackpad Takeover."},
                    apply:{_,_,_ in XCTFail("Rendering must not change actions")},
                    setSensitivity:{_,_,_ in XCTFail("Rendering must not change sensitivity")})
                    .defaultAppStorage(defaults)
                    .frame(width:1320,height:650)
                // ImageRenderer omits native scroll views/controls on macOS. Render an
                // offscreen hosting view instead; never show a window or initialize input.
                let host = NSHostingView(rootView:view)
                host.frame = NSRect(x:0,y:0,width:1320,height:650)
                let window = NSWindow(contentRect:host.frame,styleMask:[.borderless],backing:.buffered,defer:false)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds))
                host.cacheDisplay(in:host.bounds,to:bitmap)
                XCTAssertGreaterThan(bitmap.pixelsWide,0)
                XCTAssertGreaterThan(bitmap.pixelsHigh,0)
                if let directory = ProcessInfo.processInfo.environment["AMT_WORKSPACE_PREVIEW_DIR"] {
                    let url = URL(fileURLWithPath:directory,isDirectory:true)
                    try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
                    try XCTUnwrap(bitmap.representation(using:.png,properties:[:]))
                        .write(to:url.appendingPathComponent("\(pane.rawValue)\(narrow ? "-narrow" : "").png"))
                }
                window.contentView = nil

            }
        }
    }
}
