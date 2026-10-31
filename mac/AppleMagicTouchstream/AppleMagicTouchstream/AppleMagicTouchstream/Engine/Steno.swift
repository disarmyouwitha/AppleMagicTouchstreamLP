import CoreGraphics
import Foundation
import OpenMultitouchSupport

/// Gemini PR wire order: six groups of seven data bits, MSB first within each group.
/// Reference: Plover's machine/gemini_pr.py STENO_KEY_CHART.
enum StenoKey:UInt16,CaseIterable,Codable,Sendable {
    case fn, n1, n2, n3, n4, n5, n6
    case s1, s2, tl, kl, pl, wl, hl
    case rl, a, o, star1, star2, res1, res2
    case power, star3, star4, e, u, fr, rr
    case pr, br, lr, gr, tr, sr, dr
    case n7, n8, n9, na, nb, nc, zr
    private static let names = ["FN","N1","N2","N3","N4","N5","N6","S1","S2","TL","KL","PL","WL","HL",
        "RL","A","O","ST1","ST2","RES1","RES2","PWR","ST3","ST4","E","U","FR","RR","PR","BR","LR","GR","TR","SR","DR","N7","N8","N9","NA","NB","NC","ZR"]
    private static let legends = ["Fn","#1","#2","#3","#4","#5","#6","S-","S-","T-","K-","P-","W-","H-",
        "R-","A","O","*","*","res1","res2","pwr","*","*","E","U","-F","-R","-P","-B","-L","-G","-T","-S","-D","#7","#8","#9","#A","#B","#C","-Z"]
    var label:String { "STN_"+Self.names[Int(rawValue)] }
    var legend:String { Self.legends[Int(rawValue)] }
    var bit:UInt64 { UInt64(1) << rawValue }
    var action:KeyAction { KeyAction(label:label,keyCode:rawValue,flags:0,kind:.steno) }
    static func resolve(_ label:String) -> Self? { allCases.first { $0.label == label } }
}

enum GeminiPRPacket {
    static let keyMask:UInt64 = (UInt64(1)<<42)-1
    static func bytes(for mask:UInt64) -> [UInt8] {
        var bytes = [UInt8](repeating:0,count:6)
        bytes[0] = 0x80
        for index in 0..<42 where mask & (UInt64(1)<<index) != 0 {
            bytes[index/7] |= UInt8(0x40 >> (index%7))
        }
        return bytes
    }
    static func recordingLabel(for mask:UInt64) -> String {
        "GeminiPR:"+bytes(for:mask).map { String(format:"%02X",$0) }.joined()
    }
}

struct StenoRegion:Sendable {
    let key:StenoKey
    let geometry:KeyHitGeometry
}

enum StenoPointerMode:String,CaseIterable,Codable,Sendable,Identifiable {
    case disabled, twoFinger, oneFingerForce
    var id:String { rawValue }
    var title:String {
        switch self { case .disabled: return "Off"; case .twoFinger: return "2F Mouse"; case .oneFingerForce: return "1F Mouse + Force Click" }
    }
    var count:Int { self == .twoFinger ? 2 : 1 }
}

struct StenoPointerUpdate:Sendable {
    var millimetres:CGPoint? = nil
    var click = false
    var reset = false
}

