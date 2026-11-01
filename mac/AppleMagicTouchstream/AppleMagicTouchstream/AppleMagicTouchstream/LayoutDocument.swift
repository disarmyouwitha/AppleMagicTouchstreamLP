import Foundation

/// Authoring identity is independent of the engine's immutable binding address.
struct LayoutDocument: Codable, Equatable {
    struct Key: Codable, Equatable, Identifiable {
        var id = UUID()
        var right: Bool
        var row: Int
        var column: Int
        var label: String
        var rect: NormalizedRect
        var group: UUID?
        var mirrorID: UUID? = nil
        var copySourceRow: Int? = nil
        var copySourceColumn: Int? = nil
        // Explicit visual extensions preserve the accepted STENO overlap drawing.
        var edges: [CGFloat] = [0, 0, 0, 0] // left, top, right, bottom
        var displayRect: NormalizedRect {
            var r = rect
            if edges.count == 4 {
                r.x -= edges[0]; r.y -= edges[1]
                r.width += edges[0]+edges[2]; r.height += edges[1]+edges[3]
            }
            return r
        }
    }
    struct Group: Codable, Equatable, Identifiable {
        var id = UUID()
        var name: String
    }
    var keys: [Key] = []
    var groups: [Group] = []
    var nextRow = 0

    @MainActor
    static func seed(left: ContentViewModel.Layout, right: ContentViewModel.Layout,
                     leftLabels: [[String]], rightLabels: [[String]], groupByBindingColumn: Bool = false) -> Self {
        var result = Self()
        for (isRight, layout, labels) in [(false, left, leftLabels), (true, right, rightLabels)] {
            var columns: [Int: UUID] = [:]
            for (row, rects) in layout.normalizedKeyRects.enumerated() {
                for (column, rect) in rects.enumerated() where rect.width > 0 && rect.height > 0 {
                    let group: UUID
                    let geometricGroup = result.keys.first { key in
                        key.right == isRight && abs(key.rect.centerX-rect.centerX) < 2/ContentView.trackpadWidthMM &&
                        abs(key.rect.width-rect.width) < 1/ContentView.trackpadWidthMM &&
                        abs(key.rect.rotationDegrees-rect.rotationDegrees) < 5
                    }?.group
                    if let existing = groupByBindingColumn ? columns[column] : geometricGroup { group = existing }
                    else {
                        let value = Group(name: "\(isRight ? "Right" : "Left") group \(result.groups.count + 1)")
                        result.groups.append(value); columns[column] = value.id; group = value.id
                    }
                    let display = TrackpadSurfaceView.stenoDisplayRect(rect, layout: layout)
                    result.keys.append(Key(right: isRight, row: row, column: column,
                        label: labels.indices.contains(row) && labels[row].indices.contains(column) ? labels[row][column] : "None",
                        rect: rect, group: group,
                        edges: [rect.x-display.x, rect.y-display.y,
                                display.width-rect.width-(rect.x-display.x),
                                display.height-rect.height-(rect.y-display.y)]))
                    result.nextRow = max(result.nextRow, row + 1)
                }
            }
        }
        return result
    }

    var isValid: Bool {
        guard keys.count <= 2048, nextRow >= 0, nextRow < 4096,
              Set(keys.map(\.id)).count == keys.count,
              Set(groups.map(\.id)).count == groups.count else { return false }
        var slots = Set<String>()
        let groupIDs = Set(groups.map(\.id))
        let byID = Dictionary(uniqueKeysWithValues: keys.map { ($0.id, $0) })
        return keys.allSatisfy { key in
            let r = key.rect
            return key.row >= 0 && key.row < nextRow && key.column >= 0 && key.column < 128 &&
                slots.insert("\(key.right):\(key.row):\(key.column)").inserted &&
                [r.x,r.y,r.width,r.height,CGFloat(r.rotationDegrees)].allSatisfy(\.isFinite) &&
                r.width > 0 && r.width <= 2 && r.height > 0 && r.height <= 2 &&
                abs(r.x) <= 2 && abs(r.y) <= 2 && key.edges.count == 4 &&
                key.edges.allSatisfy { $0.isFinite && abs($0) < 1 } &&
                key.displayRect.width > 0 && key.displayRect.height > 0 &&
                (key.group == nil || groupIDs.contains(key.group!)) &&
                (key.mirrorID == nil || (byID[key.mirrorID!]?.mirrorID == key.id && byID[key.mirrorID!]?.right != key.right))
        }
    }

