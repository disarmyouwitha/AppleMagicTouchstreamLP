import AppKit
import SwiftUI
import XCTest
@testable import GlassToKeyRuntime

@MainActor
final class GestureWorkspaceTests: XCTestCase {
    func testDirectionalPagesDefaultToUpWithoutChangingSavedMode() {
        var settings = HandGestureSettings()
        let original = settings
        XCTAssertNil(GestureAssignmentWorkspace.defaultDirection(for:.threeFingerMove,settings:settings,scope:.left))
        settings.editMovement(.threeFingerMove,mode:.directional,in:.left)
        XCTAssertEqual(GestureAssignmentWorkspace.defaultDirection(for:.threeFingerMove,settings:settings,scope:.left),.up)
        XCTAssertNil(GestureAssignmentWorkspace.defaultDirection(for:.threeFingerMove,settings:settings,scope:.right))
        XCTAssertNil(GestureAssignmentWorkspace.defaultDirection(for:.threeFingerMove,settings:settings,scope:.both))
        XCTAssertNil(GestureAssignmentWorkspace.defaultDirection(for:.threeFingerTap,settings:settings,scope:.left))
        settings.editMovement(.threeFingerMove,mode:.directional,in:.both)
        XCTAssertEqual(GestureAssignmentWorkspace.defaultDirection(for:.threeFingerMove,settings:settings,scope:.both),.up)
        for trigger in [GestureTrigger.twoFingerMove,.fourFingerMove,.fiveFingerMove] {
            settings.editMovement(trigger,mode:.directional,in:.both)
            XCTAssertEqual(GestureAssignmentWorkspace.defaultDirection(for:trigger,settings:settings,scope:.both),.up)
        }
        XCTAssertEqual(settings.left.bindings,original.left.bindings)
        XCTAssertEqual(settings.right.bindings,original.right.bindings)
    }

