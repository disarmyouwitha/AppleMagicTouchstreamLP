import AppKit
import OpenMultitouchSupport
import SwiftUI

struct TrackpadSurfaceSnapshot {
    var trackpadSize: CGSize
    var spacing: CGFloat
    var showDetailed: Bool
    var leftLayout: ContentViewModel.Layout
    var rightLayout: ContentViewModel.Layout
    var leftTouches: [OMSTouchData]
    var rightTouches: [OMSTouchData]
    var visualsEnabled: Bool
    var selectedColumn: Int?
}

extension TrackpadSurfaceSnapshot {
    static var empty: TrackpadSurfaceSnapshot {
        TrackpadSurfaceSnapshot(
            trackpadSize: .zero,
            spacing: 0,
            showDetailed: false,
            leftLayout: ContentViewModel.Layout(keyRects: []),
            rightLayout: ContentViewModel.Layout(keyRects: []),
            leftTouches: [],
            rightTouches: [],
            visualsEnabled: false,
            selectedColumn: nil
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
            touches: snapshot.leftTouches,
            selectedColumn: snapshot.selectedColumn
        )
        drawTrackpadSide(
            origin: rightOrigin,
            layout: snapshot.rightLayout,
            touches: snapshot.rightTouches,
            selectedColumn: snapshot.selectedColumn
        )
    }

    private func drawTrackpadSide(
        origin: CGPoint,
        layout: ContentViewModel.Layout,
        touches: [OMSTouchData],
        selectedColumn: Int?
    ) {
        let trackpadRect = CGRect(origin: origin, size: snapshot.trackpadSize)
        let borderPath = NSBezierPath(roundedRect: trackpadRect, xRadius: 6, yRadius: 6)
        NSColor.secondaryLabelColor.withAlphaComponent(0.6).setStroke()
        borderPath.lineWidth = 1
        borderPath.stroke()

        guard snapshot.showDetailed else { return }

        for row in layout.keyRects {
            for (columnIndex, rect) in row.enumerated() {
                let translated = rect.offsetBy(dx: origin.x, dy: origin.y)
                let fillColor: NSColor
                if selectedColumn == columnIndex {
                    fillColor = NSColor.controlAccentColor.withAlphaComponent(0.14)
                } else {
                    fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.2)
                }
                fillColor.setFill()
                NSBezierPath(roundedRect: translated, xRadius: 6, yRadius: 6).fill()
            }
        }

        guard snapshot.visualsEnabled else { return }

        NSColor.systemBlue.withAlphaComponent(0.8).setStroke()
        for touch in touches {
            let centerX = origin.x + CGFloat(touch.position.x) * snapshot.trackpadSize.width
            let centerY = origin.y + (1.0 - CGFloat(touch.position.y)) * snapshot.trackpadSize.height
            let radius = max(4, CGFloat(touch.axis.major) * (snapshot.trackpadSize.width / 120.0))
            let touchRect = CGRect(
                x: centerX - radius,
                y: centerY - radius,
                width: radius * 2,
                height: radius * 2
            )
            let ellipse = NSBezierPath(ovalIn: touchRect)
            ellipse.lineWidth = 2
            NSColor.systemBlue.withAlphaComponent(0.12).setFill()
            ellipse.fill()
            ellipse.stroke()
        }
    }
}

struct TrackpadSurfaceRepresentable: NSViewRepresentable {
    let snapshot: TrackpadSurfaceSnapshot

    func makeNSView(context: Context) -> TrackpadSurfaceView {
        let view = TrackpadSurfaceView(frame: CGRect(origin: .zero, size: snapshot.trackpadSize))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.snapshot = snapshot
        return view
    }

    func updateNSView(_ nsView: TrackpadSurfaceView, context: Context) {
        nsView.snapshot = snapshot
    }
}
