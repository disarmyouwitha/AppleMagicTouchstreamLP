import XCTest
import OpenMultitouchSupport
@testable import GlassToKeyRuntime

final class LayoutDocumentTests: XCTestCase {
    @MainActor func testStartupResolvesAuthoredButtonsWithoutOpeningConfigAndRejectsInvalidDocuments() throws {
        let name = "AMT.StartupLayoutTests."+UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName:name))
        defer { defaults.removePersistentDomain(forName:name) }
        XCTAssertNil(GlassToKeyController.startupLayoutDocument(for:.sixByThree,defaults:defaults))
        var doc = LayoutDocument()
        doc.add(right:false,label:"Space",rect:.init(x:0.75,y:0.68,width:0.25,height:0.32))
        doc.add(right:true,label:"Space",rect:.init(x:0,y:0.68,width:0.25,height:0.32))
        doc.add(right:true,label:"0",rect:.init(x:0.3,y:0.65,width:0.27,height:0.17),layer:1)
        defaults.set(try JSONEncoder().encode(["6x3":doc]),forKey:GlassToKeyDefaultsKeys.layoutDocuments)
        let restored = try XCTUnwrap(GlassToKeyController.startupLayoutDocument(for:.sixByThree,defaults:defaults))
        XCTAssertEqual(restored,doc)
        let size = CGSize(width:160,height:115), base = ContentViewModel.Layout(keyRects:[],trackpadSize:.init(width:160,height:115))
        let run = ProductionReplaySession(startTime:1)
        run.engine.updateLayouts(leftLayout:restored.compile(right:false,base:base,size:size),rightLayout:restored.compile(right:true,base:base,size:size),leftLabels:restored.labels(right:false),rightLabels:restored.labels(right:true),trackpadSize:size,trackpadWidthMm:160)
        run.engine.updateActiveDevices(leftIndex:0,rightIndex:1,leftDeviceID:"42",rightDeviceID:"43")
        run.engine.updateKeyMappings([0:["left:0:0":KeyMapping(primary:KeyActionCatalog.action(for:"Back")!,hold:nil)]])
        run.engine.updateKeyboardModeEnabled(true); run.engine.updateSnapRadiusPercent(0); run.engine.setListening(true)
        for side in 0...1 {
            let time = 1+Double(side), x:Float = side == 0 ? 0.875:0.125
            let touch = OMSRawTouch(id:1,posX:x,posY:0.16,total:1,pressure:100,majorAxis:5,minorAxis:3,angle:0,density:1,state:.touching)
            run.ingest(.init(sequence:UInt64(side*2+1),timestamp:time,deviceNumericID:side == 0 ? 42:43,deviceIndex:side,contacts:[],rawTouches:[touch]))
            run.ingest(.init(sequence:UInt64(side*2+2),timestamp:time+0.05,deviceNumericID:side == 0 ? 42:43,deviceIndex:side,contacts:[],rawTouches:[]))
        }
        let codes = run.output.events.compactMap { event -> CGKeyCode? in
            if case let .keyStroke(code,_,_) = event.kind { return code }; return nil
        }
        XCTAssertEqual(codes,[51,49],"Saved Back/Space must dispatch with no Config view ever created")
        XCTAssertFalse(restored.compile(right:true,base:base,size:size).isVisible(.init(side:.right,row:2,column:0),on:0))
        doc.keys[0].rect.width = 0
        defaults.set(try JSONEncoder().encode(["6x3":doc]),forKey:GlassToKeyDefaultsKeys.layoutDocuments)
        XCTAssertNil(GlassToKeyController.startupLayoutDocument(for:.sixByThree,defaults:defaults))
        defaults.set(Data("corrupt".utf8),forKey:GlassToKeyDefaultsKeys.layoutDocuments)
        XCTAssertNil(GlassToKeyController.startupLayoutDocument(for:.sixByThree,defaults:defaults))
    }

    func testDeletedSlotsNeverMoveOtherBindingsAndNewKeysNeverReuseAddresses() throws {
        var doc = LayoutDocument()
        let a = doc.add(right: true, label: "A"), b = doc.add(right: true, label: "B")
        let original = try XCTUnwrap(doc.keys.first { $0.id == b })
        doc.remove([a]); _ = doc.add(right: true, label: "C")
        XCTAssertEqual(doc.keys.first { $0.id == b }?.row, original.row)
        XCTAssertEqual(doc.labels(right: true), [[], ["B"], ["C"]])
        XCTAssertTrue(doc.isValid)
    }
    func testGroupTranslationPreservesSpacingAndStopsAtPadEdge() {
        var doc = LayoutDocument()
        let a = doc.add(right: true, rect: .init(x: 0.1,y: 0.2,width: 0.1,height: 0.2))
        let b = doc.add(right: true, rect: .init(x: 0.3,y: 0.2,width: 0.1,height: 0.2))
        doc.translate([a,b], dx: 9,dy: -9)
        XCTAssertEqual(doc.keys[0].rect.x, 0.7,accuracy: 0.00001)
        XCTAssertEqual(doc.keys[1].rect.x, 0.9,accuracy: 0.00001)
        XCTAssertEqual(doc.keys[0].rect.y, 0,accuracy: 0.00001)
    }
    func testDuplicateGetsIndependentIdentityGroupAndBindingAddress() throws {
        var doc = LayoutDocument()
        let group = LayoutDocument.Group(name: "Column"); doc.groups = [group]
        let a = doc.add(right: false,label: "A",group: group.id)
        let b = doc.add(right: false,label: "B",group: group.id)
        let copies = doc.duplicate([a,b])
        XCTAssertEqual(copies.count,2)
        let keys = doc.keys.filter { copies.contains($0.id) }
        XCTAssertEqual(Set(keys.map(\.group)).count,1)
        XCTAssertNotEqual(keys[0].group,group.id)
        XCTAssertEqual(keys.map(\.copySourceRow),[0,1])
        XCTAssertEqual(keys.map(\.row),[2,3])
        XCTAssertTrue(doc.isValid)
        XCTAssertEqual(try JSONDecoder().decode(LayoutDocument.self,from: JSONEncoder().encode(doc)),doc)
    }
    func testRotationUsesPhysicalDimensionsAndPreservesPairDistance() {
        var doc = LayoutDocument()
        let a = doc.add(right: true,rect: .init(x: 0.2,y: 0.3,width: 0.1,height: 0.1))
        let b = doc.add(right: true,rect: .init(x: 0.4,y: 0.3,width: 0.1,height: 0.1))
        doc.rotate([a,b],degrees: 90,pad: CGSize(width: 160,height: 100))
        XCTAssertEqual(doc.keys[0].rect.centerX,doc.keys[1].rect.centerX,accuracy: 0.00001)
        XCTAssertEqual((doc.keys[1].rect.centerY-doc.keys[0].rect.centerY)*100,32,accuracy: 0.00001)
        XCTAssertEqual(doc.keys[0].rect.rotationDegrees,90)
        doc.rotate([a,b],degrees: -90,pad: CGSize(width: 160,height: 100))
        XCTAssertEqual(doc.keys[0].rect.x,0.2,accuracy: 0.00001)
        XCTAssertEqual(doc.keys[1].rect.x,0.4,accuracy: 0.00001)
    }
    func testUndoRedoRestoreWholeDocumentsAndBranchClearsRedo() throws {
        var doc = LayoutDocument(), history = LayoutDocumentHistory()
        history.record(doc)
        let key = doc.add(right: true,label: "A")
        let added = doc
        history.record(doc); doc.translate([key],dx: 0.1,dy: 0.1)
        let moved = doc
        doc = try XCTUnwrap(history.undo(doc)); XCTAssertEqual(doc,added)
        doc = try XCTUnwrap(history.redo(doc)); XCTAssertEqual(doc,moved)
        doc = try XCTUnwrap(history.undo(doc))
        history.record(doc); doc.remove([key])
        XCTAssertFalse(history.canRedo)
        doc = try XCTUnwrap(history.undo(doc)); XCTAssertEqual(doc,added)
        doc = try XCTUnwrap(history.undo(doc)); XCTAssertEqual(doc,LayoutDocument())
        XCTAssertFalse(history.canUndo)
    }
    @MainActor func testDeletingPrunesAssignmentsAndDuplicateCopiesAllLayers() throws {
        var doc = LayoutDocument()
        let a = doc.add(right: true,label: "A"), b = doc.add(right: true,label: "B")
        let aSlot = GridKeyPosition(side: .right,row: 0,column: 0).storageKey
        let bSlot = GridKeyPosition(side: .right,row: 1,column: 0).storageKey
        let action = try XCTUnwrap(KeyActionCatalog.action(for: "A"))
        let mapping = KeyMapping(primary: action,hold: nil)
        let mappings: LayeredKeyMappings = [0: [aSlot: mapping,bSlot: mapping],1: [bSlot: mapping]]
        doc.remove([a]); let copied = doc.duplicate([b])
        let key = try XCTUnwrap(doc.keys.first { copied.contains($0.id) })
        let copySlot = GridKeyPosition(side: .right,row: key.row,column: key.column).storageKey
        let updated = doc.updatedMappings(mappings)
        XCTAssertNil(updated[0]?[aSlot])
        XCTAssertEqual(updated[0]?[copySlot],mapping)
        XCTAssertEqual(updated[1]?[copySlot],mapping)
        doc.remove([b,key.id])
        XCTAssertTrue(doc.updatedMappings(updated).values.allSatisfy(\.isEmpty))
    }
    func testInvalidDocumentsRejected() {
        var doc = LayoutDocument(); _ = doc.add(right: true)
        doc.keys[0].rect.x = .nan; XCTAssertFalse(doc.isValid)
        doc.keys[0].rect.x = 0; doc.keys.append(doc.keys[0]); XCTAssertFalse(doc.isValid)
        doc.keys.removeLast(); doc.keys[0].row = 9999; XCTAssertFalse(doc.isValid)
    }
    @MainActor func testEveryTemplateSeedsAndCompilesWithoutChangingGeometryOrMetadata() throws {
        for preset in [TrackpadLayoutPreset.steno, .stenoSingle, .stenoVoyager, .touchstream, .sixByThree] {
            let size = CGSize(width: 800,height: 574.5)
            func layout(_ right: Bool) -> ContentViewModel.Layout {
                if preset.isSteno { return StenoLayoutDefinition.layout(preset: preset,side: right ? .right:.left,size: size,pointerMode: .twoFinger,forceThreshold: 175,includeHovering: true,minimumPressPressure: 12,connectionMode: .plugin,hapticRelease: true) }
                if preset == .touchstream { return ContentView.makeTouchStreamKeyLayout(size: size,side: right ? .right:.left,keyGeometryOverrides: [:]) }
                return ContentView.makeKeyLayout(size: size,keyWidth: ContentView.baseKeyWidthMM,keyHeight: ContentView.baseKeyHeightMM,columns: preset.columns,rows: preset.rows,trackpadWidth: ContentView.trackpadWidthMM,trackpadHeight: ContentView.trackpadHeightMM,columnAnchorsMM: preset.columnAnchors,columnSettings: ColumnLayoutDefaults.defaultSettings(columns: preset.columns),keySpacingPercent: 10,mirrored: !right)
            }
            let left = layout(false), right = layout(true)
            let doc = LayoutDocument.seed(left: left,right: right,leftLabels: preset.leftLabels,rightLabels: preset.rightLabels)
            XCTAssertTrue(doc.isValid,preset.rawValue)
            for (isRight,base) in [(false,left),(true,right)] {
                let compiled = doc.compile(right: isRight,base: base,size: size)
                XCTAssertEqual(compiled.normalizedKeyRects,base.normalizedKeyRects,preset.rawValue)
                XCTAssertEqual(compiled.isSteno,base.isSteno)
                XCTAssertEqual(compiled.stenoIncludeHovering,base.stenoIncludeHovering)
                XCTAssertEqual(compiled.stenoMinimumPressPressure,base.stenoMinimumPressPressure)
                XCTAssertEqual(compiled.stenoForceThreshold,base.stenoForceThreshold)
                XCTAssertEqual(compiled.stenoHapticRelease,base.stenoHapticRelease)
                for rows in base.normalizedKeyRects { for rect in rows {
                    let a = TrackpadSurfaceView.stenoDisplayRect(rect,layout: compiled), b = TrackpadSurfaceView.stenoDisplayRect(rect,layout: base)
                    XCTAssertEqual(a.x,b.x,accuracy: 1e-12); XCTAssertEqual(a.y,b.y,accuracy: 1e-12)
                    XCTAssertEqual(a.width,b.width,accuracy: 1e-12); XCTAssertEqual(a.height,b.height,accuracy: 1e-12)
                } }
            }
        }
    }
    @MainActor func testRemovedMappedSlotCompilesAsZeroAreaAndProfileExportRoundTrips() throws {
        var doc = LayoutDocument()
        let a = doc.add(right: true,label: "A")
        _ = doc.add(right: true,label: "B")
        _ = doc.add(right: true,label: "C")
        doc.remove([a])
        let base = ContentViewModel.Layout(keyRects: [],trackpadSize: .init(width: 800,height: 574.5))
        let compiled = doc.compile(right: true,base: base,size: .init(width: 800,height: 574.5))
        XCTAssertTrue(compiled.keyRects[0].isEmpty)
        var profile = AppKeymapProfile.defaultProfile()
        profile.layoutDocuments = [TrackpadLayoutPreset.sixByThree.rawValue: doc]
        let exported = try PortableKeymapInterop.exportBundle(from: profile)
        let restored = try PortableKeymapInterop.importProfile(from: exported,currentProfile: .defaultProfile())
        XCTAssertEqual(restored.layoutDocuments,profile.layoutDocuments)
        let captured = try JSONDecoder().decode(AppKeymapProfile.self,from: JSONEncoder().encode(profile))
        XCTAssertEqual(captured.layoutDocuments,profile.layoutDocuments)
    }
    @MainActor func testLayerScopedKeysRoundTripCompileAndFilterEditorHits() throws {
        var doc = LayoutDocument()
        let shared = doc.add(right:true,label:"A",rect:.init(x:0.1,y:0.2,width:0.1,height:0.2))
        let scoped = doc.addMirrored(right:true,label:"B",rect:.init(x:0.4,y:0.2,width:0.1,height:0.2),layer:2)
        let pad = CGSize(width:160,height:115)
        XCTAssertTrue(doc.isValid)
        XCTAssertTrue(doc.keys.first { $0.id == shared }!.isVisible(on:0))
        XCTAssertTrue(doc.keys.filter { $0.id != shared }.allSatisfy { $0.layers == [2] })
        XCTAssertNil(doc.editorHit(at:.init(x:0.45,y:0.3),right:true,pad:pad,layer:0))
        XCTAssertEqual(doc.editorHit(at:.init(x:0.45,y:0.3),right:true,pad:pad,layer:2),scoped)
        XCTAssertEqual(doc.editorMarquee(.init(x:0,y:0,width:1,height:1),right:true,groups:false,pad:pad,layer:0),[shared])
        let copies = doc.duplicate([scoped])
        XCTAssertTrue(doc.keys.filter { copies.contains($0.id) }.allSatisfy { $0.layers == [2] })
        let base = ContentViewModel.Layout(keyRects:[],trackpadSize:pad)
        let layout = doc.compile(right:true,base:base,size:pad)
        let position = GridKeyPosition(side:.right,row:1,column:0)
        XCTAssertFalse(layout.isVisible(position,on:0))
        XCTAssertTrue(layout.isVisible(position,on:2))
        XCTAssertEqual(layout.visible(on:0,size:pad).keyRects[1][0].width,0)
        XCTAssertGreaterThan(layout.visible(on:2,size:pad).keyRects[1][0].width,0)
        XCTAssertGreaterThan(layout.visible(on:0,size:pad).keyRects[0][0].width,0)
        var profile = AppKeymapProfile.defaultProfile()
        profile.layoutDocuments = [TrackpadLayoutPreset.sixByThree.rawValue:doc]
        let exported = try PortableKeymapInterop.exportBundle(from:profile)
        let restored = try PortableKeymapInterop.importProfile(from:exported,currentProfile:.defaultProfile())
        XCTAssertEqual(restored.layoutDocuments,profile.layoutDocuments)
        XCTAssertEqual(try JSONDecoder().decode(LayoutDocument.self,from:JSONEncoder().encode(doc)),doc)
        var invalid = doc
        invalid.keys[0].layers = []
        XCTAssertFalse(invalid.isValid)
        invalid.keys[0].layers = [4]
        XCTAssertFalse(invalid.isValid)
        invalid.keys[0].layers = [1,1]
        XCTAssertFalse(invalid.isValid)
    }
    func testLegacyKeysWithoutLayerFieldRemainShared() throws {
        var doc = LayoutDocument()
        doc.add(right:true,label:"A")
        let data = try JSONEncoder().encode(doc)
        XCTAssertFalse(String(decoding:data,as:UTF8.self).contains("layers"))
        let restored = try JSONDecoder().decode(LayoutDocument.self,from:data)
        XCTAssertTrue(KeyLayerConfig.editableLayers.allSatisfy { restored.keys[0].isVisible(on:$0) })
    }

}
