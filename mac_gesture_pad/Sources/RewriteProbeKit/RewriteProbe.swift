import Foundation
import ReplayFixtureKit

/// Offline observations and user-declared intent; never emits OS input.
public struct ProbePlan: Decodable {
    public let schema: String
    public let widthMM: Double?
    public let heightMM: Double?
    public let gapLimitMS: Double
    public let trials: [ProbeTrial]

    public func validate() throws {
        guard schema == "g2k-rewrite-probe-v1", gapLimitMS.isFinite, gapLimitMS > 0,
              !trials.isEmpty, Set(trials.map(\.id)).count == trials.count else {
            throw ProbeError.invalid("Invalid schema, gap limit, empty trials or duplicate trial IDs")
        }
        guard (widthMM == nil) == (heightMM == nil) else {
            throw ProbeError.invalid("Supply both physical dimensions or neither")
        }
        if let w = widthMM, let h = heightMM {
            guard w.isFinite, h.isFinite, w > 0, h > 0 else {
                throw ProbeError.invalid("Physical dimensions must be finite and positive")
            }
        }
        for trial in trials {
            guard !trial.id.isEmpty, !trial.capture.isEmpty, !trial.intent.isEmpty,
                  !trial.checks.isEmpty, trial.deviceIndex >= 0 else {
                throw ProbeError.invalid("Trial needs ID, capture, intended action, device index and checks")
            }
            for check in trial.checks {
                guard check.value.isFinite, check.value >= 0 else {
                    throw ProbeError.invalid("Check thresholds must be finite and nonnegative")
                }
            }
        }
    }
}

public struct ProbeTrial: Decodable {
    public let id: String
    public let capture: String
    public let intent: String
    public let deviceIndex: Int
    public let checks: [ProbeCheck]
}

public enum ProbeMetric: String, Codable {
    case minimumLifetimes, maximumLifetimes, minimumPeakContacts, maximumPeakContacts
    case minimumPartialLiftFrames, minimumLandingSpreadMS
    case minimumLongestDurationMS, maximumDisplacementMM, minimumDisplacementMM
    case maximumUncertainEndings, minimumTelemetryFraction, maximumIdentityChanges
}

public struct ProbeCheck: Decodable {
    public let metric: ProbeMetric
    public let value: Double
}

public enum ProbeError: Error, CustomStringConvertible {
    case invalid(String)
    public var description: String { switch self { case let .invalid(s): return s } }
}

public struct ProbeLifetime: Encodable {
    public let rawID: Int
    public let generation: Int
    public let start: Double
    public var lastSample: Double
    public var end: Double?
    public var endReason: String?
    public var samples = 0
    public var startCensored = false
    public var maxDisplacementNormalized = 0.0
    public var maxDisplacementMM: Double?
    public var pathLengthNormalized = 0.0
    public var peakPressure = -Double.infinity
    public var minPressure = Double.infinity
    public var identityChanges = 0
    public var rawFingerIDs: [Int32] = []
    public var telemetrySamples = 0
    fileprivate var x: Double
    fileprivate var y: Double
    fileprivate var lastX: Double
    fileprivate var lastY: Double
    fileprivate var previousIdentity: Int32?
    public var durationMS: Double { ((end ?? lastSample) - start) * 1000 }
    public var uncertain: Bool { startCensored || endReason != "explicitRelease" }

    private enum CodingKeys: String, CodingKey {
        case rawID, generation, start, lastSample, end, endReason, samples, startCensored
        case maxDisplacementNormalized, maxDisplacementMM, pathLengthNormalized
        case peakPressure, minPressure, identityChanges, rawFingerIDs, telemetrySamples
        case durationMS, uncertain
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rawID, forKey: .rawID); try c.encode(generation, forKey: .generation)
        try c.encode(start, forKey: .start); try c.encode(lastSample, forKey: .lastSample)
        try c.encodeIfPresent(end, forKey: .end); try c.encodeIfPresent(endReason, forKey: .endReason)
        try c.encode(samples, forKey: .samples); try c.encode(startCensored, forKey: .startCensored)
        try c.encode(maxDisplacementNormalized, forKey: .maxDisplacementNormalized)
        try c.encodeIfPresent(maxDisplacementMM, forKey: .maxDisplacementMM)
        try c.encode(pathLengthNormalized, forKey: .pathLengthNormalized)
        try c.encode(peakPressure, forKey: .peakPressure); try c.encode(minPressure, forKey: .minPressure)
        try c.encode(identityChanges, forKey: .identityChanges); try c.encode(rawFingerIDs, forKey: .rawFingerIDs)
        try c.encode(telemetrySamples, forKey: .telemetrySamples)
        try c.encode(durationMS, forKey: .durationMS); try c.encode(uncertain, forKey: .uncertain)
    }
}

