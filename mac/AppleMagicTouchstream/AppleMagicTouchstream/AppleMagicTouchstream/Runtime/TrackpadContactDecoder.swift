import Foundation
import OpenMultitouchSupport

/// Recovered Compact V7 integer conversions, independently checked against the
/// installed framework oracle. No private function addresses are used by the app.
struct CompactV7Scalars {
    private static func square(_ value: Int64) -> Int64 { value * value }
    private static func smallRadius(_ value: Int64, bias: UInt32) -> Int {
        let squared = UInt64(square(value * 1024 - 76800)) >> 10
        // Preserve the native36-bit coefficient and narrowing/shift order.
        let curved = UInt32(truncatingIfNeeded: (squared &* 0xfffffffd8) >> 10)
        return Int((curved &+ bias) >> 10)
    }
    static func major(_ byte: UInt8) -> Int {
        let v = Int64(byte)
        if v == 0 { return 0 }
        if v < 50 { return smallRadius(v, bias: 0xb5400) }
        if v <= 169 { return Int((UInt32(truncatingIfNeeded: v << 21) &+ 0x25800000) >> 20) }
        let curved = UInt32(truncatingIfNeeded: square(v * 1024 - 0x29800) >> 12)
        return Int((curved &+ 0xea000) >> 10)
    }
    static func minor(_ byte: UInt8) -> Int {
        let v = Int64(byte)
        if v == 0 { return 0 }
        if v < 50 { return smallRadius(v, bias: 0x9c400) }
        if v <= 149 { return Int((UInt32(truncatingIfNeeded: v << 21) &+ 0x1f400000) >> 20) }
        let curved = UInt32(truncatingIfNeeded: ((square(v * 1024 - 0x228f0) >> 10) * 0x57) >> 10)
        return Int((curved &+ 0xc50f0) >> 10)
    }
    static func total(_ byte: UInt8) -> Int {
        let v = Int64(byte)
        if v == 0 { return 0 }
        if v <= 149 { return Int((v * 0x28f5) >> 10) }
        let curved = UInt32(truncatingIfNeeded: ((square(v * 1024 - 0x1bfee) >> 10) * 0x8a) >> 10)
        return Int((curved &+ 0x14f568) >> 10)
    }
    static func pressure(_ byte: UInt8) -> Int {
        let v = Int64(byte)
        if v < 128 { return Int(v * 2) }
        let curved = UInt32(truncatingIfNeeded: square(v * 1024 - 0x1827b) >> 15)
        return Int((curved &+ 0x3827b) >> 10)
    }
    static func density(total: Int, major: Int, minor: Int) -> Int {
        // Parameters600/430 read from initialized native family0x81 state on both pads.
        let root = max(600, Int(Double(max(600, major) * max(600, minor)).squareRoot()))
        return Int(Int16(truncatingIfNeeded: total * 400 / (root - 430)))
    }
}

