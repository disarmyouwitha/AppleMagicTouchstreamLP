import AppKit
import SwiftUI
import XCTest
@testable import GlassToKeyRuntime

final class LayoutMirrorTests: XCTestCase {
    private let pad = CGSize(width:160,height:114.9)

    func testPairsFollowGeometryAcrossDifferentBindingRows() throws {
        var doc = LayoutDocument()
        let left = doc.add(right:false,label:"A",rect:.init(x:0.1,y:0.2,width:0.1,height:0.2))
        let right = doc.add(right:true,label:"B",rect:.init(x:0.8,y:0.2,width:0.1,height:0.2))
        XCTAssertNotEqual(doc.keys[0].row,doc.keys[1].row)
        doc.inferMirrorPairs()
        XCTAssertEqual(doc.keys[0].mirrorID,right)
        XCTAssertEqual(doc.keys[1].mirrorID,left)
        XCTAssertEqual(doc.pairedSelection([left]),[left,right])
        XCTAssertTrue(doc.isValid)
    }
    func testReflectedGeometryDeltasPreserveAsymmetryLabelsAndBindingAddresses() throws {
        var doc = LayoutDocument()
        let left = doc.add(right:false,label:"A",rect:.init(x:0.1,y:0.2,width:0.1,height:0.2))
        _ = doc.add(right:true,label:"B",rect:.init(x:0.78,y:0.21,width:0.12,height:0.22))
        doc.inferMirrorPairs()
        let before = doc
        doc.keys[0].rect = .init(x:0.13,y:0.24,width:0.14,height:0.24,rotationDegrees:15)
        doc.keys[0].edges = [0.01,0.02,0.03,0.04]
        doc.mirrorGeometryChanges(from:before,sources:[left])
        let other = doc.keys[1]
        XCTAssertEqual(other.rect.x,0.71,accuracy:1e-12)
        XCTAssertEqual(other.rect.y,0.25,accuracy:1e-12)
        XCTAssertEqual(other.rect.width,0.16,accuracy:1e-12)
        XCTAssertEqual(other.rect.height,0.26,accuracy:1e-12)
        XCTAssertEqual(other.rect.rotationDegrees,-15,accuracy:1e-12)
        XCTAssertEqual(other.edges,[0.03,0.02,0.01,0.04])
        XCTAssertEqual(doc.keys.map(\.label),before.keys.map(\.label))
        XCTAssertEqual(doc.keys.map(\.row),before.keys.map(\.row))
        XCTAssertEqual(doc.keys.map(\.column),before.keys.map(\.column))
        XCTAssertTrue(doc.isValid)
    }
    func testPairedGroupRotationRemainsAHorizontalReflection() throws {
        var doc = LayoutDocument()
        let a = doc.addMirrored(right:false,rect:.init(x:0.2,y:0.2,width:0.1,height:0.2))
        let b = doc.addMirrored(right:false,rect:.init(x:0.2,y:0.5,width:0.1,height:0.2))
        let before = doc
        doc.rotate([a,b],degrees:15,pad:pad)
        doc.mirrorGeometryChanges(from:before,sources:[a,b])
        for key in doc.keys where !key.right {
            let other = try XCTUnwrap(doc.keys.first {$0.id == key.mirrorID})
            XCTAssertEqual(other.rect.centerX,1-key.rect.centerX,accuracy:1e-12)
            XCTAssertEqual(other.rect.centerY,key.rect.centerY,accuracy:1e-12)
            XCTAssertEqual(other.rect.rotationDegrees,-key.rect.rotationDegrees,accuracy:1e-12)
        }
    }
    func testPairsSurviveIndependentEditsAndSettingsRoundTrip() throws {
        var doc = LayoutDocument()
        _ = doc.addMirrored(right:true,label:"None")
        let partners = doc.keys.map(\.mirrorID)
        doc.keys[0].rect.x += 0.3 // Mirror Edit off.
        doc.inferMirrorPairs()
        XCTAssertEqual(doc.keys.map(\.mirrorID),partners)
        var profile = AppKeymapProfile.defaultProfile()
        profile.layoutDocuments = [TrackpadLayoutPreset.sixByThree.rawValue:doc]
        let exported = try PortableKeymapInterop.exportBundle(from:profile)
        let decoded = try PortableKeymapInterop.importProfile(from:exported,currentProfile:.defaultProfile())
        XCTAssertEqual(decoded.layoutDocuments,profile.layoutDocuments)
        XCTAssertEqual(LayoutDocumentStorage.decode(try JSONEncoder().encode(["test":doc]))["test"],doc)
    }
    func testMirroredDuplicationMakesNewPairsAndCopiesOwnSideSources() throws {
        var doc = LayoutDocument()
        let source = doc.addMirrored(right:true,rect:.init(x:0.2,y:0.2,width:0.1,height:0.2))
        let originals = Set(doc.keys.map(\.id))
        doc.keys[0].label = "A"; doc.keys[1].label = "B"
        let copies = doc.duplicate(doc.pairedSelection([source]),mirrorOffset:true,sourceRight:true)
        XCTAssertEqual(copies.count,2)
        XCTAssertTrue(copies.isDisjoint(with:originals))
        let right = try XCTUnwrap(doc.keys.first {copies.contains($0.id) && $0.right})
        let left = try XCTUnwrap(doc.keys.first {copies.contains($0.id) && !$0.right})
        XCTAssertEqual(right.mirrorID,left.id); XCTAssertEqual(left.mirrorID,right.id)
        XCTAssertEqual(right.label,"A"); XCTAssertEqual(left.label,"B")
        XCTAssertEqual(right.copySourceRow,0); XCTAssertEqual(left.copySourceRow,1)
        XCTAssertEqual(right.rect.x,0.22,accuracy:1e-12)
        XCTAssertEqual(left.rect.x,0.68,accuracy:1e-12)
        XCTAssertEqual(left.rect.y,right.rect.y,accuracy:1e-12)
        XCTAssertTrue(doc.isValid)
    }
    func testIndependentRemovalClearsPartnerAndPairedRemovalRemovesBoth() throws {
        var doc = LayoutDocument()
        let source = doc.addMirrored(right:true)
        let original = doc
        doc.remove([source])
        XCTAssertEqual(doc.keys.count,1); XCTAssertNil(doc.keys[0].mirrorID)
        XCTAssertTrue(doc.isValid)
        doc = original; doc.remove(doc.pairedSelection([source]))
        XCTAssertTrue(doc.keys.isEmpty); XCTAssertTrue(doc.isValid)
    }
    func testUnpairedSinglePadDoesNotGrowAnotherHalfOrChangeItsGeometry() {
        var doc = LayoutDocument()
        let source = doc.add(right:true,label:"A")
        doc.inferMirrorPairs()
        XCTAssertNil(doc.keys[0].mirrorID)
        let before = doc
        doc.translate([source],dx:0.1,dy:0.1)
        let moved = doc
        doc.mirrorGeometryChanges(from:before,sources:[source])
        XCTAssertEqual(doc,moved)
        XCTAssertEqual(doc.keys.count,1)
    }
    func testMarqueeSelectsKeysOrWholeColumnsWithoutCrossingPads() throws {
        var doc = LayoutDocument()
        let group = LayoutDocument.Group(name:"Column"); doc.groups.append(group)
        let upper = doc.add(right:false,rect:.init(x:0.1,y:0.1,width:0.1,height:0.2),group:group.id)
        let lower = doc.add(right:false,rect:.init(x:0.1,y:0.4,width:0.1,height:0.2),group:group.id)
        _ = doc.add(right:true,rect:.init(x:0.1,y:0.1,width:0.1,height:0.2),group:group.id)
        _ = doc.add(right:false,rect:.init(x:0.7,y:0.1,width:0.1,height:0.2))
        let box = CGRect(x:0.09,y:0.09,width:0.12,height:0.22)
        XCTAssertEqual(doc.editorMarquee(box,right:false,groups:false,pad:pad),[upper])
        XCTAssertEqual(doc.editorMarquee(box,right:false,groups:true,pad:pad),[upper,lower])
        XCTAssertEqual(doc.expandedGroups([upper]),[upper,lower])
        XCTAssertEqual(doc.editorHit(at:CGPoint(x:0.15,y:0.2),right:false,pad:pad),upper)
        XCTAssertNil(doc.editorHit(at:CGPoint(x:0.5,y:0.9),right:false,pad:pad))
    }
    func testEditorSelectionUsesRotatedDisplayShapeIncludingStenoOverlap() throws {
        var doc = LayoutDocument()
        let id = doc.add(right:true,rect:.init(x:0.4,y:0.4,width:0.2,height:0.2,rotationDegrees:30))
        doc.keys[0].edges = [0.03,0.02,0.03,0.02]
        let rect = doc.keys[0].displayRect
        XCTAssertEqual(rect.width,0.26,accuracy:1e-12)
        XCTAssertEqual(doc.editorHit(at:CGPoint(x:rect.centerX,y:rect.centerY),right:true,pad:pad),id)
        let corners = rect.corners(in:pad)
        let box = rect.boundingRect(in:pad)
        XCTAssertTrue(corners.allSatisfy { box.insetBy(dx:-0.00001,dy:-0.00001).contains($0) })
        let normalized = CGRect(x:box.minX/pad.width,y:box.minY/pad.height,width:box.width/pad.width,height:box.height/pad.height)
        XCTAssertEqual(doc.editorMarquee(normalized,right:true,groups:false,pad:pad),[id])
        XCTAssertNil(doc.editorHit(at:CGPoint(x:normalized.minX,y:normalized.minY),right:true,pad:pad))
    }
}
