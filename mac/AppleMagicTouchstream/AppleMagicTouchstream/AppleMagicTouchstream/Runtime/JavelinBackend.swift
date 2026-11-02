import Foundation
import JavelinBridge
import os

/// The native translator returns edits only. Live event posting belongs to
/// DispatchService; constructing this type or exercising it in tests is offline.
final class JavelinTranslator {
    struct Edit:Equatable,Sendable { var backspaces:Int; var text:String; var failed = false }
    private let engine:UnsafeMutableRawPointer
    private(set) var entryCount = 0
    private(set) var unsupportedCount = 0
    init(dictionaries:[[String:String]],numericFallback:Bool = false) {
        engine = AMTJavelinCreate()!
        for dictionary in dictionaries {
            for (outline,translation) in dictionary {
                guard Self.supported(translation) else {
                    // Reserve the outline as inert rather than falling through
                    // to a lower-priority word or printing the command's outline.
                    unsupportedCount += 1
                    _ = AMTJavelinAdd(engine,outline,"")
                    continue
                }
                if AMTJavelinAdd(engine,outline,translation) != 0 { entryCount += 1 }
            }
        }
        if numericFallback {
            // Standard Plover number-key mapping. Explicit dictionary entries win.
            let digits = Array("1234506789")
            for subset in 1..<(1 << digits.count) {
                let number = String(digits.indices.filter { subset & (1 << $0) != 0 }.map { digits[$0] })
                _ = AMTJavelinAdd(engine,number,"{&"+number+"}")
            }
        }
    }
    deinit { AMTJavelinDestroy(engine) }
    func reset() { AMTJavelinReset(engine) }
    func translate(_ mask:UInt64) -> Edit {
        guard AMTJavelinProcess(engine,Self.stroke(mask)) != 0 else { return Edit(backspaces:0,text:"",failed:true) }
        let scalars = (0..<AMTJavelinTextCount(engine)).compactMap { Unicode.Scalar(AMTJavelinTextAt(engine,$0)) }
        return Edit(backspaces:AMTJavelinDeleteCount(engine),text:String(String.UnicodeScalarView(scalars)))
    }
    // Both drawn S keys and all stars are aliases. Number keys remain an
    // explicit # chord: Lapwing does not use Plover's automatic number mapping.
    static func stroke(_ mask:UInt64) -> UInt32 {
        let keys:[StenoKey?] = [nil,.s2,.tl,.kl,.pl,.wl,.hl,.rl,.a,.o,.star1,.e,.u,.fr,.rr,.pr,.br,.lr,.gr,.tr,.sr,.dr,.zr]
        var result:UInt32 = 0
        for (bit,key) in keys.enumerated() { if let key,mask & key.bit != 0 { result |= 1 << bit } }
        if mask & StenoKey.s1.bit != 0 { result |= 1 << 1 }
        if mask & (StenoKey.star2.bit|StenoKey.star3.bit|StenoKey.star4.bit) != 0 { result |= 1 << 10 }
        let numbers:[StenoKey] = [.n1,.n2,.n3,.n4,.n5,.n6,.n7,.n8,.n9,.na,.nb,.nc]
        if numbers.contains(where:{ mask & $0.bit != 0 }) { result |= 1 }
        return result
    }
    static func supported(_ text:String) -> Bool {
        // No Plover plugins, firmware functions, raw shortcuts or macros run in
        // this prototype. Standard Plover text/affix/case/punctuation syntax does.
        !text.hasPrefix("=") && !text.contains("{#") && !text.contains("{PLOVER:") && !text.contains("{MODE:") &&
        text.range(of:#"\{:[^}]"#,options:.regularExpression) == nil && !text.utf8.contains(0) &&
        !["{*}","{*+}","{*?}","{*("].contains(where:text.contains)
    }
    static var resourceURL:URL? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        return bundle.url(forResource:"manifest",withExtension:"json",subdirectory:"Javelin")?.deletingLastPathComponent()
            ?? bundle.url(forResource:"manifest",withExtension:"json",subdirectory:"Resources/Javelin")?.deletingLastPathComponent()
    }
    static func bundled(profile:JavelinDictionaryProfile = .lapwing) throws -> JavelinTranslator {
        guard let folder = resourceURL else { throw CocoaError(.fileNoSuchFile) }
        let dictionaries = try profile.bundledNames.map { try StenoDictionaryDocument.load(folder.appendingPathComponent($0)).entries }
        return JavelinTranslator(dictionaries:dictionaries,numericFallback:profile == .plover)
    }
}

/// Called on the existing serial output queue, never the touch input queue.
/// Keep loaded dictionaries warm; reset history at every transport/lifecycle boundary.
final class JavelinBackend:@unchecked Sendable {
    static let shared = JavelinBackend()
    struct Snapshot:Sendable { var ready = false; var entries = 0; var unsupported = 0; var error:String? }
    private let status = OSAllocatedUnfairLock(initialState:Snapshot())
    private var translator:JavelinTranslator?
    private var profile:JavelinDictionaryProfile?
    private var revision:UInt64 = 0
    var snapshot:Snapshot { status.withLock { $0 } }
    func start(profile:JavelinDictionaryProfile = .lapwing,force:Bool = false) {
        let store = JavelinDictionaryStore.shared
        do {
            if force || translator == nil || self.profile != profile || revision != store.revision {
                status.withLock { $0.ready = false; $0.error = nil }
                translator = try JavelinTranslator(dictionaries:store.dictionaries(profile),numericFallback:profile == .plover)
                self.profile = profile; revision = store.revision
            }
            reset()
            status.withLock { $0 = Snapshot(ready:true,entries:translator!.entryCount,unsupported:translator!.unsupportedCount) }
        } catch { status.withLock { $0 = Snapshot(error:"Could not load \(profile.title) dictionaries: \(error.localizedDescription)") } }
    }
    func stop() { reset(); status.withLock { $0.ready = false } }
    func reset() { translator?.reset() }
    func translate(_ mask:UInt64) -> JavelinTranslator.Edit? {
        guard snapshot.ready, let edit = translator?.translate(mask) else { return nil }
        if edit.failed {
            status.withLock { $0.ready = false; $0.error = "Dictionary output exceeded the safe limit. Edit the entry, then reload dictionaries." }
            return nil
        }
        return edit
    }
}

// AX is confined to the main actor, independent of recognition/translation.
// A ticket pins one destination while the output pump waits for verification.
@MainActor final class JavelinFocusTicket {
    nonisolated let pid:pid_t
    private let destination:FocusedTextDestination
    private static var previous:FocusedTextDestination?
    private static var previousGeneration:UInt64?
    let needsReset:Bool
    init?(generation:UInt64) {
        guard let target = FocusedTextDestination.capture() else {
            Self.previous = nil; return nil
        }
        pid = target.pid; destination = target
        needsReset = Self.previousGeneration != generation || Self.previous.map { !$0.matches(target) } ?? true
        Self.previous = target; Self.previousGeneration = generation
    }
    func isCurrent() -> Bool {
        guard let current = FocusedTextDestination.capture() else { return false }
        return destination.matches(current)
    }
}
