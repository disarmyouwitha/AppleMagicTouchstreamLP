import AppKit
import OpenMultitouchSupport
import SwiftUI

struct TrackpadSurfaceLabel: Sendable, Equatable {
    var primary: String
    var hold: String?
}

struct TrackpadSurfaceKeySelection: Sendable, Equatable {
    var row: Int
    var column: Int
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
    var leftTouches: [OMSTouchData]
    var rightTouches: [OMSTouchData]
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
            leftTouches: [],
            rightTouches: [],
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
            touches: snapshot.leftTouches,
            trackpadSize: snapshot.trackpadSize,
            selectedColumn: snapshot.selectedColumn,
            selectedKey: snapshot.selectedLeftKey,
            selectedButtonID: snapshot.selectedLeftButtonID
        )
        drawTrackpadDynamicSide(
            origin: rightOrigin,
            layout: snapshot.rightLayout,
            customButtons: snapshot.rightCustomButtons,
            touches: snapshot.rightTouches,
            trackpadSize: snapshot.trackpadSize,
            selectedColumn: snapshot.selectedColumn,
            selectedKey: snapshot.selectedRightKey,
            selectedButtonID: snapshot.selectedRightButtonID
        )
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

    private func viewSize(for snapshot: TrackpadSurfaceSnapshot) -> CGSize {
        CGSize(
            width: (snapshot.trackpadSize.width * 2) + snapshot.spacing,
            height: snapshot.trackpadSize.height
        )
    }

    func makeNSView(context: Context) -> TrackpadSurfaceView {
        let view = TrackpadSurfaceView(frame: CGRect(origin: .zero, size: viewSize(for: snapshot)))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.snapshot = snapshot
        return view
    }

    func updateNSView(_ nsView: TrackpadSurfaceView, context: Context) {
        let size = viewSize(for: snapshot)
        if nsView.frame.size != size {
            nsView.setFrameSize(size)
        }
        nsView.snapshot = snapshot
    }
}
