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
        var copySourceRow: Int? = nil
        var copySourceColumn: Int? = nil
        // Explicit visual extensions preserve the accepted STENO overlap drawing.
        var edges: [CGFloat] = [0, 0, 0, 0] // left, top, right, bottom
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
        return keys.allSatisfy { key in
            let r = key.rect
            return key.row >= 0 && key.row < nextRow && key.column >= 0 && key.column < 128 &&
                slots.insert("\(key.right):\(key.row):\(key.column)").inserted &&
                [r.x,r.y,r.width,r.height,CGFloat(r.rotationDegrees)].allSatisfy(\.isFinite) &&
                r.width > 0 && r.width <= 2 && r.height > 0 && r.height <= 2 &&
                abs(r.x) <= 2 && abs(r.y) <= 2 && key.edges.count == 4 &&
                key.edges.allSatisfy { $0.isFinite && abs($0) < 1 } &&
                (key.group == nil || groupIDs.contains(key.group!))
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
        groups.removeAll { group in !keys.contains { $0.group == group.id } }
    }
    mutating func duplicate(_ ids: Set<UUID>) -> Set<UUID> {
        var newIDs = Set<UUID>(), groupMap: [UUID: UUID] = [:]
        for key in keys.filter({ ids.contains($0.id) }) {
            var copy = key; copy.id = UUID(); copy.copySourceRow = key.row; copy.copySourceColumn = key.column
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
        translate(newIDs, dx: 0.02, dy: 0.02)
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
