import AppKit
import SwiftUI

enum GesturePane: String, CaseIterable, Identifiable {
    case oneFinger, twoFingers, twoFingerPinch, threeFingers, threeFingerPinch, fourFingers, fourFingerPinch, fiveFingers, fiveFingerPinch, thumbTwo
    var id: String { rawValue }
    var group: String {
        switch self {
        case .oneFinger: return "1 finger"
        case .fiveFingers, .fiveFingerPinch: return "5 fingers"
        case .twoFingers, .twoFingerPinch: return "2 fingers"; case .threeFingers, .threeFingerPinch: return "3 fingers"
        case .fourFingers, .fourFingerPinch: return "4 fingers"; case .thumbTwo: return "Thumb + 2 fingers"
        }
    }
    var title: String {
        switch self {
        case .oneFinger: return "Force Click"
        case .fiveFingers: return "Force Click"
        case .twoFingers: return "Tap and Move"
        case .twoFingerPinch, .threeFingerPinch, .fourFingerPinch, .fiveFingerPinch: return "Pinch and Spread"
        case .threeFingers: return "Tap and Move"
        case .fourFingers: return "Move and Force Click"
        case .thumbTwo: return "Tap"
        }
    }
    var summary: String {
        switch self {
        case .oneFinger: return "Choose an action for a one-finger force click."
        case .fiveFingers: return "Choose an action for five-finger force clicking."
        case .twoFingers: return "Choose actions for two-finger tapping, movement and force clicking."
        case .twoFingerPinch, .threeFingerPinch, .fourFingerPinch, .fiveFingerPinch:
            return "Choose an action for pinching and spreading. Both directions require a recognized thumb to begin."
        case .threeFingers: return "Choose actions for three-finger tapping, movement and force clicking."
        case .fourFingers: return "Choose actions for four-finger movement and force clicking."
        case .thumbTwo: return "Choose an action for a tap with a spread thumb and two fingertips."
        }
    }
    var triggers: [GestureTrigger] {
        switch self {
        case .oneFinger: return [.oneFingerForce]
        case .fiveFingers: return [.fiveFingerForce]
        case .fiveFingerPinch: return [.fiveFingerPinch,.fiveFingerSpread]
        case .twoFingers: return [.twoFingerTap,.twoFingerForce,.twoFingerMove]
        case .twoFingerPinch: return [.twoFingerPinch,.twoFingerSpread]
        case .threeFingers: return [.threeFingerTap,.threeFingerForce,.threeFingerMove]
        case .threeFingerPinch: return [.threeFingerPinch,.threeFingerSpread]
        case .fourFingers: return [.fourFingerMove,.fourFingerForce]
        case .fourFingerPinch: return [.fourFingerPinch,.fourFingerSpread]
        case .thumbTwo: return [.thumbTwoTap]
        }
    }
    var isPinchSection: Bool {
        switch self {
        case .twoFingerPinch, .threeFingerPinch, .fourFingerPinch, .fiveFingerPinch: return true
        default: return false
        }
    }
    var activeFingers: Set<Int> {
        switch self {
        case .oneFinger: return [1]; case .fiveFingers, .fiveFingerPinch: return [0,1,2,3,4]
        case .twoFingers: return [1,2]; case .twoFingerPinch: return [0,2]
        case .threeFingers: return [1,2,3]; case .threeFingerPinch: return [0,2,3]
        case .fourFingers: return [1,2,3,4]; case .fourFingerPinch: return [0,1,2,3]
        case .thumbTwo: return [0,2,3]
        }
    }
}

/// Animated trackpad demonstrations, independent of live input and recognition.
struct GestureChordIcon: View {
    let gesture: GesturePane
    let trigger: GestureTrigger
    var direction: GestureMovementDirection? = nil
    private var demonstrationTitle: String { direction.map { "Swipe " + $0.title } ?? (fourFingerScrollExample ? "Scroll / Pan" : trigger.assignmentTitle) }
    private var fourFingerScrollExample: Bool { trigger == .fourFingerMove }
    private var strokeExample: Bool { trigger.isContinuous && !trigger.isPinch }
    // Original stroke time units, with only stationary holds compressed by half.
    private static let outboundUnits = 0.82
    private static let returnUnits = 0.84
    private static let pairUnits = outboundUnits + returnUnits
    private var cycleDuration: Double { strokeExample && direction == nil ? 2 * Self.pairUnits * 2.8 : 2.8 }
    // Deterministic offscreen previews can choose a point in the continuous loop.
    var previewPhase: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var windowVisible = false
    @State private var playbackStartedAt = Date()

