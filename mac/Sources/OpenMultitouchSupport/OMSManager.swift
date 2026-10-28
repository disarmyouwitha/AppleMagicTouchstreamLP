/*
 OMSManager.swift

 Created by Takuto Nakamura on 2024/03/02.
*/

@preconcurrency import OpenMultitouchSupportXCF
import Foundation
import os

public struct OMSDeviceInfo: Sendable, Hashable {
    public let deviceName: String
    public let deviceID: String
    public let deviceIDNumeric: UInt64
    public let isBuiltIn: Bool
    internal nonisolated(unsafe) let deviceInfo: OpenMTDeviceInfo
    
    internal init(_ deviceInfo: OpenMTDeviceInfo) {
        self.deviceInfo = deviceInfo
        self.deviceName = deviceInfo.deviceName
        self.deviceID = deviceInfo.deviceID
        self.deviceIDNumeric = UInt64(deviceInfo.deviceID) ?? 0
        self.isBuiltIn = deviceInfo.isBuiltIn
    }
}

public enum OMSHapticIntensity: Int32, CaseIterable, Sendable {
    case weak = 3
    case medium = 4
    case strong = 6
}

public enum OMSHapticPattern: Int32, CaseIterable, Sendable {
    case generic = 15
    case alignment = 16
    case level = 5  // Changed from 17 to 5 (valid ID)
}

public struct OMSRawTouchBufferView: RandomAccessCollection, @unchecked Sendable {
    public typealias Element = OMSRawTouch
    public typealias Index = Int

    public static let empty = OMSRawTouchBufferView(baseAddress: nil, count: 0)

    fileprivate let baseAddress: UnsafePointer<OMSRawTouch>?
    public let count: Int

    public var startIndex: Int { 0 }
    public var endIndex: Int { count }

    public subscript(position: Int) -> OMSRawTouch {
        precondition(position >= 0 && position < count)
        guard let baseAddress else {
            preconditionFailure("touch buffer released")
        }
        return baseAddress[position]
    }
}

public protocol OMSRawTouchFrameSink: AnyObject, Sendable {
    func handleRawTouchFrame(_ frame: OMSRawTouchFrame)
}

public final class OMSManager: Sendable {
    public static let shared = OMSManager()

    public typealias RawTouchFrameHandler = @Sendable (OMSRawTouchFrame) -> Void

    private struct WeakRawTouchFrameSink {
        weak var value: (any OMSRawTouchFrameSink)?
    }

    private struct RawDeliveryState: Sendable {
        static let capacity = 256

        var slots: [OMSRawTouchFrame?] = Array(repeating: nil, count: capacity)
        var readIndex = 0
        var writeIndex = 0
        var count = 0
        var drainScheduled = false
    }

    private let protectedCaptureManager: OSAllocatedUnfairLock<OpenMTManagerV2?>
    private let protectedHapticManager: OSAllocatedUnfairLock<OpenMTManager?>
    private let protectedRawListener = OSAllocatedUnfairLock<OpenMTListener?>(uncheckedState: nil)
    private let protectedTimestampEnabled = OSAllocatedUnfairLock<Bool>(uncheckedState: true)
    private let protectedDeviceIndexStore = OSAllocatedUnfairLock<DeviceIndexStore>(
        uncheckedState: DeviceIndexStore()
    )
    private let deviceIDStringCache = OSAllocatedUnfairLock<[UInt64: String]>(
        uncheckedState: [:]
    )
    private let rawFrameSink = OSAllocatedUnfairLock<WeakRawTouchFrameSink>(
        uncheckedState: WeakRawTouchFrameSink(value: nil)
    )
    private struct RawContinuationStore: Sendable {
        var byID: [UUID: AsyncStream<OMSRawTouchFrame>.Continuation] = [:]
        var list: [AsyncStream<OMSRawTouchFrame>.Continuation] = []
    }
    private let rawContinuationStore = OSAllocatedUnfairLock<RawContinuationStore>(
        uncheckedState: RawContinuationStore()
    )
    private let rawFrameHandler = OSAllocatedUnfairLock<RawTouchFrameHandler?>(
        uncheckedState: nil
    )
    private let rawDeliveryQueue = DispatchQueue(
        label: "ink.ranna.glasstokey.oms.raw-delivery",
        qos: .userInteractive
    )
    private let rawDeliveryLock = OSAllocatedUnfairLock<RawDeliveryState>(
        uncheckedState: RawDeliveryState()
    )
    private let rawBufferPool = OSAllocatedUnfairLock<[RawTouchBuffer]>(uncheckedState: [])
#if DEBUG
    private let signposter = OSSignposter(
        subsystem: "ink.ranna.GlassToKey",
        category: "OpenMT"
    )
#endif

