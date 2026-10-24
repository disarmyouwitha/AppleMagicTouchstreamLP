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
        case .twoFingers: return [1,2]; case .twoFingerPinch: return [0,1]
        case .threeFingers: return [1,2,3]; case .threeFingerPinch: return [0,1,2]
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
            GestureChordIcon(gesture:gesture,hand:hand == .both ? .left : hand,selected:false)
                .frame(width:40,height:26)
            Text(gesture.title).font(.system(size:14,weight:.medium))
            if hand == .both {
                GestureChordIcon(gesture:gesture,hand:.right,selected:false)
                    .frame(width:40,height:26)
            }
        }
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
                let points: [CGPoint] = gesture == .thumbTwo
                    ? [CGPoint(x:0.1,y:0.85),CGPoint(x:0.34,y:0.33),CGPoint(x:0.55,y:0.2),CGPoint(x:0.76,y:0.28),CGPoint(x:0.94,y:0.5)]
                    : [CGPoint(x:0.12,y:0.8),CGPoint(x:0.3,y:0.36),CGPoint(x:0.5,y:0.2),CGPoint(x:0.7,y:0.3),CGPoint(x:0.88,y:0.49)]
                let radius = min(cellWidth/10,size.height/9)
                for index in points.indices {
                    let point = points[index]
                    let x = CGFloat(handIndex)*cellWidth + (mirrored ? 1-point.x : point.x)*cellWidth
                    let y = point.y*size.height
                    let shape = Path(ellipseIn:CGRect(x:x-radius,y:y-radius,width:radius*2,height:radius*2))
                    if active.contains(index) {
                        let color = Color(nsColor:AnatomicalFingerPalette.color(fingerID:Int32(index+1)))
                        context.fill(shape,with:.color(color))
                        context.stroke(shape,with:.color(selected ? .white.opacity(0.95) : .white.opacity(0.65)),lineWidth:1)
                    } else {
                        context.stroke(shape,with:.color(Color(nsColor:AnatomicalFingerPalette.color(fingerID:Int32(index+1))).opacity(selected ? 0.9 : 0.5)),lineWidth:1)
                    }
                }
            }
        }
        .accessibilityHidden(true)
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
