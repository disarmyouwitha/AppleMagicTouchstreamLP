import SwiftUI
import AppKit

/// A staged document editor. Nothing reaches recognition until Apply.
struct LayoutEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var document: LayoutDocument
    let template: LayoutDocument
    let onApply: (LayoutDocument?) -> Void
    @State private var selection = Set<UUID>()
    @State private var groupSelection = false
    @State private var snap = true
    @State private var right = true
    @State private var history = LayoutDocumentHistory()
    @State private var dragStart: LayoutDocument?
    @State private var resizeStart: LayoutDocument?
    @State private var columnCount = 3
    private let width = ContentView.trackpadWidthMM
    private let height = ContentView.trackpadHeightMM

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Layout Editor").font(.title2.bold())
                Spacer()
                Button("Undo", action: undo).disabled(!history.canUndo).keyboardShortcut("z", modifiers: .command)
                Button("Redo", action: redo).disabled(!history.canRedo).keyboardShortcut("z", modifiers: [.command, .shift])
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply") { onApply(document); dismiss() }.keyboardShortcut(.defaultAction).disabled(!document.isValid)
            }
            HStack {
                Picker("Select", selection: $groupSelection) {
                    Text("Keys").tag(false); Text("Groups / Columns").tag(true)
                }.pickerStyle(.segmented).frame(width: 260)
                Toggle("Snap to 1 mm", isOn: $snap)
                Spacer()
                Button("Reset Template") { change { document = template; selection = [] } }
            }
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 14) {
                    Picker("Trackpad", selection: $right) { Text("Left").tag(false); Text("Right").tag(true) }
                        .pickerStyle(.segmented).frame(width: 220)
                    pad(isRight: right)
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity)
                ScrollView { inspector.frame(width: 265) }.frame(width: 280)
            }
            Text("Drag keys or groups. Shift-click adds to selection. Geometry is in millimeters; snapping here is independent of typing Snap Radius. Apply publishes once.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(width: 1020, height: 780)
            .onChange(of: groupSelection) { _ in selection = [] }
    }

    private func pad(isRight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isRight ? "Right trackpad" : "Left trackpad").font(.headline)
            GeometryReader { proxy in
                let size = proxy.size
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary))
                        .onTapGesture { selection = []; right = isRight }
                    ForEach(document.keys.filter { $0.right == isRight }) { key in
                        let r = visualRect(key)
                        RoundedRectangle(cornerRadius: 5)
                            .fill(selection.contains(key.id) ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(selection.contains(key.id) ? Color.accentColor : Color.secondary, lineWidth: selection.contains(key.id) ? 2 : 1))
                            .overlay(Text(legend(key)).font(.system(size: 11)).lineLimit(1).minimumScaleFactor(0.5))
                            .frame(width: r.width*size.width, height: r.height*size.height)
                            .rotationEffect(.degrees(r.rotationDegrees))
                            .position(x: r.centerX*size.width, y: r.centerY*size.height)
                            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(isRight ? "right" : "left"))
                                .onChanged { value in
                                    if dragStart == nil {
                                        right = isRight
                                        if !selection.contains(key.id) {
                                            let ids = groupSelection && key.group != nil
                                                ? Set(document.keys.filter { $0.group == key.group }.map(\.id)) : [key.id]
                                            if NSEvent.modifierFlags.contains(.shift) { selection.formUnion(ids) }
                                            else { selection = ids }
                                        }
                                        dragStart = document
                                    }
                                    guard let start = dragStart else { return }
                                    var dx = value.translation.width/size.width
                                    var dy = value.translation.height/size.height
                                    if snap { dx = (dx*width).rounded()/width; dy = (dy*height).rounded()/height }
                                    document = start; document.translate(selection, dx: dx, dy: dy)
                                }
                                .onEnded { _ in
                                    if let start = dragStart, start != document { history.record(start) }
                                    dragStart = nil
                                })
                        if selection.count == 1 && selection.contains(key.id) {
                            resizeHandle(key, size: size)
                        }
                    }
                }.coordinateSpace(name: isRight ? "right" : "left")
            }.aspectRatio(width/height, contentMode: .fit)
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(selection.count) selected").font(.headline)
            Picker("Select key", selection: Binding<UUID?>(get: { selection.count == 1 ? selection.first : nil }, set: { id in
                selection = id.map { [$0] } ?? []
            })) {
                Text("Choose…").tag(UUID?.none)
                ForEach(document.keys) { key in
                    Text("\(key.right ? "R" : "L") · \(legend(key)) [\(key.row),\(key.column)]").tag(Optional(key.id))
                }
            }
            if let key = document.keys.first(where: { selection.contains($0.id) }), selection.count == 1 {
                Text("Key: \(legend(key))").font(.headline)
                Text("Assign Primary / Hold actions in Keymap Tuning after applying.").font(.caption).foregroundStyle(.secondary)
                field("X", key: key, path: \.x, scale: width)
                field("Y", key: key, path: \.y, scale: height)
                field("Width", key: key, path: \.width, scale: width)
                field("Height", key: key, path: \.height, scale: height)
                HStack {
                    Text("Angle").frame(width: 55, alignment: .leading)
                    TextField("Degrees", value: Binding(get: { key.rect.rotationDegrees }, set: { value in
                        guard value.isFinite else { return }
                        change { if let i = document.keys.firstIndex(where: { $0.id == key.id }) { document.keys[i].rect.rotationDegrees = value.truncatingRemainder(dividingBy: 360) } }
                    }), format: .number.precision(.fractionLength(1)))
                }
            }
            HStack {
                Button("Rotate −5°") { rotate(-5) }
                Button("+5°") { rotate(5) }
            }.disabled(selection.isEmpty)
            HStack {
                Button("Align X") { align(horizontal: true) }
                Button("Align Y") { align(horizontal: false) }
            }.disabled(selection.count < 2)
            HStack {
                Button("Distribute X") { distribute(horizontal: true) }
                Button("Y") { distribute(horizontal: false) }
            }.disabled(selection.count < 3)
            HStack {
                Button("Group") { change {
                    let group = LayoutDocument.Group(name: "Group \(document.groups.count+1)")
                    document.groups.append(group)
                    for i in document.keys.indices where selection.contains(document.keys[i].id) { document.keys[i].group = group.id }
                } }
                Button("Ungroup") { change {
                    for i in document.keys.indices where selection.contains(document.keys[i].id) { document.keys[i].group = nil }
                } }
            }.disabled(selection.isEmpty)
            HStack {
                Button("Duplicate") { change { selection = document.duplicate(selection) } }
                Button("Delete") { change { document.remove(selection); selection = [] } }
            }.disabled(selection.isEmpty)
            Divider()
            Picker("Add to", selection: $right) { Text("Left").tag(false); Text("Right").tag(true) }
            Button("Add Key") { change { selection = [document.add(right: right)] } }.disabled(document.keys.count >= 2048 || document.nextRow >= 4095)
            Stepper("Column: \(columnCount) keys", value: $columnCount, in: 1...8)
            Button("Add Column") { change {
                let group = LayoutDocument.Group(name: "Column \(document.groups.count+1)")
                document.groups.append(group); selection = []
                for n in 0..<columnCount {
                    selection.insert(document.add(right: right,
                        rect: NormalizedRect(x: 0.45, y: 0.05 + CGFloat(n)*0.9/CGFloat(columnCount), width: 0.09, height: 0.85/CGFloat(columnCount)), group: group.id))
                }
            } }
            if !document.isValid { Text("Layout exceeds the supported size. Undo the last change before applying.").foregroundStyle(.red).font(.caption) }
            Spacer()
            Text("Columns are selection groups. Every key can move and resize independently. Template changes do not alter other templates.").font(.caption).foregroundStyle(.secondary)
        }.textFieldStyle(.roundedBorder)
    }
    private func legend(_ key: LayoutDocument.Key) -> String {
        KeyActionCatalog.action(for: key.label)?.displayText ?? key.label
    }
    private func visualRect(_ key: LayoutDocument.Key) -> NormalizedRect {
        var r = key.rect
        if key.edges.count == 4 {
            r.x -= key.edges[0]; r.y -= key.edges[1]
            r.width += key.edges[0]+key.edges[2]; r.height += key.edges[1]+key.edges[3]
        }
        return r
    }
    private func resizeHandle(_ key: LayoutDocument.Key, size: CGSize) -> some View {
        let r = key.rect
        let a: CGFloat = CGFloat(r.rotationDegrees) * .pi/180
        let px = r.centerX*size.width + r.width*size.width/2*cos(a)-r.height*size.height/2*sin(a)
        let py = r.centerY*size.height + r.width*size.width/2*sin(a)+r.height*size.height/2*cos(a)
        return Circle().fill(Color.accentColor).frame(width: 10,height: 10).position(x: px,y: py)
            .gesture(DragGesture(minimumDistance: 0,coordinateSpace: .named(key.right ? "right":"left"))
                .onChanged { value in
                    if resizeStart == nil { resizeStart = document }
                    guard let start = resizeStart, let i = start.keys.firstIndex(where: { $0.id == key.id }) else { return }
                    document = start
                    let original = start.keys[i].rect
                    let angle: CGFloat = CGFloat(original.rotationDegrees) * .pi/180
                    let x = value.translation.width/size.width*width, y = value.translation.height/size.height*height
                    var dw: CGFloat = x*cos(angle)+y*sin(angle)
                    var dh: CGFloat = -x*sin(angle)+y*cos(angle)
                    if snap { dw = dw.rounded(); dh = dh.rounded() }
                    dw = min(width-original.width*width,max(CGFloat(1)-original.width*width,dw))
                    dh = min(height-original.height*height,max(CGFloat(1)-original.height*height,dh))
                    var rect = original
                    rect.width += dw/width; rect.height += dh/height
                    rect.x += (dw*cos(angle)-dh*sin(angle)-dw)/2/width
                    rect.y += (dw*sin(angle)+dh*cos(angle)-dh)/2/height
                    document.keys[i].rect = rect
                }.onEnded { _ in
                    if let start = resizeStart, start != document { history.record(start) }
                    resizeStart = nil
                })
    }
    private func field(_ title: String, key: LayoutDocument.Key, path: WritableKeyPath<NormalizedRect, CGFloat>, scale: CGFloat) -> some View {
        HStack {
            Text(title).frame(width: 55, alignment: .leading)
            TextField(title, value: Binding(get: { key.rect[keyPath: path]*scale }, set: { value in
                guard value.isFinite else { return }
                change {
                    if let i = document.keys.firstIndex(where: { $0.id == key.id }) {
                        var r = document.keys[i].rect
                        r[keyPath: path] = value/scale
                        r.width = min(1, max(0.005, r.width)); r.height = min(1, max(0.005, r.height))
                        r.x = min(1-r.width, max(0, r.x)); r.y = min(1-r.height, max(0, r.y))
                        document.keys[i].rect = r
                    }
                }
            }), format: .number.precision(.fractionLength(2)))
        }
    }
    private func change(_ action: () -> Void) {
        let old = document; action()
        if old != document { history.record(old) }
    }
    private func undo() { if let old = history.undo(document) { document = old; selection = [] } }
    private func redo() { if let next = history.redo(document) { document = next; selection = [] } }
    private func rotate(_ degrees: Double) {
        change { document.rotate(selection, degrees: degrees, pad: CGSize(width: width, height: height)) }
    }
    private func align(horizontal: Bool) {
        change {
            let keys = document.keys.filter { selection.contains($0.id) }
            let target = keys.map { horizontal ? $0.rect.centerX : $0.rect.centerY }.reduce(0,+)/CGFloat(max(1,keys.count))
            for i in document.keys.indices where selection.contains(document.keys[i].id) {
                if horizontal { document.keys[i].rect.x = target-document.keys[i].rect.width/2 }
                else { document.keys[i].rect.y = target-document.keys[i].rect.height/2 }
            }
        }
    }
    private func distribute(horizontal: Bool) {
        change {
            let keys = document.keys.filter { selection.contains($0.id) }.sorted { horizontal ? $0.rect.centerX < $1.rect.centerX : $0.rect.centerY < $1.rect.centerY }
            guard keys.count > 2, let first = keys.first, let last = keys.last else { return }
            let start = horizontal ? first.rect.centerX : first.rect.centerY
            let end = horizontal ? last.rect.centerX : last.rect.centerY
            for (n,key) in keys.enumerated() {
                guard let i = document.keys.firstIndex(where: { $0.id == key.id }) else { continue }
                let center = start+(end-start)*CGFloat(n)/CGFloat(keys.count-1)
                if horizontal { document.keys[i].rect.x = center-key.rect.width/2 }
                else { document.keys[i].rect.y = center-key.rect.height/2 }
            }
        }
    }
}
