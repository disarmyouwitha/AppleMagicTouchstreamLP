import Foundation
import XCTest
@testable import GlassToKeyRuntime

final class JavelinDictionaryTests:XCTestCase {
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AMT-dictionaries-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        addTeardownBlock { try? FileManager.default.removeItem(at:url) }; return url
    }
    private func json(_ entries:[String:String],_ url:URL) throws { try JSONEncoder().encode(entries).write(to:url) }
    func testCanonicalOutlinesRejectInvalidAndConflictingAliases() throws {
        XCTAssertEqual(try StenoDictionaryDocument.canonicalOutline("123"),"#STP")
        XCTAssertEqual(try StenoDictionaryDocument.canonicalOutline("KAT/-S"),"KAT/-S")
        for value in ["", "KAT/", "/KAT", "KAT//-S", "CAT", "KATT", "kAt", "KAT\0",Array(repeating:"KAT",count:32).joined(separator:"/")] {
            XCTAssertThrowsError(try StenoDictionaryDocument.canonicalOutline(value),value)
        }
        XCTAssertThrowsError(try StenoDictionaryDocument.decode(JSONEncoder().encode(["1":"one","#S":"different"])))
        let merged = try StenoDictionaryDocument.decode(JSONEncoder().encode(["1":"one","#S":"one"]))
        XCTAssertEqual(merged.entries,["#S":"one"])
    }
    func testTranslationValidationAndPortableJSONRoundTrip() throws {
        for text in ["{broken", "broken}", "{{nested}}",String(repeating:"x",count:1025),"bad\0text"] {
            XCTAssertThrowsError(try StenoDictionaryDocument.validateTranslation(text))
        }
        var document = StenoDictionaryDocument(entries:[:])
        let key = try document.set(outline:"KAT",text:"cat 🐈\n\"quoted\"")
        XCTAssertEqual(key,"KAT")
        XCTAssertThrowsError(try document.set(outline:"KAT",text:"duplicate"))
        _ = try document.set(outline:"KATS",text:"cats",replacing:key)
        XCTAssertNil(document.entries["KAT"])
        XCTAssertEqual(try StenoDictionaryDocument.decode(document.data()).entries,document.entries)
    }
    func testEditBundledCopyProtectsBundleAndReplacesPriorityWithoutModifyingOriginal() throws {
        let root = try temporary(), bundle = root.appendingPathComponent("App.app/Resources/Javelin")
        try FileManager.default.createDirectory(at:bundle,withIntermediateDirectories:true)
        for name in JavelinDictionaryProfile.lapwing.bundledNames { try json(["KAT":"cat"],bundle.appendingPathComponent(name)) }
        let catalog = root.appendingPathComponent("settings")
        let store = JavelinDictionaryStore(folder:catalog,bundleFolder:bundle,protectedFolders:[root.appendingPathComponent("App.app")])
        let original = store.records(.lapwing)[0]
        let originalBytes = try Data(contentsOf:store.url(original))
        let copy = root.appendingPathComponent("custom.json")
        let document = StenoDictionaryDocument(entries:["KAT":"kitten"])
        XCTAssertThrowsError(try store.save(document,to:store.url(original),profile:.lapwing,replacing:original))
        XCTAssertThrowsError(try store.export(original,to:store.url(original)))
        let link = root.appendingPathComponent("alias.json")
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:store.url(original))
        XCTAssertThrowsError(try store.save(document,to:link,profile:.lapwing))
        try store.save(document,to:copy,profile:.lapwing,replacing:original)
        XCTAssertEqual(try Data(contentsOf:store.url(original)),originalBytes)
        XCTAssertFalse(try XCTUnwrap(store.records(.lapwing).first { $0.id == original.id }).enabled)
        XCTAssertEqual(store.records(.lapwing).first?.file,copy)
        let translator = JavelinTranslator(dictionaries:try store.dictionaries(.lapwing))
        XCTAssertEqual(translator.translate(StenoKey.kl.bit|StenoKey.a.bit|StenoKey.tr.bit).text,"kitten")
        let reopened = JavelinDictionaryStore(folder:catalog,bundleFolder:bundle,protectedFolders:[root.appendingPathComponent("App.app")])
        XCTAssertEqual(reopened.records(.lapwing),store.records(.lapwing))
        XCTAssertTrue(reopened.records(.plover).allSatisfy(\.isBundled))
    }
    func testLoadBatchIsAtomicAndExportRemovePriorityAndDisableRoundTrip() throws {
        let root = try temporary(), store = JavelinDictionaryStore(folder:root.appendingPathComponent("config"),bundleFolder:nil,protectedFolders:[])
        let first = root.appendingPathComponent("first.json"), second = root.appendingPathComponent("second.json"), bad = root.appendingPathComponent("bad.json")
        try json(["KAT":"first"],first); try json(["KAT":"second"],second); try Data("bad".utf8).write(to:bad)
        XCTAssertThrowsError(try store.load([first,bad],profile:.plover))
        XCTAssertTrue(store.records(.plover).allSatisfy(\.isBundled))
        try store.load([first,second],profile:.plover)
        let a = store.records(.plover)[0], b = store.records(.plover)[1]
        XCTAssertEqual(a.file,first); XCTAssertEqual(b.file,second)
        try store.move(b.id,by:-1,profile:.plover)
        XCTAssertEqual(store.records(.plover)[0].id,b.id)
        try store.setEnabled(b.id,false,profile:.plover)
        XCTAssertFalse(store.records(.plover)[0].enabled)
        let exported = root.appendingPathComponent("exported.json")
        try store.export(a,to:exported)
        XCTAssertEqual(try Data(contentsOf:first),try Data(contentsOf:exported))
        try store.remove(a.id,profile:.plover)
        XCTAssertTrue(FileManager.default.fileExists(atPath:first.path))
        XCTAssertFalse(store.records(.plover).contains { $0.id == a.id })
    }
    func testRemovingCustomDictionariesPreservesBundledCheckboxStatesAndPersists() throws {
        let root = try temporary(), folder = root.appendingPathComponent("config")
        let store = JavelinDictionaryStore(folder:folder,bundleFolder:nil,protectedFolders:[])
        for profile in JavelinDictionaryProfile.allCases {
            for row in store.records(profile) { try store.setEnabled(row.id,false,profile:profile) }
        }
        let first = root.appendingPathComponent("first.json"), second = root.appendingPathComponent("second.json")
        try json(["KAT":"first"],first); try json(["KAT":"second"],second)
        try store.load([first,second],profile:.lapwing)
        let customs = store.records(.lapwing).filter { !$0.isBundled }
        // Removing custom dictionaries must not change the remaining enabled states.
        try store.setEnabled(customs[1].id,false,profile:.lapwing)
        try store.remove(customs[0].id,profile:.lapwing)
        XCTAssertTrue(store.records(.lapwing).filter(\.isBundled).allSatisfy { !$0.enabled })
        try store.remove("missing",profile:.lapwing)
        try store.remove(store.records(.lapwing).first(where: \.isBundled)!.id,profile:.lapwing)
        XCTAssertTrue(store.records(.lapwing).filter(\.isBundled).allSatisfy { !$0.enabled })
        try store.remove(customs[1].id,profile:.lapwing)
        XCTAssertTrue(store.records(.lapwing).allSatisfy { $0.isBundled && !$0.enabled })
        XCTAssertTrue(store.records(.plover).allSatisfy { !$0.enabled })
        XCTAssertTrue(FileManager.default.fileExists(atPath:first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath:second.path))
        let reopened = JavelinDictionaryStore(folder:folder,bundleFolder:nil,protectedFolders:[])
        XCTAssertEqual(reopened.records(.lapwing),store.records(.lapwing))
    }
    func testFailedCatalogSaveRestoresExistingDictionaryAndRemovesUncommittedCopy() throws {
        let root = try temporary(), blocked = root.appendingPathComponent("blocked")
        try Data("not a directory".utf8).write(to:blocked)
        let store = JavelinDictionaryStore(folder:blocked,bundleFolder:nil,protectedFolders:[])
        let destination = root.appendingPathComponent("existing.json")
        try json(["KAT":"original"],destination)
        let original = try Data(contentsOf:destination)
        let changed = StenoDictionaryDocument(entries:["KAT":"changed"])
        XCTAssertThrowsError(try store.save(changed,to:destination,profile:.plover))
        XCTAssertEqual(try Data(contentsOf:destination),original)
        let new = root.appendingPathComponent("new.json")
        XCTAssertThrowsError(try store.save(changed,to:new,profile:.plover))
        XCTAssertFalse(FileManager.default.fileExists(atPath:new.path))
        XCTAssertTrue(store.records(.plover).allSatisfy(\.isBundled))
    }
    func testBundledPloverWordsNumbersAndExistingModeIdentities() throws {
        let translator = try JavelinTranslator.bundled(profile:.plover)
        XCTAssertGreaterThan(translator.entryCount,140_000)
        XCTAssertEqual(translator.translate(StenoKey.kl.bit|StenoKey.a.bit|StenoKey.tr.bit).text,"cat")
        translator.reset()
        XCTAssertEqual(translator.translate(StenoKey.n1.bit|StenoKey.s1.bit|StenoKey.tl.bit|StenoKey.pl.bit).text,"123")
        XCTAssertEqual(translator.translate(StenoKey.star1.bit).backspaces,3)
        XCTAssertEqual(StenoConnectionMode.javelin.dictionaryProfile,.lapwing)
        XCTAssertEqual(StenoConnectionMode.javelinPlover.dictionaryProfile,.plover)
        XCTAssertTrue(StenoConnectionMode.javelinPlover.isBuiltIn)
        XCTAssertFalse(StenoConnectionMode.plugin.isBuiltIn)
        XCTAssertFalse(StenoConnectionMode.serial.isBuiltIn)
    }
    func testOversizedTranslationFailsWithoutEditsAndResetsNativeHistory() {
        let translator = JavelinTranslator(dictionaries:[["KAT":String(repeating:"x",count:3000),"H-L":"hello"]])
        let edit = translator.translate(StenoKey.kl.bit|StenoKey.a.bit|StenoKey.tr.bit)
        XCTAssertTrue(edit.failed); XCTAssertEqual(edit.text,""); XCTAssertEqual(edit.backspaces,0)
        XCTAssertEqual(translator.translate(StenoKey.hl.bit|StenoKey.lr.bit).text,"hello")
    }
}
