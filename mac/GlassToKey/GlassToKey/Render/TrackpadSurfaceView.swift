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
    var visualsEnabled: Bool
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
            visualsEnabled: false,
            selectedColumn: nil,
            selectedLeftKey: nil,
            selectedRightKey: nil,
            selectedLeftButtonID: nil,
            selectedRightButtonID: nil
        )
    }
}

final class TrackpadSurfaceView: NSView {
    var snapshot: TrackpadSurfaceSnapshot = .empty {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard snapshot.trackpadSize.width > 0, snapshot.trackpadSize.height > 0 else { return }

        let leftOrigin = CGPoint.zero
        let rightOrigin = CGPoint(x: snapshot.trackpadSize.width + snapshot.spacing, y: 0)

        drawTrackpadSide(
            origin: leftOrigin,
            layout: snapshot.leftLayout,
            labels: snapshot.leftLabels,
            customButtons: snapshot.leftCustomButtons,
            touches: snapshot.leftTouches,
            selectedColumn: snapshot.selectedColumn,
            selectedKey: snapshot.selectedLeftKey,
            selectedButtonID: snapshot.selectedLeftButtonID
        )
        drawTrackpadSide(
            origin: rightOrigin,
            layout: snapshot.rightLayout,
            labels: snapshot.rightLabels,
            customButtons: snapshot.rightCustomButtons,
            touches: snapshot.rightTouches,
            selectedColumn: snapshot.selectedColumn,
            selectedKey: snapshot.selectedRightKey,
            selectedButtonID: snapshot.selectedRightButtonID
        )
    }

    private func drawTrackpadSide(
        origin: CGPoint,
        layout: ContentViewModel.Layout,
        labels: [[TrackpadSurfaceLabel]],
        customButtons: [CustomButton],
        touches: [OMSTouchData],
        selectedColumn: Int?,
        selectedKey: TrackpadSurfaceKeySelection?,
        selectedButtonID: UUID?
    ) {
        let trackpadRect = CGRect(origin: origin, size: snapshot.trackpadSize)
        let borderPath = NSBezierPath(roundedRect: trackpadRect, xRadius: 6, yRadius: 6)
        NSColor.secondaryLabelColor.withAlphaComponent(0.6).setStroke()
        borderPath.lineWidth = 1
        borderPath.stroke()

        guard snapshot.showDetailed else { return }

        drawSensorGrid(origin: origin)
        drawKeyGrid(layout.keyRects, origin: origin)
        drawCustomButtons(customButtons, origin: origin)
        drawGridLabels(labels, keyRects: layout.keyRects, origin: origin)
        drawKeySelection(
            keyRects: layout.keyRects,
            selectedColumn: selectedColumn,
            selectedKey: selectedKey,
            origin: origin
        )
        drawButtonSelection(customButtons, selectedButtonID: selectedButtonID, origin: origin)

        guard snapshot.visualsEnabled else { return }
        drawTouches(touches, origin: origin)
    }

    private func drawSensorGrid(origin: CGPoint) {
        let columns = 30
        let rows = 22
        let strokeColor = NSColor.secondaryLabelColor.withAlphaComponent(0.2)
        strokeColor.setStroke()
        let lineWidth: CGFloat = 0.5

        let columnWidth = snapshot.trackpadSize.width / CGFloat(columns)
        let rowHeight = snapshot.trackpadSize.height / CGFloat(rows)
        for col in 0...columns {
            let x = origin.x + (CGFloat(col) * columnWidth)
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.move(to: CGPoint(x: x, y: origin.y))
            path.line(to: CGPoint(x: x, y: origin.y + snapshot.trackpadSize.height))
            path.stroke()
        }

        for row in 0...rows {
            let y = origin.y + (CGFloat(row) * rowHeight)
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.move(to: CGPoint(x: origin.x, y: y))
            path.line(to: CGPoint(x: origin.x + snapshot.trackpadSize.width, y: y))
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

    private func drawCustomButtons(_ buttons: [CustomButton], origin: CGPoint) {
        for button in buttons {
            let rect = button.rect.rect(in: snapshot.trackpadSize).offsetBy(dx: origin.x, dy: origin.y)
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
        origin: CGPoint
    ) {
        guard let selectedButtonID,
              let button = buttons.first(where: { $0.id == selectedButtonID }) else { return }
        let rect = button.rect.rect(in: snapshot.trackpadSize).offsetBy(dx: origin.x, dy: origin.y)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    private func drawTouches(_ touches: [OMSTouchData], origin: CGPoint) {
        for touch in touches {
            let centerX = origin.x + CGFloat(touch.position.x) * snapshot.trackpadSize.width
            let centerY = origin.y + (1.0 - CGFloat(touch.position.y)) * snapshot.trackpadSize.height
            let unit = snapshot.trackpadSize.width / 100.0
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
            let alpha = min(max(CGFloat(touch.total), 0.05), 1.0)
            NSColor.labelColor.withAlphaComponent(alpha).setFill()
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
