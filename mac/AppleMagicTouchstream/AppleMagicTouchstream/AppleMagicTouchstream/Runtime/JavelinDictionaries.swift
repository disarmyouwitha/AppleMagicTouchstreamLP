import Foundation
import JavelinBridge
import os

enum JavelinDictionaryProfile:String,CaseIterable,Codable,Sendable,Identifiable {
    case lapwing, plover
    var id:String { rawValue }
    var title:String { self == .lapwing ? "Lapwing":"Plover" }
    var bundledNames:[String] { self == .lapwing ? ["lapwing-commands.json","lapwing-numbers.json","lapwing-uk-additions.json","lapwing-proper-nouns.json","lapwing-base.json"]:["plover-commands.json","plover-main.json"] }
}

enum StenoDictionaryError:Error,LocalizedError {
    case invalid(String)
    var errorDescription:String? { switch self { case .invalid(let message):message } }
}

struct StenoDictionaryDocument:Sendable {
    static let maximumBytes = 32*1024*1024
    var entries:[String:String]
    static func canonicalOutline(_ outline:String) throws -> String {
        guard !outline.utf8.contains(0) else { throw StenoDictionaryError.invalid("An outline contains a null character.") }
        var output = [CChar](repeating:0,count:4096)
        guard AMTJavelinCanonicalOutline(outline,&output,output.count) != 0 else {
            throw StenoDictionaryError.invalid("Invalid steno outline: \(outline.prefix(80)). Use standard steno order and / between strokes.")
        }
        return String(cString:output)
    }
    static func validateTranslation(_ text:String) throws {
        guard text.unicodeScalars.count <= 1024, !text.utf8.contains(0) else {
            throw StenoDictionaryError.invalid("Translations must be at most 1,024 characters and cannot contain null characters.")
        }
        var open = false, escaped = false
        for character in text {
            if escaped { escaped = false; continue }
            if character == "\\" { escaped = true; continue }
            if character == "{" { guard !open else { throw StenoDictionaryError.invalid("Nested translation braces are not supported.") }; open = true }
            if character == "}" { guard open else { throw StenoDictionaryError.invalid("Translation has an unmatched closing brace.") }; open = false }
        }
        guard !open else { throw StenoDictionaryError.invalid("Translation has an unclosed brace.") }
    }
    static func decode(_ data:Data) throws -> Self {
        guard data.count <= maximumBytes else { throw StenoDictionaryError.invalid("Dictionary exceeds 32 MB.") }
        let raw = try JSONDecoder().decode([String:String].self,from:data)
        guard raw.count <= 300_000 else { throw StenoDictionaryError.invalid("Dictionary exceeds 300,000 entries.") }
        var entries:[String:String] = [:]; entries.reserveCapacity(raw.count)
        for (outline,text) in raw {
            let key = try canonicalOutline(outline)
            try validateTranslation(text)
            if let previous = entries[key], previous != text {
                throw StenoDictionaryError.invalid("Conflicting entries use the same steno outline: \(key).")
            }
            entries[key] = text
        }
        return Self(entries:entries)
    }
    static func readData(_ url:URL) throws -> Data {
        guard url.isFileURL else { throw StenoDictionaryError.invalid("Choose a local JSON dictionary.") }
        let source = url.resolvingSymlinksInPath()
        let values = try source.resourceValues(forKeys:[.fileSizeKey,.isRegularFileKey])
        guard values.isRegularFile == true else { throw StenoDictionaryError.invalid("Choose a regular JSON file.") }
        if let size = values.fileSize, size > maximumBytes { throw StenoDictionaryError.invalid("Dictionary exceeds 32 MB.") }
        let data = try Data(contentsOf:source,options:.mappedIfSafe)
        guard data.count <= maximumBytes else { throw StenoDictionaryError.invalid("Dictionary exceeds 32 MB.") }
        return data
    }
    static func load(_ url:URL) throws -> Self { try decode(readData(url)) }
    func data() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]
        return try encoder.encode(entries)
    }
    mutating func set(outline:String,text:String,replacing old:String? = nil) throws -> String {
        let key = try Self.canonicalOutline(outline)
        try Self.validateTranslation(text)
        if key != old, entries[key] != nil { throw StenoDictionaryError.invalid("That outline already exists. Select it to edit its translation.") }
        if let old, old != key { entries.removeValue(forKey:old) }
        entries[key] = text; return key
    }
}

