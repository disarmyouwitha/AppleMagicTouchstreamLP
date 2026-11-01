import SwiftUI
import AppKit

/// Inline, staged authoring workspace. Canvas gestures never publish live geometry.
struct LayoutEditor: View {
    @State var document: LayoutDocument
    let template: LayoutDocument
    let onApply: (LayoutDocument?) -> Void
    let onCancel: () -> Void
    let mappings: [String:KeyMapping]
    @Binding var menuWidth: Double
    @State private var selection = Set<UUID>()
    @State private var mirror = true
    private let snapMM: CGFloat = 1
    @State private var right = true
    @State private var history = LayoutDocumentHistory()
    @State private var dragStart: LayoutDocument?
    @State private var dragKind: DragKind?
    @State private var dragIDs = Set<UUID>()
    @State private var marquee: CGRect?
    @State private var marqueeRight = true
    @State private var marqueeBase = Set<UUID>()
    @State private var columnCount = 3
    @State private var keepProportions = false
    @State private var documentValid = true
    @State private var legends: [UUID: String] = [:]
    private let width = ContentView.trackpadWidthMM
    private let height = ContentView.trackpadHeightMM
    private enum DragKind { case move, resizeFrame(Bool), marquee }
    private var padMM: CGSize { CGSize(width:width,height:height) }
    private var supportsIndependentResize: Bool { document.selectionAllowsIndependentAxes(selection,pad:padMM) }
    private var activeSelectionFrame: LayoutDocument.SelectionFrame? {
        document.selectionFrame(selection,right:right,pad:padMM) ?? document.selectionFrame(selection,right:!right,pad:padMM)
    }

    init(document: LayoutDocument, template: LayoutDocument, onApply: @escaping (LayoutDocument?) -> Void,
         onCancel: @escaping () -> Void, menuWidth: Binding<Double>, initialSelection: Set<UUID> = [], mappings: [String:KeyMapping] = [:]) {
        self.mappings = mappings
        _document = State(initialValue:document)
        self.template = template; self.onApply = onApply; self.onCancel = onCancel; _menuWidth = menuWidth
        _selection = State(initialValue:initialSelection)
        _right = State(initialValue:document.keys.first { initialSelection.contains($0.id) }?.right ?? true)
    }
    private var affected: Set<UUID> { mirror ? document.pairedSelection(selection) : selection }

