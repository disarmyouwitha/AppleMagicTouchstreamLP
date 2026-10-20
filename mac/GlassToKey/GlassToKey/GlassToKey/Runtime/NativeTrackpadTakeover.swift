import Combine
import Foundation
import OpenMultitouchSupport
import SwiftUI

@MainActor
protocol NativeTakeoverBackend: AnyObject {
    func begin(deviceIDs: [UInt64]) -> Bool
    func end()
    var status: [String: Any] { get }
}

@MainActor
private final class OMSNativeTakeoverBackend: NativeTakeoverBackend {
    func begin(deviceIDs: [UInt64]) -> Bool { OMSManager.shared.beginNativeTakeover(deviceIDs: deviceIDs) }
    func end() { OMSManager.shared.endNativeTakeover() }
    var status: [String: Any] { OMSManager.shared.nativeTakeoverStatus }
}

/// Owns only native input routing. The app retains its existing keyboard engine.
@MainActor
final class NativeTrackpadTakeover: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var isReleasing = false
    @Published var releaseShortcutRegistered = false
    @Published private(set) var status = "Off. Take over the currently selected trackpads."
    var hasOwnership: Bool { isActive || isReleasing }
    var onOwnershipChanged: ((Bool) -> Void)?
    var beforeRelease: (() async -> Void)?
    var afterRelease: (() async -> Void)?
    private let backend: any NativeTakeoverBackend
    private var timer: Timer?
    private var releaseTask: Task<Void, Never>?

    init(backend: (any NativeTakeoverBackend)? = nil) {
        self.backend = backend ?? OMSNativeTakeoverBackend()
    }

    func start(devices: [OMSDeviceInfo]) {
        start(deviceIDs: devices.map(\.deviceIDNumeric))
    }

    func start(deviceIDs: [UInt64]) {
        guard !hasOwnership else { return }
        _ = backend.begin(deviceIDs: Array(Set(deviceIDs)).sorted())
        updateStatus()
        onOwnershipChanged?(hasOwnership)
        if isActive {
            timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.updateStatus() }
            }
            if let timer { RunLoop.main.add(timer, forMode: .common) }
        }
    }

    func release() async {
        if let releaseTask { await releaseTask.value; return }
        guard isActive else { return }
        isReleasing = true
        let task = Task { @MainActor [self] in
            // Flush held/repeating keyboard output before changing native routing.
            await beforeRelease?()
            backend.end()
            updateStatus()
            await afterRelease?()
            releaseTask = nil
            isReleasing = false
            onOwnershipChanged?(hasOwnership)
        }
        releaseTask = task
        await task.value
    }

    private func updateStatus() {
        let snapshot = backend.status
        let previous = isActive
        isActive = snapshot["active"] as? Bool ?? false
        status = snapshot["message"] as? String ?? "Native takeover unavailable."
        if previous && !isActive {
            timer?.invalidate()
            timer = nil
            if !isReleasing { onOwnershipChanged?(false) }
        }
    }
}

struct NativeTakeoverControls: View {
    @ObservedObject var control: NativeTrackpadTakeover
    let selected: [OMSDeviceInfo]
    let unavailable: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button("Trackpad Takeover") { control.start(devices: selected) }
                .fixedSize()
                .disabled(unavailable || selected.isEmpty || control.hasOwnership)
            Button("Release Trackpads") { Task { await control.release() } }
                .fixedSize()
                .disabled(!control.isActive || control.isReleasing)
            Text(control.status + (control.hasOwnership && control.releaseShortcutRegistered ? " Press ⌃⌥R to release" : ""))
                .font(.caption)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}
