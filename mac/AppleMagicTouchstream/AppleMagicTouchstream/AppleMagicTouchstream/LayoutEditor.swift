import SwiftUI
import AppKit

/// Inline, staged authoring workspace. Canvas gestures never publish live geometry.
struct LayoutEditor: View {
    @State var document: LayoutDocument
    let template: LayoutDocument
    let onApply: (LayoutDocument?) -> Void
    let onCancel: () -> Void
    @Binding var menuWidth: Double
    @State private var selection = Set<UUID>()
    @State private var groupSelection = false
    @State private var mirror = true
    @State private var snap = true
    @State private var right = true
    @State private var history = LayoutDocumentHistory()
    @State private var dragStart: LayoutDocument?
    @State private var dragKind: DragKind?
    @State private var dragIDs = Set<UUID>()
    @State private var marquee: CGRect?
    @State private var marqueeRight = true
    @State private var marqueeBase = Set<UUID>()
    @State private var columnCount = 3
    @State private var documentValid = true
    @State private var legends: [UUID: String] = [:]
    private let width = ContentView.trackpadWidthMM
    private let height = ContentView.trackpadHeightMM
    private enum DragKind { case move, resize(UUID), marquee }
    private var affected: Set<UUID> { mirror ? document.pairedSelection(selection) : selection }