/// Local dictionary catalog. Only metadata is stored here; JSON files remain
/// portable and are never embedded in settings/captures. Higher rows win.
final class JavelinDictionaryStore:@unchecked Sendable {
    static let shared = JavelinDictionaryStore()
    struct Record:Codable,Identifiable,Equatable,Sendable {
        var id:String
        var bundledName:String?
        var file:URL?
        var enabled = true
        var isBundled:Bool { bundledName != nil }
        var title:String { bundledName ?? file?.lastPathComponent ?? "Dictionary" }
    }
    private struct Catalog:Codable { var profiles:[String:[Record]] = [:] }
    private struct State { var catalog = Catalog(); var revision:UInt64 = 0; var error:String? }
    private let state = OSAllocatedUnfairLock(initialState:State())
    let folder:URL
    let bundleFolder:URL?
    private let protectedFolders:[URL]
    init(folder:URL? = nil,bundleFolder:URL? = JavelinTranslator.resourceURL,protectedFolders:[URL]? = nil) {
        self.folder = folder ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("AppleMagicTouchstream/StenoDictionaries",isDirectory:true)
        self.bundleFolder = bundleFolder
        self.protectedFolders = protectedFolders ?? [Bundle.main.bundleURL,bundleFolder].compactMap { $0 }
        let path = self.folder.appendingPathComponent("catalog.json")
        if FileManager.default.fileExists(atPath:path.path) {
            do { let catalog = try JSONDecoder().decode(Catalog.self,from:Data(contentsOf:path)); state.withLock { $0.catalog = catalog } }
            catch { state.withLock { $0.error = "Could not read dictionary catalog: \(error.localizedDescription)" } }
        }
    }
    var revision:UInt64 { state.withLock { $0.revision } }
    var catalogError:String? { state.withLock { $0.error } }
    private func records(_ profile:JavelinDictionaryProfile,catalog:Catalog) -> [Record] {
        var rows = catalog.profiles[profile.rawValue] ?? []
        for name in profile.bundledNames where !rows.contains(where:{$0.bundledName == name}) {
            rows.append(Record(id:"bundled:"+name,bundledName:name))
        }
        return rows
    }
    func records(_ profile:JavelinDictionaryProfile) -> [Record] { state.withLock { records(profile,catalog:$0.catalog) } }
    func url(_ record:Record) throws -> URL {
        if let name = record.bundledName, let bundleFolder { return bundleFolder.appendingPathComponent(name) }
        if let file = record.file, file.isFileURL { return file }
        throw StenoDictionaryError.invalid("Dictionary file is unavailable: \(record.title)")
    }
    func validateDestination(_ url:URL) throws {
        guard url.isFileURL, url.pathExtension.lowercased() == "json" else { throw StenoDictionaryError.invalid("Save the dictionary as a local .json file.") }
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        for root in protectedFolders {
            let protected = root.standardizedFileURL.resolvingSymlinksInPath().path
            if path == protected || path.hasPrefix(protected+"/") {
                throw StenoDictionaryError.invalid("Bundled dictionaries are read-only. Choose a location outside the application.")
            }
        }
        if path == folder.appendingPathComponent("catalog.json").standardizedFileURL.resolvingSymlinksInPath().path {
            throw StenoDictionaryError.invalid("Choose a different filename; catalog.json stores your dictionary list.")
        }
    }
    private func update(_ profile:JavelinDictionaryProfile,_ edit:@Sendable (inout [Record]) throws -> Void) throws {
        try state.withLock { value in
            var rows = records(profile,catalog:value.catalog); try edit(&rows)
            var next = value.catalog; next.profiles[profile.rawValue] = rows
            let data = try JSONEncoder().encode(next)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            try data.write(to:folder.appendingPathComponent("catalog.json"),options:.atomic)
            value.catalog = next; value.revision &+= 1; value.error = nil
        }
    }
    func load(_ url:URL,profile:JavelinDictionaryProfile) throws { try load([url],profile:profile) }
    func load(_ urls:[URL],profile:JavelinDictionaryProfile) throws {
        for url in urls { _ = try StenoDictionaryDocument.load(url); try validateDestination(url) }
        let files = urls.map { $0.standardizedFileURL.resolvingSymlinksInPath() }
        try update(profile) { rows in
            for url in files.reversed() {
                if let i = rows.firstIndex(where:{$0.file == url}) { rows[i].enabled = true }
                else { rows.insert(Record(id:UUID().uuidString,file:url),at:0) }
            }
        }
    }
    func save(_ document:StenoDictionaryDocument,to url:URL,profile:JavelinDictionaryProfile,replacing source:Record? = nil) throws {
        try validateDestination(url)
        // Validate edited content too; callers cannot bypass file/outline bounds.
        let data = try document.data(); _ = try StenoDictionaryDocument.decode(data)
        let destination = url.standardizedFileURL.resolvingSymlinksInPath()
        let previous = FileManager.default.fileExists(atPath:destination.path) ? try StenoDictionaryDocument.readData(destination):nil
        try data.write(to:destination,options:.atomic)
        do { try update(profile) { rows in
            let existing = rows.firstIndex(where:{$0.file == destination}).map { rows.remove(at:$0) }
            let index = source.flatMap { s in rows.firstIndex(where:{$0.id == s.id}) } ?? 0
            if source?.isBundled == true, index < rows.count { rows[index].enabled = false }
            var record = existing ?? Record(id:UUID().uuidString,file:destination)
            record.enabled = true
            rows.insert(record,at:index)
        } } catch {
            do {
                if let previous { try previous.write(to:destination,options:.atomic) }
                else { try FileManager.default.removeItem(at:destination) }
            } catch {
                throw StenoDictionaryError.invalid("The JSON was written, but the dictionary list could not be saved or rolled back. Check \(destination.path).")
            }
            throw error
        }
    }
    func export(_ record:Record,to destination:URL) throws {
        try validateDestination(destination)
        let source = try url(record)
        // Export preserves the dictionary's raw JSON, with no engine-specific conversion.
        let data = try StenoDictionaryDocument.readData(source); _ = try StenoDictionaryDocument.decode(data)
        try data.write(to:destination,options:.atomic)
    }
    func setEnabled(_ id:String,_ enabled:Bool,profile:JavelinDictionaryProfile) throws {
        try update(profile) { rows in if let i = rows.firstIndex(where:{$0.id == id}) { rows[i].enabled = enabled } }
    }
    func remove(_ id:String,profile:JavelinDictionaryProfile) throws {
        try update(profile) { rows in rows.removeAll { $0.id == id && !$0.isBundled } } // Never deletes the JSON file.
    }
    func move(_ id:String,by offset:Int,profile:JavelinDictionaryProfile) throws {
        try update(profile) { rows in
            guard let i = rows.firstIndex(where:{$0.id == id}), rows.indices.contains(i+offset) else { return }
            rows.swapAt(i,i+offset)
        }
    }
    func dictionaries(_ profile:JavelinDictionaryProfile) throws -> [[String:String]] {
        if let error = catalogError { throw StenoDictionaryError.invalid(error) }
        return try records(profile).filter(\.enabled).map { try StenoDictionaryDocument.load(url($0)).entries }
    }
}
