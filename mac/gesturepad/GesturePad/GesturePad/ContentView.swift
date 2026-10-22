import AppKit
import SwiftUI
import OpenMultitouchSupport

/// Raw-touch workspace for future FingerWorks gesture and chord experiments.
struct ContentView: View {
    @ObservedObject var hidBlackhole: HIDBlackholeExperiment
    @ObservedObject var takeoverPreference: NativeTakeoverPreference
    @ObservedObject var viewModel: ContentViewModel
    static let trackpadWidthMM: CGFloat = 160
    static let trackpadHeightMM: CGFloat = 114.9
    static let displayScale: CGFloat = 2.7
    @State private var selectedGesture: GesturePane = .pointClick
    @State private var editingHand: GestureHandScope = .both
    @State private var leftPeakPressure = 0
    @State private var rightPeakPressure = 0
    @State private var replayScrubValue: Double = 0
    @State private var replayScrubInProgress = false

    init(viewModel: ContentViewModel, hidBlackhole: HIDBlackholeExperiment) {
        self.viewModel = viewModel
        self.hidBlackhole = hidBlackhole
        self.takeoverPreference = hidBlackhole.takeoverPreference
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
        snapshot.showTouchTelemetry = true
        snapshot.showContactPaths = true
        snapshot.replayModeEnabled = viewModel.replayTimelineState != nil
        return snapshot
    }

    var body: some View {
        HStack(spacing: 0) {
            GestureSidebar(selection:$selectedGesture,hand:$editingHand)
                .frame(width:280)
            Divider()
            ScrollView([.horizontal, .vertical]) {
                workspace
                    .padding(20)
            }
        }
        .frame(minWidth: size.width * 2 + 329, minHeight: size.height + 400)
        .onReceive(viewModel.$replayTimelineState) { state in
            if let state, !replayScrubInProgress { replayScrubValue = max(state.currentTimeSeconds, 0) }
        }
    }

