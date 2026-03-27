import Foundation
import ReplayFixtureKit

@main
struct ATPCaptureTranscode {
    static func main() throws {
        let paths = Array(CommandLine.arguments.dropFirst())
        guard !paths.isEmpty else {
            fputs("usage: swift run ATPCaptureTranscode <capture.atpcap> [more.atpcap...]\n", stderr)
            throw ExitCode.failure
        }

        let fileManager = FileManager.default
        for path in paths {
            let sourceURL = URL(fileURLWithPath: path)
            let temporaryURL = sourceURL.deletingLastPathComponent()
                .appendingPathComponent(".\(sourceURL.lastPathComponent).tmp")

            try ReplayFixtureCodec.transcodeLegacyATPCapture(from: sourceURL, to: temporaryURL)
            if fileManager.fileExists(atPath: sourceURL.path) {
                try fileManager.removeItem(at: sourceURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: sourceURL)
            print("transcoded \(sourceURL.path)")
        }
    }
}

private enum ExitCode: Error {
    case failure
}
