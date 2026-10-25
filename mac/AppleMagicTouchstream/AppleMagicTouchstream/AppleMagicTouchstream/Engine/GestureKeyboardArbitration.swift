import OpenMultitouchSupport

/// Reserve enabled multi-finger candidates or a force press before keyboard release emits taps.
/// Reservation is per pad, includes the all-up frame and survives added/lifted fingers.
/// Invalid/failed candidates stay reserved rather than falling back to typing.
struct GestureKeyboardArbitration {
    private var reserved: Set<UInt64> = []
    mutating func reset() { reserved.removeAll(keepingCapacity: true) }
    mutating func reset(device: UInt64) { reserved.remove(device) }
    mutating func process(device: UInt64, activeCount: Int, forceClick: Bool = false, holdCandidate: Bool = false, enabled: (GestureTrigger) -> Bool) -> Bool {
        if activeCount == 0 { return reserved.remove(device) != nil }
        if reserved.contains(device) { return true }
        if forceClick || holdCandidate { reserved.insert(device); return true }
        let candidate: Bool
        switch activeCount {
        case 1: candidate = false
        case 2: candidate = enabled(.twoFingerMove) || enabled(.twoFingerTap) || enabled(.twoFingerPinch) || enabled(.twoFingerSpread)
        case 3: candidate = enabled(.threeFingerMove) || enabled(.threeFingerTap) || enabled(.thumbTwoTap) || enabled(.threeFingerPinch) || enabled(.threeFingerSpread)
        case 4: candidate = enabled(.fourFingerTap) || enabled(.fourFingerMove) || enabled(.fourFingerPinch) || enabled(.fourFingerSpread)
        case 5: candidate = enabled(.fiveFingerPinch) || enabled(.fiveFingerSpread)
        default: candidate = false
        }
        if candidate { reserved.insert(device) }
        return candidate
    }
}