    private var workspace: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("FingerWorks Playground").font(.title2).bold()
            DevicesSectionView(availableDevices: viewModel.availableDevices,
                leftDevice: viewModel.leftDevice, rightDevice: viewModel.rightDevice,
                onSelectLeft: { device in
                    viewModel.selectLeftDevice(device)
                    UserDefaults.standard.set(viewModel.leftDevice?.deviceID ?? "", forKey: GesturePadDefaultsKeys.leftDeviceID)
                },
                onSelectRight: { device in
                    viewModel.selectRightDevice(device)
                    UserDefaults.standard.set(viewModel.rightDevice?.deviceID ?? "", forKey: GesturePadDefaultsKeys.rightDeviceID)
                }, onRefresh: { viewModel.refreshDevicesAndListeners() })
            nativeFilterControls
                .padding(12)
                .frame(maxWidth:.infinity,alignment:.leading)
                .background(.quaternary,in:RoundedRectangle(cornerRadius:10))
            if let left = viewModel.leftDevice, left.deviceIDNumeric == viewModel.rightDevice?.deviceIDNumeric {
                Text("The same trackpad is selected on both sides. Enabled gestures combine; left sensitivity takes priority.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            gestureDetails
            if let state = viewModel.replayTimelineState { replayTimelineView(state) }
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
        .frame(width:size.width * 2 + 16,alignment:.leading)
    }

    private var gestureDetails: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(spacing:12) {
                GestureChordIcon(gesture:selectedGesture,hand:editingHand,selected:false)
                    .frame(width:72,height:42)
                VStack(alignment:.leading,spacing:4) {
                    Text(selectedGesture.title).font(.title2).bold()
                    Text(selectedGesture.summary).foregroundStyle(.secondary)
                }
                Spacer()
                if selectedGesture == .rightClick { Text("Spread").font(.caption).padding(.horizontal,8).padding(.vertical,3).background(.quaternary,in:Capsule()) }
            }
            Divider()
            gestureSettings
            Text(editingHand == .both ? "Changes apply to both trackpads." : "Editing the \(editingHand.rawValue.lowercased()) trackpad settings.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth:.infinity,alignment:.leading)
        .background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:12))
    }

    @ViewBuilder private var gestureSettings: some View {
        switch selectedGesture {
        case .pointClick:
            gestureToggle("2-finger mouse",feature:.mouse)
            sensitivityControl("Pointer sensitivity",kind:.pointer)
            gestureToggle("2-finger tap to click",feature:.tap)
        case .dragDoubleClick:
            gestureToggle("3-finger drag/select",feature:.drag)
            gestureToggle("3-finger tap to double-click",feature:.doubleTap)
            sensitivityControl("Pointer sensitivity",kind:.pointer)
        case .scroll:
            gestureToggle("4-finger scroll",feature:.scroll)
            sensitivityControl("Scroll sensitivity",kind:.scroll)
        case .rightClick:
            gestureToggle("Spread thumb + 2 fingertips: right-click",feature:.rightClick)
        }
    }

    private func gestureToggle(_ title: String, feature: GestureFeature) -> some View {
        let value = hidBlackhole.handSettings.enabled(feature,in:editingHand)
        let status = hidBlackhole.gestureStatus(feature,scope:editingHand)
        return VStack(alignment:.leading,spacing:4) {
            ScopedGestureCheckbox(title:title,value:value) { enabled in
                hidBlackhole.setGestureEnabled(feature,enabled,scope:editingHand)
            }
            .frame(height:20).fixedSize(horizontal:true,vertical:false)
            if value == nil {
                Text("Mixed — Left: \(hidBlackhole.handSettings.left[feature] ? "On" : "Off") · Right: \(hidBlackhole.handSettings.right[feature] ? "On" : "Off")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if takeoverPreference.enabled && value != false && status != "Active" {
                Text(status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
        }
    }

    private func sensitivityControl(_ title: String, kind: GestureSensitivity) -> some View {
        let settings = hidBlackhole.handSettings
        let value = settings.sensitivity(kind,in:editingHand)
        return HStack(spacing:12) {
            Text(title).font(.caption)
            Slider(value:Binding(get:{value ?? settings.left[kind]},set:{
                hidBlackhole.setSensitivity(kind,$0,scope:editingHand)
            }),in:0.25...2,step:0.01).frame(width:180)
            if let value {
                Text(String(format:"%.2f×",value)).font(.caption).monospacedDigit()
            } else {
                Text(String(format:"Mixed · L %.2f× / R %.2f×",settings.left[kind],settings.right[kind]))
                    .font(.caption).monospacedDigit()
            }
        }
    }

    private var nativeFilterControls: some View {
        HStack(spacing: 12) {
            Toggle("Trackpad Takeover", isOn: Binding(
                get: { takeoverPreference.enabled },
                set: { hidBlackhole.setTrackpadTakeoverEnabled($0) }
            ))
            .toggleStyle(.checkbox)
            .fixedSize()
            Text(hidBlackhole.nativeFilterStatus + (hidBlackhole.nativeFilterActive ? " Press ⌃⌥R to release" : ""))
                .font(.caption)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
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
                    HStack {
                        Text("No trackpads detected.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        TrackpadRefreshButton(refresh: onRefresh)
                    }
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
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        TrackpadRefreshButton(refresh: onRefresh)
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
}

private struct TrackpadRefreshButton: View {
    let refresh: () -> Void
    var body: some View {
        Button(action: refresh) {
            Image(systemName: "arrow.clockwise").imageScale(.medium)
        }
        .buttonStyle(.bordered)
        .help("Refresh the trackpad list")
    }
}


enum GesturePane: String, CaseIterable, Identifiable {
    case pointClick, dragDoubleClick, scroll, rightClick
    var id: String { rawValue }
    var group: String {
        switch self {
        case .pointClick: return "2 fingers"
        case .dragDoubleClick: return "3 fingers"
        case .scroll: return "4 fingers"
        case .rightClick: return "Thumb + 2 fingers"
        }
    }
    var title: String {
        switch self {
        case .pointClick: return "Point & Click"
        case .dragDoubleClick: return "Drag & Double-Click"
        case .scroll: return "Scroll & Pan"
        case .rightClick: return "Right-Click"
        }
    }
    var summary: String {
        switch self {
        case .pointClick: return "Move with two fingertips, or tap and lift for a click."
        case .dragDoubleClick: return "Move three fingers to drag or select; tap to double-click."
        case .scroll: return "Move four fingers to scroll, with momentum after lift."
        case .rightClick: return "Tap with a spread thumb and two fingertips, then lift to right-click."
        }
    }
    var activeFingers: Set<Int> {
        switch self {
        case .pointClick: return [1,2]
        case .dragDoubleClick: return [1,2,3]
        case .scroll: return [1,2,3,4]
        case .rightClick: return [0,2,3]
        }
    }
}

struct GestureSidebar: View {
    @Binding var selection: GesturePane
    @Binding var hand: GestureHandScope
    @State private var expanded = Set(GesturePane.allCases)

    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack(spacing:8) {
                Text("Gestures").font(.title3).bold()
                Spacer(minLength:0)
                Picker("Gesture hand",selection:$hand) {
                    ForEach(GestureHandScope.allCases) { side in Text(side.rawValue).tag(side) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width:154)
                .help("Edit left, right, or both trackpad gesture settings.")
            }
            .padding(.horizontal,12).padding(.top,16)
            ScrollView(.vertical) {
                VStack(alignment:.leading,spacing:20) {
                    ForEach(GesturePane.allCases) { gesture in
                        DisclosureGroup(isExpanded:Binding(
                            get:{expanded.contains(gesture)},
                            set:{if $0 { expanded.insert(gesture) } else { expanded.remove(gesture) }})) {
                            gestureRow(gesture)
                                .padding(.top,5)
                        } label: {
                            HStack(spacing:8) {
                                GestureChordIcon(gesture:gesture,hand:hand,selected:false).frame(width:48,height:28)
                                Text(gesture.group).font(.headline)
                            }
                        }
                        .tint(.secondary)
                    }
                }
                .padding(12)
            }
            Text(hand == .both ? "Editing both trackpads" : "Editing \(hand.rawValue.lowercased()) trackpad")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal,16).padding(.bottom,16)
        }
        .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .background(Color(nsColor:.windowBackgroundColor))
    }

    private func gestureRow(_ gesture: GesturePane) -> some View {
        let selected = selection == gesture
        return Button { selection = gesture } label: {
            HStack(spacing:8) {
                GestureChordIcon(gesture:gesture,hand:hand,selected:selected).frame(width:48,height:30)
                Text(gesture.title).font(.system(size:14)).lineLimit(1)
                Spacer(minLength:0)
                if gesture == .rightClick {
                    Text("Spread").font(.system(size:11,weight:.medium))
                        .padding(.horizontal,5).padding(.vertical,2)
                        .overlay(Capsule().stroke(selected ? Color.white.opacity(0.6) : Color.secondary.opacity(0.5)))
                }
            }
            .padding(.horizontal,9).padding(.vertical,10)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? Color.orange : Color.clear,in:RoundedRectangle(cornerRadius:8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(gesture.summary)
        .accessibilityLabel(gesture.title)
        .accessibilityValue(selected ? "Selected" : "")
    }
}

/// Diagrammatic chord anatomy, independent of live finger classification.
struct GestureChordIcon: View {
    let gesture: GesturePane
    let hand: GestureHandScope
    let selected: Bool

    var body: some View {
        Canvas { context, size in
            let sides: [Bool] = hand == .both ? [true,false] : [hand == .left]
            let cellWidth = size.width / CGFloat(sides.count)
            let active = gesture.activeFingers
            for (handIndex,mirrored) in sides.enumerated() {
                let points: [CGPoint] = gesture == .rightClick
                    ? [CGPoint(x:0.1,y:0.85),CGPoint(x:0.34,y:0.33),CGPoint(x:0.55,y:0.2),CGPoint(x:0.76,y:0.28),CGPoint(x:0.94,y:0.5)]
                    : [CGPoint(x:0.12,y:0.8),CGPoint(x:0.3,y:0.36),CGPoint(x:0.5,y:0.2),CGPoint(x:0.7,y:0.3),CGPoint(x:0.88,y:0.49)]
                let radius = min(cellWidth/10,size.height/9)
                for index in points.indices {
                    let point = points[index]
                    let x = CGFloat(handIndex)*cellWidth + (mirrored ? 1-point.x : point.x)*cellWidth
                    let y = point.y*size.height
                    let shape = Path(ellipseIn:CGRect(x:x-radius,y:y-radius,width:radius*2,height:radius*2))
                    if active.contains(index) {
                        context.fill(shape,with:.color(selected ? .white : .orange))
                    } else {
                        context.stroke(shape,with:.color(selected ? .white.opacity(0.55) : .secondary.opacity(0.55)),lineWidth:1)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}


/// Native mixed-state checkbox: clicking a mixed Both value enables both sides.
struct ScopedGestureCheckbox: NSViewRepresentable {
    let title: String
    let value: Bool?
    let action: @MainActor (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(value:value,action:action) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle:title,target:context.coordinator,action:#selector(Coordinator.changed(_:)))
        button.allowsMixedState = true
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        button.title = title
        button.state = value.map { $0 ? .on : .off } ?? .mixed
        context.coordinator.value = value; context.coordinator.action = action
    }
    @MainActor final class Coordinator: NSObject {
        var value: Bool?
        var action: @MainActor (Bool) -> Void
        init(value: Bool?, action: @escaping @MainActor (Bool) -> Void) { self.value = value; self.action = action }
        @objc func changed(_ button: NSButton) {
            let enabled = !(value ?? false)
            value = enabled; button.state = enabled ? .on : .off
            action(enabled)
        }
    }
}