    var body: some View {
        VStack(spacing:6) {
            TimelineView(.animation(minimumInterval:strokeExample ? 1.0/60 : 1.0/30,
                                    paused:previewPhase != nil || reduceMotion || !windowVisible)) { timeline in
                let elapsed = max(0,timeline.date.timeIntervalSince(playbackStartedAt))
                let phase = previewPhase ?? (reduceMotion ? 0.5 : !windowVisible ? 0
                    : elapsed.truncatingRemainder(dividingBy:cycleDuration)/cycleDuration)
                Canvas { context, size in draw(&context,size:size,phase:phase) }
                    .frame(width:180,height:116)
            }
            Text(demonstrationTitle).font(.caption2).foregroundStyle(.secondary)
        }
        .background(GestureExampleWindowVisibility { visible in
            windowVisible = visible
            if visible { playbackStartedAt = Date() }
        }.frame(width:0,height:0))
        .onAppear { playbackStartedAt = Date() }
        .onChange(of:trigger) { _ in playbackStartedAt = Date() }
        .onChange(of:gesture) { _ in playbackStartedAt = Date() }
        .onChange(of:direction) { _ in playbackStartedAt = Date() }
        .onChange(of:reduceMotion) { reduced in
            if !reduced { playbackStartedAt = Date() }
        }
        .accessibilityElement(children:.ignore)
        .accessibilityLabel("\(gesture.contactLabel): \(demonstrationTitle) demonstration")
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, phase: Double) {
        let pad = CGRect(x:14,y:9,width:size.width-28,height:size.height-18)
        context.stroke(Path(roundedRect:pad,cornerRadius:14),
                       with:.color(.secondary.opacity(0.5)),lineWidth:2.5)
        if strokeExample {
            drawMovementStrokes(&context,pad:pad,phase:phase)
            return
        }
        // Rest, contact/motion, then release. Smoothstep eases both ends of movement.
        let motionDuration = trigger.isPinch ? 0.42 : 0.58
        let progress = min(1,max(0,(phase-0.18)/motionDuration))
        let eased = progress*progress*(3-2*progress)
        let touching = phase >= 0.18 && phase < 0.80
        let count = trigger.pinchCount ?? trigger.forceCount ?? (gesture == .thumbTwo ? 3 : gesture == .threeFingers ? 3 : gesture == .fourFingers ? 4 : 2)
        let discrete = !trigger.isContinuous
        let thumbChord = trigger.isPinch || gesture == .thumbTwo
        let starts = contactOffsets(count:count,includesThumb:thumbChord).map {
            CGPoint(x:pad.midX+$0.x,y:pad.midY+$0.y)
        }
        let moving = trigger.isContinuous && !trigger.isPinch
        // Scale around the contact centroid, not the trackpad center. In the
        // two-contact example this gives both dots equal, opposite travel.
        let chordCenter = CGPoint(x:starts.map(\.x).reduce(0,+)/CGFloat(starts.count),
                                  y:starts.map(\.y).reduce(0,+)/CGFloat(starts.count))
        let extentX = starts.map { abs($0.x-chordCenter.x) }.max() ?? 1
        let extentY = starts.map { abs($0.y-chordCenter.y) }.max() ?? 1
        // Wider travel, bounded so even five-contact examples stay inside the pad.
        let widestScale: CGFloat = min(1.65,min((pad.width/2-8)/max(1,extentX),
                                               (pad.height/2-8)/max(1,extentY)))
        func position(_ point:CGPoint, at amount:Double) -> CGPoint {
            if trigger.isPinch {
                let travel = CGFloat(amount)*(widestScale-0.65)
                let scale = trigger.isSpread ? 0.65+travel : widestScale-travel
                return CGPoint(x:pad.midX+(point.x-chordCenter.x)*scale,y:pad.midY+(point.y-chordCenter.y)*scale)
            }
            return CGPoint(x:point.x + (moving ? -23+amount*46 : 0),y:point.y)
        }
        for (index,start) in starts.enumerated() {
            let colors = contactColors(index:index)
            if discrete {
                // Reference tap stages: small filled contact, expanding halo,
                // hollow lift marker, then empty pad. Interpolate every frame.
                let swell = min(1,max(0,(phase-0.10)/0.42))
                let fade = 1-min(1,max(0,(phase-0.62)/0.14))
                let fill = 1-min(1,max(0,(phase-0.33)/0.20))
                let point = position(start,at:0)
                let radius = 5+2.8*swell
                let dot = Path(ellipseIn:CGRect(x:point.x-radius,y:point.y-radius,width:radius*2,height:radius*2))
                context.fill(dot,with:.color(colors.fill.opacity((0.12+0.7*fill)*fade)))
                context.stroke(dot,with:.color(colors.outline.opacity(0.85*fade)),lineWidth:1.4)
                let halo = radius+2+3*sin(swell*Double.pi)
                let haloOpacity = max(0,sin(min(1,phase/0.55)*Double.pi))*0.38*fade
                context.stroke(Path(ellipseIn:CGRect(x:point.x-halo,y:point.y-halo,width:halo*2,height:halo*2)),
                               with:.color((trigger.forceCount != nil ? Color.red : colors.outline).opacity(haloOpacity)),lineWidth:trigger.forceCount != nil ? 2.5 : 1.8)
                continue
            }
            if touching && trigger.isPinch {
                drawTrail(&context,color:colors.fill) { age in
                    let earlier = phase-age
                    guard earlier >= 0.18 && earlier <= 0.18+motionDuration else { return nil }
                    let t = min(1,max(0,(earlier-0.18)/motionDuration))
                    return position(start,at:t*t*(3-2*t))
                }
            }
            let point = position(start,at:eased)
            let dot = Path(ellipseIn:CGRect(x:point.x-6,y:point.y-6,width:12,height:12))
            context.fill(dot,with:.color(colors.fill.opacity(touching ? 0.9 : 0.14)))
            context.stroke(dot,with:.color(colors.outline.opacity(0.85)),lineWidth:1.4)
        }
    }

    /// Use the same anatomical palette as live contacts for every example.
    private func contactColors(index:Int) -> (fill:Color,outline:Color) {
        let fingers = gesture.activeFingers.sorted()
        let fingerID = fingers.indices.contains(index) ? Int32(fingers[index]+1) : 0
        let anatomical = Color(nsColor:AnatomicalFingerPalette.color(fingerID:fingerID))
        return (anatomical,anatomical)
    }

