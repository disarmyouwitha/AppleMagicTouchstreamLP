import AppKit
import OpenMultitouchSupport
import SwiftUI
import QuartzCore

struct TrackpadSurfaceLabel: Sendable, Equatable {
    var primary: String
    var hold: String?
}

struct TrackpadSurfaceKeySelection: Sendable, Equatable {
    var row: Int
    var column: Int
}

enum TrackpadSurfaceSelectionTarget: Equatable {
    case button(id: UUID)
    case key(row: Int, column: Int, label: String)
    case column(index: Int)
    case none
}

struct TrackpadSurfaceSelectionEvent: Equatable {
    var side: TrackpadSide
    var target: TrackpadSurfaceSelectionTarget
}

struct TrackpadSurfaceSnapshot {
    var trackpadSize: CGSize
    var spacing: CGFloat
    var showDetailed: Bool
    var leftLayout: ContentViewModel.Layout
    var rightLayout: ContentViewModel.Layout
    var leftLabels: [[TrackpadSurfaceLabel]]
    var rightLabels: [[TrackpadSurfaceLabel]]
    var leftCustomButtons: [CustomButton]
    var rightCustomButtons: [CustomButton]
    var selectedColumn: Int?
    var selectedLeftKey: TrackpadSurfaceKeySelection?
    var selectedRightKey: TrackpadSurfaceKeySelection?
    var selectedLeftButtonID: UUID?
    var selectedRightButtonID: UUID?
}

extension TrackpadSurfaceSnapshot {
    static var empty: TrackpadSurfaceSnapshot {
        TrackpadSurfaceSnapshot(
            trackpadSize: .zero,
            spacing: 0,
            showDetailed: false,
            leftLayout: ContentViewModel.Layout(keyRects: []),
            rightLayout: ContentViewModel.Layout(keyRects: []),
            leftLabels: [],
            rightLabels: [],
            leftCustomButtons: [],
            rightCustomButtons: [],
            selectedColumn: nil,
            selectedLeftKey: nil,
            selectedRightKey: nil,
            selectedLeftButtonID: nil,
            selectedRightButtonID: nil
        )
    }
}

private struct TrackpadSurfaceStaticRenderInput: Equatable {
    var trackpadSize: CGSize
    var spacing: CGFloat
    var showDetailed: Bool
    var leftKeyRects: [[CGRect]]
    var rightKeyRects: [[CGRect]]
    var leftAllowHoldBindings: Bool
    var rightAllowHoldBindings: Bool
    var leftLabels: [[TrackpadSurfaceLabel]]
    var rightLabels: [[TrackpadSurfaceLabel]]
    var leftCustomButtons: [CustomButton]
    var rightCustomButtons: [CustomButton]

    init(snapshot: TrackpadSurfaceSnapshot) {
        trackpadSize = snapshot.trackpadSize
        spacing = snapshot.spacing
        showDetailed = snapshot.showDetailed
        leftKeyRects = snapshot.leftLayout.keyRects
        rightKeyRects = snapshot.rightLayout.keyRects
        leftAllowHoldBindings = snapshot.leftLayout.allowHoldBindings
        rightAllowHoldBindings = snapshot.rightLayout.allowHoldBindings
        leftLabels = snapshot.leftLabels
        rightLabels = snapshot.rightLabels
        leftCustomButtons = snapshot.leftCustomButtons
        rightCustomButtons = snapshot.rightCustomButtons
    }
}

final class TrackpadSurfaceView: NSView {
    private var cachedStaticRenderInput: TrackpadSurfaceStaticRenderInput?
    private var cachedStaticImage: NSImage?
    private var leftTouches: [OMSTouchData] = []
    private var rightTouches: [OMSTouchData] = []

    var editModeEnabled = false
    var selectionHandler: ((TrackpadSurfaceSelectionEvent) -> Void)?