    public var rawTouchStream: AsyncStream<OMSRawTouchFrame> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let id = UUID()
            rawContinuationStore.withLockUnchecked { store in
                store.byID[id] = continuation
                store.list = Array(store.byID.values)
            }
            continuation.onTermination = { [rawContinuationStore] _ in
                rawContinuationStore.withLockUnchecked { store in
                    store.byID.removeValue(forKey: id)
                    store.list = Array(store.byID.values)
                }
            }
        }
    }

    public var isListening: Bool {
        protectedRawListener.withLockUnchecked { $0 != nil }
    }

    public func setRawFrameHandler(_ handler: RawTouchFrameHandler?) {
        rawFrameHandler.withLockUnchecked { $0 = handler }
    }

    public func setRawFrameSink(_ sink: (any OMSRawTouchFrameSink)?) {
        rawFrameSink.withLockUnchecked { state in
            state.value = sink
        }
    }

    public var isTimestampEnabled: Bool {
        get { protectedTimestampEnabled.withLockUnchecked(\.self) }
        set { protectedTimestampEnabled.withLockUnchecked { $0 = newValue } }
    }
    
    public var availableDevices: [OMSDeviceInfo] {
        guard let manager = protectedCaptureManager.withLockUnchecked(\.self) else { return [] }
        manager.refreshAvailableDevices()
        return manager.availableDevices().map { OMSDeviceInfo($0) }
    }
    
    public var activeDevices: [OMSDeviceInfo] {
        guard let manager = protectedCaptureManager.withLockUnchecked(\.self) else { return [] }
        return manager.activeDevices().map { OMSDeviceInfo($0) }
    }

    private init() {
        let hapticManager = OpenMTManager.shared()
        protectedHapticManager = .init(uncheckedState: hapticManager)
        protectedCaptureManager = .init(uncheckedState: Self.loadManagerV2())
    }

    private static func loadManagerV2() -> OpenMTManagerV2? {
        guard OpenMTManagerV2.systemSupportsMultitouch() else {
            return nil
        }
        return OpenMTManagerV2.sharedManager()
    }

    @discardableResult
    public func startListening() -> Bool {
        guard let captureManager = protectedCaptureManager.withLockUnchecked(\.self),
              protectedRawListener.withLockUnchecked({ $0 == nil }) else {
            return false
        }
        let listener = captureManager.addRawListener(callback: { [weak self] touches, count, timestamp, frame, deviceID in
            self?.handleRawFrame(
                touches: touches,
                count: Int(count),
                timestamp: timestamp,
                frame: Int(frame),
                deviceID: deviceID
            )
        })
        protectedRawListener.withLockUnchecked { $0 = listener }
        return true
    }

    @discardableResult
    public func stopListening() -> Bool {
        guard let captureManager = protectedCaptureManager.withLockUnchecked(\.self),
              let listener = protectedRawListener.withLockUnchecked(\.self) else {
            return false
        }
        captureManager.removeRawListener(listener)
        protectedRawListener.withLockUnchecked { $0 = nil }
        return true
    }
    
    @discardableResult
    public func setActiveDevices(_ devices: [OMSDeviceInfo]) -> Bool {
        guard let captureManager = protectedCaptureManager.withLockUnchecked(\.self) else { return false }
        let deviceInfos = devices.map { $0.deviceInfo }
        guard captureManager.setActiveDevices(deviceInfos) else {
            return false
        }
        _ = protectedHapticManager.withLockUnchecked { manager in
            manager?.setActiveDevices(deviceInfos) ?? false
        }
        return true
    }
    
    public var isHapticEnabled: Bool {
        guard let xcfManager = protectedHapticManager.withLockUnchecked(\.self) else { return false }
        return xcfManager.isHapticEnabled()
    }
    
    @discardableResult
    public func setHapticEnabled(_ enabled: Bool) -> Bool {
        guard let xcfManager = protectedHapticManager.withLockUnchecked(\.self) else { return false }
        return xcfManager.setHapticEnabled(enabled)
    }
    
    @discardableResult
    public func triggerRawHaptic(actuationID: Int32, unknown1: UInt32, unknown2: Float, unknown3: Float, deviceID: String? = nil) -> Bool {
        guard let xcfManager = protectedHapticManager.withLockUnchecked(\.self) else { return false }
        return xcfManager.triggerRawHaptic(actuationID, unknown1: unknown1, unknown2: unknown2, unknown3: unknown3, deviceID: deviceID)
    }

    @discardableResult
    public func playHapticFeedback(strength: Double, deviceID: String? = nil) -> Bool {
        let clampedStrength = min(max(strength, 0.0), 1.0)
        guard clampedStrength > 0 else {
            return false
        }
        let actuationStep = Int(max(0, min(5, Int(round(clampedStrength * 5.0)))))
        let actuationID = Int32(1 + actuationStep) // falls in 1..6
        let sharpness = Float(10.0 + (clampedStrength * 20.0))
        return triggerRawHaptic(actuationID: actuationID, unknown1: 0, unknown2: sharpness, unknown3: 0, deviceID: deviceID)
    }

    public func deviceIndex(for deviceID: String) -> Int? {
        guard let parsedID = UInt64(deviceID) else { return nil }
        return resolveDeviceIndex(for: parsedID)
    }

    public func deviceIndex(for deviceIDNumeric: UInt64) -> Int? {
        guard deviceIDNumeric > 0 else { return nil }
        return resolveDeviceIndex(for: deviceIDNumeric)
    }

    private func handleRawFrame(
        touches: UnsafePointer<MTTouch>?,
        count: Int,
        timestamp: TimeInterval,
        frame: Int,
        deviceID: UInt64
    ) {
#if DEBUG
        if Thread.isMainThread {
            assertionFailure("OpenMT raw callback is running on the main thread; avoid UI access and move UI work to the main actor.")
        }
        let signpostState = signposter.beginInterval("OpenMTRawFrame")
        defer { signposter.endInterval("OpenMTRawFrame", signpostState) }
#endif
        let deviceIndex = resolveDeviceIndex(for: deviceID)
        let deviceIDString = deviceIDString(for: deviceID)
        guard let touches, count > 0 else {
            enqueueRawTouchFrame(
                OMSRawTouchFrame(
                    deviceID: deviceIDString,
                    deviceIDNumeric: deviceID,
                    deviceIndex: deviceIndex,
                    timestamp: timestamp,
                    buffer: nil,
                    releaseHandler: nil
                )
            )
            return
        }
        let buffer = takeBuffer(capacity: count)
        buffer.write(from: touches, count: count)
        let rawFrame = OMSRawTouchFrame(
            deviceID: deviceIDString,
            deviceIDNumeric: deviceID,
            deviceIndex: deviceIndex,
            timestamp: timestamp,
            buffer: buffer,
            releaseHandler: { [rawBufferPool] buffer in
                buffer.reset()
                rawBufferPool.withLockUnchecked { pool in
                    pool.append(buffer)
                    return ()
                }
            }
        )
        enqueueRawTouchFrame(rawFrame)
    }

    private func enqueueRawTouchFrame(_ frame: OMSRawTouchFrame) {
        enum EnqueueResult {
            case scheduled
            case queued
            case dropped
        }

        let result = rawDeliveryLock.withLockUnchecked { state -> EnqueueResult in
            guard state.count < state.slots.count else {
                return .dropped
            }
            state.slots[state.writeIndex] = frame
            state.writeIndex = (state.writeIndex + 1) % state.slots.count
            state.count += 1
            guard !state.drainScheduled else {
                return .queued
            }
            state.drainScheduled = true
            return .scheduled
        }

        switch result {
        case .scheduled:
            rawDeliveryQueue.async { [weak self] in
                self?.drainRawFrames()
            }
        case .queued:
            return
        case .dropped:
            frame.release()
        }
    }

    private func drainRawFrames() {
        while true {
            let next = rawDeliveryLock.withLockUnchecked { state -> OMSRawTouchFrame? in
                guard state.count > 0 else {
                    state.drainScheduled = false
                    return nil
                }
                let frame = state.slots[state.readIndex]
                state.slots[state.readIndex] = nil
                state.readIndex = (state.readIndex + 1) % state.slots.count
                state.count -= 1
                return frame
            }
            guard let next else { return }
            emitRawTouchFrame(next)
        }
    }

    private func emitRawTouchFrame(_ frame: OMSRawTouchFrame) {
        if let sink = rawFrameSink.withLockUnchecked({ $0.value }) {
            sink.handleRawTouchFrame(frame)
            return
        }
        let handler = rawFrameHandler.withLockUnchecked { $0 }
        let continuations = rawContinuationStore.withLockUnchecked { $0.list }
        if let handler {
            handler(frame)
        }
        for continuation in continuations {
            _ = continuation.yield(frame)
        }
        if handler == nil, continuations.isEmpty {
            frame.release()
        }
    }

    private func resolveDeviceIndex(for deviceID: UInt64) -> Int {
        protectedDeviceIndexStore.withLockUnchecked { store in
            store.index(for: deviceID)
        }
    }

    private func deviceIDString(for deviceID: UInt64) -> String {
        guard deviceID > 0 else { return "Unknown" }
        return deviceIDStringCache.withLockUnchecked { cache in
            if let cached = cache[deviceID] {
                return cached
            }
            let value = String(deviceID)
            cache[deviceID] = value
            return value
        }
    }

    private func takeBuffer(capacity: Int) -> RawTouchBuffer {
        rawBufferPool.withLockUnchecked { pool in
            if let index = pool.lastIndex(where: { $0.capacity >= capacity }) {
                let buffer = pool.remove(at: index)
                buffer.reset()
                return buffer
            }
            return RawTouchBuffer(capacity: max(8, capacity))
        }
    }

    public static func buildTouchData(into buffer: inout [OMSTouchData], from frame: OMSRawTouchFrame) {
        buffer.removeAll(keepingCapacity: true)
        let formattedTimestamp = shared.protectedTimestampEnabled.withLockUnchecked(\.self)
            ? String(format: "%.5f", frame.timestamp)
            : nil
        let deviceID = frame.deviceID
        let deviceIndex = frame.deviceIndex
        let touches = frame.touches
        guard !touches.isEmpty else { return }
        buffer.reserveCapacity(touches.count)
        for touch in touches {
            buffer.append(OMSTouchData(
                deviceID: deviceID,
                deviceIndex: deviceIndex,
                id: touch.id,
                position: OMSPosition(x: touch.posX, y: touch.posY),
                total: touch.total,
                pressure: touch.pressure,
                axis: OMSAxis(major: touch.majorAxis, minor: touch.minorAxis),
                angle: touch.angle,
                density: touch.density,
                state: touch.state,
                timestamp: frame.timestamp,
                formattedTimestamp: formattedTimestamp
            ))
        }
    }

    public static func buildTouchData(from frame: OMSRawTouchFrame) -> [OMSTouchData] {
        var data: [OMSTouchData] = []
        buildTouchData(into: &data, from: frame)
        return data
    }
}

