import SwiftUI
import ServiceManagement
import OpenMultitouchSupport

@MainActor
final class GesturePadController: ObservableObject {
    let viewModel: ContentViewModel
    private var isRunning = false
    init(viewModel: ContentViewModel = ContentViewModel()) { self.viewModel = viewModel }
    func start() {
        guard !isRunning else { return }
        OMSManager.shared.isTimestampEnabled = false
        configureFromDefaults()
        viewModel.start()
        isRunning = true
    }

    func startATPCapture(to outputURL: URL) throws {
        try viewModel.startATPCapture(to: outputURL)
    }

    func stopATPCapture() async throws -> Int {
        try await viewModel.stopATPCapture()
    }

    func replayATPCapture(from inputURL: URL) async throws -> Int {
        try await viewModel.replayATPCapture(from: inputURL)
    }

    func beginReplaySession(from inputURL: URL) async throws {
        try await viewModel.beginReplaySession(from: inputURL)
    }

    func endReplaySession() async {
        await viewModel.endReplaySession()
    }

    func scrubReplay(to timeSeconds: Double) async throws {
        try await viewModel.scrubReplay(to: timeSeconds)
    }

    func toggleReplayPlayback() {
        viewModel.toggleReplayPlayback()
    }

    var isATPCaptureActive: Bool {
        viewModel.isATPCaptureActive
    }

    var isATPReplayActive: Bool {
        viewModel.isATPReplayActive
    }

    private func configureFromDefaults() {
        viewModel.loadDevices()
        let size = CGSize(width: ContentView.trackpadWidthMM * ContentView.displayScale,
                          height: ContentView.trackpadHeightMM * ContentView.displayScale)
        let empty = ContentViewModel.Layout(keyRects: [], trackpadSize: size)
        viewModel.configureLayouts(leftLayout: empty, rightLayout: empty,
            leftLabels: [], rightLabels: [], trackpadSize: size,
            trackpadWidthMm: ContentView.trackpadWidthMM)
        let leftDeviceID = stringValue(forKey: GesturePadDefaultsKeys.leftDeviceID)
        let rightDeviceID = stringValue(forKey: GesturePadDefaultsKeys.rightDeviceID)
        if let leftDevice = deviceForID(leftDeviceID) {
            viewModel.selectLeftDevice(leftDevice)
        }
        if let rightDevice = deviceForID(rightDeviceID) {
            viewModel.selectRightDevice(rightDevice)
        }
        let autoResyncEnabled = UserDefaults.standard.bool(
            forKey: GesturePadDefaultsKeys.autoResyncMissingTrackpads
        )
        viewModel.setAutoResyncEnabled(autoResyncEnabled)
    }

    private func deviceForID(_ deviceID: String) -> OMSDeviceInfo? {
        guard !deviceID.isEmpty else { return nil }
        return viewModel.availableDevices.first { $0.deviceID == deviceID }
    }

    private func stringValue(forKey key: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? ""
    }
}

@MainActor
final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    private init() {}

    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    func setEnabled(_ enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            if enabled == isEnabled {
                return
            }
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        }
    }
}
