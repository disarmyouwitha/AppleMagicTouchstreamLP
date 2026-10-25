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
        for mirrored in [false,true] {
            defaults.set(mirrored,forKey:"AppleMagicTouchstream.mirrorGestureEdits")
            for narrow in [false,true] {
                defaults.set(narrow ? WorkspaceColumnSizing.minimumMenu : WorkspaceColumnSizing.defaultGestureColumnWidth,forKey:WorkspaceColumnSizing.gestureNavigationWidthKey)
                defaults.set(narrow ? WorkspaceColumnSizing.minimumInspector : WorkspaceColumnSizing.defaultGestureColumnWidth,forKey:WorkspaceColumnSizing.gestureInspectorWidthKey)
                for pane in GesturePane.allCases {
                    let movement = pane.triggers.first { GestureDirectionalAssignments.triggers.contains($0) }
                    for directional in (movement == nil ? [false] : [false,true]) {
                        var settings = HandGestureSettings()
                        if directional, let movement {
                            settings.editMovement(movement,mode:.directional,direction:.up,action:.volumeUpSmall,in:.both)
                            settings.editMovement(movement,mode:.directional,direction:.down,action:.volumeDownSmall,in:.both)
                            settings.editMovement(movement,mode:.directional,direction:.left,action:.brightnessDownSmall,in:.both)
                            settings.editMovement(movement,mode:.directional,direction:.right,action:.brightnessUpSmall,in:.both)
                        }
                        let viewportWidth: CGFloat = narrow ? 1024 : 1320
                        let view = GestureAssignmentWorkspace(settings:settings,initialPane:pane,initialDirection:directional ? .up : nil,
                            status:{_,_ in "Waiting for Trackpad Takeover."},
                            apply:{_,_,_ in XCTFail("Rendering must not change actions")},
                            setSensitivity:{_,_,_ in XCTFail("Rendering must not change sensitivity")},
                            setMovementMode:{_,_,_ in XCTFail("Rendering must not switch modes")},
                            setDirectionalAction:{_,_,_,_ in XCTFail("Rendering must not assign directions")},
                            setDirectionalRepeatInterval:{_,_,_,_ in XCTFail("Rendering must not change repeat")})
                            .defaultAppStorage(defaults)
                            .frame(width:viewportWidth,height:650)
                        // ImageRenderer omits native scroll views/controls on macOS. Render an
                        // offscreen hosting view instead; never show a window or initialize input.
                        let host = NSHostingView(rootView:view)
                        host.frame = NSRect(x:0,y:0,width:viewportWidth,height:650)
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
                                .write(to:url.appendingPathComponent("\(pane.rawValue)\(narrow ? "-narrow" : "")\(mirrored ? "-mirrored" : "")\(directional ? "-directional" : "").png"))
                        }
                        window.contentView = nil
                    }
                }
            }
        }
        if let directory = ProcessInfo.processInfo.environment["AMT_WORKSPACE_PREVIEW_DIR"] {
            for trigger in [GestureTrigger.twoFingerTap,.threeFingerTap,.oneFingerForce,.twoFingerForce,.threeFingerForce,.fourFingerForce,.fiveFingerForce,.twoFingerMove,.threeFingerMove,.fourFingerMove,.twoFingerPinch,.twoFingerSpread,.fourFingerPinch,.fourFingerSpread,.threeFingerPinch,.threeFingerSpread,.fiveFingerPinch,.fiveFingerSpread] {
                let pane: GesturePane
                switch trigger {
                case .twoFingerPinch,.twoFingerSpread: pane = .twoFingerPinch
                case .fourFingerPinch,.fourFingerSpread: pane = .fourFingerPinch
                case .threeFingerPinch,.threeFingerSpread: pane = .threeFingerPinch
                case .fiveFingerPinch,.fiveFingerSpread: pane = .fiveFingerPinch
                case .oneFingerForce: pane = .oneFinger
                case .threeFingerTap,.threeFingerMove,.threeFingerForce: pane = .threeFingers
                case .fourFingerMove,.fourFingerForce: pane = .fourFingers
                case .fiveFingerForce: pane = .fiveFingers
                default: pane = .twoFingers
                }
                let strip = HStack(spacing:16) {
                    ForEach((trigger.isContinuous && !trigger.isPinch) ? [0.02,0.10,0.20,0.35,0.46,0.52,0.60,0.70,0.85,0.96] : [0.08,0.30,0.60,0.90],id:\.self) { phase in
                        GestureChordIcon(gesture:pane,trigger:trigger,previewPhase:phase)
                    }
                }.padding(16).background(Color(nsColor:.windowBackgroundColor))
                let renderer = ImageRenderer(content:strip)
                let bitmap = NSBitmapImageRep(cgImage:try XCTUnwrap(renderer.cgImage))
                try XCTUnwrap(bitmap.representation(using:.png,properties:[:]))
                    .write(to:URL(fileURLWithPath:directory).appendingPathComponent("demo-\(trigger.rawValue).png"))
                if trigger.isContinuous && !trigger.isPinch {
                    for direction in GestureMovementDirection.allCases {
                        let directionalStrip = HStack(spacing:16) {
                            ForEach([0.03,0.16,0.40,0.67,0.82,0.96],id:\.self) { phase in
                                GestureChordIcon(gesture:pane,trigger:trigger,direction:direction,previewPhase:phase)
                            }
                        }.padding(16).background(Color(nsColor:.windowBackgroundColor))
                        let renderer = ImageRenderer(content:directionalStrip)
                        let bitmap = NSBitmapImageRep(cgImage:try XCTUnwrap(renderer.cgImage))
                        try XCTUnwrap(bitmap.representation(using:.png,properties:[:]))
                            .write(to:URL(fileURLWithPath:directory).appendingPathComponent("demo-\(trigger.rawValue)-\(direction.rawValue).png"))
                    }
                }
            }
        }
    }
}
