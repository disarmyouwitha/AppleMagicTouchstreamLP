import Combine
import Foundation
import OpenMultitouchSupport
import SwiftUI

@MainActor
protocol NativeTakeoverBackend: AnyObject {
    func update(deviceIDs: [UInt64]) -> Bool
    func end()
    var status: [String: Any] { get }
}

@MainActor
private final class OMSNativeTakeoverBackend: NativeTakeoverBackend {
    func update(deviceIDs: [UInt64]) -> Bool { OMSManager.shared.updateNativeTakeover(deviceIDs: deviceIDs) }
    func end() { OMSManager.shared.endNativeTakeover() }
    var status: [String: Any] { OMSManager.shared.nativeTakeoverStatus }
}

/// Persistent opt-in, with native ownership independent of the configuration window.
/// Keyboard output is drained before every routing transition, including selection edits.
@MainActor
final class NativeTrackpadTakeover: ObservableObject {
    static let defaultsKey = "AppleMagicTouchstream.nativeTrackpadTakeoverEnabled"
    @Published private(set) var enabled: Bool
    @Published private(set) var outputArmed = false
    @Published private(set) var isActive = false
    @Published private(set) var isReleasing = false
    @Published var releaseShortcutRegistered = false
    @Published private(set) var status = "Off. Take over the currently selected trackpads."
    var hasOwnership: Bool { isActive || isReleasing }
    var onOwnershipChanged: ((Bool) -> Void)?
    var beforeRelease: (() async -> Void)?
    var afterRelease: (() async -> Void)?
    private let backend: any NativeTakeoverBackend
    private let defaults: UserDefaults
    private var selection: Set<UInt64> = []
    private var suspensions: Set<String> = []
    private var timer: Timer?
    private var operation: Task<Bool, Never>?

    init(backend: (any NativeTakeoverBackend)? = nil, defaults: UserDefaults = .standard) {
        self.backend = backend ?? OMSNativeTakeoverBackend()
        self.defaults = defaults
        enabled = defaults.bool(forKey: Self.defaultsKey)
    }

    func setEnabled(_ value: Bool) async {
        enabled = value
        defaults.set(value, forKey: Self.defaultsKey)
        await waitForOperation()
        _ = await transition(to: enabled && suspensions.isEmpty ? selection : [])
    }

    /// Commit UI/engine selection only after native preparation succeeds. Failed
    /// additions retain the previous selection and the bridge rolls ownership back.
    @discardableResult
    func updateSelection(deviceIDs: [UInt64], commit: @escaping @MainActor () -> Void = {}) async -> Bool {
        let next = Set(deviceIDs)
        await waitForOperation()
        guard !Task.isCancelled else { return false }
        return await transition(to: enabled && suspensions.isEmpty ? next : []) { [self] in
            selection = next
            commit()
        }
    }

    /// Emergency release is a persistent opt-out; lifecycle suspension is not.
    func release() async { await setEnabled(false) }

    @discardableResult
    func suspend(_ reason: String) async -> Bool {
        suspensions.insert(reason)
        await waitForOperation()
        return await transition(to: [])
    }

    func resume(_ reason: String) async {
        suspensions.remove(reason)
        await waitForOperation()
        _ = await transition(to: enabled && suspensions.isEmpty ? selection : [])
    }

    var ownedDeviceIDs: Set<UInt64> {
        Set((backend.status["deviceIDs"] as? [NSNumber] ?? []).map(\.uint64Value))
    }

    private func waitForOperation() async {
        while let operation { _ = await operation.value }
    }

    private func transition(to target: Set<UInt64>, commit: @escaping @MainActor () -> Void = {}) async -> Bool {
        // Main-actor methods can interleave while keyboard cleanup awaits. Share
        // the current operation, then serialize the next request behind it.
        while let operation { _ = await operation.value }
        if ownedDeviceIDs == target && (target.isEmpty || isActive) { commit(); return true }
        isReleasing = true
        outputArmed = false
        onOwnershipChanged?(true) // Pause auto-resync during acquisition as well.
        let task = Task { @MainActor [self] in
            await beforeRelease?()
            let succeeded: Bool
            if target.isEmpty {
                backend.end()
                succeeded = ownedDeviceIDs.isEmpty
            } else {
                succeeded = backend.update(deviceIDs: target.sorted())
            }
            updateStatus()
            outputArmed = succeeded && ownedDeviceIDs == target && !target.isEmpty
            if succeeded && ownedDeviceIDs == target { commit() }
            await afterRelease?()
            isReleasing = false
            operation = nil
            onOwnershipChanged?(hasOwnership)
            return succeeded && ownedDeviceIDs == target
        }
        operation = task
        return await task.value
    }

    private func updateStatus() {
        let snapshot = backend.status
        let wasActive = isActive
        isActive = snapshot["active"] as? Bool ?? false
        status = snapshot["message"] as? String ?? "Native takeover unavailable."
        if isActive && timer == nil {
            timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.updateStatus() }
            }
            if let timer { RunLoop.main.add(timer, forMode: .common) }
        } else if !isActive {
            timer?.invalidate()
            timer = nil
        }
        if wasActive && !isActive && !isReleasing {
            outputArmed = false
            onOwnershipChanged?(false)
        }
    }
}

struct NativeTakeoverControls: View {
    @ObservedObject var control: NativeTrackpadTakeover
    let unavailable: Bool

    var body: some View {
        HStack(spacing: 12) {
            Toggle("Trackpad Takeover", isOn: Binding(
                get: { control.enabled },
                set: { value in Task { await control.setEnabled(value) } }
            ))
            .toggleStyle(.checkbox)
            .fixedSize()
            .disabled(unavailable || control.isReleasing)
            Text(control.isActive && control.outputArmed && control.status.hasPrefix("Trackpad Takeover active")
                ? "Trackpad Takeover active on \(control.ownedDeviceIDs.count) trackpad(s), use 2-fingers to move mouse." + (control.releaseShortcutRegistered ? " Press ⌃⌥R to release." : "")
                : control.status + (control.hasOwnership && control.releaseShortcutRegistered ? " Press ⌃⌥R to release." : ""))
                .font(.caption)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
