import OpenMultitouchSupport

/// Reserve enabled multi-finger candidates or a force press before keyboard release emits taps.
/// Reservation is per pad, includes the all-up frame and survives added/lifted fingers.
/// Invalid/failed candidates stay reserved rather than falling back to typing.
struct GestureKeyboardArbitration {
    private var reserved: Set<UInt64> = []
    mutating func reset() { reserved.removeAll(keepingCapacity: true) }
    mutating func process(device: UInt64, activeCount: Int, forceClick: Bool = false, enabled: (GestureTrigger) -> Bool) -> Bool {
        if activeCount == 0 { return reserved.remove(device) != nil }
        if reserved.contains(device) { return true }
        if forceClick { reserved.insert(device); return true }
        let candidate: Bool
        switch activeCount {
        case 1: candidate = false
        case 2: candidate = enabled(.twoFingerMove) || enabled(.twoFingerTap) || enabled(.twoFingerPinch)
        case 3: candidate = enabled(.threeFingerMove) || enabled(.threeFingerTap) || enabled(.thumbTwoTap)
        case 4: candidate = enabled(.fourFingerMove)
        default: candidate = false
        }
        if candidate { reserved.insert(device) }
        return candidate
    }
}