struct MagicTrackpadPacket {
    let contacts: [OMSRawTouch]
    let buttons: UInt8
    let sensorTicks: UInt32
    static func decode(_ data: Data) -> Self? {
        let b = [UInt8](data)
        guard let id = b.first else { return nil }
        let offset: Int
        switch id { case 2: offset = 12; case 0x31: offset = 4; default: return nil }
        guard b.count >= offset, (b.count - offset) % 9 == 0,
              (b.count - offset) / 9 <= 15 else { return nil }
        let header = offset - 4
        let ticks = UInt32(b[header+1] >> 3) | UInt32(b[header+2]) << 5 | UInt32(b[header+3]) << 13
        func signed13(_ value: Int) -> Int { value & 0x1000 == 0 ? value : value - 0x2000 }
        var contacts: [OMSRawTouch] = []
        for i in stride(from: offset, to: b.count, by: 9) {
            let x = signed13(Int(b[i]) | (Int(b[i+1] & 0x1f) << 8))
            let y = signed13((Int(b[i+1]) >> 5) | (Int(b[i+2]) << 3) | (Int(b[i+3] & 3) << 11))
            let state = [OMSState.notTouching, .starting, .hovering, .making,
                         .touching, .breaking, .lingering, .leaving][Int(b[i+3] >> 5)]
            // Actual Sensor Surface Descriptor bounds on both tested pads, in native 0.01 units.
            let ax = min(7869, max(-7356, x * 2)), ay = min(9956, max(-174, y * 2 + 5000))
            let px = Float(ax + 7356) / 15225, py = Float(ay + 174) / 10130
            let finger = Int32((b[i+3] >> 2) & 7)
            let telemetry = OMSTouchTelemetry(fingerID: finger == 7 ? 12 : finger, handID: 1,
                velocityX: 0, velocityY: 0, absoluteX: Float(ax) / 100,
                absoluteY: Float(ay) / 100, absoluteVelocityX: 0, absoluteVelocityY: 0,
                sourceFrame: 0, sourceTimestamp: Double(ticks) / 1000,
                driverKit: OMSDriverKitTelemetry(contactBytes: Array(b[i..<(i+9)]), velocityAvailable: false,
                    conversionVersion: 2, sensorTicks: ticks, reportBytes: b))
            let major = CompactV7Scalars.major(b[i+4]), minor = CompactV7Scalars.minor(b[i+5])
            let total = CompactV7Scalars.total(b[i+6])
            contacts.append(OMSRawTouch(id: Int32(b[i+8] & 15),
                posX: px, posY: py, total: Float(total) / 256,
                pressure: Float(CompactV7Scalars.pressure(b[i+7])),
                majorAxis: Float(major) / 100, minorAxis: Float(minor) / 100,
                angle: Float(b[i+8] >> 5) * Float.pi / 8,
                density: Float(UInt16(truncatingIfNeeded: CompactV7Scalars.density(total: total, major: major, minor: minor))) / 256,
                state: state, telemetry: telemetry))
        }
        return Self(contacts: contacts, buttons: b[1] & 3, sensorTicks: ticks)
    }
}

