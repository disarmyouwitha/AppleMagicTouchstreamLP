import CoreGraphics
import XCTest

final class LayoutMathParityTests: XCTestCase {
    func testWindowsAndCanonicalMacMathMatchForSixByFour() {
        let anchors = [
            CGPoint(x: 35.0, y: 20.9),
            CGPoint(x: 53.0, y: 19.2),
            CGPoint(x: 71.0, y: 17.5),
            CGPoint(x: 89.0, y: 19.2),
            CGPoint(x: 107.0, y: 22.6),
            CGPoint(x: 125.0, y: 22.6),
        ]
        let settings = [
            TestColumn(scaleX: 1.05, scaleY: 1.08, offsetXPercent: -1.5, offsetYPercent: 0.3, rowSpacingPercent: 2.0, rotationDegrees: 1.5),
            TestColumn(scaleX: 1.00, scaleY: 1.02, offsetXPercent: -0.8, offsetYPercent: 0.1, rowSpacingPercent: 1.0, rotationDegrees: 0.5),
            TestColumn(scaleX: 1.12, scaleY: 1.10, offsetXPercent: -0.2, offsetYPercent: -0.1, rowSpacingPercent: 3.0, rotationDegrees: 0.0),
            TestColumn(scaleX: 1.15, scaleY: 1.09, offsetXPercent: 0.4, offsetYPercent: -0.2, rowSpacingPercent: 2.5, rotationDegrees: 0.0),
            TestColumn(scaleX: 1.03, scaleY: 1.05, offsetXPercent: 1.0, offsetYPercent: 0.2, rowSpacingPercent: 1.5, rotationDegrees: 359.0),
            TestColumn(scaleX: 0.98, scaleY: 1.00, offsetXPercent: 1.8, offsetYPercent: 0.4, rowSpacingPercent: 0.5, rotationDegrees: 358.5),
        ]

        let windows = buildWindowsLayout(
            anchors: anchors,
            rows: 4,
            settings: settings,
            keySpacingPercent: 10.0
        )
        let canonicalMac = buildCanonicalMacLayout(
            anchors: anchors,
            rows: 4,
            settings: settings,
            keySpacingPercent: 10.0
        )

        assertRectsEqual(windows, canonicalMac, accuracy: 0.000_001)
    }

    func testWindowsAndCanonicalMacMathMatchForFiveByThree() {
        let anchors = [
            CGPoint(x: 35.0, y: 20.9),
            CGPoint(x: 53.0, y: 19.2),
            CGPoint(x: 71.0, y: 17.5),
            CGPoint(x: 89.0, y: 19.2),
            CGPoint(x: 107.0, y: 22.6),
        ]
        let settings = [
            TestColumn(scaleX: 1.0, scaleY: 1.0, offsetXPercent: -1.0, offsetYPercent: 0.0, rowSpacingPercent: 0.0, rotationDegrees: 0.0),
            TestColumn(scaleX: 1.08, scaleY: 1.04, offsetXPercent: -0.4, offsetYPercent: -0.2, rowSpacingPercent: 4.0, rotationDegrees: 0.0),
            TestColumn(scaleX: 1.12, scaleY: 1.10, offsetXPercent: 0.0, offsetYPercent: -0.3, rowSpacingPercent: 5.0, rotationDegrees: 2.0),
            TestColumn(scaleX: 1.04, scaleY: 1.02, offsetXPercent: 0.7, offsetYPercent: -0.1, rowSpacingPercent: 2.0, rotationDegrees: 0.0),
            TestColumn(scaleX: 0.96, scaleY: 0.98, offsetXPercent: 1.2, offsetYPercent: 0.2, rowSpacingPercent: 1.0, rotationDegrees: 359.0),
        ]

        let windows = buildWindowsLayout(
            anchors: anchors,
            rows: 3,
            settings: settings,
            keySpacingPercent: 10.0
        )
        let canonicalMac = buildCanonicalMacLayout(
            anchors: anchors,
            rows: 3,
            settings: settings,
            keySpacingPercent: 10.0
        )

        assertRectsEqual(windows, canonicalMac, accuracy: 0.000_001)
    }

    private func assertRectsEqual(
        _ lhs: [[TestRect]],
        _ rhs: [[TestRect]],
        accuracy: CGFloat,
    ) {
        XCTAssertEqual(lhs.count, rhs.count)
        for (leftRow, rightRow) in zip(lhs, rhs) {
            XCTAssertEqual(leftRow.count, rightRow.count)
            for (leftRect, rightRect) in zip(leftRow, rightRow) {
                XCTAssertEqual(leftRect.x, rightRect.x, accuracy: accuracy)
                XCTAssertEqual(leftRect.y, rightRect.y, accuracy: accuracy)
                XCTAssertEqual(leftRect.width, rightRect.width, accuracy: accuracy)
                XCTAssertEqual(leftRect.height, rightRect.height, accuracy: accuracy)
                XCTAssertEqual(leftRect.rotationDegrees, rightRect.rotationDegrees, accuracy: 0.000_001)
            }
        }
    }

