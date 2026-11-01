import XCTest
@testable import GlassToKeyRuntime

final class LayoutSelectionResizeTests: XCTestCase {
    private let pad = CGSize(width:160,height:114.9)
    private func mmWidth(_ frame: LayoutDocument.SelectionFrame) -> CGFloat { frame.rect.width*pad.width }
    private func mmHeight(_ frame: LayoutDocument.SelectionFrame) -> CGFloat { frame.rect.height*pad.height }
    private func assertPoint(_ a: CGPoint,_ b: CGPoint,file: StaticString = #filePath,line: UInt = #line) {
        XCTAssertEqual(a.x,b.x,accuracy:1e-9,file:file,line:line)
        XCTAssertEqual(a.y,b.y,accuracy:1e-9,file:file,line:line)
    }
    func testPercentageSpacingOpensTouchingKeysWithoutResizingAndMirrors() throws {
        var doc = LayoutDocument()
        let a = doc.addMirrored(right:false,rect:.init(x:0.2,y:0.1,width:0.1,height:0.1))
        let b = doc.addMirrored(right:false,rect:.init(x:0.2,y:0.2,width:0.1,height:0.1))
        let ids:Set<UUID> = [a,b], pad = CGSize(width:160,height:100), before = doc
        doc.scaleSelectionSpacing(ids,factor:1.05,pad:pad)
        doc.mirrorGeometryChanges(from:before,sources:ids)
        XCTAssertEqual(try XCTUnwrap(doc.selectionSpacing(ids,right:false,axisX:false,pad:pad)),0.5,accuracy:0.00001)
        XCTAssertEqual(doc.keys[0].rect,before.keys[0].rect)
        XCTAssertEqual(doc.keys[2].rect.y,doc.keys[3].rect.y,accuracy:0.00001)
        for (old,new) in zip(before.keys,doc.keys) { XCTAssertEqual(old.rect.width,new.rect.width); XCTAssertEqual(old.rect.height,new.rect.height) }
        doc.scaleSelectionSpacing(ids,factor:0.95,pad:pad)
        XCTAssertEqual(try XCTUnwrap(doc.selectionSpacing(ids,right:false,axisX:false,pad:pad)),-0.025,accuracy:0.00001)
    }
    func testSelectionSpacingChangesOnlyGapsAndMirrorsWithoutResizing() throws {
        var doc = LayoutDocument()
        let a = doc.addMirrored(right:false,rect:.init(x:0.2,y:0.1,width:0.1,height:0.1))
        let b = doc.addMirrored(right:false,rect:.init(x:0.2,y:0.25,width:0.1,height:0.1))
        let c = doc.addMirrored(right:false,rect:.init(x:0.2,y:0.4,width:0.1,height:0.1))
        let ids:Set<UUID> = [a,b,c], pad = CGSize(width:160,height:100), before = doc
        XCTAssertNil(doc.selectionSpacing(ids,right:false,axisX:true,pad:pad))
        XCTAssertEqual(try XCTUnwrap(doc.selectionSpacing(ids,right:false,axisX:false,pad:pad)),5,accuracy:0.00001)
        doc.setSelectionSpacing(ids,axisX:false,millimeters:-1,pad:pad)
        doc.mirrorGeometryChanges(from:before,sources:ids)
        XCTAssertEqual(try XCTUnwrap(doc.selectionSpacing(ids,right:false,axisX:false,pad:pad)),-1,accuracy:0.00001)
        XCTAssertEqual(doc.keys.first {$0.id == a}?.rect,before.keys.first {$0.id == a}?.rect)
        for (old,new) in zip(before.keys,doc.keys) {
            XCTAssertEqual(old.rect.width,new.rect.width); XCTAssertEqual(old.rect.height,new.rect.height)
            XCTAssertEqual(old.label,new.label); XCTAssertEqual(old.mirrorID,new.mirrorID)
        }
        XCTAssertEqual(doc.keys[2].rect.y,0.19,accuracy:0.00001)
        XCTAssertEqual(doc.keys[4].rect.y,0.28,accuracy:0.00001)
        XCTAssertEqual(doc.keys[3].rect.y,doc.keys[2].rect.y,accuracy:0.00001)
    }
    func testSelectionSpacingUsesSharedRotatedAxesAndRetainsRows() throws {
        var doc = LayoutDocument(), ids = Set<UUID>()
        for x in [CGFloat(0.2),0.4] {
            for y in [CGFloat(0.2),0.4] { ids.insert(doc.add(right:true,rect:.init(x:x,y:y,width:0.1,height:0.1))) }
        }
        let pad = CGSize(width:100,height:100)
        doc.rotate(ids,degrees:30,pad:pad)
        let before = doc
        doc.setSelectionSpacing(ids,axisX:true,millimeters:2,pad:pad)
        XCTAssertEqual(try XCTUnwrap(doc.selectionSpacing(ids,right:true,axisX:true,pad:pad)),2,accuracy:0.00001)
        XCTAssertEqual(try XCTUnwrap(doc.selectionSpacing(ids,right:true,axisX:false,pad:pad)),10,accuracy:0.00001)
        for (a,b) in zip(before.keys,doc.keys) { XCTAssertEqual(a.rect.width,b.rect.width); XCTAssertEqual(a.rect.rotationDegrees,b.rect.rotationDegrees) }
    }