private struct DeviceIndexStore: Sendable {
    private var id0: UInt64?
    private var id1: UInt64?
    private var last0: UInt64 = 0
    private var last1: UInt64 = 0
    private var counter: UInt64 = 0

    mutating func index(for deviceID: UInt64) -> Int {
        if id0 == deviceID {
            last0 = tick()
            return 0
        }
        if id1 == deviceID {
            last1 = tick()
            return 1
        }
        let current = tick()
        if id0 == nil {
            id0 = deviceID
            last0 = current
            return 0
        }
        if id1 == nil {
            id1 = deviceID
            last1 = current
            return 1
        }
        if last0 <= last1 {
            id0 = deviceID
            last0 = current
            return 0
        }
        id1 = deviceID
        last1 = current
        return 1
    }

    private mutating func tick() -> UInt64 {
        counter &+= 1
        return counter
    }
}

public struct OMSRawTouch: Codable, Sendable {
    public let id: Int32
    public let posX: Float
    public let posY: Float
    public let total: Float
    public let pressure: Float
    public let majorAxis: Float
    public let minorAxis: Float
    public let angle: Float
    public let density: Float
    public let state: OMSState

    public init(
        id: Int32,
        posX: Float,
        posY: Float,
        total: Float,
        pressure: Float,
        majorAxis: Float,
        minorAxis: Float,
        angle: Float,
        density: Float,
        state: OMSState
    ) {
        self.id = id
        self.posX = posX
        self.posY = posY
        self.total = total
        self.pressure = pressure
        self.majorAxis = majorAxis
        self.minorAxis = minorAxis
        self.angle = angle
        self.density = density
        self.state = state
    }
}

