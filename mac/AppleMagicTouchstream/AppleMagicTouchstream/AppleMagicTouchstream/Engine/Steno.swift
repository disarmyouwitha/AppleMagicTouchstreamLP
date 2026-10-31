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

enum StenoForceThreshold {
    static let defaultValue:Double = 130
    static func validated(_ value:Double) -> Double { value.isFinite ? min(500,max(1,value)):defaultValue }
}

enum StenoPointerMode:String,CaseIterable,Codable,Sendable {
    case disabled, twoFinger, oneFingerForce
    // Legacy mode identities remain decodable; STENO now has one fixed behavior.
    var count:Int { 2 }
}

enum StenoPointerClick:Sendable {
    case primary, secondary
    var action:GestureAction { self == .primary ? .primaryClick:.secondaryClick }
}

struct StenoPointerUpdate:Sendable {
    var millimetres:CGPoint? = nil
    var click:StenoPointerClick? = nil
    var reset = false
    var dragBegan = false
    var dragging = false
    var scrollBegan = false
    var scrolling = false
    var scrollEnded = false
    var activatesForce:Bool { dragBegan || click != nil || scrollBegan }
}

/// Shares continuous contact ownership/coherence and force recognition with
/// ordinary gestures, while keeping the pending stroke available until a win.
struct StenoPointerArbiter:Sendable {
    private var movement = GestureSessionEngine<Int>(rules:[
        .init(gesture:1,activationCount:1,minimumMovementMM:0),
        .init(gesture:2,activationCount:2,minimumMovementMM:2,requiresFullChordMotion:true)])
    private var force = ForceClickRecognizer()
    private var excluded:UInt8 = 0
    private var forceExcluded:UInt8 = 0
    private var dragOwners:UInt8 = 0
    private var scrollOwners:UInt8 = 0
    private var scrollMotion = GestureContactMotionTracker()
    mutating func reset() { movement.reset(); force.clear(); excluded = 0; forceExcluded = 0; dragOwners = 0; scrollOwners = 0; scrollMotion.reset() }
    mutating func removeDevice(_ device:Int) {
        let id = UInt64(device), bit = UInt8(1)<<device
        movement.cancel(device:id); force.clear(device:id); scrollMotion.reset(device:id)
        excluded &= ~bit; forceExcluded &= ~bit; dragOwners &= ~bit; scrollOwners &= ~bit
    }
    mutating func process<C:Collection>(mode:StenoPointerMode,device:Int,time:Double,touches:C,mayActivate:Bool,forceThreshold:Float = 130) -> (claimed:Bool,update:StenoPointerUpdate) where C.Element == OMSRawTouch {
        guard mode != .disabled else { return (false,.init()) }
        let id = UInt64(device), bit = UInt8(1)<<device
        let count = touches.reduce(0) { $0 + (($1.state == .making || $1.state == .touching) ? 1:0) }
        if (count > mode.count || !mayActivate) && movement.owner(device:id) == nil && !force.claimed(device:id) { excluded |= bit }
        let existingOwner = movement.owner(device:id) != nil || force.claimed(device:id)
        if (count > 4 || !mayActivate) && !existingOwner { forceExcluded |= bit }
        let allowed = excluded & bit == 0
        let forceAllowed = forceExcluded & bit == 0
        let trigger = force.recognize(device:id,time:time,contacts:touches,threshold:forceThreshold,enabled:{ trigger in
            forceAllowed && (1...4).contains(trigger.forceCount ?? 0)
        })
        let dragBegan = trigger?.forceCount == 1
        if dragBegan {
            dragOwners |= bit
            movement.cancel(device:id) // Pre-press travel cannot jump the drag on activation.
        }
        let scrollBegan = trigger?.forceCount == 4
        if scrollBegan {
            scrollOwners |= bit
            movement.cancel(device:id); scrollMotion.reset(device:id)
        }
        var scrollDelta:CGPoint?
        var scrollCancelled = false
        var scrollEnded = false
        let wasScrolling = scrollOwners & bit != 0
        if wasScrolling {
            scrollDelta = scrollMotion.millimetres(device:id,time:time,contacts:touches)
            scrollEnded = count == 0 && scrollMotion.frameEndedNormally
            scrollCancelled = count > 0 && (!scrollBegan && !scrollMotion.frameContinued || touches.contains {
                ($0.state == .making || $0.state == .touching) && (!$0.pressure.isFinite || $0.pressure < 0)
            })
            if count == 0 || scrollCancelled { scrollOwners &= ~bit; scrollMotion.reset(device:id) }
        }
        if count == 0 { dragOwners &= ~bit }
        let dragging = dragOwners & bit != 0
        let scrolling = scrollOwners & bit != 0
        let click:StenoPointerClick? = trigger.flatMap {
            $0.forceCount == 2 ? .primary:($0.forceCount == 3 ? .secondary:nil)
        }
        let forceOwned = force.claimed(device:id)
        let motion = movement.process(device:id,time:time,touches:touches,
            enabled:{ $0 == 1 ? dragging:(allowed && !wasScrolling) },requiresCoherentTranslation:true,
            activationFilter:{ gesture, context in gesture == 1 ? dragging:(context.coherentMovementMM ?? 0) >= 2 })
        if motion.phase == .cancelled { excluded |= bit }
        let moving = motion.phase == .began || motion.phase == .changed
        let claimed = moving || click != nil || forceOwned
        if count == 0 { excluded &= ~bit; forceExcluded &= ~bit }
        return (claimed,.init(millimetres:scrolling ? scrollDelta:(moving ? motion.millimetres:nil),click:click,
            reset:motion.phase == .cancelled || motion.phase == .ended || count == 0 || scrollCancelled,
            dragBegan:dragBegan,dragging:dragging,scrollBegan:scrollBegan,scrolling:scrolling,
            scrollEnded:scrollEnded))
    }
}