    /// Shared soft trail treatment for translation and pinch/spread examples.
    private func drawTrail(_ context:inout GraphicsContext,color:Color,opacity:Double = 1,
                           sample:(Double)->CGPoint?) {
        var trail = context
        trail.addFilter(.blur(radius:2))
        for step in stride(from:15,through:1,by:-1) {
            let age = Double(step)*0.012
            guard let point = sample(age) else { continue }
            trail.fill(Path(ellipseIn:CGRect(x:point.x-6,y:point.y-6,width:12,height:12)),
                       with:.color(color.opacity(0.085*(1-age/0.20)*opacity)))
        }
    }

    /// Illustrative fingertip arch: middle highest, pinky lower, thumb offset.
    /// These positions never participate in gesture recognition.
    private func contactOffsets(count:Int,includesThumb:Bool = false) -> [CGPoint] {
        let thumb = includesThumb || count == 5
        let tips = thumb ? count-1 : count
        let fingers: [CGPoint]
        switch tips {
        case 1: fingers = [CGPoint(x:0,y:0)]
        case 2: fingers = [CGPoint(x:-9.5,y:0),CGPoint(x:9.5,y:0)]
        case 3: fingers = [CGPoint(x:-20,y:2),CGPoint(x:0,y:-7),CGPoint(x:20,y:0)]
        default: fingers = [CGPoint(x:-28,y:0),CGPoint(x:-9,y:-7),
                            CGPoint(x:10,y:-3),CGPoint(x:29,y:8)]
        }
        if thumb {
            return [CGPoint(x:-36,y:23)] + fingers.map { CGPoint(x:$0.x+5,y:$0.y-12) }
        }
        return fingers
    }

    private func drawMovementStrokes(_ context: inout GraphicsContext, pad:CGRect, phase:Double) {
        let horizontal: Bool
        let reversed: Bool
        let stage: Double
        if let direction {
            horizontal = direction == .left || direction == .right
            reversed = direction == .up || direction == .left
            stage = phase
        } else {
            let cycleTime = phase * 2 * Self.pairUnits
            horizontal = cycleTime >= Self.pairUnits
            let pairTime = cycleTime.truncatingRemainder(dividingBy:Self.pairUnits)
            let secondStroke = pairTime >= Self.outboundUnits
            reversed = secondStroke
            let local = secondStroke ? pairTime-Self.outboundUnits : pairTime
            if !secondStroke {
                // Keep touch/move timing; halve the bottom/right turnaround hold.
                stage = local < 0.64 ? local : 0.64+(local-0.64)*2
            } else if local < 0.10 {
                stage = local*2 // Other half of the turnaround hold.
            } else if local < 0.54 {
                stage = local+0.10 // Return movement retains its original speed.
            } else if local < 0.60 {
                stage = 0.64+(local-0.54)*2 // Half-length pause before lift.
            } else {
                stage = local+0.16 // Lift/fade timing is unchanged.
            }
        }
        func ramp(_ value:Double, _ start:Double, _ end:Double) -> Double {
            let t = min(1,max(0,(value-start)/(end-start)))
            return t*t*(3-2*t)
        }
        let movement = ramp(stage,0.20,0.64)
        let fill = direction != nil
            ? ramp(stage,0.10,0.18)*(1-ramp(stage,0.70,0.78))
            : reversed ? 1-ramp(stage,0.76,0.84) : ramp(stage,0.10,0.18)
        let opacity = direction != nil ? 1-ramp(stage,0.78,0.90) : reversed ? 1-ramp(stage,0.84,0.96) : 1
        let count = gesture.activeFingers.count
        let offsets = contactOffsets(count:count)
        let halfWidth = offsets.map { abs($0.x) }.max() ?? 0
        func point(_ index:Int, _ progress:Double) -> CGPoint {
            let offset = offsets[index]
            let distance = CGFloat(reversed ? 1-progress : progress)
            return horizontal
                ? CGPoint(x:pad.minX+halfWidth+13+distance*(pad.width-2*halfWidth-26)+offset.x,y:pad.midY+offset.y)
                : CGPoint(x:pad.midX+offset.x,y:pad.minY+24+distance*(pad.height-48)+offset.y)
        }
        for index in 0..<count {
            let colors = contactColors(index:index)
            drawTrail(&context,color:colors.fill,opacity:opacity) { age in
                let earlier = stage-age
                guard earlier >= 0.20 && earlier <= 0.64 else { return nil }
                return point(index,ramp(earlier,0.20,0.64))
            }
            let center = point(index,movement)
            let dot = Path(ellipseIn:CGRect(x:center.x-6,y:center.y-6,width:12,height:12))
            context.fill(dot,with:.color(colors.fill.opacity((0.12+0.78*fill)*opacity)))
            context.stroke(dot,with:.color(colors.outline.opacity(0.85*opacity)),lineWidth:1.4)
        }
    }

}


/// Config is an AppKit NSHostingView, so SwiftUI scenePhase is not a visibility
/// signal. Follow the actual window and pause covered/closed/minimized examples.
private struct GestureExampleWindowVisibility: NSViewRepresentable {
    var changed: @MainActor (Bool) -> Void
    func makeNSView(context:Context) -> VisibilityView {
        let view = VisibilityView()
        view.changed = changed
        return view
    }
    func updateNSView(_ view:VisibilityView,context:Context) { view.changed = changed }
    static func dismantleNSView(_ view:VisibilityView,coordinator:()) { view.stopObserving() }