/// Reconstruct the native quantized binary velocity using the sensor clock.
/// Monotonic arrival time remains a safety guard, not the velocity denominator.
struct DriverContactEstimator {
    private struct Sample { let absoluteX: Float; let absoluteY: Float; let time: Double; let state: OMSState }
    private struct Clock { var ticks: UInt32; var wraps: UInt64 = 0 }
    private var clocks: [UInt64: Clock] = [:]
    private var previous: [UInt64: [Int32: Sample]] = [:]
    mutating func reset() { previous.removeAll(keepingCapacity: true); clocks.removeAll(keepingCapacity: true) }
    mutating func reset(device: UInt64) { previous[device] = nil; clocks[device] = nil }
    mutating func process(device: UInt64, time: Double, sequence: UInt64, contacts: [OMSRawTouch], sensorTicks: UInt32? = nil) -> [OMSRawTouch] {
        let old = previous[device] ?? [:]
        var next: [Int32: Sample] = [:]
        let ticks = sensorTicks ?? contacts.first?.telemetry?.driverKit?.sensorTicks
        var sensorTime: Double?
        if let ticks {
            var clock = clocks[device] ?? Clock(ticks: ticks)
            if ticks < clock.ticks { clock.wraps += 0x200000 }
            clock.ticks = ticks; clocks[device] = clock
            sensorTime = Double(clock.wraps + UInt64(ticks)) / 1000
        }
        let result = contacts.map { c -> OMSRawTouch in
            guard let t = c.telemetry, let raw = t.driverKit else { return c }
            let sourceTime = sensorTime ?? time
            let p = old[c.id]
            let dt = sourceTime - (p?.time ?? sourceTime)
            let activeVelocity = c.state == .touching || c.state == .breaking || c.state == .lingering
            let extra = raw.contactBytes.count == 9 && raw.contactBytes[8] & 16 != 0
            var ix = 0, iy = 0
            let available = p != nil && dt > 0 && dt < 0.15 && activeVelocity && !extra
            if available, let p {
                func quantize(_ delta: Float) -> Int {
                    let value = Double(delta * 8) / dt
                    return value.isFinite ? min(32767, max(-32768, Int(value.rounded(.towardZero)))) : 0
                }
                // Native velocity uses the current un-clipped binary position against
                // the previous clipped callback position, including at sensor edges.
                let b = raw.contactBytes
                func signed13(_ value: Int) -> Int { value & 4096 == 0 ? value : value - 8192 }
                let x = signed13(Int(b[0]) | Int(b[1] & 31) << 8)
                let y = signed13(Int(b[1] >> 5) | Int(b[2]) << 3 | Int(b[3] & 3) << 11)
                ix = quantize(Float(x * 2) / 100 - p.absoluteX)
                iy = quantize(Float(y * 2 + 5000) / 100 - p.absoluteY)
                // Native zero-vector sentinel avoidance is observable in the OMS callback.
                if ix == 0 && iy == 0 { ix = 1 }
            }
            let state: OMSState = c.state == .notTouching && p != nil && dt < 0.04 && dt >= 0
                && (p?.state == .making || p?.state == .touching) ? .leaving : c.state
            if state != .notTouching && state != .leaving {
                next[c.id] = Sample(absoluteX: t.absoluteX, absoluteY: t.absoluteY, time: sourceTime, state: state)
            }
            let avx = Float(ix) * 0.125, avy = Float(iy) * 0.125
            // Match native float32 -> float64 -> float32 operation order.
            let vx = Float(Double(Float(ix * 2) / 160) * 1000 / 15225)
            let vy = Float(Double(Float(iy * 2) / 160) * 1000 / 10130)
            let telemetry = OMSTouchTelemetry(fingerID: t.fingerID, handID: t.handID,
                velocityX: vx, velocityY: vy, absoluteX: t.absoluteX, absoluteY: t.absoluteY,
                absoluteVelocityX: avx, absoluteVelocityY: avy,
                sourceFrame: Int32(truncatingIfNeeded: sequence), sourceTimestamp: sourceTime,
                driverKit: OMSDriverKitTelemetry(contactBytes: raw.contactBytes, velocityAvailable: available,
                    conversionVersion: 2, sensorTicks: raw.sensorTicks, reportBytes: raw.reportBytes))
            return OMSRawTouch(id: c.id, posX: c.posX, posY: c.posY, total: c.total,
                pressure: c.pressure, majorAxis: c.majorAxis, minorAxis: c.minorAxis,
                angle: c.angle, density: c.density, state: state, telemetry: telemetry)
        }
        previous[device] = next
        return result
    }
}

/// Fixed-size timer-published diagnostic stream; no user-client entitlement needed.
struct DriverStreamRecord {
    let sequence: UInt64
    let timestamp: Double
    let payload: Data
    static let stride = 176
    static func decodeBatch(_ data: Data) -> [Self]? {
        guard data.count == stride * 64 else { return nil }
        func number(_ offset: Int, _ count: Int) -> UInt64 {
            (0..<count).reduce(0) { $0 | (UInt64(data[offset + $1]) << ($1 * 8)) }
        }
        var records: [Self] = []
        for offset in Swift.stride(from: 0, to: data.count, by: stride) {
            let seq = number(offset, 8)
            if seq == 0 { continue }
            let length = Int(number(offset + 16, 4))
            guard (4...148).contains(length) else { return nil }
            let payload = data.subdata(in: (offset + 24)..<(offset + 24 + length))
            guard UInt64(payload[0]) == number(offset + 20, 4) else { return nil }
            records.append(Self(sequence: seq, timestamp: Double(number(offset + 8, 8)) / 1e9, payload: payload))
        }
        return records.sorted { $0.sequence < $1.sequence }
    }
}

struct DriverStreamCursor {
    private(set) var session: UInt64 = 0
    private(set) var lastSequence: UInt64 = 0
    mutating func take(session: UInt64, records: [DriverStreamRecord]) -> (records: [DriverStreamRecord], discontinuity: Bool) {
        let changed = self.session != session
        if changed { self.session = session; lastSequence = 0 }
        let fresh = records.filter { $0.sequence > lastSequence }
        let gap = fresh.first.map { $0.sequence != lastSequence + 1 } ?? false
        if let last = fresh.last { lastSequence = last.sequence }
        return (fresh, changed || gap)
    }
}

