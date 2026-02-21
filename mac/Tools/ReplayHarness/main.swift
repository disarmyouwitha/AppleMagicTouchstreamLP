import Foundation
import ReplayFixtureKit

private struct Options {
    var fixturePath: String = "ReplayFixtures/macos_first_capture_2026-02-20.jsonl"
    var outputPath: String? = nil
}

@main
struct ReplayHarnessMain {
    static func main() async {
        let options = parseOptions(arguments: CommandLine.arguments)
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fixtureURL = URL(fileURLWithPath: options.fixturePath, relativeTo: cwd).standardizedFileURL

        let fixture: ReplayFixture
        do {
            fixture = try ReplayFixtureParser.load(from: fixtureURL)
        } catch {
            fputs("Failed to load replay fixture: \(error)\n", stderr)
            Foundation.exit(1)
        }

        let transcript = await ReplayHarnessRunner.run(fixture: fixture)
        let lines = ReplayHarnessRunner.transcriptJSONLines(fixture: fixture, transcript: transcript)
        let payload = lines.joined(separator: "\n") + "\n"

        if let outputPath = options.outputPath {
            let outputURL = URL(fileURLWithPath: outputPath, relativeTo: cwd).standardizedFileURL
            do {
                try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try payload.write(to: outputURL, atomically: true, encoding: .utf8)
                print("Wrote transcript: \(outputURL.path)")
            } catch {
                fputs("Failed to write transcript: \(error)\n", stderr)
                Foundation.exit(1)
            }
        } else {
            print(payload, terminator: "")
        }

        print("Frames processed: \(fixture.frames.count)")
    }

    private static func parseOptions(arguments: [String]) -> Options {
        var options = Options()
        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--fixture":
                if index + 1 < arguments.count {
                    options.fixturePath = arguments[index + 1]
                    index += 1
                }
            case "--output":
                if index + 1 < arguments.count {
                    options.outputPath = arguments[index + 1]
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
