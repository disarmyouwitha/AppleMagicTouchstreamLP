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

/// Contact-only diagrams using the live anatomical palette, tap rings and directional arrows.
/// Examples are illustrative, not exact-only anatomy rules.
struct GestureChordIcon: View {
    let gesture: GesturePane
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private enum Example: String, Hashable {
        case pinch = "Pinch", expand = "Spread", tap = "Tap", move = "Move", force = "Force"
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
                .frame(width:36,height:47,alignment:.top)
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
                    let color = Color(nsColor:AnatomicalFingerPalette.color(fingerID:Int32(index+1)))
                    cell.fill(marker,with:.color(color))
                    cell.stroke(marker,with:.color(.white),lineWidth:0.018)
                    if tap {
                        let radius = 0.075 + phase*0.045
                        let ring = Path(ellipseIn:CGRect(x:tip.x-radius,y:tip.y-radius,width:radius*2,height:radius*2))
                        cell.stroke(ring,with:.color(color.opacity(0.9-phase*0.5)),lineWidth:0.022)
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
            setSensitivity:{controller.setSensitivity($0,kind:$1,scope:$2)})
    }
}

/// Value-only workspace so layout previews/tests never create input clients or post events.
struct GestureAssignmentWorkspace: View {
    let settings: HandGestureSettings
    let status: (GestureTrigger,GestureHandScope) -> String
    let apply: (GestureAction,GestureTrigger,GestureHandScope) -> Void
    let setSensitivity: (Double,GestureSensitivity,GestureHandScope) -> Void
    @State private var editingHand: GestureHandScope = .left
    @State private var pane: GesturePane
    @State private var selected: GestureTrigger
    @State private var search = ""
    @AppStorage(WorkspaceColumnSizing.menuWidthKey) private var menuColumnWidth = WorkspaceColumnSizing.defaultMenuWidth
    @AppStorage("AppleMagicTouchstream.gestureInspectorWidth") private var inspectorColumnWidth = 286.0

    init(settings:HandGestureSettings, initialPane:GesturePane = .twoFingers,
         status:@escaping (GestureTrigger,GestureHandScope)->String,
         apply:@escaping (GestureAction,GestureTrigger,GestureHandScope)->Void,
         setSensitivity:@escaping (Double,GestureSensitivity,GestureHandScope)->Void) {
        self.settings = settings; self.status = status; self.apply = apply; self.setSensitivity = setSensitivity
        _pane = State(initialValue:initialPane)
        _selected = State(initialValue:initialPane.triggers.first(where:{$0.isContinuous}) ?? initialPane.triggers[0])
    }

    private var action: GestureAction? { settings.action(selected,in:editingHand) }
    private var scopeText: String { "\(editingHand.rawValue) trackpad" }
    private var groups: [String] { Array(NSOrderedSet(array:GesturePane.allCases.map(\.group))) as? [String] ?? [] }
    private func matching(_ item:GesturePane) -> Bool {
        search.isEmpty || "\(item.group) \(item.title) \(item.summary) \(item.triggers.map { settings.action($0,in:editingHand)?.title ?? "" }.joined(separator:" "))"
            .localizedCaseInsensitiveContains(search)
    }
    var body: some View {
        GeometryReader { viewport in
            let menuWidth = WorkspaceColumnSizing.menu(menuColumnWidth,available:viewport.size.width,reserved:260)
            let inspectorMaximum = max(260,min(480,viewport.size.width-menuWidth-WorkspaceColumnSizing.dividerWidth*2-360))
            let inspectorWidth = min(inspectorMaximum,max(260,inspectorColumnWidth))
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
                        lifecycle
                        Text("Choose a card to edit its action. Settings apply only to the \(editingHand.rawValue.lowercased()) trackpad.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    }
                    .padding(24)
                    .frame(maxWidth:.infinity,alignment:.topLeading)
                }
                .frame(maxWidth:.infinity,maxHeight:.infinity)
                WorkspaceColumnDivider(width:Binding(get:{inspectorWidth},set:{inspectorColumnWidth = $0}),
                    minimum:260,maximum:inspectorMaximum,trailingColumn:true,label:"Gesture inspector width")
                inspector.frame(width:inspectorWidth)
            }
        }
        .background(Color(nsColor:.windowBackgroundColor))
        .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
    }

    private var navigation: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Gestures").font(.title3).bold()
            Picker("Edit trackpad",selection:$editingHand) {
                Text("Left").tag(GestureHandScope.left)
                Text("Right").tag(GestureHandScope.right)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth:.infinity)
            .help("Edit one trackpad's independent gesture settings. No coordinated two-hand gestures are configured here.")
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
            Text("\(scopeText) settings\nOnly available gestures are shown.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
        .padding(16)
        .background(Color.primary.opacity(0.025))
    }

    private func navigationItem(_ item:GesturePane) -> some View {
        Button {
            pane = item
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
                GestureChordIcon(gesture:pane).padding(.leading,8)
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
            } else {
                ForEach(pane.triggers.filter { $0.isContinuous }) { assignmentCard($0) }
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12) {
                    ForEach(pane.triggers.filter { !$0.isContinuous }) { assignmentCard($0) }
                }
            }
        }
    }
    private func assignmentCard(_ trigger:GestureTrigger) -> some View {
        let assigned = settings.action(trigger,in:editingHand)
        return Button { selected = trigger } label: {
            VStack(alignment:.leading,spacing:10) {
                HStack {
                    Image(systemName:trigger.assignmentSymbol).foregroundStyle(.secondary)
                    Text(trigger.assignmentTitle).font(.callout).foregroundStyle(.secondary)
                    Spacer(minLength:0)
                }
                Text(assigned?.title ?? "Mixed").font(.system(size:17,weight:.medium)).fixedSize(horizontal:false,vertical:true)
                Text(trigger.behavior(for:assigned)).font(.caption).foregroundStyle(.secondary)
            }
            .padding(18).frame(maxWidth:.infinity,minHeight:112,alignment:.topLeading)
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
                    Text(selected.assignmentTitle).font(.title3).bold()
                    Text("\(pane.group) · \(scopeText)").font(.caption).foregroundStyle(.secondary)
                }
                GestureActionPickerRow(trigger:selected,value:action,
                    leftAction:settings.left.bindings.action(for:selected),
                    rightAction:settings.right.bindings.action(for:selected),
                    status:status(selected,editingHand),showsStatus:true) { value in
                        apply(value,selected,editingHand)
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
                Text("Changes save automatically and are included in keymap exports.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            .padding(20)
        }
        .background(Color.primary.opacity(0.025))
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
        let value = settings.sensitivity(kind,in:editingHand) ?? 1
        return VStack(alignment:.leading,spacing:8) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(String(format:"%.2f×",value)).font(.caption).monospacedDigit()
            }
            Slider(value:Binding(get:{value},set:{setSensitivity(($0 * 100).rounded() / 100,kind,editingHand)}),in:0.25...2)
                .accessibilityLabel(title)
            Text("Shared by all \(kind == .zoom ? "zoom" : kind == .scroll ? "scroll" : "pointer and drag") gestures on the \(editingHand.rawValue.lowercased()) trackpad.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
}


/// Shared menu width keeps the Keyboard settings and Gesture browser aligned.
enum WorkspaceColumnSizing {
    static let menuWidthKey = "AppleMagicTouchstream.assignmentMenuWidth"
    static let defaultMenuWidth = 452.0
    static let minimumMenu = 400.0
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