    func testHoldEditingUsesPageRegardlessOfMovementOrPinchAssignments() {
        var settings = HandGestureSettings()
        XCTAssertFalse(GestureAssignmentWorkspace.holdEditable(pane:.oneFinger,settings:settings,scope:.left))
        XCTAssertTrue(GestureAssignmentWorkspace.holdEditable(pane:.twoFingers,settings:settings,scope:.left))
        settings.editMovement(.twoFingerMove,mode:.directional,in:.left)
        XCTAssertTrue(GestureAssignmentWorkspace.holdEditable(pane:.twoFingers,settings:settings,scope:.left))
        XCTAssertEqual(settings.left.bindings.action(for:.twoFingerPinch),.zoom)
        XCTAssertFalse(GestureAssignmentWorkspace.holdEditable(pane:.twoFingerPinch,settings:settings,scope:.left))
        XCTAssertTrue(GestureAssignmentWorkspace.holdEditable(pane:.twoFingers,settings:settings,scope:.both))
        for count in 2...5 {
            settings.setAction(.disabled,for:GestureTrigger.pinch(count:count)!,in:.both)
            settings.setAction(.disabled,for:GestureTrigger.spread(count:count)!,in:.both)
        }
        for pane in GesturePane.allCases where pane.isPinchSection {
            XCTAssertFalse(GestureAssignmentWorkspace.holdEditable(pane:pane,settings:settings,scope:.left))
        }
    }
    func testHoldCardAndRightInspectorRenderWithoutInput() throws {
        var settings = HandGestureSettings()
        settings.setHoldAction(.shortcut(.init(label:"Shift",holdUntilRelease:true)),count:2,in:.left)
        let view = GestureAssignmentWorkspace(settings:settings,initialPane:.twoFingers,initialHold:true,
            status:{_,_ in "Offline"},apply:{_,_,_ in XCTFail("Unexpected action edit")},
            setSensitivity:{_,_,_ in XCTFail("Unexpected gain edit")},
            setHoldAction:{_,_,_ in XCTFail("Rendering must not assign Hold")})
            .frame(width:1320,height:1100)
        let host = NSHostingView(rootView:view)
        host.frame = NSRect(x:0,y:0,width:1320,height:1100)
        let window = NSWindow(contentRect:host.frame,styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentView = host; host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds))
        host.cacheDisplay(in:host.bounds,to:bitmap)
        if let directory = ProcessInfo.processInfo.environment["AMT_WORKSPACE_PREVIEW_DIR"] {
            let url = URL(fileURLWithPath:directory,isDirectory:true)
            try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
            try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:url.appendingPathComponent("hold-inspector.png"))
        }
        window.contentView = nil
    }

    func testCatalogExposesEveryExistingInputExactlyOnce() {
        let triggers = GesturePane.allCases.flatMap(\.triggers)
        let hidden = GestureTrigger.rotationTriggers.filter { $0.rotationCount == 2 || $0.rotationCount == 4 }
        XCTAssertEqual(Set(triggers),Set(GestureTrigger.allCases).subtracting(hidden))
        XCTAssertEqual(triggers.count,Set(triggers).count)
        for pane in GesturePane.allCases {
            XCTAssertFalse(pane.triggers.isEmpty)
            for trigger in pane.triggers { XCTAssertTrue(pane.includes(trigger)) }
            if pane.isPinchSection {
                XCTAssertEqual(pane.triggers.count,pane == .fiveFingerPinch ? 4 : 2)
                XCTAssertTrue(pane.triggers.prefix(2).allSatisfy(\.isPinch))
                if pane == .fiveFingerPinch { XCTAssertTrue(pane.triggers.suffix(2).allSatisfy(\.isRotation)) }
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

    func testBothWorkspaceRendersAllCoordinatedAssignmentsWithoutInput() throws {
        for chord in TwoHandChord.allCases {
            for phase in chord.phases {
                let view = GestureAssignmentWorkspace(settings:.init(),initialHand:.both,
                    initialTwoHandChord:chord,initialTwoHandPhase:phase,
                    status:{_,_ in "Offline"},apply:{_,_,_ in XCTFail("Unexpected single-pad edit")},
                    setSensitivity:{_,_,_ in XCTFail("Unexpected gain edit")},
                    setTwoHandAction:{_,_ in XCTFail("Rendering must not assign an action")})
                    .frame(width:1200,height:800)
                let host = NSHostingView(rootView:view)
                host.frame = NSRect(x:0,y:0,width:1200,height:800)
                let window = NSWindow(contentRect:host.frame,styleMask:[.borderless],backing:.buffered,defer:false)
                window.contentView = host; host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds))
                host.cacheDisplay(in:host.bounds,to:bitmap)
                XCTAssertGreaterThan(bitmap.pixelsHigh,0)
                if let directory = ProcessInfo.processInfo.environment["AMT_WORKSPACE_PREVIEW_DIR"] {
                    let url = URL(fileURLWithPath:directory,isDirectory:true)
                    try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
                    try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:url.appendingPathComponent("both-\(chord.rawValue)-\(phase.rawValue).png"))
                }
                window.contentView = nil
            }
        }
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
                            if mirrored {
                                settings.editMovement(movement,mode:.directional,direction:.up,action:movement == .fourFingerMove ? .panRight : .scrollUp,in:.both)
                                settings.editMovement(movement,mode:.directional,direction:.down,action:movement == .fourFingerMove ? .panLeft : .scrollDown,in:.both)
                            }
                            let count = movement == .twoFingerMove ? 2 : movement == .threeFingerMove ? 3 : movement == .fourFingerMove ? 4 : 5
                            settings.setAction(.disabled,for:GestureTrigger.pinch(count:count)!,in:.both)
                            settings.setAction(.disabled,for:GestureTrigger.spread(count:count)!,in:.both)
                            settings.setHoldAction(.missionControl,count:count,in:.both)
                        }
                        let viewportWidth: CGFloat = narrow ? 1024 : 1320
                        let view = GestureAssignmentWorkspace(settings:settings,initialPane:pane,initialDirection:directional ? .up : nil,
                            status:{_,_ in "Waiting for Trackpad Takeover."},
                            apply:{_,_,_ in XCTFail("Rendering must not change actions")},
                            setSensitivity:{_,_,_ in XCTFail("Rendering must not change sensitivity")},
                            setMovementMode:{_,_,_ in XCTFail("Rendering must not switch modes")},
                            setDirectionalAction:{_,_,_,_ in XCTFail("Rendering must not assign directions")},
                            setDirectionalRepeatInterval:{_,_,_,_ in XCTFail("Rendering must not change repeat")},
                            setDirectionalRepeat:{_,_,_,_ in XCTFail("Rendering must not toggle repeat")},
                            setHoldAction:{_,_,_ in XCTFail("Rendering must not assign Hold")})
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
            let holdStrip = HStack(spacing:16) {
                ForEach([0.0,0.15,0.60,0.80,0.86,0.94],id:\.self) { phase in
                    GestureChordIcon(gesture:.fourCorners,trigger:.fourCornersTap,holding:true,previewPhase:phase)
                }
            }.padding(16).background(Color(nsColor:.windowBackgroundColor))
            let holdRenderer = ImageRenderer(content:holdStrip)
            let holdBitmap = NSBitmapImageRep(cgImage:try XCTUnwrap(holdRenderer.cgImage))
            try XCTUnwrap(holdBitmap.representation(using:.png,properties:[:]))
                .write(to:URL(fileURLWithPath:directory).appendingPathComponent("demo-filled-hold.png"))
            for trigger in GestureTrigger.rotationTriggers.filter({ $0.rotationCount == 3 || $0.rotationCount == 5 }) + [GestureTrigger.twoFingerTap,.threeFingerTap,.fourFingerTap,.fiveFingerTap,.oneFingerForce,.twoFingerForce,.threeFingerForce,.fourFingerForce,.fiveFingerForce,.twoFingerMove,.threeFingerMove,.fourFingerMove,.fiveFingerMove,.twoFingerPinch,.twoFingerSpread,.fourFingerPinch,.fourFingerSpread,.threeFingerPinch,.threeFingerSpread,.fiveFingerPinch,.fiveFingerSpread] {
                let pane: GesturePane
                switch trigger {
                case .twoFingerPinch,.twoFingerSpread,.twoFingerRotateLeft,.twoFingerRotateRight: pane = .twoFingerPinch
                case .fourFingerPinch,.fourFingerSpread,.fourFingerRotateLeft,.fourFingerRotateRight: pane = .fourFingerPinch
                case .threeFingerPinch,.threeFingerSpread: pane = .threeFingerPinch
                case .threeFingerRotateLeft,.threeFingerRotateRight: pane = .thumbTwo
                case .fiveFingerPinch,.fiveFingerSpread,.fiveFingerRotateLeft,.fiveFingerRotateRight: pane = .fiveFingerPinch
                case .oneFingerForce: pane = .oneFinger
                case .threeFingerTap,.threeFingerMove,.threeFingerForce: pane = .threeFingers
                case .fourFingerTap,.fourFingerMove,.fourFingerForce: pane = .fourFingers
                case .fiveFingerTap,.fiveFingerMove,.fiveFingerForce: pane = .fiveFingers
                default: pane = .twoFingers
                }
                let strip = HStack(spacing:16) {
                    ForEach((trigger.isContinuous && !trigger.isPinch) ? [0.02,0.10,0.20,0.35,0.46,0.52,0.60,0.70,0.85,0.96] : [0.08,0.30,0.60,0.80,0.86,0.94,0.98],id:\.self) { phase in
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


extension GestureWorkspaceTests {
    func testSharedShortcutBuilderRendersWithoutAssigningOrOpeningApps() throws {
        XCTAssertEqual(WorkspaceColumnSizing.defaultGestureInspectorWidth,WorkspaceColumnSizing.defaultMenuWidth)
        for (name,label) in [("shift","Shift"),("shortcut","Cmd+S"),("app",AppLaunchActionHelper.createActionLabel(fileName:"/Applications/Calculator.app")!)] {
            let action = try XCTUnwrap(KeyActionCatalog.action(for:label))
            let view = ShortcutActionBuilder(action:action,allowsHold:true,holdUntilRelease:name == "shift") { _,_ in
                XCTFail("Rendering must not apply an action")
            }.padding(20).frame(width:381,height:340,alignment:.topLeading)
            let host = NSHostingView(rootView:view)
            host.frame = NSRect(x:0,y:0,width:381,height:340)
            let window = NSWindow(contentRect:host.frame,styleMask:[.borderless],backing:.buffered,defer:false)
            window.contentView = host; host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds))
            host.cacheDisplay(in:host.bounds,to:bitmap)
            if let directory = ProcessInfo.processInfo.environment["AMT_WORKSPACE_PREVIEW_DIR"] {
                let url = URL(fileURLWithPath:directory,isDirectory:true)
                try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
                try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:url.appendingPathComponent("shortcut-builder-"+name+".png"))
            }
            window.contentView = nil
        }
    }
}
