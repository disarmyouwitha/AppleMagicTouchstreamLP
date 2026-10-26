import AppKit
import SwiftUI

enum GesturePane: String, CaseIterable, Identifiable {
    case oneFinger, twoFingers, twoFingerPinch, threeFingers, threeFingerPinch, fourFingers, fourFingerPinch, fourCorners, fiveFingers, fiveFingerPinch, thumbTwo
    var id: String { rawValue }
    var group: String {
        switch self {
        case .oneFinger: return "1 finger"
        case .fiveFingers, .fiveFingerPinch: return "5 fingers"
        case .twoFingers, .twoFingerPinch: return "2 fingers"; case .threeFingers, .threeFingerPinch, .thumbTwo: return "3 fingers"
        case .fourFingers, .fourFingerPinch, .fourCorners: return "4 fingers"
        }
    }
    var title: String {
        switch self {
        case .oneFinger: return "Force Click"
        case .fiveFingers: return "Tap and Move"
        case .twoFingers: return "Tap and Move"
        case .twoFingerPinch, .threeFingerPinch, .fourFingerPinch: return "Pinch and Spread"
        case .fiveFingerPinch: return "Pinch, Spread, and Rotate"
        case .threeFingers: return "Tap and Move"
        case .fourFingers: return "Tap and Move"
        case .fourCorners:return "Outer Corners"
        case .thumbTwo: return "Thumb+2fingers"
        }
    }
    var summary: String {
        switch self {
        case .oneFinger: return "Choose an action for a one-finger force click."
        case .fiveFingers: return "Choose actions for five-finger tapping, movement, force clicking and holding."
        case .twoFingers: return "Choose actions for two-finger tapping, movement and force clicking."
        case .twoFingerPinch, .threeFingerPinch, .fourFingerPinch:
            return "Choose actions for pinching and spreading. Both directions require a recognized thumb to begin."
        case .fiveFingerPinch:
            return "Choose actions for pinching, spreading and rotation. Pinch and Spread require a recognized thumb to begin."
        case .threeFingers: return "Choose actions for three-finger tapping, movement and force clicking."
        case .fourFingers: return "Choose actions for four-finger tapping, movement and force clicking."
        case .fourCorners:return "One contact in each outer corner of this trackpad. Hold all four corners until the configured threshold."
        case .thumbTwo: return "Choose independent tap, hold and rotation actions for a spread thumb and two fingertips."
        }
    }
    var triggers: [GestureTrigger] {
        switch self {
        case .oneFinger: return [.oneFingerForce]
        case .fiveFingers: return [.fiveFingerTap,.fiveFingerForce,.fiveFingerMove]
        case .fiveFingerPinch: return [.fiveFingerPinch,.fiveFingerSpread,.fiveFingerRotateLeft,.fiveFingerRotateRight]
        case .twoFingers: return [.twoFingerTap,.twoFingerForce,.twoFingerMove]
        case .twoFingerPinch: return [.twoFingerPinch,.twoFingerSpread]
        case .threeFingers: return [.threeFingerTap,.threeFingerForce,.threeFingerMove]
        case .threeFingerPinch: return [.threeFingerPinch,.threeFingerSpread]
        case .fourFingers: return [.fourFingerTap,.fourFingerForce,.fourFingerMove]
        case .fourCorners:return [.fourCornersTap]
        case .fourFingerPinch: return [.fourFingerPinch,.fourFingerSpread]
        case .thumbTwo: return [.thumbTwoTap,.threeFingerRotateLeft,.threeFingerRotateRight]
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
        case .fourCorners:return [1,2,3,4]
        }
    }
}

/// Fade only the contacts; keep the trackpad outline visible between cycles.
private enum GestureExampleFade {
    static func opacity(_ phase:Double,start:Double = 0.80,end:Double = 0.94) -> Double {
        let t = min(1,max(0,(phase-start)/(end-start)))
        return 1-t*t*(3-2*t)
    }
}

