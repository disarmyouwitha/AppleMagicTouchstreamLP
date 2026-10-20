import AppKit
import Carbon
import OpenMultitouchSupport
import XCTest
@testable import GlassToKeyRuntime

@MainActor
final class TouchStreamLayoutTests: XCTestCase {
    func testPresetHasIndependentCompleteSidesAndBoundedRegions() {
        XCTAssertTrue(TrackpadLayoutPreset.selectableCases.contains(.touchstream))
        XCTAssertEqual(TrackpadLayoutPreset.resolveByName("touchstream"), .touchstream)
        XCTAssertFalse(TrackpadLayoutPreset.touchstream.blankLeftSide)
        XCTAssertFalse(TrackpadLayoutPreset.touchstream.allowsColumnSettings)
        for side in [TrackpadSide.left, .right] {
            let rows = TouchStreamLayoutDefinition.rows(for: side)
            XCTAssertEqual(rows.count, 6)
            let labels = rows.flatMap { $0.map(\.label) }
            XCTAssertTrue(labels.contains("Hand"))
            XCTAssertTrue(labels.contains("Shift"))
            XCTAssertTrue(labels.contains("Ctrl"))
            XCTAssertTrue(labels.contains("Alt"))
            for key in rows.flatMap({ $0 }) {
                for corner in key.rect.corners(in: CGSize(width: 1, height: 1)) {
                    XCTAssertTrue((-0.01...1.01).contains(corner.x), key.label)
                    XCTAssertTrue((-0.01...1.01).contains(corner.y), key.label)
                }
            }
        }
        XCTAssertTrue(TrackpadLayoutPreset.touchstream.leftLabels.flatMap { $0 }.contains("Back"))
        XCTAssertTrue(TrackpadLayoutPreset.touchstream.rightLabels.flatMap { $0 }.contains("Space"))
        XCTAssertNotEqual(TrackpadLayoutPreset.touchstream.leftLabels, TrackpadLayoutPreset.touchstream.rightLabels)
        let all = TrackpadLayoutPreset.touchstream.leftLabels.flatMap { $0 } + TrackpadLayoutPreset.touchstream.rightLabels.flatMap { $0 }
        for number in 1...12 { XCTAssertTrue(all.contains("F\(number)")) }
        for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" { XCTAssertTrue(all.contains(String(letter))) }
    }

    func testPerKeyGeometryEditsStayOnTheirOwnSide() {
        let size = CGSize(width: 432, height: 310)
        let key = GridKeyPosition(side: .left, row: 2, column: 2).storageKey // A
        let baseline = ContentView.makeTouchStreamKeyLayout(size: size, side: .left)
        let edited = ContentView.makeTouchStreamKeyLayout(size: size, side: .left,
            keyGeometryOverrides: [key: KeyGeometryOverride(rotationDegrees: 10, widthScale: 1.2, heightScale: 0.8)])
        let original = baseline.normalizedKeyRects[2][2]
        XCTAssertEqual(edited.normalizedKeyRects[2][2].centerX, original.centerX, accuracy: 0.00001)
        XCTAssertEqual(edited.normalizedKeyRects[2][2].width, original.width * 1.2, accuracy: 0.00001)
        let right = ContentView.makeTouchStreamKeyLayout(size: size, side: .right,
            keyGeometryOverrides: [key: KeyGeometryOverride(widthScale: 1.2)])
        XCTAssertEqual(right.normalizedKeyRects, ContentView.makeTouchStreamKeyLayout(size: size, side: .right).normalizedKeyRects)
    }