    func labels(right: Bool) -> [[String]] { arrays(right: right).1 }
    private func arrays(right: Bool) -> ([[NormalizedRect]], [[String]]) {
        let side = keys.filter { $0.right == right }
        guard let last = side.map(\.row).max(), last >= 0, last < 4096 else { return ([], []) }
        var rects = [[NormalizedRect]](repeating: [], count: last + 1)
        var labels = [[String]](repeating: [], count: last + 1)
        for key in side where key.row >= 0 && key.column >= 0 && key.column < 128 {
            while rects[key.row].count <= key.column {
                rects[key.row].append(NormalizedRect(x: 0, y: 0, width: 0, height: 0))
                labels[key.row].append("None")
            }
            rects[key.row][key.column] = key.rect
            labels[key.row][key.column] = key.label
        }
        return (rects, labels)
    }
    @MainActor
    func compile(right: Bool, base: ContentViewModel.Layout, size: CGSize) -> ContentViewModel.Layout {
        guard isValid else { return base }
        var layout = ContentViewModel.Layout(normalizedKeyRects: arrays(right: right).0,
            trackpadSize: size, allowHoldBindings: base.allowHoldBindings, isSteno: base.isSteno,
            stenoPointerMode: base.stenoPointerMode, stenoForceThreshold: base.stenoForceThreshold,
            stenoConnectionMode: base.stenoConnectionMode,
            stenoHapticTouch: base.stenoHapticTouch, stenoHapticRelease: base.stenoHapticRelease)
        for key in keys where key.right == right && key.edges.count == 4 {
            var rect = key.rect
            rect.x -= key.edges[0]; rect.y -= key.edges[1]
            rect.width += key.edges[0] + key.edges[2]; rect.height += key.edges[1] + key.edges[3]
            layout.authoredDisplayRects[key.rect] = rect
        }
        return layout
    }

    func expandedGroups(_ ids: Set<UUID>) -> Set<UUID> {
        let selected = keys.filter { ids.contains($0.id) }
        return Set(keys.filter { key in
            ids.contains(key.id) || selected.contains { $0.right == key.right && $0.group != nil && $0.group == key.group }
        }.map(\.id))
    }

    func editorHit(at normalized: CGPoint, right: Bool, pad: CGSize) -> UUID? {
        let point = CGPoint(x: normalized.x*pad.width,y: normalized.y*pad.height)
        var best: (UUID, CGFloat, CGFloat)?
        for key in keys where key.right == right {
            let rect = key.displayRect
            let geometry = KeyHitGeometry(normalizedRect: rect,size: pad)
            guard geometry.contains(point) else { continue }
            let depth = geometry.distanceToEdge(from: point), area = rect.width*rect.height
            if best == nil || depth > best!.1 || (abs(depth-best!.1) < 0.000001 && area < best!.2) { best = (key.id,depth,area) }
        }
        return best?.0
    }

    func editorMarquee(_ normalized: CGRect, right: Bool, groups: Bool, pad: CGSize) -> Set<UUID> {
        let box = CGRect(x: normalized.minX*pad.width,y: normalized.minY*pad.height,width: normalized.width*pad.width,height: normalized.height*pad.height)
        let ids = Set(keys.filter { $0.right == right && $0.displayRect.boundingRect(in: pad).intersects(box) }.map(\.id))
        return groups ? expandedGroups(ids) : ids
    }

