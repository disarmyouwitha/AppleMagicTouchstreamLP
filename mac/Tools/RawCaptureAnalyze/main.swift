import Foundation
import ReplayFixtureKit

private struct Options {
    var rawAnalyzePath: String?
    var rawAnalyzeOutputPath: String?
    var rawAnalyzeContactsOutputPath: String?
}

@main
struct RawCaptureAnalyzeMain {
    static func main() {
        let options = parseOptions(CommandLine.arguments)
        guard let rawAnalyzePath = options.rawAnalyzePath else {
            fputs(
                "Usage: RawCaptureAnalyze --raw-analyze <capturePath> [--raw-analyze-out <path>] [--raw-analyze-contacts-out <path>]\n",
                stderr
            )
            Foundation.exit(2)
        }

        do {
            let inputPath = URL(fileURLWithPath: rawAnalyzePath, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
                .standardizedFileURL
                .path
            let contactsPath: String? = options.rawAnalyzeContactsOutputPath.map {
                URL(fileURLWithPath: $0, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
                    .standardizedFileURL
                    .path
            }

            let result = try RawCaptureAnalyzer.analyze(
                capturePath: inputPath,
                contactsCSVPath: contactsPath
            )
            print(result.toSummary())

            if let outputPath = options.rawAnalyzeOutputPath {
                let normalizedOutputPath = URL(fileURLWithPath: outputPath, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
                    .standardizedFileURL
                    .path
                try result.writeJSON(to: normalizedOutputPath)
            }
        } catch {
            fputs("Raw analyze failed: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func parseOptions(_ args: [String]) -> Options {
        var options = Options()
        var index = 1
        while index < args.count {
            switch args[index] {
            case "--raw-analyze":
                if index + 1 < args.count {
                    options.rawAnalyzePath = args[index + 1]
                    index += 1
                }
            case "--raw-analyze-out":
                if index + 1 < args.count {
                    options.rawAnalyzeOutputPath = args[index + 1]
                    index += 1
                }
            case "--raw-analyze-contacts-out":
                if index + 1 < args.count {
                    options.rawAnalyzeContactsOutputPath = args[index + 1]
                    index += 1
                }
            default:
                break
            }
            index += 1
        }
        return options
    }
}
