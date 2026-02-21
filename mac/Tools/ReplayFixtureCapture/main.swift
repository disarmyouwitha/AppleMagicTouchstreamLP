import Foundation
import OpenMultitouchSupport

private struct Options {
    var durationSeconds: Double = 3.0
    var maxFrames: Int = 1200
    var outputPath: String = "ReplayFixtures/macos_first_capture.jsonl"
}

private actor CaptureBuffer {
    private var nextSequence: UInt64 = 0
    private var frameLines: [String] = []

    func append(frame: OMSRawTouchFrame) {
        nextSequence &+= 1
        let contacts: [[String: Any]] = frame.touches.map { touch in
            [
                "id": Int(touch.id),
                "x": Double(touch.posX),
                "y": Double(touch.posY),
                "total": Double(touch.total),
                "pressure": Double(touch.pressure),
                "majorAxis": Double(touch.majorAxis),
                "minorAxis": Double(touch.minorAxis),
                "angle": Double(touch.angle),
                "density": Double(touch.density),
                "state": String(describing: touch.state)
            ]
        }

        let frameRecord: [String: Any] = [
            "type": "frame",
            "schema": "g2k-replay-v1",
            "seq": Int(nextSequence),
            "timestampSec": frame.timestamp,
            "deviceID": frame.deviceID,
            "deviceNumericID": Int64(frame.deviceIDNumeric),
            "deviceIndex": frame.deviceIndex,
            "touchCount": contacts.count,
            "contacts": contacts
        ]

        if let line = jsonLine(frameRecord) {
            frameLines.append(line)
        }
    }

    func snapshot() -> [String] {
        frameLines
    }

    nonisolated private func jsonLine(_ object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: []),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
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
                let captured = await captureBuffer.snapshot().count
                if captured >= options.maxFrames {
                    return
                }
            }
        }

        let durationNs = UInt64(max(0.25, options.durationSeconds) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: durationNs)

        captureTask.cancel()
        _ = manager.stopListening()

        let frameLines = await captureBuffer.snapshot()
        let selectedDeviceRecords: [[String: Any]] = selectedDevices.enumerated().map { index, device in
            [
                "deviceID": device.deviceID,
                "deviceNumericID": Int64(device.deviceIDNumeric),
                "deviceIndex": index,
                "deviceName": device.deviceName,
                "isBuiltIn": device.isBuiltIn
            ]
        }

        var meta: [String: Any] = [
            "type": "meta",
            "schema": "g2k-replay-v1",
            "capturedAt": iso8601Timestamp(Date()),
            "platform": "macOS",
            "source": "ReplayFixtureCapture",
            "durationSeconds": options.durationSeconds,
            "maxFrames": options.maxFrames,
            "framesCaptured": frameLines.count,
            "selectedDevices": selectedDeviceRecords,
            "startListeningSucceeded": started
        ]

        if frameLines.isEmpty {
            meta["notes"] = "No touch frames captured during sampling window."
        }

        guard let metaLine = jsonLine(meta) else {
            fputs("Failed to serialize meta record.\n", stderr)
            Foundation.exit(1)
        }

        let allLines = [metaLine] + frameLines

        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let payload = (allLines.joined(separator: "\n") + "\n")
            try payload.write(to: outputURL, atomically: true, encoding: .utf8)
        } catch {
            fputs("Failed to write fixture: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }

        print("Wrote replay fixture: \(outputURL.path)")
        print("Frames captured: \(frameLines.count)")
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

    private static func jsonLine(_ object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: []),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }
}