    /// Pair once at editor entry. Saved pairs survive independent movement and reopening.
    /// Unequal templates keep unmatched keys independent; actions are never copied.
    mutating func inferMirrorPairs() {
        let left = keys.filter { !$0.right && $0.mirrorID == nil }
        let right = keys.filter { $0.right && $0.mirrorID == nil }
        var candidates: [(UUID, UUID, CGFloat)] = []
        for l in left { for r in right {
            let x = abs(1-l.rect.centerX-r.rect.centerX), y = abs(l.rect.centerY-r.rect.centerY)
            let widthRatio = l.rect.width/max(0.0001,r.rect.width)
            let heightRatio = l.rect.height/max(0.0001,r.rect.height)
            guard x < 0.25, y < 0.2, (0.33...3).contains(widthRatio), (0.33...3).contains(heightRatio) else { continue }
            let size = abs(l.rect.width-r.rect.width)+abs(l.rect.height-r.rect.height)
            candidates.append((l.id,r.id,x*x+y*y+size*size*0.1))
        } }
        candidates.sort { $0.2 < $1.2 }
        let indices = Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($0.element.id, $0.offset) })
        for (l,r,_) in candidates {
            guard let i = indices[l], let j = indices[r], keys[i].mirrorID == nil, keys[j].mirrorID == nil else { continue }
            keys[i].mirrorID = r; keys[j].mirrorID = l
        }
    }

    func pairedSelection(_ ids: Set<UUID>) -> Set<UUID> {
        ids.union(keys.filter { ids.contains($0.id) }.compactMap(\.mirrorID))
    }

    /// Replay the source's geometry delta with horizontal reflection. Existing per-hand
    /// offsets, dimensions, labels and binding addresses remain independent.
    mutating func mirrorGeometryChanges(from before: Self, sources: Set<UUID>) {
        let oldByID = Dictionary(uniqueKeysWithValues: before.keys.map { ($0.id,$0) })
        let indices = Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($0.element.id,$0.offset) })
        let edits = keys.filter { sources.contains($0.id) }
        for edited in edits {
            guard let old = oldByID[edited.id], let partnerID = old.mirrorID,
                  !sources.contains(partnerID), let partner = oldByID[partnerID], let i = indices[partnerID] else { continue }
            guard edited.rect != old.rect || edited.edges != old.edges else { continue }
            let a = old.rect, b = edited.rect
            var r = partner.rect
            let newWidth = min(1, max(0.005,r.width+b.width-a.width))
            r.x -= (b.x-a.x)+(newWidth-r.width)
            r.y += b.y-a.y
            r.width = newWidth; r.height = min(1,max(0.005,r.height+b.height-a.height))
            r.rotationDegrees = (r.rotationDegrees-b.rotationDegrees+a.rotationDegrees).truncatingRemainder(dividingBy:360)
            keys[i].rect = r
            if old.edges.count == 4 && edited.edges.count == 4 && partner.edges.count == 4 {
                for (target,source) in [(0,2),(1,1),(2,0),(3,3)] {
                    keys[i].edges[target] = partner.edges[target]+edited.edges[source]-old.edges[source]
                }
            }
        }
    }

    @discardableResult
    mutating func addMirrored(right: Bool, label: String = "None", rect: NormalizedRect = NormalizedRect(x: 0.4,y: 0.4,width: 0.08,height: 0.18), group: UUID? = nil, oppositeGroup: UUID? = nil) -> UUID {
        let source = add(right: right,label: label,rect: rect,group: group)
        var reflected = rect; reflected.x = 1-rect.x-rect.width; reflected.rotationDegrees = -rect.rotationDegrees
        let target = add(right: !right,label: label,rect: reflected,group: oppositeGroup)
        let i = keys.count-2, j = keys.count-1
        keys[i].mirrorID = target; keys[j].mirrorID = source
        return source
    }

    /// Structural edits and layer assignments are reconciled together on Apply.
    func updatedMappings(_ mappings: LayeredKeyMappings) -> LayeredKeyMappings {
        var result = mappings
        func address(_ key: Key, row: Int, column: Int) -> String {
            GridKeyPosition(side: key.right ? .right : .left, row: row, column: column).storageKey
        }
        for key in keys {
            guard let row = key.copySourceRow, let column = key.copySourceColumn else { continue }
            let source = address(key, row: row, column: column)
            let target = address(key, row: key.row, column: key.column)
            for layer in Array(result.keys) {
                if let mapping = result[layer]?[source] { result[layer]?[target] = mapping }
            }
        }
        let surviving = Set(keys.map { address($0, row: $0.row, column: $0.column) })
        return result.mapValues { $0.filter { surviving.contains($0.key) } }
    }

    /// Presentation follows the active hand/layer mapping without changing fallback labels
    /// or assignments. Resolve staged duplicate provenance just as Apply does.
    func editorLegends(mappings: [String:KeyMapping]) -> [UUID:String] {
        let staged = updatedMappings([0:mappings])[0] ?? [:]
        return Dictionary(uniqueKeysWithValues:keys.map { key in
            let address = GridKeyPosition(side:key.right ? .right:.left,row:key.row,column:key.column).storageKey
            let label = staged[address]?.primary.displayText ?? KeyActionCatalog.action(for:key.label)?.displayText ?? key.label
            return (key.id,label)
        })
    }

    struct SelectionFrame: Equatable {
        let rect: NormalizedRect
        let allowsIndependentAxes: Bool
    }

    /// Use the keys' shared axes when possible. Mixed rotations use a world-axis
    /// frame and uniform scaling, since rotated rectangles cannot represent shear.
    func selectionFrame(_ ids: Set<UUID>, right: Bool, pad: CGSize) -> SelectionFrame? {
        guard pad.width > 0, pad.height > 0 else { return nil }
        let selected = keys.filter { ids.contains($0.id) && $0.right == right }
        guard let first = selected.first else { return nil }
        let shared = selected.allSatisfy {
            let delta = ($0.rect.rotationDegrees-first.rect.rotationDegrees).truncatingRemainder(dividingBy:180)
            return abs(delta) < 0.00001 || abs(abs(delta)-180) < 0.00001
        }
        let angle = shared ? first.rect.rotationDegrees : 0
        let a: CGFloat = CGFloat(angle * .pi/180)
        let c: CGFloat = cos(a), sn: CGFloat = sin(a)
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for key in selected {
            for point in key.rect.corners(in:pad) {
                let x: CGFloat = point.x*c+point.y*sn
                let y: CGFloat = (-point.x)*sn+point.y*c
                minX = min(minX,x); maxX = max(maxX,x)
                minY = min(minY,y); maxY = max(maxY,y)
            }
        }
        guard minX.isFinite, maxX.isFinite, minY.isFinite, maxY.isFinite else { return nil }
        let localCenter = CGPoint(x:(minX+maxX)/2,y:(minY+maxY)/2)
        let center = CGPoint(x:localCenter.x*c-localCenter.y*sn,y:localCenter.x*sn+localCenter.y*c)
        let width = (maxX-minX)/pad.width, height = (maxY-minY)/pad.height
        return SelectionFrame(rect:NormalizedRect(x:center.x/pad.width-width/2,y:center.y/pad.height-height/2,
            width:width,height:height,rotationDegrees:angle),allowsIndependentAxes:shared)
    }

    func selectionAllowsIndependentAxes(_ ids: Set<UUID>, pad: CGSize) -> Bool {
        [false,true].allSatisfy { selectionFrame(ids,right:$0,pad:pad)?.allowsIndependentAxes ?? true }
    }

    /// Transform each pad in its own coordinate system. A member handle fixes that
    /// member's opposite corner; the shared frame fixes the selection's opposite corner.
    /// Scale positions and key sizes together, retaining rotations, identities, actions,
    /// groups, counterpart links and the fixed STENO overlap allowances.
    @discardableResult
    mutating func resizeSelection(_ ids: Set<UUID>, scaleX: CGFloat, scaleY: CGFloat,
                                 pad: CGSize, referenceKey: UUID? = nil) -> Bool {
        guard scaleX.isFinite, scaleY.isFinite, scaleX > 0, scaleY > 0,
              pad.width > 0, pad.height > 0 else { return false }
        let selected = keys.filter { ids.contains($0.id) }
        guard !selected.isEmpty else { return false }
        guard abs(scaleX-1) > 1e-12 || abs(scaleY-1) > 1e-12 else { return false }
        let uniform = abs(scaleX-scaleY) < 0.0000001
        guard uniform || selectionAllowsIndependentAxes(ids,pad:pad) else { return false }
        // Match the editor's existing per-key size limits; clamp one shared factor
        // rather than clamping keys separately and distorting spacing.
        let minX = selected.map { 0.005/$0.rect.width }.max()!, minY = selected.map { 0.005/$0.rect.height }.max()!
        let maxX = selected.map { 1/$0.rect.width }.min()!, maxY = selected.map { 1/$0.rect.height }.min()!
        let sx: CGFloat, sy: CGFloat
        if uniform {
            sx = min(min(maxX,maxY),max(max(minX,minY),scaleX)); sy = sx
        } else {
            sx = min(maxX,max(minX,scaleX)); sy = min(maxY,max(minY,scaleY))
        }
        let before = self
        let indices = Dictionary(uniqueKeysWithValues:keys.enumerated().map { ($0.element.id,$0.offset) })
        for side in [false,true] {
            let members = selected.filter { $0.right == side }
            guard let frame = before.selectionFrame(ids,right:side,pad:pad) else { continue }
            let reference = members.first { $0.id == referenceKey }
            let axes = reference?.rect ?? frame.rect
            guard let anchor = axes.corners(in:pad).first else { continue }
            let a = CGFloat(axes.rotationDegrees * .pi/180), c = cos(a), sn = sin(a)
            for key in members {
                guard let i = indices[key.id] else { continue }
                let dx = key.rect.centerX*pad.width-anchor.x, dy = key.rect.centerY*pad.height-anchor.y
                let x = (dx*c+dy*sn)*sx, y = (-dx*sn+dy*c)*sy
                var r = key.rect
                r.width *= sx; r.height *= sy
                r.x = (anchor.x+x*c-y*sn)/pad.width-r.width/2
                r.y = (anchor.y+x*sn+y*c)/pad.height-r.height/2
                keys[i].rect = r
            }
        }
        return before != self
    }

    mutating func rotate(_ ids: Set<UUID>, degrees: Double, pad: CGSize) {
        guard degrees.isFinite, pad.width > 0, pad.height > 0 else { return }
        let selected = keys.filter { ids.contains($0.id) }
        guard !selected.isEmpty else { return }
        let cx = selected.map { $0.rect.centerX*pad.width }.reduce(0,+)/CGFloat(selected.count)
        let cy = selected.map { $0.rect.centerY*pad.height }.reduce(0,+)/CGFloat(selected.count)
        let angle = degrees * .pi/180
        for i in keys.indices where ids.contains(keys[i].id) {
            var r = keys[i].rect
            let x = r.centerX*pad.width-cx, y = r.centerY*pad.height-cy
            r.x = (cx+x*cos(angle)-y*sin(angle))/pad.width-r.width/2
            r.y = (cy+x*sin(angle)+y*cos(angle))/pad.height-r.height/2
            r.rotationDegrees = (r.rotationDegrees+degrees).truncatingRemainder(dividingBy: 360)
            keys[i].rect = r
        }
    }

    mutating func translate(_ ids: Set<UUID>, dx: CGFloat, dy: CGFloat) {
        guard dx.isFinite, dy.isFinite else { return }
        let selected = keys.filter { ids.contains($0.id) }
        guard !selected.isEmpty else { return }
        let minX = selected.map { $0.rect.x }.min()!, maxX = selected.map { $0.rect.x+$0.rect.width }.max()!
        let minY = selected.map { $0.rect.y }.min()!, maxY = selected.map { $0.rect.y+$0.rect.height }.max()!
        let x = min(max(dx, -minX), 1-maxX), y = min(max(dy, -minY), 1-maxY)
        for index in keys.indices where ids.contains(keys[index].id) {
            keys[index].rect.x += x; keys[index].rect.y += y
        }
    }
    @discardableResult
    mutating func add(right: Bool, label: String = "None", rect: NormalizedRect = NormalizedRect(x: 0.4, y: 0.4, width: 0.08, height: 0.18), group: UUID? = nil) -> UUID {
        let key = Key(right: right, row: nextRow, column: 0, label: label, rect: rect, group: group)
        nextRow += 1; keys.append(key); return key.id
    }
    mutating func remove(_ ids: Set<UUID>) {
        keys.removeAll { ids.contains($0.id) }
        let remaining = Set(keys.map(\.id))
        for i in keys.indices where keys[i].mirrorID.map({ !remaining.contains($0) }) == true { keys[i].mirrorID = nil }
        groups.removeAll { group in !keys.contains { $0.group == group.id } }
    }
    mutating func duplicate(_ ids: Set<UUID>, mirrorOffset: Bool = false, sourceRight: Bool = true) -> Set<UUID> {
        var newIDs = Set<UUID>(), groupMap: [UUID: UUID] = [:], keyMap: [UUID: UUID] = [:]
        for key in keys.filter({ ids.contains($0.id) }) {
            var copy = key; copy.id = UUID(); keyMap[key.id] = copy.id; copy.copySourceRow = key.row; copy.copySourceColumn = key.column
            copy.row = nextRow; copy.column = 0; nextRow += 1
            if let group = key.group {
                if groupMap[group] == nil {
                    let value = Group(name: (groups.first { $0.id == group }?.name ?? "Group") + " copy")
                    groups.append(value); groupMap[group] = value.id
                }
                copy.group = groupMap[group]
            }
            keys.append(copy); newIDs.insert(copy.id)
        }
        for i in keys.indices where newIDs.contains(keys[i].id) {
            keys[i].mirrorID = keys[i].mirrorID.flatMap { keyMap[$0] }
        }
        if mirrorOffset {
            let before = self
            let sources = Set(keys.filter { newIDs.contains($0.id) && $0.right == sourceRight }.map(\.id))
            translate(sources, dx: 0.02, dy: 0.02)
            mirrorGeometryChanges(from: before, sources: sources)
        } else { translate(newIDs, dx: 0.02, dy: 0.02) }
        return newIDs
    }
}

/// Bounded edit history contains documents only; it never references live input state.
struct LayoutDocumentHistory {
    private var past: [LayoutDocument] = []
    private var future: [LayoutDocument] = []
    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }
    mutating func record(_ previous: LayoutDocument) {
        past.append(previous)
        if past.count > 100 { past.removeFirst(past.count-100) }
        future.removeAll()
    }
    mutating func undo(_ current: LayoutDocument) -> LayoutDocument? {
        guard let previous = past.popLast() else { return nil }
        future.append(current); return previous
    }
    mutating func redo(_ current: LayoutDocument) -> LayoutDocument? {
        guard let next = future.popLast() else { return nil }
        past.append(current); return next
    }
}

enum LayoutDocumentStorage {
    static func decode(_ data: Data) -> [String: LayoutDocument] {
        ((try? JSONDecoder().decode([String: LayoutDocument].self, from: data)) ?? [:])
            .filter { $0.value.isValid }
    }
}
