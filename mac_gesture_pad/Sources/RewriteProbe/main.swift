import Foundation
import ReplayFixtureKit
import RewriteProbeKit

private struct TrialReport: Encodable {
    let id: String
    let intent: String
    let capture: String
    let status: String
    let message: String?
    let observations: ProbeObservation?
    let checks: [ProbeResult]
}
private struct SessionReport: Encodable {
    let schema = "g2k-rewrite-probe-report-v1"
    let scope = "Offline contact observations against declared trial intent. No OS events; no recognition accuracy or firmware equivalence claim."
    let planPath: String
    let planSHA256: String
    let widthMM: Double?
    let heightMM: Double?
    let trials: [TrialReport]
}

import CryptoKit

@main
struct RewriteProbeMain {
    static func main() {
        do { try run() }
        catch {
            FileHandle.standardError.write(Data("RewriteProbe: \(error)\n".utf8))
            Foundation.exit(2)
        }
    }
    static func run() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args == ["--help"] || args.isEmpty {
            print("""
            Offline contact tests; never posts keyboard/mouse events.
            RewriteProbe --plan session.json --output reports-directory
            RewriteProbe --inspect capture.atpcap [--device-index 0] [--width-mm W --height-mm H]
            Exit: 0 all observation checks pass; 1 any failed check; 3 missing/inconclusive trial; 2 invalid input.
            """)
            return
        }
        let allowed: Set<String> = ["--plan", "--output", "--inspect", "--device-index", "--width-mm", "--height-mm"]
        var options: [String: String] = [:]
        var i = 0
        while i < args.count {
            guard allowed.contains(args[i]), i+1 < args.count, options[args[i]] == nil else {
                throw ProbeError.invalid("Unknown, duplicated or incomplete option: \(args[i])")
            }
            options[args[i]] = args[i+1]; i += 2
        }
        if let path = options["--inspect"] {
            guard options["--plan"] == nil, options["--output"] == nil else {
                throw ProbeError.invalid("Inspect and plan modes are separate")
            }
            let fixture = try ReplayFixtureParser.load(from: URL(fileURLWithPath: path))
            let available = Array(Set(fixture.frames.map(\.deviceIndex))).sorted()
            let index: Int
            if let raw = options["--device-index"] {
                guard let value = Int(raw), value >= 0 else { throw ProbeError.invalid("Invalid device index") }
                index = value
            } else {
                guard available.count == 1, let only = available.first else {
                    throw ProbeError.invalid("Select --device-index; recorded indices: \(available)")
                }
                index = only
            }
            func dimension(_ key: String) throws -> Double? {
                guard let raw = options[key] else { return nil }
                guard let value = Double(raw), value.isFinite, value > 0 else { throw ProbeError.invalid("Invalid \(key)") }
                return value
            }
            let observation = try RewriteProbeAnalyzer.analyze(fixture.frames, deviceIndex: index,
                widthMM: dimension("--width-mm"), heightMM: dimension("--height-mm"), gapLimitMS: 100)
            FileHandle.standardOutput.write(try encoded(observation))
            return
        }
        guard let planPath = options["--plan"], let outputPath = options["--output"],
              options.count == 2 else { throw ProbeError.invalid("Use --plan and --output, or --inspect") }
        let planURL = URL(fileURLWithPath: planPath).standardizedFileURL
        let planBytes = try Data(contentsOf: planURL)
        let plan = try JSONDecoder().decode(ProbePlan.self, from: planBytes)
        try plan.validate()
        let directory = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var reports: [TrialReport] = []
        var captureHashes: [String: String] = [:]
        for trial in plan.trials {
            let path = URL(fileURLWithPath: trial.capture, relativeTo: planURL.deletingLastPathComponent()).standardizedFileURL
            if !FileManager.default.fileExists(atPath: path.path) {
                reports.append(TrialReport(id: trial.id, intent: trial.intent, capture: path.path,
                    status: "inconclusive", message: "Capture not recorded yet", observations: nil, checks: []))
                continue
            }
            let data = try Data(contentsOf: path)
            captureHashes[trial.id] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let fixture = try ReplayFixtureParser.load(from: path)
            let observations = try RewriteProbeAnalyzer.analyze(fixture.frames, deviceIndex: trial.deviceIndex,
                widthMM: plan.widthMM, heightMM: plan.heightMM, gapLimitMS: plan.gapLimitMS)
            let checks = RewriteProbeAnalyzer.evaluate(trial, observation: observations)
            let status = checks.contains { $0.status == "fail" } ? "fail" :
                checks.contains { $0.status == "inconclusive" } ? "inconclusive" : "pass"
            reports.append(TrialReport(id: trial.id, intent: trial.intent, capture: path.path,
                status: status, message: nil, observations: observations, checks: checks))
        }
        let report = SessionReport(planPath: planURL.path,
            planSHA256: SHA256.hash(data: planBytes).map { String(format: "%02x", $0) }.joined(),
            widthMM: plan.widthMM, heightMM: plan.heightMM, trials: reports)
        try encoded(report).write(to: directory.appendingPathComponent("report.json"), options: .atomic)
        try encoded(captureHashes).write(to: directory.appendingPathComponent("capture-sha256.json"), options: .atomic)
        var markdown = "# GlassToKey rewrite observations\n\n\(report.scope)\n\n"
        markdown += "Dimensions: \(plan.widthMM.map(String.init(describing:)) ?? "not calibrated") × \(plan.heightMM.map(String.init(describing:)) ?? "not calibrated") mm.\n\n"
        for trial in reports {
            markdown += "## \(trial.id): \(trial.status)\n\nIntended: \(trial.intent)\n\n"
            if let message = trial.message { markdown += "\(message)\n\n" }
            if let o = trial.observations {
                markdown += "Frames \(o.frames); lifetimes \(o.lifetimes.count); peak contacts \(o.peakContacts); partial lifts \(o.partialLiftFrames); landing spread \(String(format: "%.1f", o.largestLandingSpreadMS)) ms.\n\n"
                markdown += "Uncertain lifetimes \(o.uncertainEndings); raw identity changes \(o.identityChanges); telemetry \(o.telemetrySamples)/\(o.activeSamples) active samples. Inspect lifetime pressure ranges and raw finger codes in JSON.\n\n"
                markdown += "Quality: active-frame gaps \(o.gaps), time regressions \(o.timestampRegressions), invalid samples \(o.invalidSamples), duplicate IDs \(o.duplicateIDs), device changes \(o.deviceChanges).\n\n"
                if !o.lifetimes.isEmpty {
                    markdown += "| Contact:generation | Raw finger codes | Duration ms | Pressure min…peak | Max displacement | End |\n| --- | --- | --- | --- | --- | --- |\n"
                    for life in o.lifetimes.prefix(30) {
                        let raw = life.rawFingerIDs.isEmpty ? "unavailable" : life.rawFingerIDs.map(String.init).joined(separator: ", ")
                        let distance = life.maxDisplacementMM.map { String(format: "%.3f mm", $0) } ?? String(format: "%.5f normalized", life.maxDisplacementNormalized)
                        markdown += "| \(life.rawID):\(life.generation) | \(raw) | \(String(format: "%.1f", life.durationMS)) | \(String(format: "%.3f…%.3f", life.minPressure, life.peakPressure)) | \(distance) | \(life.endReason ?? "unknown")\(life.startCensored ? "; start censored" : "") |\n"
                    }
                    if o.lifetimes.count > 30 { markdown += "\nFirst 30 lifetimes shown; all are retained in report.json.\n" }
                    markdown += "\n"
                }
            }
            for check in trial.checks {
                markdown += "- **\(check.status)** \(check.metric): observed \(check.observed.map { String(format: "%.4f", $0) } ?? "unavailable"), threshold \(check.expected). \(check.detail)\n"
            }
            markdown += "\n"
        }
        markdown += "## Still untested\n\nNative event suppression/delivery, actual intended-key accuracy, OS output balance, anatomical correctness and exact firmware equivalence require separate tests. A passing contact-shape check does not validate a recognizer.\n"
        try Data(markdown.utf8).write(to: directory.appendingPathComponent("report.md"), options: .atomic)
        print("Wrote \(directory.appendingPathComponent("report.md").path)")
        for trial in reports { print("\(trial.id): \(trial.status)") }
        if reports.contains(where: { $0.status == "fail" }) { Foundation.exit(1) }
        if reports.contains(where: { $0.status == "inconclusive" }) { Foundation.exit(3) }
    }
    static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value) + Data([10])
    }
}