/// Shares continuous contact ownership/coherence and force recognition with
/// ordinary gestures, while keeping the pending stroke available until a win.
struct StenoPointerArbiter:Sendable {
    private var movement = GestureSessionEngine<Int>(rules:[
        .init(gesture:1,activationCount:1,minimumMovementMM:2,requiresFullChordMotion:true),
        .init(gesture:2,activationCount:2,minimumMovementMM:2,requiresFullChordMotion:true)])
    private var force = ForceClickRecognizer()
    private var excluded:UInt8 = 0
    mutating func reset() { movement.reset(); force.clear(); excluded = 0 }
    mutating func process<C:Collection>(mode:StenoPointerMode,device:Int,time:Double,touches:C,mayActivate:Bool) -> (claimed:Bool,update:StenoPointerUpdate) where C.Element == OMSRawTouch {
        guard mode != .disabled else { return (false,.init()) }
        let id = UInt64(device), bit = UInt8(1)<<device
        let count = touches.reduce(0) { $0 + (($1.state == .making || $1.state == .touching) ? 1:0) }
        if (count > mode.count || !mayActivate) && movement.owner(device:id) == nil && !force.claimed(device:id) { excluded |= bit }
        let allowed = mode != .disabled && excluded & bit == 0
        let click = force.recognize(device:id,time:time,contacts:touches,enabled:{ _ in allowed && mode == .oneFingerForce && count == 1 }) != nil
        let forceOwned = force.claimed(device:id)
        let motion = movement.process(device:id,time:time,touches:touches,
            enabled:{ $0 == mode.count && allowed },requiresCoherentTranslation:true,
            activationFilter:{ _, context in (context.coherentMovementMM ?? 0) >= 2 })
        if motion.phase == .cancelled { excluded |= bit }
        let moving = motion.phase == .began || motion.phase == .changed
        let claimed = moving || click || forceOwned
        if count == 0 { excluded &= ~bit }
        return (claimed,.init(millimetres:moving ? motion.millimetres:nil,click:click,
            reset:motion.phase == .cancelled || motion.phase == .ended || count == 0))
    }
}

/// Both pads form one stroke. Keys accumulate through rolling contacts; only
/// both-pad all-up emits. Invalid/stale/overflow/reset cancels, never completes.
struct StenoChordEngine:Sendable {
    var pointerMode:StenoPointerMode = .disabled
    private(set) var pointerUpdate:StenoPointerUpdate?
    private var pointer = StenoPointerArbiter()
    private var pointerOwned = false
    private var sawBothHands = false
    private var chord:UInt64 = 0
    private var down:UInt8 = 0
    private var blocked = false
    private var times = SIMD2<Double>(repeating:-1)
    mutating func cancel(blockedPads:UInt8? = nil) {
        chord = 0; pointer.reset(); pointerOwned = false; sawBothHands = false; pointerUpdate = nil
        if let blockedPads { down = blockedPads }
        blocked = down != 0
        times = SIMD2<Double>(repeating:-1)
    }
    mutating func removeDevice(_ index:Int) {
        guard index == 0 || index == 1 else { return }
        down &= ~(UInt8(1)<<index)
        cancel()
    }
    mutating func process<C:Collection>(device:Int,time:Double,touches:C,regions:[StenoRegion],size:CGSize) -> UInt64? where C.Element == OMSRawTouch {
        guard device == 0 || device == 1 else { return nil }
        let pad = UInt8(1)<<device
        pointerUpdate = nil
        var count = 0, keys:UInt64 = 0
        var valid = time.isFinite && time >= 0 && (times[device] < 0 || time > times[device])
        if times[device] >= 0, down & pad != 0, time-times[device] > 0.25 { valid = false }
        for touch in touches where (touch.state == .making || touch.state == .touching) && touch.telemetry?.fingerID != 6 {
            count += 1
            guard count <= 16, touch.posX.isFinite, touch.posY.isFinite,
                  touch.posX >= 0, touch.posX <= 1, touch.posY >= 0, touch.posY <= 1 else { valid = false; continue }
            let point = CGPoint(x:CGFloat(touch.posX)*size.width,y:CGFloat(1-touch.posY)*size.height)
            for region in regions where region.geometry.contains(point) { keys |= region.key.bit }
        }
        if count > 0 { down |= pad } else { down &= ~pad }
        times[device] = time.isFinite ? time : -1
        if !valid { cancel(blockedPads:down); return nil }
        if blocked {
            if down == 0 { blocked = false }
            return nil
        }
        if down == 3 { sawBothHands = true }
        let mouse = pointer.process(mode:pointerMode,device:device,time:time,touches:touches,mayActivate:down == pad && !sawBothHands)
        if mouse.claimed { pointerOwned = true; chord = 0 }
        if pointerOwned {
            pointerUpdate = mouse.update
            if down == 0 { pointer.reset(); pointerOwned = false; sawBothHands = false }
            return nil
        }
        chord |= keys
        guard down == 0 else { return nil }
        let stroke = chord; chord = 0; pointer.reset(); sawBothHands = false
        return stroke == 0 ? nil:stroke
    }
}