public struct ProbeObservation: Encodable {
    public let deviceIndex: Int
    public var frames = 0
    public var activeSamples = 0
    public var telemetrySamples = 0
    public var peakContacts = 0
    public var partialLiftFrames = 0
    public var largestLandingSpreadMS = 0.0
    public var gaps = 0
    public var timestampRegressions = 0
    public var invalidSamples = 0
    public var duplicateIDs = 0
    public var deviceChanges = 0
    public var lifetimes: [ProbeLifetime] = []
    public var identityChanges: Int { lifetimes.reduce(0) { $0 + $1.identityChanges } }
    public var uncertainEndings: Int { lifetimes.filter(\.uncertain).count }
}

public struct ProbeResult: Encodable {
    public let metric: String
    public let expected: Double
    public let observed: Double?
    public let status: String
    public let detail: String
}

public enum RewriteProbeAnalyzer {
    public static func analyze(_ frames: [ReplayFrameRecord], deviceIndex: Int,
                               widthMM: Double?, heightMM: Double?, gapLimitMS: Double) throws -> ProbeObservation {
        guard gapLimitMS.isFinite, gapLimitMS > 0, (widthMM == nil) == (heightMM == nil) else {
            throw ProbeError.invalid("Invalid gap limit or partial dimensions")
        }
        if let w = widthMM, let h = heightMM {
            guard w.isFinite, h.isFinite, w > 0, h > 0 else { throw ProbeError.invalid("Invalid dimensions") }
        }
        var result = ProbeObservation(deviceIndex: deviceIndex)
        var active: [Int: Int] = [:], generations: [Int: Int] = [:]
        var lastTime: Double?, previousCount = 0, episodeStart: Double?
        var episodeMembers: Set<String> = []
        var deviceIdentity: UInt64?
        func closeAll(_ reason: String, _ time: Double?) {
            for index in active.values {
                result.lifetimes[index].end = time ?? result.lifetimes[index].lastSample
                result.lifetimes[index].endReason = reason
            }
            active.removeAll(); previousCount = 0; episodeStart = nil; episodeMembers.removeAll()
        }
        for frame in frames where frame.deviceIndex == deviceIndex {
            result.frames += 1
            guard frame.timestampSec.isFinite else {
                result.invalidSamples += 1; closeAll("invalidTimestamp", lastTime); lastTime = nil; continue
            }
            let time = frame.timestampSec
            var discontinuity = false
            if let last = lastTime {
                if time < last {
                    result.timestampRegressions += 1; closeAll("timestampRegression", last); discontinuity = true
                } else if (time - last) * 1000 > gapLimitMS {
                    if !active.isEmpty { result.gaps += 1 }
                    closeAll("frameGap", last); discontinuity = true
                }
            }
            if let identity = deviceIdentity, identity != frame.deviceNumericID {
                result.deviceChanges += 1
                closeAll("deviceChanged", lastTime); discontinuity = true
            }
            let firstFrame = lastTime == nil
            lastTime = time; deviceIdentity = frame.deviceNumericID
            var seen: Set<Int> = [], currentlyActive: Set<Int> = []
            for contact in frame.contacts {
                guard seen.insert(contact.id).inserted else { result.duplicateIDs += 1; continue }
                let down = ["starting", "making", "touching"].contains(contact.state)
                if !down {
                    if let index = active.removeValue(forKey: contact.id) {
                        result.lifetimes[index].end = time
                        result.lifetimes[index].endReason = "explicitRelease"
                    }
                    continue
                }
                guard contact.x.isFinite, contact.y.isFinite, contact.pressure.isFinite else {
                    result.invalidSamples += 1; continue
                }
                currentlyActive.insert(contact.id)
                let index: Int
                if let existing = active[contact.id] { index = existing }
                else {
                    let generation = (generations[contact.id] ?? 0) + 1
                    generations[contact.id] = generation
                    index = result.lifetimes.count; active[contact.id] = index
                    result.lifetimes.append(ProbeLifetime(rawID: contact.id, generation: generation,
                        start: time, lastSample: time, startCensored: firstFrame || discontinuity,
                        maxDisplacementMM: widthMM == nil ? nil : 0,
                        x: contact.x, y: contact.y, lastX: contact.x, lastY: contact.y))
                    if episodeStart == nil { episodeStart = time }
                    episodeMembers.insert("\(contact.id):\(generation)")
                    // Spread over an uninterrupted nonempty cohort, not across separate taps.
                    if episodeMembers.count > 1, let start = episodeStart {
                        result.largestLandingSpreadMS = max(result.largestLandingSpreadMS, (time - start) * 1000)
                    }
                }
                var life = result.lifetimes[index]
                life.samples += 1; life.lastSample = time
                life.maxDisplacementNormalized = max(life.maxDisplacementNormalized, hypot(contact.x-life.x, contact.y-life.y))
                life.pathLengthNormalized += hypot(contact.x-life.lastX, contact.y-life.lastY)
                if let w = widthMM, let h = heightMM {
                    life.maxDisplacementMM = max(life.maxDisplacementMM ?? 0, hypot((contact.x-life.x)*w, (contact.y-life.y)*h))
                }
                life.lastX = contact.x; life.lastY = contact.y
                life.peakPressure = max(life.peakPressure, contact.pressure)
                life.minPressure = min(life.minPressure, contact.pressure)
                if let raw = contact.telemetry {
                    life.telemetrySamples += 1; result.telemetrySamples += 1
                    if let previous = life.previousIdentity, previous != raw.fingerID { life.identityChanges += 1 }
                    life.previousIdentity = raw.fingerID
                    if !life.rawFingerIDs.contains(raw.fingerID) { life.rawFingerIDs.append(raw.fingerID) }
                }
                result.activeSamples += 1; result.lifetimes[index] = life
            }
            for id in Array(active.keys) where !currentlyActive.contains(id) {
                if let index = active.removeValue(forKey: id) {
                    result.lifetimes[index].end = time; result.lifetimes[index].endReason = "omittedFromFrame"
                }
            }
            let count = active.count
            result.peakContacts = max(result.peakContacts, count)
            if count > 0 && count < previousCount { result.partialLiftFrames += 1 }
            if count == 0 { episodeStart = nil; episodeMembers.removeAll() }
            previousCount = count
        }
        closeAll("captureEnded", nil)
        return result
    }