    final class VisibilityView: NSView {
        var changed: (@MainActor (Bool) -> Void)?
        private var lastVisibility: Bool?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            if let window {
                for name in [NSWindow.didChangeOcclusionStateNotification,
                             NSWindow.didMiniaturizeNotification,NSWindow.didDeminiaturizeNotification,
                             NSWindow.willCloseNotification] {
                    NotificationCenter.default.addObserver(self,selector:#selector(windowChanged(_:)),name:name,object:window)
                }
            }
            reportVisibility()
        }
        func stopObserving() { NotificationCenter.default.removeObserver(self) }
        @objc private func windowChanged(_ notification:Notification) {
            reportVisibility(closing:notification.name == NSWindow.willCloseNotification)
        }
        private func reportVisibility(closing:Bool = false) {
            let visible = !closing && window?.isVisible == true && window?.isMiniaturized == false
                && window?.occlusionState.contains(.visible) == true
            guard visible != lastVisibility else { return }
            lastVisibility = visible
            // Avoid mutating SwiftUI state during a hosting-view layout update.
            DispatchQueue.main.async { [weak self] in self?.changed?(visible) }
        }
    }
}

/// A value-only action editor; production wiring decides the hand(s) to update.
struct GestureActionPickerRow: View {
    let trigger: GestureTrigger
    let value: GestureAction?
    let leftAction: GestureAction
    let rightAction: GestureAction
    let status: String
    let showsStatus: Bool
    let apply: @MainActor (GestureAction) -> Void
    var body: some View {
        VStack(alignment:.leading,spacing:5) {
            Text(trigger.title).font(.subheadline).fontWeight(.medium)
            Picker("Action",selection:Binding<GestureAction?>(get:{value},set:{ action in
                if let action { apply(action) }
            })) {
                if value == nil { Text("Mixed").tag(nil as GestureAction?) }
                ForEach(trigger.allowedActions) { action in Text(action.title).tag(Optional(action)) }
            }
            .pickerStyle(.menu)
            if value == nil {
                Text("Left: \(leftAction.title) · Right: \(rightAction.title)")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            if showsStatus && value != .disabled && status != "Active" {
                Text(status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
        }
    }
}

/// Presentation catalog for existing recognizers only; no new recognition or saved IDs.
extension GesturePane {
    var contactLabel: String {
        if isPinchSection { return "\(triggers[0].pinchCount!) contacts · thumb required" }
        if self == .thumbTwo { return "3 contacts · thumb + 2 fingertips" }
        if let count = triggers.first?.forceCount { return "\(count) contact\(count == 1 ? "" : "s") · pressure" }
        return group
    }
    var arrangementLabel: String {
        if isPinchSection { return "Thumb + fingertips" }
        switch self {
        case .threeFingers: return "Aligned fingertips for movement"
        case .thumbTwo: return "Spread thumb + fingertips"
        default: return "Current recognition"
        }
    }
    func includes(_ trigger: GestureTrigger) -> Bool { triggers.contains(trigger) }
}

extension GestureTrigger {
    var assignmentTitle: String {
        if isPinch { return isSpread ? "Spread" : "Pinch" }
        if forceCount != nil { return "Force click" }
        switch self {
        case .twoFingerMove,.threeFingerMove,.fourFingerMove: return "Move in any direction"
        default: return "Tap"
        }
    }
    var assignmentSymbol: String {
        if isPinch { return isSpread ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left" }
        if forceCount != nil { return "hand.point.up.left.fill" }
        return isContinuous ? "arrow.up.and.down.and.arrow.left.and.right" : "hand.tap"
    }
    func behavior(for action: GestureAction?) -> String {
        guard let action else { return "Mixed assignments" }
        if action == .disabled { return "No output" }
        if action.isAppleShortcut { return isPinch ? "Once on activation" : "One step per recognition" }
        switch action {
        case .pointer,.primaryDrag,.scroll,.zoom: return "Follow motion"
        default: return "Once per recognition"
        }
    }
    var recognitionNote: String {
        if isPinch { return "A recognized thumb is required to begin. Once active, the session continues through added or lifted fingers until all-up." }
        if forceCount != nil { return "Activates at P ≥ 130 on any one contact, using the current contact count. Fires once until all fingers lift." }
        switch self {
        case .thumbTwoTap: return "A spread thumb plus two fingertips. Fingertip relabeling is tolerated after a match. Tap window: 0.5 seconds."
        case .threeFingerMove: return "Begins with three aligned or gently arched fingertips. Movement latches until all-up, including added or lifted fingers."
        case .twoFingerTap,.threeFingerTap: return "Tap window: 0.5 seconds. Landing/lift skew: 80 ms. Movement slop: 1 mm. A motion-owned cycle cannot also tap."
        default: return "Movement owns its touch cycle until all-up, including added or lifted fingers. Motion and taps compete before activation."
        }
    }
}

struct GestureInspectorPanel: View {
    @ObservedObject var controller: TrackpadGestureController
    @ObservedObject var takeover: NativeTrackpadTakeover
    var body: some View {
        GestureAssignmentWorkspace(settings:controller.settings,
            status:{controller.status($0,scope:$1)},
            apply:{controller.setAction($0,for:$1,scope:$2)},
            setSensitivity:{controller.setSensitivity($0,kind:$1,scope:$2)},
            setMovementMode:{controller.setMovementMode($0,for:$1,scope:$2)},
            setDirectionalAction:{controller.setDirectionalAction($0,direction:$1,for:$2,scope:$3)})
    }
}

/// Value-only workspace so layout previews/tests never create input clients or post events.
struct GestureAssignmentWorkspace: View {
    let settings: HandGestureSettings
    let status: (GestureTrigger,GestureHandScope) -> String
    let apply: (GestureAction,GestureTrigger,GestureHandScope) -> Void
    let setSensitivity: (Double,GestureSensitivity,GestureHandScope) -> Void
    let setMovementMode: (GestureMovementMode,GestureTrigger,GestureHandScope) -> Void
    let setDirectionalAction: (GestureAction,GestureMovementDirection,GestureTrigger,GestureHandScope) -> Void
    @State private var selectedDirection: GestureMovementDirection?
    @AppStorage("AppleMagicTouchstream.mirrorGestureEdits") private var mirrorEdits = false
    @State private var editingHand: GestureHandScope = .left
    @State private var pane: GesturePane
    @State private var selected: GestureTrigger
    @State private var search = ""
    @AppStorage(WorkspaceColumnSizing.gestureNavigationWidthKey) private var menuColumnWidth = WorkspaceColumnSizing.defaultGestureColumnWidth
    @AppStorage(WorkspaceColumnSizing.gestureInspectorWidthKey) private var inspectorColumnWidth = WorkspaceColumnSizing.defaultGestureColumnWidth

    init(settings:HandGestureSettings, initialPane:GesturePane = .twoFingers,
         initialDirection:GestureMovementDirection? = nil,
         status:@escaping (GestureTrigger,GestureHandScope)->String,
         apply:@escaping (GestureAction,GestureTrigger,GestureHandScope)->Void,
         setSensitivity:@escaping (Double,GestureSensitivity,GestureHandScope)->Void,
         setMovementMode:@escaping (GestureMovementMode,GestureTrigger,GestureHandScope)->Void = {_,_,_ in},
         setDirectionalAction:@escaping (GestureAction,GestureMovementDirection,GestureTrigger,GestureHandScope)->Void = {_,_,_,_ in}) {
        self.settings = settings; self.status = status; self.apply = apply; self.setSensitivity = setSensitivity
        self.setMovementMode = setMovementMode; self.setDirectionalAction = setDirectionalAction
        _pane = State(initialValue:initialPane)
        _selectedDirection = State(initialValue:initialDirection)
        _selected = State(initialValue:initialPane.triggers.first(where:{$0.isContinuous}) ?? initialPane.triggers[0])
    }

    private var editingScope: GestureHandScope { mirrorEdits ? .both : editingHand }
    private var action: GestureAction? { settings.action(selected,in:editingScope) }
    private var scopeText: String { mirrorEdits ? "Left + Right trackpads" : "\(editingHand.rawValue) trackpad" }
    private var targetText: String { mirrorEdits ? "both trackpads" : "the \(editingHand.rawValue.lowercased()) trackpad" }
    private var groups: [String] { Array(NSOrderedSet(array:GesturePane.allCases.map(\.group))) as? [String] ?? [] }
    private func matching(_ item:GesturePane) -> Bool {
        search.isEmpty || "\(item.group) \(item.title) \(item.summary) \(item.triggers.map { settings.action($0,in:editingScope)?.title ?? "" }.joined(separator:" "))"
            .localizedCaseInsensitiveContains(search)
    }
    var body: some View {
        GeometryReader { viewport in
            let menuWidth = WorkspaceColumnSizing.menu(menuColumnWidth,available:viewport.size.width,reserved:WorkspaceColumnSizing.minimumInspector)
            let inspectorMaximum = max(WorkspaceColumnSizing.minimumInspector,min(480,viewport.size.width-menuWidth-WorkspaceColumnSizing.dividerWidth*2-360))
            let inspectorWidth = min(inspectorMaximum,max(WorkspaceColumnSizing.minimumInspector,inspectorColumnWidth))
            HStack(spacing:0) {
                navigation.frame(width:menuWidth)
                WorkspaceColumnDivider(width:Binding(get:{menuWidth},set:{menuColumnWidth = $0}),
                    minimum:WorkspaceColumnSizing.minimumMenu,
                    maximum:WorkspaceColumnSizing.menuMaximum(available:viewport.size.width,reserved:inspectorWidth),
                    trailingColumn:false,label:"Gesture navigation width")
                ScrollView(.vertical) {
                    VStack(alignment:.leading,spacing:20) {
                        header
                        Divider()
                        assignments
                        if selectedDirection == nil { lifecycle }
                        Text("Choose a card to edit its action. Changes apply to \(targetText).")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    }
                    .padding(24)
                    .frame(maxWidth:.infinity,alignment:.topLeading)
                }
                .frame(maxWidth:.infinity,maxHeight:.infinity)
                WorkspaceColumnDivider(width:Binding(get:{inspectorWidth},set:{inspectorColumnWidth = $0}),
                    minimum:WorkspaceColumnSizing.minimumInspector,maximum:inspectorMaximum,trailingColumn:true,label:"Gesture inspector width")
                inspector.frame(width:inspectorWidth)
            }
        }
        .background(Color(nsColor:.windowBackgroundColor))
        .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
    }

    private var navigation: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack(alignment:.firstTextBaseline,spacing:8) {
                Text("Gestures").font(.title3).bold().layoutPriority(1)
                Spacer(minLength:0)
                Toggle("Mirror Edit", isOn:$mirrorEdits)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .help("Apply action and sensitivity edits to both trackpads. Existing differences stay unchanged until edited; gestures still run independently on each pad.")
            }
            Picker("Edit trackpad",selection:$editingHand) {
                Text("Left").tag(GestureHandScope.left)
                Text("Right").tag(GestureHandScope.right)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth:.infinity)
            .disabled(mirrorEdits)
            .help("Choose which trackpad to edit when mirroring is off.")
            TextField("Search gestures or actions",text:$search)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search gestures or actions")
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    ForEach(groups,id:\.self) { group in
                        let items = GesturePane.allCases.filter { $0.group == group && matching($0) }
                        if !items.isEmpty {
                            VStack(alignment:.leading,spacing:5) {
                                Text(group.uppercased()).font(.caption2).fontWeight(.semibold).foregroundStyle(.secondary).padding(.horizontal,8)
                                ForEach(items) { item in navigationItem(item) }
                            }
                        }
                    }
                    if !GesturePane.allCases.contains(where:matching) {
                        Text("No matching gestures").font(.callout).foregroundStyle(.secondary).padding(8)
                    }
                }
            }
            Text("\(scopeText) settings\nDirectional assignments are a preview.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
        .padding(16)
        .background(Color.primary.opacity(0.025))
    }

    private func navigationItem(_ item:GesturePane) -> some View {
        Button {
            pane = item
            selectedDirection = nil
            selected = item.triggers.first(where:{$0.isContinuous}) ?? item.triggers[0]
        } label: {
            HStack(alignment:.top,spacing:8) {
                Circle().fill(pane == item ? Color.accentColor : Color.secondary.opacity(0.5)).frame(width:6,height:6).padding(.top,6)
                VStack(alignment:.leading,spacing:3) {
                    Text(item.title).font(.system(size:13,weight:pane == item ? .semibold : .regular))
                    if item.isPinchSection { Text("Thumb required").font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer(minLength:0)
            }
            .frame(maxWidth:.infinity,alignment:.leading).padding(10)
            .background(pane == item ? Color.accentColor.opacity(0.13) : .clear,in:RoundedRectangle(cornerRadius:8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.group), \(item.title)")
        .accessibilityAddTraits(pane == item ? [.isSelected] : [])
    }

    private var header: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Gestures / \(scopeText)").font(.caption).foregroundStyle(.secondary)
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:6) {
                    Text(pane.group).font(.system(size:25,weight:.semibold))
                    Text(pane.title).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                GestureChordIcon(gesture:pane,trigger:selected,direction:selectedDirection).padding(.leading,8)
            }
            ViewThatFits(in:.horizontal) {
                HStack(spacing:8) { metadata }
                VStack(alignment:.leading,spacing:8) { metadata }
            }
            Text(pane.summary).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
    @ViewBuilder private var metadata: some View {
        chip(pane.contactLabel)
        chip(pane.arrangementLabel)
    }
    private func chip(_ text:String) -> some View {
        Text(text).font(.caption2).foregroundStyle(.secondary).padding(.horizontal,8).padding(.vertical,6)
            .background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:6))
    }

    private var assignments: some View {
        VStack(alignment:.leading,spacing:12) {
            Text(pane.isPinchSection ? "SCALE ASSIGNMENTS" : "ASSIGNMENTS")
                .font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
            if pane.isPinchSection {
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12) {
                    ForEach(pane.triggers) { assignmentCard($0) }
                }
            } else if pane.triggers.contains(where: \.isContinuous) {
                ForEach(pane.triggers.filter { $0.isContinuous }) { movementCross($0) }
            } else {
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12) {
                    ForEach(pane.triggers.filter { !$0.isContinuous }) { assignmentCard($0) }
                }
            }
        }
    }
    private func movementCross(_ trigger:GestureTrigger) -> some View {
        let mode = settings.movementMode(trigger,in:editingScope)
        return VStack(alignment:.leading,spacing:10) {
            Text("Use continuous movement or separate directional actions.")
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(minimum:0),spacing:8),count:3),spacing:8) {
                if let tap = pane.triggers.first(where:{ !$0.isContinuous && $0.forceCount == nil }) {
                    assignmentCard(tap,compact:true)
                } else { Color.clear.frame(height:1) }
                movementCard(trigger,direction:.up)
                if let force = pane.triggers.first(where:{ $0.forceCount != nil }) {
                    assignmentCard(force,compact:true)
                } else { Color.clear.frame(height:1) }
                movementCard(trigger,direction:.left)
                movementCard(trigger,direction:nil)
                movementCard(trigger,direction:.right)
                Color.clear.frame(height:1)
                movementCard(trigger,direction:.down)
                Color.clear.frame(height:1)
            }
            if mode != .continuous {
                Text(mode == nil ? "Mixed modes. Directional output is not implemented yet." : "Directional mode: assignments save, but output is not implemented yet. Continuous movement is inactive.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
        }
    }

