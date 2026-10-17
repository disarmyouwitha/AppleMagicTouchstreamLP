import AppKit
import SwiftUI
import OpenMultitouchSupport

/// Raw-touch workspace for future FingerWorks gesture and chord experiments.
struct ContentView: View {
    @ObservedObject var viewModel: ContentViewModel
    static let trackpadWidthMM: CGFloat = 160
    static let trackpadHeightMM: CGFloat = 114.9
    static let displayScale: CGFloat = 2.7
    @State private var showTouchTelemetry = true
    @State private var showContactPaths = true
    @State private var showInspector = false
    @State private var leftPeakPressure = 0
    @State private var rightPeakPressure = 0
    @State private var replayScrubValue: Double = 0
    @State private var replayScrubInProgress = false

    init(viewModel: ContentViewModel = ContentViewModel()) { self.viewModel = viewModel }

    private var size: CGSize {
        CGSize(width: Self.trackpadWidthMM * Self.displayScale,
               height: Self.trackpadHeightMM * Self.displayScale)
    }

    private var surfaceSnapshot: TrackpadSurfaceSnapshot {
        var snapshot = TrackpadSurfaceSnapshot.empty
        snapshot.trackpadSize = size
        snapshot.spacing = 16
        snapshot.showDetailed = true
        snapshot.showTouchTelemetry = showTouchTelemetry
        snapshot.showContactPaths = showContactPaths
        snapshot.replayModeEnabled = viewModel.replayTimelineState != nil
        return snapshot
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("FingerWorks Playground").font(.title2).bold()
            Text("Raw contacts only · no GTK gestures, chords, or keyboard layout")
                .foregroundStyle(.secondary)
            DevicesSectionView(availableDevices: viewModel.availableDevices,
                leftDevice: viewModel.leftDevice, rightDevice: viewModel.rightDevice,
                onSelectLeft: { device in
                    viewModel.selectLeftDevice(device)
                    UserDefaults.standard.set(device?.deviceID ?? "", forKey: GlassToKeyDefaultsKeys.leftDeviceID)
                },
                onSelectRight: { device in
                    viewModel.selectRightDevice(device)
                    UserDefaults.standard.set(device?.deviceID ?? "", forKey: GlassToKeyDefaultsKeys.rightDeviceID)
                },
                onRefresh: { viewModel.refreshDevicesAndListeners() })
            if let state = viewModel.replayTimelineState { replayTimelineView(state) }
            HStack {
                Toggle("Inspect touch data", isOn: $showTouchTelemetry)
                Toggle("Contact paths", isOn: $showContactPaths)
                Button("Live values…") { showInspector = true }
                    .popover(isPresented: $showInspector) { TouchTelemetryInspector(viewModel: viewModel) }
            }.toggleStyle(.checkbox)
            HStack {
                Text("Left Trackpad · peak: \(leftPeakPressure)").monospacedDigit().frame(width: size.width, alignment: .leading)
                Text("Right Trackpad · peak: \(rightPeakPressure)").monospacedDigit().frame(width: size.width, alignment: .leading)
            }
            TrackpadSurfaceRepresentable(snapshot: surfaceSnapshot, viewModel: viewModel,
                selectionHandler: { _ in }, peakPressureHandler: { left, right in
                    leftPeakPressure = left
                    rightPeakPressure = right
                })
                .frame(width: size.width * 2 + 16, height: size.height)
            Text("1 Thumb · 2 Index · 3 Middle · 4 Ring · 5 Pinky · 6 Palm. H = hand ID.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minWidth: size.width * 2 + 48, minHeight: size.height + 240)
        .onReceive(viewModel.$replayTimelineState) { state in
            if let state, !replayScrubInProgress { replayScrubValue = max(state.currentTimeSeconds, 0) }
        }
    }

    private func replayTimelineView(
        _ state: ContentViewModel.ReplayTimelineState
    ) -> some View {
        let maxTime = max(state.durationSeconds, 0)
        let maxFrameIndex = max(state.frameCount - 1, 0)
        return HStack(spacing: 12) {
            Text("Replay")
                .font(.subheadline)
                .bold()
            Text(state.sourceName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Button(state.isPlaying ? "Pause" : "Play") {
                viewModel.toggleReplayPlayback()
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.frameCount == 0)
            Slider(
                value: Binding(
                    get: { replayScrubValue },
                    set: { replayScrubValue = $0 }
                ),
                in: 0...max(maxTime, 0.001),
                step: 0.01
            ) { editing in
                replayScrubInProgress = editing
                guard !editing else { return }
                Task {
                    try? await viewModel.scrubReplay(to: replayScrubValue)
                }
            }
            .disabled(state.frameCount == 0 || state.isPlaying)
            Text("\(formatReplayTime(state.currentTimeSeconds))/\(formatReplayTime(state.durationSeconds))")
                .font(.caption.monospacedDigit())
                .frame(width: 150, alignment: .trailing)
            Text("\(max(state.currentFrameIndex, 0))/\(maxFrameIndex)")
                .font(.caption.monospacedDigit())
                .frame(width: 80, alignment: .trailing)
            Button("Exit Replay") {
                Task {
                    await viewModel.endReplaySession()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.blue.opacity(0.08))
        )
    }
    private func formatReplayTime(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let totalMilliseconds = Int((clamped * 1_000).rounded())
        let minutes = totalMilliseconds / 60_000
        let secondsComponent = (totalMilliseconds / 1_000) % 60
        let millisecondsComponent = totalMilliseconds % 1_000
        return String(
            format: "%02d:%02d.%03d",
            minutes,
            secondsComponent,
            millisecondsComponent
        )
    }
    private struct DevicesSectionView: View {
        let availableDevices: [OMSDeviceInfo]
        let leftDevice: OMSDeviceInfo?
        let rightDevice: OMSDeviceInfo?
        let onSelectLeft: (OMSDeviceInfo?) -> Void
        let onSelectRight: (OMSDeviceInfo?) -> Void
        let onRefresh: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                if availableDevices.isEmpty {
                    Text("No trackpads detected.")
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Left Trackpad")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("", selection: Binding(
                                get: { leftDevice },
                                set: { device in
                                    onSelectLeft(device)
                                }
                            )) {
                                Text("None")
                                    .tag(nil as OMSDeviceInfo?)
                                ForEach(availableDevices, id: \.self) { device in
                                    Text("\(device.deviceName) (ID: \(device.deviceID))")
                                        .tag(device as OMSDeviceInfo?)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .pickerStyle(MenuPickerStyle())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Right Trackpad")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("", selection: Binding(
                                get: { rightDevice },
                                set: { device in
                                    onSelectRight(device)
                                }
                            )) {
                                Text("None")
                                    .tag(nil as OMSDeviceInfo?)
                                ForEach(availableDevices, id: \.self) { device in
                                    Text("\(device.deviceName) (ID: \(device.deviceID))")
                                        .tag(device as OMSDeviceInfo?)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .pickerStyle(MenuPickerStyle())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button(action: {
                            onRefresh()
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .imageScale(.medium)
                        }
                        .buttonStyle(.bordered)
                        .help("Refresh trackpad list")
                        .padding(.top, 20)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.05))
            )
        }
    }
    private struct TouchTelemetryInspector: View {
        @ObservedObject var viewModel: ContentViewModel
        @State private var frozenSnapshot: ContentViewModel.TouchSnapshot?
        @State private var freezePending = false
        @State private var freezeTask: Task<Void, Never>?
        @State private var copyError: String?

        var body: some View {
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                let snapshot = frozenSnapshot ?? viewModel.snapshotTouchData()
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Touch data inspector").font(.headline)
                        Spacer()
                        Text(frozenSnapshot == nil ? "Live · 10 Hz" : "Frozen")
                            .foregroundStyle(.secondary)
                        Button(frozenSnapshot == nil ? "Freeze" : "Resume") {
                            freezeTask?.cancel()
                            freezePending = false
                            frozenSnapshot = frozenSnapshot == nil ? viewModel.snapshotTouchData() : nil
                        }
                        Button(freezePending ? "Waiting…" : "Freeze in 3s") {
                            freezePending = true
                            frozenSnapshot = nil
                            freezeTask = Task { @MainActor in
                                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                                frozenSnapshot = viewModel.snapshotTouchData()
                                freezePending = false
                            }
                        }
                        .disabled(freezePending)
                        Button("Copy JSON") { copySnapshot(snapshot) }
                    }
                    Text("Finger labels: 1 Thumb, 2 Index, 3 Middle, 4 Ring, 5 Pinky, 6 Palm. Other codes are unknown; velocity arrows show direction only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let copyError { Text(copyError).foregroundStyle(.red) }
                    ScrollView {
                        HStack(alignment: .top, spacing: 16) {
                            contactColumn("Left trackpad", touches: snapshot.left)
                            contactColumn("Right trackpad", touches: snapshot.right)
                        }
                    }
                    Text("New Capture recordings retain these fields. Older recordings show unavailable. Freeze in 3s lets you put both hands back on the pads.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(width: 820, height: 480)
            }
            .onDisappear { freezeTask?.cancel() }
        }

        private func contactColumn(_ title: String, touches: [OMSTouchData]) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(title) · \(touches.count) contacts").font(.headline)
                if touches.isEmpty {
                    Text("No contacts").foregroundStyle(.secondary)
                }
                ForEach(Array(touches.enumerated()), id: \.offset) { _, touch in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Contact #\(touch.id) · \(touch.state.rawValue)").fontWeight(.semibold)
                        Text(String(format: "Normalized position  % .4f, % .4f", touch.position.x, touch.position.y))
                        if let raw = touch.telemetry {
                            Text("\(raw.fingerName) · Finger ID \(raw.fingerID)    Hand ID \(raw.handID)")
                            Text(String(format: "Normalized velocity  % .4f, % .4f", raw.velocityX, raw.velocityY))
                            Text(String(format: "Absolute position    % .4f, % .4f", raw.absoluteX, raw.absoluteY))
                            Text(String(format: "Absolute velocity    % .4f, % .4f", raw.absoluteVelocityX, raw.absoluteVelocityY))
                            Text(String(format: "Frame %d · source time %.6f", raw.sourceFrame, raw.sourceTimestamp))
                        } else {
                            Text("Identity / velocity / absolute data unavailable")
                                .foregroundStyle(.secondary)
                        }
                        Text(String(format: "Axes %.3f / %.3f · angle %.3f", touch.axis.major, touch.axis.minor, touch.angle))
                        Text(String(format: "Total %.3f · density %.3f · pressure %.3f", touch.total, touch.density, touch.pressure))
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func copySnapshot(_ snapshot: ContentViewModel.TouchSnapshot) {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(["left": snapshot.left, "right": snapshot.right])
                guard let text = String(data: data, encoding: .utf8) else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copyError = nil
            } catch {
                copyError = "Could not copy contact data: \(error.localizedDescription)"
            }
        }
    }
}