    func testTracedLetterCentersTypeCorrectKeysOnBothPads() {
        let size = CGSize(width: 432, height: 310)
        for (side, row, column, expected) in [(TrackpadSide.left, 2, 2, kVK_ANSI_A), (.right, 2, 1, kVK_ANSI_H)] {
            let run = ProductionReplaySession(startTime: 1)
            let engine = run.engine
            engine.updateLayouts(
                leftLayout: ContentView.makeTouchStreamKeyLayout(size: size, side: .left),
                rightLayout: ContentView.makeTouchStreamKeyLayout(size: size, side: .right),
                leftLabels: TrackpadLayoutPreset.touchstream.leftLabels,
                rightLabels: TrackpadLayoutPreset.touchstream.rightLabels,
                trackpadSize: size, trackpadWidthMm: 160)
            engine.updateActiveDevices(leftIndex: 0, rightIndex: 1, leftDeviceID: "42", rightDeviceID: "43")
            engine.updateKeyboardModeEnabled(true)
            engine.updateForceClickMin(0)
            engine.updateForceClickCap(1000)
            engine.updateHapticStrength(0)
            engine.updateSnapRadiusPercent(0)
            engine.setListening(true)
            let rect = TouchStreamLayoutDefinition.rows(for: side)[row][column].rect
            let index = side == .left ? 0 : 1
            for (time, state) in [(1.0, OMSState.making), (1.04, .touching), (1.08, .breaking)] {
                let touch = OMSRawTouch(id: 1, posX: Float(rect.centerX), posY: Float(1 - rect.centerY),
                    total: 1, pressure: 100, majorAxis: 5, minorAxis: 3, angle: 0, density: 1, state: state)
                run.ingest(RuntimeRawFrame(sequence: UInt64(time * 1000), timestamp: time,
                    deviceNumericID: index == 0 ? 42 : 43, deviceIndex: index, contacts: [], rawTouches: [touch]))
            }
            run.ingest(RuntimeRawFrame(sequence: 1100, timestamp: 1.1, deviceNumericID: index == 0 ? 42 : 43,
                deviceIndex: index, contacts: [], rawTouches: []))
            run.finish(at: 2)
            let taps = run.output.events.compactMap { event -> UInt16? in
                if case let .keyStroke(code, _, _) = event.kind { return code }
                return nil
            }
            XCTAssertEqual(taps, [UInt16(expected)])
        }
    }

    func testUnassignedLegacyKeysHaveInertEditableDefaults() {
        for label in ["Hand", "Caps Lock", "Scroll Lock", "Num Lock", "Popup", "Print Screen", "Pause"] {
            XCTAssertNil(KeyActionCatalog.action(for: label))
            XCTAssertEqual(TouchStreamLayoutDefinition.placeholderMapping(for: label)?.primary.kind, KeyActionKind.none)
        }
        XCTAssertNil(TouchStreamLayoutDefinition.placeholderMapping(for: "A"))
    }

    func testReferenceRenderingPreview() throws {
        // Render only the NSView with synthetic geometry; never opens native devices.
        guard let output = ProcessInfo.processInfo.environment["TOUCHSTREAM_PREVIEW_PATH"] else { return }
        let size = CGSize(width: 432, height: 310)
        var snapshot = TrackpadSurfaceSnapshot.empty
        snapshot.trackpadSize = size
        snapshot.spacing = 16
        snapshot.showDetailed = true
        snapshot.showTouchStreamReference = true
        snapshot.leftLayout = ContentView.makeTouchStreamKeyLayout(size: size, side: .left)
        snapshot.rightLayout = ContentView.makeTouchStreamKeyLayout(size: size, side: .right)
        snapshot.leftLabels = TrackpadLayoutPreset.touchstream.leftLabels.map { $0.map { TrackpadSurfaceLabel(primary: $0) } }
        snapshot.rightLabels = TrackpadLayoutPreset.touchstream.rightLabels.map { $0.map { TrackpadSurfaceLabel(primary: $0) } }
        let view = TrackpadSurfaceView(frame: CGRect(x: 0, y: 0, width: 880, height: 310))
        view.snapshot = snapshot
        let image = NSImage(size: view.bounds.size)
        image.lockFocusFlipped(true)
        NSColor.windowBackgroundColor.setFill()
        view.bounds.fill()
        view.draw(view.bounds)
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: output))
    }
}
