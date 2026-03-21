import Foundation
import OpenMultitouchSupport
import ReplayFixtureKit

private struct Options {
    var durationSeconds: Double = 3.0
    var maxFrames: Int = 1200
    var outputPath: String = "ReplayFixtures/macos_first_capture.atpcap"
}

private actor CaptureBuffer {
    private var nextSequence: UInt64 = 0
    private var frames: [ReplayFrameRecord] = []

    func append(frame: OMSRawTouchFrame) {
        nextSequence &+= 1
        let contacts = frame.touches.map { touch in
            ReplayContactRecord(
                id: Int(touch.id),
                x: Double(touch.posX),
                y: Double(touch.posY),
                total: Double(touch.total),
                pressure: Double(touch.pressure),
                majorAxis: Double(touch.majorAxis),
                minorAxis: Double(touch.minorAxis),
                angle: Double(touch.angle),
                density: Double(touch.density),
                state: ReplayFixtureParser.canonicalState(rawValue: UInt(touch.state.rawValue))
            )
        }

        frames.append(
            ReplayFrameRecord(
                seq: Int(nextSequence),
                timestampSec: frame.timestamp,
                deviceID: frame.deviceID,
                deviceNumericID: frame.deviceIDNumeric,
                deviceIndex: frame.deviceIndex,
                contacts: contacts
            )
        )
    }

    func count() -> Int {
        frames.count
    }

    func snapshot() -> [ReplayFrameRecord] {
        frames
    }
}

@main
struct ReplayFixtureCaptureMain {
    static func main() async {
        let options = parseOptions(from: CommandLine.arguments)
        let outputURL = URL(fileURLWithPath: options.outputPath, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL

        let manager = OMSManager.shared
        let availableDevices = manager.availableDevices
        let selectedDevices = Array(availableDevices.prefix(2))

        if !selectedDevices.isEmpty {
            _ = manager.setActiveDevices(selectedDevices)
        }

        let started = manager.startListening()
        let captureBuffer = CaptureBuffer()

        let captureTask = Task.detached(priority: .userInitiated) {
            guard started else { return }
            for await frame in manager.rawTouchStream {
                if Task.isCancelled {
                    frame.release()
                    return
                }
                await captureBuffer.append(frame: frame)
                frame.release()
                let captured = await captureBuffer.count()
                if captured >= options.maxFrames {
                    return
                }
            }
        }

        let durationNs = UInt64(max(0.25, options.durationSeconds) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: durationNs)

        captureTask.cancel()
        _ = manager.stopListening()

        let frames = await captureBuffer.snapshot()
        let fixture = ReplayFixture(
            meta: ReplayFixtureMeta(
                schema: ReplayFixtureParser.schema,
                capturedAt: iso8601Timestamp(Date()),
                platform: "macOS",
                source: "ReplayFixtureCapture",
                framesCaptured: frames.count
            ),
            frames: frames
        )

        do {
            try ReplayFixtureCodec.write(fixture, to: outputURL)
        } catch {
            fputs("Failed to write fixture: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }

        print("Wrote replay fixture: \(outputURL.path)")
        print("Frames captured: \(frames.count)")
        print("Start listening succeeded: \(started ? "yes" : "no")")
        if !selectedDevices.isEmpty {
            let labels = selectedDevices.enumerated().map { index, device in
                "\(index):\(device.deviceName)(\(device.deviceID))"
            }
            print("Selected devices: \(labels.joined(separator: ", "))")
        }
    }

    private static func parseOptions(from args: [String]) -> Options {
        var options = Options()
        var index = 1
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--duration":
                if index + 1 < args.count, let value = Double(args[index + 1]), value > 0 {
                    options.durationSeconds = value
                    index += 1
                }
            case "--max-frames":
                if index + 1 < args.count, let value = Int(args[index + 1]), value > 0 {
                    options.maxFrames = value
                    index += 1
                }
            case "--output":
                if index + 1 < args.count {
                    options.outputPath = args[index + 1]
                    index += 1
                }
            default:
                break
            }
            index += 1
        }
        return options
    }

    private static func iso8601Timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
