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

struct GestureSidebar<Options: View>: View {
    @Binding var hand: GestureHandScope
    @ViewBuilder let options: (GesturePane) -> Options
    @State private var expanded: Set<GesturePane> = [.twoFingers]

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
                .frame(width:190)
                .help("Edit left, right, or both trackpad gesture settings.")
            }
            .padding(.horizontal,12).padding(.top,16)
            ScrollView(.vertical) {
                VStack(alignment:.leading,spacing:20) {
                    ForEach(GesturePane.allCases) { gesture in
                        VStack(alignment:.leading,spacing:10) {
                            if !gesture.isPinchSection { Text(gesture.group).font(.headline) }
                            DisclosureGroup(isExpanded:Binding(
                                get:{expanded.contains(gesture)},
                                set:{if $0 { expanded.insert(gesture) } else { expanded.remove(gesture) }})) {
                                options(gesture).padding(.top,8)
                            } label: {
                                gestureSubheader(gesture)
                                    .frame(maxWidth:.infinity,alignment:.leading)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if expanded.contains(gesture) { expanded.remove(gesture) }
                                        else { expanded.insert(gesture) }
                                    }
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityValue(expanded.contains(gesture) ? "Expanded" : "Collapsed")
                            }
                            .tint(.secondary)
                        }
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

    private func gestureSubheader(_ gesture: GesturePane) -> some View {
        HStack(spacing:8) {
            Text(gesture.title).font(.system(size:14,weight:.medium))
            Spacer(minLength:8)
            GestureChordIcon(gesture:gesture).fixedSize()
        }
    }
}

/// Contact-only diagrams: red motion dots, blue tap rings and directional arrows.
/// Examples are illustrative, not exact-only anatomy rules.
struct GestureChordIcon: View {
    let gesture: GesturePane
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private enum Example: String, Hashable {
        case pinch = "Pinch", expand = "Expand", tap = "Tap", move = "Move", force = "Force"
    }
    private var examples: [Example] {
        if gesture.isPinchSection { return [.pinch,.expand] }
        switch gesture {
        case .twoFingers,.threeFingers: return [.tap,.move]
        case .fourFingers: return [.move,.force]
        case .thumbTwo: return [.tap]
        default: return [.force]
        }
    }
    var body: some View {
        HStack(spacing:6) {
            ForEach(examples,id:\.self) { example in
                VStack(spacing:1) {
                    TimelineView(.animation(minimumInterval:1.0/12,paused:reduceMotion || scenePhase == .background)) { timeline in
                        let phase = reduceMotion || scenePhase == .background ? 0.5
                            : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy:1.2)/1.2
                        drawing(example,phase:phase).frame(width:43,height:33)
                    }
                    Text(example.rawValue).font(.system(size:9,weight:.medium)).foregroundStyle(.secondary)
                }
                .frame(width:36,height:47)
            }
        }
        .accessibilityHidden(true)
    }

    private func drawing(_ example: Example, phase: Double) -> some View {
        Canvas { context, size in
                let active = gesture.activeFingers
                let tap = example == .tap || example == .force
                var cell = context
                // Preserve the contact spacing and margin around motion arrows.
                let diagramSize = size.height
                cell.translateBy(x:(size.width-diagramSize)/2+diagramSize*0.06,y:diagramSize*0.12)
                cell.scaleBy(x:diagramSize*0.88,y:diagramSize*0.88)
                // Thumb, index, middle, ring, pinky in anatomical order.
                let tips = [CGPoint(x:0.125,y:0.51),CGPoint(x:0.31,y:0.22),CGPoint(x:0.47,y:0.125),CGPoint(x:0.64,y:0.17),CGPoint(x:0.82,y:0.32)]
                for index in tips.indices where active.contains(index) {
                    let tip = tips[index]
                    let marker = Path(ellipseIn:CGRect(x:tip.x-0.057,y:tip.y-0.057,width:0.114,height:0.114))
                    cell.fill(marker,with:.color(tap ? .blue : .red))
                    cell.stroke(marker,with:.color(.white),lineWidth:0.018)
                    if tap {
                        let radius = 0.075 + phase*0.045
                        let ring = Path(ellipseIn:CGRect(x:tip.x-radius,y:tip.y-radius,width:radius*2,height:radius*2))
                        cell.stroke(ring,with:.color(.blue.opacity(0.9-phase*0.5)),lineWidth:0.022)
                    }
                }
                if example == .pinch || example == .expand {
                    // Diagonal motion follows the gap between thumb and index.
                    let inward = example == .pinch
                    let shift = (phase-0.5)*0.04*(inward ? 1 : -1)
                    let center = CGPoint(x:0.155,y:0.282)
                    let axis = CGPoint(x:0.53,y:-0.85)
                    func point(_ distance: Double) -> CGPoint {
                        CGPoint(x:center.x+axis.x*distance,y:center.y+axis.y*distance)
                    }
                    for side in [-1.0,1.0] {
                        let outer = point(side*(0.30-shift))
                        let inner = point(side*(0.07-shift))
                        arrow(&cell,from:inward ? outer : inner,to:inward ? inner : outer)
                    }
                } else if example == .move {
                    let reach = 0.16 + 0.012*sin(phase*2*Double.pi)
                    let center = CGPoint(x:0.155-5/(diagramSize*0.88),y:0.282)
                    arrow(&cell,from:CGPoint(x:center.x-reach,y:center.y),
                          to:CGPoint(x:center.x+reach,y:center.y),bothEnds:true)
                    arrow(&cell,from:CGPoint(x:center.x,y:center.y-reach),
                          to:CGPoint(x:center.x,y:center.y+reach),bothEnds:true)
                }
        }
    }

    private func arrow(_ context: inout GraphicsContext, from start: CGPoint, to end: CGPoint, bothEnds: Bool = false) {
        var path = Path()
        path.move(to:start); path.addLine(to:end)
        func head(_ tip: CGPoint, awayFrom other: CGPoint) {
            let angle = atan2(tip.y-other.y,tip.x-other.x)
            for side in [-1.0,1.0] {
                path.move(to:tip)
                path.addLine(to:CGPoint(x:tip.x-0.085*cos(angle+side*0.55),y:tip.y-0.085*sin(angle+side*0.55)))
            }
        }
        head(end,awayFrom:start)
        if bothEnds { head(start,awayFrom:end) }
        context.stroke(path,with:.color(.white.opacity(0.85)),style:StrokeStyle(lineWidth:0.055,lineCap:.round,lineJoin:.round))
        context.stroke(path,with:.color(.primary.opacity(0.85)),style:StrokeStyle(lineWidth:0.025,lineCap:.round,lineJoin:.round))
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

struct GestureInspectorPanel: View {
    @ObservedObject var controller: TrackpadGestureController
    @ObservedObject var takeover: NativeTrackpadTakeover
    @State private var editingHand: GestureHandScope = .both
    var body: some View {
        GestureSidebar(hand: $editingHand) { gesture in gestureDetails(gesture) }
    }
    private func gestureDetails(_ gesture: GesturePane) -> some View {
        VStack(alignment:.leading,spacing:12) {
            Text(gesture.summary)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal:false,vertical:true)
            Divider()
            gestureSettings(gesture)
            Text(editingHand == .both ? "Changes apply to both trackpads." : "Editing the \(editingHand.rawValue.lowercased()) trackpad settings.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth:.infinity,alignment:.leading)
        .background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:12))
    }

    @ViewBuilder private func gestureSettings(_ gesture: GesturePane) -> some View {
        ForEach(gesture.triggers) { trigger in
            gestureActionMenu(trigger)
            let actions = actions(for:trigger)
            if actions.contains(where:{ $0.requiresPointerProfile }) {
                sensitivityControl("Pointer sensitivity",kind:.pointer)
            }
            if actions.contains(.scroll) {
                sensitivityControl("Scroll sensitivity",kind:.scroll)
            }
        }
        if gesture.triggers.contains(where:{actions(for:$0).contains(.zoom)}) {
            sensitivityControl("Zoom sensitivity",kind:.zoom)
        }
    }

    private func actions(for trigger: GestureTrigger) -> [GestureAction] {
        let settings = controller.settings
        switch editingHand {
        case .left: return [settings.left.bindings.action(for:trigger)]
        case .right: return [settings.right.bindings.action(for:trigger)]
        case .both: return [settings.left.bindings.action(for:trigger),settings.right.bindings.action(for:trigger)]
        }
    }

    private func gestureActionMenu(_ trigger: GestureTrigger) -> some View {
        let settings = controller.settings
        let value = settings.action(trigger,in:editingHand)
        let status = controller.status(trigger,scope:editingHand)
        return GestureActionPickerRow(trigger:trigger,value:value,
            leftAction:settings.left.bindings.action(for:trigger),rightAction:settings.right.bindings.action(for:trigger),
            status:status,showsStatus:takeover.enabled) { action in
                controller.setAction(action,for:trigger,scope:editingHand)
            }
    }

    private func sensitivityControl(_ title: String, kind: GestureSensitivity) -> some View {
        let settings = controller.settings
        let value = settings.sensitivity(kind,in:editingHand)
        return VStack(alignment:.leading,spacing:6) {
            HStack {
                Text(title).font(.caption)
                Spacer(minLength:4)
                if let value {
                    Text(String(format:"%.2f×",value)).font(.caption).monospacedDigit()
                } else {
                    Text(String(format:"Mixed · L %.2f× / R %.2f×",settings.left[kind],settings.right[kind]))
                        .font(.caption).monospacedDigit()
                }
            }
            Slider(value:Binding(get:{value ?? settings.left[kind]},set:{
                controller.setSensitivity($0,kind:kind,scope:editingHand)
            }),in:0.25...2,step:0.01)
        }
    }

}