    private func movementCard(_ trigger:GestureTrigger,direction:GestureMovementDirection?) -> some View {
        let mode = settings.movementMode(trigger,in:editingScope)
        let targetMode: GestureMovementMode = direction == nil ? .continuous : .directional
        let active = mode == targetMode
        let isSelected = selected == trigger && selectedDirection == direction
        let assigned = direction.map { settings.directionalAction($0,for:trigger,in:editingScope) } ?? settings.action(trigger,in:editingScope)
        let title = direction.map { "Move " + $0.title } ?? "Movement"
        return Button {
            selected = trigger; selectedDirection = direction
            if mode != targetMode { setMovementMode(targetMode,trigger,editingScope) }
        } label: {
            VStack(alignment:.leading,spacing:8) {
                Label(title,systemImage:direction?.symbol ?? "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.caption).foregroundStyle(.secondary)
                Text(assigned?.title ?? "Mixed").font(.system(size:16,weight:.medium))
                    .fixedSize(horizontal:false,vertical:true)
                Text(active ? (direction == nil ? "Continuous" : "Output coming later") : "Inactive · click to switch")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            .padding(12).frame(maxWidth:.infinity,minHeight:106,alignment:.topLeading)
            .opacity(active ? 1 : 0.5)
            .background(active ? Color.accentColor.opacity(0.07) : Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:10))
            .overlay(RoundedRectangle(cornerRadius:10).stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.12),lineWidth:isSelected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius:10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(assigned?.title ?? "Mixed"), \(active ? "active mode" : "inactive mode")")
        .accessibilityHint("Select to edit and switch movement mode.")
    }

    private func assignmentCard(_ trigger:GestureTrigger,compact:Bool = false) -> some View {
        let assigned = settings.action(trigger,in:editingScope)
        return Button { selected = trigger; selectedDirection = nil } label: {
            VStack(alignment:.leading,spacing:10) {
                HStack {
                    Image(systemName:trigger.assignmentSymbol).foregroundStyle(.secondary)
                    Text(trigger.assignmentTitle).font(compact ? .caption : .callout).foregroundStyle(.secondary)
                    Spacer(minLength:0)
                }
                Text(assigned?.title ?? "Mixed").font(.system(size:compact ? 16 : 17,weight:.medium)).fixedSize(horizontal:false,vertical:true)
                Text(trigger.behavior(for:assigned)).font(.caption).foregroundStyle(.secondary)
            }
            .padding(compact ? 12 : 18).frame(maxWidth:.infinity,minHeight:compact ? 106 : 112,alignment:.topLeading)
            .background(selected == trigger ? Color.accentColor.opacity(0.07) : Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:10))
            .overlay(RoundedRectangle(cornerRadius:10).stroke(selected == trigger ? Color.accentColor : Color.primary.opacity(0.12),lineWidth:1))
            .contentShape(RoundedRectangle(cornerRadius:10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(trigger.assignmentTitle), \(assigned?.title ?? "Mixed")")
        .accessibilityAddTraits(selected == trigger ? [.isSelected] : [])
    }

    private var lifecycle: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("SESSION LIFETIME").font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
            HStack(alignment:.top,spacing:12) {
                lifetimeCard("Hold",symbol:"pause",detail:action == .primaryDrag ? "The mouse button stays down during an active drag." : "No separate hold gesture is available for this chord.")
                lifetimeCard("Lift",symbol:"arrow.up",detail:"All-up ends the session and releases its held outputs. Scroll momentum may continue.")
            }
        }
    }
    private func lifetimeCard(_ title:String,symbol:String,detail:String) -> some View {
        VStack(alignment:.leading,spacing:8) {
            Label(title,systemImage:symbol).font(.callout).foregroundStyle(.secondary)
            Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Text("Automatic · not assignable").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(14).frame(maxWidth:.infinity,alignment:.topLeading)
        .background(Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:9))
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                VStack(alignment:.leading,spacing:8) {
                    Text("SELECTED ASSIGNMENT").font(.caption2).fontWeight(.medium).foregroundStyle(.secondary)
                    Text(selectedDirection.map { "Move " + $0.title } ?? selected.assignmentTitle).font(.title3).bold()
                    Text("\(pane.group) · \(scopeText)").font(.caption).foregroundStyle(.secondary)
                }
                if let direction = selectedDirection {
                    directionalInspector(direction)
                } else {
                    GestureActionPickerRow(trigger:selected,value:action,
                        leftAction:settings.left.bindings.action(for:selected),
                        rightAction:settings.right.bindings.action(for:selected),
                        status:status(selected,editingScope),showsStatus:true) { value in
                            apply(value,selected,editingScope)
                        }
                    Divider()
                    VStack(alignment:.leading,spacing:8) {
                        Text("Behavior").font(.caption).foregroundStyle(.secondary)
                        Text(selected.behavior(for:action)).font(.callout).fontWeight(.medium)
                        Text(behaviorDetail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    }
                    if let action {
                        if action.requiresPointerProfile { sensitivity("Pointer sensitivity",kind:.pointer) }
                        if action == .scroll { sensitivity("Scroll sensitivity",kind:.scroll) }
                        if action == .zoom { sensitivity("Zoom sensitivity",kind:.zoom) }
                    }
                    VStack(alignment:.leading,spacing:10) {
                        Text("Recognition").font(.callout).fontWeight(.medium)
                        Text(selected.recognitionNote).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    }
                    .padding(14).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:9))
                }
                Text("Changes save automatically and are included in keymap exports.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            .padding(20)
        }
        .background(Color.primary.opacity(0.025))
    }
    private func directionalInspector(_ direction:GestureMovementDirection) -> some View {
        let value = settings.directionalAction(direction,for:selected,in:editingScope)
        return VStack(alignment:.leading,spacing:14) {
            Picker("Action",selection:Binding<GestureAction?>(get:{value},set:{ action in
                if let action { setDirectionalAction(action,direction,selected,editingScope) }
            })) {
                if value == nil { Text("Mixed").tag(nil as GestureAction?) }
                ForEach(GestureDirectionalAssignments.allowedActions) { action in
                    Text(action.title).tag(Optional(action))
                }
            }
            .pickerStyle(.menu)
            if value == nil {
                Text("Left: \(settings.left.movement(selected).action(direction).title) · Right: \(settings.right.movement(selected).action(direction).title)")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            Text("Directional output is not implemented yet.")
                .font(.callout).fontWeight(.medium)
            Text("This assignment is saved for the next gesture-engine stage. Direction detection and motion-based repeat will be added later. Continuous movement is inactive in directional mode.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Text("Choose the center Movement card to restore continuous movement. Assignments are preserved when switching modes.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }

    private var behaviorDetail:String {
        guard let action, action != .disabled else { return "Choose an action to enable this input for the selected trackpad." }
        if action.isAppleShortcut { return selected.isPinch ? "Fires once when the gesture activates. Continuing or reversing the motion does not fire again before all-up." : "Fires once when this tap or pressure gesture is recognized." }
        switch action {
        case .primaryDrag: return "Holds the primary mouse button through the drag, using the same pointer acceleration as mouse movement."
        case .scroll: return "Precise scrolling follows motion, with momentum after release."
        case .zoom: return "Continuous native magnification follows scale changes. The active action stays latched until all-up."
        case .pointer: return "Pointer movement follows the selected trackpad's Apple acceleration profile."
        default: return "A completed recognition sends one balanced click sequence."
        }
    }
    private func sensitivity(_ title:String,kind:GestureSensitivity) -> some View {
        let value = settings.sensitivity(kind,in:editingScope) ?? 1
        return VStack(alignment:.leading,spacing:8) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(settings.sensitivity(kind,in:editingScope) == nil ? "Mixed" : String(format:"%.2f×",value)).font(.caption).monospacedDigit()
            }
            Slider(value:Binding(get:{value},set:{setSensitivity(($0 * 100).rounded() / 100,kind,editingScope)}),in:0.25...2)
                .accessibilityLabel(title)
            Text("Shared by all \(kind == .zoom ? "zoom" : kind == .scroll ? "scroll" : "pointer and drag") gestures on \(targetText).")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
}


/// Independent persisted widths for Keyboard settings and the two Gesture sidebars.
enum WorkspaceColumnSizing {
    static let menuWidthKey = "AppleMagicTouchstream.assignmentMenuWidth"
    static let gestureNavigationWidthKey = "AppleMagicTouchstream.gestureNavigationWidth"
    static let gestureInspectorWidthKey = "AppleMagicTouchstream.gestureInspectorWidth"
    static let defaultGestureColumnWidth = 286.0
    static let compactMenuBreakpoint = 380.0
    static let defaultMenuWidth = compactMenuBreakpoint + 1
    static let minimumMenu = 220.0
    static let minimumInspector = 200.0
    static let dividerWidth = 8.0
    static func menuMaximum(available:Double,reserved:Double) -> Double {
        max(minimumMenu,min(620,available-reserved-360-dividerWidth*2))
    }
    static func menu(_ requested:Double,available:Double,reserved:Double) -> Double {
        min(menuMaximum(available:available,reserved:reserved),max(minimumMenu,requested))
    }
}

/// An eight-point hit target with a native resize cursor and keyboard/AX adjustments.
struct WorkspaceColumnDivider: View {
    @Binding var width: Double
    let minimum: Double
    let maximum: Double
    let trailingColumn: Bool
    let label: String
    @State private var dragOrigin: Double?
    @State private var hovered = false

    private func resize(_ proposed:Double) { width = min(maximum,max(minimum,proposed)) }
    var body: some View {
        ZStack {
            Color.primary.opacity(hovered || dragOrigin != nil ? 0.08 : 0.025)
            Rectangle().fill(Color.primary.opacity(0.13)).frame(width:1)
            Capsule().fill(Color.secondary.opacity(hovered || dragOrigin != nil ? 0.7 : 0.3))
                .frame(width:3,height:26)
            WorkspaceResizeCursor().allowsHitTesting(false)
        }
        .frame(width:WorkspaceColumnSizing.dividerWidth)
        .frame(maxHeight:.infinity)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .gesture(DragGesture(minimumDistance:0,coordinateSpace:.global).onChanged { value in
            if dragOrigin == nil { dragOrigin = width }
            resize((dragOrigin ?? width) + value.translation.width * (trailingColumn ? -1 : 1))
        }.onEnded { _ in dragOrigin = nil })
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(width)) points")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: resize(width+20)
            case .decrement: resize(width-20)
            @unknown default: break
            }
        }
    }
}

private struct WorkspaceResizeCursor: NSViewRepresentable {
    func makeNSView(context:Context) -> NSView { CursorView() }
    func updateNSView(_ view:NSView,context:Context) { view.window?.invalidateCursorRects(for:view) }
    private final class CursorView: NSView {
        override func resetCursorRects() { addCursorRect(bounds,cursor:.resizeLeftRight) }
    }
}