/// Animated trackpad demonstrations, independent of live input and recognition.
struct GestureChordIcon: View {
    let gesture: GesturePane
    let trigger: GestureTrigger
    var direction: GestureMovementDirection? = nil
    var holding = false
    private var demonstrationTitle: String { holding ? "Hold" : direction.map { "Swipe " + $0.title } ?? (fourFingerScrollExample ? "Scroll / Pan" : trigger.assignmentTitle) }
    private var fourFingerScrollExample: Bool { trigger == .fourFingerMove }
    private var strokeExample: Bool { !holding && trigger.isContinuous && !trigger.isPinch && !trigger.isRotation }
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
        .onChange(of:holding) { _ in playbackStartedAt = Date() }
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
        if holding {
            context.opacity *= GestureExampleFade.opacity(phase)
            let offsets = gesture == .fourCorners ? [CGPoint(x:-55,y:-30),CGPoint(x:-55,y:30),CGPoint(x:55,y:-30),CGPoint(x:55,y:30)] : contactOffsets(count:gesture.holdCount,includesThumb:gesture == .thumbTwo)
            for (index,offset) in offsets.enumerated() {
                let point = CGPoint(x:pad.midX+offset.x,y:pad.midY+offset.y)
                let dot = Path(ellipseIn:CGRect(x:point.x-6,y:point.y-6,width:12,height:12))
                let colors = contactColors(index:index)
                context.fill(dot,with:.color(colors.fill))
                context.stroke(dot,with:.color(colors.outline),lineWidth:1.5)
            }
            return
        }
        if strokeExample {
            drawMovementStrokes(&context,pad:pad,phase:phase)
            return
        }
        // Rest, contact/motion, then release. Smoothstep eases both ends of movement.
        let motionDuration = trigger.isPinch || trigger.isRotation ? 0.42 : 0.58
        let progress = min(1,max(0,(phase-0.18)/motionDuration))
        let eased = progress*progress*(3-2*progress)
        let touching = phase >= 0.18 && phase < 0.80
        let count = gesture.holdCount
        let discrete = !trigger.isContinuous && !trigger.isRotation
        let thumbChord = trigger.isPinch || trigger.isRotation || gesture == .thumbTwo
        let offsets = gesture == .fourCorners ? [CGPoint(x:-55,y:-30),CGPoint(x:-55,y:30),CGPoint(x:55,y:-30),CGPoint(x:55,y:30)] : contactOffsets(count:count,includesThumb:thumbChord)
        let starts = offsets.map {
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
            if trigger.isRotation {
                let angle = amount * (trigger.rotatesRight ? 1 : -1) * Double.pi/3
                let x = Double(point.x-chordCenter.x), y = Double(point.y-chordCenter.y)
                return CGPoint(x:pad.midX+x*cos(angle)-y*sin(angle),y:pad.midY+x*sin(angle)+y*cos(angle))
            }
            if trigger.isPinch {
                let travel = CGFloat(amount)*(widestScale-0.65)
                let scale = trigger.isSpread ? 0.65+travel : widestScale-travel
                return CGPoint(x:pad.midX+(point.x-chordCenter.x)*scale,y:pad.midY+(point.y-chordCenter.y)*scale)
            }
            return CGPoint(x:point.x + (moving ? -23+amount*46 : 0),y:point.y)
        }
        if !discrete { context.opacity *= GestureExampleFade.opacity(phase) }
        for (index,start) in starts.enumerated() {
            let colors = contactColors(index:index)
            if discrete {
                // Reference tap stages: small filled contact, expanding halo,
                // hollow lift marker, then empty pad. Interpolate every frame.
                let swell = min(1,max(0,(phase-0.10)/0.42))
                let fade = GestureExampleFade.opacity(phase,start:0.62,end:0.76)
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
            if touching && (trigger.isPinch || trigger.isRotation) {
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
        // Four corners uses two hands on one pad: Index/Thumb on each side.
        let fingerID:Int32 = gesture == .fourCorners ? (index.isMultiple(of:2) ? 2 : 1)
            : fingers.indices.contains(index) ? Int32(fingers[index]+1) : 0
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
            GestureActionChooser(value:value,actions:trigger.allowedActions,choose:apply)
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

/// Presentation catalog, including saved rotation slots awaiting recognition.
extension GesturePane {
    var holdKey:Int { self == .thumbTwo ? PerHandGestureSettings.thumbHoldKey : self == .fourCorners ? PerHandGestureSettings.cornersHoldKey : holdCount }
    var holdCount:Int {
        if self == .fourCorners { return 4 }
        return triggers.compactMap { $0.forceCount ?? $0.pinchCount }.first ?? (self == .thumbTwo ? 3 : 2)
    }
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
        if isRotation { return rotatesRight ? "Rotate Right" : "Rotate Left" }
        if isPinch { return isSpread ? "Spread" : "Pinch" }
        if forceCount != nil { return "Force click" }
        switch self {
        case .twoFingerMove,.threeFingerMove,.fourFingerMove,.fiveFingerMove: return "Move in any direction"
        default: return "Tap"
        }
    }
    var assignmentSymbol: String {
        if isRotation { return rotatesRight ? "rotate.right" : "rotate.left" }
        if isPinch { return isSpread ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left" }
        if forceCount != nil { return "hand.point.up.left.fill" }
        return isContinuous ? "arrow.up.and.down.and.arrow.left.and.right" : "hand.tap"
    }
    func behavior(for action: GestureAction?) -> String {
        if isRotation { return action == .disabled ? "No output" : "Once on activation" }
        guard let action else { return "Mixed assignments" }
        if action == .disabled { return "No output" }
        if action.isDiscreteOutput { return isPinch || isContinuous ? "Once on activation" : "One step per recognition" }
        switch action {
        case .pointer,.primaryDrag,.scroll,.zoom: return "Follow motion"
        default: return "Once per recognition"
        }
    }
    var recognitionNote: String {
        if isRotation { return "Turn a recognized thumb and fingertip group at least 3°. Rotation wins when angular travel dominates radial change. Fires once and remains latched until all-up." }
        if isPinch { return "A recognized thumb is required to begin. Once active, the session continues through added or lifted fingers until all-up." }
        if forceCount != nil { return "Activates at P ≥ 130 on any one contact, using the current contact count. Fires once until all fingers lift." }
        switch self {
        case .fourCornersTap: return "One contact in each outer 25% corner of this pad. Hold uses its configured threshold; movement allowance is 2 mm. Lift all fingers to rearm."
        case .thumbTwoTap: return "A spread thumb plus two fingertips. Fingertip relabeling is tolerated after a match. Tap window: 500 ms."
        case .threeFingerMove: return "Begins with three aligned or gently arched fingertips. Movement latches until all-up, including added or lifted fingers."
        case .twoFingerTap,.threeFingerTap,.fourFingerTap,.fiveFingerTap: return "Tap window: 500 ms. Landing/lift skew: 80 ms. Movement slop: 1 mm. A motion-owned cycle cannot also tap."
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
            setDirectionalAction:{controller.setDirectionalAction($0,direction:$1,for:$2,scope:$3)},
            setDirectionalRepeatInterval:{controller.setDirectionalRepeatInterval($0,direction:$1,for:$2,scope:$3)},
            setDirectionalRepeat:{controller.setDirectionalRepeat($0,direction:$1,for:$2,scope:$3)},
            setTwoHandAction:{controller.setTwoHandAction($0,for:$1)},
            twoHandStatus:{controller.twoHandStatus($0)},
            setHoldAction:{controller.setHoldAction($0,count:$1,scope:$2)},
            setHoldThreshold:{controller.setHoldThreshold($0,count:$1,scope:$2)},
            setTwoHandHoldThreshold:{controller.setTwoHandHoldThreshold($0,chord:$1)},
            holdStatus:{controller.holdStatus(count:$0,scope:$1)},
            setNaturalScrolling:{controller.setNaturalScrolling($0,scope:$1)})
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
    let setDirectionalRepeatInterval: (Double,GestureMovementDirection,GestureTrigger,GestureHandScope) -> Void
    let setDirectionalRepeat: (Bool,GestureMovementDirection,GestureTrigger,GestureHandScope) -> Void
    let setTwoHandAction:(GestureAction,TwoHandTrigger)->Void
    let twoHandStatus:(TwoHandTrigger)->String
    let setHoldAction:(GestureAction,Int,GestureHandScope)->Void
    let setHoldThreshold:(Double,Int,GestureHandScope)->Void
    let setTwoHandHoldThreshold:(Double,TwoHandChord)->Void
    let holdStatus:(Int,GestureHandScope)->String
    let setNaturalScrolling:(Bool,GestureHandScope)->Void
    @State private var twoHandChord = TwoHandChord.fourCorners
    @State private var twoHandPhase = TwoHandPhase.hold
    @State private var selectedHold = false
    @State private var selectedDirection: GestureMovementDirection?
    @AppStorage("AppleMagicTouchstream.mirrorGestureEdits") private var mirrorEdits = false
    @State private var editingHand: GestureHandScope = .left
    @State private var pane: GesturePane
    @State private var selected: GestureTrigger
    @State private var search = ""
    @AppStorage(WorkspaceColumnSizing.gestureNavigationWidthKey) private var menuColumnWidth = WorkspaceColumnSizing.defaultGestureColumnWidth
    @AppStorage(WorkspaceColumnSizing.gestureInspectorWidthKey) private var inspectorColumnWidth = WorkspaceColumnSizing.defaultGestureInspectorWidth

    init(settings:HandGestureSettings, initialPane:GesturePane = .twoFingers,
         initialDirection:GestureMovementDirection? = nil, initialHold:Bool = false, initialHand:GestureHandScope = .left,
         initialTwoHandChord:TwoHandChord = .fourCorners, initialTwoHandPhase:TwoHandPhase = .hold,
         status:@escaping (GestureTrigger,GestureHandScope)->String,
         apply:@escaping (GestureAction,GestureTrigger,GestureHandScope)->Void,
         setSensitivity:@escaping (Double,GestureSensitivity,GestureHandScope)->Void,
         setMovementMode:@escaping (GestureMovementMode,GestureTrigger,GestureHandScope)->Void = {_,_,_ in},
         setDirectionalAction:@escaping (GestureAction,GestureMovementDirection,GestureTrigger,GestureHandScope)->Void = {_,_,_,_ in},
         setDirectionalRepeatInterval:@escaping (Double,GestureMovementDirection,GestureTrigger,GestureHandScope)->Void = {_,_,_,_ in},
         setDirectionalRepeat:@escaping (Bool,GestureMovementDirection,GestureTrigger,GestureHandScope)->Void = {_,_,_,_ in},
         setTwoHandAction:@escaping (GestureAction,TwoHandTrigger)->Void = {_,_ in},
         twoHandStatus:@escaping (TwoHandTrigger)->String = {_ in "Enable Trackpad Takeover on both selected pads."},
         setHoldAction:@escaping (GestureAction,Int,GestureHandScope)->Void = {_,_,_ in},
         setHoldThreshold:@escaping (Double,Int,GestureHandScope)->Void = {_,_,_ in},
         setTwoHandHoldThreshold:@escaping (Double,TwoHandChord)->Void = {_,_ in},
         holdStatus:@escaping (Int,GestureHandScope)->String = {_,_ in "Hold still for 500 ms. Fires once until all-up."},
         setNaturalScrolling:@escaping (Bool,GestureHandScope)->Void = {_,_ in}) {
        self.setNaturalScrolling = setNaturalScrolling
        self.settings = settings; self.status = status; self.apply = apply; self.setSensitivity = setSensitivity
        self.setMovementMode = setMovementMode; self.setDirectionalAction = setDirectionalAction
        self.setDirectionalRepeatInterval = setDirectionalRepeatInterval
        self.setDirectionalRepeat = setDirectionalRepeat
        self.setHoldAction = setHoldAction; self.holdStatus = holdStatus
        self.setHoldThreshold = setHoldThreshold; self.setTwoHandHoldThreshold = setTwoHandHoldThreshold
        self.setTwoHandAction = setTwoHandAction; self.twoHandStatus = twoHandStatus
        _selectedHold = State(initialValue:(initialHold || initialPane == .fourCorners) && Self.holdEditable(pane:initialPane,settings:settings,scope:initialHand))
        _editingHand = State(initialValue:initialHand)
        _twoHandChord = State(initialValue:initialTwoHandChord); _twoHandPhase = State(initialValue:initialTwoHandChord.phases.contains(initialTwoHandPhase) ? initialTwoHandPhase : .hold)
        _pane = State(initialValue:initialPane)
        let first = initialPane.triggers.first(where:{$0.isContinuous && !$0.isRotation}) ?? initialPane.triggers[0]
        _selectedDirection = State(initialValue:initialDirection ?? Self.defaultDirection(for:first,settings:settings,scope:initialHand))
        _selected = State(initialValue:first)
    }

    static func defaultDirection(for trigger:GestureTrigger,settings:HandGestureSettings,scope:GestureHandScope) -> GestureMovementDirection? {
        GestureDirectionalAssignments.triggers.contains(trigger) && settings.movementMode(trigger,in:scope) == .directional ? .up : nil
    }
    static func holdEditable(pane:GesturePane,settings:HandGestureSettings,scope:GestureHandScope) -> Bool {
        !pane.isPinchSection && settings.holdAvailable(count:pane.holdKey,in:scope)
    }
    private func restoreMovementSelection() {
        if selectedHold {
            if Self.holdEditable(pane:pane,settings:settings,scope:editingScope) { return }
            selectedHold = false
        }
        guard editingHand != .both, selected.isContinuous else { return }
        selectedDirection = Self.defaultDirection(for:selected,settings:settings,scope:editingScope)
    }

    private var editingScope: GestureHandScope { mirrorEdits ? .both : editingHand }
    private var action: GestureAction? { settings.action(selected,in:editingScope) }
    private var scopeText: String { editingHand == .both ? "Both hands" : mirrorEdits ? "Left + Right trackpads" : "\(editingHand.rawValue) trackpad" }
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
                        if editingHand == .both {
                            twoHandHeader
                            Divider()
                            twoHandAssignments
                        } else {
                        header
                        Divider()
                        assignments
                        lifecycle
                        Text("Choose a card to edit its action. Changes apply to \(targetText).")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth:.infinity,alignment:.topLeading)
                }
                .frame(maxWidth:.infinity,maxHeight:.infinity)
                WorkspaceColumnDivider(width:Binding(get:{inspectorWidth},set:{inspectorColumnWidth = $0}),
                    minimum:WorkspaceColumnSizing.minimumInspector,maximum:inspectorMaximum,trailingColumn:true,label:"Gesture inspector width")
                Group {
                    if editingHand == .both { twoHandInspector } else { inspector }
                }.frame(width:inspectorWidth)
            }
        }
        .background(Color(nsColor:.windowBackgroundColor))
        .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .onAppear { restoreMovementSelection() }
        .onChange(of:editingScope) { _ in restoreMovementSelection() }
        .onAppear {
            if inspectorColumnWidth == WorkspaceColumnSizing.defaultGestureColumnWidth {
                inspectorColumnWidth = WorkspaceColumnSizing.defaultGestureInspectorWidth
            }
        }
    }

    private var navigation: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack(alignment:.firstTextBaseline,spacing:8) {
                Text("Gestures").font(.title3).bold().layoutPriority(1)
                Spacer(minLength:0)
                Toggle("Mirror Edit", isOn:$mirrorEdits)
                    .toggleStyle(.checkbox)
                    .disabled(editingHand == .both)
                    .font(.caption)
                    .help("Apply action and sensitivity edits to both trackpads. Existing differences stay unchanged until edited; gestures still run independently on each pad.")
            }
            Picker("Edit trackpad",selection:$editingHand) {
                Text("Left").tag(GestureHandScope.left)
                Text("Right").tag(GestureHandScope.right)
                Text("Both").tag(GestureHandScope.both)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth:.infinity)
            .help("Both edits coordinated two-hand gestures. Mirror Edit applies only to independent Left/Right settings.")
            TextField("Search gestures or actions",text:$search)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search gestures or actions")
            ScrollView {
                if editingHand == .both {
                    VStack(alignment:.leading,spacing:8) {
                        Text("COORDINATED TWO-HAND INPUT").font(.caption2).foregroundStyle(.secondary).padding(.horizontal,8)
                        ForEach(([TwoHandChord.threeFingers, .fourFingers] + TwoHandChord.allCases.filter(\.isCorner)).filter { chord in
                            search.isEmpty || (chord.title+" "+settings.twoHand.action(.init(chord:chord,phase:.tap)).title+" "+settings.twoHand.action(.init(chord:chord,phase:.hold)).title).localizedCaseInsensitiveContains(search)
                        }) { chord in
                            Button {
                                twoHandChord = chord; twoHandPhase = chord.isCorner ? .hold : .tap
                            } label: {
                                HStack(spacing:8) {
                                    Circle().fill(twoHandChord == chord ? Color.accentColor : Color.secondary.opacity(0.5)).frame(width:6,height:6)
                                    Text(chord.title).font(.system(size:13,weight:twoHandChord == chord ? .semibold : .regular))
                                    Spacer(minLength:0)
                                }.padding(10).frame(maxWidth:.infinity,alignment:.leading)
                                    .background(twoHandChord == chord ? Color.accentColor.opacity(0.13) : .clear,in:RoundedRectangle(cornerRadius:8))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                } else {
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
            }
            Text(editingHand == .both ? "One gesture uses both selected pads. Mirror Edit is separate." : "\(scopeText) settings")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
        .padding(16)
        .background(Color.primary.opacity(0.025))
    }

    private func navigationItem(_ item:GesturePane) -> some View {
        Button {
            selectedHold = item == .fourCorners
            pane = item
            let first = item.triggers.first(where:{$0.isContinuous && !$0.isRotation}) ?? item.triggers[0]
            selected = first
            selectedDirection = Self.defaultDirection(for:first,settings:settings,scope:editingScope)
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

    private var twoHandTrigger:TwoHandTrigger { .init(chord:twoHandChord,phase:twoHandPhase) }
    private var twoHandHeader:some View {
        VStack(alignment:.leading,spacing:14) {
            Text("Gestures / Both hands").font(.caption).foregroundStyle(.secondary)
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:6) {
                    Text(twoHandChord.title).font(.system(size:25,weight:.semibold))
                    Text(twoHandChord.isCorner ? "Coordinated Hold" : "Coordinated Tap and Hold").font(.callout).foregroundStyle(.secondary)
                    Text(twoHandChord.placementDescription)
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true).padding(.top,10)
                }.frame(maxWidth:.infinity,alignment:.leading)
                TwoHandChordExample(chord:twoHandChord,phase:twoHandPhase)
            }
        }
    }
    private var twoHandAssignments:some View {
        VStack(alignment:.leading,spacing:16) {
            Text("ASSIGNMENTS").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12) {
                ForEach(twoHandChord.phases) { phase in
                    let trigger = TwoHandTrigger(chord:twoHandChord,phase:phase)
                    let selected = twoHandPhase == phase
                    Button { twoHandPhase = phase } label: {
                        VStack(alignment:.leading,spacing:12) {
                            Label(phase.title,systemImage:phase == .tap ? "hand.tap" : "pause.circle").font(.caption).foregroundStyle(.secondary)
                            Text(settings.twoHand.action(trigger).title).font(.headline)
                            Text(phase == .tap ? "Once when both hands lift" : "Once after \(GestureHoldTiming.milliseconds(settings.twoHand.holdThreshold(for:twoHandChord))) ms")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth:.infinity,minHeight:95,alignment:.topLeading).padding(16)
                            .background(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:10))
                            .overlay(RoundedRectangle(cornerRadius:10).stroke(selected ? Color.accentColor : Color.primary.opacity(0.1),lineWidth:selected ? 2 : 1))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            Text(twoHandChord.expandedCornerChord.map {
                    "Before Hold activates, adding the remaining corners can select \($0.title). Lift every finger from both pads to rearm."
                 } ?? (twoHandChord.isCorner
                 ? "Lift every finger from both pads to rearm; changing finger count never transfers this cycle to another gesture."
                 : "A hold consumes the tap. Lift every finger from both pads to rearm; changing finger count never transfers this cycle to another gesture.")
                 )
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
    private var twoHandInspector:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                Text("SELECTED ASSIGNMENT").font(.caption2).foregroundStyle(.secondary)
                Text(twoHandPhase.title).font(.title3).bold()
                Text("\(twoHandChord.title) · Both hands").font(.caption).foregroundStyle(.secondary)
                GestureActionChooser(value:settings.twoHand.action(twoHandTrigger),actions:TwoHandGestureSettings.allowedActions) { setTwoHandAction($0,twoHandTrigger) }
                if twoHandPhase == .hold {
                    holdBehavior(settings.twoHand.action(twoHandTrigger)) { setTwoHandAction($0,twoHandTrigger) }
                    GestureHoldThresholdField(value:settings.twoHand.holdThreshold(for:twoHandChord)) { setTwoHandHoldThreshold($0,twoHandChord) }
                        .id("threshold.both.\(twoHandChord.rawValue)")
                }
                Text(twoHandStatus(twoHandTrigger)).font(.callout).fontWeight(.medium).fixedSize(horizontal:false,vertical:true)
                Divider()
                shortcutBuilder(settings.twoHand.action(twoHandTrigger),allowsHold:twoHandPhase == .hold) { setTwoHandAction($0,twoHandTrigger) }
                Divider()
                Text("Recognition").font(.callout).fontWeight(.medium)
                Text(twoHandPhase == .tap
                     ? "Both chords must lift within 500 ms. Lift skew: 150 ms. Movement slop: 2 mm."
                     : "Keep both chords still for \(GestureHoldTiming.milliseconds(settings.twoHand.holdThreshold(for:twoHandChord))) ms. The assigned action activates after the threshold. Shortcut Behavior chooses one shot or a key held until release.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                Text("Requires two distinct selected pads with Trackpad Takeover active. A joining hand releases the independent gesture. Layer/modifier holds keep priority. Losing contact delivery cancels the gesture.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                Text("Assignments save automatically and are included in keymap exports.").font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }.background(Color.primary.opacity(0.025))
    }

    private var header: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Gestures / \(scopeText)").font(.caption).foregroundStyle(.secondary)
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:6) {
                    Text(pane.group).font(.system(size:25,weight:.semibold))
                    Text(pane.title).font(.callout).foregroundStyle(.secondary)
                    ViewThatFits(in:.horizontal) {
                        HStack(spacing:8) { metadata }
                        VStack(alignment:.leading,spacing:8) { metadata }
                    }.padding(.top,10)
                    Text(pane.summary).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal:false,vertical:true).padding(.top,4)
                }.frame(maxWidth:.infinity,alignment:.leading)
                GestureChordIcon(gesture:pane,trigger:selected,direction:selectedDirection,holding:selectedHold).padding(.leading,8)
            }
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
            ViewThatFits(in:.horizontal) {
                HStack(spacing:12) { assignmentHeading }
                VStack(alignment:.leading,spacing:6) { assignmentHeading }
            }
            if pane.isPinchSection {
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12) {
                    ForEach(pane.triggers) { assignmentCard($0) }
                }
            } else if pane.triggers.contains(where: { $0.isContinuous && !$0.isRotation }) {
                ForEach(pane.triggers.filter { $0.isContinuous && !$0.isRotation }) { movementCross($0) }
            } else {
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12) {
                    ForEach(pane.triggers.filter { !$0.isContinuous && !$0.isRotation && $0 != .fourCornersTap }) { assignmentCard($0) }
                    if pane == .thumbTwo || pane == .fourCorners || pane == .fiveFingers { holdCard }
                    ForEach(pane.triggers.filter(\.isRotation)) { assignmentCard($0) }
                }
            }
        }
    }
    @ViewBuilder private var assignmentHeading:some View {
        Text(pane.isPinchSection ? "SHAPE ASSIGNMENTS" : "ASSIGNMENTS")
            .font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
        if !pane.isPinchSection && pane.triggers.contains(where: { $0.isContinuous && !$0.isRotation }) {
            Text("Use continuous movement or separate directional actions.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func movementCross(_ trigger:GestureTrigger) -> some View {
        let mode = settings.movementMode(trigger,in:editingScope)
        return VStack(alignment:.leading,spacing:10) {
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
                holdCard
                movementCard(trigger,direction:.down)
                Color.clear.frame(height:1)
            }
            if mode != .continuous {
                Text(mode == nil ? "Mixed movement modes." : "Directional actions are active. Continuous movement is inactive.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
        }
    }

    private func movementCard(_ trigger:GestureTrigger,direction:GestureMovementDirection?) -> some View {
        let mode = settings.movementMode(trigger,in:editingScope)
        let targetMode: GestureMovementMode = direction == nil ? .continuous : .directional
        let active = mode == targetMode
        let isSelected = !selectedHold && selected == trigger && selectedDirection == direction
        let assigned = direction.map { settings.directionalAction($0,for:trigger,in:editingScope) } ?? settings.action(trigger,in:editingScope)
        let title = direction.map { "Move " + $0.title } ?? "Movement"
        let followsMotion = assigned?.isDirectionalScroll == true
        let repeatLabel = direction.flatMap { settings.directionalRepeatInterval($0,for:trigger,in:editingScope) }
            .map { $0 > 0 ? "Repeat every \(Int($0)) ms" : "Once per direction" } ?? "Mixed repeat"
        return Button {
            selectedHold = false; selected = trigger; selectedDirection = direction
            if mode != targetMode { setMovementMode(targetMode,trigger,editingScope) }
        } label: {
            VStack(alignment:.leading,spacing:8) {
                Label(title,systemImage:direction?.symbol ?? "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.caption).foregroundStyle(.secondary)
                Text(assigned?.title ?? "Mixed").font(.system(size:16,weight:.medium))
                    .fixedSize(horizontal:false,vertical:true)
                Text(active ? (direction == nil ? "Continuous" : followsMotion ? "Follows motion" : repeatLabel) : "Inactive · click to switch")
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
        return Button { selectedHold = false; selected = trigger; selectedDirection = nil } label: {
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
            .background(!selectedHold && selected == trigger ? Color.accentColor.opacity(0.07) : Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:10))
            .overlay(RoundedRectangle(cornerRadius:10).stroke(!selectedHold && selected == trigger ? Color.accentColor : Color.primary.opacity(0.12),lineWidth:1))
            .contentShape(RoundedRectangle(cornerRadius:10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(trigger.assignmentTitle), \(assigned?.title ?? "Mixed")")
        .accessibilityAddTraits(!selectedHold && selected == trigger ? [.isSelected] : [])
    }

    private var holdCount:Int { pane.holdCount }
    private var holdKey:Int { pane.holdKey }
    private var holdDuration:Double { settings.holdThreshold(count:holdKey,in:editingScope) ?? GestureHoldTiming.defaultSeconds }
    private var holdTimingDescription:String {
        settings.holdThreshold(count:holdKey,in:editingScope).map { "\(GestureHoldTiming.milliseconds($0)) ms" } ?? "each pad’s configured threshold"
    }
    private var holdEditable:Bool { Self.holdEditable(pane:pane,settings:settings,scope:editingScope) }
    private var holdCard:some View {
        let value = settings.holdAction(count:holdKey,in:editingScope)
        return Button { selectedHold = true; selectedDirection = nil } label: {
            VStack(alignment:.leading,spacing:8) {
                Label("Hold",systemImage:"pause").font(.callout).foregroundStyle(.secondary)
                Text(value?.title ?? "Mixed").font(.system(size:17,weight:.medium))
                    .fixedSize(horizontal:false,vertical:true)
                Text(settings.holdThreshold(count:holdKey,in:editingScope) == nil ? "Mixed hold thresholds" : "After \(GestureHoldTiming.milliseconds(holdDuration)) ms · \(value?.isHeldShortcut == true ? "held until release" : "once while held")")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            .padding(14).frame(maxWidth:.infinity,minHeight:pane.triggers.contains(where: { $0.isContinuous && !$0.isRotation }) ? 106 : 112,alignment:.topLeading)
            .background(selectedHold ? Color.accentColor.opacity(0.07) : Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:9))
            .overlay(RoundedRectangle(cornerRadius:9).stroke(selectedHold ? Color.accentColor : Color.primary.opacity(0.12),lineWidth:1))
            .contentShape(RoundedRectangle(cornerRadius:9))
        }
        .buttonStyle(.plain).disabled(!holdEditable).opacity(holdEditable ? 1 : 0.5)
        .accessibilityLabel("Hold, \(value?.title ?? "Mixed")")
        .accessibilityAddTraits(selectedHold ? [.isSelected] : [])
    }
    private func shortcutBuilder(_ value:GestureAction?,allowsHold:Bool = false,
                                 apply:@escaping (GestureAction)->Void) -> some View {
        VStack(alignment:.leading,spacing:14) {
            Divider()
            ShortcutActionBuilder(action:value?.shortcutAssignment?.action,allowsHold:allowsHold,
                holdUntilRelease:value?.isHeldShortcut == true) { action,held in
                    var library = ShortcutActionLibraryStorage.decode(from:UserDefaults.standard.data(forKey:GlassToKeyDefaultsKeys.shortcutActions) ?? Data()) ?? []
                    library.append(action.storageLabel)
                    UserDefaults.standard.set(ShortcutActionLibraryStorage.encode(library),forKey:GlassToKeyDefaultsKeys.shortcutActions)
                    apply(.shortcut(.init(label:action.storageLabel,holdUntilRelease:held)))
                }
                .id("\(editingHand.rawValue).\(mirrorEdits).\(pane.rawValue).\(selected.rawValue).\(selectedHold).\(selectedDirection?.rawValue ?? "none").\(twoHandChord.rawValue).\(twoHandPhase.rawValue)")
        }
    }
    private func holdBehavior(_ value:GestureAction?,apply:@escaping (GestureAction)->Void) -> some View {
        Picker("Behavior",selection:Binding(
            get:{ value?.isHeldShortcut == true },
            set:{ held in
                guard var shortcut = value?.shortcutAssignment, shortcut.action?.kind == .key else { return }
                shortcut.holdUntilRelease = held
                apply(.shortcut(shortcut))
            })) {
                Text("Once after threshold").tag(false)
                Text("Hold until release").tag(true)
            }
            .disabled(value?.shortcutAssignment?.action?.kind != .key)
            .help("Choose or apply a keyboard shortcut to enable Hold until release. Changes save automatically.")
    }
    private var holdInspector:some View {
        let value = settings.holdAction(count:holdKey,in:editingScope)
        return VStack(alignment:.leading,spacing:14) {
            GestureActionChooser(value:value,actions:PerHandGestureSettings.holdActions(for:holdKey)) { action in
                if holdEditable { setHoldAction(action,holdKey,editingScope) }
            }.disabled(!holdEditable)
            holdBehavior(value) { if holdEditable { setHoldAction($0,holdKey,editingScope) } }
                .disabled(!holdEditable)
            GestureHoldThresholdField(value:settings.holdThreshold(count:holdKey,in:editingScope)) {
                if holdEditable { setHoldThreshold($0,holdKey,editingScope) }
            }.disabled(!holdEditable).id("threshold.\(editingScope.rawValue).\(holdKey)")
            if value == nil {
                Text("Left: \(settings.left.holdAction(count:holdKey).title) · Right: \(settings.right.holdAction(count:holdKey).title)")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            Text(holdStatus(holdKey,editingScope)).font(.callout).fixedSize(horizontal:false,vertical:true)
            shortcutBuilder(value,allowsHold:true) { if holdEditable { setHoldAction($0,holdKey,editingScope) } }
            Divider()
            Text("Recognition").font(.callout).fontWeight(.medium)
            Text(pane == .fourCorners
                 ? "One contact in each outer 25% corner of this pad. Hold for \(holdTimingDescription); the action fires while fingers are down. Movement over 2 mm, early lifts or lost input cancel output. Lift all fingers to rearm."
                 : "Keep \(holdCount) finger(s) still for \(holdTimingDescription). The action fires while the fingers are down; lifting is not required. Shortcut Behavior chooses one shot or a key held until release. The gesture owns the cycle until all-up. Movement or a pinch/spread that starts first cancels the pending Hold.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            if pane == .thumbTwo {
                Text("Requires the same spread-thumb geometry as Thumb+2 Tap. This Hold is independent of ordinary three-finger Hold. A matched chord tolerates fingertip relabeling.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            Text("The originating trackpad owns this gesture's output.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
    private var lifecycle: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("SESSION LIFETIME").font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
            HStack(alignment:.top,spacing:12) {
                if pane.isPinchSection || pane == .oneFinger {
                    lifetimeCard("Hold",symbol:"pause",detail:"No separate gesture is available for this.")
                } else if !pane.triggers.contains(where: { $0.isContinuous && !$0.isRotation }) && pane != .thumbTwo && pane != .fourCorners && pane != .fiveFingers { holdCard }
                lifetimeCard("Lift",symbol:"arrow.up",detail:"All-up ends the session and releases its held outputs. Scroll momentum may continue.")
            }.fixedSize(horizontal:false,vertical:true)
        }
    }
    private func lifetimeCard(_ title:String,symbol:String,detail:String) -> some View {
        VStack(alignment:.leading,spacing:8) {
            Label(title,systemImage:symbol).font(.callout).foregroundStyle(.secondary)
            Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Text("Automatic · not assignable").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(14).frame(maxWidth:.infinity,maxHeight:pane.isPinchSection ? .infinity : nil,alignment:.topLeading)
        .background(Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:9))
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                VStack(alignment:.leading,spacing:8) {
                    Text("SELECTED ASSIGNMENT").font(.caption2).fontWeight(.medium).foregroundStyle(.secondary)
                    Text(selectedHold ? "Hold" : selectedDirection.map { "Move " + $0.title } ?? selected.assignmentTitle).font(.title3).bold()
                    Text("\(pane.group) · \(scopeText)").font(.caption).foregroundStyle(.secondary)
                }
                if selectedHold {
                    holdInspector
                } else if let direction = selectedDirection {
                    directionalInspector(direction)
                } else {
                    GestureActionPickerRow(trigger:selected,value:action,
                        leftAction:settings.left.bindings.action(for:selected),
                        rightAction:settings.right.bindings.action(for:selected),
                        status:status(selected,editingScope),showsStatus:true) { value in
                            apply(value,selected,editingScope)
                        }
                    Divider()
                    if let action {
                        if action.requiresPointerProfile { sensitivity("Pointer sensitivity",kind:.pointer) }
                        if action == .scroll {
                            sensitivity("Scroll sensitivity",kind:.scroll)
                            naturalScrollingToggle
                        }
                    }
                    VStack(alignment:.leading,spacing:8) {
                        Text("Behavior").font(.caption).foregroundStyle(.secondary)
                        Text(selected.behavior(for:action)).font(.callout).fontWeight(.medium)
                        Text(behaviorDetail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    }
                    if action == .zoom { sensitivity("Zoom sensitivity",kind:.zoom) }
                    if !GestureDirectionalAssignments.triggers.contains(selected) {
                        shortcutBuilder(action) { apply($0,selected,editingScope) }
                    }
                    Divider()
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
        let repeatEnabled = settings.directionalRepeats(direction,for:selected,in:editingScope)
        let repeatOff = repeatEnabled == false
        return VStack(alignment:.leading,spacing:14) {
            GestureActionChooser(value:value,actions:GestureDirectionalAssignments.allowedActions) { setDirectionalAction($0,direction,selected,editingScope) }
            if value == nil {
                Text("Left: \(settings.left.movement(selected).action(direction).title) · Right: \(settings.right.movement(selected).action(direction).title)")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            if value?.isDirectionalScroll == true {
                Text("Follows \(direction.title.lowercased()) finger travel and speed. Output direction comes from this action; reversing the assignments reverses scrolling or panning. Pausing stops output; release can coast with momentum.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                sensitivity("Scroll sensitivity",kind:.scroll)
            } else {
            HStack(spacing:6) {
                Button {
                    setDirectionalRepeat(repeatEnabled != true,direction,selected,editingScope)
                } label: {
                    ZStack {
                        Image(systemName:"repeat")
                        if repeatOff { Rectangle().frame(width:20,height:1.5).rotationEffect(.degrees(-45)) }
                    }.frame(width:22,height:22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(repeatOff ? Color.secondary : Color.accentColor)
                .accessibilityLabel("Repeat while held")
                .accessibilityValue(repeatEnabled.map { $0 ? "On" : "Off" } ?? "Mixed")
                .help(repeatOff ? "Enable repeat" : "Disable repeat")
                GestureRepeatIntervalField(value:settings.directionalConfiguredRepeatInterval(direction,for:selected,in:editingScope),
                    enabled:!repeatOff) { setDirectionalRepeatInterval($0,direction,selected,editingScope) }
                    .id("\(selected.rawValue).\(direction.rawValue).\(editingScope.rawValue)")
                Text("ms while held").font(.callout)
                if repeatOff { Text("Off").font(.caption).fontWeight(.medium) }
            }
            .foregroundStyle(repeatOff ? Color.secondary : Color.primary)
            .help("Click the loop to toggle repeat. Enabled intervals range from 20 to 5000 ms. Press Return to apply the interval.")
            Text("20–5000 ms · Click loop to toggle repeat").font(.caption).foregroundStyle(.secondary)
            if settings.directionalRepeatInterval(direction,for:selected,in:editingScope) == nil {
                Text("Mixed intervals. Editing applies to both pads.").font(.caption).foregroundStyle(.secondary)
            }
            }
            shortcutBuilder(value) { setDirectionalAction($0,direction,selected,editingScope) }
            Divider()
            if GestureDirectionalAssignments.liveTriggers.contains(selected) {
                Text(status(selected,editingScope)).font(.callout).fontWeight(.medium)
                Text("Move \(selected == .twoFingerMove ? "two fingertips" : selected == .threeFingerMove ? "three aligned fingertips" : selected == .fourFingerMove ? "four fingertips" : "five fingers") 0.75 mm to choose a direction. A deliberate reversal or turn chooses a new direction. The chord stays latched until all fingers lift.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            } else {
                Text("Directional output is not implemented yet.").font(.callout).fontWeight(.medium)
                Text("This assignment and its repeat choice are saved. Live direction recognition supports two through five fingers. Continuous movement is inactive in directional mode.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            Text("Choose the center Movement card to restore continuous movement. Assignments are preserved when switching modes.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }

    private var behaviorDetail:String {
        if selected.isRotation { return "Fires once when rotation activates. Continuing or reversing the turn cannot fire another action until all fingers lift." }
        guard let action, action != .disabled else { return "Choose an action to enable this input for the selected trackpad." }
        if action.shortcutAssignment != nil { return "Runs the assigned shortcut once when this gesture is recognized. The gesture keeps its existing latch until all-up." }
        if action.isAppleShortcut { return selected.isPinch ? "Fires once when the gesture activates. Continuing or reversing the motion does not fire again before all-up." : "Fires once when this tap or pressure gesture is recognized." }
        switch action {
        case .primaryDrag: return "Holds the primary mouse button through the drag, using the same pointer acceleration as mouse movement."
        case .scroll: return "Precise scrolling follows motion, with momentum after release."
        case .zoom: return "Continuous native magnification follows scale changes. The active action stays latched until all-up."
        case .pointer: return "Pointer movement follows the selected trackpad's Apple acceleration profile."
        default: return "A completed recognition sends one balanced click sequence."
        }
    }
    private var naturalScrollingToggle:some View {
        let systemValue = UserDefaults.standard.persistentDomain(forName:UserDefaults.globalDomain)?["com.apple.swipescrolldirection"] as? Bool ?? true
        let value = settings.naturalScrolling(in:editingScope,fallback:systemValue)
        return VStack(alignment:.leading,spacing:5) {
            Toggle("Natural scrolling",isOn:Binding(get:{value ?? false},set:{setNaturalScrolling($0,editingScope)}))
            if value == nil { Text("Mixed between trackpads").font(.caption).foregroundStyle(.secondary) }
            Text("Applies to normal Scroll / Pan. Directional Scroll and Pan actions keep their explicit direction.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
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
    static let defaultGestureInspectorWidth = defaultMenuWidth
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


private struct TwoHandChordExample:View {
    let chord:TwoHandChord
    let phase:TwoHandPhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    @State private var start = Date()
    var body:some View {
        TimelineView(.animation(minimumInterval:1.0/30,paused:!visible || reduceMotion)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start).truncatingRemainder(dividingBy:3)
            let release = phase == .hold ? 2.3 : 1.1
            let filled = phase == .hold || reduceMotion || (elapsed > 0.4 && elapsed < release)
            let opacity = reduceMotion ? 1 : GestureExampleFade.opacity(elapsed/3,start:release/3,end:release/3+0.14)
            Canvas { context,size in
                for hand in 0..<2 {
                    let rect = CGRect(x:CGFloat(hand)*100+4,y:5,width:92,height:65)
                    context.stroke(Path(roundedRect:rect,cornerRadius:8),with:.color(.secondary.opacity(0.5)),lineWidth:1.7)
                    var contacts = context
                    contacts.opacity *= opacity
                    for finger in 0..<chord.count {
                        let cornerMask = chord.cornerMask(leftHand:hand == 0)
                        let corner = cornerMask != nil
                        let leftEdge = (cornerMask ?? 0) & 0b0011 != 0
                        let topEdge = chord.count == 2 ? finger == 0 : (cornerMask ?? 0) & 0b1010 != 0
                        // Index is toward the center seam; pinky toward the outer edge.
                        let fingerOffset = CGFloat(finger)*14-CGFloat(chord.count-1)*7
                        let x = corner ? (leftEdge ? rect.minX+10 : rect.maxX-10)
                            : rect.midX+(hand == 0 ? -fingerOffset : fingerOffset)
                        let y = corner ? (topEdge ? rect.minY+10 : rect.maxY-10) : rect.midY-CGFloat(finger == 1 ? 5 : 0)
                        let color:Color = corner
                            ? Color(nsColor:AnatomicalFingerPalette.color(fingerID:chord.count == 1 || finger == 0 ? 2 : 1))
                            : [.blue,.green,.purple,.pink][finger]
                        let dot = Path(ellipseIn:CGRect(x:x-4,y:y-4,width:8,height:8))
                        contacts.fill(dot,with:.color(color.opacity(filled ? 0.8 : 0.1)))
                        contacts.stroke(dot,with:.color(color),lineWidth:1.2)
                    }
                }
            }.frame(width:200,height:75)
        }
        .background(GestureExampleWindowVisibility { value in visible = value; if value { start = Date() } }.frame(width:0,height:0))
        .onChange(of:chord) { _ in start = Date() }.onChange(of:phase) { _ in start = Date() }
        .accessibilityLabel("Both hands: \(chord.title), \(phase.title)")
    }
}


/// Keep incomplete typing local; clamp only on Return or leaving the field.
struct GestureRepeatIntervalField:View {
    let value:Double?
    let enabled:Bool
    let commit:(Double)->Void
    @State private var draft = ""
    @FocusState private var focused:Bool
    static func committedValue(_ text:String) -> Double? {
        guard let number = Double(text.trimmingCharacters(in:.whitespacesAndNewlines)), number.isFinite else { return nil }
        return min(5000,max(20,number.rounded()))
    }
    private func sync() { draft = value.map { String(Int($0)) } ?? "" }
    private func apply(explicit:Bool = false) {
        guard let result = Self.committedValue(draft) else { sync(); return }
        draft = String(Int(result))
        // Return is an explicit assignment, including when repeat enablement is
        // mixed but the configured interval happens to match on both pads.
        if explicit || result != value { commit(result) }
    }
    var body:some View {
        TextField(value == nil ? "Mixed" : "20",text:$draft)
            .textFieldStyle(.plain).font(.system(size:11).monospacedDigit())
            .multilineTextAlignment(.center).padding(.vertical,3).frame(width:32.5)
            .background(RoundedRectangle(cornerRadius:5).fill(Color(nsColor:.textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius:5).strokeBorder(Color.primary.opacity(0.15),lineWidth:1))
            .focused($focused).disabled(!enabled)
            .onAppear { sync() }
            .onSubmit { apply(explicit:true) }
            .onChange(of:focused) { value in if !value && enabled { apply() } }
            .onChange(of:value) { _ in if !focused { sync() } }
            .onChange(of:enabled) { enabled in if !enabled { focused = false; sync() } }
            .accessibilityLabel("Repeat interval in milliseconds")
    }
}

/// Shared searchable chooser for keymap and gesture actions; recognition types
/// remain independent. This only builds UI values, never input clients/output.
struct SearchableActionGroup<Value:Hashable>:Identifiable {
    let title:String
    let actions:[Value]
    var id:String { title }
    static func filtered(_ groups:[Self],query:String,label:(Value)->String) -> [Self] {
        let term = query.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !term.isEmpty else { return groups }
        return groups.compactMap { group in
            let matches = group.actions.filter { label($0).localizedCaseInsensitiveContains(term) }
            return matches.isEmpty ? nil : Self(title:group.title,actions:matches)
        }
    }
}
struct SearchableActionSheet<Value:Hashable>:View {
    let title:String
    let groups:[SearchableActionGroup<Value>]
    let selected:Value?
    let label:(Value)->String
    var searchLabel:((Value)->String)? = nil
    var manageShortcuts:(()->Void)? = nil
    let choose:(Value)->Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @FocusState private var searchFocused:Bool
    var body:some View {
        let filtered = SearchableActionGroup.filtered(groups,query:searchText,label:searchLabel ?? label)
        return VStack(alignment:.leading,spacing:12) {
            HStack(alignment:.top,spacing:12) {
                VStack(alignment:.leading,spacing:4) {
                    Text(title).font(.headline)
                    Text("Current: \(selected.map(label) ?? "Mixed")").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            TextField("Filter actions",text:$searchText).textFieldStyle(.roundedBorder).focused($searchFocused)
            if filtered.isEmpty {
                VStack(spacing:8) {
                    Image(systemName:"magnifyingglass").font(.system(size:18,weight:.semibold)).foregroundStyle(.secondary)
                    Text("No matching actions").font(.headline)
                    Text("Try a different search.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment:.leading,spacing:14) {
                        ForEach(filtered) { group in
                            VStack(alignment:.leading,spacing:6) {
                                Text(group.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                VStack(alignment:.leading,spacing:4) {
                                    ForEach(group.actions,id:\.self) { action in
                                        Button { choose(action); dismiss() } label: {
                                            HStack(spacing:8) {
                                                Image(systemName:action == selected ? "checkmark.circle.fill" : "circle")
                                                    .font(.system(size:12,weight:.semibold))
                                                    .foregroundStyle(action == selected ? Color.accentColor : Color.secondary)
                                                Text(label(action)).frame(maxWidth:.infinity,alignment:.leading).multilineTextAlignment(.leading)
                                            }
                                            .padding(.horizontal,10).padding(.vertical,7)
                                            .background(RoundedRectangle(cornerRadius:8).fill(action == selected ? Color.accentColor.opacity(0.12) : Color.clear))
                                            .contentShape(Rectangle())
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }.padding(.vertical,2)
                }
            }
            if let manageShortcuts {
                Divider()
                Button(action:manageShortcuts) {
                    Label("Manage Shortcuts…",systemImage:"slider.horizontal.3")
                }.buttonStyle(.borderless)
            }
        }
        .padding(16).frame(minWidth:460,idealWidth:540,minHeight:420,idealHeight:560)
        .onAppear { searchFocused = true }
    }
}
struct GestureActionChooser:View {
    let value:GestureAction?
    let actions:[GestureAction]
    let choose:(GestureAction)->Void
    @State private var showing = false
    @State private var managingShortcuts = false
    @AppStorage(GlassToKeyDefaultsKeys.shortcutActions) private var shortcutLibrary = Data()
    private var pickerGroups:[SearchableActionGroup<GestureAction>] {
        let labels = ["Shift","Ctrl","Option","Cmd","Hyper"] + (ShortcutActionLibraryStorage.decode(from:shortcutLibrary) ?? [])
        var seen:Set<GestureAction> = []
        let shortcuts = labels.compactMap { KeyActionCatalog.action(for:$0) }.filter { $0.kind == .key || $0.kind == .appLaunch }
            .map { GestureAction.shortcut(.init(label:$0.storageLabel)) }.filter { seen.insert($0).inserted }
        let current:[SearchableActionGroup<GestureAction>] = value.flatMap { value in
            value.shortcutAssignment != nil && !shortcuts.contains(value) ? [.init(title:"Current Assignment",actions:[value])] : nil
        } ?? []
        return Self.groups(actions) + current + (shortcuts.isEmpty ? [] : [.init(title:"Shortcuts",actions:shortcuts)])
    }
    static func groups(_ actions:[GestureAction]) -> [SearchableActionGroup<GestureAction>] {
        let definitions:[(String,[GestureAction])] = [
            ("General",[.disabled]),
            ("Movement",[.pointer,.primaryDrag,.scroll,.zoom,.scrollUp,.scrollDown,.panLeft,.panRight]),
            ("Mouse Buttons",[.primaryClick,.primaryDoubleClick,.secondaryClick]),
            ("System",GestureAction.appleShortcuts),
            ("Sound & Display",GestureAction.smallStepActions),
            ("Application",[.openConfig])]
        return definitions.compactMap { title, values in
            let matches = values.filter { actions.contains($0) }
            return matches.isEmpty ? nil : .init(title:title,actions:matches)
        }
    }
    var body:some View {
        HStack {
            Text("Action")
            Button { showing = true } label: {
                HStack {
                    Text(value?.title ?? "Mixed").frame(maxWidth:.infinity,alignment:.leading)
                    Image(systemName:"chevron.up.chevron.down").font(.caption2)
                }.frame(maxWidth:.infinity)
            }.buttonStyle(.bordered).accessibilityLabel("Action, \(value?.title ?? "Mixed")")
        }
        .sheet(isPresented:$showing) {
            SearchableActionSheet(title:"Gesture Action",groups:pickerGroups,selected:value,label:{$0.title},
                manageShortcuts:{ managingShortcuts = true },choose:choose)
                .sheet(isPresented:$managingShortcuts) { ShortcutLibraryManager() }
        }
    }
}

/// The same builder edits Keyboard and Gesture actions; applying never posts input.
struct ShortcutActionBuilder:View {
    let action:KeyAction?
    var enabled = true
    var allowsHold = false
    var holdUntilRelease = false
    let apply:(KeyAction,Bool)->Void
    @State private var shortcutModifiers:[ShortcutModifier:ShortcutModifierVariant] = [:]
    @State private var shortcutModifierPicker:ShortcutModifier?
    @State private var suppressShortcutModifierTap:ShortcutModifier?
    @State private var shortcutKeyLabel = ""
    @State private var shortcutName = ""
    @State private var appLaunchTarget = ""
    @State private var appLaunchArguments = ""
    @State private var held = false
    private var canEditActionBuilder:Bool { enabled }
    private let shortcutBuilderActionButtonWidth:CGFloat = 84
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Text("Shortcut Builder").font(.callout).fontWeight(.medium)
                    HStack(spacing:8) {
                        Text("Name").font(.caption).foregroundStyle(.secondary)
                        TextField("Optional shortcut name",text:$shortcutName)
                            .textFieldStyle(.roundedBorder).disabled(!canEditActionBuilder)
                    }
                    HStack(spacing: 8) {
                        ForEach(ShortcutModifier.ordered, id: \.self) { modifier in
                            shortcutModifierButton(modifier)
                        }
                    }
                    Text("Click to toggle. Hold to choose generic, left, or right. Leave Key at None for modifiers only.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Text("Key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Shortcut Key", selection: shortcutKeyBinding) {
                            Text("None").tag("")
                            ForEach(KeyActionCatalog.shortcutKeyLabels, id: \.self) { label in
                                Text(label).tag(label)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .labelsHidden()
                        .disabled(!canEditActionBuilder)
                        Button("Apply") {
                            if let builtAction { apply(builtAction, allowsHold && held && builtAction.kind == .key) }
                        }
                        .buttonStyle(.bordered)
                        .frame(width: shortcutBuilderActionButtonWidth)
                        .disabled(!canEditActionBuilder || builtAction == nil)
                    }

                    HStack(spacing: 8) {
                        Text("App")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("App, file, folder, or URL", text: appLaunchTargetBinding)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!canEditActionBuilder)
                        Button("Browse") {
                            browseForAppTarget()
                        }
                        .buttonStyle(.bordered)
                        .frame(width: shortcutBuilderActionButtonWidth)
                        .disabled(!canEditActionBuilder)
                    }
                    Text(actionBuilderPreview)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

        }
        .onAppear { sync() }
        .onChange(of:action) { _ in sync() }
        .onChange(of:holdUntilRelease) { _ in held = holdUntilRelease }
    }
    private func sync() {
        clearShortcutBuilderState(); shortcutName = action?.customName ?? ""
        appLaunchTarget = ""; appLaunchArguments = ""; held = holdUntilRelease
        guard let action else { return }
        if let spec = KeyActionCatalog.appLaunchSpec(for:action) {
            appLaunchTarget = spec.fileName; appLaunchArguments = spec.arguments
        } else if let spec = KeyActionCatalog.shortcutSpec(for:action) {
            shortcutModifiers = spec.modifiers; shortcutKeyLabel = spec.keyLabel
        }
    }
        private var shortcutKeyBinding: Binding<String> {
            Binding(
                get: { shortcutKeyLabel },
                set: { newValue in
                    if !newValue.isEmpty {
                        appLaunchTarget = ""
                    }
                    shortcutKeyLabel = newValue
                }
            )
        }

        private var appLaunchTargetBinding: Binding<String> {
            Binding(
                get: { appLaunchTarget },
                set: { newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        clearShortcutBuilderState(); held = false
                    }
                    if newValue != appLaunchTarget { appLaunchArguments = "" }
                    appLaunchTarget = newValue
                }
            )
        }

        private func shortcutModifierPickerBinding(
            for modifier: ShortcutModifier
        ) -> Binding<Bool> {
            Binding(
                get: { shortcutModifierPicker == modifier },
                set: { isPresented in
                    if isPresented {
                        shortcutModifierPicker = modifier
                    } else if shortcutModifierPicker == modifier {
                        shortcutModifierPicker = nil
                        if suppressShortcutModifierTap == modifier {
                            suppressShortcutModifierTap = nil
                        }
                    }
                }
            )
        }

        private func setShortcutModifier(
            _ modifier: ShortcutModifier,
            variant: ShortcutModifierVariant?
        ) {
            if let variant {
                appLaunchTarget = ""
                shortcutModifiers[modifier] = variant
            } else {
                shortcutModifiers.removeValue(forKey: modifier)
            }
        }

        private func toggleShortcutModifier(_ modifier: ShortcutModifier) {
            if shortcutModifiers[modifier] == nil {
                setShortcutModifier(modifier, variant: .generic)
            } else {
                setShortcutModifier(modifier, variant: nil)
            }
        }

        private func presentShortcutModifierPicker(for modifier: ShortcutModifier) {
            guard canEditActionBuilder else { return }
            suppressShortcutModifierTap = modifier
            shortcutModifierPicker = modifier
        }

        private func chooseShortcutModifierVariant(
            _ modifier: ShortcutModifier,
            variant: ShortcutModifierVariant
        ) {
            setShortcutModifier(modifier, variant: variant)
            shortcutModifierPicker = nil
            suppressShortcutModifierTap = nil
        }

        private func handleShortcutModifierButtonTap(_ modifier: ShortcutModifier) {
            if suppressShortcutModifierTap == modifier {
                suppressShortcutModifierTap = nil
                return
            }
            toggleShortcutModifier(modifier)
        }

        private func shortcutModifierButton(_ modifier: ShortcutModifier) -> some View {
            let activeVariant = shortcutModifiers[modifier]
            let isSelected = activeVariant != nil
            let label = modifier.buttonLabel(for: activeVariant ?? .generic)

            return Button {
                handleShortcutModifierButtonTap(modifier)
            } label: {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                isSelected
                                    ? Color.accentColor.opacity(0.14)
                                    : Color(nsColor: .controlBackgroundColor)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                isSelected
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.24),
                                lineWidth: 1
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canEditActionBuilder)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35)
                    .onEnded { _ in
                        presentShortcutModifierPicker(for: modifier)
                    }
            )
            .popover(
                isPresented: shortcutModifierPickerBinding(for: modifier),
                arrowEdge: .bottom
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Use \(modifier.buttonLabel(for: .generic))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(ShortcutModifierVariant.allCases, id: \.self) { variant in
                        Button {
                            chooseShortcutModifierVariant(modifier, variant: variant)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: shortcutModifiers[modifier] == variant ? "checkmark" : "circle")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(
                                        shortcutModifiers[modifier] == variant
                                            ? Color.accentColor
                                            : Color.secondary
                                    )
                                Text(modifier.menuLabel(for: variant))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .frame(minWidth: 190)
            }
        }

        private var builtShortcutAction: KeyAction? {
            KeyActionCatalog.shortcutAction(
                modifiers: shortcutModifiers,
                keyLabel: shortcutKeyLabel
            )
        }

        private var builtAppLaunchAction: KeyAction? {
            KeyActionCatalog.appLaunchAction(fileName: appLaunchTarget, arguments: appLaunchArguments)
        }

        private var builtAction: KeyAction? {
            guard var action = builtAppLaunchAction ?? builtShortcutAction else { return nil }
            action.customName = NamedShortcutStorage.normalizedName(shortcutName)
            return action
        }

        private var actionBuilderPreview: String {
            if let action = builtAppLaunchAction {
                return action.pickerText
            }
            if let action = builtShortcutAction {
                return "Shortcut: \(action.pickerText)"
            }
            return "Shortcut: none"
        }

        private func clearShortcutBuilderState() {
            shortcutModifiers = [:]
            shortcutModifierPicker = nil
            suppressShortcutModifierTap = nil
            shortcutKeyLabel = ""
        }

        private func browseForAppTarget() {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.resolvesAliases = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            appLaunchTarget = url.path; appLaunchArguments = ""; held = false
            clearShortcutBuilderState()
        }

}


/// Shared saved-library editor. Bindings keep their own action values; only the
/// library preference changes here, including when a saved entry is replaced.
struct ShortcutLibraryManager:View {
    @AppStorage(GlassToKeyDefaultsKeys.shortcutActions) private var storedActions = Data()
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var editing:String?
    init(initialEditing:String? = nil) { _editing = State(initialValue:initialEditing) }
    private var labels:[String] { ShortcutActionLibraryStorage.decode(from:storedActions) ?? [] }
    private var filtered:[KeyAction] {
        labels.compactMap { KeyActionCatalog.action(for:$0) }.filter {
            search.isEmpty || ($0.pickerText+" "+$0.label).localizedCaseInsensitiveContains(search)
        }
    }
    private func write(_ labels:[String]) { storedActions = ShortcutActionLibraryStorage.encode(labels) ?? Data() }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Text("Manage Shortcuts").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Changing this list leaves existing key and gesture assignments unchanged.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            TextField("Search saved shortcuts",text:$search).textFieldStyle(.roundedBorder)
            if filtered.isEmpty {
                VStack(spacing:8) {
                    Image(systemName:labels.isEmpty ? "list.bullet.rectangle" : "magnifyingglass").font(.title2).foregroundStyle(.secondary)
                    Text(labels.isEmpty ? "No saved shortcuts" : "No matching shortcuts").font(.headline)
                    Text(labels.isEmpty ? "Apply a shortcut in either Shortcut Builder to add it here." : "Try a different search.")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing:6) {
                        ForEach(filtered,id:\.storageLabel) { action in
                            HStack(spacing:12) {
                                VStack(alignment:.leading,spacing:3) {
                                    Text(action.pickerText).font(.callout).frame(maxWidth:.infinity,alignment:.leading)
                                    if action.customName != nil {
                                        Text(action.commandText).font(.caption).foregroundStyle(.secondary)
                                            .lineLimit(1).truncationMode(.middle)
                                    }
                                    if let target = KeyActionCatalog.appLaunchSpec(for:action) {
                                        Text(target.fileName).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                    }
                                }
                                Button("Edit") { editing = action.storageLabel }
                                    .disabled(action.kind != .key && action.kind != .appLaunch)
                                Button(role:.destructive) {
                                    write(ShortcutActionLibraryStorage.removing(action.storageLabel,from:labels))
                                    if editing == action.storageLabel { editing = nil }
                                } label: { Image(systemName:"trash") }
                                .accessibilityLabel("Delete \(action.pickerText)")
                                .help("Remove from the saved list")
                            }
                            .padding(10)
                            .background(editing == action.storageLabel ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:8))
                        }
                    }
                }.frame(minHeight:120)
            }
            if let original = editing, labels.contains(original), let action = KeyActionCatalog.action(for:original) {
                Divider()
                HStack {
                    Text("Edit Saved Shortcut").font(.callout).fontWeight(.medium)
                    Spacer()
                    Button("Cancel Edit") { editing = nil }
                }
                ShortcutActionBuilder(action:action) { replacement,_ in
                    write(ShortcutActionLibraryStorage.replacing(original,with:replacement,in:labels))
                    editing = nil
                }.id(original)
            }
        }
        .padding(20).frame(minWidth:520,idealWidth:600,minHeight:500,idealHeight:680)
        .onChange(of:storedActions) { _ in
            if let editing, !labels.contains(editing) { self.editing = nil }
        }
    }
}


/// Keep the draft editable; validate on Return or focus loss, not each keystroke.
struct GestureHoldThresholdField:View {
    let value:Double?
    let commit:(Double)->Void
    @State private var draft = ""
    @FocusState private var focused:Bool
    static func committedValue(_ text:String) -> Double? {
        guard let milliseconds = Double(text.trimmingCharacters(in:.whitespacesAndNewlines)), milliseconds.isFinite else { return nil }
        return GestureHoldTiming.validated(milliseconds/1000)
    }
    private func sync() { draft = value.map { String(GestureHoldTiming.milliseconds($0)) } ?? "" }
    private func apply() {
        guard let seconds = Self.committedValue(draft) else { sync(); return }
        draft = String(GestureHoldTiming.milliseconds(seconds))
        if seconds != value { commit(seconds) }
    }
    var body:some View {
        HStack {
            Text("Hold threshold")
            Spacer(minLength:8)
            TextField(value == nil ? "Mixed" : "500",text:$draft)
                .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width:62)
                .focused($focused).onSubmit { apply() }
                .onAppear { sync() }
                .onChange(of:focused) { if !$0 { apply() } }
                .onChange(of:value) { _ in if !focused { sync() } }
                .accessibilityLabel("Hold threshold in milliseconds")
            Text("ms").foregroundStyle(.secondary)
        }
        .help("100–5000 ms in 10 ms increments. Saves on Return or when leaving the field.")
    }
}