    private func buildWindowsLayout(
        anchors: [CGPoint],
        rows: Int,
        settings: [TestColumn],
        keySpacingPercent: Double,
    ) -> [[TestRect]] {
        buildCanonicalLayout(
            anchors: anchors,
            rows: rows,
            settings: settings,
            keySpacingPercent: keySpacingPercent
        )
    }

    private func buildCanonicalMacLayout(
        anchors: [CGPoint],
        rows: Int,
        settings: [TestColumn],
        keySpacingPercent: Double,
    ) -> [[TestRect]] {
        buildCanonicalLayout(
            anchors: anchors,
            rows: rows,
            settings: settings,
            keySpacingPercent: keySpacingPercent
        )
    }

    private func buildCanonicalLayout(
        anchors: [CGPoint],
        rows: Int,
        settings: [TestColumn],
        keySpacingPercent: Double,
    ) -> [[TestRect]] {
        let trackpadWidth: CGFloat = 160.0
        let trackpadHeight: CGFloat = 114.9
        let keyWidth: CGFloat = 18.0
        let keyHeight: CGFloat = 17.0
        let spacingScale = CGFloat(max(0.0, min(keySpacingPercent, 200.0)) / 100.0)

        var rects = Array(
            repeating: Array(repeating: TestRect.zero, count: anchors.count),
            count: rows
        )

        for row in 0..<rows {
            for column in anchors.indices {
                let setting = settings[column]
                let width = keyWidth * CGFloat(setting.scaleX)
                let height = keyHeight * CGFloat(setting.scaleY)
                let spacingY = height * spacingScale
                let rowSpacing = height * CGFloat(setting.rowSpacingPercent / 100.0)
                rects[row][column] = TestRect(
                    x: anchors[column].x / trackpadWidth,
                    y: (anchors[column].y + CGFloat(row) * (height + rowSpacing + spacingY)) / trackpadHeight,
                    width: width / trackpadWidth,
                    height: height / trackpadHeight
                )
            }
        }

        for column in anchors.indices {
            let offsetX = CGFloat(settings[column].offsetXPercent / 100.0)
            let offsetY = CGFloat(settings[column].offsetYPercent / 100.0)
            for row in 0..<rows {
                rects[row][column].x += offsetX
                rects[row][column].y += offsetY
            }
        }

        for column in anchors.indices {
            let rotationDegrees = -normalizeDegrees(settings[column].rotationDegrees)
            if abs(rotationDegrees) < 0.000_01 {
                continue
            }
            let pivotX = rects[0][column].centerX
            let pivotY = (rects[0][column].centerY + rects[rows - 1][column].centerY) * 0.5
            for row in 0..<rows {
                rects[row][column] = rects[row][column].rotatedAround(
                    pivotX: pivotX,
                    pivotY: pivotY,
                    rotationDegrees: rotationDegrees
                )
            }
        }

        return rects
    }

    private func normalizeDegrees(_ value: Double) -> Double {
        let normalized = value.truncatingRemainder(dividingBy: 360.0)
        return normalized >= 0 ? normalized : normalized + 360.0
    }
}

private struct TestColumn {
    let scaleX: Double
    let scaleY: Double
    let offsetXPercent: Double
    let offsetYPercent: Double
    let rowSpacingPercent: Double
    let rotationDegrees: Double
}

private struct TestRect {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var rotationDegrees: Double = 0

    static let zero = TestRect(x: 0, y: 0, width: 0, height: 0)

    var centerX: CGFloat { x + (width * 0.5) }
    var centerY: CGFloat { y + (height * 0.5) }

    func rotatedAround(
        pivotX: CGFloat,
        pivotY: CGFloat,
        rotationDegrees: Double,
    ) -> TestRect {
        guard abs(rotationDegrees) >= 0.000_01 else { return self }
        let radians = CGFloat(rotationDegrees * .pi / 180.0)
        let cosValue = cos(radians)
        let sinValue = sin(radians)
        let localX = centerX - pivotX
        let localY = centerY - pivotY
        let rotatedCenterX = pivotX + (localX * cosValue) - (localY * sinValue)
        let rotatedCenterY = pivotY + (localX * sinValue) + (localY * cosValue)
        return TestRect(
            x: rotatedCenterX - (width * 0.5),
            y: rotatedCenterY - (height * 0.5),
            width: width,
            height: height,
            rotationDegrees: normalizedRotation(rotationDegrees + self.rotationDegrees)
        )
    }

    private func normalizedRotation(_ value: Double) -> Double {
        let normalized = value.truncatingRemainder(dividingBy: 360.0)
        return normalized >= 0 ? normalized : normalized + 360.0
    }
}
