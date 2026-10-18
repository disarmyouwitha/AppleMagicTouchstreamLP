import Foundation

// Missing receivers are failures only if they were not deliberately handed off.
// Keep this state independent of how many pads the user connected/selected.
struct ReceiverWatchdog {
    struct Receiver {
        var serial: String
        var opened: Bool
        var handoffRequested: Bool
    }
    private var observed: Set<String> = []
    private var handedOff: Set<String> = []
    private var disconnected: Set<String> = []
    mutating func shouldRemove(after receivers: [Receiver], physicallyConnected: Set<String>? = nil) -> Bool {
        let present = Set(receivers.map(\.serial))
        if let physicallyConnected {
            disconnected.formUnion(observed.subtracting(physicallyConnected))
        }
        for receiver in receivers {
            observed.insert(receiver.serial)
            if receiver.opened { disconnected.remove(receiver.serial) }
            if receiver.handoffRequested { handedOff.insert(receiver.serial) }
            else {
                handedOff.remove(receiver.serial)
                if !receiver.opened && !disconnected.contains(receiver.serial) { return true }
            }
        }
        return !observed.subtracting(present).subtracting(handedOff).subtracting(disconnected).isEmpty
    }
}