    public static func evaluate(_ trial: ProbeTrial, observation o: ProbeObservation) -> [ProbeResult] {
        let qualityProblems = o.gaps + o.timestampRegressions + o.invalidSamples + o.duplicateIDs + o.deviceChanges
        return trial.checks.map { check in
            var value: Double?, minimum = true, note = "Observation check; not recognizer accuracy or firmware equivalence."
            switch check.metric {
            case .minimumLifetimes: value = Double(o.lifetimes.count)
            case .maximumLifetimes: value = Double(o.lifetimes.count); minimum = false
            case .minimumPeakContacts: value = Double(o.peakContacts)
            case .maximumPeakContacts: value = Double(o.peakContacts); minimum = false
            case .minimumPartialLiftFrames: value = Double(o.partialLiftFrames)
            case .minimumLandingSpreadMS: value = o.largestLandingSpreadMS
            case .minimumLongestDurationMS:
                value = o.lifetimes.map(\.durationMS).max()
                note = "Duration can be a censored lower bound; inspect uncertain endings."
            case .maximumDisplacementMM: value = o.lifetimes.compactMap(\.maxDisplacementMM).max(); minimum = false
            case .minimumDisplacementMM: value = o.lifetimes.compactMap(\.maxDisplacementMM).max()
            case .maximumUncertainEndings: value = Double(o.uncertainEndings); minimum = false
            case .minimumTelemetryFraction:
                value = o.activeSamples > 0 ? Double(o.telemetrySamples)/Double(o.activeSamples) : nil
            case .maximumIdentityChanges:
                value = o.telemetrySamples == o.activeSamples && o.activeSamples > 0 ? Double(o.identityChanges) : nil
                minimum = false; note = "Raw identity-code changes only; anatomical names are not independently verified."
            }
            let status: String
            if o.frames == 0 || o.activeSamples == 0 || value == nil {
                status = "inconclusive"; note = "No selected-device activity or required telemetry/dimensions unavailable."
            } else if qualityProblems > 0 {
                status = "inconclusive"; note = "Capture has gaps, regressing timestamps, invalid samples or duplicate IDs; inspect quality first."
            } else if let value {
                status = (minimum ? value >= check.value : value <= check.value) ? "pass" : "fail"
            } else { status = "inconclusive" }
            return ProbeResult(metric: check.metric.rawValue, expected: check.value, observed: value, status: status, detail: note)
        }
    }
}
