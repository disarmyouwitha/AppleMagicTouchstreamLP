import AppKit
import Carbon
import os
import LocalAuthentication
import Security
import SwiftUI
import XCTest
@testable import GlassToKeyRuntime

private final class MemoryTextShortcutStore:TextShortcutStoring,@unchecked Sendable {
    private let lock = NSLock()
    private var values:[UUID:String] = [:]
    private var reads = 0
    var loadCount:Int { lock.lock(); defer { lock.unlock() }; return reads }
    func save(_ text:String) throws -> UUID {
        guard TextShortcutReference.valid(text) else { throw TextShortcutStorageError.invalidText }
        lock.lock(); defer { lock.unlock() }
        let id = UUID(); values[id] = text; return id
    }
    func load(_ id:UUID) throws -> String {
        lock.lock(); defer { lock.unlock() }
        reads += 1
        guard let text = values[id] else { throw TextShortcutStorageError.unavailable }
        return text
    }
}

@MainActor final class TextShortcutTests:XCTestCase {
    func testOpaqueReferencesRoundTripWithoutExposingText() throws {
        let store = MemoryTextShortcutStore(), secret = " Private multiline\ntext 😀  "
        let id = try store.save(secret)
        var action = TextShortcutReference.action(id:id); action.customName = "Greeting"
        XCTAssertEqual(try store.load(id),secret)
        XCTAssertEqual(KeyActionCatalog.action(for:action.storageLabel),action)
        XCTAssertEqual(action.pickerText,"Greeting")
        XCTAssertEqual(action.commandText,"Text (Keychain)")
        let mapping = KeyMapping(primary:action,hold:action)
        let position = GridKeyPosition(side:.left,row:0,column:0).storageKey
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(AppKeymapProfile.defaultProfile())) as? [String:Any])
        object["keyMappingsByLayout"] = try JSONSerialization.jsonObject(with:JSONEncoder().encode(["TouchStream":[0:[position:mapping]]]))
        object["shortcutActions"] = [action.storageLabel]
        var profile = try JSONDecoder().decode(AppKeymapProfile.self,from:JSONSerialization.data(withJSONObject:object))
        var settings = HandGestureSettings()
        let gesture = GestureAction.shortcut(.init(label:action.storageLabel))
        XCTAssertTrue(settings.setAction(gesture,for:.twoFingerTap,in:.left))
        profile.handGestureSettings = settings
        let exported = try PortableKeymapInterop.exportBundle(from:profile)
        XCTAssertFalse(String(decoding:exported,as:UTF8.self).contains(secret))
        let restored = try PortableKeymapInterop.importProfile(from:exported,currentProfile:.defaultProfile())
        XCTAssertEqual(restored.keyMappingsByLayout?["TouchStream"]?[0]?[position]?.primary,action)
        XCTAssertEqual(restored.keyMappingsByLayout?["TouchStream"]?[0]?[position]?.hold,action)
        XCTAssertEqual(restored.shortcutActions,[action.storageLabel])
        XCTAssertEqual(restored.handGestureSettings,settings)
        XCTAssertTrue(GestureActionChooser.shortcutActions(GestureTrigger.twoFingerTap.allowedActions,savedLabels:[action.storageLabel]).contains(gesture))
        XCTAssertFalse(GestureTrigger.twoFingerTap.allowedActions.acceptsGestureAction(.shortcut(.init(label:action.storageLabel,holdUntilRelease:true)),held:true))
        XCTAssertNil(KeyActionCatalog.action(for:"TEXT_SHORTCUT:not-a-uuid"))
        XCTAssertFalse(TextShortcutReference.valid(""))
        XCTAssertTrue(TextShortcutReference.valid(String(repeating:"a",count:65_536)))
        XCTAssertFalse(TextShortcutReference.valid(String(repeating:"😀",count:16_385)))
        // A settings export on another Mac has a valid action, but no secret to read.
        XCTAssertThrowsError(try MemoryTextShortcutStore().load(id))
    }

    func testUnnamedTextActionSurvivesGestureAndLibraryRoundTrip() throws {
        let store = MemoryTextShortcutStore()
        for name:String? in [nil,"","   "] {
            let action = try TextShortcutReference.savedAction(text:"private text",name:name,using:store)
            XCTAssertNil(action.customName)
            let gesture = GestureAction.shortcut(.init(label:action.storageLabel))
            var settings = HandGestureSettings()
            XCTAssertTrue(settings.setAction(gesture,for:.twoFingerTap,in:.left))
            let restored = try JSONDecoder().decode(HandGestureSettings.self,from:JSONEncoder().encode(settings))
            XCTAssertEqual(restored,settings)
            XCTAssertEqual(GestureAction(rawValue:gesture.rawValue),gesture)
            let library = try XCTUnwrap(ShortcutActionLibraryStorage.encode([action.storageLabel]))
            XCTAssertEqual(ShortcutActionLibraryStorage.decode(from:library),[action.storageLabel])
            XCTAssertTrue(GestureActionChooser.shortcutActions(GestureTrigger.twoFingerTap.allowedActions,savedLabels:[action.storageLabel]).contains(gesture))
        }
    }

    func testSimulatedTypingPreservesUnicodeAndBuildsBalancedModifierRestoringEdges() throws {
        let text = "Aé😀e\u{301}\tline\r\nnext"
        let strokes = TextShortcutTypingPlan.strokes(text)
        XCTAssertEqual(strokes.joined(),"Aé😀e\u{301}\tline\nnext")
        XCTAssertTrue(strokes.allSatisfy { $0.utf16.count <= 2 })
        for stroke in strokes {
            let pair = try XCTUnwrap(TextShortcutTypingPlan.events(stroke,restoringFlags:[.maskShift,.maskCommand]))
            XCTAssertEqual(pair.down.type,.keyDown); XCTAssertEqual(pair.up.type,.keyUp)
            XCTAssertEqual(pair.down.flags,[])
            XCTAssertEqual(pair.up.flags,[.maskShift,.maskCommand])
            if stroke == "\n" || stroke == "\t" {
                XCTAssertEqual(pair.down.getIntegerValueField(.keyboardEventKeycode),Int64(stroke == "\n" ? kVK_Return:kVK_Tab))
            } else {
                var count = 0, units = [UniChar](repeating:0,count:2)
                pair.down.keyboardGetUnicodeString(maxStringLength:2,actualStringLength:&count,unicodeString:&units)
                XCTAssertEqual(Array(units.prefix(count)),Array(stroke.utf16))
            }
        }
        XCTAssertNil(TextShortcutTypingPlan.events("",restoringFlags:[]))
    }

    func testShortcutPickerIncludesLibraryAndStenoInspectorFiltersOnlyPresentation() {
        var shortcut = KeyActionCatalog.action(for:"Cmd+C")!
        shortcut.customName = "Copy fixture"
        let text = TextShortcutReference.action(id:UUID())
        let groups = ShortcutActionBuilder.shortcutKeyPickerGroups(savedLabels:[shortcut.storageLabel,text.storageLabel])
        XCTAssertTrue(groups.first(where:{$0.title == "Shortcuts"})?.actions.contains(shortcut.storageLabel) == true)
        XCTAssertTrue(groups.first(where:{$0.title == "Shortcuts"})?.actions.contains(text.storageLabel) == true)
        for original in [KeyActionCatalog.primaryActionGroups,KeyActionCatalog.holdActionGroups] {
            XCTAssertFalse(KeyActionCatalog.inspectorActionGroups(original,isSteno:false).flatMap(\.actions).contains(where:{$0.kind == .steno}))
            let steno = KeyActionCatalog.inspectorActionGroups(original,isSteno:true).flatMap(\.actions)
            XCTAssertFalse(steno.isEmpty)
            XCTAssertTrue(steno.allSatisfy {$0.kind == .steno || $0.kind == .none})
            XCTAssertEqual(steno.filter {$0.kind == .steno}.count,StenoKey.allCases.count)
        }
    }

    func testShortcutKeyChooserRetainsEverySupportedKeyExactlyOnce() {
        let labels = ShortcutActionBuilder.shortcutKeyGroups.flatMap(\.actions)
        XCTAssertEqual(labels.filter { $0.isEmpty }.count,1)
        XCTAssertEqual(Set(labels.filter { !$0.isEmpty }),Set(KeyActionCatalog.shortcutKeyLabels))
        XCTAssertEqual(Set(labels).count,labels.count)
    }

    func testKeychainQueryProhibitsAuthenticationUIAndUsesAnAppSpecificService() {
        let id = UUID(), query = KeychainTextShortcutStore.query(id:UUID())
        XCTAssertEqual(query[kSecUseAuthenticationUI as String] as? String,kSecUseAuthenticationUIFail as String)
        XCTAssertEqual(query[kSecAttrService as String] as? String,"ink.ranna.applemagictouchstream.text-shortcuts")
        XCTAssertNil(query[kSecValueData as String])
        XCTAssertNil(query[kSecAttrSynchronizable as String])
        XCTAssertEqual(KeychainTextShortcutStore.query(id:id)[kSecAttrAccount as String] as? String,id.uuidString)
    }

    func testLifecycleCancellationInvalidatesPendingPastesWithoutReadingKeychain() {
        let output = TextShortcutTypingOutput()
        let generation = output.generation
        XCTAssertTrue(output.isCurrent(generation))
        output.cancel()
        XCTAssertFalse(output.isCurrent(generation))
        // Rejected before creating a task, querying AX, accessing Keychain, or touching clipboard.
        output.request(TextShortcutReference.action(id:UUID()).label,generation:generation)
    }

    func testPasteCompletionCanResumeTheQueueOnlyOnceAfterCancellation() {
        let results = OSAllocatedUnfairLock<[Bool]>(initialState:[])
        let request = TextShortcutTypingRequest { value in results.withLock { $0.append(value) } }
        XCTAssertTrue(request.isActive)
        request.finish(false)
        request.finish(true) // A late Keychain/native callback cannot resume the pump again.
        XCTAssertFalse(request.isActive)
        XCTAssertEqual(results.withLock { $0 },[false])
    }

    func testTextEditorKeepsAssignedTextHiddenWithoutReadingKeychain() throws {
        let store = MemoryTextShortcutStore(), text = "A private multiline\nmessage 😀"
        let id = try store.save(text)
        var action = TextShortcutReference.action(id:id); action.customName = "Greeting"
        var applied:[KeyAction] = []
        let root = ShortcutActionBuilder(action:action,apply:{ value,held in
            XCTAssertFalse(held); applied.append(value)
        },textStore:store)
        let host = NSHostingView(rootView:root.padding(16).background(Color(nsColor:.windowBackgroundColor)))
        host.frame = NSRect(x:0,y:0,width:550,height:340)
        let window = NSWindow(contentRect:host.frame,styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentView = host
        func editors(_ view:NSView) -> [NSTextView] { (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap(editors) }
        let deadline = Date().addingTimeInterval(0.2)
        repeat {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until:Date().addingTimeInterval(0.01))
        } while Date() < deadline
        XCTAssertTrue(applied.isEmpty)
        XCTAssertFalse(editors(host).contains(where:{$0.string == text}))
        XCTAssertEqual(store.loadCount,0)
        if let path = ProcessInfo.processInfo.environment["TEXT_SHORTCUT_PREVIEW_PATH"],
           let image = host.bitmapImageRepForCachingDisplay(in:host.bounds) {
            host.cacheDisplay(in:host.bounds,to:image)
            try image.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:path))
        }
        // The same operation invoked by Apply stores the content and returns only its reference.
        let saved = try TextShortcutReference.savedAction(text:text,name:"Greeting",using:store)
        XCTAssertEqual(saved.kind,.textPaste)
        XCTAssertEqual(saved.customName,"Greeting")
        let savedID = try XCTUnwrap(TextShortcutReference.id(from:saved.label))
        XCTAssertNotEqual(savedID,id) // Existing bindings keep their immutable reference.
        XCTAssertEqual(try store.load(savedID),text)
        XCTAssertFalse(saved.storageLabel.contains(text))
        window.contentView = nil
    }
}
