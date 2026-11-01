import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor private final class DictionaryManagerModel:ObservableObject {
    typealias Record = JavelinDictionaryStore.Record
    struct Session:Identifiable {
        let id = UUID()
        let source:Record?
        let destination:URL
        let document:StenoDictionaryDocument
    }
    let profile:JavelinDictionaryProfile
    let store:JavelinDictionaryStore
    @Published var records:[Record] = []
    @Published var selection:String?
    @Published var session:Session?
    @Published var busy = false
    @Published var error:String?
    init(profile:JavelinDictionaryProfile,store:JavelinDictionaryStore = .shared) {
        self.profile = profile; self.store = store; refresh()
    }
    var selected:Record? { records.first { $0.id == selection } }
    func refresh() { records = store.records(profile); error = store.catalogError }
    func changed() { refresh(); DispatchService.shared.reloadJavelinDictionaries(profile:profile) }
    func perform(reload:Bool = true,_ operation:@escaping @Sendable () throws -> Void) {
        guard !busy else { return }; busy = true; error = nil
        Task {
            do { try await Task.detached(priority:.userInitiated) { try operation() }.value; if reload { changed() } else { refresh() } }
            catch { self.error = error.localizedDescription }
            busy = false
        }
    }
    func load() {
        let panel = NSOpenPanel(); panel.title = "Load Steno Dictionary"; panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls, store = store, profile = profile
        perform { try store.load(urls,profile:profile) }
    }
    func saveDestination(name:String,title:String) -> URL? {
        let panel = NSSavePanel(); panel.title = title; panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = name; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do { try store.validateDestination(url); return url }
        catch { self.error = error.localizedDescription; return nil }
    }
    func new() {
        guard let url = saveDestination(name:"user.json",title:"Save New Dictionary") else { return }
        session = Session(source:nil,destination:url,document:.init(entries:[:]))
    }
    func edit() {
        guard let selected else { return }
        let destination:URL
        do {
            if selected.isBundled {
                guard let url = saveDestination(name:selected.title.replacingOccurrences(of:".json",with:"-custom.json"),title:"Save an Editable Copy") else { return }
                destination = url
            } else { destination = try store.url(selected) }
            busy = true; error = nil
            let source = try store.url(selected)
            Task {
                do {
                    let document = try await Task.detached(priority:.userInitiated) { try StenoDictionaryDocument.load(source) }.value
                    session = Session(source:selected,destination:destination,document:document)
                } catch { self.error = error.localizedDescription }
                busy = false
            }
        } catch { self.error = error.localizedDescription; busy = false }
    }
    func export() {
        guard let selected, let destination = saveDestination(name:selected.title,title:"Export Dictionary") else { return }
        let store = store
        perform(reload:false) { try store.export(selected,to:destination) }
    }
}

struct JavelinDictionaryManager:View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model:DictionaryManagerModel
    init(profile:JavelinDictionaryProfile) { _model = StateObject(wrappedValue:DictionaryManagerModel(profile:profile)) }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text("\(model.profile.title) Dictionaries").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.disabled(model.busy).keyboardShortcut(.cancelAction)
            }
            Text("Higher dictionaries take priority. Bundled dictionaries are read-only; Edit saves a separate copy.")
                .font(.callout).foregroundStyle(.secondary)
            List(selection:$model.selection) {
                ForEach(model.records) { row in
                    HStack {
                        Toggle("Enable \(row.title)",isOn:Binding(get:{row.enabled},set:{ enabled in
                            let store = model.store, profile = model.profile
                            model.perform { try store.setEnabled(row.id,enabled,profile:profile) }
                        })).labelsHidden().toggleStyle(.checkbox)
                        VStack(alignment:.leading) {
                            Text(row.title).lineLimit(1)
                            Text(row.isBundled ? "Bundled":"User dictionary").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if row.isBundled { Image(systemName:"lock").foregroundStyle(.secondary) }
                    }.tag(row.id).help((try? model.store.url(row).path) ?? row.title)
                }
            }.frame(minHeight:210)
            HStack {
                Button("Load…") { model.load() }
                Button("New…") { model.new() }
                Button("Edit…") { model.edit() }.disabled(model.selected == nil)
                Button("Export…") { model.export() }.disabled(model.selected == nil)
                Spacer()
                Button { move(-1) } label:{ Image(systemName:"arrow.up") }.help("Higher priority").disabled(!canMove(-1))
                Button { move(1) } label:{ Image(systemName:"arrow.down") }.help("Lower priority").disabled(!canMove(1))
                Button {
                    guard let selected = model.selected else { return }
                    let store = model.store, profile = model.profile
                    model.perform { try store.remove(selected.id,profile:profile) }
                } label:{ Image(systemName:"minus") }.help("Remove from list; keep the JSON file")
                    .disabled(model.selected?.isBundled != false)
                Button("Reload") { model.changed() }
            }.disabled(model.busy)
            if model.busy { ProgressView().controlSize(.small) }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        }.padding(20).frame(width:720,height:420)
            .sheet(item:$model.session) { session in
                JavelinDictionaryEntryEditor(session:session,store:model.store,profile:model.profile) {
                    model.session = nil; model.changed()
                }
            }
    }
    private func canMove(_ offset:Int) -> Bool {
        guard let id = model.selection, let index = model.records.firstIndex(where:{$0.id == id}) else { return false }
        return model.records.indices.contains(index+offset)
    }
    private func move(_ offset:Int) {
        guard let id = model.selection else { return }
        let store = model.store, profile = model.profile
        model.perform { try store.move(id,by:offset,profile:profile) }
    }
}