/// Stable grid identities for two visualizations of the same wire keys.
enum StenoLayoutDefinition {
    static func labels(preset:TrackpadLayoutPreset,side:TrackpadSide) -> [[String]] {
        let keys:[[StenoKey?]]
        if preset == .stenoVoyager {
            keys = side == .left ? [
                [.n5,.n4,.n3,.n2,.n1,.nc], [.star1,.hl,.pl,.tl,.s1,nil], [.star2,.rl,.wl,.kl,.s2,nil], [.a,.o]
            ] : [
                [.n6,.n7,.n8,.n9,.na,.nb], [.star3,.fr,.pr,.lr,.tr,.dr], [.star4,.rr,.br,.gr,.sr,.zr], [.e,.u]
            ]
        } else {
            keys = side == .left ? [[.n1],[.s1,.tl,.pl,.hl,.star1],[.s2,.kl,.wl,.rl],[.a,.o]]
                : [[.n6],[.star3,.fr,.pr,.lr,.tr,.dr],[.rr,.br,.gr,.sr,.zr],[.e,.u]]
        }
        return keys.map { $0.map { $0?.label ?? "None" } }
    }
    @MainActor static func layout(preset:TrackpadLayoutPreset,side:TrackpadSide,size:CGSize,
                       columns:[ColumnLayoutSettings] = [],spacing:Double = 10,overrides:KeyGeometryOverrides = [:],pointerMode:StenoPointerMode = .disabled) -> ContentViewModel.Layout {
        var rects:[[NormalizedRect]]
        if preset == .stenoVoyager {
            // Reuse the 6×3 stagger and its mirrored, inner-to-outer column identities.
            let main = ContentView.makeKeyLayout(size:size,keyWidth:ContentView.baseKeyWidthMM,keyHeight:ContentView.baseKeyHeightMM,
                columns:6,rows:3,trackpadWidth:ContentView.trackpadWidthMM,trackpadHeight:ContentView.trackpadHeightMM,
                columnAnchorsMM:TrackpadLayoutPreset.sixByThree.columnAnchors,columnSettings:columns,
                keySpacingPercent:spacing,mirrored:side == .left)
            rects = main.normalizedKeyRects
        } else {
            if side == .left {
                rects = [[.init(x:0.06,y:0.1,width:0.66,height:0.05)],
                    (0..<4).map { .init(x:0.06+CGFloat($0)*0.17,y:0.18,width:0.15,height:0.23) }
                        + [.init(x:0.76,y:0.18,width:0.16,height:0.48)],
                    (0..<4).map { .init(x:0.06+CGFloat($0)*0.17,y:0.43,width:0.15,height:0.23) }]
            } else {
                rects = [[.init(x:0.22,y:0.1,width:0.72,height:0.05)],
                    [.init(x:0.04,y:0.18,width:0.15,height:0.48)]
                        + (0..<5).map { .init(x:0.22+CGFloat($0)*0.145,y:0.18,width:0.13,height:0.23) },
                    (0..<5).map { .init(x:0.22+CGFloat($0)*0.145,y:0.43,width:0.13,height:0.23) }]
            }
        }
        rects.append(side == .left ? [.init(x:0.56,y:0.79,width:0.15,height:0.18),.init(x:0.76,y:0.79,width:0.15,height:0.18)]
            : [.init(x:0.06,y:0.79,width:0.15,height:0.18),.init(x:0.26,y:0.79,width:0.15,height:0.18)])
        for row in rects.indices {
            for col in rects[row].indices {
                guard let edit = overrides[GridKeyPosition(side:side,row:row,column:col).storageKey] else { continue }
                let old = rects[row][col], w = min(1,max(0.001,old.width*edit.widthScale)), h = min(1,max(0.001,old.height*edit.heightScale))
                rects[row][col] = .init(x:old.centerX-w/2,y:old.centerY-h/2,width:w,height:h,rotationDegrees:old.rotationDegrees-edit.rotationDegrees)
            }
        }
        return .init(normalizedKeyRects:rects,trackpadSize:size,allowHoldBindings:false,isSteno:true,stenoPointerMode:pointerMode)
    }
}
