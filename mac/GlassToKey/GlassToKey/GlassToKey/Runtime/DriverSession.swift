import Foundation

/// Owner liveness is independent of device count. A bounded, single-use lease
/// bridges only an explicit Restart; ordinary Exit/crash still releases ownership.
struct DriverOwnerLease {
    private(set) var ownerPID: Int32
    private(set) var nonce: String?
    private(set) var expiresAt: Date?

    mutating func prepare(pid: Int32, nonce: String, now: Date) -> Bool {
        guard pid == ownerPID, UUID(uuidString: nonce) != nil else { return false }
        self.nonce = nonce; expiresAt = now.addingTimeInterval(20)
        return true
    }
    mutating func cancel(pid: Int32, nonce: String) {
        guard pid == ownerPID, self.nonce == nonce else { return }
        self.nonce = nil; expiresAt = nil
    }
    mutating func claim(pid: Int32, nonce: String, now: Date) -> Bool {
        guard pid > 1, pid != ownerPID, self.nonce == nonce,
              let expiresAt, now < expiresAt else { return false }
        ownerPID = pid; self.nonce = nil; self.expiresAt = nil
        return true
    }
    func shouldRelease(ownerAlive: Bool, now: Date) -> Bool {
        !ownerAlive && !(expiresAt.map { now < $0 } ?? false)
    }
}

struct DriverSessionDevice: Codable, Equatable, Sendable {
    let serial: String
    let transport: String
    let id: UInt64
    let index: Int
    let registryID: UInt64
    let name: String
}

struct DriverRestartSnapshot: Codable, Sendable {
    static let defaultsKey = TakeoverConfiguration.restartDefaultsKey
    let session: String
    let nonce: String
    let helperPID: Int32
    let ownerPID: Int32
    let expiresAt: Date
    let devices: [DriverSessionDevice]
    let synthesize: Bool
    var inventory: [DriverSessionDevice]? = nil
    var allowClick: Bool? = nil

    func isValid(session: String, nonce: String, now: Date) -> Bool {
        self.session == session && self.nonce == nonce && now < expiresAt &&
        UUID(uuidString: session) != nil && UUID(uuidString: nonce) != nil &&
        helperPID > 1 && ownerPID > 1 && devices.count <= 2 &&
        Set(devices.map(\.serial)).count == devices.count &&
        Set(devices.map(\.id)).count == devices.count &&
        devices.allSatisfy { !$0.serial.isEmpty && $0.id > 0 && $0.index >= 0 &&
            ["USB", "Bluetooth"].contains($0.transport) }
    }
}