    var snapshot: TrackpadSurfaceSnapshot = .empty {
        didSet {
            let staticRenderInput = TrackpadSurfaceStaticRenderInput(snapshot: snapshot)
            if cachedStaticRenderInput != staticRenderInput {
                cachedStaticRenderInput = staticRenderInput
                cachedStaticImage = nil
            }
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        true
    }

    func updateTouches(left: [OMSTouchData], right: [OMSTouchData]) {
        leftTouches = left
        rightTouches = right
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard snapshot.trackpadSize.width > 0, snapshot.trackpadSize.height > 0 else { return }

        let staticRenderInput = TrackpadSurfaceStaticRenderInput(snapshot: snapshot)
        if cachedStaticRenderInput != staticRenderInput {
            cachedStaticRenderInput = staticRenderInput
            cachedStaticImage = nil
        }
        if cachedStaticImage == nil {
            cachedStaticImage = renderStaticImage(using: staticRenderInput)
        }
        let canvasRect = CGRect(
            x: 0,
            y: 0,
            width: (snapshot.trackpadSize.width * 2) + snapshot.spacing,
            height: snapshot.trackpadSize.height
        )
        if let cachedStaticImage {
            let sourceRect = CGRect(origin: .zero, size: cachedStaticImage.size)
            cachedStaticImage.draw(
                in: canvasRect,
                from: sourceRect,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
        }

        guard snapshot.showDetailed else { return }

        let leftOrigin = CGPoint.zero
        let rightOrigin = CGPoint(x: snapshot.trackpadSize.width + snapshot.spacing, y: 0)

        drawTrackpadDynamicSide(
            origin: leftOrigin,
            layout: snapshot.leftLayout,
            customButtons: snapshot.leftCustomButtons,
            touches: leftTouches,
            trackpadSize: snapshot.trackpadSize,
            selectedColumn: snapshot.selectedColumn,
            selectedKey: snapshot.selectedLeftKey,
            selectedButtonID: snapshot.selectedLeftButtonID
        )
        drawTrackpadDynamicSide(
            origin: rightOrigin,
            layout: snapshot.rightLayout,
            customButtons: snapshot.rightCustomButtons,
            touches: rightTouches,
            trackpadSize: snapshot.trackpadSize,
            selectedColumn: snapshot.selectedColumn,
            selectedKey: snapshot.selectedRightKey,
            selectedButtonID: snapshot.selectedRightButtonID
        )
    }

    override func mouseDown(with event: NSEvent) {
        guard editModeEnabled else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let selectionEvent = selectionEvent(at: point) else { return }
        selectionHandler?(selectionEvent)
    }

    private func renderStaticImage(using input: TrackpadSurfaceStaticRenderInput) -> NSImage {
        let canvasSize = CGSize(
            width: (input.trackpadSize.width * 2) + input.spacing,
            height: input.trackpadSize.height
        )
        let image = NSImage(size: canvasSize)
        image.lockFocusFlipped(true)
        defer { image.unlockFocus() }

        let leftOrigin = CGPoint.zero
        let rightOrigin = CGPoint(x: input.trackpadSize.width + input.spacing, y: 0)

        drawTrackpadStaticSide(
            origin: leftOrigin,
            keyRects: input.leftKeyRects,
            labels: input.leftLabels,
            customButtons: input.leftCustomButtons,
            showDetailed: input.showDetailed,
            trackpadSize: input.trackpadSize
        )
        drawTrackpadStaticSide(
            origin: rightOrigin,
            keyRects: input.rightKeyRects,
            labels: input.rightLabels,
            customButtons: input.rightCustomButtons,
            showDetailed: input.showDetailed,
            trackpadSize: input.trackpadSize
        )
        return image
    }

    private func drawTrackpadStaticSide(
        origin: CGPoint,
        keyRects: [[CGRect]],
        labels: [[TrackpadSurfaceLabel]],
        customButtons: [CustomButton],
        showDetailed: Bool,
        trackpadSize: CGSize
    ) {
        let trackpadRect = CGRect(origin: origin, size: trackpadSize)
        let borderPath = NSBezierPath(roundedRect: trackpadRect, xRadius: 6, yRadius: 6)
        NSColor.secondaryLabelColor.withAlphaComponent(0.6).setStroke()
        borderPath.lineWidth = 1
        borderPath.stroke()

        guard showDetailed else { return }

        drawSensorGrid(origin: origin, trackpadSize: trackpadSize)
        drawKeyGrid(keyRects, origin: origin)
        drawCustomButtons(customButtons, origin: origin, trackpadSize: trackpadSize)
        drawGridLabels(labels, keyRects: keyRects, origin: origin)
    }

    private func drawTrackpadDynamicSide(
        origin: CGPoint,
        layout: ContentViewModel.Layout,
        customButtons: [CustomButton],
        touches: [OMSTouchData],
        trackpadSize: CGSize,
        selectedColumn: Int?,
        selectedKey: TrackpadSurfaceKeySelection?,
        selectedButtonID: UUID?
    ) {
        drawKeySelection(
            keyRects: layout.keyRects,
            selectedColumn: selectedColumn,
            selectedKey: selectedKey,
            origin: origin
        )
        drawButtonSelection(
            customButtons,
            selectedButtonID: selectedButtonID,
            origin: origin,
            trackpadSize: trackpadSize
        )
        drawTouches(touches, origin: origin, trackpadSize: trackpadSize)
    }

    private func selectionEvent(at point: CGPoint) -> TrackpadSurfaceSelectionEvent? {
        guard let hit = sideHit(at: point) else { return nil }
        let side = hit.side
        let localPoint = hit.localPoint
        let layout = hit.layout
        let labels = hit.labels
        let customButtons = hit.customButtons
        let trackpadSize = snapshot.trackpadSize

        if let selectedButton = customButtons.last(where: { button in
            button.rect.rect(in: trackpadSize).contains(localPoint)
        }) {
            return TrackpadSurfaceSelectionEvent(
                side: side,
                target: .button(id: selectedButton.id)
            )
        }

        if let selectedKey = gridKey(
            at: localPoint,
            keyRects: layout.keyRects,
            labels: labels
        ) {
            return TrackpadSurfaceSelectionEvent(
                side: side,
                target: .key(
                    row: selectedKey.row,
                    column: selectedKey.column,
                    label: selectedKey.label
                )
            )
        }

        let columnRects = columnRects(
            for: layout.keyRects,
            trackpadSize: trackpadSize
        )
        if let index = columnIndex(
            for: localPoint,
            columnRects: columnRects,
            trackpadWidth: trackpadSize.width
        ) {
            return TrackpadSurfaceSelectionEvent(
                side: side,
                target: .column(index: index)
            )
        }
        return TrackpadSurfaceSelectionEvent(
            side: side,
            target: .none
        )
    }

    private struct SurfaceSideHit {
        var side: TrackpadSide
        var localPoint: CGPoint
        var layout: ContentViewModel.Layout
        var labels: [[TrackpadSurfaceLabel]]
        var customButtons: [CustomButton]
    }

    private struct SurfaceKeyHit {
        var row: Int
        var column: Int
        var label: String
    }

    private func sideHit(at point: CGPoint) -> SurfaceSideHit? {
        let width = snapshot.trackpadSize.width
        let height = snapshot.trackpadSize.height
        guard width > 0, height > 0 else { return nil }
        guard point.y >= 0, point.y <= height else { return nil }

        if point.x >= 0, point.x <= width {
            return SurfaceSideHit(
                side: .left,
                localPoint: point,
                layout: snapshot.leftLayout,
                labels: snapshot.leftLabels,
                customButtons: snapshot.leftCustomButtons
            )
        }

        let rightOriginX = width + snapshot.spacing
        if point.x >= rightOriginX, point.x <= rightOriginX + width {
            return SurfaceSideHit(
                side: .right,
                localPoint: CGPoint(x: point.x - rightOriginX, y: point.y),
                layout: snapshot.rightLayout,
                labels: snapshot.rightLabels,
                customButtons: snapshot.rightCustomButtons
            )
        }

        return nil
    }

    private func gridKey(
        at point: CGPoint,
        keyRects: [[CGRect]],
        labels: [[TrackpadSurfaceLabel]]
    ) -> SurfaceKeyHit? {
        for rowIndex in keyRects.indices {
            guard rowIndex < labels.count else { continue }
            for columnIndex in keyRects[rowIndex].indices {
                guard columnIndex < labels[rowIndex].count else { continue }
                if keyRects[rowIndex][columnIndex].contains(point) {
                    return SurfaceKeyHit(
                        row: rowIndex,
                        column: columnIndex,
                        label: labels[rowIndex][columnIndex].primary
                    )
                }
            }
        }
        return nil
    }

    private func columnRects(
        for keyRects: [[CGRect]],
        trackpadSize: CGSize
    ) -> [CGRect] {
        let columnCount = keyRects.map { $0.count }.max() ?? 0
        guard columnCount > 0 else { return [] }
        var rects = Array(repeating: CGRect.null, count: columnCount)
        for row in keyRects {
            for col in 0..<row.count {
                rects[col] = rects[col].union(row[col])
            }
        }

        let width = trackpadSize.width
        let height = trackpadSize.height
        let sortedIndices = rects.enumerated()
            .sorted { lhs, rhs in
                let lhsMid = lhs.element.isNull ? 0 : lhs.element.midX
                let rhsMid = rhs.element.isNull ? 0 : rhs.element.midX
                return lhsMid < rhsMid
            }
            .map(\.offset)

        var boundaries = Array(repeating: CGFloat.zero, count: columnCount + 1)
        boundaries[0] = 0
        for physicalIndex in 0..<max(0, sortedIndices.count - 1) {
            let current = rects[sortedIndices[physicalIndex]]
            let next = rects[sortedIndices[physicalIndex + 1]]
            let currentMid = current.isNull ? 0 : current.midX
            let nextMid = next.isNull ? width : next.midX
            boundaries[physicalIndex + 1] = (currentMid + nextMid) / 2.0
        }
        boundaries[columnCount] = width

        var expandedRects = rects
        for physicalIndex in 0..<sortedIndices.count {
            let index = sortedIndices[physicalIndex]
            let left = boundaries[physicalIndex]
            let right = boundaries[physicalIndex + 1]
            expandedRects[index] = CGRect(
                x: left,
                y: 0,
                width: max(0, right - left),
                height: height
            )
        }
        return expandedRects
    }

    private func columnIndex(
        for point: CGPoint,
        columnRects: [CGRect],
        trackpadWidth: CGFloat
    ) -> Int? {
        if let index = columnRects.firstIndex(where: { $0.contains(point) }) {
            return index
        }
        let columnCount = columnRects.count
        guard trackpadWidth > 0, columnCount > 0 else { return nil }
        let normalizedX = min(max(point.x / trackpadWidth, 0), 1)
        var index = Int(normalizedX * CGFloat(columnCount))
        if index == columnCount {
            index = columnCount - 1
        }
        return index
    }

    private func drawSensorGrid(origin: CGPoint, trackpadSize: CGSize) {
        let columns = 30
        let rows = 22
        let strokeColor = NSColor.secondaryLabelColor.withAlphaComponent(0.2)
        strokeColor.setStroke()
        let lineWidth: CGFloat = 0.5

        let columnWidth = trackpadSize.width / CGFloat(columns)
        let rowHeight = trackpadSize.height / CGFloat(rows)
        for col in 0...columns {
            let x = origin.x + (CGFloat(col) * columnWidth)
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.move(to: CGPoint(x: x, y: origin.y))
            path.line(to: CGPoint(x: x, y: origin.y + trackpadSize.height))
            path.stroke()
        }

        for row in 0...rows {
            let y = origin.y + (CGFloat(row) * rowHeight)
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.move(to: CGPoint(x: origin.x, y: y))
            path.line(to: CGPoint(x: origin.x + trackpadSize.width, y: y))
            path.stroke()
        }
    }

    private func drawKeyGrid(_ keyRects: [[CGRect]], origin: CGPoint) {
        NSColor.secondaryLabelColor.withAlphaComponent(0.6).setStroke()
        for row in keyRects {
            for rect in row {
                let translated = rect.offsetBy(dx: origin.x, dy: origin.y)
                let keyPath = NSBezierPath(roundedRect: translated, xRadius: 6, yRadius: 6)
                keyPath.lineWidth = 1
                keyPath.stroke()
            }
        }
    }

    private func drawCustomButtons(
        _ buttons: [CustomButton],
        origin: CGPoint,
        trackpadSize: CGSize
    ) {
        for button in buttons {
            let rect = button.rect.rect(in: trackpadSize).offsetBy(dx: origin.x, dy: origin.y)
            let buttonPath = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            NSColor.systemBlue.withAlphaComponent(0.12).setFill()
            buttonPath.fill()
            NSColor.secondaryLabelColor.withAlphaComponent(0.6).setStroke()
            buttonPath.lineWidth = 1
            buttonPath.stroke()

            let primaryYOffset: CGFloat = button.hold != nil ? -4 : 0
            drawCenteredText(
                button.action.displayText,
                in: rect,
                yOffset: primaryYOffset,
                font: .monospacedSystemFont(ofSize: 10, weight: .semibold),
                color: .secondaryLabelColor.withAlphaComponent(0.95)
            )
            if let holdLabel = button.hold?.label {
                drawCenteredText(
                    holdLabel,
                    in: rect,
                    yOffset: 6,
                    font: .monospacedSystemFont(ofSize: 8, weight: .semibold),
                    color: .secondaryLabelColor.withAlphaComponent(0.7)
                )
            }
        }
    }

    private func drawGridLabels(_ labels: [[TrackpadSurfaceLabel]], keyRects: [[CGRect]], origin: CGPoint) {
        for rowIndex in keyRects.indices {
            for columnIndex in keyRects[rowIndex].indices {
                guard rowIndex < labels.count, columnIndex < labels[rowIndex].count else { continue }
                let rect = keyRects[rowIndex][columnIndex].offsetBy(dx: origin.x, dy: origin.y)
                let label = labels[rowIndex][columnIndex]
                drawCenteredText(
                    label.primary,
                    in: rect,
                    yOffset: -4,
                    font: .monospacedSystemFont(ofSize: 10, weight: .semibold),
                    color: .secondaryLabelColor.withAlphaComponent(0.95)
                )
                if let hold = label.hold {
                    drawCenteredText(
                        hold,
                        in: rect,
                        yOffset: 6,
                        font: .monospacedSystemFont(ofSize: 8, weight: .semibold),
                        color: .secondaryLabelColor.withAlphaComponent(0.7)
                    )
                }
            }
        }
    }

    private func drawKeySelection(
        keyRects: [[CGRect]],
        selectedColumn: Int?,
        selectedKey: TrackpadSurfaceKeySelection?,
        origin: CGPoint
    ) {
        if let selectedColumn {
            for row in keyRects where row.indices.contains(selectedColumn) {
                let rect = row[selectedColumn].offsetBy(dx: origin.x, dy: origin.y)
                let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
                NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
                path.fill()
                NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
                path.lineWidth = 1.5
                path.stroke()
            }
        }

        if let selectedKey,
           keyRects.indices.contains(selectedKey.row),
           keyRects[selectedKey.row].indices.contains(selectedKey.column) {
            let rect = keyRects[selectedKey.row][selectedKey.column].offsetBy(dx: origin.x, dy: origin.y)
            let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
            path.fill()
            NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    private func drawButtonSelection(
        _ buttons: [CustomButton],
        selectedButtonID: UUID?,
        origin: CGPoint,
        trackpadSize: CGSize
    ) {
        guard let selectedButtonID,
              let button = buttons.first(where: { $0.id == selectedButtonID }) else { return }
        let rect = button.rect.rect(in: trackpadSize).offsetBy(dx: origin.x, dy: origin.y)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    private func drawTouches(_ touches: [OMSTouchData], origin: CGPoint, trackpadSize: CGSize) {
        for touch in touches {
            let centerX = origin.x + CGFloat(touch.position.x) * trackpadSize.width
            let centerY = origin.y + (1.0 - CGFloat(touch.position.y)) * trackpadSize.height
            let unit = trackpadSize.width / 100.0
            let width = max(2, CGFloat(touch.axis.major) * unit)
            let height = max(2, CGFloat(touch.axis.minor) * unit)
            let touchRect = CGRect(
                x: centerX - (width * 0.5),
                y: centerY - (height * 0.5),
                width: width,
                height: height
            )
            let path = NSBezierPath(ovalIn: touchRect)
            var transform = AffineTransform.identity
            transform.translate(x: centerX, y: centerY)
            transform.rotate(byRadians: CGFloat(-touch.angle))
            transform.translate(x: -centerX, y: -centerY)
            path.transform(using: transform)
            NSColor.labelColor.withAlphaComponent(0.95).setFill()
            path.fill()
        }
    }

    private func drawCenteredText(
        _ string: String,
        in rect: CGRect,
        yOffset: CGFloat,
        font: NSFont,
        color: NSColor
    ) {
        guard !string.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let attributed = NSAttributedString(string: string, attributes: attributes)
        let size = attributed.size()
        let point = CGPoint(
            x: rect.midX - (size.width * 0.5),
            y: rect.midY - (size.height * 0.5) + yOffset
        )
        attributed.draw(at: point)
    }
}

struct TrackpadSurfaceRepresentable: NSViewRepresentable {
    let snapshot: TrackpadSurfaceSnapshot
    let viewModel: ContentViewModel
    let editModeEnabled: Bool
    let selectionHandler: ((TrackpadSurfaceSelectionEvent) -> Void)?

    @MainActor
    final class Coordinator {
        private static let touchPollIntervalNanoseconds: UInt64 = 8_000_000
        private weak var surfaceView: TrackpadSurfaceView?
        private weak var viewModel: ContentViewModel?
        private var touchUpdateTask: Task<Void, Never>?
        private var lastTouchRevision: UInt64 = 0
        private var lastDisplayUpdateTime: TimeInterval = 0
        private var lastDisplayedHadTouches = false
        private var editModeEnabled = false

        deinit {
            touchUpdateTask?.cancel()
        }

        func attach(
            surfaceView: TrackpadSurfaceView,
            viewModel: ContentViewModel,
            editModeEnabled: Bool
        ) {
            self.surfaceView = surfaceView
            self.editModeEnabled = editModeEnabled
            let viewModelChanged = self.viewModel !== viewModel
            self.viewModel = viewModel
            if viewModelChanged || touchUpdateTask == nil {
                restartTouchUpdates()
            }
        }

        func detach() {
            touchUpdateTask?.cancel()
            touchUpdateTask = nil
            surfaceView = nil
            viewModel = nil
        }

        private func restartTouchUpdates() {
            touchUpdateTask?.cancel()
            touchUpdateTask = nil
            guard let viewModel else { return }
            touchUpdateTask = Task { [weak self] in
                guard let self else { return }
                self.refreshTouchSnapshot(using: viewModel, resetRevision: true)
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: Self.touchPollIntervalNanoseconds)
                    if Task.isCancelled {
                        break
                    }
                    self.refreshTouchSnapshot(using: viewModel, resetRevision: false)
                }
            }
        }

        private func refreshTouchSnapshot(
            using viewModel: ContentViewModel,
            resetRevision: Bool
        ) {
            let snapshot: ContentViewModel.TouchSnapshot
            if resetRevision {
                snapshot = viewModel.snapshotTouchData()
                lastTouchRevision = snapshot.revision
            } else if let updated = viewModel.snapshotTouchDataIfUpdated(since: lastTouchRevision) {
                snapshot = updated
                lastTouchRevision = updated.revision
            } else {
                return
            }

            let now = CACurrentMediaTime()
            if resetRevision || shouldUpdateDisplay(snapshot: snapshot, now: now) {
                surfaceView?.updateTouches(left: snapshot.left, right: snapshot.right)
                lastDisplayUpdateTime = now
                lastDisplayedHadTouches = !(snapshot.left.isEmpty && snapshot.right.isEmpty)
            }
        }

        private func shouldUpdateDisplay(
            snapshot: ContentViewModel.TouchSnapshot,
            now: TimeInterval
        ) -> Bool {
            let hasTouches = !(snapshot.left.isEmpty && snapshot.right.isEmpty)
            if hasTouches != lastDisplayedHadTouches {
                return true
            }
            let maxRefreshRate = 45.0
            let minimumInterval = 1.0 / maxRefreshRate
            return now - lastDisplayUpdateTime >= minimumInterval
        }
    }

    private func viewSize(for snapshot: TrackpadSurfaceSnapshot) -> CGSize {
        CGSize(
            width: (snapshot.trackpadSize.width * 2) + snapshot.spacing,
            height: snapshot.trackpadSize.height
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TrackpadSurfaceView {
        let view = TrackpadSurfaceView(frame: CGRect(origin: .zero, size: viewSize(for: snapshot)))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.snapshot = snapshot
        view.editModeEnabled = editModeEnabled
        view.selectionHandler = selectionHandler
        context.coordinator.attach(
            surfaceView: view,
            viewModel: viewModel,
            editModeEnabled: editModeEnabled
        )
        return view
    }

    func updateNSView(_ nsView: TrackpadSurfaceView, context: Context) {
        let size = viewSize(for: snapshot)
        if nsView.frame.size != size {
            nsView.setFrameSize(size)
        }
        nsView.snapshot = snapshot
        nsView.editModeEnabled = editModeEnabled
        nsView.selectionHandler = selectionHandler
        context.coordinator.attach(
            surfaceView: nsView,
            viewModel: viewModel,
            editModeEnabled: editModeEnabled
        )
    }

    static func dismantleNSView(
        _ nsView: TrackpadSurfaceView,
        coordinator: Coordinator
    ) {
        coordinator.detach()
    }
}