    var body: some View {
        GeometryReader { viewport in
            let inspectorWidth = WorkspaceColumnSizing.menu(menuWidth,available:viewport.size.width,reserved:0)
            let canvasWidth = max(1,viewport.size.width-inspectorWidth-WorkspaceColumnSizing.dividerWidth)
            HStack(alignment: .top,spacing: 0) {
                ScrollView(.vertical) {
                    VStack(alignment: .leading,spacing: 16) {
                        header
                        selectionTools
                        HStack(alignment: .top,spacing: 20) {
                            pad(isRight: false)
                            pad(isRight: true)
                        }
                        .frame(height: min((canvasWidth-60)/2/width*height+26,max(210,viewport.size.height-205)))
                        selectionCaption
                        Text("Click to select · drag to move · drag empty space to box-select · Shift adds to selection")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(20).frame(maxWidth: .infinity,alignment: .topLeading)
                }.frame(maxWidth: .infinity)
                WorkspaceColumnDivider(width:Binding(get:{inspectorWidth},set:{menuWidth = $0}),
                    minimum:WorkspaceColumnSizing.minimumMenu,
                    maximum:WorkspaceColumnSizing.menuMaximum(available:viewport.size.width,reserved:0),
                    trailingColumn:true,label:"Layout editor settings width")
                ScrollView { inspector.padding(16) }.frame(width: inspectorWidth)
            }
        }
        .onAppear { documentValid = document.isValid; refreshLegends() }
        .onChange(of: groupSelection) { _ in selection = [] }
        .onChange(of: mirror) { enabled in
            if enabled { selection = Set(document.keys.filter { selection.contains($0.id) && $0.right == right }.map(\.id)) }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("Layout Editor",systemImage: "square.and.pencil").font(.headline)
            Spacer(minLength: 8)
            icon("Undo", "arrow.uturn.backward",disabled: !history.canUndo || dragStart != nil,action: undo)
                .keyboardShortcut("z",modifiers: .command)
            icon("Redo", "arrow.uturn.forward",disabled: !history.canRedo || dragStart != nil,action: redo)
                .keyboardShortcut("z",modifiers: [.command,.shift])
            Button {
                change(mirrorGeometry:false) { document = template; selection = [] }
            } label: { Label("Reset",systemImage:"arrow.counterclockwise") }
                .help("Reset template geometry; Undo can restore your edits.").accessibilityLabel("Reset Template").disabled(dragStart != nil)
            Divider().frame(height: 20)
            Button("Cancel",action: onCancel).keyboardShortcut(.cancelAction)
            Button { onApply(document) } label: { Label("Apply",systemImage: "checkmark") }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!documentValid || dragStart != nil).accessibilityLabel("Apply")
        }
    }
    private var selectionTools: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { selectionMode; mirrorToggle; snapToggle; Spacer(minLength: 0) }
            VStack(alignment: .leading,spacing: 8) {
                selectionMode
                HStack { mirrorToggle; snapToggle }
            }
        }
    }
    private var selectionMode: some View {
        Picker("Select",selection: $groupSelection) {
            Label("Keys",systemImage: "square").tag(false)
            Label("Columns / Groups",systemImage: "rectangle.split.3x1").tag(true)
        }.pickerStyle(.segmented).frame(width: 245)
            .help("Choose individual keys, or select a whole column/group by clicking any of its keys.")
    }
    private var mirrorToggle: some View {
        Toggle(isOn: $mirror) { Label("Mirror Edit",systemImage: "rectangle.split.2x1") }
            .toggleStyle(.button).tint(.accentColor).accessibilityLabel("Mirror Edit")
            .help("Reflect geometry and structural edits across paired keys. Each pad keeps its own actions.")
    }
    private var snapToggle: some View {
        Toggle(isOn: $snap) { Label("1 mm",systemImage: "grid") }
            .toggleStyle(.button).help("Snap editing to a 1 mm grid. Independent of typing Snap Radius.")
    }
    private var selectionCaption: some View {
        HStack(spacing: 12) {
            Label(selection.isEmpty ? "Select a key or column" : "\(selection.count) selected",systemImage: "cursorarrow")
            if mirror {
                Label("Mirror Edit on",systemImage: "rectangle.split.2x1").foregroundStyle(Color.accentColor)
                if !selection.isEmpty {
                    Text("\(affected.count-selection.count) paired keys").foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }.font(.caption)
    }

    private func pad(isRight: Bool) -> some View {
        VStack(alignment: .leading,spacing: 5) {
            HStack {
                Text(isRight ? "Right trackpad" : "Left trackpad").font(.subheadline.bold())
                Spacer()
                if !selection.isEmpty && right == isRight { Text("Editing").font(.caption).foregroundStyle(Color.accentColor) }
            }
            GeometryReader { proxy in
                let size = proxy.size
                Canvas { context,size in drawPad(&context,size:size,isRight:isRight) }
                    .background(Color.primary.opacity(0.025))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.6)))
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0,coordinateSpace: .local)
                        .onChanged { updateDrag($0,size:size,isRight:isRight) }
                        .onEnded { _ in finishDrag() })
                    .accessibilityElement(children:.ignore)
                    .accessibilityLabel(isRight ? "Right trackpad layout" : "Left trackpad layout")
                    .accessibilityHint("Use Select key in the inspector to select keys without dragging.")
            }.aspectRatio(width/height,contentMode: .fit)
        }.frame(maxWidth: .infinity,alignment: .topLeading)
    }

    private func drawPad(_ context: inout GraphicsContext,size: CGSize,isRight: Bool) {
        var grid = Path()
        for mm in stride(from: CGFloat(10),to: width,by: 10) {
            grid.move(to: CGPoint(x: mm/width*size.width,y: 0)); grid.addLine(to: CGPoint(x:mm/width*size.width,y:size.height))
        }
        for mm in stride(from: CGFloat(10),to: height,by: 10) {
            grid.move(to: CGPoint(x:0,y:mm/height*size.height)); grid.addLine(to: CGPoint(x:size.width,y:mm/height*size.height))
        }
        context.stroke(grid,with:.color(.secondary.opacity(0.15)),lineWidth:0.5)
        let paired = mirror ? document.pairedSelection(selection).subtracting(selection) : []
        for key in document.keys where key.right == isRight {
            let rect = key.displayRect.rect(in: size)
            var local = context
            local.translateBy(x:rect.midX,y:rect.midY)
            local.rotate(by:.degrees(key.rect.rotationDegrees))
            let outline = Path(roundedRect:CGRect(x:-rect.width/2,y:-rect.height/2,width:rect.width,height:rect.height),cornerRadius:4)
            let selected = selection.contains(key.id), reflected = paired.contains(key.id)
            local.fill(outline,with:.color(selected ? .accentColor.opacity(0.2) : reflected ? .accentColor.opacity(0.08) : .primary.opacity(0.035)))
            local.stroke(outline,with:.color(selected || reflected ? .accentColor : .secondary.opacity(0.8)),
                         style:StrokeStyle(lineWidth:selected ? 2:1,dash:reflected ? [4,3]:[]))
            let fontSize = max(7,min(12,min(rect.width*0.34,rect.height*0.35)))
            let text = Text(legends[key.id] ?? key.label).font(.system(size:fontSize,weight:.semibold)).foregroundColor(.primary)
            local.draw(text,at:.zero)
        }
        if let key = singleKey, key.right == isRight {
            let p = resizePoint(key.rect,size:size)
            context.fill(Path(ellipseIn:CGRect(x:p.x-4,y:p.y-4,width:8,height:8)),with:.color(.accentColor))
        }
        if let marquee, marqueeRight == isRight {
            let rect = CGRect(x:marquee.minX*size.width,y:marquee.minY*size.height,width:marquee.width*size.width,height:marquee.height*size.height)
            let path = Path(rect)
            context.fill(path,with:.color(.accentColor.opacity(0.1)))
            context.stroke(path,with:.color(.accentColor),style:StrokeStyle(lineWidth:1,dash:[4,3]))
        }
    }

    private var singleKey: LayoutDocument.Key? {
        selection.count == 1 ? document.keys.first { selection.contains($0.id) } : nil
    }
    private func select(_ ids: Set<UUID>,onRight: Bool,adding: Bool) {
        right = onRight
        if adding {
            if mirror { selection = Set(document.keys.filter { selection.contains($0.id) && $0.right == onRight }.map(\.id)) }
            selection.formUnion(ids)
        } else { selection = ids }
    }
    private func updateDrag(_ value: DragGesture.Value,size: CGSize,isRight: Bool) {
        guard size.width > 0, size.height > 0 else { return }
        if dragStart == nil {
            let p = CGPoint(x:value.startLocation.x/size.width,y:value.startLocation.y/size.height)
            let adding = NSEvent.modifierFlags.contains(.shift)
            if let key = singleKey, key.right == isRight,
               hypot(value.startLocation.x-resizePoint(key.rect,size:size).x,value.startLocation.y-resizePoint(key.rect,size:size).y) < 10 {
                right = isRight; dragKind = .resize(key.id); dragIDs = [key.id]
            } else if let id = document.editorHit(at:p,right:isRight,pad:CGSize(width:width,height:height)) {
                var ids: Set<UUID> = [id]
                if groupSelection { ids = document.expandedGroups(ids) }
                if !ids.isSubset(of:selection) { select(ids,onRight:isRight,adding:adding) }
                else { right = isRight }
                if mirror { selection = Set(document.keys.filter { selection.contains($0.id) && $0.right == isRight }.map(\.id)) }
                dragKind = .move; dragIDs = selection
            } else {
                dragKind = .marquee; marqueeRight = isRight
                select([],onRight:isRight,adding:adding)
                marqueeBase = selection
            }
            dragStart = document
        }
        guard let start = dragStart, let kind = dragKind else { return }
        switch kind {
        case .move:
            var dx = value.translation.width/size.width, dy = value.translation.height/size.height
            if snap { dx = (dx*width).rounded()/width; dy = (dy*height).rounded()/height }
            document = start; document.translate(dragIDs,dx:dx,dy:dy)
            if mirror { document.mirrorGeometryChanges(from:start,sources:dragIDs) }
        case .resize(let id):
            guard let i = start.keys.firstIndex(where: { $0.id == id }) else { return }
            let original = start.keys[i].rect
            let a: CGFloat = CGFloat(original.rotationDegrees) * .pi/180
            let x = value.translation.width/size.width*width, y = value.translation.height/size.height*height
            var dw: CGFloat = x*cos(a)+y*sin(a), dh: CGFloat = -x*sin(a)+y*cos(a)
            if snap { dw = dw.rounded(); dh = dh.rounded() }
            dw = min(width-original.width*width,max(CGFloat(1)-original.width*width,dw))
            dh = min(height-original.height*height,max(CGFloat(1)-original.height*height,dh))
            var rect = original
            rect.width += dw/width; rect.height += dh/height
            rect.x += (dw*cos(a)-dh*sin(a)-dw)/2/width
            rect.y += (dw*sin(a)+dh*cos(a)-dh)/2/height
            document = start; document.keys[i].rect = rect
            if mirror { document.mirrorGeometryChanges(from:start,sources:[id]) }
        case .marquee:
            let x = min(max(value.location.x/size.width,0),1), y = min(max(value.location.y/size.height,0),1)
            let sx = min(max(value.startLocation.x/size.width,0),1), sy = min(max(value.startLocation.y/size.height,0),1)
            let rect = CGRect(x:min(x,sx),y:min(y,sy),width:abs(x-sx),height:abs(y-sy))
            marquee = rect
            selection = marqueeBase.union(document.editorMarquee(rect,right:isRight,groups:groupSelection,pad:CGSize(width:width,height:height)))
        }
    }
    private func finishDrag() {
        if let start = dragStart, start != document { history.record(start) }
        documentValid = document.isValid
        dragStart = nil; dragKind = nil; marquee = nil; dragIDs = []
    }
    private func resizePoint(_ rect: NormalizedRect,size: CGSize) -> CGPoint {
        let a: CGFloat = CGFloat(rect.rotationDegrees) * .pi/180
        return CGPoint(x:rect.centerX*size.width+rect.width*size.width/2*cos(a)-rect.height*size.height/2*sin(a),
                       y:rect.centerY*size.height+rect.width*size.width/2*sin(a)+rect.height*size.height/2*cos(a))
    }

    private var inspector: some View {
        VStack(alignment: .leading,spacing: 14) {
            Label("Selection",systemImage:"cursorarrow").font(.headline)
            Picker("Key",selection:Binding<UUID?>(get:{singleKey?.id},set:{id in
                guard let id, let key = document.keys.first(where:{$0.id == id}) else { selection = []; return }
                select(groupSelection ? document.expandedGroups([id]):[id],onRight:key.right,adding:false)
            })) {
                Text("Choose a key…").tag(UUID?.none)
                ForEach(Array(document.keys.enumerated()),id: \.element.id) { n,key in
                    Text("\(key.right ? "R":"L") · \(legends[key.id] ?? key.label) · \(n+1)").tag(Optional(key.id))
                }
            }
            if let key = singleKey {
                Text(legends[key.id] ?? key.label).font(.headline)
                Text("\(key.right ? "Right":"Left") trackpad · millimeters").font(.caption).foregroundStyle(.secondary)
                dimensions(key)
                Text("Assign actions in Keymap Tuning after applying.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text(selection.isEmpty ? "Click a key, or drag a box around keys." : "\(selection.count) keys · \(right ? "Right":"Left") trackpad")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if mirror && selection.contains(where: { id in document.keys.first(where:{$0.id == id})?.mirrorID == nil }) {
                Text("Unpaired keys stay independent.").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Text("Arrange").font(.subheadline.bold())
            HStack {
                tool("Rotate left 5°","arrow.counterclockwise",disabled:selection.isEmpty) { rotate(-5) }
                tool("Rotate right 5°","arrow.clockwise",disabled:selection.isEmpty) { rotate(5) }
            }
            HStack {
                tool("Align column centers","align.horizontal.center",disabled:selection.count < 2) { align(horizontal:true) }
                tool("Align row centers","align.vertical.center",disabled:selection.count < 2) { align(horizontal:false) }
            }
            HStack {
                tool("Space horizontally","distribute.horizontal.center",disabled:selection.count < 3) { distribute(horizontal:true) }
                tool("Space vertically","distribute.vertical.center",disabled:selection.count < 3) { distribute(horizontal:false) }
            }
            Divider()
            HStack {
                tool("Group","square.on.square.dashed",disabled:selection.isEmpty,action:group)
                tool("Ungroup","square.dashed",disabled:selection.isEmpty,action:ungroup)
            }
            HStack {
                tool("Duplicate","square.on.square",disabled:selection.isEmpty,action:duplicate)
                tool("Delete","trash",disabled:selection.isEmpty,action:delete)
            }
            Divider()
            Text("Add").font(.subheadline.bold())
            if mirror { Label("Both trackpads",systemImage:"rectangle.split.2x1").font(.caption).foregroundStyle(.secondary) }
            else { Picker("Trackpad",selection:$right) { Text("Left").tag(false); Text("Right").tag(true) }.pickerStyle(.segmented) }
            HStack {
                tool("Key","plus.square",disabled:!canAdd(1),action:addKey)
                tool("Column","rectangle.split.1x2",disabled:!canAdd(columnCount),action:addColumn)
            }
            Stepper("\(columnCount) keys per column",value:$columnCount,in:1...8).font(.subheadline)
            Divider()
            if !documentValid { Text("Undo the last change before applying: this layout exceeds the supported size.").font(.caption).foregroundStyle(.red) }
            Text("Dashed outlines show the paired keys affected by Mirror Edit. Key assignments stay independent.")
                .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth:.infinity,alignment:.leading).textFieldStyle(.roundedBorder)
    }
    private func dimensions(_ key: LayoutDocument.Key) -> some View {
        VStack(spacing: 8) {
            HStack { field("X",key:key,path: \.x,scale:width); field("Y",key:key,path: \.y,scale:height) }
            HStack { field("Width",key:key,path: \.width,scale:width); field("Height",key:key,path: \.height,scale:height) }
            HStack {
                Text("Angle").font(.caption).foregroundStyle(.secondary)
                TextField("Degrees",value:Binding(get:{key.rect.rotationDegrees},set:{value in
                    guard value.isFinite else { return }
                    change {
                        if let i = document.keys.firstIndex(where:{$0.id == key.id}) { document.keys[i].rect.rotationDegrees = value.truncatingRemainder(dividingBy:360) }
                    }
                }),format:.number.precision(.fractionLength(1)))
                Text("°").foregroundStyle(.secondary)
            }
        }
    }
    private func field(_ title: String,key: LayoutDocument.Key,path: WritableKeyPath<NormalizedRect,CGFloat>,scale: CGFloat) -> some View {
        VStack(alignment:.leading,spacing:4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title,value:Binding(get:{key.rect[keyPath:path]*scale},set:{value in
                guard value.isFinite else { return }
                change {
                    guard let i = document.keys.firstIndex(where:{$0.id == key.id}) else { return }
                    var r = document.keys[i].rect
                    r[keyPath:path] = value/scale
                    r.width = min(1,max(0.005,r.width)); r.height = min(1,max(0.005,r.height))
                    r.x = min(1-r.width,max(0,r.x)); r.y = min(1-r.height,max(0,r.y))
                    document.keys[i].rect = r
                }
            }),format:.number.precision(.fractionLength(2)))
        }
    }
    private func icon(_ title: String,_ symbol: String,disabled: Bool = false,action: @escaping () -> Void) -> some View {
        Button(action:action) { Image(systemName:symbol).frame(width:22,height:20) }
            .disabled(disabled).help(title).accessibilityLabel(title)
    }
    private func tool(_ title: String,_ symbol: String,disabled: Bool = false,action: @escaping () -> Void) -> some View {
        Button(action:action) {
            VStack(spacing:5) {
                Image(systemName:symbol).font(.system(size:18)).frame(height:22)
                Text(title).font(.caption).lineLimit(2).multilineTextAlignment(.center)
            }.frame(maxWidth:.infinity,minHeight:48)
        }.disabled(disabled).help(title).accessibilityLabel(title)
    }
    private func refreshLegends() {
        legends = Dictionary(uniqueKeysWithValues:document.keys.map { ($0.id,KeyActionCatalog.action(for:$0.label)?.displayText ?? $0.label) })
    }
    private func change(mirrorGeometry: Bool = true,_ action: () -> Void) {
        let old = document, ids = selection
        action()
        if mirror && mirrorGeometry { document.mirrorGeometryChanges(from:old,sources:ids) }
        if old != document { history.record(old); documentValid = document.isValid; refreshLegends() }
    }
    private func undo() { if let old = history.undo(document) { document = old; selection = []; documentValid = document.isValid; refreshLegends() } }
    private func redo() { if let next = history.redo(document) { document = next; selection = []; documentValid = document.isValid; refreshLegends() } }
    private func rotate(_ degrees: Double) {
        change { document.rotate(selection,degrees:degrees,pad:CGSize(width:width,height:height)) }
    }
    private func align(horizontal: Bool) {
        change {
            let keys = document.keys.filter { selection.contains($0.id) }
            let center = keys.map { horizontal ? $0.rect.centerX:$0.rect.centerY }.reduce(0,+)/CGFloat(max(1,keys.count))
            for i in document.keys.indices where selection.contains(document.keys[i].id) {
                if horizontal { document.keys[i].rect.x = center-document.keys[i].rect.width/2 }
                else { document.keys[i].rect.y = center-document.keys[i].rect.height/2 }
            }
        }
    }
    private func distribute(horizontal: Bool) {
        change {
            let keys = document.keys.filter { selection.contains($0.id) }.sorted { horizontal ? $0.rect.centerX < $1.rect.centerX:$0.rect.centerY < $1.rect.centerY }
            guard keys.count > 2, let first = keys.first, let last = keys.last else { return }
            let start = horizontal ? first.rect.centerX:first.rect.centerY, end = horizontal ? last.rect.centerX:last.rect.centerY
            for (n,key) in keys.enumerated() {
                guard let i = document.keys.firstIndex(where:{$0.id == key.id}) else { continue }
                let value = start+(end-start)*CGFloat(n)/CGFloat(keys.count-1)
                if horizontal { document.keys[i].rect.x = value-key.rect.width/2 }
                else { document.keys[i].rect.y = value-key.rect.height/2 }
            }
        }
    }
    private func group() {
        change(mirrorGeometry:false) {
            let ids = affected
            for side in [false,true] {
                let members = Set(document.keys.filter { ids.contains($0.id) && $0.right == side }.map(\.id))
                guard !members.isEmpty else { continue }
                let group = LayoutDocument.Group(name:"\(side ? "Right":"Left") group \(document.groups.count+1)")
                document.groups.append(group)
                for i in document.keys.indices where members.contains(document.keys[i].id) { document.keys[i].group = group.id }
            }
            document.groups.removeAll { group in !document.keys.contains { $0.group == group.id } }
        }
    }
    private func ungroup() {
        change(mirrorGeometry:false) {
            let ids = affected
            for i in document.keys.indices where ids.contains(document.keys[i].id) { document.keys[i].group = nil }
            document.groups.removeAll { group in !document.keys.contains { $0.group == group.id } }
        }
    }
    private func duplicate() {
        change(mirrorGeometry:false) {
            let ids = affected
            let added = document.duplicate(ids,mirrorOffset:mirror,sourceRight:right)
            selection = mirror ? Set(document.keys.filter { added.contains($0.id) && $0.right == right }.map(\.id)):added
        }
    }
    private func delete() { change(mirrorGeometry:false) { document.remove(affected); selection = [] } }
    private func canAdd(_ count: Int) -> Bool {
        let total = count*(mirror ? 2:1)
        return document.keys.count+total <= 2048 && document.nextRow+total < 4096
    }
    private func addKey() {
        change(mirrorGeometry:false) {
            selection = [mirror ? document.addMirrored(right:right):document.add(right:right)]
        }
    }
    private func addColumn() {
        change(mirrorGeometry:false) {
            let group = LayoutDocument.Group(name:"Column \(document.groups.count+1)")
            let other = LayoutDocument.Group(name:"Mirrored column \(document.groups.count+2)")
            document.groups.append(group)
            if mirror { document.groups.append(other) }
            selection = []
            for n in 0..<columnCount {
                let r = NormalizedRect(x:0.45,y:0.05+CGFloat(n)*0.9/CGFloat(columnCount),width:0.09,height:0.85/CGFloat(columnCount))
                selection.insert(mirror ? document.addMirrored(right:right,rect:r,group:group.id,oppositeGroup:other.id):document.add(right:right,rect:r,group:group.id))
            }
        }
    }
}
