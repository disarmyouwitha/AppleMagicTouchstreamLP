import AppKit
import SwiftUI
import OpenMultitouchSupport

/// Raw-touch workspace for future FingerWorks gesture and chord experiments.
struct ContentView: View {
    @ObservedObject var hidBlackhole: HIDBlackholeExperiment
    @ObservedObject var viewModel: ContentViewModel
    static let trackpadWidthMM: CGFloat = 160
    static let trackpadHeightMM: CGFloat = 114.9
    static let displayScale: CGFloat = 2.7
    @State private var showTouchTelemetry = true
    @State private var showContactPaths = true
    @State private var leftPeakPressure = 0
    @State private var rightPeakPressure = 0
    @State private var replayScrubValue: Double = 0
    @State private var replayScrubInProgress = false

    init(viewModel: ContentViewModel, hidBlackhole: HIDBlackholeExperiment) {
        self.viewModel = viewModel
        self.hidBlackhole = hidBlackhole
    }

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
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 16) {
                Text("FingerWorks Playground").font(.title2).bold()
                DevicesSectionView(availableDevices: viewModel.availableDevices,
                    leftDevice: viewModel.leftDevice, rightDevice: viewModel.rightDevice,
                    onSelectLeft: { device in
                        viewModel.selectLeftDevice(device)
                        UserDefaults.standard.set(device?.deviceID ?? "", forKey: GesturePadDefaultsKeys.leftDeviceID)
                    },
                    onSelectRight: { device in
                        viewModel.selectRightDevice(device)
                        UserDefaults.standard.set(device?.deviceID ?? "", forKey: GesturePadDefaultsKeys.rightDeviceID)
                    },
                    onRefresh: {
                        if hidBlackhole.hasOpenHIDDevices { hidBlackhole.release(reason: "Trackpads refreshed") }
                        viewModel.refreshDevicesAndListeners()
                        synchronizeHIDTarget()
                    }, blackholeControls: { hidBlackholeControls }, touchControls: { touchDisplayControls })
                if let state = viewModel.replayTimelineState { replayTimelineView(state) }
                InlineTouchTelemetry(viewModel: viewModel) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 16) {
                            Text("Left Trackpad · peak: \(leftPeakPressure)").monospacedDigit().frame(width: size.width, alignment: .leading)
                            Text("Right Trackpad · peak: \(rightPeakPressure)").monospacedDigit().frame(width: size.width, alignment: .leading)
                        }
                        TrackpadSurfaceRepresentable(snapshot: surfaceSnapshot, viewModel: viewModel,
                            selectionHandler: { _ in }, peakPressureHandler: { left, right in
                                leftPeakPressure = left
                                rightPeakPressure = right
                            })
                            .frame(width: size.width * 2 + 16, height: size.height)
                    }
                }

            }
            .padding(16)
        }
        .frame(minWidth: size.width * 2 + 48, minHeight: size.height + 400)
        .onAppear { synchronizeHIDTarget() }
        .onChange(of: viewModel.leftDevice) { _ in synchronizeHIDTarget() }
        .onChange(of: viewModel.rightDevice) { _ in synchronizeHIDTarget() }
        .onDisappear { hidBlackhole.release(reason: "Config closed") }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            hidBlackhole.release(reason: "App quitting")
        }
        .onChange(of: viewModel.replayTimelineState != nil) { replaying in
            if replaying { hidBlackhole.release(reason: "Replay started") }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
            hidBlackhole.release(reason: "System sleeping")
        }
        .onReceive(viewModel.$replayTimelineState) { state in
            if let state, !replayScrubInProgress { replayScrubValue = max(state.currentTimeSeconds, 0) }
        }
    }

    private func synchronizeHIDTarget() {
        hidBlackhole.pointerIdentityProbe.stop()
        if hidBlackhole.hasOpenHIDDevices {
            hidBlackhole.release(reason: "Selected trackpads changed")
            guard !hidBlackhole.hasOpenHIDDevices else { return }
        }
        hidBlackhole.refresh()
        let selected = [viewModel.leftDevice, viewModel.rightDevice].compactMap { $0 }
        hidBlackhole.selectTrackpads(registryEntryIDs: selected.map(\.registryEntryID),
            touchDeviceIDs: Set(selected.map(\.deviceIDNumeric)))
    }

    private var touchDisplayControls: some View {
        HStack(spacing: 16) {
            Toggle("Inspect touch data", isOn: $showTouchTelemetry)
            Toggle("Contact paths", isOn: $showContactPaths)
        }
        .toggleStyle(.checkbox)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var hidBlackholeControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            TrackpadControlControls(control: hidBlackhole.pointerControl,
                unavailable: hidBlackhole.selectedGroupIDs.isEmpty || viewModel.replayTimelineState != nil,
                setEnabled: { enabled in
                    if enabled && !hidBlackhole.pointerControl.isActive { synchronizeHIDTarget() }
                    hidBlackhole.setEnabled(enabled)
                }, timedTest: {
                    if !hidBlackhole.pointerControl.isActive { synchronizeHIDTarget() }
                    hidBlackhole.startTimedTest()
                }, release: { hidBlackhole.release() })
            SingleInterfaceControls(experiment: hidBlackhole)
                .disabled(viewModel.replayTimelineState != nil)
            PointerIdentityControls(probe: hidBlackhole.pointerIdentityProbe) {
                hidBlackhole.release(reason: "Pointer identity test started")
                guard !hidBlackhole.hasOpenHIDDevices else { return }
                synchronizeHIDTarget()
                hidBlackhole.pointerIdentityProbe.start(selectedTrackpads:
                    hidBlackhole.groups.filter { hidBlackhole.selectedGroupIDs.contains($0.id) })
            }
            .disabled(viewModel.replayTimelineState != nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
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
    private struct DevicesSectionView<BlackholeControls: View, TouchControls: View>: View {
        let availableDevices: [OMSDeviceInfo]
        let leftDevice: OMSDeviceInfo?
        let rightDevice: OMSDeviceInfo?
        let onSelectLeft: (OMSDeviceInfo?) -> Void
        let onSelectRight: (OMSDeviceInfo?) -> Void
        let onRefresh: () -> Void
        @ViewBuilder let blackholeControls: () -> BlackholeControls
        @ViewBuilder let touchControls: () -> TouchControls

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                if availableDevices.isEmpty {
                    Text("No trackpads detected.")
                        .foregroundStyle(.secondary)
                    blackholeControls()
                    touchControls()
                } else {
                    HStack(alignment: .top, spacing: 10) {
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
                                    Text(device.selectionLabel)
                                        .tag(device as OMSDeviceInfo?)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .pickerStyle(MenuPickerStyle())
                            blackholeControls()
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
                                    Text(device.selectionLabel)
                                        .tag(device as OMSDeviceInfo?)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .pickerStyle(MenuPickerStyle())
                            touchControls()
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
    private struct InlineTouchTelemetry<Visualizer: View>: View {
        @ObservedObject var viewModel: ContentViewModel
        @ViewBuilder let visualizer: () -> Visualizer
        private let columnWidth: CGFloat = 300
        var body: some View {
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                let snapshot = viewModel.snapshotTouchData()
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 16) {
                        ScrollView(.vertical) {
                            contactColumn("Left trackpad", touches: snapshot.left)
                        }
                        .frame(width: columnWidth, height: 520)
                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
                        visualizer()
                        ScrollView(.vertical) {
                            contactColumn("Right trackpad", touches: snapshot.right)
                        }
                        .frame(width: columnWidth, height: 520)
                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
                    }

                }
                .padding(.vertical, 12)
            }
        }

        private func contactColumn(_ title: String, touches: [OMSTouchData]) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(title) · \(touches.count) contacts").font(.headline)
                if touches.isEmpty {
                    Text("No contacts").foregroundStyle(.secondary)
                }
                ForEach(Array(touches.enumerated()), id: \.offset) { _, touch in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("#\(touch.id) · \(touch.telemetry?.fingerName ?? "Unknown")").fontWeight(.semibold)
                            Spacer()
                            Text(String(format: "p: %.3f", touch.pressure)).fontWeight(.semibold)
                        }
                        Text("\(touch.telemetry.map { "Finger \($0.fingerID) · Hand \($0.handID)" } ?? "Identity unavailable") · \(touch.state.rawValue)")
                            .foregroundStyle(.secondary)
                        Text(String(format: "Position % .4f, % .4f", touch.position.x, touch.position.y))
                        if let raw = touch.telemetry {
                            Text(String(format: "Velocity % .4f, % .4f", raw.velocityX, raw.velocityY))
                        }
                        DisclosureGroup("Raw measurements") {
                            VStack(alignment: .leading, spacing: 3) {
                                if let raw = touch.telemetry {
                                    Text(String(format: "Absolute position % .4f, % .4f", raw.absoluteX, raw.absoluteY))
                                    Text(String(format: "Absolute velocity % .4f, % .4f", raw.absoluteVelocityX, raw.absoluteVelocityY))
                                    Text(String(format: "Frame %d · time %.6f", raw.sourceFrame, raw.sourceTimestamp))
                                } else {
                                    Text("Velocity / absolute data unavailable")
                                        .foregroundStyle(.secondary)
                                }
                                Text(String(format: "Axes %.3f / %.3f · angle %.3f", touch.axis.major, touch.axis.minor, touch.angle))
                                Text(String(format: "Total %.3f · density %.3f", touch.total, touch.density))
                            }
                        }
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .frame(width: columnWidth, alignment: .leading)
        }

    }
}