/// Both pads form one stroke. Keys accumulate through rolling contacts; only
/// both-pad all-up emits. Invalid/stale/overflow/reset cancels, never completes.
struct StenoChordEngine:Sendable {
    var pointerMode:StenoPointerMode = .disabled
    var forceThreshold:Float = 130
    private(set) var pointerUpdate:StenoPointerUpdate?
    private(set) var hapticTouchPads:UInt8 = 0, hapticReleasePads:UInt8 = 0
    private var heldKeys = SIMD2<UInt64>(repeating:0)
    private var strokeKeys = SIMD2<UInt64>(repeating:0)
    private(set) var completedKeys = SIMD2<UInt64>(repeating:0)
    private var strokePads:UInt8 = 0
    private var pendingTouchPads:UInt8 = 0
    private var touchDue = SIMD2<Double>(repeating:0)
    private(set) var hapticCancellationRevision:UInt64 = 0
    static let touchFeedbackSettleWindow = 0.08
    private var pointer = StenoPointerArbiter()
    private var pointerOwned = false
    var hasPointerOwner:Bool { pointerOwned }
    private var sawBothHands = false
    private var cancelledPointerPads:UInt8 = 0
    private var chord:UInt64 = 0
    private var down:UInt8 = 0
    private var blocked = false
    private var times = SIMD2<Double>(repeating:-1)
    mutating func cancel(blockedPads:UInt8? = nil) {
        hapticCancellationRevision &+= 1; pendingTouchPads = 0
        hapticTouchPads = 0; hapticReleasePads = 0; heldKeys = SIMD2(repeating:0); strokePads = 0
        pointerUpdate = pointerOwned ? .init(reset:true):nil
        strokeKeys = SIMD2(repeating:0); completedKeys = SIMD2(repeating:0)
        chord = 0; pointer.reset(); pointerOwned = false; sawBothHands = false; cancelledPointerPads = 0
        if let blockedPads { down = blockedPads }
        blocked = down != 0
        times = SIMD2<Double>(repeating:-1)
    }
    mutating func removeDevice(_ index:Int) {
        guard index == 0 || index == 1 else { return }
        pendingTouchPads &= ~(UInt8(1)<<index); hapticCancellationRevision &+= 1
        heldKeys[index] = 0; strokePads &= ~(UInt8(1)<<index)
        hapticTouchPads = 0; hapticReleasePads = 0
        down &= ~(UInt8(1)<<index)
        cancelledPointerPads &= ~(UInt8(1)<<index)
        if pointerOwned {
            pointer.removeDevice(index); times[index] = -1; chord = 0
            pointerOwned = down != 0; pointerUpdate = .init(reset:true)
        } else { cancel() }
    }
    mutating func process<C:Collection>(device:Int,time:Double,touches:C,regions:[StenoRegion],size:CGSize) -> UInt64? where C.Element == OMSRawTouch {
        guard device == 0 || device == 1 else { return nil }
        let pad = UInt8(1)<<device
        completedKeys = SIMD2(repeating:0)
        pointerUpdate = nil; hapticTouchPads = 0; hapticReleasePads = 0
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
        if !valid {
            if pointerOwned {
                pendingTouchPads = 0; hapticCancellationRevision &+= 1
                pointer.removeDevice(device); cancelledPointerPads |= pad
                pointerUpdate = .init(reset:true)
                if down == 0 { cancel(blockedPads:0); pointerUpdate = .init(reset:true) }
            } else { cancel(blockedPads:down) }
            return nil
        }
        if cancelledPointerPads & pad != 0 {
            if count == 0 { cancelledPointerPads &= ~pad }
            pointerUpdate = .init(reset:true)
            if down == 0 { cancel(blockedPads:0); pointerUpdate = .init(reset:true) }
            return nil
        }
        if blocked {
            if down == 0 { blocked = false }
            return nil
        }
        let newKeys = keys & ~heldKeys[device]
        heldKeys[device] = keys
        if down == 3 { sawBothHands = true }
        let mouse = pointer.process(mode:pointerMode,device:device,time:time,touches:touches,mayActivate:pointerOwned || (down == pad && !sawBothHands),forceThreshold:forceThreshold)
        if mouse.claimed {
            if !pointerOwned { pendingTouchPads = 0; hapticCancellationRevision &+= 1 }
            pointerOwned = true; chord = 0; strokeKeys = SIMD2(repeating:0)
        }
        if pointerOwned {
            pointerUpdate = mouse.update
            if down == 0 { pointer.reset(); pointerOwned = false; sawBothHands = false }
            return nil
        }
        if newKeys != 0, pendingTouchPads & pad == 0 {
            pendingTouchPads |= pad; touchDue[device] = time+Self.touchFeedbackSettleWindow
        }
        if pendingTouchPads & pad != 0, time >= touchDue[device] {
            hapticTouchPads = pad; pendingTouchPads &= ~pad
        }
        if keys != 0 { strokePads |= pad }
        chord |= keys; strokeKeys[device] |= keys
        guard down == 0 else { return nil }
        completedKeys = strokeKeys; strokeKeys = SIMD2(repeating:0)
        let stroke = chord; chord = 0; pointer.reset(); sawBothHands = false
        if stroke != 0 {
            hapticTouchPads |= pendingTouchPads; hapticReleasePads = strokePads
        }
        pendingTouchPads = 0; strokePads = 0
        return stroke == 0 ? nil:stroke
    }
}