    var body: some View {
        GeometryReader { viewport in
            let inspectorWidth = WorkspaceColumnSizing.menu(menuWidth,available:viewport.size.width,reserved:0)
            let canvasWidth = max(1,viewport.size.width-inspectorWidth-WorkspaceColumnSizing.dividerWidth)
            let padWidth = min(ContentView.trackpadWidthMM * ContentView.displayScale,max(1,(canvasWidth-60)/2))
            HStack(alignment: .top,spacing: 0) {
                ScrollView(.vertical) {
                    VStack(alignment: .leading,spacing: 16) {
                        header
                        HStack(alignment: .top,spacing: 20) {
                            pad(isRight: false).frame(width:padWidth)
                            pad(isRight: true).frame(width:padWidth)
                        }
                        .frame(height:padWidth/width*height+26)
                        selectionCaption
                        Text("Click to select · drag to move · drag empty space to box-select · Shift adds to selection")
                            .font(.caption).foregroundStyle(.secondary)
                        if selection.count > 1 {
                            Text("Drag the selection box’s corner to resize. Shift keeps proportions.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
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
        .onChange(of: mirror) { enabled in
            if enabled { selection = Set(document.keys.filter { selection.contains($0.id) && $0.right == right }.map(\.id)) }
        }
    }

    private var header: some View {
        ViewThatFits(in:.horizontal) {
            HStack(spacing:12) { editorTitle; Spacer(minLength:8); editorActions }
            VStack(alignment:.leading,spacing:12) {
                editorTitle
                HStack { Spacer(minLength:0); editorActions }
            }
        }
    }
    private var editorTitle: some View {
        HStack(spacing:12) {
            Label("Layout Editor",systemImage:"square.and.pencil").font(.headline)
            mirrorToggle
        }.fixedSize()
    }
    private var editorActions: some View {
        HStack(spacing:8) {
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
    private var mirrorToggle: some View {
        MirrorEditButton(isOn:$mirror)
            .accessibilityLabel("Mirror Edit").accessibilityValue(mirror ? "On":"Off")
            .help("Reflect geometry and structural edits across paired keys. Each pad keeps its own actions.")
    }
    private var selectionCaption: some View {
        HStack(spacing: 12) {
            Label(selection.isEmpty ? "Select keys" : "\(selection.count) selected",systemImage: "cursorarrow")
            if mirror {
                Label("Mirror Edit on",systemImage: "rectangle.split.2x1").foregroundStyle(Color.accentColor)
                if !selection.isEmpty {
                    Text("\(affected.count-selection.count) paired \(affected.count-selection.count == 1 ? "key":"keys")").foregroundStyle(.secondary)
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
                    .accessibilityHint("Click keys or drag empty space to box-select.")
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
        let members = document.keys.filter { selection.contains($0.id) && $0.right == isRight }
        if !members.isEmpty, let frame = document.selectionFrame(selection,right:isRight,pad:padMM) {
            let rect = frame.rect.rect(in:size)
            var local = context
            local.translateBy(x:rect.midX,y:rect.midY); local.rotate(by:.degrees(frame.rect.rotationDegrees))
            local.stroke(Path(CGRect(x:-rect.width/2,y:-rect.height/2,width:rect.width,height:rect.height)),with:.color(.accentColor),lineWidth:1)
            let p = resizePoint(frame.rect,size:size)
            context.fill(Path(CGRect(x:p.x-4,y:p.y-4,width:8,height:8)),with:.color(.accentColor))
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
            let members = document.keys.filter { selection.contains($0.id) && $0.right == isRight }
            let frame = members.isEmpty ? nil : document.selectionFrame(selection,right:isRight,pad:padMM)
            let frameHandle = frame.map { resizePoint($0.rect,size:size) }
            if let frameHandle, hypot(value.startLocation.x-frameHandle.x,value.startLocation.y-frameHandle.y) < 10 {
                right = isRight; dragKind = .resizeFrame(isRight); dragIDs = selection
            } else if let id = document.editorHit(at:p,right:isRight,pad:CGSize(width:width,height:height)) {
                let ids: Set<UUID> = [id]
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
            if snapMM > 0 { dx = (dx*width/snapMM).rounded()*snapMM/width; dy = (dy*height/snapMM).rounded()*snapMM/height }
            document = start; document.translate(dragIDs,dx:dx,dy:dy)
            if mirror { document.mirrorGeometryChanges(from:start,sources:dragIDs) }
        case .resizeFrame(let side):
            guard let frame = start.selectionFrame(dragIDs,right:side,pad:padMM) else { return }
            resizeDrag(value,size:size,start:start,reference:frame.rect,referenceKey:nil)
        case .marquee:
            let x = min(max(value.location.x/size.width,0),1), y = min(max(value.location.y/size.height,0),1)
            let sx = min(max(value.startLocation.x/size.width,0),1), sy = min(max(value.startLocation.y/size.height,0),1)
            let rect = CGRect(x:min(x,sx),y:min(y,sy),width:abs(x-sx),height:abs(y-sy))
            marquee = rect
            selection = marqueeBase.union(document.editorMarquee(rect,right:isRight,groups:false,pad:CGSize(width:width,height:height)))
        }
    }
    private func resizeDrag(_ value: DragGesture.Value, size: CGSize, start: LayoutDocument,
                            reference: NormalizedRect, referenceKey: UUID?) {
        let a = CGFloat(reference.rotationDegrees * .pi/180), c = cos(a), sn = sin(a)
        let dx = value.translation.width/size.width*width, dy = value.translation.height/size.height*height
        var x = dx*c+dy*sn, y = -dx*sn+dy*c
        if snapMM > 0 { x = (x/snapMM).rounded()*snapMM; y = (y/snapMM).rounded()*snapMM }
        let w = reference.width*width, h = reference.height*height
        guard w > 0, h > 0 else { return }
        var sx = max(0.001,1+x/w), sy = max(0.001,1+y/h)
        let proportional = keepProportions || NSEvent.modifierFlags.contains(.shift) || !start.selectionAllowsIndependentAxes(dragIDs,pad:padMM)
        if proportional {
            let scale = max(0.001,(w*(w+x)+h*(h+y))/(w*w+h*h))
            sx = scale; sy = scale
        }
        document = start
        document.resizeSelection(dragIDs,scaleX:sx,scaleY:sy,pad:padMM,referenceKey:referenceKey)
        if mirror { document.mirrorGeometryChanges(from:start,sources:dragIDs) }
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
            if let key = singleKey {
                Text(legends[key.id] ?? key.label).font(.headline)
                Text("\(key.right ? "Right":"Left") trackpad · millimeters").font(.caption).foregroundStyle(.secondary)
                dimensions(key)
                Text("Assign actions in Keymap Tuning after applying.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text(selection.isEmpty ? "Click a key, or drag a box around keys." : "\(selection.count) keys · \(right ? "Right":"Left") trackpad")
                    .font(.subheadline).foregroundStyle(.secondary)
                if selection.count > 1 { selectionDimensions }
            }
            if mirror && selection.contains(where: { id in document.keys.first(where:{$0.id == id})?.mirrorID == nil }) {
                Text("Unpaired keys stay independent.").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Text("Arrange").font(.subheadline.bold())
            LazyVGrid(columns:[GridItem(.adaptive(minimum:90,maximum:90),spacing:8)],alignment:.leading,spacing:10) {
                tool("Smaller 5%","arrow.down.right.and.arrow.up.left",disabled:selection.isEmpty,
                     hint:"Scale selected keys and spacing down by 5%.") { scaleSelection(0.95) }
                tool("Larger 5%","arrow.up.left.and.arrow.down.right",disabled:selection.isEmpty,
                     hint:"Scale selected keys and spacing up by 5%.") { scaleSelection(1.05) }
                tool("Rotate left 5°","arrow.counterclockwise",disabled:selection.isEmpty) { rotate(-5) }
                tool("Align column centers","align.horizontal.center",disabled:selection.count < 2) { align(horizontal:true) }
                tool("Align row centers","align.vertical.center",disabled:selection.count < 2) { align(horizontal:false) }
                tool("Rotate right 5°","arrow.clockwise",disabled:selection.isEmpty) { rotate(5) }
                tool("Space horizontally","distribute.horizontal.center",disabled:selection.count < 3) { distribute(horizontal:true) }
                tool("Space vertically","distribute.vertical.center",disabled:selection.count < 3) { distribute(horizontal:false) }
                tool("Duplicate","square.on.square",disabled:selection.isEmpty,action:duplicate)
                tool("Spacing −5%","arrow.right.and.line.vertical.and.arrow.left",disabled:!canAdjustSpacing,
                     hint:"Reduce selected center-to-center spacing by 5%, keeping key sizes fixed.") { adjustSpacing(0.95) }
                tool("Spacing +5%","arrow.left.and.line.vertical.and.arrow.right",disabled:!canAdjustSpacing,
                     hint:"Increase selected center-to-center spacing by 5%, keeping key sizes fixed.") { adjustSpacing(1.05) }
                tool("Delete","trash",disabled:selection.isEmpty,action:delete)
            }.frame(maxWidth:286,alignment:.leading)
            Divider()
            Text("Add").font(.subheadline.bold())
            if mirror { Label("Both trackpads",systemImage:"rectangle.split.2x1").font(.caption).foregroundStyle(.secondary) }
            else { Picker("Trackpad",selection:$right) { Text("Left").tag(false); Text("Right").tag(true) }.pickerStyle(.segmented) }
            ViewThatFits(in:.horizontal) {
                HStack(spacing:8) { addKeyTool; addColumnControls }.fixedSize(horizontal:true,vertical:false)
                VStack(alignment:.leading,spacing:10) { addKeyTool; addColumnControls }
            }
            Divider()
            if !documentValid { Text("Undo the last change before applying: this layout exceeds the supported size.").font(.caption).foregroundStyle(.red) }
            Text("Dashed outlines show the paired keys affected by Mirror Edit. Key assignments stay independent.")
                .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth:.infinity,alignment:.leading).textFieldStyle(.roundedBorder)
    }
    private var addKeyTool: some View {
        tool("Key","plus.square",disabled:!canAdd(1),action:addKey)
    }
    private var addColumnControls: some View {
        HStack(spacing:8) {
            tool("Column","rectangle.split.1x2",disabled:!canAdd(columnCount),action:addColumn)
            Stepper("\(columnCount) keys per column",value:$columnCount,in:1...8)
                .font(.caption).frame(width:88).fixedSize(horizontal:false,vertical:true)
                .accessibilityLabel("Keys per column")
        }
    }
    @ViewBuilder private var selectionDimensions: some View {
        if let frame = activeSelectionFrame {
            VStack(alignment:.leading,spacing:8) {
                Text("Selection size · mm").font(.subheadline.bold())
                HStack {
                    selectionSizeField("Width",axisX:true,frame:frame)
                    selectionSizeField("Height",axisX:false,frame:frame)
                }
                Text("Selection spacing · mm").font(.subheadline.bold())
                HStack { spacingField("X",axisX:true); spacingField("Y",axisX:false) }
                Text("Gaps between rows or columns; negative values overlap.").font(.caption).foregroundStyle(.secondary)
                Toggle("Keep proportions",isOn:Binding(get:{keepProportions || !supportsIndependentResize},set:{keepProportions = $0}))
                    .toggleStyle(.checkbox).disabled(!supportsIndependentResize).font(.caption)
                Text(supportsIndependentResize ? "Scales keys and spacing together." : "Mixed key angles resize proportionally.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func selectionSizeField(_ title: String,axisX: Bool,frame: LayoutDocument.SelectionFrame) -> some View {
        let size = axisX ? frame.rect.width*width : frame.rect.height*height
        return VStack(alignment:.leading,spacing:4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            LayoutNumericField(title:title,value:Double(size),positive:true) { value in
                guard size > 0 else { return }
                let scale = CGFloat(value)/size
                let linked = keepProportions || !supportsIndependentResize
                let sx = axisX || linked ? scale : 1
                let sy = !axisX || linked ? scale : 1
                change { document.resizeSelection(selection,scaleX:sx,scaleY:sy,pad:padMM) }
            }
            .id(selection.sorted {$0.uuidString < $1.uuidString}.map(\.uuidString).joined()+title)
            .accessibilityLabel("Selection \(title.lowercased())")
        }
    }

    private func spacingField(_ title:String,axisX:Bool) -> some View {
        let side = document.keys.contains {$0.right == right && selection.contains($0.id)} ? right:!right
        let spacing = document.selectionSpacing(selection,right:side,axisX:axisX,pad:padMM)
        return VStack(alignment:.leading,spacing:4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            LayoutNumericField(title:title,value:Double(spacing ?? 0)) { value in
                change { document.setSelectionSpacing(selection,axisX:axisX,millimeters:CGFloat(value),pad:padMM) }
            }.disabled(spacing == nil)
                .id(selection.sorted {$0.uuidString < $1.uuidString}.map(\.uuidString).joined()+"spacing"+title)
                .accessibilityLabel("Selection spacing \(title)")
        }
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
            LayoutNumericField(title:title,value:Double(key.rect[keyPath:path]*scale),positive:path == \.width || path == \.height) { value in
                change {
                    guard let i = document.keys.firstIndex(where:{$0.id == key.id}) else { return }
                    var r = document.keys[i].rect
                    r[keyPath:path] = CGFloat(value)/scale
                    r.width = min(1,max(0.005,r.width)); r.height = min(1,max(0.005,r.height))
                    r.x = min(1-r.width,max(0,r.x)); r.y = min(1-r.height,max(0,r.y))
                    document.keys[i].rect = r
                }
            }.id(key.id.uuidString+title)
        }
    }
    private func icon(_ title: String,_ symbol: String,disabled: Bool = false,action: @escaping () -> Void) -> some View {
        Button(action:action) { Image(systemName:symbol).frame(width:22,height:20) }
            .disabled(disabled).help(title).accessibilityLabel(title)
    }
    private func tool(_ title: String,_ symbol: String,disabled: Bool = false,hint: String? = nil,action: @escaping () -> Void) -> some View {
        LayoutToolButton(title:title,symbol:symbol,action:action)
            .frame(width:90).disabled(disabled).help(hint ?? title).accessibilityLabel(title)
    }
    private var canAdjustSpacing: Bool {
        [false,true].contains { side in
            document.selectionSpacing(selection,right:side,axisX:true,pad:padMM) != nil ||
            document.selectionSpacing(selection,right:side,axisX:false,pad:padMM) != nil
        }
    }
    private func adjustSpacing(_ factor:CGFloat) {
        change { document.scaleSelectionSpacing(selection,factor:factor,pad:padMM) }
    }

    private func refreshLegends() {
        legends = document.editorLegends(mappings:mappings)
    }
    private func change(mirrorGeometry: Bool = true,_ action: () -> Void) {
        let old = document, ids = selection
        action()
        if mirror && mirrorGeometry { document.mirrorGeometryChanges(from:old,sources:ids) }
        if old != document { history.record(old); documentValid = document.isValid; refreshLegends() }
    }
    private func undo() { if let old = history.undo(document) { document = old; selection = []; documentValid = document.isValid; refreshLegends() } }
    private func redo() { if let next = history.redo(document) { document = next; selection = []; documentValid = document.isValid; refreshLegends() } }
    private func scaleSelection(_ factor: CGFloat) {
        change { document.resizeSelection(selection,scaleX:factor,scaleY:factor,pad:padMM) }
    }
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

/// Keep the enabled state visible even when another application has focus.
struct MirrorEditButton: View {
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button { isOn.toggle() } label: {
            Label("Mirror Edit",systemImage:"rectangle.split.2x1")
                .padding(.horizontal,10).padding(.vertical,5)
                .foregroundStyle(isOn && isEnabled ? Color.white:Color.primary)
                .background(isOn && isEnabled ? Color.accentColor:Color.primary.opacity(0.08),in:RoundedRectangle(cornerRadius:5))
                .contentShape(RoundedRectangle(cornerRadius:5))
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1:0.45)
        .accessibilityLabel("Mirror Edit").accessibilityValue(isOn ? "On":"Off")
    }
}

private struct LayoutToolButton: View {
    let title:String
    let symbol:String
    let action:() -> Void
    @State private var glow = false
    @State private var pulse = UUID()
    var body: some View {
        Button {
            let token = UUID(); pulse = token
            withAnimation(.easeOut(duration:0.08)) { glow = true }
            action()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds:150_000_000)
                guard pulse == token else { return }
                withAnimation(.easeOut(duration:0.65)) { glow = false }
            }
        } label: {
            VStack(spacing:5) {
                Image(systemName:symbol).font(.system(size:18)).frame(height:22)
                Text(title).font(.caption).lineLimit(2).multilineTextAlignment(.center)
            }.frame(maxWidth:.infinity,minHeight:48)
        }
        .buttonStyle(LayoutToolButtonStyle())
        .overlay(RoundedRectangle(cornerRadius:6).stroke(Color.accentColor.opacity(glow ? 1:0),lineWidth:2)
            .shadow(color:Color.accentColor.opacity(glow ? 0.55:0),radius:5).allowsHitTesting(false))
    }
}

private struct LayoutToolButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration:Configuration) -> some View {
        configuration.label.padding(.horizontal,8).padding(.vertical,4)
            .foregroundStyle(configuration.isPressed ? Color.white:Color.primary)
            .background(configuration.isPressed ? Color.accentColor:Color.primary.opacity(0.07),in:RoundedRectangle(cornerRadius:6))
            .scaleEffect(configuration.isPressed ? 0.96:1)
            .opacity(enabled ? 1:0.3)
    }
}

/// Keep incomplete input local; publish one undoable edit on Return or focus loss.
struct LayoutNumericField: View {
    let title:String
    let value:Double
    var positive = false
    let onCommit:(Double) -> Void
    @State private var draft = ""
    @State private var invalid = false
    @FocusState private var focused:Bool
    private var formatted:String { value.formatted(.number.precision(.fractionLength(2))) }
    var body: some View {
        VStack(alignment:.leading,spacing:2) {
            TextField(title,text:$draft).focused($focused).onSubmit(commit)
                .onAppear { draft = formatted }
                .onChange(of:value) { _ in if !focused { draft = formatted } }
                .onChange(of:focused) { active in if !active { commit() } }
                .onChange(of:draft) { _ in invalid = false }
            if invalid { Text(positive ? "Enter a value above zero.":"Enter a number.").font(.caption2).foregroundStyle(.red) }
        }
    }
    private func commit() {
        let text = draft.replacingOccurrences(of:Locale.current.decimalSeparator ?? ".",with:".")
        guard let number = Double(text), number.isFinite, !positive || number > 0 else { invalid = true; return }
        if number != value { onCommit(number) }
        draft = number.formatted(.number.precision(.fractionLength(2)))
    }
}