private struct PointerIdentityControls: View {
    @ObservedObject var probe: PointerIdentityProbe
    let start: () -> Void
    var body: some View {
        HStack {
            Button("Test pointer sources (40s)", action: start).disabled(probe.isObserving)
            if probe.isObserving { Button("Stop observer") { probe.stop() } }
            Text(probe.status).font(.caption).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TrackpadControlControls: View {
    @ObservedObject var control: SelectedTrackpadEventFilter
    let unavailable: Bool
    let setEnabled: (Bool) -> Void
    let timedTest: () -> Void
    let release: () -> Void
    @State private var threeFingerDrag: Bool? = GesturePadThreeFingerDragStatus.detected()
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
        HStack {
            Toggle("Control selected trackpads", isOn: Binding(get: { control.isActive }, set: { value in setEnabled(value) }))
                .disabled(unavailable)
            Button("30sec test", action: timedTest).disabled(unavailable)
            Button("Release Trackpads", action: release)
                .keyboardShortcut(.escape, modifiers: [.command]).disabled(!control.isActive)
            Text(control.status).font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        HStack {
            Toggle("Synthetic 2-finger pointer", isOn: $control.synthesizeTwoFingerPointer)
                .help("Generate pointer movement from exactly two contacts while control is enabled.")
            Toggle("macOS 3-finger drag", isOn: .constant(threeFingerDrag ?? false))
                .disabled(true)
                .help("Read-only macOS setting. Native drag events pass through.")
            Text(threeFingerDrag.map { $0 ? "On" : "Off" } ?? "Unknown").font(.caption)
            Button("Trackpad Options…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        }
        .onAppear { threeFingerDrag = GesturePadThreeFingerDragStatus.detected() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            threeFingerDrag = GesturePadThreeFingerDragStatus.detected()
        }
    }
}

private struct SingleInterfaceControls: View {
    @ObservedObject var experiment: HIDBlackholeExperiment
    @State private var interfaceID: UInt64 = 0
    @State private var requestUSBMultitouch = false
    private var canRequestUSBMode: Bool {
        experiment.selectedInterfaces.first { $0.registryID == interfaceID }?.supportsUSBMultitouchProbe == true
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Single-interface test", selection: $interfaceID) {
                    Text("Choose interface…").tag(UInt64(0))
                    ForEach(experiment.selectedInterfaces, id: \.registryID) { device in
                        Text("\(device.label) · \(String(format: "%04X:%04X", device.usagePage, device.usage)) · RID \(device.registryID)")
                            .tag(device.registryID)
                    }
                }
                .frame(maxWidth: 560)
                .disabled(experiment.hasOpenHIDDevices)
                Button("Capture one (15s)") {
                    experiment.testSingleInterface(registryID: interfaceID,
                        requestUSBMultitouch: requestUSBMultitouch && canRequestUSBMode)
                }
                    .disabled(experiment.hasOpenHIDDevices || experiment.isSavingHID || !experiment.selectedInterfaces.contains { $0.registryID == interfaceID })
                if experiment.singleInterfaceTestID != nil || experiment.isActive {
                    Button("Release interface") { experiment.release() }
                }
            }
            if canRequestUSBMode {
                Toggle("Request USB multitouch mode after 2s (02 01)", isOn: $requestUSBMultitouch)
                    .disabled(experiment.hasOpenHIDDevices)
                if requestUSBMultitouch {
                    Text("Records 2s baseline, then sends the Linux mode command. Reconnect USB if native input does not recover after release.")
                        .font(.caption)
                }
            }
            Text(experiment.summary).font(.caption).textSelection(.enabled)
            if !experiment.captureStatus.isEmpty {
                Text(experiment.captureStatus).font(.caption).textSelection(.enabled)
            }
        }
    }
}