public final class OMSRawTouchFrame: @unchecked Sendable {
    public let deviceID: String
    public let deviceIDNumeric: UInt64
    public let deviceIndex: Int
    public let timestamp: TimeInterval
    public var sequence: UInt64 = 0
    private var buffer: RawTouchBuffer?
    private let releaseHandler: ((RawTouchBuffer) -> Void)?

    public var touches: OMSRawTouchBufferView {
        buffer?.view ?? .empty
    }

    fileprivate init(
        deviceID: String,
        deviceIDNumeric: UInt64,
        deviceIndex: Int,
        timestamp: TimeInterval,
        buffer: RawTouchBuffer?,
        releaseHandler: ((RawTouchBuffer) -> Void)?
    ) {
        self.deviceID = deviceID
        self.deviceIDNumeric = deviceIDNumeric
        self.deviceIndex = deviceIndex
        self.timestamp = timestamp
        self.buffer = buffer
        self.releaseHandler = releaseHandler
    }

    public func release() {
        guard let buffer else { return }
        self.buffer = nil
        releaseHandler?(buffer)
    }

    deinit {
        release()
    }
}

private final class RawTouchBuffer {
    let capacity: Int
    private let storage: UnsafeMutablePointer<OMSRawTouch>
    private(set) var count: Int = 0

    var view: OMSRawTouchBufferView {
        OMSRawTouchBufferView(baseAddress: UnsafePointer(storage), count: count)
    }

    init(capacity: Int) {
        self.capacity = capacity
        storage = UnsafeMutablePointer<OMSRawTouch>.allocate(capacity: capacity)
    }

    deinit {
        reset()
        storage.deallocate()
    }

    func reset() {
        guard count > 0 else { return }
        storage.deinitialize(count: count)
        count = 0
    }

    func write(from rawTouches: UnsafePointer<MTTouch>, count: Int) {
        precondition(count <= capacity)
        reset()
        for index in 0..<count {
            let touch = rawTouches[index]
            let state = OMSState(OpenMTState(rawValue: UInt(touch.state)) ?? .notTouching) ?? .notTouching
            storage.advanced(by: index).initialize(to: OMSRawTouch(
                id: Int32(touch.identifier),
                posX: touch.normalizedPosition.position.x,
                posY: touch.normalizedPosition.position.y,
                total: touch.total,
                pressure: touch.pressure,
                majorAxis: touch.majorAxis,
                minorAxis: touch.minorAxis,
                angle: touch.angle,
                density: touch.density,
                state: state
            ))
        }
        self.count = count
    }
}