    func testTemporarySelectionScalesKeysAndSpacingWithoutCreatingGroups() throws {
        var doc = LayoutDocument()
        let a = doc.add(right:true,label:"A",rect:.init(x:0.1,y:0.2,width:0.1,height:0.2))
        let b = doc.add(right:true,label:"B",rect:.init(x:0.3,y:0.5,width:0.2,height:0.1))
        let untouched = doc.add(right:true,label:"C",rect:.init(x:0.8,y:0.8,width:0.05,height:0.1))
        let before = doc
        let ids: Set<UUID> = [a,b]
        let initial = try XCTUnwrap(doc.selectionFrame(ids,right:true,pad:pad))
        XCTAssertTrue(doc.resizeSelection(ids,scaleX:2,scaleY:0.5,pad:pad))
        let after = try XCTUnwrap(doc.selectionFrame(ids,right:true,pad:pad))
        XCTAssertEqual(mmWidth(after),mmWidth(initial)*2,accuracy:1e-9)
        XCTAssertEqual(mmHeight(after),mmHeight(initial)*0.5,accuracy:1e-9)
        assertPoint(after.rect.corners(in:pad)[0],initial.rect.corners(in:pad)[0])
        XCTAssertEqual(doc.keys[0].rect.x,0.1,accuracy:1e-12)
        XCTAssertEqual(doc.keys[1].rect.x,0.5,accuracy:1e-12)
        XCTAssertEqual(doc.keys[1].rect.y,0.35,accuracy:1e-12)
        XCTAssertEqual(doc.keys.first {$0.id == untouched},before.keys.first {$0.id == untouched})
        XCTAssertEqual(doc.keys.map(\.id),before.keys.map(\.id))
        XCTAssertEqual(doc.keys.map(\.row),before.keys.map(\.row))
        XCTAssertEqual(doc.keys.map(\.label),before.keys.map(\.label))
        XCTAssertTrue(doc.groups.isEmpty)
        XCTAssertTrue(doc.isValid)
    }
    func testCommonRotationResizesInSharedAxesAndKeepsRotations() throws {
        var doc = LayoutDocument()
        let a = doc.add(right:false,rect:.init(x:0.25,y:0.2,width:0.1,height:0.2,rotationDegrees:30))
        let b = doc.add(right:false,rect:.init(x:0.3,y:0.5,width:0.15,height:0.2,rotationDegrees:30))
        let ids: Set<UUID> = [a,b]
        let initial = try XCTUnwrap(doc.selectionFrame(ids,right:false,pad:pad))
        XCTAssertTrue(initial.allowsIndependentAxes)
        XCTAssertEqual(initial.rect.rotationDegrees,30)
        doc.resizeSelection(ids,scaleX:1.4,scaleY:0.7,pad:pad)
        let after = try XCTUnwrap(doc.selectionFrame(ids,right:false,pad:pad))
        XCTAssertEqual(mmWidth(after),mmWidth(initial)*1.4,accuracy:1e-9)
        XCTAssertEqual(mmHeight(after),mmHeight(initial)*0.7,accuracy:1e-9)
        assertPoint(after.rect.corners(in:pad)[0],initial.rect.corners(in:pad)[0])
        XCTAssertEqual(doc.keys.map {$0.rect.rotationDegrees},[30,30])
    }
    func testMemberCornerScalesWholeSelectionAboutThatMembersOppositeCorner() throws {
        var doc = LayoutDocument()
        let a = doc.add(right:true,rect:.init(x:0.2,y:0.2,width:0.1,height:0.15,rotationDegrees:20))
        let b = doc.add(right:true,rect:.init(x:0.35,y:0.5,width:0.15,height:0.2,rotationDegrees:20))
        let before = doc
        let anchor = doc.keys[1].rect.corners(in:pad)[0]
        doc.resizeSelection([a,b],scaleX:1.3,scaleY:0.8,pad:pad,referenceKey:b)
        assertPoint(doc.keys[1].rect.corners(in:pad)[0],anchor)
        for i in doc.keys.indices {
            XCTAssertEqual(doc.keys[i].rect.width,before.keys[i].rect.width*1.3,accuracy:1e-12)
            XCTAssertEqual(doc.keys[i].rect.height,before.keys[i].rect.height*0.8,accuracy:1e-12)
            XCTAssertEqual(doc.keys[i].rect.rotationDegrees,20)
        }
        XCTAssertNotEqual(doc.keys[0].rect,before.keys[0].rect)
    }
    func testMixedRotationsScaleProportionallyWithoutShearingKeys() throws {
        var doc = LayoutDocument()
        let a = doc.add(right:false,rect:.init(x:0.2,y:0.2,width:0.1,height:0.2))
        let b = doc.add(right:false,rect:.init(x:0.4,y:0.4,width:0.15,height:0.2,rotationDegrees:25))
        let ids: Set<UUID> = [a,b], before = doc
        let frame = try XCTUnwrap(doc.selectionFrame(ids,right:false,pad:pad))
        XCTAssertFalse(frame.allowsIndependentAxes)
        XCTAssertFalse(doc.resizeSelection(ids,scaleX:1.2,scaleY:0.8,pad:pad))
        XCTAssertEqual(doc,before)
        XCTAssertTrue(doc.resizeSelection(ids,scaleX:1.2,scaleY:1.2,pad:pad))
        let after = try XCTUnwrap(doc.selectionFrame(ids,right:false,pad:pad))
        XCTAssertEqual(mmWidth(after),mmWidth(frame)*1.2,accuracy:1e-9)
        XCTAssertEqual(mmHeight(after),mmHeight(frame)*1.2,accuracy:1e-9)
        XCTAssertEqual(doc.keys.map {$0.rect.rotationDegrees},[0,25])
    }
    func testUniformSizeLimitsPreserveRelativeSizesAndSpacing() throws {
        var doc = LayoutDocument()
        let a = doc.add(right:true,rect:.init(x:0.2,y:0.2,width:0.01,height:0.02))
        let b = doc.add(right:true,rect:.init(x:0.3,y:0.3,width:0.02,height:0.04))
        let before = doc
        doc.resizeSelection([a,b],scaleX:0.0001,scaleY:0.0001,pad:pad)
        XCTAssertEqual(doc.keys[0].rect.width,0.005,accuracy:1e-12)
        XCTAssertEqual(doc.keys[1].rect.width,0.01,accuracy:1e-12)
        let oldDistance = before.keys[1].rect.centerX-before.keys[0].rect.centerX
        XCTAssertEqual(doc.keys[1].rect.centerX-doc.keys[0].rect.centerX,oldDistance*0.5,accuracy:1e-12)
    }
    func testMirroredResizeUndoAndRoundTripRetainGroupsLinksAndOverlap() throws {
        var doc = LayoutDocument()
        let group = LayoutDocument.Group(name:"Column"); doc.groups.append(group)
        let other = LayoutDocument.Group(name:"Other column"); doc.groups.append(other)
        let a = doc.addMirrored(right:false,rect:.init(x:0.2,y:0.2,width:0.1,height:0.2),group:group.id,oppositeGroup:other.id)
        let b = doc.addMirrored(right:false,rect:.init(x:0.2,y:0.4,width:0.1,height:0.2),group:group.id,oppositeGroup:other.id)
        for i in doc.keys.indices { doc.keys[i].edges = [0,0.01,0,0.01] }
        let before = doc
        var history = LayoutDocumentHistory(); history.record(before)
        doc.resizeSelection([a,b],scaleX:1.3,scaleY:0.9,pad:pad)
        doc.mirrorGeometryChanges(from:before,sources:[a,b])
        for key in doc.keys where !key.right {
            let partner = try XCTUnwrap(doc.keys.first {$0.id == key.mirrorID})
            XCTAssertEqual(partner.rect.x,1-key.rect.x-key.rect.width,accuracy:1e-12)
            XCTAssertEqual(partner.rect.y,key.rect.y,accuracy:1e-12)
            XCTAssertEqual(partner.rect.width,key.rect.width,accuracy:1e-12)
            XCTAssertEqual(partner.rect.height,key.rect.height,accuracy:1e-12)
        }
        XCTAssertEqual(doc.keys.map(\.group),before.keys.map(\.group))
        XCTAssertEqual(doc.keys.map(\.mirrorID),before.keys.map(\.mirrorID))
        XCTAssertEqual(doc.keys.map(\.edges),before.keys.map(\.edges))
        XCTAssertEqual(doc.expandedGroups([a]),[a,b])
        let restored = try JSONDecoder().decode(LayoutDocument.self,from:JSONEncoder().encode(doc))
        XCTAssertEqual(restored,doc)
        let resized = doc
        doc = try XCTUnwrap(history.undo(doc)); XCTAssertEqual(doc,before)
        doc = try XCTUnwrap(history.redo(doc)); XCTAssertEqual(doc,resized)
        XCTAssertTrue(doc.isValid)
    }
    func testResizeAcrossPadsUsesSeparateAnchors() throws {
        var doc = LayoutDocument()
        let left = doc.add(right:false,rect:.init(x:0.1,y:0.1,width:0.1,height:0.1))
        let right = doc.add(right:true,rect:.init(x:0.7,y:0.6,width:0.1,height:0.1))
        doc.resizeSelection([left,right],scaleX:1.2,scaleY:1.2,pad:pad)
        XCTAssertEqual(doc.keys[0].rect.x,0.1,accuracy:1e-12)
        XCTAssertEqual(doc.keys[1].rect.x,0.7,accuracy:1e-12)
        XCTAssertEqual(doc.keys[1].rect.y,0.6,accuracy:1e-12)
    }
    func testIdentityResizeAndMirrorAreExactNoOps() {
        var doc = LayoutDocument()
        let id = doc.addMirrored(right:true,rect:.init(x:0.1,y:0.2,width:0.123456,height:0.234567))
        let before = doc
        XCTAssertFalse(doc.resizeSelection([id],scaleX:1,scaleY:1,pad:pad))
        doc.mirrorGeometryChanges(from:before,sources:[id])
        XCTAssertEqual(doc,before)
        XCTAssertFalse(doc.resizeSelection([id],scaleX:.nan,scaleY:1,pad:pad))
        XCTAssertFalse(doc.resizeSelection([id],scaleX:-1,scaleY:1,pad:pad))
        XCTAssertEqual(doc,before)
    }
    func testPartialSavedGroupCanResizeIndependentlyWithoutLosingMembership() {
        var doc = LayoutDocument()
        let group = LayoutDocument.Group(name:"Saved"); doc.groups.append(group)
        let a = doc.add(right:true,group:group.id), b = doc.add(right:true,group:group.id)
        let before = doc
        doc.resizeSelection([a],scaleX:1.2,scaleY:1.2,pad:pad)
        XCTAssertEqual(doc.keys[1],before.keys[1])
        XCTAssertEqual(doc.expandedGroups([a]),[a,b])
        XCTAssertEqual(doc.groups,before.groups)
    }
}
