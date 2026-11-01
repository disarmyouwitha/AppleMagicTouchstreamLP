import OpenMultitouchSupport

/// Reserve enabled multi-finger candidates or a force press before keyboard release emits taps.
/// Reservation is per pad, includes the all-up frame and survives added/lifted fingers.
/// Invalid/failed candidates stay reserved rather than falling back to typing.
struct GestureKeyboardArbitration {
    private var reserved: Set<UInt64> = []
    mutating func reset() { reserved.removeAll(keepingCapacity: true) }
    mutating func reset(device: UInt64) { reserved.remove(device) }
    mutating func process(device: UInt64, activeCount: Int, forceClick: Bool = false, holdCandidate: Bool = false, enabled: (GestureTrigger) -> Bool) -> Bool {
        if activeCount == 0 { return reserved.remove(device) != nil }
        if reserved.contains(device) { return true }
        if forceClick || holdCandidate { reserved.insert(device); return true }
        let candidate: Bool
        switch activeCount {
        case 1: candidate = false
        case 2: candidate = enabled(.twoFingerRotateLeft) || enabled(.twoFingerRotateRight) || enabled(.twoFingerMove) || enabled(.twoFingerTap) || enabled(.twoFingerPinch) || enabled(.twoFingerSpread)
        case 3: candidate = enabled(.thumbTwoMove) || enabled(.threeFingerMove) || enabled(.threeFingerTap) || enabled(.thumbTwoTap) || enabled(.threeFingerRotateLeft) || enabled(.threeFingerRotateRight) || enabled(.threeFingerPinch) || enabled(.threeFingerSpread)
        case 4: candidate = enabled(.fourFingerRotateLeft) || enabled(.fourFingerRotateRight) || enabled(.fourFingerTap) || enabled(.fourFingerMove) || enabled(.fourFingerPinch) || enabled(.fourFingerSpread)
        case 5: candidate = enabled(.fiveFingerTap) || enabled(.fiveFingerMove) || enabled(.fiveFingerPinch) || enabled(.fiveFingerSpread) || enabled(.fiveFingerRotateLeft) || enabled(.fiveFingerRotateRight)
        default: candidate = false
        }
        if candidate { reserved.insert(device) }
        return candidate
    }
}


struct KeyboardProposalToken:Equatable { let generation:Int; let layer:Int; let epoch:Int }

/// Bounded owned copies: native frame buffers are returned immediately after ingress.
/// Allocated once, never retains native pooled frames or grows on the callback path.
final class PendingKeyboardProposalBuffer {
    enum Mode { case idle, pending, typing, gesture }
    static func resolvesToTyping(activeCount:Int,tapPending:Bool) -> Bool { activeCount == 0 || (activeCount < 2 && !tapPending) }
    struct Header { let sequence:UInt64; let index:Int; let time:Double; let count:Int; let flags:UInt64 }
    static let capacity = 1024, contactsPerFrame = 16
    private let storage = UnsafeMutablePointer<OMSRawTouch>.allocate(capacity:capacity*contactsPerFrame)
    private var headers:[Header] = []
    var mode:Mode = .idle
    var device:UInt64?
    var token:KeyboardProposalToken?
    var gestureEpoch:UInt64 = 0
    private var lastTime:Double?
    init() { headers.reserveCapacity(Self.capacity) }
    deinit { clear(); storage.deallocate() }
    func clear() {
        for i in headers.indices { storage.advanced(by:i*Self.contactsPerFrame).deinitialize(count:headers[i].count) }
        headers.removeAll(keepingCapacity:true); lastTime = nil
    }
    func reset() { clear(); mode = .idle; device = nil; token = nil }
    @discardableResult func append<C:Collection>(sequence:UInt64,index:Int,time:Double,touches:C,flags:UInt64 = 0) -> Bool where C.Element == OMSRawTouch {
        guard headers.count < Self.capacity, touches.count <= Self.contactsPerFrame, time.isFinite,
              lastTime.map({time > $0 && time-$0 < 0.15}) ?? true else { clear(); mode = .gesture; return false }
        var ids = SIMD16<Int32>(repeating:0), n = 0
        for touch in touches {
            guard touch.posX.isFinite, touch.posY.isFinite, touch.pressure.isFinite,
                  touch.telemetry?.fingerID != 6 else { clear(); mode = .gesture; return false }
            for j in 0..<n where ids[j] == touch.id { clear(); mode = .gesture; return false }
            ids[n] = touch.id; n += 1
        }
        let offset = headers.count*Self.contactsPerFrame
        for (i,touch) in touches.enumerated() { storage.advanced(by:offset+i).initialize(to:touch) }
        headers.append(.init(sequence:sequence,index:index,time:time,count:n,flags:flags));lastTime = time
        return true
    }
    func drain(_ consume:(Header,UnsafeBufferPointer<OMSRawTouch>)->Void) {
        for i in headers.indices { consume(headers[i],UnsafeBufferPointer(start:storage.advanced(by:i*Self.contactsPerFrame),count:headers[i].count)) }
        clear()
    }
}