/// Stable grid identities for split and single-pad visualizations of the same wire keys.
enum StenoLayoutDefinition {
    static func labels(preset:TrackpadLayoutPreset,side:TrackpadSide) -> [[String]] {
        if preset == .stenoSingle {
            guard side == .right else { return [] }
            return [[StenoKey.n1,.n6],[.s1,.tl,.pl,.hl,.star1,.fr,.pr,.lr,.tr,.dr],
                [.s2,.kl,.wl,.rl,.rr,.br,.gr,.sr,.zr],[.a,.o,.e,.u]].map { $0.map(\.label) }
        }
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
    // Key bounds from the maker's published Asterisk layout drawing:
    // https://docs.stenokeyboards.com/images/keyboard-layouts/asterisk.svg
    // Its 626-unit board width is calibrated to the published 234 mm board.
    // Keep the drawing's column widths, rather than stretching each half to fill
    // its pad. Row heights below use the user's 25 mm hardware measurement.
    @MainActor private static func asteriskRects(side:TrackpadSide) -> [[NormalizedRect]] {
        let scale:CGFloat = 234/626
        let left = side == .left
        var bounds:[[CGRect]] = left ? [
            [CGRect(x:9.13078,y:3.9384,width:177.665,height:10.3977)],
            [CGRect(x:9.06885,y:25.1304,width:32.78585,height:61.5942),
             CGRect(x:57.4512,y:25.1304,width:32.7859,height:61.5942),
             CGRect(x:104.634,y:25.1304,width:32.786,height:61.5942),
             CGRect(x:153.1,y:25.1304,width:32.786,height:61.5942),
             CGRect(x:191.316,y:25.6381,width:39.662,height:126.5809)],
            [9.13078,57.0502,104.97,152.89].map { CGRect(x:$0,y:97.0658,width:33.4535,height:55.1532) },
            [151.534,194.933].map { CGRect(x:$0,y:181.603,width:32.549,height:56.961) }
        ] : [
            [CGRect(x:392.941,y:3.71233,width:176.761,height:9.94561)],
            [CGRect(x:347.734,y:25.6381,width:39.662,height:126.5809)] +
                [392.901,441.283,488.466,536.933].map { CGRect(x:$0,y:25.1304,width:32.786,height:61.5942) } +
                [CGRect(x:577.839,y:23.83,width:40.6866,height:62.3861)],
            [392.489,440.409,488.329,536.248].map { CGRect(x:$0,y:97.0658,width:33.4535,height:55.1532) } +
                [CGRect(x:577.839,y:97.0658,width:40.6866,height:55.1532)],
            [351.35,394.749].map { CGRect(x:$0,y:181.603,width:32.549,height:56.961) }
        ]
        // Each physical consonant row is 25 mm. Draw the rows edge-to-edge;
        // the independent 1.5 mm hit allowance already overlaps the seam so a
        // stationary fingertip can press both without overlapping drawn keys.
        let upperEdge = bounds[1][left ? 0:1].minY
        let rowHeight = CGFloat(25)/scale
        for column in bounds[1].indices {
            bounds[1][column].origin.y = upperEdge
            bounds[1][column].size.height = rowHeight*(column == (left ? 4:0) ? 2:1)
        }
        for column in bounds[2].indices {
            bounds[2][column].origin.y = upperEdge+rowHeight
            bounds[2][column].size.height = rowHeight
        }
        bounds[0][0].size.height = upperEdge-bounds[0][0].minY
        let minX:CGFloat = left ? 9.06885:347.734
        let maxX:CGFloat = left ? 230.978:618.5256
        let offsetX = (ContentView.trackpadWidthMM-(maxX-minX)*scale)/2
        let offsetY = (ContentView.trackpadHeightMM-90)/2
        return bounds.map { $0.map { r in
            .init(x:(offsetX+(r.minX-minX)*scale)/ContentView.trackpadWidthMM,
                  y:(offsetY+r.minY*scale)/ContentView.trackpadHeightMM,
                  width:r.width*scale/ContentView.trackpadWidthMM,
                  height:r.height*scale/ContentView.trackpadHeightMM)
        } }
    }
    @MainActor static func layout(preset:TrackpadLayoutPreset,side:TrackpadSide,size:CGSize,
                       columns:[ColumnLayoutSettings] = [],spacing:Double = 10,overrides:KeyGeometryOverrides = [:],pointerMode:StenoPointerMode = .disabled,forceThreshold:Double = 130,connectionMode:StenoConnectionMode = .plugin,hapticTouch:Bool = false,hapticRelease:Bool = false) -> ContentViewModel.Layout {
        var rects:[[NormalizedRect]]
        if preset == .stenoSingle {
            rects = []
            if side == .right {
                // Preserve letter sizes; move each bank 3.2 mm outward and give
                // the central star the freed space. Outer margins are 0.8 mm.
                let gap:CGFloat = 0.01, width:CGFloat = (0.95-9*gap)/10.5
                let margin:CGFloat = 0.005
                let starWidth = 1.5*width+2*(0.025-margin)
                var x:CGFloat = margin
                let rowHeight = CGFloat(25)/ContentView.trackpadHeightMM
                var upper:[NormalizedRect] = []
                for column in 0..<10 {
                    let w = column == 4 ? starWidth:width
                    upper.append(.init(x:x,y:0.18,width:w,height:column == 4 ? 2*rowHeight:rowHeight))
                    x += w+gap
                }
                let lower = upper.enumerated().filter { $0.offset != 4 }.map {
                    NormalizedRect(x:$0.element.x,y:0.18+rowHeight,width:$0.element.width,height:rowHeight)
                }
                let vowelsWidth = 4*width+3*gap, vowelsX = (1-vowelsWidth)/2
                rects = [[.init(x:upper[0].x,y:0.1,width:upper[3].x+width-upper[0].x,height:0.08),
                    .init(x:upper[5].x,y:0.1,width:upper[9].x+width-upper[5].x,height:0.08)],upper,lower,
                    (0..<4).map { .init(x:vowelsX+CGFloat($0)*(width+gap),y:0.79,width:width,height:0.18) }]
            }
        } else if preset == .stenoVoyager {
            // Reuse the 6×3 stagger and its mirrored, inner-to-outer column identities.
            let main = ContentView.makeKeyLayout(size:size,keyWidth:ContentView.baseKeyWidthMM,keyHeight:ContentView.baseKeyHeightMM,
                columns:6,rows:3,trackpadWidth:ContentView.trackpadWidthMM,trackpadHeight:ContentView.trackpadHeightMM,
                columnAnchorsMM:TrackpadLayoutPreset.sixByThree.columnAnchors,columnSettings:columns,
                keySpacingPercent:spacing,mirrored:side == .left)
            rects = main.normalizedKeyRects
        } else {
            rects = asteriskRects(side:side)
        }
        if preset == .stenoVoyager {
            rects.append(side == .left ? [.init(x:0.56,y:0.79,width:0.15,height:0.18),.init(x:0.76,y:0.79,width:0.15,height:0.18)]
                : [.init(x:0.06,y:0.79,width:0.15,height:0.18),.init(x:0.26,y:0.79,width:0.15,height:0.18)])
        }
        // Widen each A/O and E/U pair toward its shared midpoint. The existing
        // 1.5 mm hit allowance then supplies the same 3 mm overlap as the rows.
        if preset != .stenoVoyager, rects.count > 3 {
            for leftColumn in stride(from:0,to:rects[3].count-1,by:2) {
                let left = rects[3][leftColumn], right = rects[3][leftColumn+1]
                let seam = (left.x+left.width+right.x)/2
                rects[3][leftColumn].width = seam-left.x
                rects[3][leftColumn+1].x = seam
                rects[3][leftColumn+1].width = right.x+right.width-seam
            }
        }
        if preset == .stenoSingle, rects.count > 3 {
            // Move all four thumbs together: center A and U beneath the two R
            // columns as closely as possible while preserving every pair/gap.
            let targetCenter = (rects[2][3].centerX+rects[2][4].centerX)/2
            let thumbCenter = (rects[3][0].centerX+rects[3][3].centerX)/2
            let shift = targetCenter-thumbCenter
            let thumbTop = asteriskRects(side:.right)[3][0].y
            for column in rects[3].indices {
                rects[3][column].x += shift
                rects[3][column].y = thumbTop
            }
        }
        // Extend the bottom vowel/thumb bars down to a 0.8 mm pad-edge margin.
        // Preserve their top edges, widths and stable key identities.
        if preset != .stenoVoyager, rects.count > 3 {
            let bottom = 1-0.8/ContentView.trackpadHeightMM
            for column in rects[3].indices {
                rects[3][column].height = bottom-rects[3][column].y
            }
        }
        for row in rects.indices {
            for col in rects[row].indices {
                guard let edit = overrides[GridKeyPosition(side:side,row:row,column:col).storageKey] else { continue }
                let old = rects[row][col], w = min(1,max(0.001,old.width*edit.widthScale)), h = min(1,max(0.001,old.height*edit.heightScale))
                rects[row][col] = .init(x:old.centerX-w/2,y:old.centerY-h/2,width:w,height:h,rotationDegrees:old.rotationDegrees-edit.rotationDegrees)
            }
        }
        return .init(normalizedKeyRects:rects,trackpadSize:size,allowHoldBindings:false,isSteno:true,stenoPointerMode:pointerMode,stenoForceThreshold:Float(StenoForceThreshold.validated(forceThreshold)),stenoConnectionMode:connectionMode,stenoHapticTouch:hapticTouch,stenoHapticRelease:hapticRelease)
    }
}