private struct DictionarySearchResult:Sendable { var keys:[String]; var total:Int }

private struct JavelinDictionaryEntryEditor:View {
    @Environment(\.dismiss) private var dismiss
    let session:DictionaryManagerModel.Session
    let store:JavelinDictionaryStore
    let profile:JavelinDictionaryProfile
    let saved:@MainActor () -> Void
    @State private var document:StenoDictionaryDocument
    @State private var search = ""
    @State private var matches = DictionarySearchResult(keys:[],total:0)
    @State private var selected:String?
    @State private var outline = ""
    @State private var translation = ""
    @State private var dirty = false
    @State private var revision = 0
    @State private var saving = false
    @State private var error:String?
    init(session:DictionaryManagerModel.Session,store:JavelinDictionaryStore,profile:JavelinDictionaryProfile,saved:@escaping @MainActor () -> Void) {
        self.session = session; self.store = store; self.profile = profile; self.saved = saved
        _document = State(initialValue:session.document)
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                VStack(alignment:.leading) {
                    Text(session.destination.lastPathComponent).font(.title2.bold())
                    Text(session.destination.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Cancel") { cancel() }.disabled(saving).keyboardShortcut(.cancelAction)
                Button("Save Dictionary") { save() }.disabled(saving).keyboardShortcut("s",modifiers:.command)
            }
            TextField("Search outlines or translations",text:$search).textFieldStyle(.roundedBorder)
            List(selection:Binding(get:{selected},set:{ select($0) })) {
                ForEach(matches.keys,id:\.self) { key in
                    HStack {
                        Text(key).font(.system(.body,design:.monospaced)).frame(width:160,alignment:.leading)
                        Text(document.entries[key] ?? "").lineLimit(1)
                        Spacer()
                        if !JavelinTranslator.supported(document.entries[key] ?? "") {
                            Image(systemName:"exclamationmark.circle").foregroundStyle(.secondary)
                                .help("This command is not supported by the built-in translator and will stay inert.")
                        }
                    }.tag(key)
                }
            }.frame(minHeight:230)
            Text("\(document.entries.count) entries · \(matches.total) matches\(matches.total > matches.keys.count ? " · Showing first 300; narrow your search":"")")
                .font(.caption).foregroundStyle(.secondary)
            HStack(alignment:.top) {
                VStack(alignment:.leading) {
                    Text("Outline").font(.caption)
                    TextField("KAT or KAT/-S",text:$outline).textFieldStyle(.roundedBorder)
                }.frame(width:200)
                VStack(alignment:.leading) {
                    Text("Translation").font(.caption)
                    TextEditor(text:$translation).font(.system(.body,design:.monospaced)).frame(height:70)
                        .overlay(RoundedRectangle(cornerRadius:4).stroke(Color.secondary.opacity(0.25)))
                }
                VStack {
                    Button(selected == nil ? "Add Entry":"Update Entry") { commitEntry() }.disabled(outline.isEmpty)
                    Button("New Entry") { select(nil) }
                    Button("Delete Entry") {
                        guard let selected else { return }
                        document.entries.removeValue(forKey:selected); self.selected = nil
                        outline = ""; translation = ""; dirty = true; revision += 1
                    }.disabled(selected == nil)
                }.padding(.top,18)
            }.disabled(saving)
            if saving { ProgressView().controlSize(.small) }
            if let error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        }.padding(20).frame(width:860,height:600).interactiveDismissDisabled()
            .task(id:search+"#\(revision)") {
                try? await Task.sleep(for:.milliseconds(180))
                guard !Task.isCancelled else { return }
                let entries = document.entries, query = search.trimmingCharacters(in:.whitespacesAndNewlines)
                let result = await Task.detached(priority:.userInitiated) {
                    let keys = entries.keys.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) || entries[$0]!.localizedCaseInsensitiveContains(query) }.sorted()
                    return DictionarySearchResult(keys:Array(keys.prefix(300)),total:keys.count)
                }.value
                guard !Task.isCancelled else { return }; matches = result
            }
            .onChange(of:selected) { key in
                outline = key ?? ""; translation = key.flatMap { document.entries[$0] } ?? ""; error = nil
            }
    }
    private func select(_ key:String?) {
        if pending && !commitEntry() { return }
        selected = key; outline = key ?? ""; translation = key.flatMap { document.entries[$0] } ?? ""
    }
    private var pending:Bool { selected.map { outline != $0 || translation != document.entries[$0] } ?? (!outline.isEmpty || !translation.isEmpty) }
    @discardableResult private func commitEntry() -> Bool {
        do {
            selected = try document.set(outline:outline,text:translation,replacing:selected)
            dirty = true; revision += 1; error = nil; return true
        } catch { self.error = error.localizedDescription; return false }
    }
    private func save() {
        if pending && !commitEntry() { return }
        saving = true; error = nil
        let document = document, destination = session.destination, source = session.source
        Task {
            do {
                try await Task.detached(priority:.userInitiated) { try store.save(document,to:destination,profile:profile,replacing:source) }.value
                saved(); dismiss()
            } catch { self.error = error.localizedDescription; saving = false }
        }
    }
    private func cancel() {
        if dirty || pending {
            let alert = NSAlert(); alert.messageText = "Discard dictionary edits?"; alert.informativeText = "Your JSON file has not been changed."
            alert.addButton(withTitle:"Keep Editing"); alert.addButton(withTitle:"Discard")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        dismiss()
    }
}
